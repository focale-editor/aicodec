#!/usr/bin/env python3
"""Check exact counted-path moves, independent ownership and both saved projections."""

import argparse
from copy import deepcopy
import hashlib
import importlib
import json
from pathlib import Path
import subprocess
import sys

from lxml import etree

from corpus_support import REVISION, printable_svg
from verify_native_direct_shapes import normalized
from verify_native_layers import verified_inventory
from verify_native_reference_resources import pinned_program
from verify_native_shape_lifecycle import body, inventory, signature
from verify_native_shape_reordering import inactive_stroke, raster_check
from verify_native_shape_removal import COLORS, SCALARS
from verify_native_structure import parsed
from verify_native_subtree_copy import input_state
from verify_native_subtree_movement import exact_bytes, inherited_flags, owner, topology, tree
from verify_native_subtree_removal import children

SYNTHETIC = {
    'synthetic-ordinary': '59546a514c3988837da6dac392fa534021e4beb6b3cfa661982e8eb2c0b6ae98',
    'synthetic-counted': '7a09f2fad0b37d1566b3ee01d6730da9c55a8a80cb8979025ccad96bf5db4ed2',
    'synthetic-layers': '6597d1950fbaa28e1032a4807793ad9236b6418ac085145d650ad46b84f741d9',
    'synthetic-mixed': '669f1e8413a92063f60302b9f572017172352a86c47c72444aba05d0cfe23eee',
}
POSITIONS = {
    'simple_shapes.ai': (988486, 976053),
    'simple_shapes_cc.ai': (987970, 975488),
    'circle.ai': (2270585, 2269489),
}
PAINT = {'n', 'N', 'f', 'F', 's', 'S', 'b', 'B'}


def paints(document, items, private):
    """Observe every consumed scalar without the reader SVG dispatcher's color resets."""
    result = []
    for index, item in enumerate(items):
        if getattr(item, 'command', None) != 'm' or item.is_pseudo_comment and not private:
            continue
        end = next(at for at in range(index, len(items)) if getattr(items[at], 'command', None) in PAINT)
        paint = items[end].command
        used = {'A', 'Xw', 'Ap', 'D', 'XR'}
        if paint not in ('n', 'N'):
            used.add('Xy')
        if paint in ('f', 'F', 'b', 'B'):
            used.update(('fill', 'O'))
        if paint in ('s', 'S', 'b', 'B'):
            used.update(('stroke', 'R', 'w', 'd', 'J', 'j', 'M'))
        state = input_state(document, items, index, private)
        result.append((index, (normalized(items[index:end + 1]), {key: state.get(key) for key in used})))
    return result


def requests():
    """Pin selected path indices, target names, inheritance and expected refusals."""
    result = {}
    for name in POSITIONS:
        for variant in ('forward', 'backward'):
            result[name, variant] = 0 if name == 'circle.ai' else 18, 'empty-group', True, variant == 'backward' and name != 'circle.ai'
    for name in ('destination', 'empty', 'source'):
        result['synthetic-ordinary', name] = 0, name, False, False
    result['synthetic-ordinary', 'backward'] = 2, 'source', False, False
    result['synthetic-counted', 'empty'] = 0, 'empty', False, False
    result['synthetic-layers', 'cross'] = 0, 'empty', True, False
    result['synthetic-layers', 'reject-parent'] = 0, 'empty', False, True
    result['synthetic-mixed', 'forward'] = 4, 'empty-group', True, False
    result['synthetic-mixed', 'backward'] = 14, 'outer_0', True, False
    return result


