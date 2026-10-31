#!/usr/bin/env python3
"""Verify layer subtree movement with pinned inkai and exact native transactions."""

import argparse
import copy
import hashlib
import importlib
import json
from pathlib import Path
import re
import subprocess
import sys

from corpus_support import REVISION, native_programs
from verify_live_shapes import GEOMETRY, walk_body
from verify_native_group_lifecycle import ATTRIBUTES, PAINT, attributes, parent
from verify_native_layers import commands, layers, verified_inventory, verify_insertion
from verify_native_structure import native_values, parsed

SYNTHETIC_SHA256 = 'e916a0352622e057fd9b67452abd20dd4bd200317bfa14688ec155312acd3e81'


def inventory(document):
    """Observe nested objects and persistent paint across native layer boundaries."""
    items = list(walk_body(document.trailer))
    headers = layers(document)
    openings = {layer['first']: layer for layer in headers}
    metadata = {index for layer in headers for index in range(layer['first'] + 1, layer['last'] - len(layer['body']))}
    roots, owners, stack, state, geometry = [], [], [], {}, []
    count = None
    for position, item in enumerate(items):
        if position in metadata:
            continue
        operator = getattr(item, 'command', None)
        operands = tuple(getattr(item, 'tokens', []))
        private = getattr(item, 'is_pseudo_comment', False)
        children = stack[-1]['children'] if stack else roots
        if operator in ATTRIBUTES:
            key = 'fill' if operator in ('g', 'k', 'Xa') else 'stroke' if operator in ('G', 'K', 'XA') else operator
            state[key] = (operator, operands)
        elif operator == 'Lb':
            header = openings[position]
            node = dict(kind='Lb', name=header['name'], identifier=header['identifier'], attributes=header['attributes'], expanded=header['expanded'], children=[])
            children.append(node)
            owners.append(node)
            stack.append(node)
        elif operator in ('u', '*u', 'q'):
            node = dict(kind=operator, flags={key: state[key] for key in ('A', 'Xw') if key in state}, private=private, children=[])
            children.append(node)
            stack.append(node)
        elif operator in ('LB', 'U', '*U', 'Q'):
            assert stack and stack.pop()['kind'].upper() == operator
        elif operator in GEOMETRY:
            geometry.append((operator, operands))
        elif operator == 'As':
            assert count is None and len(operands) == 1
            count = int(operands[0])
        elif operator in PAINT and geometry:
            children.append(dict(kind='path', geometry=geometry, paint=operator, private=private, count=count, state=dict(state)))
            geometry, count = [], None
        else:
            # Uninterpreted appearance state is not assigned guessed defaults.
            # Selected subtrees reject it; untouched opaque source remains exact.
            state.clear()
    assert not stack and not geometry and count is None
    return roots, owners


def expected_tree(tree, owners, row):
    """Apply the declared ownership change to the independently decoded tree."""
    tree, owners = copy.deepcopy((tree, owners))
    selected = row['selected']
    if row['operation'] == 'reorder':
        slots = sorted(selected, key=lambda index: row['before']['layers'][index]['start'])
        replacements = [(parent(tree, owners[slot]), owners[source]) for slot, source in zip(slots, selected)]
        for (siblings, index), replacement in replacements:
            siblings[index] = replacement
    elif row['operation'] == 'duplicate':
        for index in selected:
            memo = {}
            copied = copy.deepcopy(owners[index], memo)
            for field, key in [('identifiers', 'identifier'), ('names', 'name')]:
                for replacement in row[field]:
                    target = memo.get(id(owners[replacement['layer']]))
                    if target is not None:
                        target[key] = bytes(replacement['bytes']).decode() if key == 'identifier' else replacement['bytes']
            siblings, position = parent(tree, owners[index])
            siblings.insert(position + 1, copied)
    elif row['operation'] == 'remove':
        for index in selected:
            siblings, position = parent(tree, owners[index])
            siblings.pop(position)
    else:
        assert row['operation'] in ('after', 'inside') and len(selected) == 1
        moved, anchor = owners[selected[0]], owners[row['anchor']]
        siblings, index = parent(tree, moved)
        siblings.pop(index)
        if row['operation'] == 'inside':
            anchor['children'].append(moved)
        else:
            siblings, index = parent(tree, anchor)
            siblings.insert(index + 1, moved)
    return tree


