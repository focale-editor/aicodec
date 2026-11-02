#!/usr/bin/env python3
"""Check fixed native calligraphy, complete containers and original/reopened PDF views.

The independent reader parses nib descriptors and styles. It does not execute
Illustrator's brush engine; native appearance/editability acceptance is separate.
"""

from io import BytesIO

from PIL import Image, ImageChops
from pypdf import PdfReader

from corpus_support import native_programs
from verify_native_artboard_brush_descriptors import descriptor_state
from verify_native_brush_lifecycle import descriptors
from verify_native_documents import renders
from verify_native_structure import native_values


def verify_brushes(inkai, output):
    """Verify authored nibs, retained editable spines and repeated whole-file saves."""
    for base in ('brush-created', 'brush-edited-1', 'brush-edited-2'):
        for reopened in (False, True):
            stem = base + ('-reopened' if reopened else '')
            ai = output / f'{stem}.ai'
            data = (output / f'{stem}.ps').read_bytes()
            assert native_programs(ai) == [data]
            document = inkai.parse(str(output / f'{stem}.ps'))
            state = descriptor_state(document)
            assert state['references']
            definitions = descriptors(document)
            assert len(definitions) == (1 if base == 'brush-created' else int(base[-1]) + 1)
            for (plugin, _), payload in definitions.items():
                assert plugin == b'Adobe Calligraphic Brush Tool'
                values = list(map(float, payload.split()))
                assert len(values) == 11 and values[0:3] == [1, 1, 1]
                assert values[3] == values[4] and values[5] == values[6]
                assert values[7:] == [0, 0, 0, 0]
            filters = [value for value in native_values(document.setup) if type(value).__name__ == 'BasicFilter' and value.Filter[0] == 'Adobe Calligraphic Brush Tool']
            assert len(filters) == len(definitions)
            expected = (25, -30) if base == 'brush-created' else (40, 55) if base.endswith('1') else (65, -15)
            parameters = filters[-1].Dict
            assert float(parameters['Diameter']) == 1
            assert abs(float(parameters['Roundness']) - expected[0]) < 1e-10
            assert abs(float(parameters['Angle']) - expected[1]) < 1e-10
            saved = PdfReader(ai, strict=True)
            reference = output / f'{stem}-reference.pdf'
            expected_pdf = PdfReader(reference, strict=True)
            assert len(saved.pages) == len(expected_pdf.pages) == 1
            assert saved.pages[0].mediabox == expected_pdf.pages[0].mediabox
            assert renders(ai) == renders(reference)
            print(stem, 'passed', flush=True)
    print('Verified six brush comparisons across three complete saves and original/reopened host PDF views.')


def verify_affine_brushes(inkai, output):
    """Check physical nib ellipses under unequal scale, shear and reflection."""
    import math
    from verify_focale_group_paints import ghostscript_renders

    def metric(angle, ratio, width, matrix):
        cosine, sine = math.cos(math.radians(angle)), math.sin(math.radians(angle))
        a, b, c, d = matrix
        x, y = width * (a * cosine + c * sine), width * (b * cosine + d * sine)
        u, v = width * ratio * (-a * sine + c * cosine), width * ratio * (-b * sine + d * cosine)
        return x * x + u * u, x * y + u * v, y * y + v * v

    cosine, sine = math.cos(.3), math.sin(.3)
    cases = {
        'brush-affine-0': (30, .25, 6, (1.7, 0, 0, -.8)),
        'brush-affine-1': (30, .25, 6, (cosine, -sine, .55 * cosine - sine, -(.55 * sine + cosine))),
        'brush-affine-2': (30, .25, 6, (-1.6, 0, -.33, -1.1)),
        'brush-affine-nested-1': (20, .4, 5, (1.4, 0, .36, .9)),
        'brush-affine-nested-2': (-35, .6, 5, (1.4, 0, .36, .9)),
    }
    for base, expected in cases.items():
        for reopened in (False, True):
            stem = base + ('-reopened' if reopened else '')
            path = output / f'{stem}.ai'
            source = output / f'{stem}.ps'
            assert native_programs(path) == [source.read_bytes()], stem
            document = inkai.parse(str(source))
            assert descriptor_state(document)['references'], stem
            filters = [value for value in native_values(document.setup) if type(value).__name__ == 'BasicFilter' and value.Filter[0] == 'Adobe Calligraphic Brush Tool']
            parameters = filters[-1].Dict
            width, = [float(value.tokens[0]) for value in native_values(parameters['StrokeStyle']) if getattr(value, 'command', None) == 'w']
            actual = metric(float(parameters['Angle']), float(parameters['Roundness']) / 100, width * float(parameters['Diameter']), (1, 0, 0, 1))
            assert all(abs(a - b) < 1e-8 for a, b in zip(actual, metric(*expected))), (stem, actual, expected)
            reference = output / f'{stem}-reference.pdf'
            saved, host = PdfReader(path, strict=True), PdfReader(reference, strict=True)
            assert len(saved.pages) == len(host.pages) == 1 and saved.pages[0].mediabox == host.pages[0].mediabox, stem
            if not reopened:
                assert renders(path) == renders(reference), stem
                assert renders(path, dpi=144) == renders(reference, dpi=144), stem
            else:
                # Rebuilding an equivalent ellipse changes the coordinate basis
                # used by the host's .01-point outline approximation. These small
                # fixtures permit at most ten antialiased edge pixels at 144 dpi;
                # native ellipse metrics above remain independently constrained.
                actual_pages = renders(path, dpi=144)
                expected_pages = renders(reference, dpi=144)
                assert len(actual_pages) == len(expected_pages) == 1, stem
                actual_image = Image.open(BytesIO(actual_pages[0])).convert('RGB')
                expected_image = Image.open(BytesIO(expected_pages[0])).convert('RGB')
                assert actual_image.size == expected_image.size, stem
                difference = ImageChops.difference(actual_image, expected_image)
                red, green, blue = difference.split()
                nonzero = ImageChops.lighter(red, ImageChops.lighter(green, blue))
                changed = actual_image.width * actual_image.height - nonzero.histogram()[0]
                maximum = max(high for _, high in difference.getextrema())
                assert changed <= 10 and maximum <= 32, (stem, changed, maximum)
                print(stem, f'Poppler 144 dpi: {changed} edge pixels, maximum channel difference {maximum}/255', flush=True)
            assert ghostscript_renders(path) == ghostscript_renders(reference), stem
            print(stem, 'passed', flush=True)
    print('Verified ten affine-brush views: native nib metrics, exact original PDF pixels, bounded reopened Poppler edges and exact Ghostscript 72 dpi pixels.')


