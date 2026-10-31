#!/usr/bin/env python3
"""Verify complete CC shape copies, source preservation and both SVG interpretations."""

import argparse
import hashlib
import importlib
import json
from pathlib import Path
import re
import subprocess
import sys

from lxml import etree

from corpus_support import REVISION, native_programs, printable_svg
from verify_live_shapes import walk_body
from verify_native_direct_shapes import normalized
from verify_native_capabilities import body_operators
from verify_native_path_lifecycle import patch
from verify_native_structure import parsed, version_ranges

SYNTHETIC = {
    'synthetic': '6f368c1aa74ad5a4efe5526cea465cb57418dc3ddc7302eb78f5894399fdbc05',
    'synthetic-identified': '49cf56659fd5aaa38292907d5c810c3f331cf6b783e44d9fe0aad41febd7034f',
    'synthetic-state': '399005c1c8f84ed6e4fcb45970738b9025d45f3a3b59f91ccd7f399e138b5698',
}


def body(items):
    """Flatten the reader's selected newer-branch lists without dropping owners."""
    for item in walk_body(items):
        if isinstance(item, list):
            yield from body(item)
        else:
            yield item


def requests():
    """Declare every expected operation independently of the generated report."""
    result = {}
    for name in ('simple_shapes.ai', 'simple_shapes_cc.ai'):
        result.update({(name, f'copy-{index}'): ([index], False) for index in range(1, 5)})
        result[name, 'batch'] = ([1, 2, 3, 4], False)
        result[name, 'reject-first'] = ([0], True)
    result['gradient_linear.ai', 'copy-0'] = ([0], False)
    result['gradient_linear.ai', 'batch'] = (list(range(15)), False)
    result['gradient_radial.ai', 'copy-1'] = ([1], False)
    result['gradient_radial.ai', 'batch'] = (list(range(1, 9)), False)
    result['gradient_radial.ai', 'reject-first'] = ([0], True)
    result['opacity.ai', 'reject-first'] = ([1], True)
    result['synthetic', 'first'] = ([0], False)
    result['synthetic', 'batch'] = ([0, 1], False)
    result['synthetic-identified', 'first'] = ([0], False)
    result['synthetic-state', 'first'] = ([0], False)
    return result


def bundles(document):
    """Bind complete pairs by independent XW, group and dictionary parsing."""
    items = list(body(document.trailer))
    result, groups, completed = [], [], {}
    marker = None
    for index, item in enumerate(items):
        operator = getattr(item, 'command', None)
        if operator in ('u', '*u', 'q'):
            groups.append(index)
        elif operator in ('U', '*U', 'Q'):
            first = groups.pop()
            completed[index] = first
        elif operator == 'XW' and int(item.tokens[0]) == 6:
            assert marker is None and item.tokens[1] == b''
            marker = index
        elif operator == 'XW' and int(item.tokens[0]) == 1:
            assert marker is not None
            last = max(position for position in completed if position < marker)
            first = completed[last]
            assert items[first].command == 'u' and not items[first].is_pseudo_comment
            metadata = items[last + 1]
            assert isinstance(metadata, dict) and metadata['_type'] == 'ArtDictionary'
            assert metadata['ai::LiveShape']['Recorded'] is False
            definitions = [record for record in items[marker + 1:index] if isinstance(record, dict) and record.get('ai::LiveShape', {}).get('Recorded', True) and 'ai::LiveShape' in record]
            assert len(definitions) == 1
            definition = definitions[0]
            handler = definition['ai::LiveShape']['ai::LiveShape::HandlerName']
            assert all(record['ai::LiveShape']['ai::LiveShape::HandlerName'] == handler for record in definitions)
            assert metadata['ai::LiveShape']['ai::LiveShape::HandlerName'] == handler
            paths = [entry for entry in items[marker + 1:index] if getattr(entry, 'command', None) == 'm']
            assert len(paths) == 1 and paths[0].is_pseudo_comment
            if first and getattr(items[first - 1], 'command', None) == 'Ae':
                first -= 1
            result.append(dict(items=items[first:index + 1], handler=handler, definition=definition, style=item.tokens[1].decode('latin1')))
            marker = None
    assert not groups and marker is None
    return result


