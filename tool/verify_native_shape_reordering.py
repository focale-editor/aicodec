#!/usr/bin/env python3
"""Verify sibling-pair permutations, exact owners and both inherited state streams."""

import argparse
import hashlib
import importlib
import json
from pathlib import Path
import re
import subprocess
import sys

from lxml import etree
from PIL import Image, ImageChops

from corpus_support import REVISION, native_programs, printable_svg
from verify_native_capabilities import body_operators
from verify_native_shape_lifecycle import artwork, body, bundles, inventory, signature
from verify_native_shape_removal import COLORS, SCALARS, scalar_value
from verify_native_structure import parsed

SYNTHETIC = {
    'synthetic-following': '9d24bf78168ad7477b0062e1f9b418d67d8bc950173d7e112bb4016d6ffc5f90',
    'synthetic-panel': 'c7421a9ebfdb0d3fc95ba47002ebead52803ab0e06783dc289dedc769b37f5db',
    'synthetic-reference': 'aa754a5d8f04d84ed8fa4004b200616eaeccbe91c8a437b82c8b05fbf75fcbee',
    'synthetic-unknown': '0365987ecf97b1ac7e9444e8c66103a015a3f54c8464ea10fd7203c55ec68640',
    'synthetic': '737d0ac53aa93ea59ff6351715c0c057b93d3b20aaa6ad3ff13106522f56841a',
}


def requests():
    """Pin every permutation, unchanged transaction and expected refusal."""
    result = {}
    for name, count in [('simple_shapes.ai', 5), ('simple_shapes_cc.ai', 5), ('gradient_linear.ai', 15), ('gradient_radial.ai', 9)]:
        first = int(name != 'gradient_linear.ai')
        result[name, 'adjacent'] = [first + 1, first], False
        result[name, 'ends'] = [count - 1, first], False
        result[name, 'reverse'] = list(range(count - 1, first - 1, -1)), False
        result[name, 'reject-first' if first else 'unchanged'] = ([1, 0], True) if first else ([0, 1], False)
    for variant, order in [('rotate', [2, 0, 1]), ('ends', [2, 0]), ('reverse', [2, 1, 0]), ('unchanged', [0, 1, 2])]:
        result['synthetic', variant] = order, False
    result['synthetic-unknown', 'reverse'] = [1, 0], False
    for name in ('synthetic-panel', 'synthetic-reference', 'synthetic-following'):
        result[name, 'reverse'] = [2, 1, 0], name == 'synthetic-following'
    return result


def permutation(row):
    """Map destination pair slots to original source indices without moving neighbors."""
    order = list(range(len(row['before'])))
    for target, source in zip(sorted(row['order']), row['order']):
        order[target] = source
    return order


def exact_placements(before, after, original, row, order):
    """Require exact moved pairs, literal unselected gaps and only source scalar replay."""
    literals = [item for item in [*body(original.trailer), *body_operators(original.setup)] if getattr(item, 'command', None) in SCALARS | COLORS]
    pieces, position = [], 0
    scalar = rb'(?:%_)?[+\-.\deE \t\[\]]+ (?:' + b'|'.join(key.encode() for key in sorted(SCALARS | COLORS)) + rb')\n'
    for target, source in enumerate(order):
        old, moved = row['before'][target], row['before'][source]
        if target == source:
            continue
        pieces.append(re.escape(before[position:old['start']]))
        pieces.append(rb'(\n(?:' + scalar + rb')*?)')
        pieces.append(re.escape(before[moved['start']:moved['end']]))
        pieces.append(rb'\n((?:' + scalar + rb')*?)')
        position = old['end']
    pieces.append(re.escape(before[position:]))
    match = re.fullmatch(b''.join(pieces), after)
    assert match is not None, (row['result'], 'Changed source outside pair slots or introduced non-scalar replay')
    for replay in match.groups():
        for command in parsed(replay):
            assert command.command in SCALARS | COLORS
            assert any(scalar_value(command) == scalar_value(value) and (command.is_pseudo_comment or not value.is_pseudo_comment) for value in literals)


