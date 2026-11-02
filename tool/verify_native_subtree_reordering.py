#!/usr/bin/env python3
"""Verify mixed-owner permutations against pinned original sources and native readers."""

import argparse
import hashlib
import importlib
import json
from pathlib import Path
import re
import subprocess
import sys
import tempfile

from lxml import etree

from corpus_support import REVISION, printable_svg
from verify_native_direct_shapes import normalized
from verify_native_layers import verified_inventory
from verify_native_path_lifecycle import patch
from verify_native_reference_resources import FILES, pinned_program
from verify_native_shape_lifecycle import artwork, body, bundles, inventory, signature
from verify_native_shape_reordering import flags, inactive_stroke, raster_check
from verify_native_shape_removal import COLORS, SCALARS, scalar_value
from verify_native_structure import parsed
from verify_native_subtree_copy import input_state, key
from verify_native_subtree_removal import children as svg_children

SYNTHETIC = {
    ('synthetic-batch', 'group'): '8b3b5898676018ac6e9c35f27bc916d7cdde12ceb6eae573070a74bf305cb319',
    ('synthetic', 'group'): 'ba3add023c86492e1dcfb4043a526186314b939c4300b96fc25508711963a399',
    ('synthetic-following', 'group'): 'a901e7fc2186a99f40219d529afa71d2f9c05868affd6c991f9aaf6e983a099a',
    ('synthetic-reset', 'group'): 'f3f4439580dcb244a24b0db4d8bda7a749e9bf59110d453d4fffd183273fc325',
    ('synthetic', 'layer'): 'c13c68cc8d95dcfdc539c093f0d2bbd41acbc91d976c4b2e31afe8a9eeacc1a4',
    ('synthetic-following', 'layer'): '22494a394b50cf0688619ba885ded94efc5b113bcf9c842ac5e0d8045f7aeb80',
    ('synthetic-reset', 'layer'): '7cdfc1f9a9897221f1fb89b61a9498dc84c35f207605f4adf29573f017e84aa4',
}
COUNTS = {'simple_shapes.ai': 5, 'simple_shapes_cc.ai': 5, 'gradient_linear.ai': 15, 'gradient_radial.ai': 9}


def requests():
    """Require all fixed permutations, unchanged transactions and atomic refusals."""
    result = {}
    for name, count in COUNTS.items():
        first = int(name != 'gradient_linear.ai')
        for operation in ('group', 'layer'):
            result[name, operation, 'adjacent'] = [first + 1, first], False
            result[name, operation, 'ends'] = [count - 1, first], False
            result[name, operation, 'reverse'] = list(range(count - 1, first - 1, -1)), False
            result[name, operation, 'reject-first' if first else 'unchanged'] = ([1, 0], True) if first else ([0, 1], False)
    for operation in ('group', 'layer'):
        result['synthetic', operation, 'rotate'] = [2, 0, 1], False
        result['synthetic', operation, 'ends'] = [2, 0], False
        result['synthetic', operation, 'unchanged'] = [0, 1, 2], False
        result['synthetic-following', operation, 'reverse'] = [2, 1, 0], True
        result['synthetic-reset', operation, 'reverse'] = [2, 1, 0], False
    result['synthetic-batch', 'group', 'reverse'] = [1, 0], False
    return result


def dictionary(name):
    """Reconstruct the declared wrapper identity without accepting arbitrary metadata."""
    return f'%_/ArtDictionary :\n%_/XMLUID : ({name}) ; (AI10_ArtUID) ,\n%_\n%_;'.encode()


def provenance(inkai, source, row, programs, directory):
    """Bind every added wrapper to one exact complete pair from a pinned original."""
    original = programs[row['source']]
    path = directory / row['source']
    path.write_bytes(original)
    pairs = bundles(inkai.parse(str(path)))
    assert len(pairs) == len(row['recipe']) == COUNTS[row['source']]
    edits = []
    for index, (pair, recipe) in enumerate(zip(pairs, row['recipe'])):
        first, last = recipe['start'], recipe['end']
        opening = b'0 Ae\nu\nu\n'
        closing = b'\nU\n' + dictionary(f'inner_{index}') + b'\nU\n' + dictionary(f'outer_{index}')
        if row['operation'] == 'layer':
            opening = (b'%AI5_BeginLayer\n1 1 1 1 0 0 1 0 79 128 255 0 50 0 Lb\n'
                       + f'(Wrapped_{index}) Ln\n1 AE\n%_/ArtDictionary :\n%_/XMLUID : (Wrapped_{index}) ; (AI10_ArtUID) ,\n%_;\n'.encode() + opening)
            closing += b'\nLB\n%AI5_EndLayer--'
        assert recipe == dict(start=first, end=last, opening=opening.decode(), closing=closing.decode())
        assert normalized(body(parsed(original[first:last]))) == normalized(pair['items'])
        edits.append((first, last, opening + original[first:last] + closing))
    assert source.read_bytes() == patch(original, edits)


