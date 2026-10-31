#!/usr/bin/env python3
"""Verify complete CC movement, independent hierarchy and both source state streams."""

import argparse
import copy
import hashlib
import importlib
import json
from pathlib import Path
import re
import subprocess
import sys

from lxml import etree

from corpus_support import REVISION, native_programs, printable_svg
from verify_native_capabilities import body_operators
from verify_native_shape_lifecycle import body, bundles, inventory, signature
from verify_native_shape_removal import COLORS, SCALARS, scalar_value
from verify_native_shape_reordering import retained_state, views
from verify_native_structure import parsed

SYNTHETIC = {
    'synthetic': '737d0ac53aa93ea59ff6351715c0c057b93d3b20aaa6ad3ff13106522f56841a',
    'synthetic-groups': '8c2fd5b51933c0c06ce6c802a2df7f1210658c68677169259f77e633e98852e5',
    'synthetic-layers': 'ab6ef52c8520f7628f8edc3d8c3b168efc23c80afca94e947bfcfebc4b94d83f',
    'synthetic-native-flags': '12cb81c7c04bf6800094fe41d78b93f309297aa74329aa2f8f2b61e82899740a',
    'synthetic-printing-flags': '75717fbc9acb0345ba2b8e0a0782773d19c6dc906f38ce6190c21515f6c89516',
    'synthetic-panel': 'c7421a9ebfdb0d3fc95ba47002ebead52803ab0e06783dc289dedc769b37f5db',
    'synthetic-reference': 'aa754a5d8f04d84ed8fa4004b200616eaeccbe91c8a437b82c8b05fbf75fcbee',
    'synthetic-unknown': '0365987ecf97b1ac7e9444e8c66103a015a3f54c8464ea10fd7203c55ec68640',
    'synthetic-following': '9d24bf78168ad7477b0062e1f9b418d67d8bc950173d7e112bb4016d6ffc5f90',
}


def requests():
    """Pin source selections, destinations, inheritance and every expected refusal."""
    result = {}
    for name, count in [('simple_shapes.ai', 5), ('simple_shapes_cc.ai', 5), ('gradient_linear.ai', 15), ('gradient_radial.ai', 9)]:
        first = int(name != 'gradient_linear.ai')
        result[name, 'forward'] = first, str(count - 1), False, False
        result[name, 'backward'] = count - 1, str(first), False, False
        result[name, 'adjacent'] = first, str(first + 1), False, False
        if first:
            result[name, 'reject-first'] = 0, str(count - 1), False, True
    result['synthetic', 'forward'] = 0, '2', False, False
    result['synthetic', 'backward'] = 2, '0', False, False
    result['synthetic-groups', 'empty'] = 0, 'empty-group', False, False
    result['synthetic-groups', 'backward'] = 2, 'first-group', False, False
    result['synthetic-layers', 'cross'] = 0, '2', True, False
    result['synthetic-layers', 'empty'] = 0, 'empty-layer', True, False
    result['synthetic-layers', 'lift'] = 0, 'first-layer', True, False
    result['synthetic-layers', 'reject-cross'] = 0, '2', False, True
    for projection in ('native', 'printing'):
        result[f'synthetic-{projection}-flags', 'inherit'] = 0, 'last-group', True, False
        result[f'synthetic-{projection}-flags', 'reject-flags'] = 0, 'last-group', False, True
    for name in ('synthetic-panel', 'synthetic-reference', 'synthetic-unknown'):
        result[name, 'forward'] = 0, '1' if name == 'synthetic-unknown' else '2', False, False
    result['synthetic-following', 'reject-forward'] = 0, '2', False, True
    result['synthetic-following', 'reject-backward'] = 2, '0', False, True
    return result


def hierarchy(document, order):
    """Bind each complete pair to independently parsed enclosing groups and layers."""
    items = list(body(document.trailer))
    pairs = bundles(document)
    starts = {id(pair['items'][0]): (index, len(pair['items'])) for index, pair in enumerate(pairs)}
    nodes = [dict(kind='root', parent=None, children=[])]
    stack, parents, position = [0], {}, 0
    closing = {'U': 'u', '*U': '*u', 'Q': 'q', 'LB': 'Lb'}
    while position < len(items):
        item = items[position]
        if id(item) in starts:
            index, count = starts[id(item)]
            nodes[stack[-1]]['children'].append(('pair', order[index]))
            parents[order[index]] = stack[-1]
            position += count
            continue
        operator = getattr(item, 'command', None)
        if operator in closing.values():
            index = len(nodes)
            nodes[stack[-1]]['children'].append(('node', index))
            nodes.append(dict(kind=operator, parent=stack[-1], children=[]))
            stack.append(index)
        elif operator in closing:
            assert len(stack) > 1 and nodes[stack[-1]]['kind'] == closing[operator]
            stack.pop()
        position += 1
    assert stack == [0] and len(parents) == len(pairs)
    return nodes, parents