def selection(data, items, nodes, row):
    """Bind a unique complete geometry/count/dictionary owner to a source child."""
    fragment = list(body(parsed(data[slice(*row['span'])])))
    matches = [index for index in range(len(items) - len(fragment) + 1) if normalized(items[index:index + len(fragment)]) == normalized(fragment)]
    assert len(matches) == 1
    first, last = matches[0], matches[0] + len(fragment)
    moves = [index for index, item in enumerate(items) if getattr(item, 'command', None) == 'm']
    start = moves[row['selected']]
    end = next(index for index in range(start, last) if getattr(items[index], 'command', None) in PAINT) + 1
    assert first <= start < end <= last
    geometry = items[start:end]
    assert normalized(parsed(data[slice(*row['geometry'])])) == normalized(geometry)
    assert not any(item.is_pseudo_comment for item in geometry)
    assert all(getattr(item, 'command', None) in COLORS | SCALARS | {'As'} for item in items[first:start])
    counts = [item for item in items[first:start] if item.command == 'As']
    assert len(counts) <= 1
    if counts:
        assert items[first] is counts[0]
        count = len(geometry) - 1
        if geometry[-1].command.islower() and list(map(float, geometry[-2].tokens[-2:])) == list(map(float, geometry[0].tokens)):
            count -= 1
        assert int(counts[0].tokens[0]) == count
    else:
        assert first == start
    assert last == end or last == end + 1 and isinstance(items[end], dict) and items[end]['_type'] == 'ArtDictionary'
    marker = ('path', (geometry[-1].command not in ('n', 'N'), normalized(geometry)))
    parents = [index for index, node in enumerate(nodes) if marker in node['children']]
    assert len(parents) == 1 and nodes[parents[0]]['children'].count(marker) == 1
    return first, last, marker, parents[0]


def views(inkai, source, target, nodes, marker, parent, anchor, row):
    """Relocate the independently rendered path in the original tree before comparing."""
    modes = ('printing',) if row['source'].startswith('synthetic') else ('native', 'printing')
    for mode in modes:
        before = etree.fromstring(inkai.to_svg(str(source)) if mode == 'native' else etree.tostring(printable_svg(inkai, source)))
        after = etree.fromstring(inkai.to_svg(str(target)) if mode == 'native' else etree.tostring(printable_svg(inkai, target)))
        elements, paths = {0: before}, {}

        def bind(index):
            """Map explicit source containers and drawn paths to independent SVG owners."""
            visible = [(kind, value) for kind, value in nodes[index]['children'] if kind != 'path' or value[0]]
            actual = children(elements[index])
            assert len(visible) == len(actual), (row['result'], mode, index, 'Ambiguous SVG owners')
            for position, ((kind, value), child) in enumerate(zip(visible, actual)):
                if kind == 'node':
                    elements[value] = child
                    bind(value)
                elif kind == 'path':
                    paths[index, position] = child

        bind(0)
        if marker[1][0]:
            visible = [value for value in nodes[parent]['children'] if value[0] != 'path' or value[1][0]]
            selected = paths[parent, visible.index(marker)]
            selected.getparent().remove(selected)
            elements[anchor].append(selected)
        assert before.attrib == after.attrib
        raster_check(before, after, target.with_suffix('.' + mode))
        if [signature(node, before) for node in children(before)] != [signature(node, after) for node in children(after)]:
            inactive_stroke(before)
            inactive_stroke(after)
        assert [signature(node, before) for node in children(before)] == [signature(node, after) for node in children(after)], (row['result'], mode, 'Changed active appearance')
    return len(modes)


