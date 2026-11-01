#!/usr/bin/env python3
"""Verify source-owned resource artwork and references in complete CC programs."""

import argparse
from collections import Counter
import hashlib
import importlib
import json
from pathlib import Path
import re
import subprocess
import sys
from types import SimpleNamespace

from corpus_support import REVISION, native_programs
from verify_live_shapes import walk_body
from verify_native_artboard_text import normalized
from verify_native_group_lifecycle import command, descendant_paths, inventory as group_inventory
from verify_native_path_topology import bind, inventory
from verify_native_structure import native_values, parsed, version_ranges

PRODUCERS = ('simple_shapes.ai', 'simple_shapes_cc.ai', 'stroke_styles.ai', 'fill_stroke_test_cc.ai', 'styles.ai', 'text_transforms.ai', 'opacity.ai')
WRAPPERS = {'pattern': b'%AI3_BeginPattern:', 'symbol': b'%AI14_BeginSymbol', 'brush': b'%AI8_BeginBrushPattern'}


def direct_records(items):
    """Flatten the reader's version lists while keeping record fields nested."""
    for item in walk_body(items):
        if isinstance(item, list):
            yield from direct_records(item)
        elif isinstance(item, dict):
            yield item


def metadata(data, spans, items, start, end):
    """Bind complete records, including older branches discarded by the reader."""
    older = []
    for block in version_ranges(data):
        if start <= block['start'] < block['end'] <= end and block['older'] is not None:
            first, last = block['older']
            selected = [span for span in spans if first <= span[0] < span[1] <= last]
            records = list(direct_records(parsed(data[first:last])))
            assert len(selected) == len(records)
            for span, record in zip(selected, records, strict=True):
                decoded, = parsed(data[slice(*span)])
                assert normalized(decoded) == normalized(record)
                older.append(span)
    current = [span for span in spans if span not in older]
    records = list(direct_records(items))
    assert len(records) == len(current)
    for span, record in zip(current, records, strict=True):
        decoded, = parsed(data[slice(*span)])
        assert normalized(decoded) == normalized(record)


def resource(data, report, section, declarations):
    """Compare complete geometry, metadata, sample spans and resolved references."""
    first = section.children[0]
    assert first.command == 'A' and first.token_is_string[0]
    assert bytes(report['name']) == first.tokens[0]
    if report['kind'] == 'pattern':
        assert section.arguments == [first.tokens[0]]
        assert report['bounds'] == list(map(float, first.tokens[1:5]))
    else:
        assert report['bounds'] is None
    wrapped, = parsed(data[slice(*report['span'])])
    assert normalized(wrapped) == normalized(section)
    local = SimpleNamespace(trailer=section.children)
    paths = inventory(local)
    _, groups, group_paths = group_inventory(local)
    assert len(report['paths']) == len(paths) and len(report['groups']) == len(groups)
    for reported, path in zip(report['paths'], paths, strict=True):
        bind(data, reported, path)
    for reported, group in zip(report['groups'], groups, strict=True):
        assert reported['private'] == group['private']
        # A private group can start after scalar commands on the same %_ line.
        prefix = b'%_' if reported['private'] else b''
        assert [command(item) for item in walk_body(parsed(prefix + data[slice(*reported['span'])]))] == group['commands']
        assert reported['paths'] == [next(index for index, candidate in enumerate(group_paths) if candidate is path) for path in descendant_paths(group)]
    metadata(data, report['metadata'], section.children, *report['span'])
    values = list(native_values(section.children))
    uses = [item for item in values if getattr(item, 'command', None) == 'Bg' or getattr(item, 'command', None) == 'XW' and item.tokens[0] in (b'0', b'1') and item.tokens[1]]
    assert Counter(('gradient' if item.command == 'Bg' else 'knownStyle', item.tokens[1]) for item in uses) == Counter((item['kind'], bytes(item['name'])) for item in report['uses'])
    assert len({tuple(item['span']) for item in report['uses']}) == len(uses)
    for use in report['uses']:
        decoded, = parsed(data[slice(*use['span'])])
        assert (decoded.command, decoded.tokens[1]) == ('Bg' if use['kind'] == 'gradient' else 'XW', bytes(use['name']))
        matches = declarations[use['kind']].count(bytes(use['name']))
        assert use['resolution'] == ('resolved' if matches == 1 else 'ambiguous' if matches else 'missing')
        assert report['body'][0] <= use['span'][0] < use['span'][1] <= report['body'][1]
    images = [item for item in values if getattr(item, 'command', None) == 'XI']
    assert len(images) == len(report['rasters'])
    for image, reported in zip(images, report['rasters'], strict=True):
        assert (reported['width'], reported['height'], reported['components']) == (image.h, image.w, image.image_type)
        samples = data[slice(*reported['data'])]
        assert image.bits == 8 and len(samples) == image.h * image.w * (image.image_type + image.alpha_channel_count)
        span = data[slice(*reported['span'])]
        header = re.search(rb'%%BeginData: (\d+)\r?\nXI\r?\n', span)
        assert header is not None and reported['span'][0] + header.end() == reported['data'][0]
        assert int(header[1]) == image.data.length
        ending = data[reported['data'][1]:reported['span'][1]]
        assert re.fullmatch(rb'(?:\r\n?|\n)?(?:%_)?%%EndData(?:\r\n?|\n)(?:%_)?XH(?:\r\n?|\n)(?:%_)?%AI5_EndRaster', ending)
        decoded = image.data.raw + image.data.additional
        # The pinned reader may retain the next private-line prefix as samples.
        # Bound the actual plane independently from XI dimensions and framing.
        suffix = b'%_' if ending.startswith(b'%_%%EndData') and decoded.endswith(b'%_') else b''
        assert decoded == samples + suffix or samples[0] == 32 and decoded == samples[1:] + suffix
        assert reported['span'][0] < reported['data'][0] < reported['data'][1] < reported['span'][1]


