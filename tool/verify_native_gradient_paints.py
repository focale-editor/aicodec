#!/usr/bin/env python3
"""Inspect authored CC gradient styles with pinned inkai and pypdf.

The supplied placeholder PDF/printing does not establish appearance equivalence.
Native coordinate interpretation and Illustrator editing need host acceptance.
"""

import argparse
import importlib
from pathlib import Path
import subprocess
import sys

from pypdf import PdfReader

from corpus_support import REVISION, native_programs
from verify_native_structure import native_values


def main():
    """Check reference bytes, CC layout, paint channel and whole-file ownership."""
    if not __debug__:
        raise RuntimeError('Run verification without assertion stripping')
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--reference', required=True, type=Path)
    parser.add_argument('--output', type=Path, default=Path('test/corpus/output/gradient-paints'))
    args = parser.parse_args()
    assert subprocess.check_output(['git', '-C', str(args.reference), 'rev-parse', 'HEAD'], text=True).strip() == REVISION
    assert not subprocess.check_output(['git', '-C', str(args.reference), 'status', '--porcelain', '--untracked-files=no'], text=True).strip()
    sys.path.insert(0, str(args.reference.resolve()))
    inkai = importlib.import_module('inkai')
    for radial in (False, True):
        for stroke in (False, True):
            name = ('radial' if radial else 'linear') + ('-stroke' if stroke else '-fill')
            source = args.output / f'{name}.ps'
            container = args.output / f'{name}.ai'
            assert native_programs(container) == [source.read_bytes()]
            assert len(PdfReader(container, strict=True).pages) == 1
            document = inkai.parse(str(source))
            styles = [value for value in native_values(document.setup) if type(value).__name__ == 'KnownStyle']
            assert len(styles) == 1
            commands = [value for value in native_values(styles[0]) if getattr(value, 'command', None) in ('Bb', 'Bg', 'BB')]
            assert [value.command for value in commands] == ['Bb', 'Bg', 'BB']
            assert commands[0].tokens == ([b'1'] if stroke else [])
            operands = commands[1].tokens
            assert operands[0] == b'2' and operands[1] == b'Gradient (shared)'
            assert list(map(float, operands[2:])) == [-.25, .125, 37, 1.25, 1, .2, -.3, 2, .1, -.4, .75]
            assert commands[2].tokens == [b'1' if stroke else b'0']
            definitions = [value for value in native_values(document.setup) if getattr(value, 'command', None) == 'Bd']
            assert definitions and all(value.tokens[0] == b'Gradient (shared)' and int(value.tokens[1]) == int(radial) for value in definitions)
            print(name, 'passed')
    print('Verified four relative CC gradient paints and complete containers; no rendering claim.')


if __name__ == '__main__':
    main()
