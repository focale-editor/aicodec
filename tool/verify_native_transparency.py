#!/usr/bin/env python3
"""Check transparency edits and every retained byte with the pinned native reader."""

import argparse
import hashlib
import importlib
import json
from pathlib import Path
import re
import subprocess
import sys

from corpus_support import REVISION, native_programs
from verify_native_appearance_edits import replace_once, string
from verify_native_appearance_graphs import patch
from verify_native_appearances import verify
from verify_native_structure import native_values, parsed

PRINTING = b'u\n0 0 0 1 k\n1 0.25 1 1 0 Xy\n0 0 m 10 0 L 10 10 L f\n0 1 0 0 0 Xy\nU'


def expected(before, row):
    """Prescribe one changed tuple, supplied groups and selected style ownership."""
    real = row['name'] == 'stroke_styles.ai'
    shared = row['name'].endswith('-shared')
    style = row['before']['styles'][row['style']]
    start, end = style['record']
    part = style['parts'][row['part']]
    paint, = part['paints']
    assignment, = [item for item in paint['assignments'] if item['parameter'] == 'transparency']
    first, last = paint['instructions'][assignment['instruction']]['span']
    assert before[first:last] == (b'0 1 0 0 0 Xy' if real else b'9 0.5 1 2 1 Xy')
    command = b'1.0 0.25 0.0 0.0 0.0 Xy' if real else b'1.0 0.25 1.0 1.0 0.0 Xy'
    changed = patch(before[start:end], [(first - start, last - start, command)])
    name = bytes(style['name'])
    if not shared:
        changed = replace_once(changed, b'(' + name + b') /Name', string(b'Transparent selection') + b' /Name')
    edits = [(start, end, changed)] if shared else [(end, end, b'\n' + changed + b'\n')]
    for use_index, (first, last) in zip(row['uses'], row['groups'], strict=True):
        group = before[first:last]
        commands = [item for item in native_values(parsed(group)) if hasattr(item, 'command')]
        assert commands[0].command == 'u' and commands[-1].command == 'U'
        if real:
            colors = [item for item in commands if item.command == 'XA']
            assert len(colors) == 1 and not any(item.command == 'Xy' for item in commands)
            group = replace_once(group, b' XA', b' XA\n1 0.25 0 0 0 Xy\n')[:-1] + b'0 1 0 0 0 Xy\nU'
        else:
            group = PRINTING
        edits.append((first, last, group))
        first, last = row['before']['uses'][use_index]['span']
        assert before[first:last] == b'1 (' + name + b') XW'
        if not shared:
            # The producer's following user inherits the original explicit Xy.
            # Preserve that state privately after the selected application.
            restoration = b'\n%_0 1 0 0 0 Xy\n' if real else b''
            edits.append((first, last, b'1 ' + string(b'Transparent selection') + b' XW' + restoration))
    result = patch(before, edits)
    if not real:
        result = re.sub(rb'%%BoundingBox: [^\r\n]+', b'%%BoundingBox: -20 -30 120 140', result)
        result = re.sub(rb'%%HiResBoundingBox: [^\r\n]+', b'%%HiResBoundingBox: -20.0 -30.0 120.0 140.0', result)
    return result


def main():
    """Require all five transactions and the original complete producer fixture."""
    if not __debug__:
        raise RuntimeError('Run verification without assertion stripping')
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--inkai-source', required=True, type=Path)
    args = parser.parse_args()
    assert subprocess.check_output(['git', '-C', str(args.inkai_source), 'rev-parse', 'HEAD'], text=True).strip() == REVISION
    assert not subprocess.check_output(['git', '-C', str(args.inkai_source), 'status', '--porcelain', '--untracked-files=no'], text=True).strip()
    sys.path.insert(0, str(args.inkai_source.resolve()))
    inkai = importlib.import_module('inkai')
    output = Path('test/corpus/output/transparency')
    rows = json.loads((output / 'report.json').read_text())
    assert {row['name'] for row in rows} == {'path-selected', 'path-shared', 'group-selected', 'group-shared', 'stroke_styles.ai'} and len(rows) == 5
    fixture = Path('test/corpus/files/stroke_styles.ai')
    entry, = [entry for entry in json.loads(Path('test/corpus/manifest.json').read_text())['files'] if entry['file'] == fixture.name]
    assert fixture.stat().st_size == entry['size'] and hashlib.sha256(fixture.read_bytes()).hexdigest() == entry['sha256'] and entry['license'] and entry['revision'] == REVISION
    assert native_programs(fixture) == [(output / 'stroke_styles.ai.before.ps').read_bytes()]
    for row in rows:
        original = row['before']
        counts = (22, 173, 31) if row['name'] == fixture.name else (1, 8, 2)
        added = 0 if row['name'].endswith('-shared') else 1
        verify(inkai, output, original, expected=counts)
        verify(inkai, output, row['after'], expected=(counts[0] + added, counts[1] + added * len(original['styles'][row['style']]['parts']), counts[2]))
        before = (output / f'{row["name"]}.before.ps').read_bytes()
        after = (output / f'{row["name"]}.after.ps').read_bytes()
        assert after == expected(before, row), row['name']
        print(row['name'], 'passed', flush=True)
    (output / 'independent-report.json').write_text(json.dumps(dict(oracleRevision=REVISION, transactions=[row['name'] for row in rows]), indent=2) + '\n')


if __name__ == '__main__':
    main()
