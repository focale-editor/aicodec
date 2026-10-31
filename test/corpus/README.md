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
non-BMP text, a forced break and a paragraph. The oracle checks every run's UTF-16
ownership, cache removal and complete preservation outside the edited model/view. Edited
programs are deliberately not paired with the original PDF appearance.
Sixty additional outputs change character and paragraph features separately,
including twenty paragraph edits spanning the inserted forced breaks.
Their complete native trees, UTF-16 coverage, size/reference fields and fresh
inline style identifiers are checked independently; source resources and
unselected features must remain intact. These checks do not render new text.
Each of the 32 engine documents also receives two synthetic font identities:
PostScript and variable TrueType. The oracle checks all 64 resource additions,
their fresh ASCII UUIDs, versions, signed axis coordinates and display-list
updates, while requiring existing resources and stories to remain unchanged.
These metadata fixtures do not install fonts or claim glyph-rendering acceptance.
Seventeen point/area stories also receive reauthored source-position layouts.
The oracle compares frame/line/segment origins, character coverage, bounds,
selection metrics and fourteen automatic hyphens, while requiring other model
and resource data to remain unchanged. Three path-text compositions must reject
missing per-glyph geometry. This validates position records, not a glyph renderer.
Twenty-six frame translations cover point, area, path and linked text, including
existing rotations, reflections and shears. The independent reader checks all
thirteen confinement paths, frame matrix offsets and exact preservation of other
model/layout data. A second output moves only the first linked frame in
`text_transforms.ai`; exactly one confinement path must change. Unrelated body
operators and metadata remain intact. These checks do not render moved text.
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

The gradient-resource check reads all 37 fixtures and compares 378 definitions,
1,103 native color stops, fallback records and 725 printing intervals with the
same pinned independent reader. It replaces the first resource in each of the
23 gradient-bearing files, including opacity and three stops with two new sampled
intervals. Seven additional color-layout writes cover named and custom inks.
Unrelated definitions and drawing commands must remain unchanged; linear
printing matrices follow the edited stop intervals. The independent check also
covers 139 rewritten caches across the first-resource edits, seven color variants
and four real pattern variants with added/removed intervals. Two Inkscape
render comparisons cover 15 linear and nine radial CC instances against the
original SVG with only its expected stops replaced; both differences are zero.
These renders use midpoint 50 and do not validate print-engine interpolation,
color management, Adobe reopening or synchronized PDF appearances.

```sh
dart run tool/check_native_gradients.dart
python3 tool/verify_native_gradients.py --inkai-source /tmp/extension-ai
```

Generated programs, samples, SVG/PNG comparisons and `oracle-report.json` remain
under the ignored `output/gradients` directory.

The native PDF bridge has a separate required eight-file check. Six PDF-backed
fixtures rebuild their compatibility pages, translate their shapes, and save
matching native data. Two native-only fixtures generate standalone PDFs. The
independent checker compares original/shifted PDFs through Poppler and recovers
every saved native owner with pypdf and Python zlib/Zstandard. For native-only
fixtures, the pinned reader independently parses the printable stream and
converts it through SVG/Inkscape to PDF; private authoring geometry and its
known-style markers are excluded to retain the actual expanded printing paths.
All eighteen comparisons require unchanged flat pixels and bounded differences
around edges. Nine synthetic pixel probes also cover fill/stroke object opacity,
a Multiply group, clip restoration, hidden and nonprinting layers.
The CC linear/radial fixtures additionally change their shared resource to
three RGB stops with opacity. The independent reference replaces only the
original PDF shading functions and adds matching gray opacity masks. Saved
native bytes are decoded separately. Fifteen linear instances match exactly;
the nine radial instances have small differences at rounded outline boundaries.
Two nonlinear swatches from `circle.ai` compare generated PDF functions against
independently decoded printing ramps, covering midpoints on both sides of 50%.

```sh
dart run tool/check_native_pdf.dart
python3 tool/verify_native_pdf.py --inkai-source /tmp/extension-ai
```

These commands need Poppler (`pdftoppm`) and the oracle dependencies above.
The PDFs, native programs, images and `independent-report.json` remain under
the ignored `output/native-pdf` directory. This is printing-path validation;
text, gradients along/across strokes, newer gradient methods, effect rendering and
Adobe reopening remain outside it.

