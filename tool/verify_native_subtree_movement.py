#!/usr/bin/env python3
"""Verify whole-owner movement, parent inheritance and both native state boundaries."""

import argparse
from copy import deepcopy
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
from verify_native_reference_resources import FILES, pinned_program
from verify_native_shape_lifecycle import body, bundles, inventory, signature
from verify_native_shape_reordering import flags, inactive_stroke, raster_check
from verify_native_shape_removal import COLORS, SCALARS, restored_style, scalar_value
from verify_native_structure import parsed
from verify_native_subtree_copy import input_state, key
from verify_native_subtree_reordering import COUNTS, provenance
from verify_native_subtree_removal import children as svg_children

SYNTHETIC = {
    'synthetic-groups': 'f3c54af86c7a65d5438511c15c6c6d1b106a7a0a889001ce905126107e75c28b',
    'synthetic-layers': 'b198cbb7b1c278d332ad607645ea6de34a291001f409ebe229f474fe695111e5',
    'synthetic-batch': '8b3b5898676018ac6e9c35f27bc916d7cdde12ceb6eae573070a74bf305cb319',
    'synthetic-following': 'a901e7fc2186a99f40219d529afa71d2f9c05868affd6c991f9aaf6e983a099a',
    'synthetic-reset': 'f3f4439580dcb244a24b0db4d8bda7a749e9bf59110d453d4fffd183273fc325',
}


def requests():
    """Pin original owner names, destinations, explicit inheritance and refusals."""
    result = {}
    for name, count in COUNTS.items():
        for operation in ('group', 'layer'):
            prefix = 'outer_' if operation == 'group' else 'Wrapped_'
            first, last = prefix + str(int(name != 'gradient_linear.ai')), prefix + str(count - 1)
            result[name, operation, 'forward'] = first, 'after', last, False, False
            result[name, operation, 'backward'] = last, 'after', first, False, False
            result[name, operation, 'inside'] = first, 'inside', last, True, False
            if name != 'gradient_linear.ai':
                result[name, operation, 'reject-first'] = prefix + '0', 'after', last, False, True
    for variant, selected, destination, anchor, inherit, rejected in [
        ('forward', 'outer_0', 'after', 'outer_2', False, False),
        ('backward', 'outer_2', 'after', 'outer_0', False, False),
        ('inside', 'outer_0', 'inside', 'outer_2', True, False),
        ('empty', 'outer_0', 'inside', 'empty-group', True, False),
        ('reject-parent', 'outer_0', 'inside', 'outer_2', False, True),
    ]:
        result['synthetic-groups', 'group', variant] = selected, destination, anchor, inherit, rejected
    for variant, destination, anchor, inherit, rejected in [
        ('cross', 'after', 'outer_2', True, False), ('lift', 'inside', 'Layer_0', True, False),
        ('empty', 'inside', 'Empty', True, False), ('reject-cross', 'after', 'outer_2', False, True),
    ]:
        result['synthetic-layers', 'group', variant] = 'outer_0', destination, anchor, inherit, rejected
    for variant, selected, destination, anchor, inherit, rejected in [
        ('forward', 'Layer_0', 'after', 'Layer_2', False, False), ('backward', 'Layer_2', 'after', 'Layer_0', False, False),
        ('inside', 'Layer_0', 'inside', 'Layer_2', True, False), ('empty', 'Layer_0', 'inside', 'Empty', True, False),
        ('lift', 'Child_0', 'after', 'Layer_2', True, False), ('ancestor', 'Child_0', 'after', 'Layer_0', True, False),
        ('reject-parent', 'Layer_0', 'inside', 'Layer_2', False, True),
    ]:
        result['synthetic-layers', 'layer', variant] = selected, destination, anchor, inherit, rejected
    result['synthetic-batch', 'group', 'forward'] = 'batch_a', 'after', 'batch_b', False, False
    for name in ('synthetic-following', 'synthetic-reset'):
        result[name, 'group', 'forward'] = 'outer_0', 'after', 'outer_2', False, name == 'synthetic-following'
        result[name, 'group', 'backward'] = 'outer_2', 'after', 'outer_0', False, name == 'synthetic-following'
    return result


