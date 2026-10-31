#!/usr/bin/env python3
"""Verify native image samples and placement edits independently."""

import argparse
import importlib
import json
import subprocess
import sys
from pathlib import Path


from corpus_support import REVISION


def images(document):
    """Walk image operators in setup resources, private records and drawing order."""
    from inkai.parser.consts import Section
    from inkai.parser.hierarchy_objects import HierarchyObject
    from inkai.parser.operators import ImageOperator, Operator

    def walk(value):
        if isinstance(value, ImageOperator):
            yield value
        elif isinstance(value, Operator):
            return
        elif isinstance(value, Section):
            yield from walk(value.children)
        elif isinstance(value, HierarchyObject):
            yield from walk(vars(value))
        elif isinstance(value, dict):
            for child in value.values():
                yield from walk(child)
        elif isinstance(value, (list, tuple)):
            for child in value:
                yield from walk(child)

    return list(walk([document.prolog, document.setup, document.trailer]))


def samples(image):
    """Recover original bytes through the pinned reader, including its alpha tail."""
    assert image.bits == 8 and image.is_binary == 1
    color_length = image.h * image.w * image.image_type
    total = color_length + image.h * image.w * image.alpha_channel_count
    raw = image.data.decoded + image.data.additional_decoded
    assert len(raw) >= total and raw[total:] in (b'', b'\n', b'%_'), (len(raw), total, raw[total:][:30])
    return raw[:color_length], raw[color_length:total]


def main():
    """Require exact decoded samples, translated matrices and unchanged resources."""
    if not __debug__:
        raise RuntimeError('Run verification without assertion stripping')
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--inkai-source', required=True, type=Path)
    parser.add_argument('--output', default=Path('test/corpus/output/native-rasters'), type=Path)
    args = parser.parse_args()
    assert subprocess.check_output(['git', '-C', str(args.inkai_source), 'rev-parse', 'HEAD'], text=True).strip() == REVISION
    assert not subprocess.check_output(['git', '-C', str(args.inkai_source), 'status', '--porcelain', '--untracked-files=no'], text=True).strip()
    sys.path.insert(0, str(args.inkai_source.resolve()))
    inkai = importlib.import_module('inkai')
    report = json.loads((args.output / 'report.json').read_text())
    rejections = json.loads((args.output / 'rejections.json').read_text())
    assert {row['file'] for row in rejections} == {'transparent_image.ai', 'image_linked.ai'}
    assert all('raster data boundary' in row['error'] for row in rejections)
    assert {row['file']: len(row['images']) for row in report} == {'raster_ai8.ai': 1, 'raster_v2020.ai': 6, 'empty_cs.ai': 5, 'empty_cs2.ai': 5, 'simple_shapes_cc.ai': 7}
    count, alpha_count, private_count = 0, 0, 0
    for row in report:
        name = row['file']
        before = images(inkai.parse(str(args.output / f'{name}.native.ps')))
        assert len(before) == len(row['images'])
        for expected, actual in zip(row['images'], before):
            assert [actual.h, actual.w, actual.bits, actual.image_type] == [expected['width'], expected['height'], expected['bits'], expected['components']]
            assert actual.matrix == expected['matrix']
            assert [actual.llx, actual.lly, actual.urx, actual.ury] == expected['bounds']
            colors, alpha = samples(actual)
            assert colors == (args.output / f'{expected["prefix"]}.colors.bin').read_bytes()
            assert bool(alpha) == expected['alpha']
            if alpha:
                assert alpha == (args.output / f'{expected["prefix"]}.alpha.bin').read_bytes()
                alpha_count += 1
            private_count += expected['private']
            count += 1
        if row['bounds'] is None:
            continue
        after = images(inkai.parse(str(args.output / f'{name}.translated.ps')))
        assert len(before) == len(after)
        for info, first, second in zip(row['images'], before, after):
            expected = list(first.matrix)
            if info['printable']:
                expected[4] += 37
                expected[5] -= 19
            assert all(abs(a-b) < 1e-10 for a, b in zip(second.matrix, expected))
            assert samples(first) == samples(second)
    assert count == 24 and alpha_count == 20 and private_count == 2
    result = {'oracleRevision': REVISION, 'images': count, 'alphaPlanes': alpha_count, 'privateImages': private_count, 'rejectedFiles': [row['file'] for row in rejections]}
    (args.output / 'independent-report.json').write_text(json.dumps(result, indent=2) + '\n')
    print('Native rasters: 24 images, 20 alpha planes and translated native matrices passed')


if __name__ == '__main__':
    main()
