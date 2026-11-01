#!/usr/bin/env python3
"""Verify retained brush descriptors, panel order and resolved calligraphic styles."""

import argparse
import hashlib
import importlib
import json
from pathlib import Path
import re
import subprocess
import sys

from corpus_support import REVISION, native_programs
from verify_native_artboard_brushes import brush_state, brush_sections
from verify_native_artboard_svg_filters import filter_state, filter_bytes
from verify_native_artboard_lifecycle import requests, verify as verify_lifecycle
from verify_native_artboard_styles import appearance_state, panel, styles
from verify_native_artboard_symbols import symbols
from verify_native_artboard_text import normalized, text_state
from verify_native_page_saves import native_edit

CARRIERS = {
    'simple_cc_legacy.ai': 'a4194813b7a9c642c2cfb49ad40a5d69bd282181600f87343b0d55f0da57fdff',
    'simple_v2020.ai': 'e46507a7159875404eb75f670345005ca81e1f7a7d904ebcc374923eecf89fd3',
    'text_transforms.ai': 'aa3f7efd695da058fc32285d70cf4324e439fafc94b335fae13e437a42473c6f',
    'flowtext.ai': '70f93ae522457a083f2f8d79bc6f6bd8d3d9e5744f61388d3512b1f8dbea3cf1',
    'synthetic-descriptor': '81992990dd725885f2d7dcdbfc5b4ed24c2b6d44493e8d3398d7a27950ffdb9b',
}


def reference_pairs(value):
    """Read literal GObjRef owners from the independent appearance model."""
    if type(value).__name__ == 'GObjRef':
        assert len(value.PluginObject) == 2 and value._plugin_obj is None
        yield tuple(reversed(value.PluginObject))
    elif isinstance(value, dict):
        for child in value.values():
            yield from reference_pairs(child)
    elif isinstance(value, (list, tuple)):
        for child in value:
            yield from reference_pairs(child)
    elif hasattr(value, '__dict__'):
        yield from reference_pairs(vars(value))


def descriptor_state(document):
    """Resolve panel, native resource and appearance identities independently."""
    sections = list(document.setup.all_subsections_of_type_recursive(b'%AI8_BeginPluginObject'))
    names, inventory = {}, None
    for section in sections:
        values = section.arguments
        assert not section.children and len(values) >= 4 and len(values) % 2 == 0
        assert values[-1] == b'.' and all(value == b'-' for value in values[3:-1:2])
        plugin, name = values[:2]
        payload = b''.join(values[2::2])
        if plugin == b'Adobe Brush Manager Order':
            assert name == plugin and inventory is None
            fields = [field.strip() for field in payload.split(b'/')]
            assert fields.pop() == b'' and len(fields) % 2 == 0
            inventory = list(zip(fields[::2], fields[1::2]))
        else:
            assert (plugin, name) not in names
            names[plugin, name] = payload
        if plugin in (b'Adobe ArtOnPath Brush Tool', b'Adobe PatternOnPath Brush Tool'):
            tiles = [field.strip() for field in payload.split(b'/')[1:6]]
            assert all(tile in brush_sections(document) for tile in tiles if tile)
    assert inventory is not None and len(inventory) == len(set(inventory)) and set(inventory) == set(names)
    appearances = styles(document)
    references = list(reference_pairs(appearances))
    assert all(reference in names for reference in references)
    return dict(sections=normalized(sections), references=references, styles={key: normalized(value) for key, value in appearances.items()})


def descriptor_bytes(data):
    """Compare exact known descriptor sections, including fragment boundaries."""
    return re.findall(rb'%AI8_BeginPluginObject[\s\S]*?%AI8_EndPluginObject', data)


