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

The separate `mesh_manifest.json` pins one public CC 21.1 educational example.
It has no identified redistribution license; artwork and generated outputs stay
ignored and unpublished. The required mesh check compares all 180 patches,
720 colored corners, eight additional anchors and eleven subdivision points
with an independent restricted-format Python reader. It checks complete field
tokens/spans, mixed gray/CMYK/NChannel declarations and exact native extraction.
This is structural inspection, not mesh rendering or editing qualification.

```sh
python3 tool/fetch_corpus.py --manifest mesh_manifest.json
dart run tool/check_native_meshes.dart
python3 tool/verify_native_meshes.py
```

The independent check uses pypdf 3.x and Python zlib. Its detailed projections
and report are under `output/meshes/`; a missing/changed fixture fails the check.

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

Linked placements use `placement_manifest.json`, pinning the intact
`image_linked.ai` from revision `41bac2967b0f2bd80bc14fce9c8c0dea01283536` as
`image_linked_original_cc.ai`. The later core-source revision damaged its binary
bytes by text transcoding; that damaged copy remains a separate rejection case.
The independent reader checks all 277,504 ARGB preview bytes, and Pillow confirms
their row order and channel conversion. Five setup images remain byte-identical.

Three incorporation variants use either the explicit preview or CMYK pixels
supplied from `raster_v2020.ai`, with and without placement translation. The latter
is host-supplied replacement content, not a recovered external JPEG. Ghostscript
evaluates the original placement operands with standard `colorimage`; three
complete-page Poppler comparisons have zero differences. A synthetic PDF carrier
tests synchronized native data and adds a fourth zero-difference comparison.
The source has no PDF compatibility page, and the independent parser does not
fully model its placement metadata; original header operands and DSC bounds
separately verify geometry. Adobe reopening remains unqualified. Outputs stay
in ignored `output/native-placements`.

The same three variants also use the host resolver to render and save linked
artwork. Six additional page comparisons have zero differences; independent
extraction verifies exact preservation of all three native linked programs.
Their paths, relative-directory sections and preview bytes remain unchanged.
Five linked-image pixel probes verify separate alpha, object opacity, row order
and clipping against explicit expected colors. Together with the embedded cases,
the verifier requires ten page comparisons and four recovered native programs.

```sh
python3 tool/fetch_corpus.py --manifest placement_manifest.json
dart run tool/check_native_placements.dart
python3 tool/verify_native_placements.py --inkai-source /tmp/extension-ai
```

Relinking uses the same intact fixture and the linked PDF carrier generated above.
The verifier writes an actual `assets/relinked-apple.png`, independently inverted
from the original saved RGB preview. Two native variants use that new absolute
path and relative directory; one refreshes the preview, the other removes it.
Ghostscript independently decodes both path operands. The pinned reader and
Pillow verify the new ARGB rows, all five unchanged setup images and preserved
geometry/object metadata. Four zero-difference Poppler comparisons cover the
standalone and synchronized PDFs; two native programs are recovered exactly.
Outputs and the generated linked resource stay in ignored `output/native-relinks`.
This does not qualify Illustrator reopening or global XMP dependency updates.

```sh
dart run tool/check_native_relinks.dart
python3 tool/verify_native_relinks.py --inkai-source /tmp/extension-ai
```

Catalog XMP has a separate pinned corpus. Adobe's `BlueSquare.ai` (Illustrator CS2)
provides a real packet without a dependency manifest. ExifTool's `XMP3.xmp` provides
a manifest plus unrelated non-XMP RDF extensions, which remain opaque. The checker
retains the Adobe packet and relinks one ExifTool reference. lxml and ExifTool
independently verify the result, while pypdf checks source preservation and saved
catalog packets. Two Poppler comparisons require zero pixel differences. The
ExifTool packet attached to Adobe artwork is a synthetic metadata carrier, not a
real Illustrator linked-resource edit. Adobe reopening and automatic native/XMP
mapping remain unqualified. Dependencies: lxml, pypdf, Pillow, zstandard, ExifTool
and Poppler, as used by the existing PDF verifier.

```sh
python3 tool/fetch_corpus.py --manifest xmp_manifest.json
dart run tool/check_xmp_metadata.dart
python3 tool/verify_xmp_metadata.py
```

Affine image geometry uses the existing raster fixtures and linked PDF carrier
from `check_native_placements.dart`. Three operations—nonuniform resize, scaled
quarter-turn and reflection/shear—cover 66 embedded and three linked edits. The
pinned reader verifies all sample planes and matrices, including `Xh`/`XI`
agreement. UUIDs, local bounds, previews and unrelated source data remain exact;
explicit frame angles update to six decimals. Two private fuzzy masks reject the
edit. Six saved native programs are recovered independently. Twelve page
comparisons against transformed original Adobe/Ghostscript appearances have a
maximum mean channel difference below 0.00981/255 and no differences in flat
pixels. This does not qualify Adobe reopening, frame-tool interactions or effect
regeneration.

```sh
dart run tool/check_native_image_geometry.dart
python3 tool/verify_native_image_geometry.py --inkai-source /tmp/extension-ai
```

