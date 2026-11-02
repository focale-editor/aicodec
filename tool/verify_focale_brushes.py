#!/usr/bin/env python3
"""Check fixed native calligraphy, complete containers and original/reopened PDF views.

The independent reader parses nib descriptors and styles. It does not execute
Illustrator's brush engine; native appearance/editability acceptance is separate.
"""

from pypdf import PdfReader

from corpus_support import native_programs
from verify_native_artboard_brush_descriptors import descriptor_state
from verify_native_brush_lifecycle import descriptors
from verify_native_documents import renders
from verify_native_structure import native_values


def verify_brushes(inkai, output):
    """Verify authored nibs, retained editable spines and repeated whole-file saves."""
    for base in ('brush-created', 'brush-edited-1', 'brush-edited-2'):
        for reopened in (False, True):
            stem = base + ('-reopened' if reopened else '')
            ai = output / f'{stem}.ai'
            data = (output / f'{stem}.ps').read_bytes()
            assert native_programs(ai) == [data]
            document = inkai.parse(str(output / f'{stem}.ps'))
            state = descriptor_state(document)
            assert state['references']
            definitions = descriptors(document)
            assert len(definitions) == (1 if base == 'brush-created' else int(base[-1]) + 1)
            for (plugin, _), payload in definitions.items():
                assert plugin == b'Adobe Calligraphic Brush Tool'
                values = list(map(float, payload.split()))
                assert len(values) == 11 and values[0:3] == [1, 1, 1]
                assert values[3] == values[4] and values[5] == values[6]
                assert values[7:] == [0, 0, 0, 0]
            filters = [value for value in native_values(document.setup) if type(value).__name__ == 'BasicFilter' and value.Filter[0] == 'Adobe Calligraphic Brush Tool']
            assert len(filters) == len(definitions)
            expected = (25, -30) if base == 'brush-created' else (40, 55) if base.endswith('1') else (65, -15)
            parameters = filters[-1].Dict
            assert float(parameters['Diameter']) == 1
            assert abs(float(parameters['Roundness']) - expected[0]) < 1e-10
            assert abs(float(parameters['Angle']) - expected[1]) < 1e-10
            saved = PdfReader(ai, strict=True)
            reference = output / f'{stem}-reference.pdf'
            expected_pdf = PdfReader(reference, strict=True)
            assert len(saved.pages) == len(expected_pdf.pages) == 1
            assert saved.pages[0].mediabox == expected_pdf.pages[0].mediabox
            assert renders(ai) == renders(reference)
            print(stem, 'passed', flush=True)
    print('Verified six brush comparisons across three complete saves and original/reopened host PDF views.')
