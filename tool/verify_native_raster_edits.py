#!/usr/bin/env python3
"""Check edited native pixels and metadata against an independent reader."""

import argparse
import importlib
import json
import re
import subprocess
import sys
from pathlib import Path


from corpus_support import REVISION
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


def identities(path):
    """Recover the two known scalar identity keys from pinned native fixtures."""
    pattern = rb'\(([0-9a-fA-F-]{36})\) /(?:UnicodeString|String) \((AI24 Image(?:Alpha)?RawDataUUID)\)'
    return [(key.decode(), value.decode()) for value, key in re.findall(pattern, path.read_bytes())]


def main():
    """Require exact edited samples, preserved extents and sample identities."""
    if not __debug__:
        raise RuntimeError('Run verification without assertion stripping')
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--inkai-source', type=Path, required=True)
    parser.add_argument('--output', type=Path, default=Path('test/corpus/output/native-raster-edits'))
    args = parser.parse_args()
    assert subprocess.check_output(['git', '-C', str(args.inkai_source), 'rev-parse', 'HEAD'], text=True).strip() == REVISION
    assert not subprocess.check_output(['git', '-C', str(args.inkai_source), 'status', '--porcelain', '--untracked-files=no'], text=True).strip()
    sys.path.insert(0, str(args.inkai_source.resolve()))
    inkai = importlib.import_module('inkai')
    report = json.loads((args.output / 'report.json').read_text())
    assert {row['file']: len(row['images']) for row in report} == {'raster_ai8.ai': 1, 'raster_v2020.ai': 6, 'empty_cs.ai': 5, 'empty_cs2.ai': 5, 'simple_shapes_cc.ai': 7}
    edits = 0
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
    assert edits == 72
    (args.output / 'independent-report.json').write_text(json.dumps({'oracleRevision': REVISION, 'imageEdits': edits}, indent=2) + '\n')
    print('Native raster edits: 72 native image edits passed')


if __name__ == '__main__':
    main()