def moved_hierarchy(nodes, parents, row):
    """Apply the declared parent operation independently of output pair positions."""
    result = copy.deepcopy(nodes)
    shape, destination = row['shape'], row['destination']
    marker = ('pair', shape)
    result[parents[shape]]['children'].remove(marker)
    if destination.isdigit():
        anchor = int(destination)
        siblings = result[parents[anchor]]['children']
        siblings.insert(siblings.index(('pair', anchor)) + 1, marker)
    else:
        if destination == 'empty-group':
            targets = [index for index, node in enumerate(nodes) if node['kind'] == 'u' and not node['children']]
            assert len(targets) == 1
            target = targets[0]
        elif destination in ('first-group', 'last-group'):
            target = parents[0 if destination == 'first-group' else len(parents) - 1]
            assert nodes[target]['kind'] == 'u'
        else:
            layers = [index for index, node in enumerate(nodes) if node['kind'] == 'Lb']
            target = layers[0 if destination == 'first-layer' else -1]
            if destination == 'empty-layer':
                assert not nodes[target]['children']
        result[target]['children'].append(marker)
    return result


def pair_order(nodes, index=0):
    """Enumerate complete source pairs in lexical order through the expected tree."""
    return [value for kind, child in nodes[index]['children'] for value in ([child] if kind == 'pair' else pair_order(nodes, child))]


def exact_bytes(before, after, original, row):
    """Allow only old-state replay, one intact source insertion and its scalar guards."""
    selected = row['before'][row['shape']]
    scalar = rb'(?:%_)?[+\-.\deE \t\[\]]+ (?:' + b'|'.join(key.encode() for key in sorted(SCALARS | COLORS)) + rb')\n'
    replay = rb'(\n(?:' + scalar + rb')*?)'
    events = [
        (selected['start'], selected['end'], replay),
        (row['position'], row['position'], replay + re.escape(before[selected['start']:selected['end']]) + rb'\n((?:' + scalar + rb')*?)'),
    ]
    pieces, position = [], 0
    for start, end, replacement in sorted(events):
        assert start >= position
        pieces.extend([re.escape(before[position:start]), replacement])
        position = end
    pieces.append(re.escape(before[position:]))
    match = re.fullmatch(b''.join(pieces), after)
    assert match is not None, (row['result'], 'Changed bytes outside the two owned boundaries')
    literals = [item for item in [*body(original.trailer), *body_operators(original.setup)] if getattr(item, 'command', None) in SCALARS | COLORS]
    for fragment in match.groups():
        for command in parsed(fragment):
            assert command.command in SCALARS | COLORS
            assert any(command.command == value.command and scalar_value(command) == scalar_value(value) and (command.is_pseudo_comment or not value.is_pseudo_comment) for value in literals)
    if row['destination'].isdigit():
        assert row['position'] == row['before'][int(row['destination'])]['end']
    else:
        # Exact source bytes plus the complete independently checked output tree
        # bind this closing delimiter to the requested group or layer.
        token = before[row['position']:].split(None, 1)[0]
        assert token == (b'LB' if row['destination'].endswith('layer') else b'U')


def synthetic_view(inkai, source, target, nodes, expected, row):
    """Move one original printable subtree and compare complete enclosing SVG trees."""
    before = printable_svg(inkai, source)
    after = printable_svg(inkai, target)
    elements, pairs = {0: before}, {}

    def bind(index):
        """Bind independently decoded owner slots to original printable subtrees."""
        children = [child for child in elements[index] if etree.QName(child).localname != 'defs']
        assert len(children) == len(nodes[index]['children'])
        for (kind, identifier), child in zip(nodes[index]['children'], children):
            if kind == 'pair':
                pairs[identifier] = child
            else:
                elements[identifier] = child
                bind(identifier)

    bind(0)
    selected = pairs[row['shape']]
    selected.getparent().remove(selected)
    for index, node in enumerate(expected):
        if ('pair', row['shape']) in node['children']:
            offset = node['children'].index(('pair', row['shape']))
            parent = elements[index]
            offset += sum(etree.QName(child).localname == 'defs' for child in parent)
            parent.insert(offset, selected)
            break
    assert signature(before, before) == signature(after, after), (row['result'], 'Printing geometry, resources or enclosing appearance changed')


