#!/usr/bin/env python3
"""Verify grouping/dissolution through exact source, native topology and identities."""

import argparse
from copy import deepcopy
import hashlib
import importlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile

from corpus_support import REVISION
from verify_native_direct_shapes import normalized
from verify_native_path_lifecycle import patch
from verify_native_reference_resources import FILES, pinned_program
from verify_native_shape_lifecycle import body, bundles
from verify_native_shape_reordering import flags
from verify_native_structure import parsed
from verify_native_subtree_copy import input_state
from verify_native_subtree_movement import topology, tree
from verify_native_subtree_reordering import provenance

SYNTHETIC = {
    'mixed': 'ef0683a2a0039d216f103877402e69240aee331b09ed7e959c83eac6e18e202e',
    'identified': 'ba3add023c86492e1dcfb4043a526186314b939c4300b96fc25508711963a399',
    'flags': '5610491b500ecfc990e4e02cac6b1bbedc4c3ed3e279761414e103fcf12f90f6',
    'gap': '737d0ac53aa93ea59ff6351715c0c057b93d3b20aaa6ad3ff13106522f56841a',
    'opaque': 'dad9132b8369eb2eeec2fd9b5461d67f7f2c39538297fe7cf269eb5ac10e06d5',
    'alias': '5b9a9bc1b6c9a0d4d879412b419b8e25be53bd24e5c79f78ebd49034377d54ee',
}


def requests():
    """Fix operation, exact selected owners and explicit policies before decoding."""
    result = {}
    for name in FILES:
        result[name, 'pairs'] = 'group', [('pair', 0), ('pair', 1)], False, True, None
        result[name, 'dissolve'] = 'dissolve', [('group', '')], False, True, None
        result[name, 'subtrees'] = 'group', [('group', 'outer_0'), ('group', 'outer_1')], False, True, None
    result['synthetic', 'mixed'] = 'group', [('group', 'parent'), ('path', 'ordinary'), ('pair', 1)], False, True, None
    result['synthetic', 'identified'] = 'dissolve', [('group', f'outer_{index}') for index in range(3)], True, False, None
    result['synthetic', 'flags'] = 'group', [('pair', 0), ('pair', 1)], False, False, 'explicit inheritParentFlags'
    result['synthetic', 'gap'] = 'group', [('pair', 0), ('pair', 2)], False, True, 'unqualified group boundary'
    result['synthetic', 'opaque'] = 'dissolve', [('group', 'outer_0')], True, True, 'reference owners'
    result['synthetic', 'alias'] = 'dissolve', [('group', 'outer_0')], True, True, 'unambiguous native identity'
    return result


def selection(data, items, nodes, pairs, selected):
    """Bind reported byte spans to uniquely parsed complete native owners."""
    first, last = selected['start'], selected['end']
    fragment = list(body(parsed(data[first:last])))
    matches = [index for index in range(len(items) - len(fragment) + 1) if normalized(items[index:index + len(fragment)]) == normalized(fragment)]
    assert len(matches) == 1
    start = matches[0]
    if selected['kind'] == 'pair':
        assert normalized(fragment) == normalized(pairs[selected['index']]['items'])
        marker = 'pair', selected['index']
    elif selected['kind'] == 'group':
        opening = start + int(getattr(fragment[0], 'command', None) == 'Ae')
        index, = [index for index, node in enumerate(nodes) if index and node['first'] == opening]
        node = nodes[index]
        assert node['kind'] == 'u'
        closing = node['last'] - start
        assert normalized(body(parsed(data[first:selected['openingEnd']]))) == normalized(fragment[:opening - start + 1])
        assert normalized(body(parsed(data[selected['closingStart']:last]))) == normalized(fragment[closing:])
        tail = fragment[closing + 1:]
        if selected.get('reset', False):
            assert tail[-1].command == 'XW' and tail[-1].tokens == [b'9', b''] and not tail[-1].is_pseudo_comment
            tail = tail[:-1]
        if selected['name']:
            assert len(tail) == 1 and tail[0]['_type'] == 'ArtDictionary' and tail[0]['AI10_ArtUID'] == selected['name']
        else:
            assert not tail or len(tail) == 1 and tail[0] == {'_type': 'ArtDictionary'}
        marker = 'node', index
    else:
        assert selected['kind'] == 'path' and fragment[-1]['AI10_ArtUID'] == selected['name']
        assert fragment[0].command == 'As' and int(fragment[0].tokens[0]) == 2
        assert [item.command for item in fragment[1:-1]] == ['m', 'L', 'S']
        marker = 'path', (True, normalized(fragment[1:-1]))
    parent, = [index for index, node in enumerate(nodes) if marker in node['children']]
    return parent, marker, start


