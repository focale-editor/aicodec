#!/usr/bin/env python3
"""Check shared native masters/instances and host-composed original/reopened views.

Generate with Focale's ai_symbols_test.dart and FOCALE_AI_NEW_OUTPUT.
Pinned inkai checks literal records; this does not certify Adobe recomposition.
"""

import argparse
from collections import Counter
import json
from pathlib import Path
import subprocess
import sys

from corpus_support import REVISION, native_programs
from verify_focale_group_paints import ghostscript_renders
from verify_native_documents import renders
from verify_native_structure import native_values


def verify_symbols(inkai, output):
    """Resolve every independent parsed reference and compare all matrix entries."""
    cases = sorted(output.glob('symbol-*.json'))
    assert len(cases) >= 18, len(cases)
    for path in cases:
        stem = path.stem
        expected = json.loads(path.read_text())
        native = path.with_suffix('.ps').read_bytes()
        assert native_programs(path.with_suffix('.ai')) == [native], stem
        document = inkai.parse(str(path.with_suffix('.ps')))
        masters = [section.children[0].tokens[0].decode()
                   for section in document.setup.children
                   if getattr(section, 'start', None) == b'%AI14_BeginSymbol']
        panels = [name.decode() for section in document.setup.children
                  if getattr(section, 'start', None) == b'%AI24_BeginSymbolList'
                  for name in section.arguments]
        assert Counter(masters) == Counter(expected['masters']), (stem, masters)
        assert Counter(panels) == Counter(masters), (stem, panels, masters)
        assert len(set(masters)) == len(masters), stem
        instances = [value for value in native_values(document.trailer)
                     if type(value).__name__ == 'SymbolInstance']
        assert len(instances) == len(expected['instances']), stem
        for instance, source in zip(instances, expected['instances']):
            assert instance.SymbolRef == source['master'] and masters.count(instance.SymbolRef) == 1, stem
            assert all(abs(a - b) < 1e-9 for a, b in zip(instance.RTransformMatrix, source['matrix'])), (stem, instance.RTransformMatrix, source['matrix'])
        for dpi in (72, 144):
            actual = renders(path.with_suffix('.ai'), dpi)
            assert actual == renders(output / f'{stem}-reference.pdf', dpi), (stem, dpi, 'original')
            assert actual == renders(output / f'{stem}-reopened.pdf', dpi), (stem, dpi, 'reopened')
        assert ghostscript_renders(path.with_suffix('.ai')) == ghostscript_renders(output / f'{stem}-reference.pdf') == ghostscript_renders(output / f'{stem}-reopened.pdf'), (stem, 'Ghostscript')
        print(stem, 'passed', flush=True)
    print(f'Verified {len(cases)} symbol saves: native names, panels, references, affine placement and original/reopened Poppler/Ghostscript views.')


def main():
    """Use the pinned unchanged external reader on local acceptance artifacts."""
    if not __debug__:
        raise RuntimeError('Run without assertion stripping')
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--reference', required=True, type=Path)
    args = parser.parse_args()
    assert subprocess.check_output(['git', '-C', str(args.reference), 'rev-parse', 'HEAD'], text=True).strip() == REVISION
    assert not subprocess.check_output(['git', '-C', str(args.reference), 'status', '--porcelain', '--untracked-files=no'], text=True).strip()
    sys.path.insert(0, str(args.reference.resolve()))
    import inkai
    verify_symbols(inkai, args.output)


if __name__ == '__main__':
    main()
