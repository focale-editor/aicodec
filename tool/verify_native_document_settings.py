#!/usr/bin/env python3
"""Compare document settings and native owners with the pinned independent reader."""

import argparse
import hashlib
import importlib
import json
from pathlib import Path
import subprocess
import sys

from corpus_support import REVISION, native_programs


def objects(value):
    """Traverse sections without treating nested dictionaries as root owners."""
    from inkai.parser.consts import Section

    if isinstance(value, Section):
        yield from objects(value.children)
    elif isinstance(value, list):
        for child in value:
            yield from objects(child)
    else:
        yield value


def verify(inkai, native, row):
    """Check declared values without using the reference reader's inferred defaults."""
    from inkai.parser.hierarchy_objects import Document, AI11TextDocument
    from inkai.parser.units import header_comments_to_units

    document = inkai.parse(str(native))
    names = {'AI5_RulerUnits', 'AI24_RulerUnitsLarge', 'AI24_LargeCanvasScale', 'Canvassize', 'AI3_TemplateBox', 'PageOrigin'}
    expected_header = {key: list(map(float, value)) for key, value in document.header.items() if key in names}
    assert row['header'] == expected_header, (native.name, row['header'], expected_header)
    labels = {'in': 'inches', 'mm': 'millimeters', 'pt': 'points', 'pc': 'picas', 'cm': 'centimeters', 'px': 'pixels', 'ft,in': 'feetAndInches', 'm': 'meters', 'yd': 'yards', 'ft': 'feet'}
    ordinary = document.header.get('AI5_RulerUnits', [''])[0]
    large = document.header.get('AI24_RulerUnitsLarge', [''])[0]
    expected_unit = labels.get(header_comments_to_units(ordinary, large)) if ordinary or large else None
    assert row['rulerUnit'] == expected_unit
    setup = list(objects(document.setup))
    owners = [item for item in [*setup, *objects(document.trailer)] if isinstance(item, Document)]
    assert row['documents'] == len(owners)
    boards = []
    for owner, record in enumerate(owners):
        for index, board in enumerate(record.Recorded.get('ArtboardArray', [])):
            first, second = board['PositionPoint1'], board['PositionPoint2']
            origin = board.get('RulerOrigin')
            boards.append({
                'document': owner, 'index': index, 'name': board['Name'],
                'identifier': board.get('ArtboardUUID'), 'selected': board.get('IsArtboardSelected', False),
                'bounds': [first.x, second.y, second.x, first.y],
                'rulerOrigin': list(origin) if origin is not None else None,
            })
    assert row['artboards'] == boards, native.name
    origins = [list(item.RulerOrigin) for item in setup if isinstance(item, AI11TextDocument) and item.RulerOrigin is not None]
    assert row['textRulerOrigins'] == origins, native.name
    return len(expected_header), len(boards), len(origins)


def main():
    """Require the complete baseline and nine pinned modern units/origin fixtures."""
    if not __debug__:
        raise RuntimeError('Run verification without assertion stripping')
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--inkai-source', required=True, type=Path)
    parser.add_argument('--output', default=Path('test/corpus/output/document-settings'), type=Path)
    args = parser.parse_args()
    assert subprocess.check_output(['git', '-C', str(args.inkai_source), 'rev-parse', 'HEAD'], text=True).strip() == REVISION
    assert not subprocess.check_output(['git', '-C', str(args.inkai_source), 'status', '--porcelain', '--untracked-files=no'], text=True).strip()
    sys.path.insert(0, str(args.inkai_source.resolve()))
    inkai = importlib.import_module('inkai')
    manifests = {name: json.loads(Path('test/corpus', name).read_text())['files'] for name in ('manifest.json', 'document_manifest.json')}
    rows = json.loads((args.output / 'report.json').read_text())
    assert len(manifests['manifest.json']) == 37 and len(manifests['document_manifest.json']) == 9
    assert len(rows) == 46
    assert {(row['manifest'], row['file'], row['sourceIndex']) for row in rows} == {(name, entry['file'], 0) for name, entries in manifests.items() for entry in entries}
    totals = [0, 0, 0]
    scales = set()
    for row in rows:
        entry = next(entry for entry in manifests[row['manifest']] if entry['file'] == row['file'])
        path = Path('test/corpus/files', row['file'])
        original = path.read_bytes()
        assert len(original) == entry['size'] and hashlib.sha256(original).hexdigest() == entry['sha256']
        native = args.output / row['native']
        assert native.read_bytes() in (native_programs(path) if original.startswith(b'%PDF-') else [inkai.extract(str(path))])
        counts = verify(inkai, native, row)
        totals = [a + b for a, b in zip(totals, counts)]
        scales.update(row['header'].get('AI24_LargeCanvasScale', []))
    assert {1, 10} <= scales
    report = dict(oracleRevision=REVISION, sources=len(rows), headerFields=totals[0], artboards=totals[1], textRulerOrigins=totals[2], canvasScales=sorted(scales))
    (args.output / 'independent-report.json').write_text(json.dumps(report, indent=2) + '\n')
    print(report)


if __name__ == '__main__':
    main()
