"""Check host-retained effects without claiming native Adobe effect controls."""

import json

from pypdf import PdfReader

from corpus_support import native_programs
from verify_focale_group_paints import ghostscript_renders
from verify_native_documents import renders
from verify_native_rasters import images, samples


def verify_retained_effects(inkai, output):
    """Compare complete page captures and developed vectors after restoration."""
    kinds = ('innerShadow', 'innerGlow', 'bevelEmboss', 'satin', 'colorOverlay',
             'gradientOverlay', 'patternOverlay', 'dropShadow', 'outerGlow',
             'bend', 'combined')
    for kind in kinds:
        for view in ('', '-reopened'):
            stem = f'retained-effect-{kind}{view}'
            path = output / f'{stem}.ai'
            reference = output / f'{stem}-reference.pdf'
            actual, expected = PdfReader(path, strict=True), PdfReader(reference, strict=True)
            snapshot = actual.trailer['/Root']['/AiKitHost_FocaleEffects']
            assert snapshot['/Type'] == '/AiKitHostSnapshot' and snapshot['/Version'] == 1, stem
            assert len(snapshot['/SHA256'].original_bytes) == 32, stem
            data = snapshot.get_data()
            assert len(data) <= 32 * 1024 * 1024, stem
            authored = json.loads(data)
            assert authored['format'] == 'fvector' and authored['version'] == 1, stem
            assert 'aiOrigin' not in authored, stem
            programs = native_programs(path)
            assert programs and all(program == programs[0] for program in programs), stem
            source = output / f'{stem}.ps'
            source.write_bytes(programs[0])
            document = inkai.parse(str(source))
            rasters = images(document)
            assert len(actual.pages) == len(expected.pages) == (2 if kind == 'combined' else 1), stem
            for page, wanted in zip(actual.pages, expected.pages):
                assert page.mediabox == wanted.mediabox, stem
            if kind == 'bend':
                assert not rasters, stem
            else:
                assert len(rasters) == len(actual.pages), stem
                # Both native images and PDF compatibility must carry the exact
                # full-page host samples, including transparent coverage.
                for raster, page in zip(rasters, actual.pages):
                    color, alpha = samples(raster)
                    image, = page.images
                    # The pinned parser names the width token h and height token w.
                    assert image.image.size == (raster.h, raster.w), stem
                    assert image.image.convert('RGB').tobytes() == color, stem
                    if alpha:
                        assert image.image.convert('RGBA').getchannel('A').tobytes() == alpha, stem
            assert renders(path) == renders(reference), (stem, 'Poppler', 72)
            assert renders(path, dpi=144) == renders(reference, dpi=144), (stem, 'Poppler', 144)
            assert ghostscript_renders(path) == ghostscript_renders(reference), (stem, 'Ghostscript', 72)
            print(stem, 'passed', flush=True)
    print('Verified 22 retained-effect views: bounded host authoring, native captures/vectors and exact independent PDF renders.')
