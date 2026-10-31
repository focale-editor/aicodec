#!/usr/bin/env python3
"""Independently verify artboard lifecycle, identity and untouched native source."""

import argparse
from copy import deepcopy
import hashlib
import importlib
import json
from pathlib import Path
import subprocess
import sys

from corpus_support import REVISION, native_programs
from verify_native_artboards import SYNTHETIC, inventory
from verify_native_artboards import verify as verify_resize
from verify_native_path_lifecycle import patch
from verify_native_reference_scope import documents, values
from verify_native_structure import parsed


def requests(names):
    """Pin complete transaction order and predecessor files independently of Dart."""
    result = {}
    for name in names:
        for variant, predecessor in (
            ('resize', 'original'),
            ('create-front', 'original'), ('reorder', 'create-front'),
            ('remove-new', 'reorder'), ('create-active', 'original'),
            ('remove-original', 'create-active'),
        ):
            result[name, variant] = predecessor
    for name in SYNTHETIC:
        for variant in ('reorder', 'remove-active', 'remove-first', 'create-middle', 'create-active'):
            result[name, variant] = 'original'
    return result


def new_board(selected):
    """Describe the supplied native record without relying on decoded output."""
    return dict(
        _type='Dictionary', Name='New (board)\\',
        PositionPoint1=[-300, 180], PositionPoint2=[-100, -20],
        RulerOrigin=[7650, 8000], ArtboardUUID='b9ef2db5-64d8-49a5-b02e-b455c61a1f27',
        IsArtboardSelected=selected, IsArtboardDefaultName=False, PAR=1, DisplayMark=0,
    )


def expected_document(original, row):
    """Apply independently specified ownership changes and explicit history values."""
    expected = deepcopy(original)
    recorded = expected['Recorded']
    boards = recorded['ArtboardArray']
    variant = row['variant']
    real = row['source'] not in SYNTHETIC
    if variant == 'create-front':
        boards.insert(0, new_board(True))
        recorded['CropAreaActive'] += 1
        expected['NotRecorded']['LastArtboardID'] += 7
    elif variant == 'create-active':
        boards.append(new_board(False))
        recorded['CropAreaActive'] = len(boards) - 1
        expected['NotRecorded']['LastArtboardID'] += 11 if real else 1
    elif variant == 'create-middle':
        boards.insert(1, new_board(True))
        recorded['CropAreaActive'] = 3
        expected['NotRecorded']['LastArtboardID'] = 72
    elif variant == 'reorder':
        order = [1, 0] if real else [2, 0, 1]
        recorded['ArtboardArray'] = [boards[index] for index in order]
        recorded['CropAreaActive'] = order.index(recorded['CropAreaActive'])
    elif variant == 'remove-new':
        boards.pop()
    elif variant == 'remove-active':
        recorded['ArtboardArray'] = [boards[1]]
        recorded['CropAreaActive'] = 0
    elif variant in ('remove-original', 'remove-first'):
        boards.pop(0)
        recorded['CropAreaActive'] -= 1
    else:
        raise AssertionError(variant)
    return expected


def checked_inventory(data, document, reported):
    """Bind reported array, board and scalar spans to independently parsed values."""
    inventory(data, document, reported)
    array = parsed(data[slice(*reported['array'])])
    assert len(array) == 1 and values(array[0]) == document['Recorded']['ArtboardArray']
    for actual, board in zip(reported['boards'], document['Recorded']['ArtboardArray']):
        record = parsed(data[slice(*actual['record'])])
        assert len(record) == 1 and values(record[0]) == board
        assert reported['array'][0] < actual['record'][0] < actual['record'][1] < reported['array'][1]
    for field in ('active', 'lastId'):
        assert int(data[slice(*reported[field + 'Span'])]) == reported[field]


