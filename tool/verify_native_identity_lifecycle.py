#!/usr/bin/env python3
"""Verify mixed layer/artwork identities and deletions with pinned native decoding."""

import argparse
import copy
import hashlib
import importlib
import json
from pathlib import Path
import subprocess
import sys

from corpus_support import REVISION
from verify_native_group_lifecycle import check_bytes as group_bytes, parent
from verify_native_layer_lifecycle import verify_bytes as layer_bytes
from verify_native_layers import verified_inventory
from verify_native_objects import checked_inventory, semantic
from verify_native_path_lifecycle import patch

SYNTHETIC_SHA256 = '8b7fda23e237d357ddb1d38b31e926dd0e65e6b2f130c332be660062dfc5d5c6'


def layers(tree):
    """Enumerate native layer owners in independent lexical order."""
    result = []
    for node in tree:
        if node['kind'] == 'layer':
            result.append(node)
        result.extend(layers(node.get('children', [])))
    return result


def expected_tree(tree, objects, row):
    """Copy or remove precisely the declared owner, updating only copied IDs."""
    tree, objects = copy.deepcopy((tree, objects))
    owners = layers(tree)
    if row['operation'] == 'copy':
        for index in row['layers']:
            owner = owners[index]
            memo = {}
            copied = copy.deepcopy(owner, memo)
            for replacements, nodes, key in [(row['layerIdentifiers'], owners, 'layer'), (row['artworkIdentifiers'], objects, 'object')]:
                for replacement in replacements:
                    target = memo.get(id(nodes[replacement[key]]))
                    if target is not None:
                        if key == 'layer':
                            target['identifier'] = bytes(replacement['bytes']).decode()
                        else:
                            target['metadata']['AI10_ArtUID'] = bytes(replacement['bytes']).decode()
            siblings, position = parent(tree, owner)
            siblings.insert(position + 1, copied)
    else:
        selected = [owners[index] for index in row['layers']] if row['operation'] == 'remove-layers' else [objects[index] for index in row['objects']]
        for node in selected:
            siblings, position = parent(tree, node)
            siblings.pop(position)
    return semantic(tree)


def verify_request(row):
    """Require fixed requests so missing identity coverage cannot silently pass."""
    requests = {
        'copy-root.ps': ('copy', [0], [], [(0, 'Copy_A'), (1, 'Copy_A1')], [(0, 'Copy_path_a'), (2, 'Copy_path_child'), (1, 'Copy_group_child')]),
        'copy-batch.ps': ('copy', [2, 1], [], [(1, 'Nested_A1'), (2, 'Other_B')], [(2, 'Nested_path'), (1, 'Nested_group'), (3, 'Other_path')]),
        'remove-root.ps': ('remove-layers', [0], [], [], []),
        'remove-all.ps': ('remove-layers', [0, 2, 3], [], [], []),
        'remove-paths.ps': ('remove-paths', [], [0, 2], [], []),
        'remove-group.ps': ('remove-groups', [], [1], [], []),
    }
    operation, selected_layers, selected_objects, layer_ids, object_ids = requests[row['result']]
    assert row['operation'] == operation and row['layers'] == selected_layers and row['objects'] == selected_objects
    assert row['layerIdentifiers'] == [dict(layer=index, bytes=list(value.encode())) for index, value in layer_ids]
    assert row['artworkIdentifiers'] == [dict(object=index, bytes=list(value.encode())) for index, value in object_ids]


def verify_bytes(before, after, row, objects):
    """Reuse independent whole-layer checks and exact artwork deletion boundaries."""
    if row['operation'] in ('copy', 'remove-layers'):
        original = dict(row['before']['layers'], artwork=row['before']['objects'])
        layer_bytes(before, after, dict(
            operation='duplicate' if row['operation'] == 'copy' else 'remove',
            selected=row['layers'], identifiers=row['layerIdentifiers'], artworkIdentifiers=row['artworkIdentifiers'], names=[],
            before=original, after=row['after']['layers'],
        ))
    elif row['operation'] == 'remove-paths':
        edits = []
        for index in row['objects']:
            span = row['before']['objects'][index]
            assert objects[index]['kind'] == 'path'
            edits.append((span['start'], span['end'], b' '))
            if span['count'] is not None:
                edits.append((*span['count'], b' '))
        assert patch(before, edits) == after
    else:
        assert row['operation'] == 'remove-groups'
        group_bytes(before, after, dict(operation='remove', selected=row['objects'], before=row['before']['objects']), objects, [])


def main():
    """Bind every changed identity, metadata owner and unselected byte independently."""
    if not __debug__:
        raise RuntimeError('Run verification without assertion stripping')
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--inkai-source', required=True, type=Path)
    parser.add_argument('--output', default=Path('test/corpus/output/identity-lifecycle'), type=Path)
    args = parser.parse_args()
    assert subprocess.check_output(['git', '-C', str(args.inkai_source), 'rev-parse', 'HEAD'], text=True).strip() == REVISION
    assert not subprocess.check_output(['git', '-C', str(args.inkai_source), 'status', '--porcelain', '--untracked-files=no'], text=True).strip()
    sys.path.insert(0, str(args.inkai_source.resolve()))
    inkai = importlib.import_module('inkai')
    rows = json.loads((args.output / 'report.json').read_text())
    assert len(rows) == 6 and {row['result'] for row in rows} == {'copy-root.ps', 'copy-batch.ps', 'remove-root.ps', 'remove-all.ps', 'remove-paths.ps', 'remove-group.ps'}
    source = args.output / 'original.ps'
    before = source.read_bytes()
    assert hashlib.sha256(before).hexdigest() == SYNTHETIC_SHA256
    checked = []
    for row in rows:
        verify_request(row)
        target = args.output / row['result']
        after = target.read_bytes()
        verified_inventory(inkai, source, row['before']['layers'])
        verified_inventory(inkai, target, row['after']['layers'])
        tree, objects = checked_inventory(inkai, source, row['before']['objects'])
        changed, _ = checked_inventory(inkai, target, row['after']['objects'])
        assert expected_tree(tree, objects, row) == semantic(changed), row['result']
        verify_bytes(before, after, row, objects)
        if row['operation'] not in ('copy', 'remove-layers'):
            assert row['before']['layers']['rootCount'] == row['after']['layers']['rootCount']
        checked.append(row['result'])
        print(row['result'], 'passed', flush=True)
    (args.output / 'independent-report.json').write_text(json.dumps(dict(oracleRevision=REVISION, transactions=checked, copies=2, removals=4), indent=2) + '\n')


if __name__ == '__main__':
    main()
