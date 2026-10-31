#!/usr/bin/env python3
"""Verify native shape lifecycle without flattening authoring records to paths."""

import argparse
import hashlib
import importlib
import json
from pathlib import Path
import subprocess
import sys

from corpus_support import REVISION, native_programs
from verify_live_shapes import GEOMETRY, walk_body
from verify_native_group_lifecycle import PAINT
from verify_native_identity_lifecycle import expected_tree as layer_tree, verify_bytes as layer_bytes
from verify_native_layers import commands, verified_inventory
from verify_native_objects import checked_inventory, expected_tree, semantic, verify_bytes
from verify_native_path_lifecycle import checked_count, patch
from verify_native_reference_scope import values
from verify_native_structure import parsed

SYNTHETIC_SHA256 = 'acb387f7dacdb1737d1afa123ba87ade59141486090734f29560ec91842b465f'
FILES = {'circle.ai', 'cmyk_rectangle.ai', 'rgb_rectangle.ai', 'opacity.ai', 'rectangle_with_rounded_corners.ai', 'rectangle-rounded-corners-all-different.ai', 'styles.ai'}
SYNTHETIC = {'duplicate-path', 'remove-path', 'duplicate-group', 'remove-group', 'move-path', 'copy', 'remove-layers'}


def shape_count(items):
    """Count authoring records independently, excluding printable redundancies."""
    return sum(isinstance(item, dict) and 'ai::LiveShape' in item and item['ai::LiveShape'].get('Recorded', True) for item in items)


def normalized(items):
    """Compare every parsed operator and dictionary, including unknown neighbors."""
    return [commands([item])[0] if hasattr(item, 'command') else values(item) for item in items]


def real_edit(inkai, source, target, row):
    """Bind the first native path/dictionary to the full parse and exact source edit."""
    before, after = source.read_bytes(), target.read_bytes()
    items = list(walk_body(inkai.parse(str(source)).trailer))
    changed = list(walk_body(inkai.parse(str(target)).trailer))
    first = next(index for index, item in enumerate(items) if getattr(item, 'command', None) == 'm')
    painted = next(index for index in range(first, len(items)) if getattr(items[index], 'command', None) in PAINT)
    assert all(getattr(item, 'command', None) in GEOMETRY and not item.is_pseudo_comment for item in items[first:painted])
    metadata = items[painted + 1]
    assert isinstance(metadata, dict) and metadata['_type'] == 'ArtDictionary'
    assert metadata['ai::LiveShape'].get('Recorded', True)
    expected_handler = 'ai::Ellipse' if row['source'] == 'circle.ai' else 'ai::Rectangle'
    assert metadata['ai::LiveShape']['ai::LiveShape::HandlerName'] == expected_handler
    span = row['before']['objects'][0]
    assert row['objects'] == [0] and not row['layers'] and not row['artworkIdentifiers'] and not row['layerIdentifiers'] and row['anchor'] is None
    assert span['kind'] == 'path' and span['liveShape'] == expected_handler and not span['private']
    assert span['start'] == span['artworkStart'] < span['artworkEnd'] <= span['dictionary'][0] < span['end'] == span['dictionary'][1]
    assert normalized(parsed(before[span['start']:span['end']])) == normalized(items[first:painted + 2])
    assert parsed(before[slice(*span['dictionary'])]) == [metadata]
    count = next((index for index in range(first - 1, -1, -1) if getattr(items[index], 'command', None) == 'As'), None)
    if span['count'] is None:
        assert count is None
        count_bytes = b''
    else:
        assert count is not None
        assert commands(parsed(before[slice(*span['count'])])) == commands([items[count]])
        count_bytes = checked_count(before, span['count'], int(items[count].tokens[0]))
    if row['operation'] == 'duplicate-path':
        copy = count_bytes + before[span['start']:span['end']] + b'\n'
        assert patch(before, [(span['end'], span['end'], b'\n' + copy)]) == after
        expected = items[:painted + 2] + ([] if count is None else [items[count]]) + items[first:painted + 2] + items[painted + 2:]
    else:
        assert row['operation'] == 'remove-path'
        edits = [(span['start'], span['end'], b' ')]
        if span['count'] is not None:
            edits.append((*span['count'], b' '))
        assert patch(before, edits) == after
        expected = [item for index, item in enumerate(items) if not first <= index <= painted + 1 and index != count]
    assert normalized(expected) == normalized(changed)
    assert shape_count(items) == row['before']['shapes'] and shape_count(changed) == row['after']['shapes']


