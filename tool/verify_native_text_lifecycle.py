#!/usr/bin/env python3
"""Check synthetic lifecycle/save structure with pinned independent ATE/PDF readers.

This does not certify glyph shaping or Illustrator rendering. No external artwork
is created or downloaded; the oracle revision is checked just as for corpus tools.
"""

import argparse
import importlib
import io
import json
import re
import subprocess
import sys
from pathlib import Path

from pypdf import PdfReader

from corpus_support import REVISION, native_programs
from verify_native_text import field
from verify_native_text_paints import native_payload


def main():
    if not __debug__:
        raise RuntimeError('Run verification without assertion stripping')
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--reference', required=True, type=Path)
    parser.add_argument('--output', type=Path, default=Path('test/corpus/output/text-lifecycle'))
    args = parser.parse_args()
    assert subprocess.check_output(['git', '-C', str(args.reference), 'rev-parse', 'HEAD'], text=True).strip() == REVISION
    assert not subprocess.check_output(['git', '-C', str(args.reference), 'status', '--porcelain', '--untracked-files=no'], text=True).strip()
    sys.path.insert(0, str(args.reference.resolve()))
    reader = importlib.import_module('inkai.parser.text').TextDocumentParser
    stream = importlib.import_module('inkai.parser.streamreader').StreamWrapper
    rows = json.loads((args.output / 'report.json').read_text())
    expected = {
        'original': (['Old'], [[0]]),
        'created': (['New', 'Temporary'], [[0], [1]]),
        'copied': (['New', 'Temporary', 'New'], [[0], [1], [2]]),
        'linked': (['New', 'Temporary', 'New'], [[0], [1], [2, 3]]),
        'removed': (['New'], [[0]]),
        'composed': (['New'], [[0]]),
    }
    assert {row['name'] for row in rows} == {f'{prefix}.{stage}' for prefix in ('compact', 'named') for stage in expected}
    typography = {}
    for row in rows:
        prefix, stage = row['name'].split('.')
        native = (args.output / f'{row["name"]}.ps').read_bytes()
        payload = (args.output / f'{row["name"]}.ate').read_bytes()
        assert native_payload(native)[0] == payload
        document = reader.read_object(stream(io.BytesIO(payload)))
        resources = field(document, '0', 'DocumentResources')
        current_typography = {key: value for key, value in resources.items() if key not in ('/8', '/TextFrameSet')}
        if stage == 'original':
            typography[prefix] = current_typography
        assert current_typography == typography[prefix]
        stories = field(field(document, '1', 'DocumentObjects'), '1', 'TextObjects')
        texts = [field(field(story, '0', 'Model'), '0', 'Text') for story in stories]
        frames = [[field(entry, '0', 'Resource') for entry in field(field(story, '1', 'View'), '0', 'Frames')] for story in stories]
        wanted_texts, wanted_frames = expected[stage]
        assert texts == [text + '\r' for text in wanted_texts] and frames == wanted_frames
        assert row['texts'] == wanted_texts and row['frames'] == wanted_frames
        table = field(resources, '8', 'TextFrameSet')
        definitions = field(table, '0', 'Resources')
        identities = [field(field(entry, '0', 'Resource'), '97', 'UUID') for entry in definitions]
        assert len(set(identities)) == len(identities) == sum(map(len, frames))
        display = [field(entry, '0', 'Resource') for entry in field(table, '1', 'DisplayList')]
        assert display == list(range(len(definitions)))
        refs = []
        for body in re.findall(rb'/AI11Text\s*:(.*?);', native, re.S):
            values = [int(re.search(rb'(\d+)\s*/' + key, body).group(1)) for key in (b'FreeUndo', b'StoryIndex', b'FrameIndex')]
            assert values[0] == 0
            refs.append(tuple(values[1:]))
        assert sorted(refs) == [(index, local) for index, linked in enumerate(frames) for local in range(len(linked))]
        if stage == 'composed':
            strikes = field(field(stories[0], '1', 'View'), '2', 'Strikes')
            assert strikes and field(strikes[0], '99', 'StreamTag') in ('/PC', '/PathSelectGroupCharacter')
    for prefix in ('compact', 'named'):
        path = args.output / f'{prefix}.ai'
        programs = native_programs(path)
        assert programs and all(program == (args.output / f'{prefix}.composed.ps').read_bytes() for program in programs)
        pdf = PdfReader(path)
        assert len(pdf.pages) == 2 and all(page.extract_text().strip() == 'New' for page in pdf.pages)
    print('Verified 12 independent ATE snapshots, drawing references and 2 complete PDF-backed AI saves (structural acceptance).')


if __name__ == '__main__':
    main()