def verify(inkai, source, target, row):
    """Require both saved metadata branches, intact pairs and independent ownership."""
    original = inventory(inkai, source, row['before'])
    changed = inventory(inkai, target, row['after'])
    nodes, parents = hierarchy(original, list(range(len(row['before']))))
    expected = moved_hierarchy(nodes, parents, row)
    order = pair_order(expected)
    actual, _ = hierarchy(changed, order)
    assert actual == expected, (row['result'], 'Unexpected object parent or ordering')
    before, after = source.read_bytes(), target.read_bytes()
    for target_index, source_index in enumerate(order):
        old, new = row['before'][source_index], row['after'][target_index]
        assert before[old['start']:old['end']] == after[new['start']:new['end']]
    exact_bytes(before, after, original, row)
    retained_state(original, changed, {**row, 'source': 'synthetic' if row['source'] in SYNTHETIC else row['source']}, order)
    if row['source'] in SYNTHETIC:
        # The external SVG dispatcher does not evaluate synthetic version lists.
        # Native authoring branches are verified by inventory and exact bytes.
        synthetic_view(inkai, source, target, nodes, expected, row)
    else:
        views(inkai, source, target, row, order)


def main():
    """Require pinned input provenance and an unchanged external reader revision."""
    if not __debug__:
        raise RuntimeError('Run verification without assertion stripping')
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--inkai-source', required=True, type=Path)
    parser.add_argument('--output', default=Path('test/corpus/output/shape-movement'), type=Path)
    args = parser.parse_args()
    assert subprocess.check_output(['git', '-C', str(args.inkai_source), 'rev-parse', 'HEAD'], text=True).strip() == REVISION
    assert not subprocess.check_output(['git', '-C', str(args.inkai_source), 'status', '--porcelain', '--untracked-files=no'], text=True).strip()
    sys.path.insert(0, str(args.inkai_source.resolve()))
    inkai = importlib.import_module('inkai')
    manifest = {entry['file']: entry for entry in json.loads(Path('test/corpus/manifest.json').read_text())['files']}
    expected = requests()
    rows = json.loads((args.output / 'report.json').read_text())
    assert len(rows) == len(expected) == 32 and {(row['source'], row['variant']) for row in rows} == expected.keys()
    checked = []
    for row in rows:
        assert (row['shape'], row['destination'], row['inheritParentFlags'], row['rejected']) == expected[row['source'], row['variant']]
        assert row['original'] == row['source'] + '.original.ps' and row['result'] == row['source'] + '.' + row['variant'] + '.ps'
        source, target = args.output / row['original'], args.output / row['result']
        before = source.read_bytes()
        if row['source'] in SYNTHETIC:
            assert hashlib.sha256(before).hexdigest() == SYNTHETIC[row['source']]
        else:
            path = Path('test/corpus/files', row['source'])
            entry = manifest[row['source']]
            assert path.stat().st_size == entry['size'] and hashlib.sha256(path.read_bytes()).hexdigest() == entry['sha256']
            assert before in (native_programs(path) if path.read_bytes().startswith(b'%PDF-') else [path.read_bytes()])
        if row['rejected']:
            assert before == target.read_bytes() and row['before'] == row['after'] and row['issue']
            issue = ('unresolved native style state: fill' if row['source'] == 'synthetic-following' else
                     'explicit inheritParentFlags' if row['source'] in SYNTHETIC else 'unknown inherited printing Ap')
            assert issue in row['issue']
        else:
            assert row['issue'] is None
            verify(inkai, source, target, row)
        checked.append(row['result'])
        print(row['result'], 'passed', flush=True)
    (args.output / 'independent-report.json').write_text(json.dumps(dict(oracleRevision=REVISION, transactions=checked, realMoves=12, syntheticMoves=12, refusals=8), indent=2) + '\n')


if __name__ == '__main__':
    main()