def inventory(inkai, path, spans):
    """Bind each reported whole-object span to independently parsed source owners."""
    data = path.read_bytes()
    document = inkai.parse(str(path))
    expected = bundles(document)
    versions = version_ranges(data)
    assert len(expected) == len(spans)
    for bundle, span in zip(expected, spans):
        assert bundle['handler'] == span['handler'] and bundle['style'] == span['style']
        assert normalized(body(parsed(data[span['start']:span['end']]))) == normalized(bundle['items'])
        dictionary = parsed(data[slice(*span['dictionary'])])
        assert len(dictionary) == 1 and dictionary[0]['ai::LiveShape']['ai::LiveShape::HandlerName'] == span['handler']
        assert dictionary[0] == bundle['definition']
        blocks = [block for block in versions if span['start'] <= block['start'] < block['end'] <= span['end']]
        assert len(blocks) == len(span['alternatives'])
        for block, alternate in zip(blocks, span['alternatives']):
            assert block['older'][0] <= alternate[0] < alternate[1] <= block['older'][1]
            assert block['newer'][0] <= span['dictionary'][0] < span['dictionary'][1] <= block['newer'][1]
            assert parsed(data[slice(*block['newer'])]) == dictionary
            old = parsed(data[slice(*alternate)])
            assert len(old) == 1 and old[0]['_type'] == 'ArtDictionary'
            assert parsed(data[slice(*block['older'])]) == old
        private = parsed(b'%_' + data[slice(*span['path'])])
        assert private and all(item.is_pseudo_comment for item in private)
        assert private[0].command == 'm' and private[-1].command in ('n', 'N')
        printing = parsed(data[slice(*span['printing'])])
        assert printing[0].command == 'u' and printing[-1].command == 'U'
        assert all(not item.is_pseudo_comment for item in printing)
    return document


def copy_bytes(before, span, identities):
    """Require exact copied bytes apart from independently located XML ID strings."""
    edits = []
    for identity in identities:
        first, last = identity['owner']
        if span['start'] <= first < last <= span['end']:
            dictionary = parsed(before[first:last])
            assert len(dictionary) == 1 and dictionary[0]['AI10_ArtUID'] in (b'author', b'older', 'author', 'older')
            matches = list(re.finditer(rb'/XMLUID\s*:\s*(\([^)]*\))\s*;', before[first:last]))
            assert len(matches) == 1
            value = matches[0]
            encoded = b'(' + b''.join(f'\\{byte:03o}'.encode() for byte in identity['bytes']) + b')'
            edits.append((first + value.start(1) - span['start'], first + value.end(1) - span['start'], encoded))
    return patch(before[span['start']:span['end']], edits)


def assignment(command):
    """Compare parsed dash arrays independently of producer whitespace choices."""
    if command.command == 'd':
        return ('d', tuple(command.dashes), command.phase)
    return command.command, tuple(command.tokens)


def source_flags(document, *, private):
    """Track native owner flags ignored by the independent SVG renderer."""
    result, state = [], {}
    for item in body(document.trailer):
        if not hasattr(item, 'command') or item.is_pseudo_comment and not private:
            continue
        if item.command in ('A', 'Xw', 'Ap', 'D'):
            state[item.command] = tuple(item.tokens)
        elif item.command == 'm':
            result.append((item.is_pseudo_comment, tuple(item.tokens), dict(state)))
    return result


def artwork(root):
    """Select the observed single-layer or root artwork without including definitions."""
    children = [item for item in root if etree.QName(item).namespace == 'http://www.w3.org/2000/svg' and etree.QName(item).localname != 'defs']
    if len(children) == 1 and etree.QName(children[0]).localname == 'g' and children[0].get('{http://www.inkscape.org/namespaces/inkscape}groupmode') == 'layer':
        return list(children[0])
    return children


def signature(node, root, seen=()):
    """Compare full geometry/styles and resolved resources, excluding generated SVG IDs."""
    def resource(identifier):
        assert identifier not in seen
        targets = root.xpath('//*[@id=$id]', id=identifier)
        assert len(targets) == 1
        return repr(signature(targets[0], root, (*seen, identifier)))

    attributes = []
    for key, value in sorted(node.attrib.items()):
        if key == 'id':
            continue
        value = re.sub(r'url\(#([^)]*)\)', lambda match: resource(match[1]), value)
        if etree.QName(key).localname in ('href', 'path-effect') and value.startswith('#'):
            value = ';'.join(resource(identifier[1:]) for identifier in value.split(';'))
        attributes.append((key, value))
    return node.tag, attributes, [signature(child, root, seen) for child in node]


def views(inkai, source, target, row):
    """Compare both real-file views and printable synthetic versioned pairs."""
    # The pinned SVG dispatcher ignores lists returned for version alternatives.
    # Inventory and exact byte checks above verify both synthetic metadata owners;
    # its SVG output cannot independently verify their authoritative geometry.
    modes = ('printing',) if row['source'] in SYNTHETIC else ('native', 'printing')
    for mode in modes:
        before = etree.fromstring(inkai.to_svg(str(source)) if mode == 'native' else etree.tostring(printable_svg(inkai, source)))
        after = etree.fromstring(inkai.to_svg(str(target)) if mode == 'native' else etree.tostring(printable_svg(inkai, target)))
        original = [signature(item, before) for item in artwork(before)]
        changed = [signature(item, after) for item in artwork(after)]
        extra = int(row['source'].startswith('simple_shapes'))
        assert len(original) == len(row['before']) + extra, (row['source'], mode, len(original))
        expected = [value for index, value in enumerate(original) for _ in range(2 if index in row['selected'] else 1)]
        assert expected == changed, (row['result'], mode, 'Geometry, style, resources or unselected appearance changed')


