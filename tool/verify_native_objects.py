#!/usr/bin/env python3
"""Verify attached metadata and identity transactions through unchanged pinned inkai."""

import argparse
import copy
import hashlib
import importlib
import json
import re
from pathlib import Path
import subprocess
import sys

from corpus_support import REVISION, native_programs
from verify_live_shapes import GEOMETRY, walk_body
from verify_native_artwork_movement import source_commands
from verify_native_group_lifecycle import ATTRIBUTES, PAINT, attributes, parent
from verify_native_layers import commands, layers
from verify_native_path_lifecycle import checked_count, patch
from verify_native_structure import parsed

SYNTHETIC_SHA256 = '15ff3519fdb14215fe3365d31143aa83708312929b6e5c54deddd0c4cbd48be6'
METADATA = {'_type', 'AI10_ArtUID', 'AIArtName', 'Object name', 'BBAccumRotation'}


def inventory(document):
    """Associate direct dictionaries after complete objects, observing saved state."""
    items = list(walk_body(document.trailer))
    headers = layers(document)
    openings = {layer['first']: layer for layer in headers}
    header_items = {index for layer in headers for index in range(layer['first'] + 1, layer['last'] - len(layer['body']))}
    roots, stack, state, geometry = [], [], {}, []
    count, previous = None, None
    for position, item in enumerate(items):
        if position in header_items:
            previous = None
            continue
        operator = getattr(item, 'command', None)
        operands = tuple(getattr(item, 'tokens', []))
        private = getattr(item, 'is_pseudo_comment', False)
        children = stack[-1]['children'] if stack else roots
        if isinstance(item, dict) and item.get('_type') == 'ArtDictionary':
            if previous is not None:
                previous['metadata'] = item
            if item.keys() - METADATA:
                state.clear()
            previous = None
            continue
        previous = None
        if operator in ATTRIBUTES:
            key = 'fill' if operator in ('g', 'k', 'Xa') else 'stroke' if operator in ('G', 'K', 'XA') else operator
            state[key] = (operator, operands)
        elif operator == 'Lb':
            header = openings[position]
            node = dict(kind='layer', name=header['name'], identifier=header['identifier'], attributes=header['attributes'], expanded=header['expanded'], children=[])
            children.append(node)
            stack.append(node)
        elif operator in ('u', '*u', 'q'):
            node = dict(kind={'u': 'group', '*u': 'compound', 'q': 'clip'}[operator], flags={key: state[key] for key in ('A', 'Xw') if key in state}, private=private, children=[], metadata=None, first=position)
            children.append(node)
            stack.append(node)
        elif operator in ('LB', 'U', '*U', 'Q'):
            node = stack.pop()
            assert node['kind'] == {'LB': 'layer', 'U': 'group', '*U': 'compound', 'Q': 'clip'}[operator]
            if operator != 'LB':
                node['commands'] = commands(items[node.pop('first'):position + 1])
                previous = node
        elif operator in GEOMETRY:
            geometry.append((operator, operands, private))
        elif operator == 'As':
            assert count is None and len(operands) == 1
            count = int(operands[0])
        elif operator in PAINT and geometry:
            node = dict(kind='path', geometry=geometry, paint=operator, private=private, count=count, state=dict(state), metadata=None, commands=geometry + [(operator, operands, private)])
            children.append(node)
            previous = node
            geometry, count = [], None
        else:
            state.clear()
    assert not stack and not geometry and count is None
    return roots


def objects(tree):
    """List artwork in lexical order, without conflating layer-header dictionaries."""
    result = []
    for node in tree:
        if node['kind'] != 'layer':
            result.append(node)
        result.extend(objects(node.get('children', [])))
    return result


def semantic(tree):
    """Drop trace-only syntax after separately validating source span preservation."""
    return [{key: semantic(value) if key == 'children' else value for key, value in node.items() if key != 'commands'} for node in tree]