def verify_artwork_brushes(inkai, output):
    """Check source tiles, native references and host views for art/pattern saves.

    This parses the native dictionaries independently and compares composed
    printing/PDF views. It does not execute Adobe's artwork brush plug-ins.
    """
    from verify_focale_group_paints import ghostscript_renders

    for kind, fit in (('art', 'stretch'), ('pattern', 'stretch'), ('pattern', 'space')):
        for edited in (False, True):
            for reopened in (False, True):
                stem = f'artwork-brush-{kind}-{fit}' + ('-edited' if edited else '') + ('-reopened' if reopened else '')
                path = output / f'{stem}.ai'
                source = output / f'{stem}.ps'
                assert native_programs(path) == [source.read_bytes()], stem
                document = inkai.parse(str(source))
                state = descriptor_state(document)
                assert state['references'], stem
                definitions = descriptors(document)
                assert len(definitions) == (2 if edited else 1), stem
                plugin = b'Adobe ArtOnPath Brush Tool' if kind == 'art' else b'Adobe PatternOnPath Brush Tool'
                for (owner, _), payload in definitions.items():
                    assert owner == plugin, stem
                    fields = [field.strip() for field in payload.split(b'/')]
                    assert len(fields) == 9 and fields[0] == b'2' and fields[1], stem
                    assert fields[6] == b'0 0' and fields[7] == b'0 1', stem
                    values = list(map(float, fields[8].split()))
                    assert len(values) == 15 and values[1] == 1 and values[2] == values[4] == values[8], stem
                filters = [value for value in native_values(document.setup) if type(value).__name__ == 'BasicFilter' and value.Filter[0].encode() == plugin]
                assert len(filters) == (3 if edited else 1), stem
                parameters = filters[-1].Dict
                assert float(parameters['Scaling']) == (1 if kind == 'art' else 1.2 if edited else .8), stem
                assert int(parameters['Adjustment']) == (1 if fit == 'space' else 0), stem
                assert int(parameters['Colorization']) == 1 and not parameters['Segmented'], stem
                reference = output / f'{stem}-reference.pdf'
                saved, host = PdfReader(path, strict=True), PdfReader(reference, strict=True)
                assert len(saved.pages) == len(host.pages) == 1 and saved.pages[0].mediabox == host.pages[0].mediabox, stem
                assert renders(path) == renders(reference), stem
                assert renders(path, dpi=144) == renders(reference, dpi=144), stem
                assert ghostscript_renders(path) == ghostscript_renders(reference), stem
                print(stem, 'passed', flush=True)
    for suffix in ('', '-reopened'):
        stem = 'artwork-brush-reflected' + suffix
        path, source = output / f'{stem}.ai', output / f'{stem}.ps'
        assert native_programs(path) == [source.read_bytes()], stem
        document = inkai.parse(str(source))
        assert descriptor_state(document)['references'], stem
        definition, = descriptors(document).values()
        fields = [field.strip() for field in definition.split(b'/')]
        assert all(fields[1:6]) and fields[2] != fields[3] and fields[4] != fields[5], stem
        reference = output / f'{stem}-reference.pdf'
        for dpi, maximum_pixels in ((72, 5), (144, 8)):
            actual, expected = renders(path, dpi=dpi), renders(reference, dpi=dpi)
            if not suffix:
                assert actual == expected, stem
            else:
                # Baking the source reflection into spine coordinates changes
                # floating-point outline evaluation at a few antialiased edges.
                # Native controls/tiles are checked separately by host tests.
                assert len(actual) == len(expected) == 1, stem
                difference = ImageChops.difference(Image.open(BytesIO(actual[0])).convert('RGB'), Image.open(BytesIO(expected[0])).convert('RGB'))
                pixels = list(difference.getdata())
                assert sum(max(pixel) != 0 for pixel in pixels) <= maximum_pixels, (stem, dpi)
                assert max(max(pixel) for pixel in pixels) <= 24, (stem, dpi)
        assert ghostscript_renders(path) == ghostscript_renders(reference), stem
        print(stem, 'passed', flush=True)
    print('Verified fourteen artwork brush views, source resources and complete saved native references.')
