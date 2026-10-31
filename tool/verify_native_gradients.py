#!/usr/bin/env python3
"""Verify native gradient colors, fallback stops, ramps and edited CC rendering."""

import argparse
import importlib
import json
import math
import re
import subprocess
import sys
from pathlib import Path

REVISION = '1a5f42a0b0407fc869e032420570682048810108'


def gradient_instances(document):
    """Walk the oracle's setup, styles, nested art and printable body in order."""
    from inkai.parser.consts import Section
    from inkai.parser.hierarchy_objects import HierarchyObject
    from inkai.parser.operators import Operator

    def operators(value):
        if isinstance(value, Operator):
            yield value
        elif isinstance(value, Section):
            yield from operators(value.children)
        elif isinstance(value, HierarchyObject):
            # Inspect parsed children without invoking unrelated binary decoders.
            yield from operators(vars(value))
        elif isinstance(value, dict):
            for child in value.values():
                yield from operators(child)
        elif isinstance(value, (list, tuple)):
            for child in value:
                yield from operators(child)

    result = []
    current = None
    for command in operators([document.prolog, document.setup, document.trailer]):
        if command.command == 'Bb':
            assert current is None
            current = []
        if current is not None:
            current.append(command)
        if command.command == 'BB':
            assert current is not None
            result.append(current)
            current = None
    assert current is None
    return result


def verify_geometry(before, after, target, radial, previous, positions):
    """Check strip coverage and fixed exterior edges from independent operators."""
    original = gradient_instances(before)
    changed = gradient_instances(after)
    assert len(original) == len(changed)
    updated = 0

    def matrices(commands, operator):
        return [[float(value) for value in command.tokens] for command in commands if command.command == operator]

    def close(first, second):
        assert len(first) == len(second)
        assert all(math.isclose(a, b, rel_tol=1e-10, abs_tol=1e-6) for a, b in zip(first, second)), (first, second)

    for first, second in zip(original, changed):
        geometry = next(command for command in first if command.command == 'Bg')
        strips = matrices(first, 'Bm')
        if geometry.name != target or radial or not strips:
            assert repr(first) == repr(second), geometry.name
            continue
        assert repr([command for command in first if command.command not in {'Bm', 'Bc'}]) == repr([command for command in second if command.command not in {'Bm', 'Bc'}])
        whole = matrices(first, 'Xm')
        if whole:
            axis = whole[0]
        else:
            span = previous[1] - previous[0]
            a, b, c, d, x, y = strips[0]
            axis = [a / span, b / span, c, d, x - previous[0] * a / span, y - previous[0] * b / span]
        rewritten = matrices(second, 'Bm')
        assert len(rewritten) == len(positions) - 1
        for matrix, start, end in zip(rewritten, positions, positions[1:]):
            close(matrix[:2], [(end - start) * value for value in axis[:2]])
            close(matrix[2:4], strips[0][2:4])
            close(matrix[4:], [axis[4 + index] + start * axis[index] for index in range(2)])
        caps_before, caps_after = matrices(first, 'Bc'), matrices(second, 'Bc')
        assert len(caps_before) == len(caps_after) == 2
        for index, (old, new) in enumerate(zip(caps_before, caps_after)):
            close(old[2:4], new[2:4])
            exterior = [new[4 + component] + (new[component] if index else 0) for component in range(2)]
            close(exterior, [old[4 + component] + (old[component] if index else 0) for component in range(2)])
            interior = [new[4 + component] + (0 if index else new[component]) for component in range(2)]
            close(interior, [axis[4 + component] + positions[-1 if index else 0] * axis[component] for component in range(2)])
        updated += 1
    return {'instances': len(original), 'updatedLinearCaches': updated}


def without_printing_matrices(body):
    """Compare every other body line exactly, tolerating rewritten matrix breaks."""
    return [line for line in body.splitlines() if line.strip() not in {b'', b'%_'} and not re.fullmatch(rb'(?:%_)?[\d.eE+\- \t]+ (?:Bm|Bc)', line)]


def stops(section, stop_type, command):
    """Extract independent stop values without merging lower-precision fallbacks."""
    result = []
    for item in section.children:
        if not isinstance(item, stop_type) or item.command != command:
            continue
        opacity = item.color_style.value == 6
        result.append({
            'style': item.subtype.value if opacity else item.color_style.value,
            'components': item.gray or item.cmyk + item.rgb,
            'name': item.name or None,
            'tint': item.tint if item.name else None,
            'position': item.ramp_point,
            'midpoint': item.mid_point,
            'opacity': item.opacity,
            'hasOpacity': opacity,
        })
    return result


