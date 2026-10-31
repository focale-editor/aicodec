#!/usr/bin/env python3
"""Verify native print-range remapping and exact unrelated source preservation."""

import argparse
from copy import deepcopy
import hashlib
import importlib
import json
from pathlib import Path
import re
import subprocess
import sys

from corpus_support import REVISION
from verify_native_artboard_lifecycle import checked_inventory, new_board
from verify_native_page_saves import native_document
from verify_native_path_lifecycle import patch
from verify_native_reference_scope import values
from verify_native_structure import parsed

REAL = ['units-525x801_origin_at_100_100_CC.ai', 'units-20000x10000_origin_at_100_100_CC.ai', 'units-20x40mm_origin_topleft_CC.ai']
SYNTHETIC_SHA256 = '47ecd1458adfce21940717b40d18f66ee1e21a95bb1047f251e9446d76ab94aa'
VARIANTS = ['select', 'create', 'reorder', 'remove', 'resize']
PREFIX = '/attributes/job.'


def indices(text):
    """Read this corpus's explicit finite one-based range lists independently."""
    result = set()
    for part in text.split(',') if text else []:
        bounds = [int(value) for value in part.split('-')]
        assert len(bounds) in (1, 2) and bounds[0] > 0 and bounds[-1] >= bounds[0]
        result.update(range(bounds[0] - 1, bounds[-1]))
    return sorted(result)


def range_text(selected):
    """Canonicalize explicit selections without using any emitted Dart report."""
    groups = []
    for index in sorted(selected):
        if groups and groups[-1][-1] + 1 == index:
            groups[-1].append(index)
        else:
            groups.append([index])
    return ','.join(str(group[0] + 1) if len(group) == 1 else f'{group[0] + 1}-{group[-1] + 1}' for group in groups)


def expected_document(original, variant):
    """Specify retained identities, active replacement and independent page choices."""
    expected = deepcopy(original)
    recorded = expected['Recorded']
    boards = recorded['ArtboardArray']
    job = expected['NotRecorded']['AI11 Print JobInfo Dict']
    selected = indices(job[PREFIX + 'artboardrange'])
    if variant == 'select':
        selected = {0, len(boards) - 1}
        job[PREFIX + 'printallartboards'] = 0
    elif variant == 'create':
        boards.insert(0, new_board(False))
        selected = [index + 1 for index in selected]
        recorded['CropAreaActive'] += 1
        expected['NotRecorded']['LastArtboardID'] += 7
    elif variant == 'reorder':
        boards.reverse()
        selected = [len(boards) - 1 - index for index in selected]
        recorded['CropAreaActive'] = len(boards) - 1 - recorded['CropAreaActive']
    elif variant == 'remove':
        keep = [index for index in range(len(boards)) if index not in selected]
        assert keep
        active = recorded['CropAreaActive']
        recorded['CropAreaActive'] = 0 if active in selected else keep.index(active)
        recorded['ArtboardArray'] = [boards[index] for index in keep]
        selected = []
        job[PREFIX + 'printallartboards'] = 1
    elif variant == 'resize':
        boards[0]['PositionPoint1'] = [-20, 120]
        boards[0]['PositionPoint2'] = [250, -40]
    else:
        raise AssertionError(variant)
    job[PREFIX + 'artboardrange'] = range_text(selected)
    job[PREFIX + 'printall'] = 1 if variant == 'remove' else 0
    job[PREFIX + 'pagerange'] = dict(select='2,5', create='1,6,12', reorder='4,8', remove='', resize='3')[variant]
    return expected


def inventory(data, document, reported):
    """Bind each reported print operand to its independent owning record and key."""
    checked_inventory(data, document, reported)
    job_start, job_end = reported['printJob']
    decoded = parsed(data[job_start:job_end])
    assert len(decoded) == 1 and values(decoded[0]) == document['NotRecorded']['AI11 Print JobInfo Dict']
    assert set(reported['printFields']) == {PREFIX + key for key in ('printallartboards', 'artboardrange', 'printall', 'pagerange')}
    for key, field in reported['printFields'].items():
        start, end = field['typeSpan']
        assert job_start < start < end < job_end
        assert data[start:end] == ('/' + field['type']).encode()
        assert re.match(rb'\s+\(' + re.escape(key.encode()) + rb'\)\s*,', data[end:job_end])
        assert all(job_start < first < last < start for first, last in field['items'])


