#!/usr/bin/env python3
"""Check complete CC artboard transactions against original producer programs."""

import argparse
import hashlib
import importlib
import json
from pathlib import Path
import subprocess
import sys

from corpus_support import REVISION, native_programs
from verify_native_artboard_brush_descriptors import descriptor_state, descriptor_bytes
from verify_native_artboard_brushes import brush_state
from verify_native_artboard_lifecycle import requests, verify as verify_lifecycle
from verify_native_artboard_styles import appearance_state
from verify_native_artboard_svg_filters import filter_state, filter_bytes
from verify_native_artboard_symbols import symbols
from verify_native_artboard_text import text_state

SOURCES = ('simple_cc_legacy.ai', 'simple_v2020.ai', 'text_transforms.ai', 'flowtext.ai', 'layers_and_sublayers.ai')


def blend_state(document):
    """Bind Band's endpoint annotations to its first and last of ten saved paths."""
    band = symbols(document).get(b'Band')
    if band is None:
        return None
    groups, paths, endpoints = [], {}, []
    for index, item in enumerate(band.children):
        command = getattr(item, 'command', None)
        if command == 'u':
            groups.append(index)
            paths[index] = 0
        elif command == 'U':
            assert groups
            groups.pop()
        elif command == 's':
            assert groups
            paths[groups[-1]] += 1
        elif isinstance(item, dict) and 'ShapeBlendPathID' in item:
            assert groups and index and band.children[index - 1].command == 's'
            assert item['_type'] == 'ArtDictionary' and item['ShapeBlendPathType'] == 'K'
            endpoints.append((groups[-1], paths[groups[-1]], item))
    assert not groups and len(endpoints) == 2
    first, last = endpoints
    assert first[0] == last[0] and first[1] == 1 and last[1] == paths[first[0]] == 10
    assert first[2]['ShapeBlendPathID'] == 'B' and first[2]['ShapeBlendMatchToBefore'] == 'ALL'
    assert last[2]['ShapeBlendPathID'] == 'A' and last[2]['ShapeBlendMatchToAfter'] == 'ALL'
    assert 'ShapeBlendMatchToAfter' not in first[2] and 'ShapeBlendMatchToBefore' not in last[2]
    return endpoints


def resource_state(document, data, text_parser, stream):
    """Compare all previously qualified producer owners with the edited source."""
    return dict(
        appearances=appearance_state(document),
        brushes=brush_state(document, data),
        descriptors=descriptor_state(document),
        descriptorBytes=descriptor_bytes(data),
        filters=filter_state(document),
        filterBytes=filter_bytes(data),
        text=text_state(document, text_parser, stream),
        blend=blend_state(document),
    )


def main():
    """Require exact provenance, complete originals and thirty prescribed outcomes."""
    if not __debug__:
        raise RuntimeError('Run verification without assertion stripping')
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--inkai-source', required=True, type=Path)
    parser.add_argument('--output', default=Path('test/corpus/output/artboard-complete-sources'), type=Path)
    args = parser.parse_args()
    assert subprocess.check_output(['git', '-C', str(args.inkai_source), 'rev-parse', 'HEAD'], text=True).strip() == REVISION
    assert not subprocess.check_output(['git', '-C', str(args.inkai_source), 'status', '--porcelain', '--untracked-files=no'], text=True).strip()
    sys.path.insert(0, str(args.inkai_source.resolve()))
    inkai = importlib.import_module('inkai')
    text_parser = importlib.import_module('inkai.parser.text').TextDocumentParser
    stream = importlib.import_module('inkai.parser.streamreader').StreamWrapper
    manifest = {
        entry['file']: entry for filename in ('manifest.json', 'artboard_manifest.json')
        for entry in json.loads(Path('test/corpus', filename).read_text())['files']
    }
    rows = json.loads((args.output / 'report.json').read_text())
    expected = {key: value for key, value in requests(SOURCES).items() if key[0] in SOURCES}
    assert len(rows) == len(expected) == 30
    assert {(row['source'], row['variant']) for row in rows} == expected.keys()
    resources, source_hashes = {}, {}
    for name in SOURCES:
        entry, fixture = manifest[name], Path('test/corpus/files', name)
        assert entry['revision'] == REVISION and fixture.stat().st_size == entry['size']
        assert hashlib.sha256(fixture.read_bytes()).hexdigest() == entry['sha256']
        original = args.output / f'{name}.full.original.ps'
        data = original.read_bytes()
        assert native_programs(fixture) == [data], 'The full producer program must remain unmodified'
        source_hashes[name] = hashlib.sha256(data).hexdigest()
        resources[name] = resource_state(inkai.parse(str(original)), data, text_parser, stream)
    checked = []
    for row in rows:
        name, variant = row['source'], row['variant']
        assert row['original'] == f'{name}.full.{expected[name, variant]}.ps'
        assert row['result'] == f'{name}.full.{variant}.ps'
        original, target = args.output / row['original'], args.output / row['result']
        verify_lifecycle(inkai, original, target, row)
        assert resource_state(inkai.parse(str(target)), target.read_bytes(), text_parser, stream) == resources[name]
        checked.append(f'{name}/full/{variant}')
        print(checked[-1], 'passed', flush=True)
    report = dict(oracleRevision=REVISION, nativeSourceSha256=source_hashes, transactions=checked, completeSourceTransactions=30)
    (args.output / 'independent-report.json').write_text(json.dumps(report, indent=2) + '\n')


if __name__ == '__main__':
    main()
