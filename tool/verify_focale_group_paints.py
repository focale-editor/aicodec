#!/usr/bin/env python3
"""Verify grouped native paint ownership and complete original/reopened PDF views.

Independent parsing checks references, child contours and mask carriers. Native
Illustrator pattern/brush execution and editability still need Adobe acceptance.
"""

from pathlib import Path
import subprocess
import tempfile

from pypdf import PdfReader

from corpus_support import native_programs
from verify_live_shapes import walk_body
from verify_native_artboard_brush_descriptors import descriptor_state
from verify_native_documents import renders
from verify_native_group_lifecycle import inventory
from verify_native_structure import native_values


def ghostscript_renders(path):
    """Compare original and reopened forms with a second independent PDF engine."""
    with tempfile.TemporaryDirectory() as directory:
        prefix = Path(directory) / 'page-%d.ppm'
        subprocess.run([
            'gs', '-dSAFER', '-dBATCH', '-dNOPAUSE', '-sDEVICE=ppmraw', '-r72',
            f'-sOutputFile={prefix}', str(path),
        ], check=True, capture_output=True)
        return [page.read_bytes() for page in sorted(Path(directory).glob('*.ppm'))]


def verify_group_paints(inkai, output):
    """Check typed creation, selected revisions and first styling of retained children."""
    original_identities = None
    for base in ('group-paints-created', 'group-paints-edited-1', 'group-paints-edited-2', 'group-paints-attached'):
        for reopened in (False, True):
            stem = base + ('-reopened' if reopened else '')
            path = output / f'{stem}.ai'
            native = (output / f'{stem}.ps').read_bytes()
            assert native_programs(path) == [native], stem
            document = inkai.parse(str(output / f'{stem}.ps'))
            values = list(native_values(document.trailer))
            owners = [value for value in values if isinstance(value, dict) and 'AI10_ArtUID' in value]
            identities = [value['AI10_ArtUID'] for value in owners]
            assert len(set(identities)) == len(identities), stem
            if base == 'group-paints-created':
                original_identities = identities
            elif 'edited' in base:
                assert identities == original_identities, stem
            labels = {value.get('AIArtName'): value for value in owners if 'AIArtName' in value}
            assert {'Paint group', 'Inner group', 'Pattern child', 'Brush child', 'Inner neighbor'} <= labels.keys(), stem
            assert type(labels['Pattern child']['AI9_Mask']).__name__ == 'Mask', stem
            assert sum('AI9_Mask' in value for value in owners) == 1, stem
            _, _, paths = inventory(document)
            private = [value for value in paths if value['private']]
            assert sum(value['paint'] in ('n', 'N') for value in private) == 2, stem
            applications = [item for item in walk_body(document.trailer)
                            if getattr(item, 'command', None) == 'XW' and item.tokens[0] in (b'0', b'1')]
            assert len(applications) == 4, stem
            assert sum(getattr(item, 'is_pseudo_comment', False) for item in applications) == 3, stem
            resources = list(document.setup.all_subsections_of_type_recursive(b'%AI3_BeginPattern:'))
            expected_count = int(base[-1]) + 1 if 'edited' in base else 1
            assert len(resources) == expected_count, stem
            assert descriptor_state(document)['references'], stem
            styles = [value for value in native_values(document.setup) if type(value).__name__ == 'KnownStyle']
            paints = [value for value in native_values(styles) if getattr(value, 'command', None) in ('p', 'P')]
            names = {resource.children[0].tokens[0] for resource in resources}
            assert paints and all(paint.tokens[0] in names for paint in paints), stem
            expected_roundness = 25 if 'edited' not in base else 40 if base.endswith('1') else 60
            nibs = [value for value in native_values(styles) if type(value).__name__ == 'BasicFilter' and value.Filter[0] == 'Adobe Calligraphic Brush Tool']
            assert float(nibs[-1].Dict['Roundness']) == expected_roundness, stem
            reference = output / f'{stem}-reference.pdf'
            saved, expected = PdfReader(path, strict=True), PdfReader(reference, strict=True)
            assert len(saved.pages) == len(expected.pages) == 1, stem
            assert saved.pages[0].mediabox == expected.pages[0].mediabox, stem
            # At 72 dpi Poppler samples subpixel tiles differently when their
            # coordinate scale moves from the containing form into the pattern
            # matrix. These equivalent spaces agree exactly at 144 dpi and in
            # Ghostscript at 72 dpi. Keep both exact checks, without tolerance;
            # original same-revision exports also retain the 72 dpi comparison.
            if not reopened:
                assert renders(path) == renders(reference), stem
            assert renders(path, dpi=144) == renders(reference, dpi=144), stem
            assert ghostscript_renders(path) == ghostscript_renders(reference), stem
            print(stem, 'passed', flush=True)
    print('Verified eight grouped-paint comparisons with nested styles, masks, retained identities and exact original/reopened PDF pixels in Poppler at 144 dpi and Ghostscript at 72 dpi.')
