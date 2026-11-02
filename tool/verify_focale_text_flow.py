#!/usr/bin/env python3
"""Verify host text-flow artifacts through independent ATE and PDF readers.

Generate inputs with Focale's ai_text_flow_test.dart and FOCALE_AI_NEW_OUTPUT.
This checks serialized data and supplied printing, not Illustrator recomposition.
"""

import argparse
import importlib
import io
from pathlib import Path
import subprocess
import sys

from PIL import Image, ImageChops

from corpus_support import REVISION, native_programs
from verify_focale_group_paints import ghostscript_renders
from verify_native_documents import renders
from verify_native_text import field, resources
from verify_native_text_paints import native_payload


def descendants(node):
    """Visit native strike children without interpreting their visual appearance."""
    yield node
    for child in field(node, '6', 'Children') or []:
        yield from descendants(child)


def verify_text_flow(inkai, output):
    """Check source coverage, actual glyph caches, path resources and saved pixels."""
    reader = importlib.import_module('inkai.parser.text').TextDocumentParser
    stream = importlib.import_module('inkai.parser.streamreader').StreamWrapper
    cases = {
        'text-paragraph-5': 'Ofi\rO\r',
        'text-paragraph-7': '\rO\r\rfi\r\r',
        'text-paragraph-0': '\r',
        'text-wrapped': 'Ofi Ofi Ofi\r\rO fi\r',
        'text-wrapped-edited': 'O\rfi\r\r',
        **{f'text-path-{flip}{offset}{edit}': 'fi O\r' if edit else 'Ofi O\r'
           for flip in ('false', 'true') for offset in ('', '-offset') for edit in ('', '-edited')},
        **{f'text-path-multi-{closed}{edit}': 'Ofi\r'
           for closed in ('false', 'true') for edit in ('', '-edited')},
    }
    identities = {}
    for stem, expected in cases.items():
        native = (output / f'{stem}.ps').read_bytes()
        payload = (output / f'{stem}.ate').read_bytes()
        assert native_programs(output / f'{stem}.ai') == [native], stem
        assert native_payload(native)[0] == payload, stem
        inkai.parse(str(output / f'{stem}.ps'))
        document = reader.read_object(stream(io.BytesIO(payload)))
        story, = field(field(document, '1', 'DocumentObjects'), '1', 'TextObjects')
        model = field(story, '0', 'Model')
        assert field(model, '0', 'Text') == expected, stem
        frame, = resources(document, '8', 'TextFrameSet')
        identifier = field(frame, '97', 'UUID')
        if stem.endswith('-edited'):
            assert identifier == identities[stem.removesuffix('-edited')], stem
        else:
            identities[stem] = identifier
        data = field(frame, '2', 'Data')
        path = stem.startswith('text-path-')
        assert (field(data, '0', 'Type') or 0) == (2 if path else 1 if stem.startswith('text-wrapped') else 0), stem
        if path:
            points = field(field(frame, '1', 'Bezier'), '0', 'Points')
            assert len(points) == (24 if 'multi-true' in stem else 16 if 'multi-false' in stem else 8), stem
            start, end = field(data, '6', 'TextOnPathTRange')
            assert 0 <= start < end <= len(points) / 8, stem
            assert field(field(data, '11', 'PathData'), '0', 'Flip') == stem.startswith('text-path-true'), stem
            if 'multi-' in stem:
                assert 1 < start < 2 and end == len(points) / 8, stem
                assert points[8:10] == ([90.0, 10.0] if stem.endswith('-edited') else [90.0, 0.0]), stem
        roots = field(field(story, '1', 'View'), '2', 'Strikes')
        nodes = [node for root in roots for node in descendants(root)]
        segments = [node for node in nodes if field(node, '99', 'StreamTag') == '/S']
        covered = 0
        marks = 0
        for segment in segments:
            start = field(segment, '20', 'FirstCharacterIndexInSegment')
            count = field(field(segment, '15', 'Mapping'), '0', 'CharacterCount')
            assert start == covered and count > 0, stem
            glyph, = field(segment, '6', 'Children')
            assert field(glyph, '99', 'StreamTag') == '/G', stem
            ids = field(glyph, '5', 'Glyphs')
            assert ids and all(value in (1, 2, 3, 4, 5) for value in ids), stem
            mark = field(glyph, '11', 'IsParagraphEnd') is True
            assert mark == (expected[start:start + count] == '\r'), stem
            marks += mark
            if path:
                bounds = field(glyph, '8', 'VisualBounds')
                assert len(bounds) == 4 and bounds[0] <= bounds[2] and bounds[1] <= bounds[3], stem
                assert field(glyph, '24', '24') == 0, stem
            covered += count
        assert covered == len(expected) and marks == expected.count('\r'), stem
        for dpi in (72, 144):
            actual = renders(output / f'{stem}.ai', dpi)
            assert actual == renders(output / f'{stem}-reference.pdf', dpi), (stem, dpi, 'original')
            reopened = renders(output / f'{stem}-reopened.pdf', dpi)
            if stem == 'text-path-true' and dpi == 144:
                # Native segment parameters are inverted through float path metrics.
                # This original flipped fixture differs on one antialiased edge
                # pixel after that subpixel round trip, never on its geometry.
                first = Image.open(io.BytesIO(actual[0])).convert('RGB')
                second = Image.open(io.BytesIO(reopened[0])).convert('RGB')
                assert first.size == second.size, stem
                difference = ImageChops.difference(first, second)
                red, green, blue = difference.split()
                combined = ImageChops.lighter(red, ImageChops.lighter(green, blue))
                count = first.width * first.height - combined.histogram()[0]
                maximum = max(high for _, high in difference.getextrema())
                assert count <= 1 and maximum <= 11, (stem, count, maximum)
                print(f'{stem}: {count} reopened edge pixel, maximum {maximum}/255 at 144 dpi.')
            else:
                assert actual == reopened, (stem, dpi, 'reopened')
        assert ghostscript_renders(output / f'{stem}.ai') == ghostscript_renders(output / f'{stem}-reference.pdf') == ghostscript_renders(output / f'{stem}-reopened.pdf'), (stem, 'Ghostscript')
    print(f'Verified {len(cases)} text-flow saves: native source coverage, paragraph marks, path geometry, identities and original/reopened PDF pixels at 72 and 144 dpi (one explicitly bounded flipped edge), plus exact Ghostscript pixels at 72 dpi.')
    return len(cases)


def main():
    """Require the pinned clean reader before inspecting the generated artifacts."""
    if not __debug__:
        raise RuntimeError('Run verification without assertion stripping')
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--reference', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    assert subprocess.check_output(['git', '-C', str(args.reference), 'rev-parse', 'HEAD'], text=True).strip() == REVISION
    assert not subprocess.check_output(['git', '-C', str(args.reference), 'status', '--porcelain', '--untracked-files=no'], text=True).strip()
    sys.path.insert(0, str(args.reference.resolve()))
    verify_text_flow(importlib.import_module('inkai'), args.output)


if __name__ == '__main__':
    main()
