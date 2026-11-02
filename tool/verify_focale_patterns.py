#!/usr/bin/env python3
"""Verify Focale's native pattern tiles, complete saves and independent PDF pixels.

Native declarations are parsed by pinned inkai. It does not render AI patterns;
Poppler checks the synchronized PDF against the original and reopened host scenes.
This is not an Illustrator editability or native rendering acceptance result.
"""

import argparse
import importlib
from pathlib import Path
import subprocess
import sys
from types import SimpleNamespace

from pypdf import PdfReader

from corpus_support import REVISION, native_programs
from verify_native_documents import renders
from verify_native_group_lifecycle import inventory
from verify_native_structure import native_values


def verify_patterns(inkai, output):
    """Verify all pattern revisions with an already-pinned independent reader."""
    for base in ('pattern-fill', 'pattern-stroke', 'pattern-edited-1', 'pattern-edited-2'):
        for reopened in (False, True):
            stem = base + ('-reopened' if reopened else '')
            ai_path = output / f'{stem}.ai'
            reference = output / f'{stem}-reference.pdf'
            data = (output / f'{stem}.ps').read_bytes()
            assert native_programs(ai_path) == [data]
            native = inkai.parse(str(output / f'{stem}.ps'))
            resources = list(native.setup.all_subsections_of_type_recursive(b'%AI3_BeginPattern:'))
            count = 1 if 'edited' not in base else int(base[-1]) + 1
            assert len(resources) == count
            names = []
            for index, resource in enumerate(resources):
                header = resource.children[0]
                names.append(header.tokens[0])
                assert list(map(float, header.tokens[1:5])) == [0, 0, 8, 6]
                _, _, paths = inventory(SimpleNamespace(trailer=resource.children[1:]))
                path, = paths
                assert path['private'] and path['paint'] == 'f'
                operator, channels = path['state']['fill']
                assert operator == 'Xa'
                assert tuple(map(float, channels)) == ((0, 170 / 255, 85 / 255), (34 / 255, 68 / 255, 1), (1, 102 / 255, 0))[index]
                assert [(op, tuple(map(float, values))) for op, values in path['geometry']] == [('m', (0, 0)), ('L', (5, 0)), ('L', (0, 3)), ('L', (0, 0))]
            styles = [value for value in native_values(native.setup) if type(value).__name__ == 'KnownStyle']
            paints = [value for value in native_values(styles) if getattr(value, 'command', None) in ('p', 'P')]
            assert paints
            for paint in paints:
                assert paint.tokens[0] in names
                assert [paint.px, paint.py, paint.sx, paint.sy, paint.angle, paint.rf, paint.r, paint.k, paint.ka] == [0, 0, 1, 1, 0, 0, 0, 0, 0]
                assert len(paint.tfm) == 6 and abs(paint.tfm[0] * paint.tfm[3] - paint.tfm[1] * paint.tfm[2]) > 0
            assert paints[-1].command == ('P' if base == 'pattern-stroke' else 'p')
            if 'edited' not in base:
                assert paints[-1].tfm == [.6, -.1, .05, -.4, 1, -.5]
            saved, expected = PdfReader(ai_path, strict=True), PdfReader(reference, strict=True)
            assert len(saved.pages) == len(expected.pages) == 1
            assert saved.pages[0].mediabox == expected.pages[0].mediabox
            assert renders(ai_path) == renders(reference)
            print(stem, 'passed', flush=True)
    print('Verified eight pattern comparisons across four complete saves and original/reopened host PDF views.')


def main():
    """Check actual saved library geometry, paint references and full PDF pages."""
    if not __debug__:
        raise RuntimeError('Run verification without assertion stripping')
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--reference', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    assert subprocess.check_output(['git', '-C', str(args.reference), 'rev-parse', 'HEAD'], text=True).strip() == REVISION
    assert not subprocess.check_output(['git', '-C', str(args.reference), 'status', '--porcelain', '--untracked-files=no'], text=True).strip()
    sys.path.insert(0, str(args.reference.resolve()))
    inkai = importlib.import_module('inkai')
    verify_patterns(inkai, args.output)


if __name__ == '__main__':
    main()