def verify(inkai, source, target, row):
    """Check whole pairs, exact insertions, source-backed prefixes and native flags."""
    before, after = source.read_bytes(), target.read_bytes()
    original = inventory(inkai, source, row['before'])
    changed = inventory(inkai, target, row['after'])
    literals = [*body_operators(original.trailer), *(command for style in original.setup.art_styles.values() for command in body_operators(style))]
    assert len(row['after']) == len(row['before']) + len(row['selected'])
    edits, position = [], 0
    for index, span in enumerate(row['before']):
        retained = row['after'][position]
        assert before[span['start']:span['end']] == after[retained['start']:retained['end']]
        position += 1
        if index not in row['selected']:
            continue
        copied = row['after'][position]
        assert after[copied['start']:copied['end']] == copy_bytes(before, span, row['identifiers'])
        prefix = parsed(after[retained['end']:copied['start']])
        for command in prefix:
            assert hasattr(command, 'command') and command.command in ('A', 'Xw', 'Ap', 'D', 'XR', 'O', 'R', 'g', 'G', 'k', 'K', 'Xa', 'XA', 'J', 'j', 'w', 'M', 'd', 'Xy')
            # Replayed values are existing source literals, not invented defaults.
            assert any(assignment(command) == assignment(candidate) and (command.is_pseudo_comment or not candidate.is_pseudo_comment) for candidate in literals)
        assert after[copied['end']:copied['end'] + 1] == b'\n'
        edits.append((span['end'], span['end'], after[retained['end']:copied['end'] + 1]))
        position += 1
    assert patch(before, edits) == after
    for private in (False, True):
        expected, first = [], 0
        old_flags = source_flags(original, private=private)
        for index, span in enumerate(row['before']):
            owned = parsed(before[span['start']:span['end']])
            count = sum(getattr(item, 'command', None) == 'm' and (private or not item.is_pseudo_comment) for item in owned)
            flags = old_flags[first:first + count]
            expected.extend(flags)
            if index in row['selected']:
                expected.extend(flags)
            first += count
        expected.extend(old_flags[first:])
        assert expected == source_flags(changed, private=private), (row['result'], private, 'Native owner flags changed')
    views(inkai, source, target, row)


def main():
    """Require pinned inputs, fixed requests and unchanged independent reader code."""
    if not __debug__:
        raise RuntimeError('Run verification without assertion stripping')
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--inkai-source', required=True, type=Path)
    parser.add_argument('--output', default=Path('test/corpus/output/shape-lifecycle'), type=Path)
    args = parser.parse_args()
    assert subprocess.check_output(['git', '-C', str(args.inkai_source), 'rev-parse', 'HEAD'], text=True).strip() == REVISION
    assert not subprocess.check_output(['git', '-C', str(args.inkai_source), 'status', '--porcelain', '--untracked-files=no'], text=True).strip()
    sys.path.insert(0, str(args.inkai_source.resolve()))
    inkai = importlib.import_module('inkai')
    manifest = {entry['file']: entry for entry in json.loads(Path('test/corpus/manifest.json').read_text())['files']}
    expected = requests()
    rows = json.loads((args.output / 'report.json').read_text())
    assert len(rows) == len(expected) == 22 and {(row['source'], row['variant']) for row in rows} == expected.keys()
    checked = []
    for row in rows:
        assert (row['selected'], row['rejected']) == expected[row['source'], row['variant']]
        assert row['original'] == row['source'] + '.original.ps' and row['result'] == row['source'] + '.' + row['variant'] + '.ps'
        source, target = args.output / row['original'], args.output / row['result']
        before = source.read_bytes()
        if row['source'] in SYNTHETIC:
            assert hashlib.sha256(before).hexdigest() == SYNTHETIC[row['source']]
        else:
            entry = manifest[row['source']]
            path = Path('test/corpus/files', row['source'])
            assert path.stat().st_size == entry['size'] and hashlib.sha256(path.read_bytes()).hexdigest() == entry['sha256']
            assert before in (native_programs(path) if path.read_bytes().startswith(b'%PDF-') else [path.read_bytes()])
        if row['source'] == 'synthetic-identified':
            assert row['identifiers'] == [dict(owner=row['before'][0]['dictionary'], bytes=list(b'copy_author')), dict(owner=row['before'][0]['alternatives'][0], bytes=list(b'copy_older'))]
        else:
            assert not row['identifiers']
        if row['rejected']:
            assert before == target.read_bytes() and row['before'] == row['after'] and 'unknown inherited printing D' in row['issue']
        else:
            assert row['issue'] is None
            verify(inkai, source, target, row)
        checked.append(row['result'])
        print(row['result'], 'passed', flush=True)
    (args.output / 'independent-report.json').write_text(json.dumps(dict(oracleRevision=REVISION, transactions=checked, nativeAndPrintingCopies=14, printingAndMetadataCopies=4, refusals=4), indent=2) + '\n')


if __name__ == '__main__':
    main()
