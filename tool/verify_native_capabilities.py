#!/usr/bin/env python3
"""Verify capability locations, ownership and inventory with independent readers."""

import argparse
import hashlib
import importlib
import json
from pathlib import Path
import re
import subprocess
import sys

from pypdf import PdfReader

from corpus_support import REVISION, native_programs


def body_operators(value):
    """Include declarative art nested inside text frame and hierarchy objects."""
    from inkai.parser.consts import Section
    from inkai.parser.hierarchy_objects import HierarchyObject
    from inkai.parser.operators import Operator

    if isinstance(value, Operator):
        yield value
    elif isinstance(value, Section):
        yield from body_operators(value.children)
    elif isinstance(value, HierarchyObject):
        yield from body_operators(vars(value))
    elif isinstance(value, dict):
        for item in value.values():
            yield from body_operators(item)
    elif isinstance(value, (list, tuple)):
        for item in value:
            yield from body_operators(item)


def owners(path):
    """Read catalog/page membership independently of AiCodec's extracted handles."""
    document = PdfReader(path)
    result = []
    for index, owner in enumerate([document.trailer['/Root'], *document.pages]):
        pieces = owner.get('/PieceInfo')
        illustrator = pieces.get_object().get('/Illustrator') if pieces is not None else None
        if illustrator is not None:
            private = illustrator.get_object().get('/Private')
            if private is not None and any(re.fullmatch(r'/(?:AIPrivateData|AIPDFPrivateData)\d+', key) for key in private.get_object()):
                result.append(None if index == 0 else index - 1)
    return result


def main():
    """Check every pinned source and compare supported native body inventories."""
    if not __debug__:
        raise RuntimeError('Run verification without assertion stripping')
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--inkai-source', required=True, type=Path)
    parser.add_argument('--output', default=Path('test/corpus/output/capabilities'), type=Path)
    args = parser.parse_args()
    assert subprocess.check_output(['git', '-C', str(args.inkai_source), 'rev-parse', 'HEAD'], text=True).strip() == REVISION
    assert not subprocess.check_output(['git', '-C', str(args.inkai_source), 'status', '--porcelain', '--untracked-files=no'], text=True).strip()
    sys.path.insert(0, str(args.inkai_source.resolve()))
    inkai = importlib.import_module('inkai')
    manifest = json.loads(Path('test/corpus/manifest.json').read_text())['files']
    rows = json.loads((args.output / 'report.json').read_text())
    assert len(rows) == len(manifest) == 37
    assert {row['file'] for row in rows} == {entry['file'] for entry in manifest}
    count, layers, paths = 0, 0, 0
    for entry in manifest:
        path = Path('test/corpus/files') / entry['file']
        original = path.read_bytes()
        assert len(original) == entry['size'] and hashlib.sha256(original).hexdigest() == entry['sha256']
        row = next(row for row in rows if row['file'] == entry['file'])
        native_path = args.output / row['native']
        native = native_path.read_bytes()
        if original.startswith(b'%PDF-'):
            independent = native_programs(path)
            assert row['owners'] == owners(path)
            assert all(program == native for program in independent)
        else:
            assert row['owners'] == []
            assert native == inkai.extract(str(path))
        findings = row['findings']
        for finding in findings:
            assert 0 <= finding['start'] < finding['end'] <= len(native), (path.name, finding)
            assert finding['editable'] == (finding['support'] == 'typed' and any(edit['support'] == 'available' for edit in finding['edits']))
            if finding['editable']:
                assert finding['feature'] in ('layer', 'path'), finding
            if finding['support'] == 'preserved':
                assert not finding['editable']
            count += 1
        body = list(body_operators(inkai.parse(str(native_path)).trailer))
        expected_layers = [item for item in body if getattr(item, 'command', None) == 'Lb']
        expected_paths = [item for item in body if getattr(item, 'command', None) == 'm' and not item.is_pseudo_comment]
        reported_layers = [finding for finding in findings if finding['feature'] == 'layer' and finding['support'] == 'typed']
        reported_paths = [finding for finding in findings if finding['feature'] == 'path' and finding['support'] == 'typed']
        assert len(reported_layers) == len(expected_layers), path.name
        assert len(reported_paths) == len(expected_paths), (path.name, len(reported_paths), len(expected_paths))
        for finding in reported_layers:
            header = native[finding['start']:finding['end']]
            assert re.search(rb'\bLb(?:\s|$)', header) and header.endswith((b'Lb', b'Ln'))
            assert not re.search(rb'\bm\s', header), 'Layer header accidentally includes child geometry'
        for finding in reported_paths:
            geometry = native[finding['start']:finding['end']]
            assert re.match(rb'[-+\d.eE]+\s+[-+\d.eE]+\s+m(?:\s|$)', geometry)
            assert re.search(rb'\b[nNfFsSbB]$', geometry)
        layers += len(reported_layers)
        paths += len(reported_paths)
        expected_incomplete = path.name == 'image_linked_ai8.ai'
        assert row['complete'] == (not expected_incomplete)
        if expected_incomplete:
            assert any(finding['feature'] == 'raster' and finding['support'] == 'unsupported' for finding in findings)
    result = {'oracleRevision': REVISION, 'files': len(rows), 'findings': count, 'layers': layers, 'paths': paths}
    (args.output / 'independent-report.json').write_text(json.dumps(result, indent=2) + '\n')
    print(f'Capabilities: {len(rows)} exact sources, {layers} layer headers and {paths} ordinary paths passed independent checks')


if __name__ == '__main__':
    main()