def tree(document, order):
    """Independently retain all group/layer boundaries, complete pairs and plain paths."""
    items = list(body(document.trailer))
    pairs = bundles(document)
    starts = {id(pair['items'][0]): (order[index], len(pair['items'])) for index, pair in enumerate(pairs)}
    nodes = [dict(kind='root', parent=None, children=[], first=0, last=len(items), label=None)]
    stack, position = [0], 0
    closing = {'U': 'u', '*U': '*u', 'Q': 'q', 'LB': 'Lb'}
    while position < len(items):
        item = items[position]
        if id(item) in starts:
            index, count = starts[id(item)]
            nodes[stack[-1]]['children'].append(('pair', index))
            position += count
            continue
        operator = getattr(item, 'command', None)
        if operator in closing.values():
            index = len(nodes)
            nodes[stack[-1]]['children'].append(('node', index))
            nodes.append(dict(kind=operator, parent=stack[-1], children=[], first=position, last=None, label=None))
            stack.append(index)
        elif operator in closing:
            assert nodes[stack[-1]]['kind'] == closing[operator]
            nodes[stack.pop()]['last'] = position
        elif operator == 'Ln':
            assert nodes[stack[-1]]['kind'] == 'Lb'
            nodes[stack[-1]]['label'] = item.tokens[0]
        elif operator == 'm':
            first = position
            while getattr(items[position], 'command', None) not in {'n', 'N', 'f', 'F', 's', 'S', 'b', 'B'}:
                position += 1
            nodes[stack[-1]]['children'].append(('path', (items[position].command not in ('n', 'N'), normalized(items[first:position + 1]))))
        position += 1
    assert stack == [0] and len(pairs) == len(order)
    return items, nodes


def owner(data, items, nodes, span, name):
    """Bind an exact saved byte owner and its declared name to balanced source tokens."""
    first, last = span
    fragment = list(body(parsed(data[first:last])))
    expected = normalized(fragment)
    matches = [index for index in range(len(items) - len(fragment) + 1) if normalized(items[index:index + len(fragment)]) == expected]
    assert len(matches) == 1
    start, end = matches[0], matches[0] + len(fragment)
    opening = start + int(getattr(items[start], 'command', None) == 'Ae')
    found = [index for index, node in enumerate(nodes) if index and node['first'] == opening]
    assert len(found) == 1
    index = found[0]
    if nodes[index]['kind'] == 'Lb':
        assert nodes[index]['label'] == name.encode() and nodes[index]['last'] == end - 1
    else:
        assert nodes[index]['kind'] == 'u'
        if name == 'empty-group':
            assert not nodes[index]['children'] and nodes[index]['last'] == end - 1
        else:
            assert fragment[-1]['AI10_ArtUID'] == name and nodes[index]['last'] == end - 2
    return index, start, end


def moved_tree(nodes, selected, anchor, row):
    """Apply the requested whole-node relocation without deriving it from output."""
    expected = deepcopy(nodes)
    marker = ('node', selected)
    expected[nodes[selected]['parent']]['children'].remove(marker)
    if row['destination'] == 'after':
        parent = nodes[anchor]['parent']
        children = expected[parent]['children']
        children.insert(children.index(('node', anchor)) + 1, marker)
    else:
        parent = anchor
        expected[parent]['children'].append(marker)
    expected[selected]['parent'] = parent
    return expected


def topology(nodes, index=0):
    """Compare semantic topology independently of relocated token offsets and indices."""
    node = nodes[index]
    return node['kind'], node['label'], [(kind, topology(nodes, value) if kind == 'node' else value) for kind, value in node['children']]


def pair_order(nodes, index=0):
    """Enumerate complete pairs in the requested new lexical order."""
    return [value for kind, child in nodes[index]['children'] for value in (pair_order(nodes, child) if kind == 'node' else [child] if kind == 'pair' else [])]


