#!/usr/bin/env python3
"""Verify explicit path creation, independent paint state and exact old source."""

import argparse
from copy import deepcopy
import hashlib
import importlib
import json
import math
from pathlib import Path
import re
import subprocess
import sys

from corpus_support import REVISION
from verify_native_direct_shapes import normalized
from verify_native_group_creation import destination
from verify_native_layers import verified_inventory
from verify_native_path_group_movement import PAINT, paints
from verify_native_path_lifecycle import BOUNDS, patch
from verify_native_reference_resources import pinned_program
from verify_native_shape_lifecycle import inventory
from verify_native_shape_removal import COLORS, SCALARS, scalar_value
from verify_native_structure import parsed
from verify_native_subtree_copy import input_state, key
from verify_native_subtree_movement import topology, tree

SYNTHETIC = {
    'synthetic-empty': '8800079b1f59078c271118e374fe51ec65c9c99662040f05fa06aa81a4698c7d',
    'synthetic-groups': 'fd6a70d4c7ae0217c9189586f0b2128dc649cac2788edca4d650b999e9e0b237',
    'synthetic-mixed': '669f1e8413a92063f60302b9f572017172352a86c47c72444aba05d0cfe23eee',
    'synthetic-unknown': '3ed03c468286ed2f9d641de0a36cf3a9e387977b1dc2e48f493d7c50c2cc2307',
}


def requests():
    """Pin each parent, process color, geometry and paint request before inspection."""
    result = {}
    for name in ('simple_shapes.ai', 'simple_shapes_cc.ai', 'layers_and_sublayers.ai'):
        for target in ('root', 'layer'):
            result[name, target] = target, None, 'rgb', True, True, True, True, False
    result['layers_and_sublayers.ai', 'group'] = 'group', None, 'rgb', True, True, True, True, False
    for space in ('gray', 'rgb', 'cmyk'):
        result['synthetic-empty', space] = 'root', None, space, True, True, True, True, False
    for variant, closed, counted, filled, stroked in (
        ('unpainted', True, True, False, False), ('fill', True, True, True, False),
        ('stroke', True, True, False, True), ('uncounted-open', False, False, True, True),
    ):
        result['synthetic-empty', variant] = 'root', None, 'rgb', closed, counted, filled, stroked, False
    for anchor in ('Parent', 'Empty'):
        result['synthetic-groups', anchor.lower()] = 'group', anchor, 'rgb', True, True, True, True, False
    result['synthetic-mixed', 'parent'] = 'group', 'outer_0', 'rgb', True, True, True, True, False
    result['synthetic-unknown', 'rejected'] = 'group', None, 'rgb', True, True, True, True, True
    return result


def expected_path(row):
    """Describe the independently requested triangle and explicit consumed state."""
    state = {name: (name, (value,)) for name, value in dict(A=1, Xw=0, Ap=0, D=0, XR=1).items()}
    channels = dict(gray=(0.4,), rgb=(0.2, 0.4, 0.6), cmyk=(0.1, 0.2, 0.3, 0.4))[row['space']]
    if row['filled'] or row['stroked']:
        state['Xy'] = 'Xy', (0, 0.7, 0, 0, 0)
    if row['filled']:
        state.update(O=('O', (1,)), fill=(dict(gray='g', rgb='Xa', cmyk='k')[row['space']], channels))
    if row['stroked']:
        state.update({name: (name, (value,)) for name, value in dict(R=1, w=2, J=1, j=2, M=4).items()})
        state.update(stroke=(dict(gray='G', rgb='XA', cmyk='K')[row['space']], channels[::-1]), d=('d', (4, 2), 1))
    geometry = [('m', (10, -10)), ('L', (30, -10)), ('L', (30, -30))]
    if row['closed'] and row['counted']:
        geometry.append(('L', (10, -10)))
    paint = ('B' if row['stroked'] else 'F') if row['filled'] else ('S' if row['stroked'] else 'N')
    geometry.append((paint.lower() if row['closed'] else paint, ()))
    return state, geometry


def exact_bytes(before, after, row):
    """Permit only the new fragment and the union of declared drawing bounds."""
    old_bounds, new_bounds = list(re.finditer(BOUNDS, before)), list(re.finditer(BOUNDS, after))
    assert len(old_bounds) == len(new_bounds) in (1, 2)
    assert b'%%BeginDocument' not in before
    edits = []
    for old, new in zip(old_bounds, new_bounds):
        assert old.end() < before.index(b'%%EndComments') and new.end() < after.index(b'%%EndComments')
        label, coordinates = old.group().split(b':', 1)
        new_label, replacement = new.group().split(b':', 1)
        assert label == new_label
        left, bottom, right, top = map(float, coordinates.split())
        expected = [min(left, 8), min(bottom, -32), max(right, 32), max(top, -8)]
        if label != b'%%HiResBoundingBox':
            expected = [math.floor(expected[0]), math.floor(expected[1]), math.ceil(expected[2]), math.ceil(expected[3])]
        assert list(map(float, replacement.split())) == expected
        edits.append((old.start(), old.end(), new.group()))
    delta = sum(len(value) - (end - start) for start, end, value in edits)
    first = row['position'] + delta
    length = len(after) - len(before) - delta
    assert length > 0 and row['inserted'] == [first, first + length]
    fragment = after[first:first + length]
    assert patch(before, [*edits, (row['position'], row['position'], fragment)]) == after
    return parsed(fragment)