def ramps(section, ramp_type):
    """Decode independently tokenized Br payloads, including constant channels."""
    result = []
    for item in section.children:
        if not isinstance(item, ramp_type):
            continue
        fields = re.findall(rb'<[\da-fA-F\s]*>|[^\s<>]+', b' '.join(item.tokens))
        channels = []
        for field in fields[:-1]:
            channels.append(list(bytes.fromhex(field[1:-1].decode())) if field.startswith(b'<') else float(field))
        result.append({'kind': int(fields[-1]), 'channels': channels})
    return result


def verify_render(inkai, original, changed, output, count):
    """Compare against the original SVG with only explicit expected stops changed."""
    from lxml import etree
    from PIL import Image, ImageChops, ImageStat

    before = etree.fromstring(inkai.to_svg(str(original)))
    after = etree.fromstring(inkai.to_svg(str(changed)))
    ns = {'s': 'http://www.w3.org/2000/svg'}
    expected = before.xpath('//s:linearGradient|//s:radialGradient', namespaces=ns)
    actual = after.xpath('//s:linearGradient|//s:radialGradient', namespaces=ns)
    assert len(expected) == len(actual) == count
    for first, second in zip(expected, actual):
        # Resource IDs are newly allocated by the reference converter.
        assert {k: v for k, v in first.attrib.items() if k != 'id'} == {k: v for k, v in second.attrib.items() if k != 'id'}
        for child in list(first):
            first.remove(child)
        for offset, color, opacity in [('0', '#ff0000', '1'), ('0.4', '#00ff00', '0.4'), ('1', '#0000ff', '1')]:
            child = etree.SubElement(first, '{http://www.w3.org/2000/svg}stop')
            child.set('offset', offset)
            child.set('style', f'stop-color:{color};stop-opacity:{opacity}')
    images = []
    for label, tree in [('expected', before), ('actual', after)]:
        svg = output / f'{original.name}.{label}.svg'
        png = output / f'{original.name}.{label}.png'
        svg.write_bytes(etree.tostring(tree))
        subprocess.run(['inkscape', str(svg), '--export-type=png', '--export-width=1200', f'--export-filename={png}'], check=True)
        with Image.open(png) as image:
            images.append(image.convert('RGBA'))
    assert images[0].size == images[1].size
    difference = ImageChops.difference(*images)
    mean = max(ImageStat.Stat(difference).mean)
    assert mean < 0.01, f'Gradient rendering differs by {mean} mean channel levels'
    difference.save(output / f'{original.name}.difference.png')
    return mean