`pdf_manifest.json` pins three additional complete CC drawings for compound
gradient and appearance-state validation. The two random linear/radial drawings
are fully rebuilt and saved, then receive global color/opacity edits to their six
painted gradient resources. `styles.ai` is also rebuilt, including its unexpanded
`1 Bb` gradient stroke, then receives the same edit to its two painted resources.
The reference changes only the original PDF shading functions and opacity masks,
retaining the original stroke pattern and geometry. Six 1,920 × 1,080 comparisons
require unchanged flat pixels and matching gradient fields away from edges; maximum mean channel
difference is below 0.0004/255. Native data from all six saves is decoded and
checked separately, including stops and printing-matrix coverage through the
pinned reader. Eight additional pixel probes check nonzero/even-odd holes, grouped
contours, object/stop opacity, solid strokes and nonpainting gradient notes.
This separate manifest retains the scope and counts of the original corpus.

```sh
python3 tool/fetch_corpus.py --manifest pdf_manifest.json
dart run tool/check_native_pdf_compounds.dart
python3 tool/verify_native_pdf_compounds.py --inkai-source /tmp/extension-ai
```

The reports, native programs, PDFs and inspected PNGs remain under the ignored
`output/native-pdf-compounds` directory. These checks use the original PDF
compatibility pages, not a live Adobe Illustrator installation.

Additional generated probes validate open and closed gradient strokes, dashes,
round/butt caps, curves, linear/radial fields and object/group/stop opacity.
Eighteen pixel assertions and two exact whole-page comparisons check nonzero
native coordinates, two different PDF MediaBox origins and artboard cropping.
The saved native program is recovered independently. These outputs and the
report remain under the ignored `output/native-pdf-strokes` directory.

```sh
dart run tool/check_native_pdf_strokes.dart
python3 tool/verify_native_pdf_strokes.py
```

Native raster verification uses five existing core fixtures: `raster_ai8.ai`,
`raster_v2020.ai`, `empty_cs.ai`, `empty_cs2.ai` and `simple_shapes_cc.ai`.
The independent reader checks 24 images, 20 alpha planes and two private image
records byte for byte. The two visible images are rebuilt and translated; all
four Poppler comparisons have zero pixel differences. References use the original
Adobe PDF for the first file and standard PostScript `colorimage`/Ghostscript
rendering of independently read CMYK samples for the second. The latter does not
execute the Illustrator program, whose printing prolog is absent. Two saved native
programs are independently recovered. Seven probes check alpha, row orientation,
object opacity and stencil polarity against the retained Adobe prolog.
PDF/PNG/binary outputs stay in ignored `output/native-rasters`.

`raster_manifest.json` separately pins two UTF-8-transcoded, damaged raster files.
They must reject at the computed binary boundary, without scanning for a later
end marker or interpreting image bytes as commands. The optional check requires
both these rejection cases and the five accepted core fixtures.
Their preserved containers must also report an incomplete DSC inspection at the
damaged raster declaration. Accepted PostScript files in the core corpus require
complete inspection, independently of exact source-byte preservation.

```sh
python3 tool/fetch_corpus.py --manifest raster_manifest.json
dart run tool/check_native_rasters.dart
python3 tool/verify_native_rasters.py --inkai-source /tmp/extension-ai
```

Pixel replacement uses the same 24 images, replacing colors, alpha and resolution
in three separate variants. The pinned reader checks 72 edited plane sets,
geometry and UUID policies. Six zero-difference PDF comparisons replace only image streams in
the independently generated references above, retaining their page operators;
three native programs are recovered from the saved PDF envelopes. Run the raster
checks above first to generate these references. Outputs stay in ignored
`output/native-raster-edits`. This does not qualify Adobe reopening or arbitrary
image effects.

```sh
dart run tool/check_native_raster_edits.dart
python3 tool/verify_native_raster_edits.py --inkai-source /tmp/extension-ai
```

To check the existing downloads without network access or rewriting files:

```sh
python3 tool/fetch_corpus.py --verify-only
```