def verify(inkai, source, target, row):
    """Apply the requested hierarchy change independently and constrain every byte."""
    before, after = source.read_bytes(), target.read_bytes()
    original, changed = inkai.parse(str(source)), inkai.parse(str(target))
    pairs, retained = bundles(original), bundles(changed)
    assert [normalized(pair['items']) for pair in pairs] == [normalized(pair['items']) for pair in retained]
    items, nodes = tree(original, list(range(len(pairs))))
    _, actual = tree(changed, list(range(len(pairs))))
    bound = [selection(before, items, nodes, pairs, selected) for selected in row['selected']]
    expected = deepcopy(nodes)
    edits = []
    if row['operation'] == 'group':
        assert len({parent for parent, _, _ in bound}) == 1
        parent = bound[0][0]
        markers = [marker for _, marker, _ in bound]
        indices = [nodes[parent]['children'].index(marker) for marker in markers]
        assert indices == list(range(indices[0], indices[0] + len(indices)))
        first, last = row['selected'][0]['start'], row['selected'][-1]['end']
        edits = [(first, first, b'\nu\n'), (last, last, b'\nU\n')]
        expected[parent]['children'][indices[0]:indices[-1] + 1] = [('node', len(expected))]
        expected.append(dict(kind='u', label=None, children=markers))
    else:
        for selected, (parent, (_, index), _) in zip(row['selected'], bound):
            children = expected[parent]['children']
            position = children.index(('node', index))
            children[position:position + 1] = expected[index]['children']
            edits.extend([(selected['start'], selected['openingEnd'], b' '), (selected['closingStart'], selected['end'], b' ')])
    assert after == patch(before, edits)
    assert topology(actual) == topology(expected)
    for private in (False, True):
        assert flags(original, private=private, opacity=True)[1] == flags(changed, private=private, opacity=True)[1]
        if not row['inheritParentFlags']:
            for _, _, boundary in bound:
                state = input_state(original, items, boundary, private)
                assert all(state.get(key) == (key, (0.0,)) for key in ('A', 'Xw'))


def main():
    """Require pinned sources, fixed requests and an unmodified independent reader."""
    if not __debug__:
        raise RuntimeError('Run verification without assertion stripping')
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--inkai-source', required=True, type=Path)
    parser.add_argument('--output', default=Path('test/corpus/output/subtree-grouping'), type=Path)
    args = parser.parse_args()
    assert subprocess.check_output(['git', '-C', str(args.inkai_source), 'rev-parse', 'HEAD'], text=True).strip() == REVISION
    assert not subprocess.check_output(['git', '-C', str(args.inkai_source), 'status', '--porcelain', '--untracked-files=no'], text=True).strip()
    sys.path.insert(0, str(args.inkai_source.resolve()))
    inkai = importlib.import_module('inkai')
    manifest = {entry['file']: entry for entry in json.loads(Path('test/corpus/manifest.json').read_text())['files']}
    programs = {name: pinned_program(name, manifest) for name in FILES}
    rows = json.loads((args.output / 'report.json').read_text())
    expected, checked = requests(), []
    assert len(rows) == len(expected) == 18 and {(row['source'], row['variant']) for row in rows} == expected.keys()
    with tempfile.TemporaryDirectory(prefix='aikit-subtree-grouping-') as temporary:
        for row in rows:
            name, variant = row['source'], row['variant']
            operation, selected, discard, inherit, refusal = expected[name, variant]
            assert (row['operation'], row['discardMetadata'], row['inheritParentFlags']) == (operation, discard, inherit)
            assert [(owner['kind'], owner.get('index', owner.get('name'))) for owner in row['selected']] == selected
            assert row['original'] == f'{name}.{variant}.original.ps' and row['result'] == f'{name}.{variant}.ps'
            source, target = args.output / row['original'], args.output / row['result']
            if name == 'synthetic':
                assert row['recipe'] is None and hashlib.sha256(source.read_bytes()).hexdigest() == SYNTHETIC[variant]
            elif variant == 'subtrees':
                provenance(inkai, source, row, programs, Path(temporary))
            else:
                assert row['recipe'] is None
                assert source.read_bytes() == (programs[name] if variant == 'pairs' else (args.output / f'{name}.pairs.ps').read_bytes())
            if refusal:
                assert refusal in row['issue'] and source.read_bytes() == target.read_bytes()
                document = inkai.parse(str(source))
                pairs = bundles(document)
                items, nodes = tree(document, list(range(len(pairs))))
                bound = [selection(source.read_bytes(), items, nodes, pairs, owner) for owner in row['selected']]
                if variant == 'flags':
                    assert input_state(document, items, bound[0][2], True)['A'] == ('A', (1.0,))
                    assert input_state(document, items, bound[0][2], False)['A'] == ('A', (0.0,))
                elif variant == 'gap':
                    parent = bound[0][0]
                    assert bound[1][0] == parent and nodes[parent]['children'].index(bound[1][1]) - nodes[parent]['children'].index(bound[0][1]) == 2
            else:
                assert row['issue'] is None
                verify(inkai, source, target, row)
            checked.append(row['result'])
            print(row['result'], 'passed', flush=True)
    (args.output / 'independent-report.json').write_text(json.dumps(dict(oracleRevision=REVISION, transactions=checked, derivedReal=12, synthetic=2, refusals=4), indent=2) + '\n')


if __name__ == '__main__':
    main()
