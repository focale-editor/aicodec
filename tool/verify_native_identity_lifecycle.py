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
from verify_native_document_settings import objects as setup_objects
from verify_native_group_lifecycle import check_bytes as group_bytes, parent
from verify_native_layer_lifecycle import verify_bytes as layer_bytes
from verify_native_layers import verified_inventory
from verify_native_objects import checked_inventory, semantic
from verify_native_path_lifecycle import patch

SYNTHETIC_SHA256 = '8b7fda23e237d357ddb1d38b31e926dd0e65e6b2f130c332be660062dfc5d5c6'
RESERVATION_SOURCE = 'units-20x40mm_origin_topleft_CC.ai'
RESERVATION = b'/XMLUID : (reserved) ; (UnknownIdentity) ,\n'


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
    for label in ('reserved', RESERVATION_SOURCE):
        for operation in ('copy', 'reject-copy'):
            layer_ids = [(0, 'Copy_A'), (1, 'Copy_A1')] if label == 'reserved' else [(0, 'Copy_CC')]
            object_ids = requests['copy-root.ps'][4] if label == 'reserved' else []
            if operation == 'reject-copy':
                layer_ids[0] = (0, 'reserved')
            requests[label + '.' + operation + '.ps'] = (operation, [0], [], layer_ids, object_ids)
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
    expected = {'copy-root.ps', 'copy-batch.ps', 'remove-root.ps', 'remove-all.ps', 'remove-paths.ps', 'remove-group.ps'}
    expected |= {label + '.' + operation + '.ps' for label in ('reserved', RESERVATION_SOURCE) for operation in ('copy', 'reject-copy')}
    assert len(rows) == len(expected) == 10 and {row['result'] for row in rows} == expected
    checked = []
    for row in rows:
        verify_request(row)
        source = args.output / row['original']
        before = source.read_bytes()
        if row['source'] == 'synthetic':
            assert row['original'] == 'original.ps' and row['result'] in expected and not row['result'].startswith(('reserved.', RESERVATION_SOURCE))
            assert hashlib.sha256(before).hexdigest() == SYNTHETIC_SHA256
        else:
            from inkai.parser.hierarchy_objects import Document

            assert row['source'] in ('reserved', RESERVATION_SOURCE)
            assert row['result'] == row['source'] + '.' + row['operation'] + '.ps'
            assert row['original'] == row['result'][:-3] + '.original.ps'
            assert before.count(RESERVATION) == 1
            roots = list(setup_objects(inkai.parse(str(source)).setup))
            if row['source'] == 'reserved':
                envelope = b'/Dictionary : ' + RESERVATION + b' ;\n'
                assert before.count(envelope) == 1
                assert hashlib.sha256(before.replace(envelope, b'', 1)).hexdigest() == SYNTHETIC_SHA256
                owners = [item for item in roots if isinstance(item, dict) and 'UnknownIdentity' in item]
                assert owners == [{'_type': 'Dictionary', 'UnknownIdentity': 'reserved'}]
            else:
                manifest = json.loads(Path('test/corpus/document_manifest.json').read_text())['files']
                entry = next(item for item in manifest if item['file'] == RESERVATION_SOURCE)
                original = Path('test/corpus/files', RESERVATION_SOURCE).read_bytes()
                assert len(original) == entry['size'] and hashlib.sha256(original).hexdigest() == entry['sha256']
                assert before.replace(RESERVATION, b'', 1) == original
                owners = [item for item in roots if isinstance(item, Document)]
                assert len(owners) == 1 and owners[0].Recorded['UnknownIdentity'] == 'reserved'
        target = args.output / row['result']
        after = target.read_bytes()
        verified_inventory(inkai, source, row['before']['layers'])
        verified_inventory(inkai, target, row['after']['layers'])
        tree, objects = checked_inventory(inkai, source, row['before']['objects'])
        changed, _ = checked_inventory(inkai, target, row['after']['objects'])
        if row['operation'] == 'reject-copy':
            assert before == after
            assert row['layerIdentifiers'][0]['bytes'] == list(b'reserved')
        else:
            assert expected_tree(tree, objects, row) == semantic(changed), row['result']
            verify_bytes(before, after, row, objects)
        if row['operation'] not in ('copy', 'remove-layers'):
            assert row['before']['layers']['rootCount'] == row['after']['layers']['rootCount']
        checked.append(row['result'])
        print(row['result'], 'passed', flush=True)
    (args.output / 'independent-report.json').write_text(json.dumps(dict(oracleRevision=REVISION, transactions=checked, copies=4, removals=4, collisionRejections=2), indent=2) + '\n')


if __name__ == '__main__':
    main()