def verify(inkai, source, target, row):
    """Require an ordinary appended path, source-backed replay and unchanged owners."""
    before, after = source.read_bytes(), target.read_bytes()
    original = inventory(inkai, source, row['before']['pairs'])
    changed = inventory(inkai, target, row['after']['pairs'])
    verified_inventory(inkai, source, row['before']['layers'])
    verified_inventory(inkai, target, row['after']['layers'])
    items, nodes = tree(original, list(range(len(row['before']['pairs']))))
    parent = destination(before, items, nodes, row)
    boundary = nodes[parent]['last']
    fragment = exact_bytes(before, after, row)
    start = next(index for index, item in enumerate(fragment) if getattr(item, 'command', None) == 'm')
    end = next(index for index, item in enumerate(fragment) if getattr(item, 'command', None) in PAINT) + 1
    state, geometry = expected_path(row)
    assert [scalar_value(item) for item in fragment[start:end]] == geometry
    assert not any(item.is_pseudo_comment for item in fragment[:end])
    assert normalized(parsed(after[slice(*row['geometry'])])) == normalized(fragment[start:end])
    assert fragment[end] == {'_type': 'ArtDictionary', 'AI10_ArtUID': 'Created', 'AIArtName': 'New (path)'}
    prefix = fragment[:start]
    if row['counted']:
        assert prefix[-1].command == 'As' and prefix[-1].tokens == [b'3']
        prefix = prefix[:-1]
    assert len(prefix) == len(state) and all(item.command in SCALARS | COLORS for item in prefix)
    assert {key(item.command): scalar_value(item) for item in prefix} == state
    for command in fragment[end + 1:]:
        assert command.command in SCALARS | COLORS
        incoming = input_state(original, items, boundary, command.is_pseudo_comment)
        assert incoming.get(key(command.command)) == scalar_value(command), (row['result'], 'Invented outgoing state', command.command)
    expected = deepcopy(nodes)
    expected[parent]['children'].append(('path', (row['filled'] or row['stroked'], normalized(fragment[start:end]))))
    changed_items, actual = tree(changed, list(range(len(row['after']['pairs']))))
    assert topology(actual) == topology(expected)
    metadata = [index for index, item in enumerate(changed_items) if isinstance(item, dict) and item.get('AI10_ArtUID') == 'Created']
    assert len(metadata) == 1
    new_start = metadata[0] - len(geometry)
    for private in (False, True):
        observations = paints(changed, changed_items, private)
        assert [value for index, value in observations if index == new_start] == [(normalized(fragment[start:end]), state)]
        assert [value for index, value in observations if index != new_start] == [value for _, value in paints(original, items, private)], (row['result'], private, 'Changed old paint state')
    assert len(row['before']['pairs']) == len(row['after']['pairs'])
    for old, new in zip(row['before']['pairs'], row['after']['pairs']):
        assert before[old['start']:old['end']] == after[new['start']:new['end']]


def main():
    """Bind all transactions to pinned programs and an unmodified independent reader."""
    if not __debug__:
        raise RuntimeError('Run verification without assertion stripping')
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--inkai-source', required=True, type=Path)
    parser.add_argument('--output', default=Path('test/corpus/output/path-creation'), type=Path)
    args = parser.parse_args()
    assert subprocess.check_output(['git', '-C', str(args.inkai_source), 'rev-parse', 'HEAD'], text=True).strip() == REVISION
    assert not subprocess.check_output(['git', '-C', str(args.inkai_source), 'status', '--porcelain', '--untracked-files=no'], text=True).strip()
    sys.path.insert(0, str(args.inkai_source.resolve()))
    inkai = importlib.import_module('inkai')
    expected, checked = requests(), []
    manifest = {entry['file']: entry for entry in json.loads(Path('test/corpus/manifest.json').read_text())['files']}
    programs = {name: pinned_program(name, manifest) for name, _ in expected if not name.startswith('synthetic')}
    rows = json.loads((args.output / 'report.json').read_text())
    assert len(rows) == len(expected) == 18 and {(row['source'], row['variant']) for row in rows} == expected.keys()
    for row in rows:
        name, variant = row['source'], row['variant']
        assert tuple(row[key] for key in ('target', 'anchor', 'space', 'closed', 'counted', 'filled', 'stroked', 'rejected')) == expected[name, variant]
        assert row['original'] == f'{name}.original.ps' and row['result'] == f'{name}.{variant}.ps'
        source, target = args.output / row['original'], args.output / row['result']
        if name in SYNTHETIC:
            assert hashlib.sha256(source.read_bytes()).hexdigest() == SYNTHETIC[name]
        else:
            assert source.read_bytes() == programs[name]
        if row['rejected']:
            assert 'unresolved native style state: fill' in row['issue']
            assert source.read_bytes() == target.read_bytes() and row['before'] == row['after'] and row['geometry'] is None
        else:
            assert row['issue'] is None
            verify(inkai, source, target, row)
        checked.append(row['result'])
        print(row['result'], 'passed', flush=True)
    (args.output / 'independent-report.json').write_text(json.dumps(dict(oracleRevision=REVISION, transactions=checked, realCreations=7, syntheticCreations=10, refusals=1), indent=2) + '\n')


if __name__ == '__main__':
    main()
