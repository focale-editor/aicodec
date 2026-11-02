#!/usr/bin/env python3
"""Verify affine/parallelogram saves with pinned independent native/PDF readers.

Synthetic structural acceptance only: no Adobe reopen or rendering certification.
The producer corpus independently establishes the irregular-polygon sentinel.
"""

import argparse
import importlib
from pathlib import Path
import subprocess
import sys

from pypdf import PdfReader

from corpus_support import REVISION, native_programs
from verify_live_shapes import GEOMETRY, walk_body
from verify_native_structure import parsed


def main():
    if not __debug__:
        raise RuntimeError('Run verification without assertion stripping')
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--reference', required=True, type=Path)
    parser.add_argument('--output', type=Path, default=Path('test/corpus/output/affine'))
    args = parser.parse_args()
    assert subprocess.check_output(['git', '-C', str(args.reference), 'rev-parse', 'HEAD'], text=True).strip() == REVISION
    assert not subprocess.check_output(['git', '-C', str(args.reference), 'status', '--porcelain', '--untracked-files=no'], text=True).strip()
    sys.path.insert(0, str(args.reference.resolve()))
    inkai = importlib.import_module('inkai')
    for name in ('simple_shapes.ai', 'simple_shapes_cc.ai'):
        document = inkai.parse(str(args.reference / 'tests/data/ai' / name))
        parameters = [item['ai::LiveShape']['ai::LiveShape::Params'] for item in walk_body(document.trailer)
                      if isinstance(item, dict) and 'ai::LiveShape' in item]
        assert any(value.get('ai::Polygon::Radius') == -11 and value.get('ai::Polygon::IsRegular') == 0 for value in parameters)
    for prefix in ('direct', 'paired'):
        for stage, corners, center in (
            ('sheared', [(0, 0), (20, 0), (30, 10), (10, 10), (0, 0)], (1015, 1995)),
            ('edited', [(0, 0), (30, 0), (40, 20), (10, 20), (0, 0)], (1020, 1990)),
        ):
            name = f'{prefix}.{stage}'
            native = (args.output / f'{name}.ps').read_bytes()
            body = native.split(b'%%EndSetup', 1)[1].split(b'%%Trailer', 1)[0]
            items = parsed(body)
            geometry = [item for item in items if getattr(item, 'command', None) in GEOMETRY]
            coordinates = [tuple(map(float, item.tokens)) for item in geometry]
            copies = 2 if prefix == 'paired' else 1
            assert coordinates == corners * copies + [(50, 0), (60, 10)]
            assert all(item.is_pseudo_comment == (prefix == 'paired' and 5 <= index < 10) for index, item in enumerate(geometry))
            counts = [float(item.tokens[0]) for item in items if getattr(item, 'command', None) == 'As']
            assert counts == [4] * copies
            dictionaries = [item for item in items if isinstance(item, dict) and 'ai::LiveShape' in item]
            assert len(dictionaries) == copies
            for dictionary in dictionaries:
                definition = dictionary['ai::LiveShape']
                assert definition['ai::LiveShape::HandlerName'] == 'ai::Polygon'
                values = definition['ai::LiveShape::Params']
                assert values['ai::Polygon::NumSides'] == 4 and values['ai::Polygon::Radius'] == -11
                assert values['ai::Polygon::IsRegular'] == 0 and values['ai::Polygon::Clockwise'] == 0
                assert (values['ai::Polygon::CenterX'], values['ai::Polygon::CenterY']) == center
                assert not any(key.startswith('ai::Rectangle::') for key in values)
            path = args.output / f'{name}.ai'
            assert all(program == native for program in native_programs(path))
            pdf = PdfReader(path)
            assert len(pdf.pages) == 2
            expected = ('0 g 0 0 m ' + ('20 0 l 30 10 l 10 10 l' if stage == 'sheared' else '30 0 l 40 20 l 10 20 l') + ' h f 50 0 m 60 10 l S').encode()
            assert all(page.get_contents().get_data() == expected for page in pdf.pages)
    print('Verified producer irregular polygons and 4 synthetic native/PDF saves with independent readers.')


if __name__ == '__main__':
    main()