def verify_full(inkai, output, expected_state):
    """Check six prescribed lifecycle steps on the complete producer program."""
    name = 'text_transforms.ai'
    rows = json.loads((output / 'full-report.json').read_text())
    expected = {variant: predecessor for (source, variant), predecessor in requests([name]).items() if source == name}
    assert len(rows) == len(expected) == 6 and {row['variant'] for row in rows} == set(expected)
    assert (output / f'{name}.full.original.ps').read_bytes() == (output / f'{name}.producer.ps').read_bytes()
    checked = []
    for row in rows:
        variant = row['variant']
        assert row['source'] == name
        assert row['original'] == f'{name}.full.{expected[variant]}.ps'
        assert row['result'] == f'{name}.full.{variant}.ps'
        original, target = output / row['original'], output / row['result']
        verify_lifecycle(inkai, original, target, row)
        assert descriptor_state(inkai.parse(str(target))) == expected_state
        checked.append(f'{name}/full/{variant}')
        print(checked[-1], 'passed', flush=True)
    return checked


def main():
    """Require original brush owners and all twenty-six independently prescribed transactions."""
    if not __debug__:
        raise RuntimeError('Run verification without assertion stripping')
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--inkai-source', required=True, type=Path)
    parser.add_argument('--output', default=Path('test/corpus/output/artboard-brush-descriptors'), type=Path)
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
    originals, descriptors, resources, filters = {}, {}, {}, {}
    for name, checksum in CARRIERS.items():
        original = args.output / f'{name}.original.ps'
        originals[name] = original.read_bytes()
        assert hashlib.sha256(originals[name]).hexdigest() == checksum
        document = inkai.parse(str(original))
        descriptors[name] = descriptor_state(document)
        filters[name] = filter_state(document)
        synthetic = name == 'synthetic-descriptor'
        assert len(descriptors[name]['sections']) == (5 if synthetic else 12 if name == 'flowtext.ai' else 8)
        assert len(descriptors[name]['references']) == (1 if synthetic else 0 if name == 'flowtext.ai' else 2)
        if synthetic:
            continue
        entry, fixture = manifest[name], Path('test/corpus/files', name)
        assert entry['revision'] == REVISION and fixture.stat().st_size == entry['size']
        assert hashlib.sha256(fixture.read_bytes()).hexdigest() == entry['sha256']
        producer = args.output / f'{name}.producer.ps'
        assert native_programs(fixture) == [producer.read_bytes()]
        source = inkai.parse(str(producer))
        assert descriptor_state(source) == descriptors[name]
        assert descriptor_bytes(producer.read_bytes()) == descriptor_bytes(originals[name])
        assert filter_state(source) == filters[name]
        assert filter_bytes(producer.read_bytes()) == filter_bytes(originals[name])
        appearance = appearance_state(document)
        assert {key: normalized(value) for key, value in styles(source).items()} == appearance['styles']
        assert {key: normalized(value) for key, value in symbols(source).items() if key != b'Band'} == appearance['symbols']
        if name != 'flowtext.ai':
            assert normalized(panel(source)) == appearance['inventory']
        text = text_state(source, text_parser, stream)
        brushes = brush_state(source, producer.read_bytes())
        assert text_state(document, text_parser, stream) == text
        assert brush_state(document, originals[name]) == brushes
        resources[name] = (text, brushes, appearance)
    checked = []
    for row in rows:
        name, operation = row['source'], row['operation']
        target = args.output / f'{name}.{operation}.ps'
        data = target.read_bytes()
        native_edit(originals[name], data, dict(row, fixture=None))
        document = inkai.parse(str(target))
        assert descriptor_state(document) == descriptors[name]
        assert descriptor_bytes(data) == descriptor_bytes(originals[name])
        assert filter_state(document) == filters[name]
        assert filter_bytes(data) == filter_bytes(originals[name])
        if name in resources:
            text, brushes, appearance = resources[name]
            assert text_state(document, text_parser, stream) == text
            assert brush_state(document, data) == brushes
            assert appearance_state(document) == appearance
        checked.append(f'{name}/{operation}')
        print(checked[-1], 'passed', flush=True)
    checked.extend(verify_full(inkai, args.output, descriptors['text_transforms.ai']))
    report = dict(oracleRevision=REVISION, transactions=checked, producerDescriptors=36, producerBrushReferences=6, completeSourceTransactions=6)
    (args.output / 'independent-report.json').write_text(json.dumps(report, indent=2) + '\n')


if __name__ == '__main__':
    main()
