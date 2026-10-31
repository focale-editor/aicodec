#!/usr/bin/env python3
"""Verify native ownership spans and decode paths/resources with pinned inkai."""

import argparse
from collections import Counter
import hashlib
import importlib
from io import BytesIO
import json
from pathlib import Path
import re
import subprocess
import sys

from corpus_support import REVISION, native_programs


def parsed(data):
    """Decode an exact fragment through the unmodified external native parser."""
    from inkai.parser.fileparser import FileParser
    from inkai.parser.streamreader import StreamWrapper

    # A leading newline gives the external scanner its required line-start state.
    return FileParser.read_many_objects(StreamWrapper(BytesIO(b'\n' + data + b'\n%%EOF')), b'%%EOF')


def version_ranges(data):
    """Locate all literal version delimiters in these pinned, non-executable cases.

    This is a corpus boundary check, not a general binary-safe PostScript parser.
    Fake delimiters in procedures/data are covered separately by VM/Node tests.
    """
    pattern = rb'^%(AI\d+)_(Begin_Content_if_version_gt|Alternate_Content|End_Versioned_Content)([^\r\n]*)'
    stack, result = [], []
    for match in re.finditer(pattern, data, re.MULTILINE):
        family, command, arguments = match.groups()
        if command == b'Begin_Content_if_version_gt':
            major, minor = map(int, arguments.strip(b': ').split())
            stack.append(dict(start=match.start(), family=family.decode(), major=major, minor=minor, newer=[match.end(), None], older=None))
        else:
            assert stack and stack[-1]['family'] == family.decode() and not arguments.strip()
            block = stack[-1]
            if command == b'Alternate_Content':
                assert block['older'] is None
                block['newer'][1] = match.start()
                block['older'] = [match.end(), None]
            else:
                block['older' if block['older'] is not None else 'newer'][1] = match.start()
                block['end'] = match.end()
                result.append(stack.pop())
    assert not stack
    return sorted(result, key=lambda block: block['start'])


def branch_owners(blocks, start, end):
    """Check the exact saved intervals, without evaluating a target version."""
    result = []
    for index, block in enumerate(blocks):
        for branch, key in [('newer', 'newer'), ('older', 'older')]:
            span = block[key]
            if span is not None and span[0] <= start < end <= span[1]:
                result.append(dict(block=index, branch=branch))
    return result


def native_values(value):
    """Walk the independent reader's typed data without decoding opaque binaries."""
    from inkai.parser.hierarchy_objects import Binary, HierarchyObject

    if isinstance(value, Binary):
        return
    yield value
    if isinstance(value, HierarchyObject):
        yield from native_values(value.asdict())
    elif isinstance(value, dict):
        for child in value.values():
            yield from native_values(child)
    elif isinstance(value, (list, tuple)):
        for child in value:
            yield from native_values(child)
    elif hasattr(value, 'children'):
        yield from native_values(value.children)


def complete_inventory(data, row):
    """Compare all qualified declarations/uses, including saved older branches.

    The upstream reader discards alternate branches. Removing only the verified
    delimiter comments from this inspection copy exposes both sides to its
    unchanged parser; source fragments are checked separately at exact offsets.
    """
    from inkai.parser.fileparser import FileParser
    from inkai.parser.streamreader import StreamWrapper, dec
    from inkai.parser.hierarchy_objects import KnownStyle

    flattened = re.sub(rb'^%AI\d+_(?:Begin_Content_if_version_gt|Alternate_Content|End_Versioned_Content)[^\r\n]*', b'', data, flags=re.MULTILINE)
    document = FileParser.read_document(StreamWrapper(BytesIO(flattened)))
    declarations, uses = Counter(), Counter()
    for value in native_values([document.setup, document.trailer]):
        command = getattr(value, 'command', None)
        if isinstance(value, KnownStyle):
            declarations['knownStyle', value.Name] += 1
        elif command == 'Bd':
            declarations['gradient', dec(value.tokens[0])] += 1
        elif command == 'XW' and value.integer == 1:
            uses['knownStyle', value.stylename] += 1
        elif command == 'Bg':
            uses['gradient', value.name] += 1
    assert declarations == Counter((value['kind'], dec(bytes(value['name']))) for value in row['resources']), row['file']
    assert uses == Counter((value['kind'], dec(bytes(value['name']))) for value in row['uses']), row['file']


