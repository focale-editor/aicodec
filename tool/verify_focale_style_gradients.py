#!/usr/bin/env python3
"""Verify host-authored relative gradients with independent geometry and PDF readers."""

import json
import math
from io import BytesIO

from PIL import Image, ImageChops
from pypdf import PdfReader

from corpus_support import native_programs
from verify_focale_group_paints import ghostscript_renders
from verify_native_documents import renders
from verify_native_group_lifecycle import inventory
from verify_native_structure import native_values


def verify_geometry(document, expected, radial, stroke):
    """Ask the pinned inkai gradient projector to interpret actual native operands."""
    import inkex
    from inkai.parser.gradient import GradientType
    from inkai.svg.gradient import AIGradient, create_gradient

    commands = [value for value in native_values(document.setup)
                if getattr(value, 'command', None) in ('Bb', 'Bg', 'BB')]
    assert [value.command for value in commands] == ['Bb', 'Bg', 'BB']
    assert commands[0].tokens == ([b'1'] if stroke else [])
    assert commands[-1].tokens == [b'1' if stroke else b'0']
    placement = commands[1]
    assert placement.tokens[0] == b'2'
    x, y, angle, length, a, b, c, d, tx, ty, aspect = map(float, placement.tokens[2:])
    assert tx == ty == 0
    definitions = [value for value in native_values(document.setup)
                   if getattr(value, 'command', None) == 'Bd']
    assert definitions and all(value.tokens[:2] == [placement.tokens[1], b'1' if radial else b'0'] for value in definitions)
    path, = inventory(document)[2]
    anchors = expected['anchors']
    coordinates = [anchors[0], anchors[2] + anchors[4] + anchors[3], anchors[6], anchors[9], anchors[0]]
    assert [command.upper() for command, _ in path['geometry']] == ['M', 'C', 'L', 'L', 'L']
    geometry = []
    for (command, tokens), wanted in zip(path['geometry'], coordinates):
        values = [float(value) * (-1 if index % 2 else 1) for index, value in enumerate(tokens)]
        assert len(values) == len(wanted) and all(abs(actual - reference) < 1e-10 for actual, reference in zip(values, wanted))
        geometry.append(command.upper() + ' ' + ' '.join(map(str, values)))
    shape = inkex.PathElement.new(' '.join(geometry) + ' Z')
    gradient = AIGradient(
        gradient_type=GradientType.RADIAL if radial else GradientType.LINEAR,
        tfm=inkex.Transform((a, b, c, d, 0, 0)),
        origin=inkex.Vector2d(x, y),
        offset=inkex.Vector2d(length * math.cos(math.radians(-angle)), length * math.sin(math.radians(-angle))),
        focus=inkex.Vector2d(0, 0), aspect_ratio=aspect, stops=(),
    )
    projected = create_gradient(gradient, shape)
    inverse = -inkex.Transform(projected.get('gradientTransform'))
    if radial:
        start = inkex.Vector2d(float(projected.get('cx')), float(projected.get('cy')))
        radius = float(projected.get('r'))
    else:
        start = inkex.Vector2d(float(projected.get('x1')), float(projected.get('y1')))
        end = inkex.Vector2d(float(projected.get('x2')), float(projected.get('y2')))
        axis = end - start
    for sample in expected['samples']:
        delta = inverse.apply_to_point(sample['point']) - start
        actual = delta.length / radius if radial else (delta.x * axis.x + delta.y * axis.y) / axis.length**2
        # Inkex serializes SVG coordinates to six significant decimal places.
        assert abs(actual - sample['parameter']) < 1e-5, (actual, sample)


def compare_reopened(actual, expected, stem, antialiased):
    """Bound raster edges after exact native contour and gradient geometry checks.

    Native import bakes object placement into cubic controls and stroke width.
    The mathematically equivalent PDF basis can move hard-stop/curve coverage by
    a subpixel. Poppler antialiases those edges; the Ghostscript ppm device does
    not, so one changed sample can carry the complete 80-percent group opacity.
    These limits apply only to the four independently checked transformed cases.
    """
    assert len(actual) == len(expected) == 1, stem
    first, second = Image.open(BytesIO(actual[0])).convert('RGB'), Image.open(BytesIO(expected[0])).convert('RGB')
    assert first.size == second.size, stem
    difference = ImageChops.difference(first, second)
    red, green, blue = difference.split()
    nonzero = ImageChops.lighter(red, ImageChops.lighter(green, blue))
    count = first.width * first.height - nonzero.histogram()[0]
    maximum = max(high for _, high in difference.getextrema())
    assert count <= (25 if antialiased else 5) and maximum <= (64 if antialiased else 204), (stem, count, maximum)
    print(stem, 'Poppler 144 dpi' if antialiased else 'Ghostscript 72 dpi', count, 'edge pixels; maximum difference', maximum, flush=True)


def verify_style_gradients(inkai, output):
    """Check channel selection, source geometry, repeated edits and host PDF views."""
    bases = [f'style-gradient-{kind}-{channel}' for kind in ('linear', 'radial') for channel in ('fill', 'stroke')]
    bases += ['style-gradient-edited-1', 'style-gradient-edited-2', 'style-gradient-geometry']
    for base in bases:
        document = inkai.parse(str(output / f'{base}.ps'))
        if base.endswith(('-fill', '-stroke')):
            verify_geometry(document, json.loads((output / f'{base}-samples.json').read_text()), '-radial-' in base, base.endswith('-stroke'))
        owners = [value['AI10_ArtUID'] for value in native_values(document.trailer)
                  if isinstance(value, dict) and 'AI10_ArtUID' in value]
        assert len(set(owners)) == len(owners), base
        for reopened in (False, True):
            stem = base + ('-reopened' if reopened else '')
            path, source = output / f'{stem}.ai', output / f'{stem}.ps'
            assert native_programs(path) == [source.read_bytes()], stem
            reference = output / f'{stem}-reference.pdf'
            saved, host = PdfReader(path, strict=True), PdfReader(reference, strict=True)
            assert len(saved.pages) == len(host.pages) == 1 and saved.pages[0].mediabox == host.pages[0].mediabox, stem
            if reopened and base.endswith(('-fill', '-stroke')):
                compare_reopened(renders(path, dpi=144), renders(reference, dpi=144), stem, True)
                compare_reopened(ghostscript_renders(path), ghostscript_renders(reference), stem, False)
            else:
                assert renders(path, dpi=144) == renders(reference, dpi=144), stem
                assert ghostscript_renders(path) == ghostscript_renders(reference), stem
            print(stem, 'passed', flush=True)
    print('Verified fourteen gradient-style views: independent native placement, exact original/edited PDF pixels and bounded initial reopened edges.')
