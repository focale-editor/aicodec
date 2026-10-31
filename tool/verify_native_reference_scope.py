#!/usr/bin/env python3
"""Verify CC document metadata preservation and qualified identified removals."""

import argparse
import hashlib
import importlib
from io import BytesIO
import json
from pathlib import Path
import subprocess
import sys

from PIL import ImageCms

from corpus_support import REVISION, native_programs
from verify_native_document_settings import objects as setup_objects
from verify_native_identity_lifecycle import expected_tree, verify_bytes
from verify_native_layers import verified_inventory
from verify_native_objects import checked_inventory, semantic
from verify_native_structure import parsed

SYNTHETIC_SHA256 = 'ab233165a0975e9a3ac9f8e80db8e370488681a2934651677df136e1506aacef'
REFERENCE_SOURCE = 'units-20x40mm_origin_topleft_CC.ai'


def values(value):
    """Compare all independently decoded metadata, including exact profile bytes."""
    from inkai.parser.hierarchy_objects import HierarchyObject

    if isinstance(value, HierarchyObject):
        return values(value.asdict())
    if isinstance(value, dict):
        return {key: values(child) for key, child in value.items()}
    if isinstance(value, (list, tuple)):
        return [values(child) for child in value]
    return value


def documents(inkai, path, spans):
    """Bind document spans to the complete external parse and retain every byte."""
    from inkai.parser.hierarchy_objects import Document

    result = [item for item in setup_objects(inkai.parse(str(path)).setup) if isinstance(item, Document)]
    assert len(result) == len(spans) == 1
    data = path.read_bytes()
    for item, (start, end) in zip(result, spans):
        independent = parsed(data[start:end])
        assert len(independent) == 1 and isinstance(independent[0], Document)
        assert values(independent[0]) == values(item)
    return result


def empty_references(document):
    """Check actual empty reference tables without mirroring the editor's scalar list."""
    recorded = document.Recorded
    assert recorded['DocumentDict/ExportableAssetsKey'] == {'_type': 'Dictionary'}
    assert recorded['SelHatDocTableDict'] == {'_type': 'Dictionary', 'SelHatDocLocalNamesArray': [], 'SelHatDocInterIDsArray': []}
    assert document.NotRecorded['AI11 Ink List Dict']['/attributes/inklst.count'] == 0
    names = set()

    def visit(node):
        name = node['xmlnode-nodename']
        assert node['xmlnode-nodevalue'] == ''
        names.add(name)
        if name in ('variables', 'v:sampleDataSets', 'slices'):
            assert not node['xmlnode-children']
        for child in node['xmlnode-children']:
            visit(child)

    visit(recorded['#document'])
    assert names == {'#document', 'metadata', 'variableSets', 'variableSet', 'variables', 'v:sampleDataSets', 'sfw', 'slices', 'sliceSourceBounds'}


def main():
    """Require every pinned real deletion, injected refusal and synthetic operation."""
    if not __debug__:
        raise RuntimeError('Run verification without assertion stripping')
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--inkai-source', required=True, type=Path)
    parser.add_argument('--output', default=Path('test/corpus/output/reference-scope'), type=Path)
    args = parser.parse_args()
    assert subprocess.check_output(['git', '-C', str(args.inkai_source), 'rev-parse', 'HEAD'], text=True).strip() == REVISION
    assert not subprocess.check_output(['git', '-C', str(args.inkai_source), 'status', '--porcelain', '--untracked-files=no'], text=True).strip()
    sys.path.insert(0, str(args.inkai_source.resolve()))
    inkai = importlib.import_module('inkai')
    manifest = json.loads(Path('test/corpus/document_manifest.json').read_text())['files']
    rows = json.loads((args.output / 'report.json').read_text())
    expected = {entry['file'] + '.remove-layers.ps' for entry in manifest}
    expected |= {REFERENCE_SOURCE + '.' + label + '.reject-remove.ps' for label in ('unknown-reference', 'asset-reference')}
    expected |= {'synthetic.' + operation + '.ps' for operation in ('remove-layers', 'remove-paths', 'remove-groups')}
    assert len(manifest) == 9 and len(rows) == 14 and {row['result'] for row in rows} == expected
    checked = []
    for row in rows:
        source, target = args.output / row['original'], args.output / row['result']
        before, after = source.read_bytes(), target.read_bytes()
        if row['source'] == 'synthetic':
            assert hashlib.sha256(before).hexdigest() == SYNTHETIC_SHA256
            wanted_layers, wanted_objects = {'remove-layers': ([0], []), 'remove-paths': ([], [0]), 'remove-groups': ([], [1])}[row['operation']]
        else:
            name = row['source'].split('.ai', 1)[0] + '.ai'
            entry = next(entry for entry in manifest if entry['file'] == name)
            path = Path('test/corpus/files', name)
            data = path.read_bytes()
            assert len(data) == entry['size'] and hashlib.sha256(data).hexdigest() == entry['sha256']
            original = native_programs(path) if data.startswith(b'%PDF-') else [data]
            if row['operation'] == 'reject-remove':
                key = 'FutureReference' if row['source'].endswith('unknown-reference') else 'ExportedObject'
                payload = f'/XMLUID : (Layer_1) ; ({key}) ,\n'.encode()
                assert before.count(payload) == 1 and before.replace(payload, b'', 1) in original
            else:
                assert before in original
            wanted_layers, wanted_objects = [0], []
        assert row['layers'] == wanted_layers and row['objects'] == wanted_objects
        assert row['layerIdentifiers'] == row['artworkIdentifiers'] == []
        original_documents = documents(inkai, source, row['before']['documents'])
        changed_documents = documents(inkai, target, row['after']['documents'])
        assert values(original_documents) == values(changed_documents)
        for first, second in zip(row['before']['documents'], row['after']['documents']):
            assert before[slice(*first)] == after[slice(*second)]
        verified_inventory(inkai, source, row['before']['layers'])
        verified_inventory(inkai, target, row['after']['layers'])
        tree, objects = checked_inventory(inkai, source, row['before']['objects'])
        changed, _ = checked_inventory(inkai, target, row['after']['objects'])
        document = original_documents[0]
        if row['operation'] == 'reject-remove':
            assert before == after
            reference = document.Recorded.get('FutureReference') if row['source'].endswith('unknown-reference') else document.Recorded['DocumentDict/ExportableAssetsKey']['ExportedObject']
            assert reference == tree[0]['identifier'] == 'Layer_1'
        else:
            empty_references(document)
            assert expected_tree(tree, objects, row) == semantic(changed)
            verify_bytes(before, after, row, objects)
            profile = document.NotRecorded['AI12 Document Profile Data'].decode()
            assert len(profile) == document.NotRecorded['AI12 Document Profile Size']
            assert int.from_bytes(profile[:4], 'big') == len(profile) and profile[36:40] == b'acsp'
            if row['source'] != 'synthetic':
                assert ImageCms.getProfileName(ImageCms.ImageCmsProfile(BytesIO(profile))).strip()
        checked.append(row['result'])
        print(row['result'], 'passed', flush=True)
    (args.output / 'independent-report.json').write_text(json.dumps(dict(oracleRevision=REVISION, transactions=checked, realRemovals=9, syntheticRemovals=3, referenceRejections=2), indent=2) + '\n')


if __name__ == '__main__':
    main()
