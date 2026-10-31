#!/usr/bin/env python3
"""Compare regenerated native artwork with original PDFs and a pinned AI reader."""

import argparse
import importlib
import json
import math
import re
import subprocess
import sys
import zlib
from pathlib import Path

from PIL import Image, ImageChops, ImageFilter, ImageStat
from lxml import etree
from pypdf import PdfReader, PdfWriter
from pypdf.generic import ArrayObject, BooleanObject, DecodedStreamObject, DictionaryObject, FloatObject, NameObject, NumberObject
import zstandard

REVISION = '1a5f42a0b0407fc869e032420570682048810108'
FILES = {'cmyk_rectangle.ai', 'rgb_rectangle.ai', 'circle.ai', 'simple_shapes.ai', 'simple_shapes_cc.ai', 'opacity.ai', 'gradient_linear.ai', 'gradient_radial.ai'}


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
        envelope = b''.join(value for _, value in sorted(blocks))
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


def compare(first, second, difference, ceiling, gradient=False):
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
    if gradient:
        # Smooth field variations must agree to one channel level. Only sharp
        # boundaries permit the larger coverage difference from rounded outlines.
        sharp = edges.point(lambda value: 255 if value > 8 else 0).filter(ImageFilter.MaxFilter(3))
        for channel in delta.split():
            interior = ImageChops.multiply(channel, ImageChops.invert(sharp))
            assert interior.getextrema()[1] <= 1, f'{second.name}: gradient field differs away from sharp edges'
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


def check_composition(output):
    """Check known colors away from antialiasing, without using AiKit as an oracle."""
    path = render_pdf(output / 'composition.pdf', 1200, 960)
    samples = [
        (40, 120, (255, 128, 128)),  # Half-opaque red fill.
        (12, 120, (128, 128, 255)),  # Blue stroke overlaps fill, alpha applied once.
        (130, 120, (0, 128, 0)),  # Half-opaque red Multiply group over green.
        (105, 120, (0, 255, 0)),
        (40, 40, (0, 0, 255)),  # Inside clip.
        (80, 40, (255, 255, 255)),  # Outside clip.
        (100, 40, (255, 0, 0)),  # After clip group, original clipping restored.
        (130, 40, (255, 255, 255)),  # Hidden layer.
        (160, 40, (255, 255, 255)),  # Nonprinting layer.
    ]
    with Image.open(path) as image:
        for x, y, expected in samples:
            actual = image.getpixel((x * 6, (160 - y) * 6))
            assert max(abs(first - second) for first, second in zip(actual, expected)) <= 1, (x, y, expected, actual)
    return len(samples)


def recolor_original(source, destination):
    """Independently replace original PDF fields with specified RGB/opacity stops."""
    def array(values):
        return ArrayObject([FloatObject(value) for value in values])

    def function(values):
        intervals = ArrayObject([
            DictionaryObject({NameObject('/FunctionType'): NumberObject(2), NameObject('/Domain'): array([0, 1]), NameObject('/C0'): array(first), NameObject('/C1'): array(last), NameObject('/N'): NumberObject(1)})
            for first, last in zip(values, values[1:])
        ])
        return DictionaryObject({NameObject('/FunctionType'): NumberObject(3), NameObject('/Domain'): array([0, 1]), NameObject('/Functions'): intervals, NameObject('/Bounds'): array([0.4]), NameObject('/Encode'): array([0, 1, 0, 1])})

    document = PdfReader(source)
    writer = PdfWriter()
    writer.clone_document_from_reader(document)
    page = writer.pages[0]
    resources = page['/Resources']
    content = page.get_contents().get_data()
    for index, (name, reference) in enumerate(resources['/Shading'].items()):
        shading = reference.get_object()
        shading[NameObject('/ColorSpace')] = NameObject('/DeviceRGB')
        shading[NameObject('/Function')] = function([[1, 0, 0], [0, 1, 0], [0, 0, 1]])
        mask_shading = DictionaryObject(shading)
        mask_shading[NameObject('/ColorSpace')] = NameObject('/DeviceGray')
        mask_shading[NameObject('/Function')] = function([[1], [0.4], [1]])
        form = DecodedStreamObject()
        form.set_data(b'/MaskShade sh')
        form.update({
            NameObject('/Type'): NameObject('/XObject'), NameObject('/Subtype'): NameObject('/Form'),
            NameObject('/BBox'): array([-100, -100, 100, 100]),
            NameObject('/Resources'): DictionaryObject({NameObject('/Shading'): DictionaryObject({NameObject('/MaskShade'): mask_shading})}),
            NameObject('/Group'): DictionaryObject({NameObject('/S'): NameObject('/Transparency'), NameObject('/CS'): NameObject('/DeviceGray'), NameObject('/I'): BooleanObject(True)}),
        })
        state_name = f'/ExpectedAlpha{index}'
        resources['/ExtGState'][NameObject(state_name)] = DictionaryObject({
            NameObject('/SMask'): DictionaryObject({NameObject('/S'): NameObject('/Luminosity'), NameObject('/G'): writer._add_object(form), NameObject('/BC'): array([0])}),
        })
        content = content.replace(f'{name} sh'.encode(), f'{state_name} gs {name} sh'.encode())
    stream = DecodedStreamObject()
    stream.set_data(content)
    page[NameObject('/Contents')] = writer._add_object(stream)
    writer.write(destination)


