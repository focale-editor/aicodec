#!/usr/bin/env python3
"""Shared independent native extraction and external-renderer corpus helpers."""

import re
import subprocess
import zlib

from PIL import Image, ImageChops, ImageFilter, ImageStat
from pypdf import PdfReader
import zstandard

REVISION = '1a5f42a0b0407fc869e032420570682048810108'


def render_pdf(path, width, height):
    """Render with Poppler at fixed dimensions shared with the reference image."""
    png = path.with_suffix('.png')
    result = subprocess.run(['pdftoppm', '-singlefile', '-png', '-scale-to-x', str(width), '-scale-to-y', str(height), str(path), str(png.with_suffix(''))], check=True, stderr=subprocess.PIPE, text=True)
    assert 'Syntax Error' not in result.stderr, f'{path.name}: {result.stderr}'
    return png


def native_programs(path):
    """Extract every Illustrator owner independently, including shared blocks."""
    document = PdfReader(path)
    programs = []
    for owner in [document.trailer['/Root'], *document.pages]:
        pieces = owner.get('/PieceInfo')
        if pieces is None:
            continue
        illustrator = pieces.get_object().get('/Illustrator')
        if illustrator is None:
            continue
        private = illustrator.get_object()['/Private']
        blocks = []
        for name, value in private.items():
            match = re.fullmatch(r'/(?:AIPrivateData|AIPDFPrivateData)(\d+)', name)
            if match:
                blocks.append((int(match[1]), value.get_object().get_data()))
        if not blocks:
            continue
        ordered = [value for _, value in sorted(blocks)]
        while ordered and ordered[0].startswith((b'%%BoundingBox:', b'%%HiResBoundingBox:', b'%AI7_Thumbnail:')):
            ordered.pop(0)
        envelope = b''.join(ordered)
        if envelope.startswith(b'%AI24_ZStandard_Data'):
            data = zstandard.ZstdDecompressor().decompress(envelope[20:], max_output_size=128 * 1024 * 1024)
        elif envelope.startswith(b'%AI12_CompressedData'):
            data = zlib.decompress(envelope[20:])
        else:
            assert envelope.startswith(b'%!PS-Adobe-')
            data = envelope
        programs.append(data)
    assert programs, f'No independently readable native data in {path}'
    return programs


def compare(first, second, difference, ceiling):
    """Measure all channel differences, retaining the image for visual review."""
    with Image.open(first) as image:
        expected = image.convert('RGB')
    with Image.open(second) as image:
        actual = image.convert('RGB')
    assert expected.size == actual.size, (first, expected.size, actual.size)
    delta = ImageChops.difference(expected, actual)
    mean = max(ImageStat.Stat(delta).mean)
    delta.save(difference)
    assert mean < ceiling, f'{second.name}: mean channel difference {mean} >= {ceiling}'
    # Permit renderer/decimal rounding only near reference edges, never in flats.
    edges = Image.new('L', expected.size)
    for offset in [(1, 0), (0, 1)]:
        adjacent = ImageChops.difference(expected, ImageChops.offset(expected, *offset))
        for channel in adjacent.split():
            edges = ImageChops.lighter(edges, channel)
    mask = edges.point(lambda value: 255 if value else 0).filter(ImageFilter.MaxFilter(3))
    for channel in delta.split():
        assert ImageChops.multiply(channel, ImageChops.invert(mask)).getbbox() is None, f'{second.name}: changed flat pixels'
    return mean


def printable_svg(inkai, path):
    """Select the independently parsed printing stream instead of rebuilt live shapes."""
    from inkai.parser.consts import Section
    from inkai.parser.operators import Operator
    from inkai.svg.convert import ai2svg

    def printable(items):
        result = []
        for item in items:
            if isinstance(item, Section):
                item.children = printable(item.children)
                result.append(item)
            elif isinstance(item, Operator):
                # Pseudo-comment outlines and authoring dictionaries are not print art.
                # XW 1 styles the private shape that has just been omitted; the
                # preceding printing expansion already contains its paint.
                if not item.is_pseudo_comment and not (item.command == 'XW' and item.integer == 1):
                    result.append(item)
        return result

    document = inkai.parse(str(path))
    document.trailer = printable(document.trailer)
    return ai2svg(document)
