# AiKit external corpus

The manifest pins 37 internet fixtures with URL, revision, size, SHA-256,
license and expected outcome. 0 are deliberate rejection cases. Run the fetcher and checker from this package:

```sh
python3 tool/fetch_corpus.py
dart run tool/check_corpus.dart
dart run tool/check_native_corpus.dart
python3 tool/verify_native.py
```

`files/` and `output/` are ignored and excluded from publication. The checker
fails on missing files and unexpected outcomes; it does not silently skip
external coverage. Ordinary `dart test` stays offline and independent of this
corpus. See the [technical reference](../../docs/AI.md).

Decoded documents are written under `output/` for independent validation.
Source works are not redistributed. Consult each manifest license before
copying third-party artwork elsewhere.

`check_native_corpus.dart` requires extraction and structural parsing for all
37 fixtures, verifies the nested layer fixture's names and flags, renames a
layer and artboard where present, decodes native hierarchical and binary records,
and checks native data after PDF rewriting. Eight fixtures also receive separate
native translations of all supported live shapes; their `.translated.ps` outputs
are not packaged with an unchanged PDF appearance. Reports include unhandled operators and private
extension flags rather than interpreting a successful decode as full editability.

`verify_native.py` requires Python and the `zstd` reference executable. It compares
both original and rewritten envelopes with their expected native program bytes,
using Python zlib and reference Zstandard decoding. Missing outputs fail the
check. Downloaded artwork and generated outputs remain excluded from publication.

`verify_live_shapes.py` checks the translated outlines, printable expansions,
canvas centers and styles through the independent Inkscape extension-ai reader,
then compares rendered SVGs with explicitly shifted originals. It requires
Inkscape, Pillow, lxml, inkex, pypdf 3.x and zstandard 0.25.0.
Keep the oracle checkout outside AiKit; no oracle implementation is bundled:

```sh
git clone https://gitlab.com/inkscape/extras/extension-ai.git /tmp/extension-ai
git -C /tmp/extension-ai checkout 1a5f42a0b0407fc869e032420570682048810108
python3 tool/verify_live_shapes.py --inkai-source /tmp/extension-ai
```

Use a virtual environment for missing Python dependencies. The checker refuses
a different revision or modified tracked oracle source. Its report and comparison
images go under `output/native/live-shape-oracle/`. The current eight comparisons
cover 39 live shapes, 112 paths and 148 center fields, including linear/radial
gradient matrices and independent SVG endpoint/focus checks. Runtime versions
are recorded in the report. Inkscape is the required renderer because librsvg
2.62.4 differed for equivalent radial SVGs with boundary focal points.
Adobe Illustrator reopening
and full style/effect fidelity are separate acceptance checks.

The native checker also decodes 32 ATE payloads and renames their first character
style when present. The expanded fixtures include point text across CS–CC and
ten stories of transformed, linked-area and path text in `text_transforms.ai`.
Each of the twenty stories also receives a separate content edit, introducing
non-BMP text and a paragraph. The oracle checks every run's UTF-16 ownership,
cache removal and complete preservation outside the edited model/view. Edited
programs are deliberately not paired with the original PDF appearance.
Forty additional outputs change character and paragraph features separately.
Their complete native trees, UTF-16 coverage, size/reference fields and fresh
inline style identifiers are checked independently; source resources and
unselected features must remain intact. These checks do not render new text.
Verify these outputs with the same pinned external checkout:

```sh
python3 tool/verify_native_text.py --reference /tmp/extension-ai
```

This check independently decodes both the rewritten native ASCII85 container and
the complete ATE tree, requiring exact semantic equality except for the selected
style name. It retains glyph/frame layout and verifies the area's text and run
lengths. It compares the `.text-model.json` projections with independently parsed
fonts, frames and layout nodes. The transformed-text fixture requires ten
stories, sixteen frames, twenty-four style ranges, 387 layout nodes and 4,003
cached glyph IDs, including four stories without an explicit character-run
table. Its report is `output/native/native-text-report.json`. This does not
validate changed text shaping, text appearance or reopening in Illustrator.

To check the existing downloads without network access or rewriting files:

```sh
python3 tool/fetch_corpus.py --verify-only
```