def owners(data, document, row):
    """Bind every reported owner to a balanced independent group or layer interval."""
    items = list(body(document.trailer))
    ranges, parents, stack = [], {}, []
    for index, item in enumerate(items):
        operator = getattr(item, 'command', None)
        parents[index] = tuple(stack)
        if operator in ('u', '*u', 'q', 'Lb'):
            stack.append(index)
        elif operator in ('U', '*U', 'Q', 'LB'):
            stack.pop()
    assert not stack
    for index, (first, last) in enumerate(row['spans']):
        fragment = list(body(parsed(data[first:last])))
        expected = normalized(fragment)
        matches = [position for position in range(len(items) - len(fragment) + 1) if normalized(items[position:position + len(fragment)]) == expected]
        assert len(matches) == 1
        start, end = matches[0], matches[0] + len(fragment)
        assert parents[start] == parents.get(end, ())
        if row['operation'] == 'group':
            if row['source'] == 'synthetic-batch':
                assert fragment[0].command == 'u'
            else:
                assert fragment[0].command == 'Ae' and fragment[1].command == 'u'
            identity = ('batch_a', 'batch_b')[index] if row['source'] == 'synthetic-batch' else f'outer_{index}'
            assert fragment[-2].command == 'U' and fragment[-1]['AI10_ArtUID'] == identity
        else:
            assert fragment[0].command == 'Lb' and fragment[-1].command == 'LB'
            name = ('Layer_' if row['source'].startswith('synthetic') else 'Wrapped_') + str(index)
            assert fragment[1].command == 'Ln' and fragment[1].tokens == [name.encode()]
            bound = [layer for layer in row['before']['layers']['layers'] if layer['start'] == first and layer['end'] == last]
            assert len(bound) == 1
        ranges.append((start, end))
    assert all(a[1] <= b[0] for a, b in zip(ranges, ranges[1:]))
    assert len({parents[ranges[index][0]] for index in row['order']}) == 1
    return items, ranges


def permutation(row):
    """Map every destination owner to its original source index."""
    order = list(range(len(row['spans'])))
    for target, source in zip(sorted(row['order']), row['order']):
        order[target] = source
    return order


def exact_placements(before, after, document, items, ranges, row, order):
    """Allow exact whole owners and only source-derived boundary-state restoration."""
    scalar = rb'(?:%_)?[+\-.\deE \t\[\]]+ (?:' + b'|'.join(value.encode() for value in sorted(SCALARS | COLORS)) + rb')\n'
    parts, checks, position = [], [], 0
    events = [(*row['spans'][target], target, source) for target, source in enumerate(order) if target != source]
    if row['operation'] == 'layer':
        events.extend((*span, None, None) for span in row['before']['layers']['viewSpans'])
        assert not row['after']['layers']['viewSpans']
    for first, last, target, source in sorted(events):
        assert first >= position
        parts.append(re.escape(before[position:first]))
        if source is not None:
            start, end = row['spans'][source]
            parts.extend([rb'(\n(?:' + scalar + rb')*?)', re.escape(before[start:end]), rb'\n((?:' + scalar + rb')*?)'])
            checks.extend([ranges[source][0], ranges[target][1]])
        position = last
    parts.append(re.escape(before[position:]))
    match = re.fullmatch(b''.join(parts), after)
    assert match is not None, (row['result'], 'Modified owner bytes, unselected source or non-scalar replay')
    for fragment, boundary in zip(match.groups(), checks):
        for command in parsed(fragment):
            state = input_state(document, items, boundary, command.is_pseudo_comment)
            assert state.get(key(command.command)) == scalar_value(command), (row['result'], 'Replay differs from required original boundary state', command.command)


def retained_state(original, changed, items, ranges, row, order):
    """Check every moved and retained contour's inherited state in both projections."""
    for private in (False, True):
        moves, values = flags(original, private=private, opacity=row['source'].startswith('synthetic'))
        indices = {id(item): index for index, item in enumerate(moves)}
        blocks, starts = [], {}
        for index, (first, last) in enumerate(ranges):
            selected = [indices[id(item)] for item in items[first:last] if id(item) in indices]
            assert selected == list(range(selected[0], selected[-1] + 1))
            starts[selected[0]] = index
            blocks.append(values[selected[0]:selected[-1] + 1])
        expected, position = [], 0
        while position < len(values):
            if position in starts:
                index = starts[position]
                expected.extend(blocks[order[index]])
                position += len(blocks[index])
            else:
                expected.append(values[position])
                position += 1
        assert expected == flags(changed, private=private, opacity=row['source'].startswith('synthetic'))[1], (row['result'], private, 'Inherited contour flags changed')