def checked_inventory(inkai, path, report):
    """Bind all reported source/dictionary/count spans to independent parsed owners."""
    from inkai.parser.streamreader import dec

    data = path.read_bytes()
    tree = inventory(inkai.parse(str(path)))
    nodes = objects(tree)
    assert len(nodes) == len(report), (path, len(nodes), len(report))
    for node, span in zip(nodes, report):
        assert node['kind'] == span['kind'] and node['private'] == span['private']
        assert source_commands(data, dict(start=span['start'], end=span['artworkEnd']), span['private']) == node['commands']
        if span['dictionary'] is None:
            assert span['end'] == span['artworkEnd'] and node['metadata'] is None
        else:
            start, end = span['dictionary']
            assert span['artworkEnd'] <= start < end == span['end']
            assert parsed(data[span['artworkEnd']:end]) == [node['metadata']]
            assert parsed(data[start:end]) == [node['metadata']]
        identifier = (node['metadata'] or {}).get('AI10_ArtUID')
        assert identifier == (dec(bytes(span['identifier'])) if span['identifier'] is not None else None)
        if span['identifierSpan'] is not None:
            value = data[slice(*span['identifierSpan'])]
            assert parsed(b'/ArtDictionary : /XMLUID : ' + value + b' ; (AI10_ArtUID) , ;') == [{'_type': 'ArtDictionary', 'AI10_ArtUID': identifier}]
        if node['kind'] == 'path':
            checked_count(data, span['count'], node['count'])
    return tree, nodes


def expected_tree(tree, nodes, row):
    """Apply only the requested topology change and declared fresh identities."""
    tree, nodes = copy.deepcopy((tree, nodes))
    selected, operation = row['selected'], row['operation']
    if operation.startswith('duplicate-'):
        node = nodes[selected[0]]
        memo = {}
        duplicate = copy.deepcopy(node, memo)
        for replacement in row['identifiers']:
            copied = memo[id(nodes[replacement['object']])]
            copied['metadata']['AI10_ArtUID'] = bytes(replacement['bytes']).decode()
        siblings, index = parent(tree, node)
        siblings.insert(index + 1, duplicate)
    elif operation == 'remove-path':
        siblings, index = parent(tree, nodes[selected[0]])
        siblings.pop(index)
    elif operation == 'reorder-paths':
        slots = sorted(selected, key=lambda index: row['before'][index]['start'])
        replacements = [(parent(tree, nodes[slot]), nodes[source]) for slot, source in zip(slots, selected)]
        for (siblings, index), replacement in replacements:
            siblings[index] = replacement
    else:
        assert operation == 'move-path'
        siblings, index = parent(tree, nodes[selected[0]])
        moved = siblings.pop(index)
        siblings, index = parent(tree, nodes[row['anchor']])
        siblings.insert(index + 1, moved)
    return semantic(tree)


def copied_bytes(before, row, index):
    """Require an exact original object with only declared copied IDs replaced."""
    span = row['before'][index]
    edits = []
    for replacement in row['identifiers']:
        owner = row['before'][replacement['object']]
        if span['start'] <= owner['start'] < span['end']:
            start, end = owner['identifierSpan']
            encoded = b'(' + b''.join(b'\\%03o' % byte for byte in replacement['bytes']) + b')'
            edits.append((start - span['start'], end - span['start'], encoded))
    return patch(before[span['start']:span['end']], edits)


def verify_bytes(before, after, row, nodes):
    """Constrain every changed byte to owned objects, counts and source assignments."""
    operation, selected, spans = row['operation'], row['selected'], row['before']
    edits = []
    if operation.startswith('duplicate-'):
        index = selected[0]
        edits.append((spans[index]['end'], spans[index]['end'], ('copy-count', index)))
    elif operation == 'remove-path' or operation == 'move-path':
        index = selected[0]
        span = spans[index]
        edits.append((span['start'], span['end'], ('space', index)))
        if span['count'] is not None:
            edits.append((*span['count'], ('space', index)))
        if operation == 'move-path':
            position = spans[row['anchor']]['end']
            edits.append((position, position, ('copy-count', index)))
    else:
        assert operation == 'reorder-paths'
        slots = sorted(selected, key=lambda index: spans[index]['start'])
        for slot, source in zip(slots, selected):
            edits.append((spans[slot]['start'], spans[slot]['end'], ('copy', source)))
            assert spans[slot]['count'] is not None and spans[source]['count'] is not None
            edits.append((*spans[slot]['count'], ('count', source)))
    original_assignments = {value for value in commands(parsed(before)) if value[0] in ATTRIBUTES}
    position, pattern, expected = 0, b'', []
    assignment = rb'[ \t\r\n0-9.eE+\-\[\]A-Za-z]*'
    for start, end, (kind, index) in sorted(edits):
        assert position <= start <= end <= len(before)
        span = spans[index]
        count = checked_count(before, span['count'], nodes[index].get('count')) if span['kind'] == 'path' else b''
        value = b' ' if kind == 'space' else count if kind == 'count' else (count if kind == 'copy-count' else b'') + copied_bytes(before, row, index)
        replacement = re.escape(value)
        if kind.startswith('copy'):
            replacement = assignment + replacement + assignment
        pattern += re.escape(before[position:start]) + b'(' + replacement + b')'
        expected.append((kind, value))
        position = end
    match = re.fullmatch(pattern + re.escape(before[position:]), after)
    assert match is not None, 'Unselected bytes or copied source changed'
    for (kind, value), fragment in zip(expected, match.groups()):
        if kind.startswith('copy'):
            assert fragment.count(value) == 1
            prefix, suffix = fragment.split(value)
            assert all(command in original_assignments for command in attributes(prefix) + attributes(suffix))
        else:
            assert fragment == value