Live-shape rotation reuses eight existing CC fixtures and the three additional
files in `rotation_manifest.json`: rounded rectangles with equal/different
corners and a moved first artboard. Quarter-turn and oblique variants exercise
42 live shapes, including private outlines and redundant/versioned dictionaries.
The independent reader checks rotated centers, angles, frame metadata, gradient
matrices and Cartesian highlights, and byte-exact shared setup resources.
Twenty native-authoring SVG renders are compared with transformed original SVGs.
The two irregular-corner variants use printable curves because the pinned reader
cannot render that authoring path effect; their corner parameters are checked
independently. Empty renders fail validation. The maximum SVG mean channel
difference is below 0.00218/255. Thirty-two saved PDF/AI comparisons use transformed
Adobe appearances; four use Ghostscript's independent rendering of the moved
artboard's known black rectangle, since its original PDF contains a compatibility
warning. Their maximum mean channel difference is below 0.06142/255, with equal
flat pixels and gradient-field differences at most one channel level. All
eighteen saved native programs are recovered byte-exactly. These checks do not
qualify Adobe reopening, frame-tool interactions or arbitrary effect regeneration.

```sh
python3 tool/fetch_corpus.py --manifest rotation_manifest.json
dart run tool/check_live_shape_rotation.dart
python3 tool/verify_live_shape_rotation.py --inkai-source /tmp/extension-ai
```

Uniform live-shape scaling reuses those eleven pinned files and 42 shapes at
factors 0.5 and 1.5. The independent parser checks dimensions, angles, irregular
polygon radius sentinels, both inherited stroke states, isolated style copies,
gradient matrices and focus. SVG references bake path effects before applying
the scale so Inkscape does not keep their offset widths fixed. Twenty native
authoring and two printable-curve comparisons have a maximum mean channel
difference below 0.00625/255. Empty images fail; flat pixels match and smooth
gradient fields differ by at most one channel level. Eighteen saved native
programs are recovered exactly. Thirty-six PDF comparisons use the same
Adobe/Ghostscript reference split as rotation, with a maximum mean channel
difference below 0.000066/255, identical flat pixels and gradient fields within
one level. Adobe reopening, nonuniform scaling and fixed-stroke/corner resizing
remain separate work.

```sh
dart run tool/check_live_shape_scale.dart
python3 tool/verify_live_shape_scale.py --inkai-source /tmp/extension-ai
```

Radial focus editing reuses the 37 pinned native fixtures. The dedicated checker
changes every radial resource to an interior focus, then saves three variants of
the CC radial drawing: interior, centered and boundary. The independent reader
verifies 45 printing instances and 173 authoring notes, including older CS
matrix-free style notes, and unchanged source outside `Bh` operands. Three saved
native programs are recovered exactly. Six Poppler comparisons use Adobe's
original PDF with independently changed focal coordinates. Their maximum mean
channel difference is below 0.06791/255, against the unedited 0.06792/255 baseline
caused by rounded rectangle edges. Flat pixels must be identical; smooth fields
may differ by at most one level. Outputs stay in ignored `output/gradient-focus`.
This qualifies a global focus edit, not isolated object editing, arbitrary
gradient transforms, flattened effects or Illustrator reopening.

```sh
dart run tool/check_native_gradient_focus.dart
python3 tool/verify_native_gradient_focus.py --inkai-source /tmp/extension-ai
```

Selected live-shape gradient isolation reuses `gradient_linear.ai` and
`gradient_radial.ai`, selecting three of fifteen and three of nine shapes.
Five variants isolate resources alone, change selected colors or move selected
radial foci. The independent parser checks every original definition/style,
new bindings, bank counts and selected/unselected body commands. Four SVG
comparisons are pixel-exact. Five saved native programs are recovered exactly.
Ten Poppler comparisons use Adobe's original PDF, cloning only the selected
shading occurrences before applying expected colors or focal coordinates.
The radial file's Black-only DeviceN space is retained when changing ink values.
Linear comparisons are exact; radial means stay below 0.06792/255, including
isolation alone, with the existing rounded-outline discrepancy. Flat pixels
remain identical and smooth gradient fields differ by at most one level.
Outputs stay in ignored `output/gradient-isolation`. This does not qualify
plain-path selections, arbitrary effects or Illustrator reopening.

```sh
dart run tool/check_live_shape_gradients.dart
python3 tool/verify_live_shape_gradients.py --inkai-source /tmp/extension-ai
```

Relative gradient placement uses the same 15 linear and nine radial CC shapes.
Six variants change every shape, a partial selection, or a partial selection
after object rotation and uniform scaling. The independent parser checks old
resources/styles, new style bindings, every retained path/dictionary, relative
placement, polar/Cartesian focus and complete strip/cap coverage. Six saved
native programs are recovered exactly. Twelve PDF comparisons use independently
placed shadings in Adobe's original PDF; their new axes and origins are computed
with Inkex from Adobe's own clip curves. Maximum mean channel difference is
below 0.067991/255. Flat pixels must match exactly; smooth fields differ by at
most one level away from reference color and clip edges. The clip-edge mask
comes from Adobe's path geometry, including near-white boundaries that a
contrast-only mask cannot identify. The checker never derives that mask from
AiKit's output. Results remain in ignored `output/gradient-placement`.
This qualifies source geometry and PDF rendering, not Adobe reopening, arbitrary
affine paint transforms or execution of Illustrator's printing procsets.

```sh
dart run tool/check_live_shape_gradient_placement.dart
python3 tool/verify_live_shape_gradient_placement.py --inkai-source /tmp/extension-ai
```

To check the existing downloads without network access or rewriting files:

```sh
python3 tool/fetch_corpus.py --verify-only
```