def synthetic_request(row):
    """Require fixed selections and identity maps independently of generated output."""
    operation = row['operation']
    assert operation in SYNTHETIC and row['result'] == 'synthetic.' + operation + '.ps'
    assert row['layers'] == ([0] if operation in ('copy', 'remove-layers') else [])
    assert row['objects'] == ([] if row['layers'] else [1] if operation.endswith('group') else [0])
    assert row['anchor'] == (3 if operation == 'move-path' else None)
    artwork = [(0, 'copy_rect')] if operation == 'duplicate-path' else [(2, 'copy_child')] if operation == 'duplicate-group' else [(0, 'copy_a'), (2, 'copy_child')] if operation == 'copy' else []
    layer = [(0, 'Copy_A')] if operation == 'copy' else []
    assert row['artworkIdentifiers'] == [dict(object=index, bytes=list(name.encode())) for index, name in artwork]
    assert row['layerIdentifiers'] == [dict(layer=index, bytes=list(name.encode())) for index, name in layer]


def main():
    """Verify seven pinned sources and complete identified synthetic subtrees."""
    if not __debug__:
        raise RuntimeError('Run verification without assertion stripping')
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--inkai-source', required=True, type=Path)
    parser.add_argument('--output', default=Path('test/corpus/output/direct-shapes'), type=Path)
    args = parser.parse_args()
    assert subprocess.check_output(['git', '-C', str(args.inkai_source), 'rev-parse', 'HEAD'], text=True).strip() == REVISION
    assert not subprocess.check_output(['git', '-C', str(args.inkai_source), 'status', '--porcelain', '--untracked-files=no'], text=True).strip()
    sys.path.insert(0, str(args.inkai_source.resolve()))
    inkai = importlib.import_module('inkai')
    manifests = [entry for name in ('manifest.json', 'rotation_manifest.json', 'direct_shape_manifest.json') for entry in json.loads(Path('test/corpus', name).read_text())['files']]
    expected = {name + '.' + operation + '.ps' for name in FILES for operation in ('duplicate-path', 'remove-path')}
    expected |= {'synthetic.' + operation + '.ps' for operation in SYNTHETIC}
    rows = json.loads((args.output / 'report.json').read_text())
    assert len(rows) == len(expected) == 21 and {row['result'] for row in rows} == expected
    checked = []
    for row in rows:
        assert row['original'] == row['source'] + '.original.ps' and row['result'] == row['source'] + '.' + row['operation'] + '.ps'
        source, target = args.output / row['original'], args.output / row['result']
        before, after = source.read_bytes(), target.read_bytes()
        if row['source'] == 'synthetic':
            assert hashlib.sha256(before).hexdigest() == SYNTHETIC_SHA256
            synthetic_request(row)
            tree, objects = checked_inventory(inkai, source, row['before']['objects'])
            changed, _ = checked_inventory(inkai, target, row['after']['objects'])
            if row['operation'] in ('copy', 'remove-layers'):
                assert layer_tree(tree, objects, row) == semantic(changed)
                layer_bytes(before, after, row, objects)
            else:
                request = dict(operation=row['operation'], selected=row['objects'], anchor=row['anchor'], identifiers=row['artworkIdentifiers'], before=row['before']['objects'])
                assert expected_tree(tree, objects, request) == semantic(changed)
                verify_bytes(before, after, request, objects)
            for path, inventory in [(source, row['before']), (target, row['after'])]:
                assert shape_count(walk_body(inkai.parse(str(path)).trailer)) == inventory['shapes']
        else:
            assert row['source'] in FILES
            entry = next(item for item in manifests if item['file'] == row['source'])
            path = Path('test/corpus/files', row['source'])
            data = path.read_bytes()
            assert len(data) == entry['size'] and hashlib.sha256(data).hexdigest() == entry['sha256']
            assert before in (native_programs(path) if data.startswith(b'%PDF-') else [data])
            real_edit(inkai, source, target, row)
        verified_inventory(inkai, source, row['before']['layers'])
        verified_inventory(inkai, target, row['after']['layers'])
        checked.append(row['result'])
        print(row['result'], 'passed', flush=True)
    (args.output / 'independent-report.json').write_text(json.dumps(dict(oracleRevision=REVISION, transactions=checked, realTransactions=14, syntheticTransactions=7), indent=2) + '\n')


if __name__ == '__main__':
    main()