def main():
    """Require pinned complete sources and every resource in all namespaces."""
    if not __debug__:
        raise RuntimeError('Run verification without assertion stripping')
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--inkai-source', required=True, type=Path)
    parser.add_argument('--output', type=Path, default=Path('test/corpus/output/artwork-resources'))
    args = parser.parse_args()
    assert subprocess.check_output(['git', '-C', str(args.inkai_source), 'rev-parse', 'HEAD'], text=True).strip() == REVISION
    assert not subprocess.check_output(['git', '-C', str(args.inkai_source), 'status', '--porcelain', '--untracked-files=no'], text=True).strip()
    sys.path.insert(0, str(args.inkai_source.resolve()))
    inkai = importlib.import_module('inkai')
    manifest = {
        entry['file']: entry
        for name in ('manifest.json', 'direct_shape_manifest.json')
        for entry in json.loads(Path('test/corpus', name).read_text())['files']
    }
    rows = json.loads((args.output / 'report.json').read_text())
    assert len(rows) == 8 and {row['source'] for row in rows} == {'synthetic', *PRODUCERS}
    totals = Counter()
    for row in rows:
        name = row['source']
        path = args.output / f'{name}.ps'
        data = path.read_bytes()
        if name == 'synthetic':
            assert hashlib.sha256(data).hexdigest() == 'ee3217ef14771802290ef31da370b496f42fb055a29b85636997baa267f74922'
        else:
            entry, fixture = manifest[name], Path('test/corpus/files', name)
            assert entry['license'] and entry['revision'] == REVISION and fixture.stat().st_size == entry['size']
            assert hashlib.sha256(fixture.read_bytes()).hexdigest() == entry['sha256']
            original = fixture.read_bytes()
            assert ([original] if original.startswith(b'%!PS-Adobe-') else native_programs(fixture)) == [data]
        document = inkai.parse(str(path))
        declarations = {
            'knownStyle': [value.Name.encode('latin1') for value in native_values(document.setup) if type(value).__name__ == 'KnownStyle'],
            'gradient': [section.arguments[0] for section in document.setup.all_subsections_of_type_recursive(b'%AI5_BeginGradient:')],
        }
        for kind, wrapper in WRAPPERS.items():
            sections = list(document.setup.all_subsections_of_type_recursive(wrapper))
            reports = [item for item in row['resources'] if item['kind'] == kind]
            assert len(sections) == len(reports)
            for report, section in zip(reports, sections, strict=True):
                resource(data, report, section, declarations)
                totals['resources'] += 1
                totals['paths'] += len(report['paths'])
                totals['groups'] += len(report['groups'])
                totals['rasters'] += len(report['rasters'])
                totals['styleUses'] += sum(item['kind'] == 'knownStyle' for item in report['uses'])
                totals['gradientUses'] += sum(item['kind'] == 'gradient' for item in report['uses'])
        assert len(row['resources']) == (2 if name == 'synthetic' else 21)
        print(name, 'passed', flush=True)
    (args.output / 'independent-report.json').write_text(json.dumps(dict(oracleRevision=REVISION, sources=[row['source'] for row in rows], **totals), indent=2) + '\n')


if __name__ == '__main__':
    main()
