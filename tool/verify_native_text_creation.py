#!/usr/bin/env python3
"""Verify text initialization with independent ATE, native and PDF readers.

Created stories deliberately remain uncomposed and are not saved with a blank
PDF. Complete AI cases have no stories and retain initialized typography.
"""

import argparse
import importlib
import io
from pathlib import Path
import subprocess
import sys

from pypdf import PdfReader

from corpus_support import REVISION, native_programs
from verify_native_text import field
from verify_native_text_paints import native_payload


def main():
    if not __debug__:
        raise RuntimeError('Run verification without assertion stripping')
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--reference', required=True, type=Path)
    parser.add_argument('--output', type=Path, default=Path('test/corpus/output/text-creation'))
    args = parser.parse_args()
    assert subprocess.check_output(['git', '-C', str(args.reference), 'rev-parse', 'HEAD'], text=True).strip() == REVISION
    assert not subprocess.check_output(['git', '-C', str(args.reference), 'status', '--porcelain', '--untracked-files=no'], text=True).strip()
    sys.path.insert(0, str(args.reference.resolve()))
    inkai = importlib.import_module('inkai')
    reader = importlib.import_module('inkai.parser.text').TextDocumentParser
    stream = importlib.import_module('inkai.parser.streamreader').StreamWrapper
    undo = None
    for name, count in [('initial', 0), ('created', 1), ('copied', 2), ('removed', 1), ('empty', 0)]:
        native = (args.output / f'{name}.ps').read_bytes()
        payload = (args.output / f'{name}.ate').read_bytes()
        assert native_payload(native)[0] == payload
        inkai.parse(str(args.output / f'{name}.ps'))
        document = reader.read_object(stream(io.BytesIO(payload)))
        resources = field(document, '0', 'DocumentResources')
        objects = field(document, '1', 'DocumentObjects')
        stories = field(objects, '1', 'TextObjects')
        assert len(stories) == count
        assert [field(field(story, '0', 'Model'), '0', 'Text') for story in stories] == ['Bonjour 🖋\rSuite\r'] * count
        fonts = field(field(resources, '1', 'FontSet'), '0', 'Resources')
        assert len(fonts) == 1
        identifier = field(field(fonts[0], '0', 'Resource'), '0', 'Identifier')
        assert field(identifier, '0', 'Name') == 'DejaVuSans'
        assert field(identifier, '2', 'Type') == 1
        assert field(identifier, '5', 'VersionString') == 'Version 2.37'
        styles = field(field(resources, '5', 'StyleSheetSet'), '0', 'Resources')
        normal = field(styles[0], '0', 'Resource')
        assert field(normal, '0', 'Name') == 'Corps 🖋'
        features = field(normal, '6', 'Features')
        assert field(features, '0', 'Font') == 0 and field(features, '1', 'FontSize') == 14
        assert field(features, '8', 'Tracking') == 12
        frames = field(field(resources, '8', 'TextFrameSet'), '0', 'Resources')
        assert len(frames) == count
        actual_undo = (args.output / f'{name}.undo.ate').read_bytes()
        undo = actual_undo if undo is None else undo
        assert actual_undo == undo
        auxiliary = reader.read_object(stream(io.BytesIO(actual_undo)))
        assert field(field(auxiliary, '1', 'DocumentObjects'), '1', 'TextObjects') == []
        if count == 0:
            path = args.output / f'{name}.ai'
            assert native_programs(path) == [native]
            pdf = PdfReader(path, strict=True)
            assert len(pdf.pages) == 1 and pdf.pages[0].get_contents().get_data().strip() == b''
            header = pdf.pages[0]['/PieceInfo']['/Illustrator']['/Private']['/AIMetaData'].get_data()
            assert b'%%DocumentFonts: DejaVuSans\n' in header
            assert b'%%DocumentNeededFonts: DejaVuSans\n' in header
    print('Verified five newly authored ATE snapshots, unchanged independent undo typography and two complete font-initialized AI saves.')


if __name__ == '__main__':
    main()