def verify(inkai, source, target, row):
    """Require exact unselected bytes, whole owner relocation and retained scalar state."""
    before, after = source.read_bytes(), target.read_bytes()
    original = inventory(inkai, source, row['before']['pairs'])
    changed = inventory(inkai, target, row['after']['pairs'])
    verified_inventory(inkai, source, row['before']['layers'])
    verified_inventory(inkai, target, row['after']['layers'])
    items, nodes = tree(original, list(range(len(row['before']['pairs']))))
    first, last, marker, parent = selection(before, items, nodes, row)
    anchor, anchor_start, _ = owner(before, items, nodes, row['anchorSpan'], row['anchor'])
    boundary = nodes[anchor]['last']
    assert before[row['position']:].split(None, 1)[0] == b'U'
    assert normalized(body(parsed(before[row['anchorSpan'][0]:row['position'] + 1]))) == normalized(items[anchor_start:boundary + 1])
    expected = deepcopy(nodes)
    expected[parent]['children'].remove(marker)
    expected[anchor]['children'].append(marker)
    _, actual = tree(changed, list(range(len(row['after']['pairs']))))
    assert topology(actual) == topology(expected), (row['result'], 'Incorrect path parent or sibling order')
    assert len(row['before']['pairs']) == len(row['after']['pairs'])
    for old, new in zip(row['before']['pairs'], row['after']['pairs']):
        assert before[old['start']:old['end']] == after[new['start']:new['end']]
    exact_bytes(before, after, original, items, (first, last), boundary, row)
    inherited_flags(original, changed, items, (first, last), boundary, row)
    changed_items = list(body(changed.trailer))
    for private in (False, True):
        observations = paints(original, items, private)
        moved = [value for index, value in observations if first <= index < last]
        expected = [value for index, value in observations if index < boundary and not first <= index < last]
        expected.extend(moved)
        expected.extend(value for index, value in observations if index >= boundary and not first <= index < last)
        assert expected == [value for _, value in paints(changed, changed_items, private)], (row['result'], private, 'Changed consumed native paint')
    if row['source'] == 'synthetic-counted':
        # The pinned SVG attach_path() clears persistent fill after an S command.
        # This fixture intentionally reuses that fill in the following F path;
        # qualify native states above, without claiming SVG/pixel agreement.
        return 0
    return views(inkai, source, target, nodes, marker, parent, anchor, row)


def main():
    """Bind every transaction to pinned originals or declared deterministic fixtures."""
    if not __debug__:
        raise RuntimeError('Run verification without assertion stripping')
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--inkai-source', required=True, type=Path)
    parser.add_argument('--output', default=Path('test/corpus/output/path-group-movement'), type=Path)
    args = parser.parse_args()
    assert subprocess.check_output(['git', '-C', str(args.inkai_source), 'rev-parse', 'HEAD'], text=True).strip() == REVISION
    assert not subprocess.check_output(['git', '-C', str(args.inkai_source), 'status', '--porcelain', '--untracked-files=no'], text=True).strip()
    sys.path.insert(0, str(args.inkai_source.resolve()))
    inkai = importlib.import_module('inkai')
    manifest = {entry['file']: entry for name in ('manifest.json', 'direct_shape_manifest.json') for entry in json.loads(Path('test/corpus', name).read_text())['files']}
    programs = {name: pinned_program(name, manifest) for name in POSITIONS}
    rows = json.loads((args.output / 'report.json').read_text())
    expected, checked, comparisons = requests(), [], 0
    assert len(rows) == len(expected) == 15 and {(row['source'], row['variant']) for row in rows} == expected.keys()
    for row in rows:
        name, variant = row['source'], row['variant']
        assert row['operation'] == 'path'
        assert tuple(row[key] for key in ('selected', 'anchor', 'inheritParentFlags', 'rejected')) == expected[name, variant]
        assert row['original'] == f'{name}.{variant}.original.ps' and row['result'] == f'{name}.{variant}.ps'
        source, target = args.output / row['original'], args.output / row['result']
        if name in SYNTHETIC:
            assert row['recipe'] is None and hashlib.sha256(source.read_bytes()).hexdigest() == SYNTHETIC[name]
        else:
            position = POSITIONS[name][variant == 'backward']
            assert row['recipe'] == dict(position=position, insertion='\nu U\n')
            assert source.read_bytes() == programs[name][:position] + b'\nu U\n' + programs[name][position:]
        if row['rejected']:
            assert source.read_bytes() == target.read_bytes() and row['before'] == row['after']
            assert ('explicit inheritParentFlags' if name.startswith('synthetic') else 'unresolved native style state: D, Ap') in row['issue']
        else:
            assert row['issue'] is None
            comparisons += verify(inkai, source, target, row)
        checked.append(row['result'])
        print(row['result'], 'passed', flush=True)
    (args.output / 'independent-report.json').write_text(json.dumps(dict(
        oracleRevision=REVISION, transactions=checked, successfulMoves=12, refusals=3, svgAndPixelComparisons=comparisons,
        nativeOnly=['synthetic-counted.empty.ps'],
        visualLimitation='Pinned SVG attach_path clears persistent fill after stroke-only paths; counted reuse is verified as native data only.',
    ), indent=2) + '\n')


if __name__ == '__main__':
    main()