def copied_bytes(before, row, index):
    """Permit only caller-requested string tokens inside an otherwise exact copy."""
    node = row['before']['layers'][index]
    replacements = []
    for field, key in [('identifiers', 'identifierSpan'), ('names', 'nameSpan')]:
        for replacement in row[field]:
            target = row['before']['layers'][replacement['layer']]
            if node['start'] <= target['start'] < target['end'] <= node['end']:
                encoded = b'(' + b''.join(b'\\%03o' % value for value in replacement['bytes']) + b')'
                replacements.append((*target[key], encoded))
    for replacement in row.get('artworkIdentifiers', []):
        target = row['before']['artwork'][replacement['object']]
        if node['start'] <= target['start'] < target['end'] <= node['end']:
            encoded = b'(' + b''.join(b'\\%03o' % value for value in replacement['bytes']) + b')'
            replacements.append((*target['identifierSpan'], encoded))
    result, position = b'', node['start']
    for start, end, value in sorted(replacements):
        assert position <= start < end <= node['end']
        result += before[position:start] + value
        position = end
    return result + before[position:node['end']]


def verify_bytes(before, after, row):
    """Allow only selected spans, copied source assignments and declared headers."""
    inventory = row['before']
    nodes = inventory['layers']
    edits = [(*span, 'view') for span in inventory['viewSpans']]
    if row['after']['rootCount'] != inventory['rootCount'] and inventory['rootCountSpan'] is not None:
        edits.append((*inventory['rootCountSpan'], 'count'))
    selected = row['selected']
    if row['operation'] == 'reorder':
        slots = sorted(selected, key=lambda index: nodes[index]['start'])
        edits.extend((nodes[slot]['start'], nodes[slot]['end'], ('copy', source)) for slot, source in zip(slots, selected) if slot != source)
    elif row['operation'] == 'duplicate':
        edits.extend((nodes[index]['end'], nodes[index]['end'], ('copy', index)) for index in selected)
    elif row['operation'] == 'remove':
        edits.extend((nodes[index]['start'], nodes[index]['end'], ('remove', index)) for index in selected)
    else:
        index = selected[0]
        node, anchor = nodes[index], nodes[row['anchor']]
        position = anchor['closing'][0] if row['operation'] == 'inside' else anchor['end']
        edits.extend([(node['start'], node['end'], ('remove', index)), (position, position, ('copy', index))])
    original_assignments = {value for value in commands(parsed(before)) if value[0] in ATTRIBUTES}
    # Adjacent slots may have only a newline between them. Require the expected
    # complete copied subtree in each capture rather than guessing that split.
    # Candidate assignment syntax is subsequently checked by the native parser.
    assignment = rb'[ \t\r\n0-9.eE+\-\[\]A-Za-z]*'
    position, pattern = 0, b''
    ordered = sorted(edits)
    for start, end, kind in ordered:
        assert position <= start <= end <= len(before)
        replacement = assignment
        if isinstance(kind, tuple) and kind[0] == 'copy':
            replacement += re.escape(copied_bytes(before, row, kind[1])) + assignment
        elif isinstance(kind, tuple) and kind[0] == 'remove':
            replacement = rb'\s*'
            node = nodes[kind[1]]
            for operator, operands, private in commands(parsed(before[node['start']:node['end']])):
                if operator in ATTRIBUTES:
                    assert not private
                    replacement += rb'\s*'.join(re.escape(value) for value in (*operands, operator.encode())) + rb'\b\s*'
        elif kind == 'view':
            replacement = b''
        elif kind == 'count':
            replacement = re.escape(before[start:end].split(b':')[0] + b': ' + str(row['after']['rootCount']).encode())
        pattern += re.escape(before[position:start]) + b'(' + replacement + b')'
        position = end
    match = re.fullmatch(pattern + re.escape(before[position:]), after)
    assert match is not None, 'Unselected source bytes changed'
    for (_, _, kind), fragment in zip(ordered, match.groups()):
        if kind == 'view':
            assert not fragment
        elif kind == 'count':
            old = before[slice(*inventory['rootCountSpan'])]
            assert fragment == old.split(b':')[0] + b': ' + str(row['after']['rootCount']).encode()
        else:
            action, index = kind
            node = nodes[index]
            source = copied_bytes(before, row, index)
            if action == 'remove':
                assert attributes(fragment) == [value for value in commands(parsed(source)) if value[0] in ATTRIBUTES]
            else:
                assert action == 'copy' and fragment.count(source) == 1
                prefix, suffix = fragment.split(source)
                assert all(value in original_assignments for value in attributes(prefix) + attributes(suffix))
    assert not row['after']['viewSpans']


