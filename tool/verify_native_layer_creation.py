#!/usr/bin/env python3
"""Verify new native layers without a source template or renderer dependency."""

import argparse
import hashlib
import importlib
import json
from pathlib import Path
import re
import subprocess
import sys

from corpus_support import REVISION
from verify_native_layers import verified_inventory
from verify_native_path_lifecycle import patch
from verify_native_reference_resources import pinned_program

ATTRIBUTES = [1, 1, 1, 1, 0, 0, 1, 0, 79, 128, 255, 0, 50, 0]
SYNTHETIC = {
    'synthetic-empty': 'c14c15b1d68a0a4241c784e71a51d1f019b3ad8d63efa5d5e169edf7f123c385',
    'synthetic-nine': 'cea4e31d2d7eee8e2a75349178cc186f6f310002c53d5ea2abfb90cc799ea35e',
    'synthetic-parent': '608bb3d9667cabc765ed0f79417e6089367253cd9c7ffe4ca660bd77c675f3d7',
}


def requests():
    """Fix source owners, complete headers and panel state independently of output."""
    result = {}
    for name in ('simple_shapes.ai', 'simple_shapes_cc.ai', 'layers_and_sublayers.ai'):
        result[name, 'root'] = None, ATTRIBUTES, False
        result[name, 'nested'] = 0, ATTRIBUTES, True
    result['synthetic-empty', 'classic'] = None, [0, 1, 0, 0, 1, 0, -1, 255, 0, 128], False
    result['synthetic-empty', 'extended'] = None, ATTRIBUTES[:13], True
    result['synthetic-empty', 'cc'] = None, ATTRIBUTES, False
    result['synthetic-nine', 'root'] = None, ATTRIBUTES, False
    result['synthetic-parent', 'populated'] = 0, ATTRIBUTES, False
    result['synthetic-parent', 'empty'] = 1, ATTRIBUTES, False
    return result


def verify(inkai, source, target, row):
    """Bind the new owner, unchanged old headers and exact permitted source edits."""
    before, after = source.read_bytes(), target.read_bytes()
    original = verified_inventory(inkai, source, row['before'])
    changed = verified_inventory(inkai, target, row['after'])
    parent, position = row['parent'], row['position']
    if parent is None:
        boundary = re.search(rb'^%%(?:PageTrailer|Trailer)\r?$', before, re.MULTILINE)
        assert boundary is not None and position == boundary.start()
    else:
        assert position == row['before']['layers'][parent]['closing'][0]
    insertion = sum(node['start'] < position for node in row['before']['layers'])
    assert len(changed) == len(original) + 1
    added = changed[insertion]
    assert added['parent'] == parent and not added['children'] and not added['body']
    assert added['name'] == row['name'] == list(b'AiKit (new)')
    assert added['identifier'] == 'AiKit_new' and row['identifier'] == list(b'AiKit_new')
    assert added['attributes'] == row['attributes'] and added['expanded'] == row['expanded']
    assert added['dictionary'] == {'_type': 'ArtDictionary', 'AI10_ArtUID': 'AiKit_new'}
    assert [(command, private) for command, _, private in added['commands']] == [('Lb', False), ('Ln', False), ('AE', False), ('LB', False)]
    assert all(node['identifier'] != 'AiKit_new' for node in original)

    def shifted(index):
        """Account for the one new lexical index without changing old identities."""
        return None if index is None else index + (index >= insertion)

    for index, old in enumerate(original):
        new = changed[shifted(index)]
        assert all(old[key] == new[key] for key in ('attributes', 'name', 'expanded', 'identifier', 'dictionary'))
        assert new['parent'] == shifted(old['parent'])
        assert new['children'] == [shifted(child) for child in old['children']] + ([insertion] if index == parent else [])
    previous, current = row['before'], row['after']
    assert current['rootCount'] == previous['rootCount'] + (parent is None) and not current['viewSpans']
    span = current['layers'][insertion]
    assert span['openingComment'] == '%AI5_BeginLayer' and span['closingComment'] == '%AI5_EndLayer--' and span['issue'] is None
    newline = b'\r\n' if before.split(b'\n', 1)[0].endswith(b'\r') else b'\n'
    edits = [(position, position, newline + after[span['start']:span['end']] + newline)]
    edits.extend((*value, b'') for value in previous['viewSpans'])
    if parent is None and previous['rootCountSpan'] is not None:
        start, end = previous['rootCountSpan']
        edits.append((start, end, before[start:end].split(b':')[0] + b': ' + str(current['rootCount']).encode()))
    assert patch(before, edits) == after, (row['result'], 'Unexpected source, artwork, state or metadata edit')


def main():
    """Require every pinned creation request and the unchanged independent reader."""
    if not __debug__:
        raise RuntimeError('Run verification without assertion stripping')
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--inkai-source', required=True, type=Path)
    parser.add_argument('--output', default=Path('test/corpus/output/layer-creation'), type=Path)
    args = parser.parse_args()
    assert subprocess.check_output(['git', '-C', str(args.inkai_source), 'rev-parse', 'HEAD'], text=True).strip() == REVISION
    assert not subprocess.check_output(['git', '-C', str(args.inkai_source), 'status', '--porcelain', '--untracked-files=no'], text=True).strip()
    sys.path.insert(0, str(args.inkai_source.resolve()))
    inkai = importlib.import_module('inkai')
    manifest = {entry['file']: entry for entry in json.loads(Path('test/corpus/manifest.json').read_text())['files']}
    expected, checked = requests(), []
    programs = {name: pinned_program(name, manifest) for name, _ in expected if not name.startswith('synthetic')}
    rows = json.loads((args.output / 'report.json').read_text())
    assert len(rows) == len(expected) == 12 and {(row['source'], row['variant']) for row in rows} == expected.keys()
    for row in rows:
        name, variant = row['source'], row['variant']
        assert (row['parent'], row['attributes'], row['expanded']) == expected[name, variant]
        assert row['original'] == f'{name}.original.ps' and row['result'] == f'{name}.{variant}.ps'
        source, target = args.output / row['original'], args.output / row['result']
        if name.startswith('synthetic'):
            assert hashlib.sha256(source.read_bytes()).hexdigest() == SYNTHETIC[name]
        else:
            assert source.read_bytes() == programs[name]
        verify(inkai, source, target, row)
        checked.append(row['result'])
        print(row['result'], 'passed', flush=True)
    (args.output / 'independent-report.json').write_text(json.dumps(dict(oracleRevision=REVISION, transactions=checked, realInsertions=6, syntheticInsertions=6), indent=2) + '\n')


if __name__ == '__main__':
    main()
