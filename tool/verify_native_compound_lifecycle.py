#!/usr/bin/env python3
"""Check compound ownership and exact bytes with a pinned independent AI reader."""

from copy import deepcopy
import argparse
import hashlib
import importlib
import json
from pathlib import Path
import re
import subprocess
import sys

from corpus_support import REVISION
from verify_native_path_lifecycle import patch
from verify_native_path_topology import inventory


SOURCES = {
    'nested': 'e80440cf4c7428c6be6e4b5f40961c16b18ea9ddf56db52dfb246933f5b89655',
    'mask': 'ed53ff1a1a7fdbb950494640d0ff0a354d058cafa9af7f49ddd90339d8d6d644',
    'mask-tree': '0ae47beead3e074e3c5e02fc8ab62e2d0b3ac244f6997e100bff0fe5cf3ddde1',
    'cc-pairs': 'e5a59c009610e265af2b1b88af187fe783f0c1be386fe5925e3292f58860c913',
    'metadata': '292e1c04dae1ccdfd74d0d4eb8b40c208f908f0de80716287ad3d10231fc508d',
    'batch': '273540c410d07e412cef4f59c04974566b9a8cc981469f3f8494cb9fba53cadc',
}


def selection(data, name):
    """Locate prescribed boundaries in fixed, hash-pinned synthetic programs.

    These searches describe these fixtures only, not a general AI lexer. No
    writer-reported offset or selected-object index grants an editable range.
    """
    if name == 'nested':
        start = data.index(b'4 As')
        end = data.index(b'\n%_;', data.index(b'(Branch)')) + len(b'\n%_;')
        return start, end, range(3), 0
    if name == 'mask':
        return data.index(b'4 As'), data.index(b'n Q') + 1, range(2), 1
    if name == 'mask-tree':
        return data.index(b' u q') + 1, data.index(b' U Q\n%%Trailer') + 2, range(2), 1
    assert name == 'cc-pairs'
    start = data.rindex(b'0 A 0 Xw 4 As') + len(b'0 A 0 Xw ')
    return start, data.rindex(b'f\n%%Trailer') + 1, range(9, 11), 0


def normalized_paths(document):
    """Compare each contour's data and ancestry without mutable group ordinals."""
    paths = inventory(document)
    for path in paths:
        path['owners'] = [kind for kind, _ in path['owners']]
    return paths


def verify(inkai, directory, name, variant, predecessor):
    """Require the prescribed native topology and exact authorized byte changes."""
    source = directory / f'{name}.{predecessor}.ps'
    target = directory / f'{name}.{variant}.ps'
    before, after = source.read_bytes(), target.read_bytes()
    expected = deepcopy(normalized_paths(inkai.parse(str(source))))
    original = (directory / f'{name}.original.ps').read_bytes()
    if name in ('metadata', 'batch'):
        assert variant == 'release' and predecessor == 'original'
        selected = range(1 if name == 'metadata' else 400)
        depth = 0
        if name == 'metadata':
            start = before.index(b'1 Ae *u')
            end = before.index(b'9 () XW') + len(b'9 () XW')
            closing = before.index(b'*U\n')
            edits = [(start, start + len(b'1 Ae *u'), b' '), (closing, end, b' ')]
        else:
            matches = list(re.finditer(rb'\*[uU](?=\s)', before))
            assert len(matches) == 400
            edits = [(match.start(), match.end(), b' ') for match in matches]
    else:
        start, end, selected, depth = selection(original, name)
        if variant == 'compound':
            assert predecessor == 'original'
            edits = [(start, start, b'\n*u\n'), (end, end, b'\n*U\n')]
        else:
            assert variant == 'release' and predecessor == 'compound'
            assert before == patch(original, [(start, start, b'\n*u\n'), (end, end, b'\n*U\n')])
            edits = [(start + 1, start + 3, b' '), (end + 5, end + 7, b' ')]
    for index in selected:
        assert not expected[index]['private']
        if variant == 'compound':
            expected[index]['owners'].insert(depth, '*u')
        else:
            assert expected[index]['owners'].pop(depth) == '*u'
    assert normalized_paths(inkai.parse(str(target))) == expected, (name, variant, 'contours or ancestry changed')
    assert patch(before, edits) == after, (name, variant, 'unexpected geometry, state, identity or source change')


def main():
    """Require all ten transactions with the unmodified pinned external reader."""
    if not __debug__:
        raise RuntimeError('Run verification without assertion stripping')
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--inkai-source', required=True, type=Path)
    parser.add_argument('--output', default=Path('test/corpus/output/compound-lifecycle'), type=Path)
    args = parser.parse_args()
    assert subprocess.check_output(['git', '-C', str(args.inkai_source), 'rev-parse', 'HEAD'], text=True).strip() == REVISION
    assert not subprocess.check_output(['git', '-C', str(args.inkai_source), 'status', '--porcelain', '--untracked-files=no'], text=True).strip()
    sys.path.insert(0, str(args.inkai_source.resolve()))
    inkai = importlib.import_module('inkai')
    rows = json.loads((args.output / 'report.json').read_text())
    requests = {
        (name, variant): 'original' if variant == 'compound' or name in ('metadata', 'batch') else 'compound'
        for name in SOURCES
        for variant in (['release'] if name in ('metadata', 'batch') else ['compound', 'release'])
    }
    assert len(rows) == len(requests) == 10
    assert {(row['source'], row['variant']) for row in rows} == requests.keys()
    for name, checksum in SOURCES.items():
        assert hashlib.sha256((args.output / f'{name}.original.ps').read_bytes()).hexdigest() == checksum
    checked = []
    for row in rows:
        name, variant = row['source'], row['variant']
        assert row['predecessor'] == requests[name, variant]
        verify(inkai, args.output, name, variant, row['predecessor'])
        checked.append(f'{name}/{variant}')
        print(checked[-1], 'passed', flush=True)
    (args.output / 'independent-report.json').write_text(json.dumps(dict(oracleRevision=REVISION, transactions=checked), indent=2) + '\n')


if __name__ == '__main__':
    main()