def verify(before, after, row):
    """Require the complete expected Document and only the prescribed byte edits."""
    original = native_document(before, row['before'])
    changed = native_document(after, row['after'])
    inventory(before, original, row['before'])
    inventory(after, changed, row['after'])
    assert changed == expected_document(original, row['variant']), (row['source'], row['variant'])
    edits = []
    if row['variant'] in ('create', 'reorder', 'remove'):
        edits.append((*row['before']['array'], after[slice(*row['after']['array'])]))
        old_boards = {board['identifier']: board for board in row['before']['boards']}
        for board in row['after']['boards']:
            if board['identifier'] in old_boards:
                assert after[slice(*board['record'])] == before[slice(*old_boards[board['identifier']]['record'])]
    elif row['variant'] == 'resize':
        for key in ('PositionPoint1', 'PositionPoint2'):
            for old, new in zip(row['before']['boards'][0]['coordinates'][key], row['after']['boards'][0]['coordinates'][key]):
                edits.append((*old, after[slice(*new)]))
    for key in ('active', 'lastId'):
        if row['before'][key] != row['after'][key]:
            edits.append((*row['before'][key + 'Span'], after[slice(*row['after'][key + 'Span'])]))
    for key, old in row['before']['printFields'].items():
        new = row['after']['printFields'][key]
        assert old['type'] == new['type']
        if not old['items'] and not new['items']:
            continue
        assert len(new['items']) == 1
        replacement = after[slice(*new['items'][0])]
        if old['items']:
            edits.append((*old['items'][0], replacement))
            edits.extend((start, end, b'') for start, end in old['items'][1:])
        else:
            edits.append((old['typeSpan'][0], old['typeSpan'][0], replacement + b' '))
    assert patch(before, edits) == after


def main():
    """Require all fifteen real-file and five synthetic chained transactions."""
    if not __debug__:
        raise RuntimeError('Run verification without assertion stripping')
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--inkai-source', type=Path, required=True)
    parser.add_argument('--output', type=Path, default=Path('test/corpus/output/print-jobs'))
    args = parser.parse_args()
    assert subprocess.check_output(['git', '-C', str(args.inkai_source), 'rev-parse', 'HEAD'], text=True).strip() == REVISION
    assert not subprocess.check_output(['git', '-C', str(args.inkai_source), 'status', '--porcelain', '--untracked-files=no'], text=True).strip()
    sys.path.insert(0, str(args.inkai_source.resolve()))
    importlib.import_module('inkai')
    manifest = {entry['file']: entry for entry in json.loads(Path('test/corpus/artboard_manifest.json').read_text())['files']}
    names = [*REAL, 'synthetic-print']
    for name in names:
        original = (args.output / f'{name}.original.ps').read_bytes()
        if name == 'synthetic-print':
            assert hashlib.sha256(original).hexdigest() == SYNTHETIC_SHA256
        else:
            path = Path('test/corpus/files', name)
            data = path.read_bytes()
            assert len(data) == manifest[name]['size'] and hashlib.sha256(data).hexdigest() == manifest[name]['sha256']
            assert data.startswith(b'%!PS-Adobe-') and data == original
    rows = json.loads((args.output / 'report.json').read_text())
    assert [(row['source'], row['variant']) for row in rows] == [(name, variant) for name in names for variant in VARIANTS]
    for row in rows:
        previous = 'original' if row['variant'] == 'select' else VARIANTS[VARIANTS.index(row['variant']) - 1]
        assert row['original'] == f'{row["source"]}.{previous}.ps'
        assert row['result'] == f'{row["source"]}.{row["variant"]}.ps'
        verify((args.output / row['original']).read_bytes(), (args.output / row['result']).read_bytes(), row)
        print(row['source'], row['variant'], 'passed', flush=True)
    (args.output / 'independent-report.json').write_text(json.dumps(dict(oracleRevision=REVISION, realPrintTransactions=15, syntheticPrintTransactions=5), indent=2) + '\n')


if __name__ == '__main__':
    main()
