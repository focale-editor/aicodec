#!/usr/bin/env python3
"""Verify private child lifecycle through independent native and PDF readers."""

from pypdf import PdfReader

from corpus_support import native_programs
from verify_focale_group_paints import ghostscript_renders
from verify_live_shapes import walk_body
from verify_native_artboard_brush_descriptors import descriptor_state
from verify_native_documents import renders
from verify_native_group_lifecycle import inventory
from verify_native_structure import native_values


def named_children(document):
    """Bind postfix labels to actual parsed group/path nesting and sibling order."""
    roots, stack, last, named = [], [], None, {}
    for item in walk_body(document.trailer):
        operator = getattr(item, 'command', None)
        if operator in ('u', 'q', '*u', 'Lb'):
            node = {'children': []}
            (stack[-1]['children'] if stack else roots).append(node)
            stack.append(node)
        elif operator in ('U', 'Q', '*U', 'LB'):
            last = stack.pop()
        elif operator in ('n', 'N', 'f', 'F', 's', 'S', 'b', 'B'):
            last = {'children': []}
            (stack[-1]['children'] if stack else roots).append(last)
        elif isinstance(item, dict) and 'AIArtName' in item:
            assert last is not None
            last['name'] = item['AIArtName']
            named[item['AIArtName']] = last
    assert not stack
    return {name: [child.get('name') for child in node['children']] for name, node in named.items()}


def verify_group_topology(inkai, output):
    """Check sequential private creation/removal/movement and matching host views."""
    previous = None
    for base in ('group-topology-created', 'group-topology-revised', 'group-topology-empty'):
        for reopened in (False, True):
            stem = base + ('-reopened' if reopened else '')
            path, source = output / f'{stem}.ai', output / f'{stem}.ps'
            assert native_programs(path) == [source.read_bytes()], stem
            document = inkai.parse(str(source))
            owners = [value for value in native_values(document.trailer)
                      if isinstance(value, dict) and 'AI10_ArtUID' in value]
            identities = [value['AI10_ArtUID'] for value in owners]
            assert len(set(identities)) == len(identities), stem
            labels = {value['AIArtName']: value for value in owners if 'AIArtName' in value}
            empty = base.endswith('empty')
            expected = {'Topology'} if empty else {'Topology', 'Inner', 'Brush', 'Added group'}
            if not empty:
                expected |= {'Pattern', 'Added plain', 'Added pattern'} if base.endswith('created') else {'Renamed pattern', 'Copied pattern'}
            assert expected <= labels.keys() and 'Neighbor' not in labels, stem
            children = named_children(document)
            assert children['Topology'] == ([] if empty else ['Added group', 'Inner'] if base.endswith('created') else ['Inner', 'Added group', 'Copied pattern']), stem
            if not empty:
                assert children['Added group'] == (['Added plain', 'Added pattern', 'Pattern'] if base.endswith('created') else ['Renamed pattern']), stem
                assert children['Inner'] == ['Brush'], stem
            if base.endswith('created'):
                previous = labels
            elif not empty:
                for label in ('Topology', 'Inner', 'Brush', 'Added group'):
                    assert labels[label]['AI10_ArtUID'] == previous[label]['AI10_ArtUID'], (stem, label)
                assert labels['Renamed pattern']['AI10_ArtUID'] == previous['Added pattern']['AI10_ArtUID'], stem
                assert 'Pattern' not in labels and 'Added plain' not in labels, stem
            assert sum('AI9_Mask' in value for value in owners) == (0 if empty else 2), stem
            _, groups, paths = inventory(document)
            private = [group for group in groups if group['private']]
            assert len(private) == (1 if empty else 3), stem
            expected_paths = 0 if empty else 4 if base.endswith('created') else 3
            assert len([path for path in paths if path['private']]) == expected_paths, stem
            applications = [item for item in walk_body(document.trailer)
                            if getattr(item, 'command', None) == 'XW' and item.tokens[0] in (b'0', b'1')]
            assert len(applications) == (1 if empty else 6), stem
            styles = [value for value in native_values(document.setup) if type(value).__name__ == 'KnownStyle']
            names = [style.Name.encode('latin1') for style in styles]
            assert len(names) == len(set(names)) and all(use.tokens[1] in names for use in applications), stem
            assert descriptor_state(document)['references'], stem
            tiles = list(document.setup.all_subsections_of_type_recursive(b'%AI3_BeginPattern:'))
            assert len(tiles) == 1, stem
            paints = [value for value in native_values(styles) if getattr(value, 'command', None) in ('p', 'P')]
            assert paints and all(paint.tokens[0] == tiles[0].children[0].tokens[0] for paint in paints), stem
            reference = output / f'{stem}-reference.pdf'
            saved, host = PdfReader(path, strict=True), PdfReader(reference, strict=True)
            assert len(saved.pages) == len(host.pages) == 1, stem
            assert saved.pages[0].mediabox == host.pages[0].mediabox, stem
            if not reopened:
                assert renders(path) == renders(reference), stem
            assert renders(path, dpi=144) == renders(reference, dpi=144), stem
            assert ghostscript_renders(path) == ghostscript_renders(reference), stem
            print(stem, 'passed', flush=True)
    print('Verified six private-topology comparisons with retained identities, nested masks, ordered and empty groups, and exact original/reopened PDF pixels.')