def exact_bytes(before, after, document, items, selected_range, boundary, row):
    """Allow only state at the old site, one exact insertion and source boundary replay."""
    first, last = row['span']
    scalar = rb'(?:%_)?[+\-.\deE \t\[\]]+ (?:' + b'|'.join(value.encode() for value in sorted(SCALARS | COLORS)) + rb')\n'
    replay = rb'(\n(?:' + scalar + rb')*?)'
    events = [(first, last, 'removed'), (row['position'], row['position'], 'inserted')]
    if row['operation'] == 'layer':
        events.extend((*span, 'view') for span in row['before']['layers']['viewSpans'])
        if row['before']['layers']['rootCount'] != row['after']['layers']['rootCount']:
            events.append((*row['before']['layers']['rootCountSpan'], 'count'))
    pieces, checks, position = [], [], 0
    for start, end, kind in sorted(events):
        assert start >= position
        pieces.append(re.escape(before[position:start]))
        if kind == 'removed':
            pieces.append(replay)
            checks.append(('retained', selected_range))
        elif kind == 'inserted':
            pieces.extend([replay, re.escape(before[first:last]), rb'\n((?:' + scalar + rb')*?)'])
            checks.extend([('state', selected_range[0]), ('state', boundary)])
        elif kind == 'count':
            prefix = before[start:end].split(b':')[0]
            pieces.append(re.escape(prefix + b': ' + str(row['after']['layers']['rootCount']).encode()))
        position = end
    pieces.append(re.escape(before[position:]))
    match = re.fullmatch(b''.join(pieces), after)
    assert match is not None, (row['result'], 'Changed complete source owner, unrelated bytes or non-scalar replay')
    for fragment, (kind, at) in zip(match.groups(), checks):
        commands = list(parsed(fragment))
        if kind == 'state':
            for command in commands:
                state = input_state(document, items, at, command.is_pseudo_comment)
                assert state.get(key(command.command)) == scalar_value(command), (row['result'], 'Replay differs from original boundary', command.command)
        else:
            position = 0
            for item in items[at[0]:at[1]]:
                operator = getattr(item, 'command', None)
                if operator in SCALARS | COLORS:
                    expected = [(item.is_pseudo_comment, scalar_value(item))]
                elif operator == 'XW' and int(item.tokens[0]) == 1:
                    expected = [(True, value) for value in restored_style(document, item.tokens[1].decode('latin1')).values()]
                else:
                    continue
                actual = [(value.is_pseudo_comment, scalar_value(value)) for value in commands[position:position + len(expected)]]
                assert sorted(actual, key=repr) == sorted(expected, key=repr), (row['result'], 'Removed-owner state replay differs')
                position += len(expected)
            assert position == len(commands)


def inherited_flags(original, changed, items, span, boundary, row):
    """Move all contour-state observations with the selected owner in both views."""
    for private in (False, True):
        moves, values = flags(original, private=private, opacity=row['source'].startswith('synthetic'))
        mapped = {id(item): value for item, value in zip(moves, values)}
        moved = [mapped[id(item)] for item in items[span[0]:span[1]] if id(item) in mapped]
        expected = []
        for index in range(len(items) + 1):
            if index == boundary:
                expected.extend(moved)
            if index < len(items) and not span[0] <= index < span[1] and id(items[index]) in mapped:
                expected.append(mapped[id(items[index])])
        assert expected == flags(changed, private=private, opacity=row['source'].startswith('synthetic'))[1], (row['result'], 'Moved or retained contour state changed')


def views(inkai, source, target, nodes, expected, selected, row):
    """Relocate complete SVG parents and compare resolved appearances and resources."""
    for mode in (('printing',) if row['source'].startswith('synthetic') else ('native', 'printing')):
        before = etree.fromstring(inkai.to_svg(str(source)) if mode == 'native' else etree.tostring(printable_svg(inkai, source)))
        after = etree.fromstring(inkai.to_svg(str(target)) if mode == 'native' else etree.tostring(printable_svg(inkai, target)))
        elements = {0: before}

        def bind(index):
            """Match explicit native parent topology to independently generated SVG."""
            children = svg_children(elements[index])
            visible = [(kind, value) for kind, value in nodes[index]['children'] if kind != 'path' or value[0]]
            assert len(children) == len(visible), (row['result'], mode, index, 'Unqualified SVG/native owner mapping')
            for (kind, value), child in zip(visible, children):
                if kind == 'node':
                    elements[value] = child
                    bind(value)

        bind(0)
        node = elements[selected]
        node.getparent().remove(node)
        parent = expected[selected]['parent']
        siblings = expected[parent]['children']
        offset = sum(kind != 'path' or value[0] for kind, value in siblings[:siblings.index(('node', selected))])
        children = svg_children(elements[parent])
        if offset == len(children):
            elements[parent].append(node)
        else:
            children[offset].addprevious(node)
        assert before.attrib == after.attrib
        if [signature(node, before) for node in svg_children(before)] != [signature(node, after) for node in svg_children(after)]:
            raster_check(before, after, target.with_suffix('.' + mode))
            inactive_stroke(before)
            inactive_stroke(after)
            assert [signature(node, before) for node in svg_children(before)] == [signature(node, after) for node in svg_children(after)], (row['result'], mode, 'Moved or enclosing active appearance changed')


