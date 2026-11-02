#!/usr/bin/env python3
"""Verify new CC files with pinned inkai, pypdf and unchanged Poppler renders.

Inputs are authored from scratch by check_native_documents.dart, with no producer
template. This establishes native/container interoperability, not Adobe acceptance.
"""

import argparse
import importlib
from pathlib import Path
import subprocess
import sys
import tempfile

from pypdf import PdfReader

from corpus_support import REVISION, native_programs
from verify_native_colors import operators


def sections(items):
    """Walk nested native layers through the independent reader's section model."""
    from inkai.parser.consts import Section
    for item in items:
        if isinstance(item, Section):
            yield item
            yield from sections(item.children)


def renders(path, dpi=72):
    """Render every PDF page and retain exact PPM pixels for deterministic equality."""
    with tempfile.TemporaryDirectory() as directory:
        prefix = Path(directory) / 'page'
        result = subprocess.run(['pdftoppm', '-r', str(dpi), str(path), str(prefix)], check=True, capture_output=True)
        assert b'Syntax Error' not in result.stderr, result.stderr
        return [page.read_bytes() for page in sorted(Path(directory).glob('*.ppm'))]


def main():
    if not __debug__:
        raise RuntimeError('Run verification without assertion stripping')
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--reference', required=True, type=Path)
    parser.add_argument('--output', type=Path, default=Path('test/corpus/output/documents'))
    args = parser.parse_args()
    assert subprocess.check_output(['git', '-C', str(args.reference), 'rev-parse', 'HEAD'], text=True).strip() == REVISION
    assert not subprocess.check_output(['git', '-C', str(args.reference), 'status', '--porcelain', '--untracked-files=no'], text=True).strip()
    sys.path.insert(0, str(args.reference.resolve()))
    inkai = importlib.import_module('inkai')
    for mode in ('rgb', 'cmyk'):
        for blank in (True, False):
            name = f'{mode}-{"blank" if blank else "artwork"}'
            host_path = args.output / f'{name}.pdf'
            host = PdfReader(host_path, strict=True)
            expected_pixels = renders(host_path)
            for edited in (False, True):
                stem = name + ('-edited' if edited else '')
                native = (args.output / f'{stem}.ps').read_bytes()
                parsed = inkai.parse(str(args.output / f'{stem}.ps'))
                setup = [value.asdict() if hasattr(value, 'asdict') else value for value in parsed.setup.children]
                document, = [value for value in setup if isinstance(value, dict) and value.get('_type') == 'Document']
                boards = document['Recorded']['ArtboardArray']
                assert len(boards) == (1 if blank else 2)
                assert document['NotRecorded']['LastArtboardID'] == len(boards)
                assert document['Recorded']['CropAreaActive'] == 0
                for index, board in enumerate(boards):
                    assert board['Name'] == f'\0B\0{index}'
                    assert board['ArtboardUUID'] == f'12345678-1234-4234-8234-{index:012}'
                    assert tuple(board['PositionPoint1']) == ((-10, 80) if index == 0 else (200, 50))
                    assert tuple(board['PositionPoint2']) == ((90, -20) if index == 0 else (320, -30))
                layers = [value for value in sections(parsed.trailer) if value.start == b'%AI5_BeginLayer']
                assert len(layers) == (1 if blank else 2) + edited
                root_layers = [value for value in parsed.trailer if getattr(value, 'start', None) == b'%AI5_BeginLayer']
                assert len(root_layers) == 1 + edited
                assert f'%AI5_NumLayers: {1 + edited}\n'.encode() in native
                assert f'%AI9_ColorModel: {int(mode == "rgb")}\n'.encode() in native
                starts = [list(map(float, value.tokens)) for value in operators(parsed.trailer) if value.command == 'm']
                assert starts == ([] if blank else [[10, 10], [210, 10]])
                fills = [list(map(float, value.tokens)) for value in operators(parsed.trailer) if value.command == ('Xa' if mode == 'rgb' else 'k')]
                assert fills == ([] if blank else ([[1, 0, 0], [0, 0, 1]] if mode == 'rgb' else [[0, 1, 1, 0], [1, 1, 0, 0]]))
                ai_path = args.output / f'{stem}.ai'
                assert native_programs(ai_path) == [native] * len(boards)
                pdf = PdfReader(ai_path, strict=True)
                assert len(pdf.pages) == len(host.pages) == len(boards)
                private_refs = []
                for index, page in enumerate(pdf.pages):
                    illustrator = page['/PieceInfo']['/Illustrator']
                    assert illustrator['/LastModified'] == 'D:20261101130000Z'
                    private_refs.append(illustrator.raw_get('/Private'))
                    private = illustrator['/Private']
                    assert [private[key] for key in ('/ContainerVersion', '/CreatorVersion', '/RoundtripStreamType', '/RoundtripVersion')] == [12, 24, 2, 24]
                    assert int(private['/NumBlock']) > 0
                    assert private['/AIMetaData'].get_data() == native[:native.index(b'%%EndComments\n') + len(b'%%EndComments\n')]
                    assert page.get_contents().get_data() == host.pages[index].get_contents().get_data()
                    assert page.mediabox == host.pages[index].mediabox
                    assert page['/Resources'] == host.pages[index]['/Resources']
                assert all(reference == private_refs[0] for reference in private_refs)
                assert renders(ai_path) == expected_pixels
    print('Verified eight complete AI saves: newly authored RGB/CMYK blank/multipage data, nested layers, subsequent edits, shared Zstandard blocks, current header caches and unchanged host PDF pixels.')


if __name__ == '__main__':
    main()
