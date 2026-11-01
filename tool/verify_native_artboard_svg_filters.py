#!/usr/bin/env python3
"""Compare retained Illustrator filter trees and surrounding data after board edits."""

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
from verify_native_artboard_brushes import brush_state
from verify_native_artboard_styles import appearance_state, panel, styles
from verify_native_artboard_symbols import symbols
from verify_native_artboard_text import normalized, text_state
from verify_native_page_saves import native_edit

CARRIERS = {
    'simple_cc_legacy.ai': '18f7d0bbd8b76cc3afd00b62f768916601c033702edce896f674c4b0f6b186fe',
    'simple_v2020.ai': 'f7ff325995173f5cb32788394a2a24c94e50550ba9aaa54a0761661b691b8df0',
    'text_transforms.ai': '3f9cd13112d92b72593a12b49825986bd7e2d828720341d92257f8866a57d0ea',
    'flowtext.ai': '55776d4af3473780c72c012fc9b64e3cdfca610b1f8d2e2734dc9f084da00149',
    'synthetic-filter': '05ffea9624ff6bb604001ad671f4d41da7b468bb419e22d9debfec0dc9b85cde',
}


def filter_state(document):
    """Keep every native XML field, attribute, child, value and ordered filter."""
    result = [item.Def for item in walk_body(document.setup.children) if type(item).__name__ == 'SVGFilter']
    assert all(node['xmlnode-nodename'] == 'filter' for node in result)
    return result


def animation_count(nodes):
    """Count real nested animation owners independently of AiKit's inspector."""
    return sum((node['xmlnode-nodename'] == 'animate') + animation_count(node['xmlnode-children']) for node in nodes)


def filter_bytes(data):
    """Extract entire collections from checksum-pinned native fixture data."""
    return re.findall(rb'%AI10_BeginSVGFilter[\s\S]*?%AI10_EndSVGFilter', data)


def main():
    """Require exact producer trees, unchanged resource data and twenty transactions."""
    if not __debug__:
        raise RuntimeError('Run verification without assertion stripping')
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--inkai-source', required=True, type=Path)
    parser.add_argument('--output', default=Path('test/corpus/output/artboard-svg-filters'), type=Path)
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
    originals, filters, resources = {}, {}, {}
    for name, checksum in CARRIERS.items():
        original = args.output / f'{name}.original.ps'
        originals[name] = original.read_bytes()
        assert hashlib.sha256(originals[name]).hexdigest() == checksum
        document = inkai.parse(str(original))
        filters[name] = filter_state(document)
        synthetic = name == 'synthetic-filter'
        assert len(filters[name]) == (1 if synthetic else 18)
        assert animation_count(filters[name]) == (1 if synthetic else 6)
        if synthetic:
            continue
        entry, fixture = manifest[name], Path('test/corpus/files', name)
        assert entry['revision'] == REVISION and fixture.stat().st_size == entry['size']
        assert hashlib.sha256(fixture.read_bytes()).hexdigest() == entry['sha256']
        producer = args.output / f'{name}.producer.ps'
        assert native_programs(fixture) == [producer.read_bytes()]
        source = inkai.parse(str(producer))
        assert filter_state(source) == filters[name]
        assert filter_bytes(producer.read_bytes()) == filter_bytes(originals[name])
        appearance = appearance_state(document)
        assert {key: normalized(value) for key, value in styles(source).items() if key != b'Chrome Highlight'} == appearance['styles']
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
        assert filter_state(document) == filters[name]
        assert filter_bytes(data) == filter_bytes(originals[name])
        if name in resources:
            text, brushes, appearance = resources[name]
            assert text_state(document, text_parser, stream) == text
            assert brush_state(document, data) == brushes
            assert appearance_state(document) == appearance
        checked.append(f'{name}/{operation}')
        print(checked[-1], 'passed', flush=True)
    report = dict(oracleRevision=REVISION, transactions=checked, producerFilters=72, producerAnimations=24)
    (args.output / 'independent-report.json').write_text(json.dumps(report, indent=2) + '\n')


if __name__ == '__main__':
    main()
