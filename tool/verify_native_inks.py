#!/usr/bin/env python3
"""Verify global ink references with pinned inkai and independent PDF decoding.

Checks stored alternatives, tints, ramps, names, mesh controls and supplied PDF
content. This is not Adobe Illustrator or native/PDF visual-equivalence evidence.
"""

import argparse
import importlib
from pathlib import Path
import subprocess
import sys

from pypdf import PdfReader

from corpus_support import REVISION, native_programs
from verify_native_colors import operators
from verify_native_mesh_geometry import read_packet


def main():
    """Require two complete revisions of direct and appearance-backed inks."""
    if not __debug__:
        raise RuntimeError('Run verification without assertion stripping')
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--reference', required=True, type=Path)
    parser.add_argument('--output', default=Path('test/corpus/output/inks'), type=Path)
    args = parser.parse_args()
    assert subprocess.check_output(['git', '-C', str(args.reference), 'rev-parse', 'HEAD'], text=True).strip() == REVISION
    assert not subprocess.check_output(['git', '-C', str(args.reference), 'status', '--porcelain', '--untracked-files=no'], text=True).strip()
    sys.path.insert(0, str(args.reference.resolve()))
    inkai = importlib.import_module('inkai')
    from inkai.parser.hierarchy_objects import KnownStyle

    for family in ('references', 'appearance'):
        for revision, cyan in ((1, .2), (2, .9)):
            stem = f'{family}-{revision}'
            path = args.output / f'{stem}.ps'
            native = path.read_bytes()
            document = inkai.parse(str(path))
            cmyk, rgb = [cyan, .3, .4, .5], [.6, .7, .8]
            named = [op for op in operators([document.setup, document.trailer]) if op.command in ('x', 'X', 'Xx', 'XX', 'Xs', 'XS', 'Xz', 'XZ')]
            selected, other = [], []
            for op in named:
                count = 7 if op.command in ('Xz', 'XZ') else 3 if op.command in ('Xx', 'XX') and op.tokens[-1] == b'1' else 4
                # The pinned reader retains hex-string names as lexical tokens.
                name = op.tokens[count]
                if name.startswith(b'<') and name.endswith(b'>'):
                    name = bytes.fromhex(name[1:-1].decode('ascii'))
                if name == b'Ink':
                    expected = cmyk + rgb if count == 7 else rgb if count == 3 else cmyk
                    assert list(map(float, op.tokens[:count])) == expected, (stem, op)
                    selected.append(float(op.tokens[count + 1]))
                else:
                    assert name == b'Other'
                    assert list(map(float, op.tokens[:count])) == [0, 0, 0, 1]
                    other.append(float(op.tokens[count + 1]))
            if family == 'references':
                assert sorted(selected) == [.25, .3, .4, .5, .6, 1] and other == [.7]
                gradients = list(document.setup.all_subsections_of_type_recursive(b'%AI5_BeginGradient:'))
                assert len(gradients) == 2
                for gradient in gradients:
                    assert gradient.name == 'Gradient'
                    for command in ('Bs', '%_BS'):
                        stops = [value for value in gradient.children if getattr(value, 'command', None) == command]
                        assert len(stops) == 2
                        assert [stop.ramp_point for stop in stops] == [100, 0]
                        assert all(list(map(float, stop.tokens[:4])) == cmyk for stop in stops)
                        assert [float(stop.tokens[5]) for stop in stops] == [.9, .2]
                        assert all(stop.tokens[4] == b'Ink' for stop in stops)
                    ramps = [op for op in operators(gradient) if op.command == '%_Br']
                    assert len(ramps) == 1
                    assert list(map(float, ramps[0].tokens)) == cmyk + [.6, 2]
                packet, size, patches = read_packet(native)
                assert size == (1, 1)
                assert patches[(0, 0)][0] == ('R', [-1.0])
                corners = [node for node in patches[(0, 0)] if node[0] == 'N']
                assert len(corners) == 4 and all(node[1] == [.4, .7, 1] for node in corners)
                assert f'[[{cyan} 0.3 0.4 0.5 /DeviceCMYK (Ink) /Separation] [0 1 0 0 /DeviceCMYK (Other) /Separation] 2 /NChannel]'.encode() in native
                assert f'%%CMYKCustomColor: {cyan} 0.3 0.4 0.5 (Ink)'.encode() in native
                assert b'%%DocumentCustomColors: (Ink) (Other)' in native
            else:
                assert selected == [.5] and not other
                styles = [value for value in document.setup.children if isinstance(value, KnownStyle)]
                assert len(styles) == 1 and styles[0].Name == 'Shared'
                uses = [op.tokens for op in operators(document.trailer) if op.command == 'XW' and op.tokens[0] == b'1']
                assert uses == [[b'1', b'Shared']] * 2
                assert [list(map(float, op.tokens)) for op in operators(document.trailer) if op.command == 'Xa'] == [[.7, .6, .5]] * 2
            saved = args.output / f'{stem}.ai'
            programs = native_programs(saved)
            assert len(programs) == 2 and all(program == native for program in programs), stem
            pdf = PdfReader(saved, strict=True)
            assert len(pdf.pages) == 2
            content = f'q {cyan} 0.3 0.4 0.5 k 0 0 10 10 re f Q'.encode()
            assert all(page.get_contents().get_data() == content for page in pdf.pages), stem
            print(stem, 'passed', flush=True)
    print('Verified four complete global-ink saves: paints, palettes, paired gradient banks, mesh alternatives, DSC caches, shared appearance printing and repeated saves.')


if __name__ == '__main__':
    main()