def verify(inkai, source, target, row):
    """Bind source owners, requested parents, exact bytes, both alternatives and flags."""
    before, after = source.read_bytes(), target.read_bytes()
    original = inventory(inkai, source, row['before']['pairs'])
    changed = inventory(inkai, target, row['after']['pairs'])
    verified_inventory(inkai, source, row['before']['layers'])
    verified_inventory(inkai, target, row['after']['layers'])
    items, nodes = tree(original, list(range(len(row['before']['pairs']))))
    selected, first, last = owner(before, items, nodes, row['span'], row['selected'])
    anchor, anchor_start, anchor_end = owner(before, items, nodes, row['anchorSpan'], row['anchor'])
    assert row['operation'] == ('layer' if nodes[selected]['kind'] == 'Lb' else 'group')
    boundary = anchor_end if row['destination'] == 'after' else nodes[anchor]['last']
    if row['destination'] == 'after':
        assert row['position'] == row['anchorSpan'][1]
    else:
        if nodes[anchor]['kind'] == 'Lb':
            # These declared wrappers have an exact closing LB/comment suffix;
            # parsing a truncated layer makes the oracle append an EOF record.
            assert re.fullmatch(rb'LB\s+%AI5_EndLayer--', before[row['position']:row['anchorSpan'][1]])
        else:
            assert before[row['position']:].split(None, 1)[0] == b'U'
            prefix = list(body(parsed(before[row['anchorSpan'][0]:row['position'] + 1])))
            assert normalized(prefix) == normalized(items[anchor_start:boundary + 1])
    expected = moved_tree(nodes, selected, anchor, row)
    order = pair_order(expected)
    _, actual = tree(changed, order)
    assert topology(actual) == topology(expected), (row['result'], 'Incorrect parent or child ordering')
    assert row['after']['layers']['rootCount'] == sum(expected[child]['kind'] == 'Lb' for kind, child in expected[0]['children'] if kind == 'node')
    for index, source_index in enumerate(order):
        old, new = row['before']['pairs'][source_index], row['after']['pairs'][index]
        assert before[old['start']:old['end']] == after[new['start']:new['end']]
    exact_bytes(before, after, original, items, (first, last), boundary, row)
    inherited_flags(original, changed, items, (first, last), boundary, row)
    views(inkai, source, target, nodes, expected, selected, row)


def main():
    """Require exact fixed transactions, pinned fixtures and unchanged reader code."""
    if not __debug__:
        raise RuntimeError('Run verification without assertion stripping')
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--inkai-source', required=True, type=Path)
    parser.add_argument('--output', default=Path('test/corpus/output/subtree-movement'), type=Path)
    args = parser.parse_args()
    assert subprocess.check_output(['git', '-C', str(args.inkai_source), 'rev-parse', 'HEAD'], text=True).strip() == REVISION
    assert not subprocess.check_output(['git', '-C', str(args.inkai_source), 'status', '--porcelain', '--untracked-files=no'], text=True).strip()
    sys.path.insert(0, str(args.inkai_source.resolve()))
    inkai = importlib.import_module('inkai')
    manifest = {entry['file']: entry for entry in json.loads(Path('test/corpus/manifest.json').read_text())['files']}
    programs = {name: pinned_program(name, manifest) for name in FILES}
    rows = json.loads((args.output / 'report.json').read_text())
    expected, checked = requests(), []
    assert len(rows) == len(expected) == 51 and {(row['source'], row['operation'], row['variant']) for row in rows} == expected.keys()
    with tempfile.TemporaryDirectory(prefix='aikit-subtree-movement-') as temporary:
        for row in rows:
            assert tuple(row[key] for key in ('selected', 'destination', 'anchor', 'inheritParentFlags', 'rejected')) == expected[row['source'], row['operation'], row['variant']]
            assert row['original'] == row['source'] + '.' + row['operation'] + '.original.ps'
            assert row['result'] == row['source'] + '.' + row['operation'] + '.' + row['variant'] + '.ps'
            source, target = args.output / row['original'], args.output / row['result']
            if row['source'].startswith('synthetic'):
                assert row['recipe'] is None and hashlib.sha256(source.read_bytes()).hexdigest() == SYNTHETIC[row['source']]
            else:
                provenance(inkai, source, row, programs, Path(temporary))
            if row['rejected']:
                assert row['issue'] and source.read_bytes() == target.read_bytes() and row['before'] == row['after']
                reason = 'explicit inheritParentFlags' if row['variant'] in ('reject-parent', 'reject-cross') else 'unresolved native style state: fill' if row['source'].startswith('synthetic') else 'unknown inherited printing'
                assert reason in row['issue']
            else:
                assert row['issue'] is None
                verify(inkai, source, target, row)
            checked.append(row['result'])
            print(row['result'], 'passed', flush=True)
    (args.output / 'independent-report.json').write_text(json.dumps(dict(oracleRevision=REVISION, transactions=checked, derivedRealMoves=24, syntheticMoves=16, refusals=11), indent=2) + '\n')


if __name__ == '__main__':
    main()