def check_midpoints(inkai, output):
    """Compare PDF function evaluation with original Adobe sampled print ramps."""
    from inkai.parser.gradient import Br
    from verify_native_gradients import ramps

    def evaluate(function, value):
        function = function.get_object()
        if function['/FunctionType'] == 2:
            factor = value ** float(function['/N'])
            return [float(first) + (float(last) - float(first)) * factor for first, last in zip(function['/C0'], function['/C1'])]
        assert function['/FunctionType'] == 3
        boundaries = [0, *map(float, function['/Bounds']), 1]
        index = next((index for index in range(len(boundaries) - 1) if value < boundaries[index + 1]), len(boundaries) - 2)
        first, last = map(float, function['/Encode'][2 * index:2 * index + 2])
        mapped = first + (last - first) * (value - boundaries[index]) / (boundaries[index + 1] - boundaries[index])
        return evaluate(function['/Functions'][index], mapped)

    definitions = inkai.parse(str(output / 'circle.ai.native.ps')).setup.gradients
    results = []
    for number in [14, 54]:
        definition = definitions[f'Unnamed gradient {number}']
        samples = ramps(definition, Br)[0]['channels']
        stops = sorted(definition.color_stops, key=lambda stop: stop.ramp_point)
        start, end = stops[0].ramp_point / 100, stops[1].ramp_point / 100
        page = PdfReader(output / f'midpoint-{number}.pdf').pages[0]
        shade = next(iter(page['/Resources']['/Shading'].values())).get_object()
        assert shade['/ColorSpace'] == '/DeviceCMYK'
        assert all(isinstance(channel, list) and len(channel) == len(samples[0]) for channel in samples)
        errors = []
        for index in range(len(samples[0])):
            actual = evaluate(shade['/Function'], start + (end - start) * index / (len(samples[0]) - 1))
            errors.extend(abs(value - samples[channel][index] / 255) for channel, value in enumerate(actual))
        mean, maximum = sum(errors) / len(errors), max(errors)
        assert mean < 0.5 / 255 and maximum < 1 / 255, (number, mean, maximum)
        results.append({'resource': number, 'samples': len(samples[0]), 'meanChannelDifference': mean, 'maxChannelDifference': maximum})
        render_pdf(output / f'midpoint-{number}.pdf', 600, 600)
    return results