def views(inkai, source, target, row, order):
    """Permute entire native/printing SVG subtrees and retain unselected artwork."""
    for mode in (('printing',) if row['source'].startswith('synthetic') else ('native', 'printing')):
        before = etree.fromstring(inkai.to_svg(str(source)) if mode == 'native' else etree.tostring(printable_svg(inkai, source)))
        after = etree.fromstring(inkai.to_svg(str(target)) if mode == 'native' else etree.tostring(printable_svg(inkai, target)))
        children = artwork(before)
        assert len(children) >= len(order)
        parent = children[0].getparent()
        assert all(node.getparent() is parent for node in children)
        for node in children:
            parent.remove(node)
        parent.extend([children[index] for index in order] + children[len(order):])
        assert before.attrib == after.attrib
        # Generated definitions can change order; bind each resource at its use.
        if [signature(node, before) for node in svg_children(before)] != [signature(node, after) for node in svg_children(after)]:
            # Pin the existing disabled-stroke exception to exact independent ink.
            raster_check(before, after, target.with_suffix('.' + mode))
            inactive_stroke(before)
            inactive_stroke(after)
            assert [signature(node, before) for node in svg_children(before)] == [signature(node, after) for node in svg_children(after)], (row['result'], mode, 'Changed active geometry, styles or ownership')


def verify(inkai, source, target, row):
    """Verify byte owners, both metadata alternatives, projections and source flags."""
    before, after = source.read_bytes(), target.read_bytes()
    original = inventory(inkai, source, row['before']['pairs'])
    changed = inventory(inkai, target, row['after']['pairs'])
    verified_inventory(inkai, source, row['before']['layers'])
    verified_inventory(inkai, target, row['after']['layers'])
    items, ranges = owners(before, original, row)
    order = permutation(row)
    pairs = row['before']['pairs']
    blocks = [[pair for pair in pairs if first <= pair['start'] and pair['end'] <= last] for first, last in row['spans']]
    assert sum(map(len, blocks)) == len(pairs)
    expected = [pair for index in order for pair in blocks[index]]
    assert len(row['after']['pairs']) == len(expected)
    for old, new in zip(expected, row['after']['pairs']):
        assert before[old['start']:old['end']] == after[new['start']:new['end']]
    exact_placements(before, after, original, items, ranges, row, order)
    retained_state(original, changed, items, ranges, row, order)
    views(inkai, source, target, row, order)


def main():
    """Require pinned sources, exact requests and an unchanged independent reader."""
    if not __debug__:
        raise RuntimeError('Run verification without assertion stripping')
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--inkai-source', required=True, type=Path)
    parser.add_argument('--output', default=Path('test/corpus/output/subtree-reordering'), type=Path)
    args = parser.parse_args()
    assert subprocess.check_output(['git', '-C', str(args.inkai_source), 'rev-parse', 'HEAD'], text=True).strip() == REVISION
    assert not subprocess.check_output(['git', '-C', str(args.inkai_source), 'status', '--porcelain', '--untracked-files=no'], text=True).strip()
    sys.path.insert(0, str(args.inkai_source.resolve()))
    inkai = importlib.import_module('inkai')
    manifest = {entry['file']: entry for entry in json.loads(Path('test/corpus/manifest.json').read_text())['files']}
    programs = {name: pinned_program(name, manifest) for name in FILES}
    rows = json.loads((args.output / 'report.json').read_text())
    expected, checked = requests(), []
    assert len(rows) == len(expected) == 43 and {(row['source'], row['operation'], row['variant']) for row in rows} == expected.keys()
    with tempfile.TemporaryDirectory(prefix='aicodec-subtree-reordering-') as temporary:
        for row in rows:
            assert (row['order'], row['rejected']) == expected[row['source'], row['operation'], row['variant']]
            assert row['original'] == row['source'] + '.' + row['operation'] + '.original.ps'
            assert row['result'] == row['source'] + '.' + row['operation'] + '.' + row['variant'] + '.ps'
            source, target = args.output / row['original'], args.output / row['result']
            if row['source'].startswith('synthetic'):
                assert row['recipe'] is None and hashlib.sha256(source.read_bytes()).hexdigest() == SYNTHETIC[row['source'], row['operation']]
            else:
                provenance(inkai, source, row, programs, Path(temporary))
            if row['rejected']:
                assert row['issue'] and source.read_bytes() == target.read_bytes() and row['before'] == row['after']
                reason = 'unresolved native style state: fill' if row['source'].startswith('synthetic') else 'unknown inherited printing D'
                assert reason in row['issue']
            else:
                assert row['issue'] is None
                if row['variant'] == 'unchanged':
                    assert source.read_bytes() == target.read_bytes() and row['before'] == row['after']
                else:
                    verify(inkai, source, target, row)
            checked.append(row['result'])
            print(row['result'], 'passed', flush=True)
    (args.output / 'independent-report.json').write_text(json.dumps(dict(oracleRevision=REVISION, transactions=checked, derivedRealReorderings=24, syntheticReorderings=7, unchanged=4, refusals=8), indent=2) + '\n')


if __name__ == '__main__':
    main()
