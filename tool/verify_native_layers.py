#!/usr/bin/env python3
"""Verify native layer headers and empty insertion with unchanged pinned inkai."""

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
from verify_native_group_lifecycle import replacement_regions
from verify_native_structure import parsed


def commands(items):
    """Retain exact decoded operators while traversing external DSC sections."""
    return [(item.command, tuple(item.tokens), item.is_pseudo_comment)
            for item in walk_body(items) if hasattr(item, 'command')]


def layers(document):
    """Derive source-order ownership from native Lb/LB instructions independently."""
    items = list(walk_body(document.trailer))
    result, stack = [], []
    for position, item in enumerate(items):
        operator = getattr(item, 'command', None)
        if operator == 'Lb':
            index = len(result)
            parent = stack[-1] if stack else None
            node = dict(parent=parent, children=[], first=position, attributes=list(map(float, item.tokens)))
            if parent is not None:
                result[parent]['children'].append(index)
            result.append(node)
            stack.append(index)
        elif operator == 'LB':
            assert stack and not item.tokens
            node = result[stack.pop()]
            node['last'] = position
    assert not stack
    for node in result:
        position = node['first'] + 1
        node.update(name=None, expanded=None, identifier=None, dictionary=None)
        if getattr(items[position], 'command', None) == 'Ln':
            node['name'] = list(items[position].tokens[0])
            position += 1
        if getattr(items[position], 'command', None) == 'AE':
            assert items[position].tokens in ([b'0'], [b'1'])
            node['expanded'] = items[position].tokens == [b'1']
            position += 1
        if isinstance(items[position], dict) and items[position].get('_type') == 'ArtDictionary':
            node['dictionary'] = items[position]
            node['identifier'] = items[position].get('AI10_ArtUID')
            position += 1
        node['body'] = items[position:node['last']]
        node['commands'] = commands(items[node['first']:node['last'] + 1])
    return result


def verified_inventory(inkai, path, reported):
    """Bind every reported layer span, header and parent to an independent parse."""
    from inkai.parser.streamreader import dec

    data = path.read_bytes()
    actual = layers(inkai.parse(str(path)))
    assert len(actual) == len(reported['layers'])
    assert reported['rootCount'] == sum(node['parent'] is None for node in actual)
    declared = re.findall(rb'^%{1,2}AI5_NumLayers:\s*(\d+)[ \t]*\r?$', data, re.MULTILINE)
    assert len(declared) <= 1
    assert reported['declaredRootCount'] == (int(declared[0]) if declared else None)
    if declared:
        assert int(declared[0]) == reported['rootCount']
        assert re.fullmatch(rb'%{1,2}AI5_NumLayers:\s*\d+[ \t]*', data[slice(*reported['rootCountSpan'])])
    else:
        assert reported['rootCountSpan'] is None
    views = re.findall(rb'^%{1,2}AI5_OpenViewLayers:[^\r\n]*', data, re.MULTILINE)
    assert len(views) <= 1
    assert len(reported['viewSpans']) == len(views)
    if views:
        assert data[slice(*reported['viewSpans'][0])] == views[0]
    for node, span in zip(actual, reported['layers']):
        for key in ('parent', 'children', 'attributes', 'name', 'expanded'):
            assert node[key] == span[key], (path, key)
        assert node['identifier'] == (dec(bytes(span['identifier'])) if span['identifier'] is not None else None)
        if span['nameSpan'] is not None:
            assert span['opening'][1] <= span['nameSpan'][0] < span['nameSpan'][1] <= span['bodyStart']
            naming = parsed(data[slice(*span['nameSpan'])] + b' Ln')
            assert len(naming) == 1 and naming[0].command == 'Ln' and list(naming[0].tokens[0]) == span['name']
        else:
            assert span['name'] is None
        if span['identifierSpan'] is not None:
            assert span['opening'][1] <= span['identifierSpan'][0] < span['identifierSpan'][1] <= span['bodyStart']
            identity = parsed(b'/ArtDictionary : /XMLUID : ' + data[slice(*span['identifierSpan'])] + b' ; (AI10_ArtUID) , ;')
            assert identity == [{'_type': 'ArtDictionary', 'AI10_ArtUID': node['identifier']}]
        else:
            assert node['identifier'] is None
        start, end = span['start'], span['end']
        opening, closing = span['opening'], span['closing']
        assert start <= opening[0] < opening[1] <= span['bodyStart'] <= closing[0] < closing[1] <= end
        assert commands(parsed(data[slice(*opening)])) == [node['commands'][0]]
        assert commands(parsed(data[slice(*closing)])) == [('LB', (), False)]
        assert commands(parsed(data[start:end])) == node['commands']
        assert data[start:opening[0]].strip() == (span['openingComment'] or '').encode()
        assert data[closing[1]:end].strip() == (span['closingComment'] or '').encode()
        if span['openingComment']:
            assert span['openingComment'] == '%AI5_BeginLayer'
            assert span['closingComment'] in ('%AI5_EndLayer', '%AI5_EndLayer--')
        else:
            assert span['closingComment'] is None
    return actual