def flags(document, *, private, opacity):
    """Track native owner flags and synthetic opacity without rendering or default values."""
    state, result, moves = {}, [], []
    keys = {'A', 'Xw', 'Ap', 'D'} | ({'Xy'} if opacity else set())
    for item in body(document.trailer):
        if not hasattr(item, 'command') or item.is_pseudo_comment and not private:
            continue
        if item.command in keys:
            state[item.command] = scalar_value(item)
        elif item.command == 'm':
            moves.append(item)
            result.append((item.is_pseudo_comment, tuple(float(token) for token in item.tokens), dict(state)))
    return moves, result


def retained_state(original, changed, row, order):
    """Reorder complete contour-state blocks while retaining every ordinary neighbor."""
    pairs = bundles(original)
    for private in (False, True):
        moves, values = flags(original, private=private, opacity=row['source'] in SYNTHETIC)
        indices = {id(item): index for index, item in enumerate(moves)}
        starts, blocks = {}, []
        for index, pair in enumerate(pairs):
            positions = [indices[id(item)] for item in pair['items'] if id(item) in indices]
            assert positions == list(range(positions[0], positions[-1] + 1))
            starts[positions[0]] = index
            blocks.append(values[positions[0]:positions[-1] + 1])
        expected, position = [], 0
        while position < len(values):
            if position in starts:
                index = starts[position]
                expected.extend(blocks[order[index]])
                position += len(blocks[index])
            else:
                expected.append(values[position])
                position += 1
        assert expected == flags(changed, private=private, opacity=row['source'] in SYNTHETIC)[1], (row['result'], private, 'Contour state changed')


def views(inkai, source, target, row, order):
    """Compare real native/printing SVG and synthetic printing SVG in the requested order."""
    # The pinned SVG dispatcher ignores lists holding synthetic version branches.
    for mode in (('printing',) if row['source'] in SYNTHETIC else ('native', 'printing')):
        before = etree.fromstring(inkai.to_svg(str(source)) if mode == 'native' else etree.tostring(printable_svg(inkai, source)))
        after = etree.fromstring(inkai.to_svg(str(target)) if mode == 'native' else etree.tostring(printable_svg(inkai, target)))
        old = [signature(item, before) for item in artwork(before)]
        new = [signature(item, after) for item in artwork(after)]
        extra = int(row['source'].startswith('simple_shapes'))
        assert len(old) == len(order) + extra
        expected = [old[index] for index in order] + old[len(order):]
        if expected != new:
            inactive_stroke(before)
            inactive_stroke(after)
            old = [signature(item, before) for item in artwork(before)]
            new = [signature(item, after) for item in artwork(after)]
            assert [old[index] for index in order] + old[len(order):] == new, (row['result'], mode, 'Active geometry, paint, resources or unrelated appearance changed')
            # Also render the original, unnormalized SVG trees. This accepts only
            # inactive stroke metadata differences with identical independent ink.
            before = etree.fromstring(inkai.to_svg(str(source)) if mode == 'native' else etree.tostring(printable_svg(inkai, source)))
            after = etree.fromstring(inkai.to_svg(str(target)) if mode == 'native' else etree.tostring(printable_svg(inkai, target)))
            objects = artwork(before)
            parent = objects[0].getparent()
            for item in objects:
                parent.remove(item)
            for index in order:
                parent.append(objects[index])
            parent.extend(objects[len(order):])
            raster_check(before, after, target.with_suffix('.' + mode))


def inactive_stroke(root):
    """Ignore only leaf stroke attributes when stroke is explicitly disabled and no markers use them."""
    inactive = {'stroke-width', 'stroke-miterlimit', 'stroke-linejoin', 'stroke-linecap', 'stroke-dasharray', 'stroke-dashoffset'}
    shapes = {'path', 'rect', 'circle', 'ellipse', 'line', 'polyline', 'polygon'}
    for node in root.iter():
        if len(node) or etree.QName(node).localname not in shapes:
            continue
        style = dict(part.split(':', 1) for part in node.get('style', '').split(';') if ':' in part)
        if style.get('stroke') != 'none' or any('marker' in key for key in [*style, *node.attrib]):
            continue
        node.set('style', ';'.join(key + ':' + value for key, value in style.items() if key not in inactive))


