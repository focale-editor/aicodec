#!/usr/bin/env python3
"""Verify mask transactions and complete AI saves with the pinned native reader."""

import argparse
import hashlib
import importlib
import json
from pathlib import Path
import re
import subprocess
import sys

from pypdf import PdfReader

from corpus_support import REVISION, native_programs
from verify_native_appearance_graphs import patch
from verify_native_artboard_text import normalized
from verify_native_structure import native_values, parsed
from verify_native_transparency import PRINTING


def main():
    """Require six complete saves, retained producer artwork and exact byte edits."""
    if not __debug__:
        raise RuntimeError('Run verification without assertion stripping')
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--inkai-source', required=True, type=Path)
    args = parser.parse_args()
    assert subprocess.check_output(['git', '-C', str(args.inkai_source), 'rev-parse', 'HEAD'], text=True).strip() == REVISION
    assert not subprocess.check_output(['git', '-C', str(args.inkai_source), 'status', '--porcelain', '--untracked-files=no'], text=True).strip()
    sys.path.insert(0, str(args.inkai_source.resolve()))
    mask_type = importlib.import_module('inkai.parser.hierarchy_objects').Mask
    output = Path('test/corpus/output/opacity-masks')
    rows = json.loads((output / 'report.json').read_text())
    assert len(rows) == 6 and {row['name'] for row in rows} == {'path', 'group', 'child', 'raster', 'producer-0', 'producer-1'}
    fixture = Path('test/corpus/files/simple_v2020.ai')
    entry, = [entry for entry in json.loads(Path('test/corpus/manifest.json').read_text())['files'] if entry['file'] == fixture.name]
    assert entry['revision'] == REVISION and entry['license']
    assert fixture.stat().st_size == entry['size'] and hashlib.sha256(fixture.read_bytes()).hexdigest() == entry['sha256']
    producer = (output / 'producer.ps').read_bytes()
    assert native_programs(fixture) == [producer]
    for row in rows:
        name = row['name']
        before = (output / f'{name}.before.ps').read_bytes()
        after = (output / f'{name}.after.ps').read_bytes()
        first, last = row['beforeMask']
        raw = before[first:last]
        target = after[slice(*row['afterMask'])]
        old_mask, = parsed(raw)
        new_mask, = parsed(target)
        assert isinstance(old_mask, mask_type) and isinstance(new_mask, mask_type)
        assert (old_mask.Linked, old_mask.Disabled, old_mask.Clipping, old_mask.Inverted) == (True, False, False, False)
        assert (new_mask.Linked, new_mask.Disabled, new_mask.Clipping, new_mask.Inverted) == (False, True, True, True)
        assert normalized(old_mask.Art) == normalized(new_mask.Art)
        assert old_mask.Art[0].command == 'X=' and old_mask.Art[-1].command == 'X+'
        if name.startswith('producer-'):
            assert raw in producer
        # Only the four outer flags may change, never tokens inside raster bytes.
        opening, closing = raw.index(b'X='), raw.rindex(b'X+') + 2
        prefix, count = re.subn(rb'1(?= /Bool \(Linked\))', b'0', raw[:opening])
        assert count == 1
        suffix = raw[closing:]
        for key in (b'Disabled', b'Clipping', b'Inverted'):
            suffix, count = re.subn(rb'0(?= /Bool \(' + key + rb'\))', b'1', suffix)
            assert count == 1
        expected_mask = prefix + raw[opening:closing] + suffix
        assert target == expected_mask
        expected = patch(before, [(first, last, expected_mask), (*row['printing'], PRINTING)])
        expected = re.sub(rb'%%BoundingBox: [^\r\n]+', b'%%BoundingBox: -20 -30 120 140', expected)
        expected = re.sub(rb'%%HiResBoundingBox: [^\r\n]+', b'%%HiResBoundingBox: -20.0 -30.0 120.0 140.0', expected)
        assert after == expected, name
        saved = output / f'{name}.ai'
        programs = native_programs(saved)
        assert programs and all(program == after for program in programs)
        pdf = PdfReader(saved)
        assert len(pdf.pages) == 2
        for page in pdf.pages:
            assert page.get_contents().get_data() == b'q /Host1 gs 0 0 0 rg 0 0 m 10 0 l 10 10 l h f Q'
            state = page['/Resources']['/ExtGState']['/Host1']
            assert state['/ca'] == .25 and state['/CA'] == .25 and state['/BM'] == '/Multiply' and state['/SMask'] == '/None'
        print(name, 'passed', flush=True)
    for kind in ('blend', 'fill', 'stroke'):
        part, = parsed((output / f'created-{kind}.part').read_bytes())
        assert part.Filter[0] == f'{kind.title()} Style Filter'
        paint = part.Dict[f'{kind.title()}Style']
        values = [value for value in native_values(paint) if getattr(value, 'command', None) == 'Xy']
        command, = values
        assert list(map(float, command.tokens)) == [1, .25, 1, 1, 0]
        print('created-' + kind, 'passed', flush=True)
    active = PdfReader(output / 'active.ai')
    assert len(active.pages) == 2
    for page in active.pages:
        state = page['/Resources']['/ExtGState']['/Host1']
        assert state['/ca'] == .25 and state['/BM'] == '/Multiply'
        mask = state['/SMask']
        assert mask['/S'] == '/Luminosity' and mask['/BC'] == [0]
        form = mask['/G']
        assert form['/Subtype'] == '/Form' and form['/Group']['/CS'] == '/DeviceGray'
        assert form.get_data() == b'0.3 g 0 0 m 10 0 l 10 10 l h f'
    programs = native_programs(output / 'active.ai')
    assert programs and all(program == programs[0] for program in programs)
    assert b'1 0.075 1 1 0 Xy' in programs[0]
    assert b'0 /Bool (Disabled)' in programs[0] and b'1 /Bool (Clipping)' in programs[0]
    print('active-mask', 'passed', flush=True)
    (output / 'independent-report.json').write_text(json.dumps(dict(oracleRevision=REVISION, transactions=[row['name'] for row in rows] + ['active-mask'], createdParts=['blend', 'fill', 'stroke']), indent=2) + '\n')


if __name__ == '__main__':
    main()
