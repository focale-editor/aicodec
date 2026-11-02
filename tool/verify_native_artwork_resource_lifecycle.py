#!/usr/bin/env python3
"""Check authored native libraries with pinned inkai and unchanged host PDF pages.

Library definitions are unused: page rendering verifies preservation, not the
appearance of placed symbols, brush strokes or pattern applications in Illustrator.
"""

import argparse
import importlib
from pathlib import Path
import subprocess
import sys
from types import SimpleNamespace

from pypdf import PdfReader

from corpus_support import REVISION, native_programs
from verify_native_artwork_resources import WRAPPERS
from verify_native_documents import renders
from verify_native_group_lifecycle import inventory


def main():
    """Verify exact native geometry, resource names and repeated saved containers."""
    if not __debug__:
        raise RuntimeError('Run verification without assertion stripping')
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--reference', type=Path, required=True)
    parser.add_argument('--output', type=Path, default=Path('test/corpus/output/artwork-resource-lifecycle'))
    args = parser.parse_args()
    assert subprocess.check_output(['git', '-C', str(args.reference), 'rev-parse', 'HEAD'], text=True).strip() == REVISION
    assert not subprocess.check_output(['git', '-C', str(args.reference), 'status', '--porcelain', '--untracked-files=no'], text=True).strip()
    sys.path.insert(0, str(args.reference.resolve()))
    inkai = importlib.import_module('inkai')
    host_path = args.output / 'host.pdf'
    host = PdfReader(host_path, strict=True)
    pixels = renders(host_path)
    for kind, wrapper in WRAPPERS.items():
        body = None
        for phase in ('created', 'replaced', 'removed'):
            stem = f'{kind}-{phase}'
            path = args.output / f'{stem}.ps'
            data = path.read_bytes()
            document = inkai.parse(str(path))
            for other, marker in WRAPPERS.items():
                if other != kind:
                    assert not list(document.setup.all_subsections_of_type_recursive(marker))
            panels = list(document.setup.all_subsections_of_type_recursive(b'%AI24_BeginSymbolList'))
            assert len(panels) == (1 if kind == 'symbol' else 0)
            if panels:
                assert panels[0].arguments == ([] if phase == 'removed' else [b'Resource (\xe9)\\'])
            resources = list(document.setup.all_subsections_of_type_recursive(wrapper))
            assert len(resources) == (0 if phase == 'removed' else 1)
            if resources:
                resource, = resources
                header = resource.children[0]
                assert header.command == 'A' and header.tokens[0] == b'Resource (\xe9)\\'
                if kind == 'pattern':
                    assert list(map(float, header.tokens[1:5])) == ([-2, -3, 18, 17] if phase == 'created' else [0, 0, 30, 40])
                _, groups, paths = inventory(SimpleNamespace(trailer=resource.children[1:]))
                assert len(groups) == len(paths) == 1
                path, = paths
                assert path['private'] and path['paint'] == 'f' and path['count'] == 3
                assert path['geometry'] == [('m', (b'0', b'0')), ('L', (b'12', b'0')), ('L', (b'12', b'8')), ('L', (b'0', b'0'))]
                assert path['state']['fill'] == ('g', (b'0.25' if phase == 'created' else b'0.75',))
            current_body = data[data.index(b'%%EndSetup'):]
            if body is None:
                body = current_body
            assert current_body == body
            ai_path = args.output / f'{stem}.ai'
            assert native_programs(ai_path) == [data]
            saved = PdfReader(ai_path, strict=True)
            assert len(saved.pages) == len(host.pages) == 1
            assert saved.pages[0].get_contents().get_data() == host.pages[0].get_contents().get_data()
            assert saved.pages[0].mediabox == host.pages[0].mediabox
            assert renders(ai_path) == pixels
            print(stem, 'passed', flush=True)
    print('Verified nine native library saves and unchanged host PDF pixels; Illustrator exchange remains unverified.')


if __name__ == '__main__':
    main()