def raster_check(before, after, base):
    """Require exact independent RGBA pixels when only disabled stroke attributes differ."""
    images = []
    for kind, root in [('expected', before), ('actual', after)]:
        svg = Path(str(base) + '.' + kind + '.svg')
        png = svg.with_suffix('.png')
        svg.write_bytes(etree.tostring(root))
        subprocess.run(['rsvg-convert', '-w', '1024', '-o', str(png), str(svg)], check=True, capture_output=True)
        with Image.open(png) as image:
            images.append(image.convert('RGBA'))
    assert images[0].size == images[1].size
    assert all(channel.getbbox() is None for channel in ImageChops.difference(*images).split()), (str(base), 'Independent rendered pixels changed')
    print(str(base.name), 'inactive stroke attributes, identical librsvg pixels', flush=True)


def verify(inkai, source, target, row):
    """Bind the reported spans to complete independently parsed pairs and saved alternatives."""
    original = inventory(inkai, source, row['before'])
    changed = inventory(inkai, target, row['after'])
    before, after = source.read_bytes(), target.read_bytes()
    order = permutation(row)
    assert len(order) == len(row['after'])
    for target_index, source_index in enumerate(order):
        old, new = row['before'][source_index], row['after'][target_index]
        assert before[old['start']:old['end']] == after[new['start']:new['end']]
    exact_placements(before, after, original, row, order)
    retained_state(original, changed, row, order)
    views(inkai, source, target, row, order)


def main():
    """Require pinned sources, fixed transactions and unchanged independent reader code."""
    if not __debug__:
        raise RuntimeError('Run verification without assertion stripping')
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--inkai-source', required=True, type=Path)
    parser.add_argument('--output', default=Path('test/corpus/output/shape-reordering'), type=Path)
    args = parser.parse_args()
    assert subprocess.check_output(['git', '-C', str(args.inkai_source), 'rev-parse', 'HEAD'], text=True).strip() == REVISION
    assert not subprocess.check_output(['git', '-C', str(args.inkai_source), 'status', '--porcelain', '--untracked-files=no'], text=True).strip()
    sys.path.insert(0, str(args.inkai_source.resolve()))
    inkai = importlib.import_module('inkai')
    manifest = {entry['file']: entry for entry in json.loads(Path('test/corpus/manifest.json').read_text())['files']}
    expected = requests()
    rows = json.loads((args.output / 'report.json').read_text())
    assert len(rows) == len(expected) == 24 and {(row['source'], row['variant']) for row in rows} == expected.keys()
    checked = []
    for row in rows:
        assert (row['order'], row['rejected']) == expected[row['source'], row['variant']]
        assert row['original'] == row['source'] + '.original.ps' and row['result'] == row['source'] + '.' + row['variant'] + '.ps'
        source, target = args.output / row['original'], args.output / row['result']
        before = source.read_bytes()
        if row['source'] in SYNTHETIC:
            assert hashlib.sha256(before).hexdigest() == SYNTHETIC[row['source']]
        else:
            entry = manifest[row['source']]
            path = Path('test/corpus/files', row['source'])
            assert path.stat().st_size == entry['size'] and hashlib.sha256(path.read_bytes()).hexdigest() == entry['sha256']
            assert before in (native_programs(path) if path.read_bytes().startswith(b'%PDF-') else [path.read_bytes()])
        if row['rejected']:
            assert before == target.read_bytes() and row['before'] == row['after']
            assert ('unresolved native style state: fill' if row['source'] in SYNTHETIC else 'unknown inherited printing D') in row['issue']
        else:
            assert row['issue'] is None
            if row['variant'] == 'unchanged':
                assert before == target.read_bytes() and row['before'] == row['after']
            else:
                verify(inkai, source, target, row)
        checked.append(row['result'])
        print(row['result'], 'passed', flush=True)
    (args.output / 'independent-report.json').write_text(json.dumps(dict(oracleRevision=REVISION, transactions=checked, realReorderings=12, syntheticReorderings=6, unchanged=2, refusals=4), indent=2) + '\n')


if __name__ == '__main__':
    main()
