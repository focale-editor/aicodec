#!/usr/bin/env python3
"""Verify selected native gradient copies, subsequent edits and Adobe PDF views."""

import argparse
import copy
import hashlib
import importlib
import json
import math
import re
import subprocess
import sys
from pathlib import Path

from lxml import etree
from PIL import Image, ImageChops, ImageStat
from pypdf import PdfReader, PdfWriter
from pypdf.generic import ArrayObject, ContentStream, DictionaryObject, FloatObject, NameObject, NumberObject

from verify_live_shapes import walk_body
from verify_native_gradients import stops, ramps
from verify_native_pdf import REVISION, compare, native_programs, render_pdf
from verify_live_shape_rotation import close


def style_tree(before, after, row, changed=False):
    """Require original style semantics except the selected name and focal note."""
    if hasattr(before, 'command'):
        assert before.command == after.command
        if before.command == 'Bg' and changed and before.name == row['sourceName']:
            assert after.name == row['name']
            assert before.tokens[:1] == after.tokens[:1] and before.tokens[2:] == after.tokens[2:]
        elif before.command == 'Bh' and changed and row['variant'] == 'focus':
            close(after.tokens, (0, 0, 37, 0.375))
        else:
            assert before.tokens == after.tokens
    elif hasattr(before, 'asdict'):
        style_tree(before.asdict(), after.asdict(), row, changed)
    elif isinstance(before, dict):
        assert before.keys() == after.keys()
        for key, value in before.items():
            style_tree(value, after[key], row, changed)
    elif isinstance(before, (list, tuple)):
        assert len(before) == len(after)
        for first, second in zip(before, after):
            style_tree(first, second, row, changed)
    else:
        assert before == after, (before, after)


def verify_native(inkai, original, changed, row):
    """Inspect all old definitions/styles and every selected or unselected object."""
    from inkai.parser.gradient import Bs, Br
    before, after = inkai.parse(str(original)), inkai.parse(str(changed))
    old, new = before.setup.gradients, after.setup.gradients
    assert set(new) == set(old) | {row['name']}
    for name in old:
        assert repr(old[name].children) == repr(new[name].children), name
    source, isolated = old[row['sourceName']], new[row['name']]
    assert source.type == isolated.type
    if row['variant'] != 'colors':
        assert repr(source.children[1:]) == repr(isolated.children[1:])
    else:
        for command in ['Bs', '%_BS']:
            values = sorted(stops(isolated, Bs, command), key=lambda stop: stop['position'])
            assert len(values) == 2
            for value, color, position in zip(values, [0.2, 0.8], [0, 100]):
                assert value['components'] == [color] and value['position'] == position
                assert value['midpoint'] == 50 and value['opacity'] == 1 and value['style'] == 0
        assert ramps(isolated, Br) == [{'kind': 0, 'channels': [[round(51 + 153 * index / 255) for index in range(256)]]}]
    # These pinned files have one printed source bank, followed by 17 swatches.
    counts = lambda path: [int(value) for value in re.findall(rb'(?m)^([0-9]+) Bn\r?$', path.read_bytes())]
    assert counts(original) == [1, 17] and counts(changed) == [2, 17]
    source_styles, target_styles = before.setup.art_styles, after.setup.art_styles
    assert set(source_styles) <= set(target_styles)
    for name in source_styles:
        style_tree(source_styles[name], target_styles[name], row)
    first_items, second_items = list(walk_body(before.trailer)), list(walk_body(after.trailer))
    assert len(first_items) == len(second_items)
    owner = 0
    copies = set()
    instances = 0
    for first, second in zip(first_items, second_items):
        command = getattr(first, 'command', None)
        assert command == getattr(second, 'command', None)
        if command is None:
            assert first == second
            continue
        assert first.is_pseudo_comment == second.is_pseudo_comment
        selected = owner in row['selected']
        if command == 'Bg':
            assert first.name == row['sourceName'] and first.flag == 1 and not first.is_pseudo_comment
            assert second.name == (row['name'] if selected else row['sourceName'])
            assert first.tokens[:1] == second.tokens[:1] and first.tokens[2:] == second.tokens[2:]
            instances += 1
        elif command == 'Bh' and selected and row['variant'] == 'focus':
            following = first_items[first_items.index(first) + 1:]
            imaging = next(item for item in following if getattr(item, 'command', None) == 'Bm')
            a, b, c, d, _, _ = map(float, imaging.tokens)
            x, y = 0.375 * math.cos(math.radians(37)), -0.375 * math.sin(math.radians(37))
            close(second.tokens, (a * x + c * y, b * x + d * y, 37, 0.375))
        elif command == 'XW' and first.integer == 1:
            if selected:
                assert first.stylename != second.stylename
                style_tree(source_styles[first.stylename].Def, target_styles[second.stylename].Def, row, True)
                copies.add(second.stylename)
            else:
                assert first.tokens == second.tokens
            owner += 1
        else:
            assert first.tokens == second.tokens, (owner, command)
    assert owner == instances == row['shapes']
    assert set(target_styles) - set(source_styles) == copies
    return len(copies)


