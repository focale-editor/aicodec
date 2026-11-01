#!/usr/bin/env python3
"""Check atomic appearance edits against complete independently decoded sources."""

import argparse
import hashlib
import importlib
import json
from pathlib import Path
import re
import subprocess
import sys

from corpus_support import REVISION
from verify_native_appearances import verify

SOURCES = {
    'selected': '6fe71fbd8ae3cad10651919649bb474f84fd76bb03f7ed2f00ac2ade41a7882d',
    'shared': '6fe71fbd8ae3cad10651919649bb474f84fd76bb03f7ed2f00ac2ade41a7882d',
    'settings': 'c74a591901980f0cd751de5f79a40ab101f53279537ad16f7d705c57182001b6',
    'simple-selected': '9618b13fd1fd2261ad9b96cbd9f60b65ca8de593a0d015b3a2d154be33afaa92',
    'simple-shared': '9618b13fd1fd2261ad9b96cbd9f60b65ca8de593a0d015b3a2d154be33afaa92',
}
GROUP = b'u\n0.7 0.6 0.5 Xa\n0 0 m 10 0 L 10 10 L f\n0 0 0 1 k\nU'
SIMPLE_GROUP = b'u\n1 0 0 0 k\n0 0 m 10 0 L 10 10 L f\n0 0 0 1 k\nU'


def string(value):
    """Specify escaped literal bytes independently of the Dart writer."""
    return b'(' + b''.join(f'\\{byte:03o}'.encode() for byte in value) + b')'


def replace_once(data, before, after):
    """Require unique intended source fields rather than silently replacing none."""
    assert data.count(before) == 1, before
    return data.replace(before, after)


def expected(before, variant, original):
    """Prescribe every changed byte, including unaffected objects and metadata."""
    simple = variant.startswith('simple-')
    shared = variant in ('shared', 'simple-shared')
    start, end = original['styles'][0]['record']
    # The inventory checker has bound this entire span to an independent style.
    style = before[start:end]
    if variant == 'settings':
        for old, new in [
            (b'0 /Visible', b'1 /Visible'),
            (b'1 /Bool (UseEvenOdd)', b'0 /Bool (UseEvenOdd)'),
            (b'1 /Bool (StrokeOffsetInside)', b'0 /Bool (StrokeOffsetInside)'),
            (b'(Inside) /String (DisplayString)', string(b'Outside') + b' /String (DisplayString)'),
            (b'0.1 0.2 0.3 0.4 0.5 0.6 0.7 XA', b'0.0 0.1 0.2 0.3 0.4 0.5 0.6 XA'),
            (b'3 w', b'8.0 w'),
            (b'[2 3 0] -1 d', b'[5.0 2.0 3.0 4.0 ] -2.0 d'),
        ]:
            style = replace_once(style, old, new)
    elif simple:
        style = replace_once(style, b'0.1 0.2 0.3 0.4 k', b'1.0 0.0 0.0 0.0 k')
    else:
        style = replace_once(style, b'0.2 0.3 0.4 Xa', b'0.7 0.6 0.5 Xa')
    users = [0, 1] if shared else [1] if variant == 'settings' else [0]
    edits = []
    if shared:
        edits.append((start, end, style))
    else:
        style = replace_once(style, b'(Shared) /Name', string(b'Selected') + b' /Name')
        edits.append((end, end, b'\n' + style + b'\n'))
    # Locate both complete groups and style applications from the pinned source,
    # without accepting writer-reported ownership ranges as an edit mask.
    groups = list(re.finditer(rb'(?m)^u\n\n0 0 0 1 k\n.*?\nU(?=\n%_/ArtDictionary)', before, re.DOTALL))
    applications = list(re.finditer(rb'(?m)^1 \(Shared\) XW$', before))
    assert len(groups) == len(applications) == 2
    for index in users:
        group, application = groups[index], applications[index]
        assert group.end() < application.start()
        edits.append((group.start(), group.end(), SIMPLE_GROUP if simple else GROUP))
        if not shared:
            edits.append((application.start(), application.end(), b'1 ' + string(b'Selected') + b' XW'))
    for start, end, value in sorted(edits, reverse=True):
        before = before[:start] + value + before[end:]
    return replace_once(before, b'%%BoundingBox: 0 0 100 100', b'%%BoundingBox: -20 -30 120 140')


def main():
    """Require all declared variants and validate their complete appearance trees."""
    if not __debug__:
        raise RuntimeError('Run verification without assertion stripping')
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--inkai-source', type=Path, required=True)
    parser.add_argument('--output', type=Path, default=Path('test/corpus/output/appearance-edits'))
    args = parser.parse_args()
    assert subprocess.check_output(['git', '-C', str(args.inkai_source), 'rev-parse', 'HEAD'], text=True).strip() == REVISION
    assert not subprocess.check_output(['git', '-C', str(args.inkai_source), 'status', '--porcelain', '--untracked-files=no'], text=True).strip()
    sys.path.insert(0, str(args.inkai_source.resolve()))
    inkai = importlib.import_module('inkai')
    rows = json.loads((args.output / 'report.json').read_text())
    assert len(rows) == 2 * len(SOURCES) and {row['source'] for row in rows} == {f'{variant}.{phase}' for variant in SOURCES for phase in ('before', 'after')}
    inventory = {row['source']: row for row in rows}
    for variant, checksum in SOURCES.items():
        before = (args.output / f'{variant}.before.ps').read_bytes()
        after = (args.output / f'{variant}.after.ps').read_bytes()
        assert hashlib.sha256(before).hexdigest() == checksum
        parts = 0 if variant.startswith('simple-') else 8
        styles = 1 if variant in ('shared', 'simple-shared') else 2
        verify(inkai, args.output, inventory[f'{variant}.before'], expected=(1, parts, 2))
        verify(inkai, args.output, inventory[f'{variant}.after'], expected=(styles, styles * parts, 2))
        assert after == expected(before, variant, inventory[f'{variant}.before'])
        print(variant, 'passed', flush=True)
    (args.output / 'independent-report.json').write_text(json.dumps(dict(oracleRevision=REVISION, variants=list(SOURCES)), indent=2) + '\n')


if __name__ == '__main__':
    main()
