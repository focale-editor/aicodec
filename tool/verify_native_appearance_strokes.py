#!/usr/bin/env python3
"""Verify explicit advanced stroke changes and whole-source preservation."""

import argparse
import hashlib
import importlib
import json
from pathlib import Path
import re
import subprocess
import sys

from corpus_support import REVISION
from verify_native_appearance_edits import GROUP, replace_once, string
from verify_native_appearance_graphs import patch
from verify_native_appearances import verify

SOURCE = '0b241a34e56a2664051e3ea53d080c3926cd24c0dad60f3e2d9ec8969edd2bce'


def expected(data, row, variant):
    """Specify the exact scalar, style-copy, use, expansion and bounds edits."""
    style, = row['styles']
    part = style['parts'][6]
    settings = part['strokeSettings']
    assert settings['version'] == 1 and settings['adjustDashes'] is True
    start, end = style['record']
    first, last = part['record']
    changed_part = replace_once(data[first:last], b'1 /Bool (BSDashAdj)', b'0 /Bool (BSDashAdj)')
    changed_part = replace_once(changed_part, b'[2 3 0] -1 d', b'[4.0 2.0 ] 3.0 d')
    changed_style = data[start:first] + changed_part + data[last:end]
    shared = variant == 'shared'
    if shared:
        edits = [(start, end, changed_style)]
    else:
        changed_style = replace_once(changed_style, b'(Shared) /Name', string(b'Stroke settings') + b' /Name')
        edits = [(end, end, b'\n' + (b'%_' if variant == 'private' else b'') + changed_style + b'\n')]
    groups = list(re.finditer(rb'(?ms)^u\n.*?\nU$', data))
    uses = list(re.finditer(rb'(?m)^1 \(Shared\) XW$', data))
    assert len(groups) == len(uses) == 2
    for index in ([0, 1] if shared else [1]):
        edits.append((*groups[index].span(), GROUP))
        if not shared:
            edits.append((*uses[index].span(), b'1 ' + string(b'Stroke settings') + b' XW'))
    return replace_once(patch(data, edits), b'%%BoundingBox: 0 0 100 100', b'%%BoundingBox: -20 -30 120 140')


def main():
    """Check native fields and serialization without rendering synthetic groups."""
    if not __debug__:
        raise RuntimeError('Run verification without assertion stripping')
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--inkai-source', required=True, type=Path)
    parser.add_argument('--output', type=Path, default=Path('test/corpus/output/appearance-strokes'))
    args = parser.parse_args()
    assert subprocess.check_output(['git', '-C', str(args.inkai_source), 'rev-parse', 'HEAD'], text=True).strip() == REVISION
    assert not subprocess.check_output(['git', '-C', str(args.inkai_source), 'status', '--porcelain', '--untracked-files=no'], text=True).strip()
    sys.path.insert(0, str(args.inkai_source.resolve()))
    inkai = importlib.import_module('inkai')
    rows = json.loads((args.output / 'report.json').read_text())
    inventory = {row['source']: row for row in rows}
    assert len(rows) == 6 and set(inventory) == {f'{variant}.{phase}' for variant in ('selected', 'shared', 'private') for phase in ('before', 'after')}
    original = (args.output / 'selected.before.ps').read_bytes()
    assert hashlib.sha256(original).hexdigest() == SOURCE
    for variant in ('selected', 'shared', 'private'):
        before = (args.output / f'{variant}.before.ps').read_bytes()
        after = (args.output / f'{variant}.after.ps').read_bytes()
        if variant == 'private':
            start, end = original.index(b'/KnownStyle'), original.index(b'%%EndSetup')
            projected = b'\n'.join(b'%_' + line for line in original[start:end].split(b'\n') if line) + b'\n'
            assert before == original[:start] + projected + original[end:]
        else:
            assert before == original
        row = inventory[f'{variant}.before']
        verify(inkai, args.output, row, expected=(1, 8, 2))
        verify(inkai, args.output, inventory[f'{variant}.after'], expected=(1, 8, 2) if variant == 'shared' else (2, 16, 2))
        assert after == expected(before, row, variant), variant
        print(variant, 'passed exact stroke settings and complete byte delta', flush=True)
    (args.output / 'verification.json').write_text(json.dumps(dict(oracleRevision=REVISION, variants=['selected', 'shared', 'private']), indent=2) + '\n')


if __name__ == '__main__':
    main()
