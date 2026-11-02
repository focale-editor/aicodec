"""Check literal native effects and independently composed original/reopened views.

This does not execute Adobe's native effect implementation. The PDF comparisons
validate supplied representations and host recipe persistence, not Adobe parity.
"""
from io import BytesIO

from PIL import Image, ImageChops
from pypdf import PdfReader

from corpus_support import native_programs
from verify_focale_group_paints import ghostscript_renders
from verify_native_documents import renders
from verify_native_structure import native_values


def compare_views(actual, expected, stem, engine, dpi):
    """Bound the rotated group's local-blur resampling; keep other views exact."""
    if actual == expected:
        return
    # Native group geometry bakes rotation into its child contours. Reopening
    # therefore blurs rotated coverage instead of rotating an already blurred
    # local layer. The finite host raster filters differ at alpha/edge pixels.
    # These bounds apply to this inspected fixture only, never arbitrary saves.
    assert stem == 'effect-group-reopened' and len(actual) == len(expected) == 1, (stem, engine, dpi)
    first = Image.open(BytesIO(actual[0])).convert('RGB')
    second = Image.open(BytesIO(expected[0])).convert('RGB')
    assert first.size == second.size
    difference = ImageChops.difference(first, second)
    pixels = list(difference.get_flattened_data())
    changed = sum(max(pixel) != 0 for pixel in pixels)
    maximum = max(max(pixel) for pixel in pixels)
    mean = sum(sum(pixel) for pixel in pixels) / (len(pixels) * 3)
    assert changed <= (1400 if dpi == 72 else 5500) and maximum <= 36 and mean <= .2, (stem, engine, dpi, changed, maximum, mean)
    print(stem, engine, dpi, f'{changed} coverage pixels, max {maximum}/255, mean {mean:.4f}/255', flush=True)


def verify_effects(inkai, output):
    """Require all four qualified native filters and complete repeated saves."""
    cases = [f'effect-{kind}{phase}{view}' for kind in ('offset', 'round', 'shadow', 'glow')
             for phase in ('', '-edit-0', '-edit-1') for view in ('', '-reopened')]
    cases += [f'effect-{kind}{view}' for kind in ('ordered', 'group') for view in ('', '-reopened')]
    plugins = {'Adobe Offset Path', 'Adobe Round Corners', 'Adobe Drop Shadow', 'Adobe Outer Glow'}
    seen = set()
    for stem in cases:
        path, source = output / f'{stem}.ai', output / f'{stem}.ps'
        assert native_programs(path) == [source.read_bytes()], stem
        document = inkai.parse(str(source))
        filters = [value for value in native_values(document.setup) if type(value).__name__ == 'BasicFilter' and value.Filter[0] in plugins]
        assert filters, stem
        for effect in filters:
            name, parameters = effect.Filter[0], effect.Dict
            seen.add(name)
            assert effect.Filter[1:] == [1, 0] or tuple(effect.Filter[1:]) == (1, 0), stem
            if name == 'Adobe Offset Path':
                assert int(parameters['jntp']) in (0, 1, 2) and float(parameters['mlim']) >= 1, stem
            elif name == 'Adobe Round Corners':
                assert float(parameters['radius']) >= 0, stem
            else:
                assert 0 <= float(parameters['opac']) <= 1 and float(parameters['blur']) >= 0, stem
                assert int(parameters['usePSLBlur']) == 1 and 'sclr' in parameters, stem
                if name == 'Adobe Drop Shadow':
                    assert int(parameters['pair']) == int(parameters['csrc']) == 1, stem
        reference = output / f'{stem}-reference.pdf'
        actual, expected = PdfReader(path, strict=True), PdfReader(reference, strict=True)
        assert len(actual.pages) == len(expected.pages) == 1 and actual.pages[0].mediabox == expected.pages[0].mediabox, stem
        compare_views(renders(path), renders(reference), stem, 'Poppler', 72)
        compare_views(renders(path, dpi=144), renders(reference, dpi=144), stem, 'Poppler', 144)
        compare_views(ghostscript_renders(path), ghostscript_renders(reference), stem, 'Ghostscript', 72)
        print(stem, 'passed', flush=True)
    assert seen == plugins
    print('Verified 28 effect saves: native parameters, complete owners and original/reopened PDF views.')
