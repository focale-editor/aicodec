#!/usr/bin/env python3
"""Verify retained opacity masks, raster bytes and independent artboard edits."""

import argparse
import hashlib
import importlib
import json
from pathlib import Path
import re
import subprocess
import sys

from corpus_support import REVISION, native_programs
from verify_live_shapes import walk_body
from verify_native_artboard_text import normalized, text_state
from verify_native_page_saves import native_edit

CARRIERS = {
    'simple_cc_legacy.ai': '8a21da7da0f48ffbf0ba6516845a41a26551a9bdb0345f7a084c258ce748c71e',
    'simple_v2020.ai': '42eb592b5168000b099adfda005166d79db9a7930fa4620548390a6504620609',
    'text_transforms.ai': '2f79f4e9805e3f0c898def8a1fc022ace65214d4498caec95007a72baeea5cf1',
    'synthetic-raster': '92e118d939c58c5203bdb2d5a236b313f576e65d6cc90bdbbd214dc3e7543306',
    'synthetic-vector': '453c13680789a8cd4fed36d1fb22f802b8f85bb612b3f1f7311b219ac0baf143',
}


def mask_owners(document):
    """Find complete symbol dictionaries with independently parsed mask fields."""
    return [
        item for symbol in document.setup.all_subsections_of_type_recursive(b'%AI14_BeginSymbol')
        for item in walk_body(symbol.children)
        if isinstance(item, dict) and item.get('_type') == 'ArtDictionary' and 'AI9_Mask' in item
    ]


def mask_state(document):
    """Retain every field, command, image descriptor and exact sample byte."""
    owners = mask_owners(document)
    images = []
    for owner in owners:
        mask = owner['AI9_Mask']
        assert set(vars(mask)) == {'_art', 'Linked', 'Disabled', 'Clipping', 'Inverted'}
        assert (mask.Linked, mask.Disabled, mask.Clipping, mask.Inverted) == (True, False, False, False)
        assert mask.Art[0].command == 'X=' and mask.Art[-1].command == 'X+'
        for item in walk_body(mask.Art):
            if getattr(item, 'command', None) == 'XI':
                assert item.bits == 8 and item.image_type == 1 and item.alpha_channel_count == 0 and item.is_binary == 1
                assert len(item.data.raw) == item.h * item.w
                images.append((item.h, item.w, len(item.data.raw)))
    return dict(owners=normalized(owners), images=images)


def main():
    """Require pinned producer provenance and all twenty declared transactions."""
    if not __debug__:
        raise RuntimeError('Run verification without assertion stripping')
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--inkai-source', required=True, type=Path)
    parser.add_argument('--output', default=Path('test/corpus/output/artboard-masks'), type=Path)
    args = parser.parse_args()
    assert subprocess.check_output(['git', '-C', str(args.inkai_source), 'rev-parse', 'HEAD'], text=True).strip() == REVISION
    assert not subprocess.check_output(['git', '-C', str(args.inkai_source), 'status', '--porcelain', '--untracked-files=no'], text=True).strip()
    sys.path.insert(0, str(args.inkai_source.resolve()))
    inkai = importlib.import_module('inkai')
    text_parser = importlib.import_module('inkai.parser.text').TextDocumentParser
    stream = importlib.import_module('inkai.parser.streamreader').StreamWrapper
    manifest = {entry['file']: entry for entry in json.loads(Path('test/corpus/manifest.json').read_text())['files']}
    rows = json.loads((args.output / 'report.json').read_text())
    expected = {(name, operation) for name in CARRIERS for operation in ('create', 'resize', 'reorder', 'remove')}
    assert len(rows) == len(expected) == 20 and {(row['source'], row['operation']) for row in rows} == expected
    originals, states, texts = {}, {}, {}
    for name, checksum in CARRIERS.items():
        original = args.output / f'{name}.original.ps'
        originals[name] = original.read_bytes()
        assert hashlib.sha256(originals[name]).hexdigest() == checksum
        states[name] = mask_state(inkai.parse(str(original)))
        assert len(states[name]['owners']) == (1 if name.startswith('synthetic-') else 2)
        assert states[name]['images'] == ([] if name == 'synthetic-vector' else [(4, 1, 4)] if name == 'synthetic-raster' else [(32, 32, 1024), (29, 30, 870)])
        if name.startswith('synthetic-'):
            continue
        entry, fixture = manifest[name], Path('test/corpus/files', name)
        assert entry['revision'] == REVISION and fixture.stat().st_size == entry['size']
        assert hashlib.sha256(fixture.read_bytes()).hexdigest() == entry['sha256']
        producer = args.output / f'{name}.producer.ps'
        assert native_programs(fixture) == [producer.read_bytes()]
        document = inkai.parse(str(producer))
        assert mask_state(document) == states[name]
        copied = re.findall(rb'%_/ArtDictionary :\s+%_/Mask :[\s\S]*?%_; \(AI9_Mask\) ,\s+%_;', originals[name])
        assert len(copied) == 2 and all(section in producer.read_bytes() for section in copied)
        texts[name] = text_state(document, text_parser, stream)
        assert text_state(inkai.parse(str(original)), text_parser, stream) == texts[name]
    checked = []
    for row in rows:
        name, operation = row['source'], row['operation']
        target = args.output / f'{name}.{operation}.ps'
        native_edit(originals[name], target.read_bytes(), dict(row, fixture=None))
        document = inkai.parse(str(target))
        assert mask_state(document) == states[name]
        if name in texts:
            assert text_state(document, text_parser, stream) == texts[name]
        checked.append(f'{name}/{operation}')
        print(checked[-1], 'passed', flush=True)
    (args.output / 'independent-report.json').write_text(json.dumps(dict(oracleRevision=REVISION, transactions=checked, producerMasks=6), indent=2) + '\n')


if __name__ == '__main__':
    main()