def verify(inkai, source, target, row):
    """Check the whole Document, exact retained records and all external bytes."""
    if row['variant'] == 'resize':
        verify_resize(inkai, source, target, dict(row, selected=0, crop=False, origin=False, rejected=False), {})
        return
    before, after = source.read_bytes(), target.read_bytes()
    original = values(documents(inkai, source, [row['before']['document']])[0])
    changed = values(documents(inkai, target, [row['after']['document']])[0])
    checked_inventory(before, original, row['before'])
    checked_inventory(after, changed, row['after'])
    assert changed == expected_document(original, row), (row['source'], row['variant'], 'Unexpected native field changes')
    original_boards = {board['identifier']: board for board in row['before']['boards']}
    source_chunks = {}
    for index, board in enumerate(row['before']['boards']):
        end = row['before']['boards'][index + 1]['record'][0] if index + 1 < len(row['before']['boards']) else row['before']['array'][1] - 1
        source_chunks[board['identifier']] = before[board['record'][0]:end]
    assert before[row['before']['array'][0]:row['before']['boards'][0]['record'][0]] == after[row['after']['array'][0]:row['after']['boards'][0]['record'][0]]
    for index, board in enumerate(row['after']['boards']):
        if board['identifier'] in original_boards:
            previous = original_boards[board['identifier']]
            assert before[slice(*previous['record'])] == after[slice(*board['record'])]
            end = row['after']['boards'][index + 1]['record'][0] if index + 1 < len(row['after']['boards']) else row['after']['array'][1] - 1
            assert source_chunks[board['identifier']] == after[board['record'][0]:end]
    edits = [(*row['before']['array'], after[slice(*row['after']['array'])])]
    for field in ('active', 'lastId'):
        if row['before'][field] != row['after'][field]:
            edits.append((*row['before'][field + 'Span'], after[slice(*row['after'][field + 'Span'])]))
    if row['source'] in SYNTHETIC and row['variant'] == 'create-active':
        assert row['after']['crop'] == [-10, -20, 30, 40]
        edits.append((*row['before']['cropSpan'], after[slice(*row['after']['cropSpan'])]))
    else:
        assert row['before']['crop'] == row['after']['crop']
    assert patch(before, edits) == after, 'Unexpected artwork, resource, header or document edit'


def main():
    """Require all pinned inputs and chained edit outcomes without Adobe claims."""
    if not __debug__:
        raise RuntimeError('Run verification without assertion stripping')
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--inkai-source', required=True, type=Path)
    parser.add_argument('--output', default=Path('test/corpus/output/artboard-lifecycle'), type=Path)
    args = parser.parse_args()
    assert subprocess.check_output(['git', '-C', str(args.inkai_source), 'rev-parse', 'HEAD'], text=True).strip() == REVISION
    assert not subprocess.check_output(['git', '-C', str(args.inkai_source), 'status', '--porcelain', '--untracked-files=no'], text=True).strip()
    sys.path.insert(0, str(args.inkai_source.resolve()))
    inkai = importlib.import_module('inkai')
    manifest = {entry['file']: entry for entry in json.loads(Path('test/corpus/artboard_manifest.json').read_text())['files'] if entry['file'].startswith('units-')}
    manifest.update({entry['file']: entry for entry in json.loads(Path('test/corpus/manifest.json').read_text())['files'] if entry['file'] in ('rgb_rectangle.ai', 'cmyk_rectangle.ai')})
    expected = requests(manifest)
    rows = json.loads((args.output / 'report.json').read_text())
    assert len(manifest) == 5 and len(rows) == len(expected) == 40
    assert {(row['source'], row['variant']) for row in rows} == expected.keys()
    for name in (*manifest, *SYNTHETIC):
        original = (args.output / f'{name}.original.ps').read_bytes()
        if name in SYNTHETIC:
            assert hashlib.sha256(original).hexdigest() == SYNTHETIC[name]
        else:
            path, entry = Path('test/corpus/files', name), manifest[name]
            assert path.stat().st_size == entry['size'] and hashlib.sha256(path.read_bytes()).hexdigest() == entry['sha256']
            programs = native_programs(path) if path.read_bytes().startswith(b'%PDF-') else [inkai.extract(str(path))]
            assert programs == [original]
    checked = []
    for row in rows:
        name, variant = row['source'], row['variant']
        assert row['original'] == f'{name}.{expected[name, variant]}.ps'
        assert row['result'] == f'{name}.{variant}.ps'
        verify(inkai, args.output / row['original'], args.output / row['result'], row)
        checked.append(f'{name}/{variant}')
        print(checked[-1], 'passed', flush=True)
    (args.output / 'independent-report.json').write_text(json.dumps(dict(oracleRevision=REVISION, transactions=checked, realTransactions=30, syntheticTransactions=10), indent=2) + '\n')


if __name__ == '__main__':
    main()
