#!/usr/bin/env python3
"""Verify retained appearance graphs and complete symbols after artboard edits."""

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
from verify_native_artboard_masks import mask_state
from verify_native_artboard_symbols import symbols
from verify_native_artboard_text import normalized, text_state
from verify_native_page_saves import native_edit

CARRIERS = {
    'simple_cc_legacy.ai': 'a1d38b514f84b3418654a9b79b08054c29cad365417b17abaaa4ca772a7ede80',
    'simple_v2020.ai': '6281183a9c06b1dc3edf777038ba809774f02648962f772144b2e44df4089901',
    'text_transforms.ai': '07c57119e4ff0d059af00c8e5136b93c73e6100a32dcf84aef7353bcf26fc90d',
    'flowtext.ai': 'ea6f2ea6203e6799ddb1cdbd9bf923071c42b15f2779f2cd4a05df02a5d1962e',
    'synthetic-style': '2a83927df19c8f2ee4aeae7dfbea79c360fb5bea21f8f303b049d423b2fe5c42',
}


def styles(document):
    """Index all complete appearance graphs without executing any filter."""
    owners = [item for item in walk_body(document.setup.children) if type(item).__name__ == 'KnownStyle']
    result = {style._name.encode('latin1'): style for style in owners}
    assert len(result) == len(owners)
    return result


def panel(document):
    """Locate one source inventory, including the actual legacy NUL wrapper."""
    sections = [
        section for kind in (b'%AI10_BeginSymbolList', b'%AI10_BeginSymbolList\0', b'%AI24_BeginSymbolList')
        for section in document.setup.all_subsections_of_type_recursive(kind)
    ]
    assert len(sections) == 1
    return sections[0]


def appearance_state(document):
    """Check named uses, independent inventories and complete retained graphs."""
    definitions, appearances = symbols(document), styles(document)
    inventory = panel(document)
    assert not inventory.children
    assert len(inventory.arguments) == len(definitions) and set(inventory.arguments) == set(definitions)
    for symbol in definitions.values():
        for item in walk_body(symbol.children):
            if getattr(item, 'command', None) == 'XW' and item.tokens[0] in (b'0', b'1') and item.tokens[1]:
                assert item.tokens[1] in appearances
    return dict(
        symbols={name: normalized(symbol) for name, symbol in definitions.items()},
        styles={name: normalized(style) for name, style in appearances.items()},
        inventory=normalized(inventory),
        masks=mask_state(document),
    )


def main():
    """Require exact source provenance and all twenty prescribed transactions."""
    if not __debug__:
        raise RuntimeError('Run verification without assertion stripping')
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--inkai-source', required=True, type=Path)
    parser.add_argument('--output', default=Path('test/corpus/output/artboard-styles'), type=Path)
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
        document = inkai.parse(str(original))
        states[name] = appearance_state(document)
        assert len(states[name]['symbols']) == (1 if name == 'synthetic-style' else 5 if name == 'flowtext.ai' else 15)
        assert len(states[name]['styles']) == (1 if name == 'synthetic-style' else 11 if name in ('flowtext.ai', 'text_transforms.ai') else 12)
        if name == 'synthetic-style':
            continue
        entry, fixture = manifest[name], Path('test/corpus/files', name)
        assert entry['revision'] == REVISION and fixture.stat().st_size == entry['size']
        assert hashlib.sha256(fixture.read_bytes()).hexdigest() == entry['sha256']
        producer = args.output / f'{name}.producer.ps'
        assert native_programs(fixture) == [producer.read_bytes()]
        document = inkai.parse(str(producer))
        producer_symbols, producer_styles = symbols(document), styles(document)
        assert {key: normalized(value) for key, value in producer_symbols.items() if key != b'Band'} == states[name]['symbols']
        assert {key: normalized(value) for key, value in producer_styles.items() if key != b'Chrome Highlight'} == states[name]['styles']
        assert len(producer_styles) - len(states[name]['styles']) == (0 if name == 'flowtext.ai' else 1)
        copied = re.findall(rb'%AI14_BeginSymbol[\s\S]*?%AI10_EndSymbol', originals[name])
        assert len(copied) == len(states[name]['symbols']) and all(section in producer.read_bytes() for section in copied)
        assert mask_state(document) == states[name]['masks']
        if name != 'flowtext.ai':
            assert normalized(panel(document)) == states[name]['inventory']
            copied_panel = re.search(rb'%AI(10|24)_BeginSymbolList\x00?[\s\S]*?%AI\1_EndSymbolList\x00?', originals[name])
            assert copied_panel is not None and copied_panel.group() in producer.read_bytes()
        texts[name] = text_state(document, text_parser, stream)
        assert text_state(inkai.parse(str(original)), text_parser, stream) == texts[name]
    checked = []
    for row in rows:
        name, operation = row['source'], row['operation']
        target = args.output / f'{name}.{operation}.ps'
        native_edit(originals[name], target.read_bytes(), dict(row, fixture=None))
        document = inkai.parse(str(target))
        assert appearance_state(document) == states[name]
        if name in texts:
            assert text_state(document, text_parser, stream) == texts[name]
        checked.append(f'{name}/{operation}')
        print(checked[-1], 'passed', flush=True)
    (args.output / 'independent-report.json').write_text(json.dumps(dict(oracleRevision=REVISION, transactions=checked, producerSymbols=50, producerStyles=46), indent=2) + '\n')


if __name__ == '__main__':
    main()
