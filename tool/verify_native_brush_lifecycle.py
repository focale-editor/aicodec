#!/usr/bin/env python3
"""Verify authored brush descriptors and panels independently of the Dart parser."""

import argparse
import importlib
from pathlib import Path
import subprocess
import sys

from pypdf import PdfReader

from corpus_support import REVISION, native_programs
from verify_native_artboard_brush_descriptors import descriptor_state
from verify_native_documents import renders


def descriptors(document):
    """Decode literal descriptor continuations through the pinned native reader."""
    result = {}
    for section in document.setup.all_subsections_of_type_recursive(b'%AI8_BeginPluginObject'):
        values = section.arguments
        if values[0] != b'Adobe Brush Manager Order':
            result[values[0], values[1]] = b''.join(values[2::2])
    return result


def main():
    """Require all four families, repeated saves and exact untouched page pixels."""
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
    host = PdfReader(args.output / 'host.pdf', strict=True)
    pixels = renders(args.output / 'host.pdf')
    plugins = dict(calligraphic=b'Adobe Calligraphic Brush Tool', art=b'Adobe ArtOnPath Brush Tool', pattern=b'Adobe PatternOnPath Brush Tool', bristle=b'Adobe dBrush Brush Tool')
    for kind, plugin in plugins.items():
        body = None
        for phase in ('created', 'replaced', 'removed'):
            stem = f'{kind}-{phase}'
            data = (args.output / f'{stem}.ps').read_bytes()
            document = inkai.parse(str(args.output / f'{stem}.ps'))
            state = descriptor_state(document)
            assert not state['references']
            definitions = descriptors(document)
            if phase == 'removed':
                assert not definitions
            else:
                payload, = definitions.values()
                assert list(definitions) == [(plugin, b'Brush (\xe9)\\')]
                revised = phase == 'replaced'
                if kind == 'calligraphic':
                    assert list(map(float, payload.split())) == ([1, 7, 7, 25, 25, 30, 30, 0, 0, 0, 0] if revised else [1, 5, 5, 100, 100, 0, 0, 0, 0, 0, 0])
                elif kind in ('art', 'pattern'):
                    fields = [value.strip() for value in payload.split(b'/')]
                    assert fields[:7] == [b'2', b'Tile', b'', b'', b'', b'', b'0 0']
                    assert fields[7] == (b'5 0.2 0.4 0.6' if revised else b'0 1')
                    assert fields[8] == b'1 0 1 0 1 0 0 0 1 1 0 1 25 25 1'
                else:
                    assert payload.split()[3] == (b'0.25' if revised else b'0.75')
                    assert payload.split()[8:] == [b'AI_BristleBrushLibary_CS5', b'05_Round_Fan']
            current = data[data.index(b'%%EndSetup'):]
            body = current if body is None else body
            assert current == body
            ai = args.output / f'{stem}.ai'
            assert native_programs(ai) == [data]
            saved = PdfReader(ai, strict=True)
            assert len(saved.pages) == len(host.pages) == 1
            assert saved.pages[0].get_contents().get_data() == host.pages[0].get_contents().get_data()
            assert renders(ai) == pixels
            print(stem, 'passed', flush=True)
    print('Verified twelve descriptor saves, literal panel references and unchanged host PDF pixels.')


if __name__ == '__main__':
    main()
