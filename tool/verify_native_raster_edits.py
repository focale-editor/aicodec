#!/usr/bin/env python3
"""Check edited native pixels and metadata against independent readers and PDFs."""

import argparse
import importlib
import json
import re
import subprocess
import sys
from pathlib import Path

from pypdf import PdfReader, PdfWriter
from pypdf.generic import DecodedStreamObject, DictionaryObject, NameObject, NumberObject

from verify_native_pdf import REVISION, compare, native_programs, render_pdf
from verify_native_rasters import images, samples


def replacement(image, variant):
    """Construct expected planes from independently recovered original pixels."""
    colors, alpha = samples(image)
    width, height = image.h, image.w
    if variant == 'colors':
        colors = bytes(255 - value for value in colors)
    elif variant == 'alpha':
        alpha = bytes(0 if x < width // 2 and y < height // 2 else 128 if x < width // 2 else 255
                      for y in range(height) for x in range(width))
    else:
        width, height = (width + 1) // 2, (height + 1) // 2
        indices = [(y * image.w // height) * image.h + x * image.h // width for y in range(height) for x in range(width)]
        colors = b''.join(colors[index * image.image_type:(index + 1) * image.image_type] for index in indices)
        if alpha:
            alpha = bytes(alpha[index] for index in indices)
    return width, height, colors, alpha


def reference_pdf(source, target, image, variant):
    """Replace only image planes in an existing independently generated PDF."""
    width, height, colors, alpha = replacement(image, variant)
    writer = PdfWriter()
    writer.clone_document_from_reader(PdfReader(source))

    def plane(data, components):
        stream = DecodedStreamObject()
        stream.set_data(data)
        stream.update(DictionaryObject({
            NameObject('/Type'): NameObject('/XObject'), NameObject('/Subtype'): NameObject('/Image'),
            NameObject('/Width'): NumberObject(width), NameObject('/Height'): NumberObject(height),
            NameObject('/BitsPerComponent'): NumberObject(8),
            NameObject('/ColorSpace'): NameObject({1: '/DeviceGray', 3: '/DeviceRGB', 4: '/DeviceCMYK'}[components]),
        }))
        return stream

    def rewrite(resources):
        count = 0
        objects = resources.get('/XObject', DictionaryObject()).get_object()
        for key, value in list(objects.items()):
            old = value.get_object()
            if old.get('/Subtype') == '/Form':
                count += rewrite(old['/Resources'])
            elif old.get('/Subtype') == '/Image':
                assert old['/Width'] == image.h and old['/Height'] == image.w
                new = plane(colors, image.image_type)
                if alpha:
                    new[NameObject('/SMask')] = writer._add_object(plane(alpha, 1))
                objects[key] = writer._add_object(new)
                count += 1
        return count

    assert sum(rewrite(page['/Resources']) for page in writer.pages) == 1
    writer.write(target)


def identities(path):
    """Recover the two known scalar identity keys from pinned native fixtures."""
    pattern = rb'\(([0-9a-fA-F-]{36})\) /(?:UnicodeString|String) \((AI24 Image(?:Alpha)?RawDataUUID)\)'
    return [(key.decode(), value.decode()) for value, key in re.findall(pattern, path.read_bytes())]


def main():
    """Require exact edited samples, preserved extents and synchronized PDF owners."""
    if not __debug__:
        raise RuntimeError('Run verification without assertion stripping')
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--inkai-source', type=Path, required=True)
    parser.add_argument('--output', type=Path, default=Path('test/corpus/output/native-raster-edits'))
    parser.add_argument('--references', type=Path, default=Path('test/corpus/output/native-rasters'))
    args = parser.parse_args()
    assert subprocess.check_output(['git', '-C', str(args.inkai_source), 'rev-parse', 'HEAD'], text=True).strip() == REVISION
    assert not subprocess.check_output(['git', '-C', str(args.inkai_source), 'status', '--porcelain', '--untracked-files=no'], text=True).strip()
    sys.path.insert(0, str(args.inkai_source.resolve()))
    inkai = importlib.import_module('inkai')
    report = json.loads((args.output / 'report.json').read_text())
    assert {row['file']: len(row['images']) for row in report} == {'raster_ai8.ai': 1, 'raster_v2020.ai': 6, 'empty_cs.ai': 5, 'empty_cs2.ai': 5, 'simple_shapes_cc.ai': 7}
    edits, owners, renders = 0, 0, []
    for row in report:
        name = row['file']
        before = images(inkai.parse(str(args.output / f'{name}.native.ps')))
        original_ids = {value.lower() for _, value in identities(args.output / f'{name}.native.ps')}
        allocated = set(original_ids)
        for variant_row in row['variants']:
            variant = variant_row['variant']
            path = args.output / f'{name}.{variant}.ps'
            after = images(inkai.parse(str(path)))
            assert len(before) == len(after) == len(row['images'])
            native_ids = identities(path)
            for first, second, info, changed in zip(before, after, row['images'], variant_row['images']):
                width, height, colors, alpha = replacement(first, variant)
                assert [second.h, second.w, second.bits, second.image_type] == [width, height, 8, first.image_type]
                assert [second.llx, second.lly, second.urx, second.ury] == [0, 0, width, height]
                assert samples(second) == (colors, alpha)
                expected_matrix = [first.matrix[0] * first.h / width, first.matrix[1] * first.h / width,
                                   first.matrix[2] * first.w / height, first.matrix[3] * first.w / height, *first.matrix[4:]]
                assert all(abs(a-b) < 1e-10 for a, b in zip(second.matrix, expected_matrix))
                for field, key, change in [('colorIdentity', 'AI24 ImageRawDataUUID', variant != 'alpha'),
                                           ('alphaIdentity', 'AI24 ImageAlphaRawDataUUID', variant == 'alpha' or variant == 'resolution' and bool(first.alpha_channel_count))]:
                    if info[field] is None:
                        assert changed[field] is None
                    elif change:
                        value = changed[field]
                        assert re.fullmatch(r'[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}', value)
                        assert value.lower() not in allocated
                        allocated.add(value.lower())
                        assert (key, value) in native_ids
                    else:
                        assert changed[field] == info[field] and (key, changed[field]) in native_ids
                assert changed['originalScale'] == info['originalScale'] and changed['name'] == info['name']
                edits += 1
            visible = [image for image, info in zip(before, row['images']) if info['printable']]
            if not visible:
                continue
            assert len(visible) == 1
            reference = args.output / f'{name}.{variant}.reference.pdf'
            reference_pdf(args.references / f'{name}.reference.pdf', reference, visible[0], variant)
            size = (1920, 1080) if name == 'raster_ai8.ai' else (612, 792)
            difference = compare(render_pdf(reference, *size), render_pdf(args.output / f'{name}.{variant}.pdf', *size), args.output / f'{name}.{variant}.difference.png', 0.02)
            if name == 'raster_ai8.ai':
                assert native_programs(args.output / f'{name}.{variant}.ai') == [path.read_bytes()]
                owners += 1
            renders.append({'file': name, 'variant': variant, 'meanChannelDifference': difference})
            print(f'{name} {variant}: mean channel difference {difference}')
    assert edits == 72 and owners == 3 and len(renders) == 6
    (args.output / 'independent-report.json').write_text(json.dumps({'oracleRevision': REVISION, 'imageEdits': edits, 'nativeOwners': owners, 'renders': renders}, indent=2) + '\n')
    print('Native raster edits: 72 image edits, 3 PDF owners and 6 renders passed')


if __name__ == '__main__':
    main()