def main():
    """Verify all required transactions and real dependent-owner rejection cases."""
    if not __debug__:
        raise RuntimeError('Run verification without assertion stripping')
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--inkai-source', required=True, type=Path)
    parser.add_argument('--output', default=Path('test/corpus/output/objects'), type=Path)
    args = parser.parse_args()
    assert subprocess.check_output(['git', '-C', str(args.inkai_source), 'rev-parse', 'HEAD'], text=True).strip() == REVISION
    assert not subprocess.check_output(['git', '-C', str(args.inkai_source), 'status', '--porcelain', '--untracked-files=no'], text=True).strip()
    sys.path.insert(0, str(args.inkai_source.resolve()))
    inkai = importlib.import_module('inkai')
    rows = json.loads((args.output / 'report.json').read_text())
    expected = {'synthetic-identity.' + operation + '.ps' for operation in ('duplicate-path', 'duplicate-group', 'remove-path', 'reorder-paths', 'move-path')}
    expected |= {'layers_and_sublayers.ai.reject-' + operation + '.ps' for operation in ('duplicate-path', 'remove-path', 'reorder-paths', 'duplicate-group', 'remove-group', 'ungroup')}
    assert len(rows) == 11 and {row['result'] for row in rows} == expected
    manifest = json.loads(Path('test/corpus/manifest.json').read_text())['files']
    requests = {
        'duplicate-path': ([1], None, [(1, b'copied_path')]),
        'duplicate-group': ([0], None, [(0, b'copied_group'), (1, b'copied_a'), (2, b'copied_b')]),
        'remove-path': ([3], None, []),
        'reorder-paths': ([2, 1], None, []),
        'move-path': ([1], 3, []),
    }
    checked = []
    for row in rows:
        source, target = args.output / row['original'], args.output / row['result']
        before, after = source.read_bytes(), target.read_bytes()
        if row['source'] == 'synthetic-identity':
            assert hashlib.sha256(before).hexdigest() == SYNTHETIC_SHA256
            selected, anchor, identifiers = requests[row['operation']]
            assert row['selected'] == selected and row['anchor'] == anchor
            assert row['identifiers'] == [dict(object=index, bytes=list(value)) for index, value in identifiers]
        else:
            entry = next(value for value in manifest if value['file'] == row['source'])
            artwork = Path('test/corpus/files', row['source'])
            data = artwork.read_bytes()
            assert len(data) == entry['size'] and hashlib.sha256(data).hexdigest() == entry['sha256']
            assert before in native_programs(artwork)
        tree, nodes = checked_inventory(inkai, source, row['before'])
        changed, _ = checked_inventory(inkai, target, row['after'])
        if row['operation'].startswith('reject-'):
            assert before == after
            assert [nodes[index]['metadata'] for index in row['selected']] == [{'_type': 'ArtDictionary'}] * 3
            group = row['before'][row['selected'][0]]
            following = commands(parsed(before[group['end']:]))
            assert following[0][:2] == ('XW', (b'9', b''))
        else:
            assert expected_tree(tree, nodes, row) == semantic(changed), row['result']
            verify_bytes(before, after, row, nodes)
        checked.append(row['result'])
        print(row['result'], 'passed', flush=True)
    (args.output / 'independent-report.json').write_text(json.dumps(dict(oracleRevision=REVISION, transactions=checked, edits=5, dependentRejections=6), indent=2) + '\n')


if __name__ == '__main__':
    main()
