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
    'simple_cc_legacy.ai': '326c86b6920d46de35d3023d1d5bd24f2f822b3a9c76229f9e56066bef62d025',
    'simple_v2020.ai': '3c3c80b13047eaff1e6d999d8cdf42add1fd0aef5920aa9c11b7c410d54d3f93',
    'text_transforms.ai': 'af48b911bf228311be6be2c9a1257a2dbfb539452884829a51ed0db353c53cd8',
    'flowtext.ai': 'ea6f2ea6203e6799ddb1cdbd9bf923071c42b15f2779f2cd4a05df02a5d1962e',
    'synthetic-style': '2a83927df19c8f2ee4aeae7dfbea79c360fb5bea21f8f303b049d423b2fe5c42',
}


def styles(document):
    """Index all complete appearance graphs without executing any filter."""
    owners = [item for item in walk_body(document.setup.children) if type(item).__name__ == 'KnownStyle']
    result = {style._name.encode('latin1'): style for style in owners}
    assert len(result) == len(owners)
    return result


def appearance_state(document):
    """Check named uses, independent inventories and complete retained graphs."""
    definitions, appearances = symbols(document), styles(document)
    inventory = document.setup.first_subsection_of_type(b'%AI24_BeginSymbolList')
    assert inventory is not None and not inventory.children
    assert tuple(inventory.arguments) == tuple(definitions)
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