def verify(data, row):
    """Verify every node owner and independently decode all paths and references."""
    from inkai.parser.streamreader import dec

    blocks = version_ranges(data)
    assert row['versions'] == blocks
    complete_inventory(data, row)
    nodes, stack, children = row['nodes'], [], [[] for _ in row['nodes']]
    counts = Counter()
    assert [(node['start'], -node['end']) for node in nodes] == sorted((node['start'], -node['end']) for node in nodes)
    for index, node in enumerate(nodes):
        start, end = node['start'], node['end']
        assert 0 <= start < end <= len(data)
        while stack and nodes[stack[-1]]['end'] <= start:
            stack.pop()
        assert node['parent'] == (stack[-1] if stack else None)
        if stack:
            assert end <= nodes[stack[-1]]['end']
            children[stack[-1]].append(index)
        stack.append(index)
        assert node['versions'] == branch_owners(blocks, start, end)
        counts[node['kind']] += 1
        if node['kind'] == 'path':
            items = parsed((b'%_' if node['private'] else b'') + data[start:end])
            geometry = [item for item in items if getattr(item, 'command', None) in ('m', 'l', 'L', 'c', 'C', 'v', 'V', 'y', 'Y')]
            assert [{'operator': item.command, 'numbers': list(map(float, item.tokens))} for item in geometry] == node['geometry']
            assert items[-1].command == node['paint']
            assert all(item.is_pseudo_comment == node['private'] for item in geometry)
        elif node['kind'] in ('group', 'compound', 'clip', 'layer'):
            opening = parsed(data[start:node['openingEnd']])
            closing = parsed(data[node['closingStart']:end])
            assert len(opening) == len(closing) == 1
            expected = 'Lb' if node['kind'] == 'layer' else node['operator']
            assert opening[0].command == expected and closing[0].command == expected.upper()
            if node['kind'] == 'layer':
                assert (int(opening[0].tokens[0]) != 0) == node['visible']
                assert (int(opening[0].tokens[2]) == 0) == node['locked']
        elif node['kind'] == 'record':
            assert data[start:end].startswith(('/' + node['type']).encode() + b' ' ) or data[start:end].startswith(('/' + node['type'] + ':').encode())
            assert data[start:end].endswith(b';')
    assert children == [node['children'] for node in nodes]
    for resource in row['resources']:
        node = nodes[resource['definition']]
        fragment = data[node['start']:node['end']]
        # The corpus stores whole conditional declarations; inner-name conditions
        # are qualified separately by synthetic VM/Node regressions.
        assert resource['versions'] == node['versions']
        if resource['kind'] == 'knownStyle':
            record, = parsed(fragment)
            assert record.Name == dec(bytes(resource['name']))
        else:
            opening, = parsed(data[node['start']:node['openingEnd']])
            closing, = parsed(data[node['closingStart']:node['end']])
            assert opening.command == 'Bd' and closing.command == 'BD'
            assert opening.tokens[0] == bytes(resource['name'])
    for use in row['uses']:
        command, = parsed(data[use['start']:use['end']])
        assert command.command == ('XW' if use['kind'] == 'knownStyle' else 'Bg')
        assert (command.stylename if command.command == 'XW' else command.name) == dec(bytes(use['name']))
        assert use['versions'] == branch_owners(blocks, use['start'], use['end'])
        owners = [index for index, node in enumerate(nodes) if node['start'] <= use['start'] and node['end'] >= use['end']]
        assert use['owner'] == (owners[-1] if owners else None)
        selection = {value['block']: value['branch'] for value in use['versions']}
        candidates, available = [], []
        for index, resource in enumerate(row['resources']):
            if (resource['kind'], resource['name']) != (use['kind'], use['name']):
                continue
            branches = resource['versions']
            if all(selection.get(value['block'], value['branch']) == value['branch'] for value in branches):
                candidates.append(index)
                if all(selection.get(value['block']) == value['branch'] for value in branches):
                    available.append(index)
        assert use['candidates'] == candidates
        expected = 'missing' if not candidates else 'resolved' if len(candidates) == len(available) == 1 else 'ambiguous' if len(available) > 1 else 'conditional'
        assert use['resolution'] == expected
    identifiers = []
    for index, node in enumerate(nodes):
        if node.get('type') not in ('ArtDictionary', 'Document'):
            continue
        record, = parsed(data[node['start']:node['end']])
        if node['type'] == 'ArtDictionary' and 'AI10_ArtUID' in record:
            identifiers.append(('xmlArt', index, record['AI10_ArtUID']))
        elif node['type'] == 'Document':
            for artboard in record.Recorded.get('ArtboardArray', []):
                if 'ArtboardUUID' in artboard:
                    # Artboard owners are validated below at their exact spans.
                    identifiers.append(('artboard', None, artboard['ArtboardUUID']))
    actual = []
    for value in row['identifiers']:
        node = nodes[value['owner']]
        owner, = parsed(data[node['start']:node['end']])
        identifier = bytes(value['bytes']).decode('latin-1')
        assert owner[value['key']] == identifier
        actual.append((value['kind'], value['owner'] if value['kind'] == 'xmlArt' else None, identifier))
    assert Counter(identifiers) == Counter(actual)
    counts.update(dict(versions=len(blocks), resources=len(row['resources']), uses=len(row['uses']), identifiers=len(actual)))
    return counts