def svg_reference(inkai, original, changed, row, output):
    """Edit only the selected original SVG paint resources, keeping their axes."""
    expected = etree.fromstring(inkai.to_svg(str(original)))
    actual = etree.fromstring(inkai.to_svg(str(changed)))
    tags = {'rect', 'path', 'ellipse', 'circle', 'polygon', 'line'}
    shapes = [node for node in expected.iter() if etree.QName(node).localname in tags]
    assert len(shapes) == row['shapes']
    if row['variant'] == 'colors':
        defs = next(node for node in expected if etree.QName(node).localname == 'defs')
        for index in row['selected']:
            shape = shapes[index]
            style = shape.get('style')
            names = re.findall(r'url\(#([^)]+)\)', style)
            assert names
            for number, name in enumerate(names):
                source = expected.xpath('//*[@id=$name]', name=name)[0]
                assert etree.QName(source).localname in {'linearGradient', 'radialGradient'}
                paint = copy.deepcopy(source)
                isolated = f'OracleSelected{index}_{number}'
                paint.set('id', isolated)
                for child in list(paint):
                    paint.remove(child)
                for offset, color in [('0', '#333333'), ('1', '#cccccc')]:
                    stop = etree.SubElement(paint, '{http://www.w3.org/2000/svg}stop')
                    stop.set('offset', offset)
                    stop.set('style', f'stop-color:{color};stop-opacity:1')
                defs.append(paint)
                style = style.replace(f'url(#{name})', f'url(#{isolated})')
            shape.set('style', style)
    images = []
    for label, tree in [('expected', expected), ('actual', actual)]:
        path = output / f'{changed.stem}.{label}.svg'
        png = path.with_suffix('.png')
        path.write_bytes(etree.tostring(tree))
        subprocess.run(['inkscape', str(path), '--export-type=png', '--export-width=1200', f'--export-filename={png}'], check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        with Image.open(png) as image:
            images.append(image.convert('RGBA'))
    assert images[0].size == images[1].size
    for image in images:
        assert image.getchannel('A').getbbox() and ImageChops.difference(image.convert('RGB'), Image.new('RGB', image.size, 'white')).getbbox()
    difference = ImageChops.difference(*images)
    mean = max(ImageStat.Stat(difference).mean)
    difference.save(output / f'{changed.stem}.svg-difference.png')
    assert mean < 0.01, (changed.name, mean)
    return mean


def reference_pdf(source, target, row):
    """Clone Adobe shadings only at the three selected painting occurrences."""
    writer = PdfWriter()
    writer.clone_document_from_reader(PdfReader(source))
    page = writer.pages[0]
    resources = page['/Resources']['/Shading']
    stream = ContentStream(page['/Contents'], writer)
    count = 0
    for operands, operator in stream.operations:
        if operator != b'sh':
            continue
        if count in row['selected'] and row['variant'] != 'isolated':
            shading = DictionaryObject(resources[operands[0]].get_object())
            if row['variant'] == 'focus':
                assert shading['/ShadingType'] == 3 and list(shading['/Coords'][2:]) == [0, 0, 0, 1]
                shading[NameObject('/Coords')] = ArrayObject([FloatObject(value) for value in (
                    0.375 * math.cos(math.radians(37)), -0.375 * math.sin(math.radians(37)), 0, 0, 0, 1,
                )])
            else:
                # The radial fixture uses Adobe's Black-only DeviceN space:
                # native gray is inverse ink coverage, not screen luminance.
                black = shading['/ColorSpace'] != '/DeviceRGB'
                if black:
                    assert list(shading['/ColorSpace'][:3]) == ['/DeviceN', ['/Black'], '/DeviceCMYK']
                else:
                    shading[NameObject('/ColorSpace')] = NameObject('/DeviceGray')
                shading[NameObject('/Function')] = DictionaryObject({
                    NameObject('/FunctionType'): NumberObject(2),
                    NameObject('/Domain'): ArrayObject([NumberObject(0), NumberObject(1)]),
                    NameObject('/C0'): ArrayObject([FloatObject(0.8 if black else 0.2)]),
                    NameObject('/C1'): ArrayObject([FloatObject(0.2 if black else 0.8)]), NameObject('/N'): NumberObject(1),
                })
            name = NameObject(f'/OracleSelected{count}')
            resources[name] = writer._add_object(shading)
            operands[0] = name
        count += 1
    assert count == row['shapes']
    page[NameObject('/Contents')] = writer._add_object(stream)
    writer.write(target)


def main():
    """Require pinned originals and exact saved native programs for every variant."""
    if not __debug__:
        raise RuntimeError('Run without assertion stripping')
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--inkai-source', type=Path, required=True)
    parser.add_argument('--output', type=Path, default=Path('test/corpus/output/gradient-isolation'))
    args = parser.parse_args()
    assert subprocess.check_output(['git', '-C', str(args.inkai_source), 'rev-parse', 'HEAD'], text=True).strip() == REVISION
    assert not subprocess.check_output(['git', '-C', str(args.inkai_source), 'status', '--porcelain', '--untracked-files=no'], text=True).strip()
    sys.path.insert(0, str(args.inkai_source.resolve()))
    inkai = importlib.import_module('inkai')
    manifest = {row['file']: row for row in json.loads(Path('test/corpus/manifest.json').read_text())['files']}
    rows = json.loads((args.output / 'report.json').read_text())
    assert [(row['file'], row['variant']) for row in rows] == [
        ('gradient_linear.ai', 'isolated'), ('gradient_linear.ai', 'colors'),
        ('gradient_radial.ai', 'isolated'), ('gradient_radial.ai', 'colors'), ('gradient_radial.ai', 'focus'),
    ]
    report = []
    for row in rows:
        name, variant = row['file'], row['variant']
        assert hashlib.sha256(Path('test/corpus/files', name).read_bytes()).hexdigest() == manifest[name]['sha256']
        assert row['selected'] == ([0, 7, 14] if name == 'gradient_linear.ai' else [0, 4, 8])
        original = args.output / f'{name}.original.ps'
        assert native_programs(Path('test/corpus/files', name)) == [original.read_bytes()]
        stem = f'{name}.{variant}'
        changed = args.output / f'{stem}.ps'
        copies = verify_native(inkai, original, changed, row)
        svg_mean = svg_reference(inkai, original, changed, row, args.output) if variant != 'focus' else None
        saved = args.output / f'{stem}.ai'
        assert native_programs(saved) == [changed.read_bytes()]
        reference = args.output / f'{stem}.reference.pdf'
        reference_pdf(Path('test/corpus/files', name), reference, row)
        expected = render_pdf(reference, 1200, 675)
        comparisons = []
        for target in [args.output / f'{stem}.pdf', saved]:
            actual = render_pdf(target, 1200, 675)
            mean = compare(expected, actual, target.with_suffix(f'.{target.suffix[1:]}.difference.png'), 0.1, gradient=True)
            comparisons.append({'file': target.name, 'meanChannelDifference': mean})
        report.append({'file': name, 'variant': variant, 'styleCopies': copies, 'svgMeanChannelDifference': svg_mean, 'pdf': comparisons})
        print(name, variant, 'passed', flush=True)
    (args.output / 'oracle-report.json').write_text(json.dumps(report, indent=2) + '\n')


if __name__ == '__main__':
    main()
