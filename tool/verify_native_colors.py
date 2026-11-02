#!/usr/bin/env python3
"""Check color lifecycle/application saves with independent pinned native/PDF readers.

This verifies stored data and supplied PDF content, not Adobe rendering or global
ink redefinition. No original producer artwork is rewritten for these fixtures.
"""

import argparse
import importlib
from pathlib import Path
import subprocess
import sys

from pypdf import PdfReader

from corpus_support import REVISION, native_programs


def operators(value):
    """Traverse source operators without executing paint or decoding text caches."""
    from inkai.parser.consts import Section
    from inkai.parser.hierarchy_objects import HierarchyObject
    from inkai.parser.operators import Operator
    if isinstance(value, Operator):
        yield value
    elif isinstance(value, Section):
        yield from operators(value.children)
    elif isinstance(value, HierarchyObject):
        yield from operators(vars(value))
    elif isinstance(value, dict):
        for child in value.values():
            yield from operators(child)
    elif isinstance(value, (list, tuple)):
        for child in value:
            yield from operators(child)


def main():
    if not __debug__:
        raise RuntimeError('Run verification without assertion stripping')
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--reference', required=True, type=Path)
    parser.add_argument('--output', type=Path, default=Path('test/corpus/output/colors'))
    args = parser.parse_args()
    assert subprocess.check_output(['git', '-C', str(args.reference), 'rev-parse', 'HEAD'], text=True).strip() == REVISION
    assert not subprocess.check_output(['git', '-C', str(args.reference), 'status', '--porcelain', '--untracked-files=no'], text=True).strip()
    sys.path.insert(0, str(args.reference.resolve()))
    inkai = importlib.import_module('inkai')
    from inkai.parser.hierarchy_objects import KnownStyle
    pdf_content = b'q 0 g 0 0 10 10 re f 1 g 10 0 10 10 re f 0 g 10 20 20 20 re f Q'
    for name in ('selected', 'named', 'banks', 'removed'):
        native = (args.output / f'{name}.ps').read_bytes()
        document = inkai.parse(str(args.output / f'{name}.ps'))
        gradients = list(document.setup.all_subsections_of_type_recursive(b'%AI5_BeginGradient:'))
        styles = [value for value in document.setup.children if isinstance(value, KnownStyle)]
        counts = [int(value.tokens[0]) for value in document.setup.children if getattr(value, 'command', None) == 'Bn']
        if name == 'selected':
            assert counts == [2] and {value.name for value in gradients} == {'Old', 'Hard'}
            hard, = [value for value in gradients if value.name == 'Hard']
            for command in ('Bs', '%_BS'):
                stops = [value for value in hard.children if getattr(value, 'command', None) == command]
                assert [value.ramp_point for value in stops] == [100, 50, 50, 0]
                assert [value.gray for value in stops] == [[1], [1], [0], [0]]
            assert len(styles) == 2
            assert styles[0].Name == 'Shared' and styles[1].Name == 'Selected gradient'
            assert [[value.tokens[1] for value in operators(style) if value.command == 'Bg'] for style in styles] == [[b'Old', b'Old'], [b'Hard', b'Old']]
            uses = [value.tokens for value in operators(document.trailer) if value.command == 'XW' and value.tokens[0] == b'1']
            assert uses == [[b'1', b'Selected gradient'], [b'1', b'Shared']]
            palette, = document.setup.all_subsections_of_type_recursive(b'%AI5_BeginPalette')
            cells = [value.tokens[0] for value in operators(palette) if value.command == 'Pc']
            assert cells == [b'Process', b'Named', b'Hard swatch']
            named, = [value for value in operators(palette) if value.command == 'Xs']
            assert list(map(float, named.tokens[:4])) == [0, .5, .75, 0] and named.tokens[4] == b'Ink' and float(named.tokens[5]) == .25
            dual, = [value for value in operators(palette) if value.command == 'Xa']
            assert list(map(float, dual.tokens)) == [.1, .2, .3, .4, .2, .3, .4]
        elif name == 'named':
            assert len(styles) == 1
            named, = [value for value in operators(styles[0]) if value.command == 'Xz']
            assert list(map(float, named.tokens[:7])) == [0, .5, .75, 0, .2, .3, .4]
            assert named.tokens[7] == b'Ink' and float(named.tokens[8]) == .75 and named.tokens[9] == b'1'
            assert len([value for value in operators(document.trailer) if value.command == 'XW' and value.tokens == [b'1', b'Shared']]) == 2
        elif name == 'banks':
            assert counts == [1, 1] and len(gradients) == 2
            for gradient in gradients:
                assert gradient.name == 'Edge'
                for command in ('Bs', '%_BS'):
                    stops = [value for value in gradient.children if getattr(value, 'command', None) == command]
                    assert [value.ramp_point for value in stops] == [0, 50, 50, 100]
                    assert [value.gray for value in stops] == [[0], [.2], [.8], [1]]
        else:
            assert counts == [0, 0] and not gradients
            assert b'Edge' not in native
        saved = args.output / f'{name}.ai'
        assert all(program == native for program in native_programs(saved))
        pdf = PdfReader(saved)
        assert len(pdf.pages) == 2
        assert all(page.get_contents().get_data() == pdf_content for page in pdf.pages)
    print('Verified four complete AI saves: ordered hard stops, selected applications, named alternatives/tints, palettes and counted resource deletion.')


if __name__ == '__main__':
    main()