def main():
    """Require all 46 sources, unchanged upstream code and exact extraction."""
    if not __debug__:
        raise RuntimeError('Run verification without assertion stripping')
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--inkai-source', required=True, type=Path)
    parser.add_argument('--output', default=Path('test/corpus/output/structure'), type=Path)
    args = parser.parse_args()
    assert subprocess.check_output(['git', '-C', str(args.inkai_source), 'rev-parse', 'HEAD'], text=True).strip() == REVISION
    assert not subprocess.check_output(['git', '-C', str(args.inkai_source), 'status', '--porcelain', '--untracked-files=no'], text=True).strip()
    sys.path.insert(0, str(args.inkai_source.resolve()))
    inkai = importlib.import_module('inkai')
    manifests = {name: json.loads(Path('test/corpus', name).read_text())['files'] for name in ('manifest.json', 'document_manifest.json')}
    rows = json.loads((args.output / 'report.json').read_text())
    assert len(rows) == 46
    assert {(row['manifest'], row['file'], row['sourceIndex']) for row in rows} == {(name, entry['file'], 0) for name, entries in manifests.items() for entry in entries}
    totals = Counter()
    for row in rows:
        entry = next(entry for entry in manifests[row['manifest']] if entry['file'] == row['file'])
        path = Path('test/corpus/files', row['file'])
        original = path.read_bytes()
        assert len(original) == entry['size'] and hashlib.sha256(original).hexdigest() == entry['sha256']
        native = (args.output / row['native']).read_bytes()
        assert native in (native_programs(path) if original.startswith(b'%PDF-') else [inkai.extract(str(path))])
        totals.update(verify(native, row))
        print(row['file'], 'passed', flush=True)
    report = dict(oracleRevision=REVISION, sources=len(rows), counts=dict(totals))
    (args.output / 'independent-report.json').write_text(json.dumps(report, indent=2) + '\n')
    print(report)


if __name__ == '__main__':
    main()