def main():
    """Check provenance, independent semantics and exact unselected preservation."""
    if not __debug__:
        raise RuntimeError('Run verification without assertion stripping')
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--inkai-source', required=True, type=Path)
    parser.add_argument('--output', default=Path('test/corpus/output/layer-lifecycle'), type=Path)
    args = parser.parse_args()
    assert subprocess.check_output(['git', '-C', str(args.inkai_source), 'rev-parse', 'HEAD'], text=True).strip() == REVISION
    assert not subprocess.check_output(['git', '-C', str(args.inkai_source), 'status', '--porcelain', '--untracked-files=no'], text=True).strip()
    sys.path.insert(0, str(args.inkai_source.resolve()))
    inkai = importlib.import_module('inkai')
    rows = json.loads((args.output / 'report.json').read_text())
    assert len(rows) == 22 and {row['result'] for row in rows} == ({
        'layers_and_sublayers.ai.' + name + '.ps' for name in ('reorder', 'sibling', 'lift-subtree', 'lift-child', 'inside', 'copy-child', 'copy-subtree')
    } | {source + '.' + name + '.ps' for source in ('simple_shapes.ai', 'simple_shapes_cc.ai') for name in ('insert', 'inside')}
    | {'inkscape_minimized_ai7.ai.' + name + '.ps' for name in ('insert', 'remove')}
    | {'synthetic-state.' + name + '.ps' for name in ('reorder', 'after', 'inside', 'empty-parent', 'backwards', 'copy-batch', 'remove', 'remove-child', 'remove-all')})
    manifest = json.loads(Path('test/corpus/manifest.json').read_text())['files']
    verified = set()
    for row in rows:
        source = args.output / row['original']
        target = args.output / row['result']
        before, after = source.read_bytes(), target.read_bytes()
        if row['source'] == 'synthetic-state':
            assert hashlib.sha256(before).hexdigest() == SYNTHETIC_SHA256
        elif row['original'] not in verified:
            assert row['original'] == row['source'] + '.original.ps'
            path = Path('test/corpus/files', row['source'])
            entry = next(entry for entry in manifest if entry['file'] == row['source'])
            data = path.read_bytes()
            assert len(data) == entry['size'] and hashlib.sha256(data).hexdigest() == entry['sha256']
            assert before in (native_programs(path) if data.startswith(b'%PDF-') else [inkai.extract(str(path))])
        original_layers = verified_inventory(inkai, source, row['before'])
        changed_layers = verified_inventory(inkai, target, row['after'])
        if row['operation'] == 'insert':
            assert row['selected'] == [0]
            variant = dict(selected=0, name=list(b'Inserted'), identifier=list(b'AiKit_inserted') if original_layers[0]['identifier'] is not None else None, after=row['after'])
            verify_insertion(before, after, original_layers, changed_layers, row, variant)
        else:
            document = inkai.parse(str(source))
            original, owners = inventory(document)
            changed, _ = inventory(inkai.parse(str(target)))
            if row['operation'] == 'duplicate':
                old_identifiers = {value['AI10_ArtUID'] for value in native_values([document.setup, document.trailer]) if isinstance(value, dict) and 'AI10_ArtUID' in value}
                new_identifiers = [bytes(replacement['bytes']).decode() for replacement in row['identifiers']]
                assert len(set(new_identifiers)) == len(new_identifiers) and not old_identifiers.intersection(new_identifiers)
            assert expected_tree(original, owners, row) == changed, row['result']
            verify_bytes(before, after, row)
        verified.add(row['result'])
        print(row['result'], 'passed', flush=True)
    (args.output / 'independent-report.json').write_text(json.dumps(dict(oracleRevision=REVISION, transactions=sorted(verified), moves=12, prerequisiteInsertions=3, duplications=3, removals=4), indent=2) + '\n')


if __name__ == '__main__':
    main()
