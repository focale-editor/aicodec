#!/usr/bin/env python3
"""Verify complete outer edits while retaining every private nested style use."""

import argparse
import hashlib
import importlib
import json
from pathlib import Path
import subprocess
import sys

from corpus_support import REVISION
from verify_native_appearance_groups import expected, owners, shared
from verify_native_appearances import verify

SOURCES = {
    'selected': 'e3eddd60261ef84518f1ab5898f9958d0b624294d08e7538fe48c05b50eddcce',
    'shared': 'e3eddd60261ef84518f1ab5898f9958d0b624294d08e7538fe48c05b50eddcce',
    'simple-selected': '2edab09904d5ae09c4bab080a8edc86a70a547ab83359090a28d55e95219940f',
    'simple-shared': '2edab09904d5ae09c4bab080a8edc86a70a547ab83359090a28d55e95219940f',
    'compound-selected': '8a07e3dc3fdac0e6afa86f10a84a2eedfcccc943cf772c92a78c83838234a57e',
    'compound-shared': '8a07e3dc3fdac0e6afa86f10a84a2eedfcccc943cf772c92a78c83838234a57e',
}


def main():
    """Pin synthetic sources and compare every tree, reference and output byte."""
    if not __debug__:
        raise RuntimeError('Run verification without assertion stripping')
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--inkai-source', required=True, type=Path)
    parser.add_argument('--output', default=Path('test/corpus/output/appearance-nested-styles'), type=Path)
    args = parser.parse_args()
    assert subprocess.check_output(['git', '-C', str(args.inkai_source), 'rev-parse', 'HEAD'], text=True).strip() == REVISION
    assert not subprocess.check_output(['git', '-C', str(args.inkai_source), 'status', '--porcelain', '--untracked-files=no'], text=True).strip()
    sys.path.insert(0, str(args.inkai_source.resolve()))
    inkai = importlib.import_module('inkai')
    rows = json.loads((args.output / 'report.json').read_text())
    assert len(rows) == 2 * len(SOURCES) and {row['source'] for row in rows} == {f'{variant}.{phase}' for variant in SOURCES for phase in ('before', 'after')}
    inventory = {row['source']: row for row in rows}
    for variant, checksum in SOURCES.items():
        before, after = [(args.output / f'{variant}.{phase}.ps').read_bytes() for phase in ('before', 'after')]
        assert hashlib.sha256(before).hexdigest() == checksum
        original, changed = [inventory[f'{variant}.{phase}'] for phase in ('before', 'after')]
        styles = 2 if shared(variant) else 3
        child_parts = 0 if variant.startswith('simple') else 8
        verify(inkai, args.output, original, expected=(2, 8 + child_parts, 6))
        verify(inkai, args.output, changed, expected=(styles, (styles - 1) * 8 + child_parts, 6))
        assert after == expected(before, original, variant, name_bytes=b'Selected outer')
        assert owners(inkai, args.output, before, original, variant) == owners(inkai, args.output, after, changed, variant)
        for row in (original, changed):
            assert [artwork['nestedUses'] for artwork in row['artwork']] == [[0, 1], [3, 4]]
            for index in (0, 1, 3, 4):
                use = row['uses'][index]
                assert use['mode'] == int(index in (1, 4)) and bytes(use['name']) == b'Child'
        print(variant, 'passed', flush=True)
    (args.output / 'independent-report.json').write_text(json.dumps(dict(oracleRevision=REVISION, variants=list(SOURCES)), indent=2) + '\n')


if __name__ == '__main__':
    main()