def main():
    """Require all eight fixtures and verify both original and edited artwork."""
    if not __debug__:
        raise RuntimeError('Run verification without assertion stripping')
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--inkai-source', required=True, type=Path)
    parser.add_argument('--output', default=Path('test/corpus/output/native-pdf'), type=Path)
    args = parser.parse_args()
    assert subprocess.check_output(['git', '-C', str(args.inkai_source), 'rev-parse', 'HEAD'], text=True).strip() == REVISION
    assert not subprocess.check_output(['git', '-C', str(args.inkai_source), 'status', '--porcelain', '--untracked-files=no'], text=True).strip()
    sys.path.insert(0, str(args.inkai_source.resolve()))
    inkai = importlib.import_module('inkai')
    report = json.loads((args.output / 'report.json').read_text())
    assert len(report) == len(FILES) and {row['file'] for row in report} == FILES
    assert all(row['status'] == 'passed' for row in report)
    results = []
    owners = 0
    for row in report:
        name = row['file']
        left, bottom, right, top = row['bounds']
        width, height = 1200, math.ceil(1200 * (top - bottom) / (right - left))
        if row['pdfBacked']:
            source = PdfReader(args.output / f'{name}.original.pdf')
            assert len(source.pages) == 1
            source.pages[0].add_transformation((1, 0, 0, 1, 37, -19))
            writer = PdfWriter()
            writer.add_page(source.pages[0])
            writer.write(args.output / f'{name}.expected-translated.pdf')
            programs = native_programs(args.output / f'{name}.saved.ai')
            assert all(program == (args.output / f'{name}.translated.ps').read_bytes() for program in programs)
            owners += len(programs)
        gradient = name.startswith('gradient_')
        if gradient:
            recolor_original(args.output / f'{name}.original.pdf', args.output / f'{name}.expected-colors.pdf')
            assert all(program == (args.output / f'{name}.colors.ps').read_bytes() for program in native_programs(args.output / f'{name}.colors.ai'))
        for label in ['rebuilt', 'translated', *(['colors'] if gradient else [])]:
            if row['pdfBacked']:
                expected = args.output / f'{name}.{"original" if label == "rebuilt" else "expected-" + label}.pdf'
                reference = render_pdf(expected, width, height)
                # Native radial outlines retain more precision than the original
                # PDF's rounded rectangles; subpixel edges differ, fields do not.
                ceiling = 0.1 if name == 'gradient_radial.ai' else 0.02
            else:
                native = args.output / f'{name}.{"native" if label == "rebuilt" else "translated"}.ps'
                svg = args.output / f'{name}.{label}.reference.svg'
                tree = printable_svg(inkai, native)
                # Match physical page units while preserving the oracle's viewBox.
                tree.set('width', f'{right - left}pt')
                tree.set('height', f'{top - bottom}pt')
                svg.write_bytes(etree.tostring(tree))
                pdf = svg.with_suffix('.pdf')
                subprocess.run(['inkscape', str(svg), '--export-type=pdf', f'--export-filename={pdf}'], check=True)
                reference = render_pdf(pdf, width, height)
                ceiling = 0.05
            actual = render_pdf(args.output / f'{name}.{label}.pdf', width, height)
            mean = compare(reference, actual, args.output / f'{name}.{label}.difference.png', ceiling, gradient)
            results.append({'file': name, 'variant': label, 'reference': 'original PDF' if row['pdfBacked'] else 'independent printable AI to SVG', 'meanChannelDifference': mean})
            print(f'{name} {label}: mean channel difference {mean}')
    assert owners == 6 and len(results) == 18
    probes = check_composition(args.output)
    midpoints = check_midpoints(inkai, args.output)
    poppler = subprocess.run(['pdftoppm', '-v'], check=True, capture_output=True, text=True).stderr.splitlines()[0]
    inkscape = subprocess.check_output(['inkscape', '--version'], text=True).strip()
    result = {'oracleRevision': REVISION, 'poppler': poppler, 'inkscape': inkscape, 'nativeOwners': owners, 'compositionProbes': probes, 'midpoints': midpoints, 'renders': results}
    (args.output / 'independent-report.json').write_text(json.dumps(result, indent=2) + '\n')
    print(f'Independent native PDF comparisons: {len(results)}/18; native owners: {owners}/6, plus two gradient color saves')


if __name__ == '__main__':
    main()