def main():
    """Require the pinned oracle and complete corpus before accepting the edits."""
    if not __debug__:
        raise RuntimeError('Run verification without assertion stripping')
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--inkai-source', required=True, type=Path)
    parser.add_argument('--output', default=Path('test/corpus/output/gradients'), type=Path)
    args = parser.parse_args()
    assert subprocess.check_output(['git', '-C', str(args.inkai_source), 'rev-parse', 'HEAD'], text=True).strip() == REVISION
    assert not subprocess.check_output(['git', '-C', str(args.inkai_source), 'status', '--porcelain', '--untracked-files=no'], text=True).strip()
    sys.path.insert(0, str(args.inkai_source.resolve()))
    inkai = importlib.import_module('inkai')
    gradient = importlib.import_module('inkai.parser.gradient')
    report = json.loads((args.output / 'report.json').read_text())
    assert len(report) == 37 and all(entry['status'] == 'passed' for entry in report)
    total_definitions = total_stops = total_ramps = edits = 0
    render_results = []
    geometry_results = []
    for entry in report:
        name = entry['file']
        original = args.output / f'{name}.original.ps'
        before = inkai.parse(str(original))
        definitions = before.setup.gradients
        assert list(definitions) == [item['name'] for item in entry['definitions']]
        for item in entry['definitions']:
            source = definitions[item['name']]
            primary = stops(source, gradient.Bs, 'Bs') or stops(source, gradient.Bs, '%_Bs') or stops(source, gradient.Bs, '%_BS')
            assert primary == item['stops'], (name, item['name'], 'stops')
            assert stops(source, gradient.Bs, '%_BS') == item['fallback'], (name, item['name'], 'fallback')
            assert ramps(source, gradient.Br) == item['ramps'], (name, item['name'], 'ramps')
            assert source.definition.type == int(item['radial'])
            total_definitions += 1
            total_stops += len(primary)
            total_ramps += len(item['ramps'])
        if not definitions:
            continue
        changed = args.output / f'{name}.edited.ps'
        after = inkai.parse(str(changed))
        rewritten = after.setup.gradients
        assert definitions.keys() == rewritten.keys()
        target = next(iter(definitions))
        for key in definitions:
            if key != target:
                assert repr(definitions[key].children) == repr(rewritten[key].children), (name, key)
        new = rewritten[target]
        assert new.definition.nColors == 3 and new.definition.type == definitions[target].definition.type
        actual = stops(new, gradient.Bs, 'Bs')
        assert actual == stops(new, gradient.Bs, '%_BS')
        radial = new.definition.type == 1
        assert [item['position'] for item in actual] == ([0, 40, 100] if radial else [100, 40, 0])
        for primary, stop in zip([0, 1, 2] if radial else [2, 1, 0], actual):
            assert stop['components'] == [0 if channel == primary else 1 for channel in range(3)] + [0] + [1 if channel == primary else 0 for channel in range(3)]
            assert stop['opacity'] == (0.4 if primary == 1 else 1)
            assert stop['midpoint'] == 50 and stop['style'] == 2 and stop['hasOpacity']
        new_ramps = ramps(new, gradient.Br)
        assert len(new_ramps) == 2
        colors = [stop['components'] for stop in sorted(actual, key=lambda stop: stop['position'])]
        for interval, ramp in enumerate(new_ramps):
            assert ramp['kind'] == 4 and len(ramp['channels']) == 7
            for channel, samples in enumerate(ramp['channels']):
                assert samples == [int(colors[interval][channel] * (255 - sample) + colors[interval + 1][channel] * sample) for sample in range(256)]
        first_body = original.read_bytes().partition(b'%%EndSetup')
        second_body = changed.read_bytes().partition(b'%%EndSetup')
        assert first_body[1] and second_body[1] and without_printing_matrices(first_body[2]) == without_printing_matrices(second_body[2]), 'Unrelated drawing bytes changed'
        old_stops = stops(definitions[target], gradient.Bs, 'Bs') or stops(definitions[target], gradient.Bs, '%_Bs')
        geometry_results.append({'file': name, **verify_geometry(before, after, target, radial, sorted(stop['position'] / 100 for stop in old_stops), [0, 0.4, 1])})
        edits += 1
        if name in {'gradient_linear.ai', 'gradient_radial.ai'}:
            count = 15 if name == 'gradient_linear.ai' else 9
            # These fixtures use the first resource for every gradient instance.
            assert target == 'Unnamed gradient 6'
            mean = verify_render(inkai, original, changed, args.output, count)
            render_results.append({'file': name, 'instances': count, 'meanChannelDifference': mean})
    assert (total_definitions, total_stops, total_ramps, edits) == (378, 1103, 725, 23)
    assert len(render_results) == 2
    colors = json.loads((args.output / 'colors.json').read_text())
    assert len(colors) == 7
    for variant in colors:
        after = inkai.parse(str(args.output / variant['file']))
        section = next(iter(after.setup.gradients.values()))
        assert stops(section, gradient.Bs, 'Bs')[-1] == variant['stop'], variant['file']
        assert stops(section, gradient.Bs, '%_BS')[-1] == variant['stop'], variant['file']
        before = inkai.parse(str(args.output / 'gradient_linear.ai.original.ps'))
        geometry_results.append({'file': variant['file'], **verify_geometry(before, after, 'Unnamed gradient 6', False, [0, 1], [0.1, 1])})
    variants = json.loads((args.output / 'geometry.json').read_text())
    assert len(variants) == 4
    for variant in variants:
        before = inkai.parse(str(args.output / 'circle.ai.original.ps'))
        after = inkai.parse(str(args.output / variant['file']))
        result = verify_geometry(before, after, variant['name'], False, variant['previous'], [0.1, 0.4, 0.9])
        assert result['updatedLinearCaches'] > 0, variant['file']
        geometry_results.append({'file': variant['file'], **result})
    assert sum(result['updatedLinearCaches'] for result in geometry_results) == 139
    assert sum(result['instances'] for result in geometry_results) == 1848
    result = {'oracleRevision': REVISION, 'definitions': total_definitions, 'stops': total_stops, 'ramps': total_ramps, 'editedFiles': edits, 'colorVariants': len(colors), 'renders': render_results, 'geometry': geometry_results}
    (args.output / 'oracle-report.json').write_text(json.dumps(result, indent=2) + '\n')
    print(f'Native gradients: {total_definitions} definitions, {total_stops} stops, {total_ramps} ramps, {edits} edits and 2 render checks passed')


if __name__ == '__main__':
    main()
