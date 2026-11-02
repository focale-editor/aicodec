#!/usr/bin/env python3
"""Check heterogeneous authoring, references and original/reopened PDF pixels.

Generate with Focale's ai_mixed_appearance_test.dart and FOCALE_AI_NEW_OUTPUT.
This is independent format/rendering evidence, not Illustrator recomposition.
"""

import argparse
import importlib
import io
from pathlib import Path
import subprocess
import sys

from corpus_support import REVISION, native_programs
from verify_focale_group_paints import ghostscript_renders
from verify_native_documents import renders
from verify_native_rasters import images
from verify_native_structure import native_values
from verify_native_text import field, resources
from verify_native_text_paints import native_payload


def verify_mixed_appearances(inkai, output):
    """Require native editable families, coherent ATE references and exact views."""
    reader = importlib.import_module('inkai.parser.text').TextDocumentParser
    stream = importlib.import_module('inkai.parser.streamreader').StreamWrapper
    cases = {
        'mixed-original': ['Ofi\rO\r'],
        'mixed-edited': ['O\rfi\rO\r'],
        'mixed-added': ['fi\r'],
        'mixed-clipped': ['Ofi\rO\r'],
        'mixed-copied': ['Ofi\rO\r', 'Ofi\rO\r'],
        'mixed-removed': ['Ofi\rO\r'],
        'mixed-mask': [],
        'mixed-mask-edited': [],
    }
    for stem, expected in cases.items():
        path = output / f'{stem}.ai'
        native = (output / f'{stem}.ps').read_bytes()
        assert native_programs(path) == [native], stem
        parsed = inkai.parse(str(output / f'{stem}.ps'))
        values = list(native_values(parsed.trailer))
        identifiers = [value['AI10_ArtUID'] for value in values if isinstance(value, dict) and 'AI10_ArtUID' in value]
        assert len(identifiers) == len(set(identifiers)), stem
        assert any(isinstance(value, dict) and 'ai::LiveShape' in value for value in values), stem
        assert b'%_/Mesh X!' in native, stem
        small = [image for image in images(parsed) if image.w == image.h == 2]
        assert len(small) == (2 if stem == 'mixed-copied' else 1), stem
        for image in small:
            assert image.bits == 8 and image.is_binary == 1 and image.image_type == 3 and image.alpha_channel_count == 1, stem
            raw = image.data.decoded + image.data.additional_decoded
            assert raw[:16] == bytes([255, 0, 0, 0, 255, 0, 0, 0, 255, 255, 255, 0, 255, 128, 64, 255]), stem
            assert raw[16:] in (b'', b'\n', b'%_', b'\n%_'), stem
        document = reader.read_object(stream(io.BytesIO(native_payload(native)[0])))
        stories = field(field(document, '1', 'DocumentObjects'), '1', 'TextObjects')
        assert [field(field(story, '0', 'Model'), '0', 'Text') for story in stories] == expected, stem
        frames = resources(document, '8', 'TextFrameSet')
        assert len(frames) == len(expected), stem
        references = [value for value in values if type(value).__name__ == 'AI11Text']
        assert sorted((value._story_index, value._frame_index) for value in references) == [(index, 0) for index in range(len(expected))], stem
        for dpi in (72, 144):
            actual = renders(path, dpi)
            assert actual == renders(output / f'{stem}-reference.pdf', dpi), (stem, dpi, 'original')
            assert actual == renders(output / f'{stem}-reopened.pdf', dpi), (stem, dpi, 'reopened')
        assert ghostscript_renders(path) == ghostscript_renders(output / f'{stem}-reference.pdf') == ghostscript_renders(output / f'{stem}-reopened.pdf'), (stem, 'Ghostscript')
        print(stem, 'passed', flush=True)
    print(f'Verified {len(cases)} heterogeneous saves with independent native/ATE readers and original/reopened Poppler 72/144 dpi and Ghostscript 72 dpi comparisons.')


def main():
    """Load only the pinned independent reader used by the acceptance corpus."""
    if not __debug__:
        raise RuntimeError('Run without assertion stripping')
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--reference', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    assert subprocess.check_output(['git', '-C', str(args.reference), 'rev-parse', 'HEAD'], text=True).strip() == REVISION
    assert not subprocess.check_output(['git', '-C', str(args.reference), 'status', '--porcelain', '--untracked-files=no'], text=True).strip()
    sys.path.insert(0, str(args.reference.resolve()))
    verify_mixed_appearances(importlib.import_module('inkai'), args.output)


if __name__ == '__main__':
    main()
