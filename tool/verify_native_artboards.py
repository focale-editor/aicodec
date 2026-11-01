#!/usr/bin/env python3
"""Check independent artboard state, explicit geometry and untouched native bytes."""

import argparse
from copy import deepcopy
import hashlib
import importlib
import json
from pathlib import Path
import re
import subprocess
import sys

from corpus_support import REVISION, native_programs
from verify_native_path_lifecycle import patch
from verify_native_reference_scope import documents, values

SYNTHETIC = {
    'synthetic': '0a4dbe4eba6deda377af77885a7e28b0205a697abf3632bd0c64e8126da29d39',
    'synthetic-mixed': '9fb44c6ca1163bbafed1752d9c075a1d8ae283baf35e1b401ee23c2ecf69bb33',
}
FIELDS = {'PositionPoint1': [-25, 40], 'PositionPoint2': [2000, -950], 'RulerOrigin': [7000, 7100]}


def requests(names):
    """Pin inspection, geometry, explicit crop/origin choices and expected refusals."""
    result = {}
    for name in names:
        result[name, 'inspection'] = None, False, False, False
        if name.startswith('units-') or name == 'layers_and_sublayers.ai':
            result[name, 'bounds'] = 0, False, False, False
            result[name, 'explicit'] = 0, True, True, False
        else:
            result[name, 'rejected'] = 4 if name.startswith('reuters-') else 0, False, False, True
    for index in range(3):
        result['synthetic', f'board-{index}'] = index, index == 2, index == 1, False
    result['synthetic-mixed', 'board-1'] = 1, True, True, False
    return result


def inventory(data, document, reported):
    """Bind distinct active, selection, crop and history fields to the native owner."""
    recorded = document['Recorded']
    assert reported['active'] == recorded.get('CropAreaActive')
    assert reported['lastId'] == document.get('NotRecorded', {}).get('LastArtboardID')
    boards = recorded['ArtboardArray']
    assert len(reported['boards']) == len(boards)
    for board, actual in zip(boards, reported['boards']):
        assert actual['name'] == board['Name'] and actual['identifier'] == board.get('ArtboardUUID')
        assert actual['selected'] == board.get('IsArtboardSelected', False)
        first, second = board['PositionPoint1'], board['PositionPoint2']
        assert actual['bounds'] == [first[0], second[1], second[0], first[1]]
        assert actual['origin'] == board.get('RulerOrigin')
        for key, spans in actual['coordinates'].items():
            assert len(spans) == len(board[key]) == 2
            assert [float(data[start:end]) for start, end in spans] == board[key]
            assert all(reported['document'][0] <= start < end <= reported['document'][1] for start, end in spans)
    crop = list(re.finditer(rb'(?m)(?:^|(?<=[\r\n]))(%AI3_Cropmarks:([^\r\n]*))', data))
    assert len(crop) == 1
    assert reported['cropSpan'] == [crop[0].start(1), crop[0].end(1)]
    assert reported['crop'] == list(map(float, crop[0][2].split()))


def verify(inkai, source, target, row, cache):
    """Require exactly the requested coordinates while preserving every other field."""
    before, after = source.read_bytes(), target.read_bytes()
    if source not in cache:
        cache[source] = values(documents(inkai, source, [row['before']['document']])[0])
    original = cache[source]
    changed = original if source == target else values(documents(inkai, target, [row['after']['document']])[0])
    inventory(before, original, row['before'])
    inventory(after, changed, row['after'])
    if row['selected'] is None or row['rejected']:
        assert before == after and row['before'] == row['after']
        if row['source'] == 'reuters-preview-dev.ai':
            assert row['before']['active'] == 4 and row['before']['lastId'] == 67
            assert [index for index, board in enumerate(row['before']['boards']) if board['selected']] == [2]
            assert row['before']['crop'] == row['before']['boards'][4]['bounds']
        return
    expected, edits = deepcopy(original), []
    index = row['selected']
    for key in ('PositionPoint1', 'PositionPoint2', *(['RulerOrigin'] if row['origin'] else [])):
        expected['Recorded']['ArtboardArray'][index][key] = FIELDS[key]
        old_spans = row['before']['boards'][index]['coordinates'][key]
        new_spans = row['after']['boards'][index]['coordinates'][key]
        for (start, end), span, wanted in zip(old_spans, new_spans, FIELDS[key]):
            replacement = after[slice(*span)]
            assert float(replacement) == wanted
            edits.append((start, end, replacement))
    assert changed == expected, (row['source'], 'Changed unrelated native document fields')
    if row['crop']:
        assert row['after']['crop'] == [1, 2, 300, 400]
        replacement = after[slice(*row['after']['cropSpan'])]
        assert replacement.split(b':')[0] == before[slice(*row['before']['cropSpan'])].split(b':')[0]
        edits.append((*row['before']['cropSpan'], replacement))
    else:
        assert row['after']['crop'] == row['before']['crop']
    assert patch(before, edits) == after, (row['source'], 'Unexpected artwork, metadata or header edit')


def main():
    """Verify pinned complete originals, source ownership and all declared requests."""
    if not __debug__:
        raise RuntimeError('Run verification without assertion stripping')
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--inkai-source', required=True, type=Path)
    parser.add_argument('--output', default=Path('test/corpus/output/artboards'), type=Path)
    args = parser.parse_args()
    assert subprocess.check_output(['git', '-C', str(args.inkai_source), 'rev-parse', 'HEAD'], text=True).strip() == REVISION
    assert not subprocess.check_output(['git', '-C', str(args.inkai_source), 'status', '--porcelain', '--untracked-files=no'], text=True).strip()
    sys.path.insert(0, str(args.inkai_source.resolve()))
    inkai = importlib.import_module('inkai')
    manifest = {entry['file']: entry for entry in json.loads(Path('test/corpus/artboard_manifest.json').read_text())['files']}
    expected = requests(manifest)
    rows = json.loads((args.output / 'report.json').read_text())
    assert len(manifest) == 6 and len(rows) == len(expected) == 20
    assert {(row['source'], row['variant']) for row in rows} == expected.keys()
    verified, cache, checked = set(), {}, []
    for row in rows:
        name, variant = row['source'], row['variant']
        assert tuple(row[key] for key in ('selected', 'crop', 'origin', 'rejected')) == expected[name, variant]
        assert row['original'] == f'{name}.original.ps'
        assert row['result'] == (row['original'] if row['selected'] is None or row['rejected'] else f'{name}.{variant}.ps')
        source, target = args.output / row['original'], args.output / row['result']
        if name not in verified:
            data = source.read_bytes()
            if name in SYNTHETIC:
                assert hashlib.sha256(data).hexdigest() == SYNTHETIC[name]
            else:
                path, entry = Path('test/corpus/files', name), manifest[name]
                assert path.stat().st_size == entry['size'] and hashlib.sha256(path.read_bytes()).hexdigest() == entry['sha256']
                programs = native_programs(path) if path.read_bytes().startswith(b'%PDF-') else [inkai.extract(str(path))]
                assert len(programs) == (5 if name.startswith('reuters-') else 1) and all(program == data for program in programs)
                del programs
            verified.add(name)
        assert bool(row['issue']) == row['rejected']
        verify(inkai, source, target, row, cache)
        checked.append(f'{name}/{variant}')
        print(checked[-1], 'passed', flush=True)
    (args.output / 'independent-report.json').write_text(json.dumps(dict(oracleRevision=REVISION, transactions=checked, inspections=6, realResizes=8, syntheticResizes=4, refusals=2), indent=2) + '\n')


if __name__ == '__main__':
    main()