def verify_insertion(before, after, original, changed, row, variant):
    """Check the new empty sibling and exact preservation of all original bytes."""
    selected = variant['selected']
    source = row['before']['layers'][selected]
    nodes = row['before']['layers']
    insertion = next((index for index, node in enumerate(nodes) if node['start'] >= source['end']), len(nodes))
    assert len(changed) == len(original) + 1
    added = changed[insertion]
    assert added['name'] == variant['name'] and added['parent'] == source['parent']
    assert added['attributes'] == source['attributes'] and not added['body'] and not added['children']
    assert added['expanded'] == (False if source['expanded'] is not None else None)
    assert added['identifier'] == (bytes(variant['identifier']).decode() if variant['identifier'] is not None else None)
    if added['identifier'] is not None:
        assert all(added['identifier'] != node['identifier'] for node in original)
    if original[selected]['dictionary'] is None:
        assert added['dictionary'] is None
    else:
        expected = dict(original[selected]['dictionary'])
        if added['identifier'] is not None:
            expected['AI10_ArtUID'] = added['identifier']
        assert added['dictionary'] == expected
    retained = changed[:insertion] + changed[insertion + 1:]
    for index, (old, new) in enumerate(zip(original, retained)):
        for key in ('attributes', 'name', 'expanded', 'identifier', 'dictionary'):
            assert old[key] == new[key]
        parent = old['parent']
        assert new['parent'] == (parent + (parent >= insertion) if parent is not None else None)
        children = [child + (child >= insertion) for child in old['children']]
        if index == source['parent']:
            children.append(insertion)
            children.sort()
        assert new['children'] == children
    count = row['before']['rootCount'] + (source['parent'] is None)
    assert variant['after']['rootCount'] == count and not variant['after']['viewSpans']
    edits = [(source['end'], source['end'], 'insert')]
    edits += [(*span, 'view') for span in row['before']['viewSpans']]
    if source['parent'] is None and row['before']['rootCountSpan'] is not None:
        edits.append((*row['before']['rootCountSpan'], 'count'))
    for kind, fragment in replacement_regions(before, after, edits):
        if kind == 'view':
            assert not fragment
        elif kind == 'count':
            previous = before[slice(*row['before']['rootCountSpan'])]
            assert fragment == previous.split(b':')[0] + b': ' + str(count).encode()
        else:
            assert kind == 'insert'
            assert commands(parsed(fragment)) == added['commands']
            assert [operator for operator, _, _ in added['commands']] == ['Lb', 'Ln'] + (['AE'] if added['expanded'] is not None else []) + ['LB']
            if source['openingComment']:
                assert fragment.strip().startswith(source['openingComment'].encode())
                assert fragment.strip().endswith(source['closingComment'].encode())
            else:
                assert b'%AI5_' not in fragment


def main():
    """Require the pinned corpus and external parser before checking every variant."""
    if not __debug__:
        raise RuntimeError('Run verification without assertion stripping')
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--inkai-source', required=True, type=Path)
    parser.add_argument('--output', default=Path('test/corpus/output/layers'), type=Path)
    args = parser.parse_args()
    assert subprocess.check_output(['git', '-C', str(args.inkai_source), 'rev-parse', 'HEAD'], text=True).strip() == REVISION
    assert not subprocess.check_output(['git', '-C', str(args.inkai_source), 'status', '--porcelain', '--untracked-files=no'], text=True).strip()
    sys.path.insert(0, str(args.inkai_source.resolve()))
    inkai = importlib.import_module('inkai')
    rows = json.loads((args.output / 'report.json').read_text())
    manifests = {name: json.loads(Path('test/corpus', name).read_text())['files'] for name in ('manifest.json', 'document_manifest.json')}
    assert len(rows) == 46
    assert {(row['manifest'], row['file'], row['sourceIndex']) for row in rows} == {
        (name, entry['file'], 0) for name, entries in manifests.items() for entry in entries}
    checked, skipped = [], []
    for row in rows:
        path = Path('test/corpus/files', row['file'])
        entry = next(entry for entry in manifests[row['manifest']] if entry['file'] == row['file'])
        data = path.read_bytes()
        assert len(data) == entry['size'] and hashlib.sha256(data).hexdigest() == entry['sha256']
        source = args.output / row['native']
        before = source.read_bytes()
        assert before == (native_programs(path) if data.startswith(b'%PDF-') else [inkai.extract(str(path))])[row['sourceIndex']]
        original = verified_inventory(inkai, source, row['before'])
        assert [variant['selected'] for variant in row['variants']] == list(range(len(original)))
        for variant in row['variants']:
            if 'result' not in variant:
                assert row['file'].startswith('inkscape_minimized_')
                assert original[variant['selected']]['dictionary'].keys() - {'_type', 'AI10_ArtUID'}
                skipped.append(dict(file=row['file'], reason=variant['unsupported']))
                continue
            target = args.output / variant['result']
            changed = verified_inventory(inkai, target, variant['after'])
            verify_insertion(before, target.read_bytes(), original, changed, row, variant)
            checked.append(variant['result'])
            print(variant['result'], 'passed', flush=True)
    assert sum(len(row['before']['layers']) for row in rows) == 50 and len(checked) == 40 and len(skipped) == 10
    report = dict(oracleRevision=REVISION, sources=len(rows), originalLayers=50, insertions=checked, unsupported=skipped)
    (args.output / 'independent-report.json').write_text(json.dumps(report, indent=2) + '\n')


if __name__ == '__main__':
    main()
