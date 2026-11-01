#!/usr/bin/env python3
"""Verify retained producer symbol data independently after artboard changes."""

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
    'simple_cc_legacy.ai': 'cd1718ce6d0443c35b98aaa26e1cf1ac9c5ae4f64cf0e86d4a794a2be9604092',
    'simple_v2020.ai': 'a833a94b16fafc1e7856696b80b2d96e398cfc428a03d1db466429121d6c332e',
    'text_transforms.ai': '9b510ef541d0a792d202012906f8fdcc3435423f94cb4c71ca998790560ac385',
    'flowtext.ai': 'c8a8e0d888340587c96abef82a2c3055e65423a218f79ef0bf0bcca5bfe6d84a',
    'synthetic-symbol': '034d6c18e803648821c73a38e9935c33dc2dd305cd52c65f3775ac38872d244e',
}
COMMON = (
    b'Button_over', b'Credit Card', b'DateField_over', b'Dropdown_over', b'Home',
    b'Panel_CloseButtonOver', b'PopUpButton_over', b'Print', b'RSS', b'Shopping Cart',
    b'TabBar-tab_over', b'TextArea_focus',
)
FLOW = (b'Gerbera', b'Schnittmarken (9-Slice)', b'Vektorschmutz')


def symbols(document):
    """Retain the complete independent syntax tree of each named definition."""
    result = {}
    for section in document.setup.all_subsections_of_type_recursive(b'%AI14_BeginSymbol'):
        # The external parser retains the definition name before its first A.
        first = section.children[0]
        assert first.command == 'A' and first.token_is_string == [True, False]
        name = first.tokens[0]
        assert name not in result
        result[name] = section
    return result


def symbol_state(document):
    """Check panel order, unique references and all retained geometry/metadata."""
    definitions = symbols(document)
    inventory = document.setup.first_subsection_of_type(b'%AI24_BeginSymbolList')
    assert inventory is not None and not inventory.children
    assert tuple(definitions) == tuple(inventory.arguments)
    gradients = {section.arguments[0] for section in document.setup.all_subsections_of_type_recursive(b'%AI5_BeginGradient:')}
    styles = [item for item in walk_body(document.setup.children) if type(item).__name__ == 'KnownStyle']
    style_names = {style._name.encode('latin1') for style in styles}
    assert len(styles) == len(style_names)
    operations = [item for symbol in definitions.values() for item in walk_body(symbol.children) if hasattr(item, 'command')]
    for item in operations:
        if item.command == 'Bg':
            assert item.tokens[1] in gradients
        elif item.command == 'XW' and item.tokens[0] == b'1':
            assert item.tokens[1] in style_names
    return dict(
        definitions={name: normalized(symbol) for name, symbol in definitions.items()},
        inventory=normalized(inventory),
        styles=[normalized(style) for style in styles],
        paths=sum(item.command == 'm' for item in operations),
    )


def main():
    """Require pinned sources and all twenty independent edit transactions."""
    if not __debug__:
        raise RuntimeError('Run verification without assertion stripping')
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--inkai-source', required=True, type=Path)
    parser.add_argument('--output', default=Path('test/corpus/output/artboard-symbols'), type=Path)
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
        states[name] = symbol_state(document)
        names = (b'board-0',) if name == 'synthetic-symbol' else FLOW if name == 'flowtext.ai' else COMMON
        assert tuple(states[name]['definitions']) == names
        assert states[name]['paths'] == (1 if name == 'synthetic-symbol' else 167 if name == 'flowtext.ai' else 65)
        if name == 'synthetic-symbol':
            continue
        entry, fixture = manifest[name], Path('test/corpus/files', name)
        assert entry['revision'] == REVISION and fixture.stat().st_size == entry['size']
        assert hashlib.sha256(fixture.read_bytes()).hexdigest() == entry['sha256']
        producer = args.output / f'{name}.producer.ps'
        assert native_programs(fixture) == [producer.read_bytes()]
        document = inkai.parse(str(producer))
        originals_symbols = symbols(document)
        assert {name: normalized(originals_symbols[name]) for name in names} == states[name]['definitions']
        copied = re.findall(rb'%AI14_BeginSymbol[\s\S]*?%AI10_EndSymbol', originals[name])
        assert len(copied) == len(names) and all(section in producer.read_bytes() for section in copied)
        texts[name] = text_state(document, text_parser, stream)
        assert text_state(inkai.parse(str(original)), text_parser, stream) == texts[name]
    checked = []
    for row in rows:
        name, operation = row['source'], row['operation']
        target = args.output / f'{name}.{operation}.ps'
        native_edit(originals[name], target.read_bytes(), dict(row, fixture=None))
        document = inkai.parse(str(target))
        assert symbol_state(document) == states[name]
        if name in texts:
            assert text_state(document, text_parser, stream) == texts[name]
        checked.append(f'{name}/{operation}')
        print(checked[-1], 'passed', flush=True)
    (args.output / 'independent-report.json').write_text(json.dumps(dict(oracleRevision=REVISION, transactions=checked, producerSymbolDefinitions=39), indent=2) + '\n')


if __name__ == '__main__':
    main()
