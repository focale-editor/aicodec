# Illustrator format and editing reference

## Format families

`AiDecoder` identifies `%PDF-`, `%!PS-Adobe-` or a DOS binary EPS header.
A file extension is never used as proof of format. Illustrator provenance is
required by default: private PDF blocks, Illustrator Creator/Producer metadata,
or legacy Creator/AI-version DSC comments. `allowGeneric: true` deliberately
accepts generic PDF/EPS interchange, including output created without native
Illustrator data. This marker check is not an authenticity/security guarantee.

`AiPdfDocument` owns a `PdfDocument`; all PdfCore parsing and writing boundaries
apply, including rejection of encryption and full-rewrite signature invalidation.
`AiPostScriptDocument` owns the exact input bytes plus the location of the
PostScript section and immutable top-level DSC comments.

## Native Illustrator data

For each catalog/page owner, `privateBlocks` follows
`PieceInfo → Illustrator → Private → AIPrivateDataN` (or `AIPDFPrivateDataN`). Block suffixes are sorted
numerically; shared indirect blocks are returned once. Each block retains its
page index, suffix and original PDF stream dictionary and encoded bytes.
Unknown fields and blocks remain in the PDF graph.

`AiNativeData.extract` resolves each owner's complete sequence, checks contiguous
block numbering, decodes outer PDF filters and joins the native envelope.
It excludes recognized thumbnail-only blocks before the program. Owners sharing
the same complete block sequence share one extracted source; independent page
programs remain separate. Markers split across streams are supported. It does
not search arbitrary binary bytes for a plausible compression signature.

Supported native envelopes are plain `%!PS-Adobe-` programs,
`%AI12_CompressedData` followed immediately by zlib, and
`%AI24_ZStandard_Data` followed immediately by Zstandard. ZCodec provides both
compressed decoders and encoders. Native data is accessible even when the PDF
page only contains a compatibility warning. Extraction is not rendering.

`AiNativeSource` owns immutable program bytes, records its catalog/page owners
and compression family, and can expose a standalone PostScript container without
changing the program's version. `AiNativeData.encodeEnvelope` writes a selected
compression family. Unknown instructions and private records stay in the source.

## Native hierarchical records and artboards

`AiNativeRecords.decode(program: program)` exposes native dictionaries, arrays,
object records and binary resources in both ordinary and `%_`-prefixed syntax.
The projection retains original source offsets, removes prefixes outside binary
payloads and preserves multiline strings. Adjacent PostScript string fragments
are concatenated for values and keys. Unknown scalar/container types and embedded
drawing commands remain available as source-backed items.

Dictionary keys are unique; repeated object fields, such as filter `/Part`
entries, remain ordered and accessible through `values(key)`. Ambiguous single
lookups fail explicitly. Known numeric and string types are validated. Tokens,
container nesting and operand nesting use the program's native resource policy.
`decodeBinary(maxOutputBytes: ...)` uses PdfCore's bounded ASCII85 decoder for
profiles and text-engine payloads; decoding a payload does not interpret its
contents as a fully supported Illustrator feature.

`records.artboards` reads the document's recorded `ArtboardArray`, retaining each
dictionary, name bytes, source identifier, active flag and drawing-coordinate
bounds. These artboards are independent of PDF compatibility pages.
`replaceString` and `replaceNumbers` update existing source-backed entries and
reparse the complete records. They reject foreign handles and invalid values.
Names and text use explicit bytes; `entry.text(encoding: ...)` lets the caller
select the encoding. Integer edits preserve integer syntax and are restricted
to exactly representable values on both VM and JavaScript.

### Native text documents

`AiNativeTextDocument.decode(records: ...)` decodes an `AI11TextDocument` through
PsCore's shared EngineData parser. Select a container explicitly when a program
contains multiple text documents. The separate `AI11UndoFreeTextDocument` remains
opaque to this semantic view; it is not silently merged into the current model.
The reader accepts named CS keys and compact numeric keys without normalizing
the retained source. A dictionary containing both aliases for a recognized
field is rejected as ambiguous.

The view exposes ordered fonts, character/paragraph styles, frame resources,
stories and `AI11Text` drawing references. `story.modelText` retains the mandatory
final carriage return, while `story.text` removes only that final mark. Run
lengths and offsets count UTF-16 code units, including the final mark. An omitted
character/paragraph run table inherits the corresponding normal style; its
explicit run list stays empty. Present run tables must cover the text exactly;
empty/incomplete tables, zero lengths, overflow and boundaries within surrogate
pairs are rejected. Known story text requires a UTF-16 BOM. Unknown
fields, inline style overrides, UUIDs, glyph strikes and layout caches remain
available through immutable PsCore values and the original engine bytes.

`characterStyleAt`, `paragraphStyleAt` and `styledRanges` resolve normal styles,
bounded parent chains and local overrides, splitting ranges at both run tables.
Character resolution applies inherited paragraph `DefaultStyle` layers above
the shared normal character features, then explicit character-style overrides.
Partial paragraph character defaults preserve unrelated parent features. Feature
layers remain immutable and source-backed, including unknown keys. Missing
values remain null rather than receiving guessed application defaults. Common
font/size/scale/spacing fields and explicit OpenType Boolean switches are exposed;
optical kerning, script-specific composition, synthesized styles and font fallback
still require host logic.

`referenceIssues` reports unresolved story/frame/style/font references, cyclic
or excessive style inheritance and drawing references selecting the undo-free
model. It does not validate every cached glyph field or typography rule.

`story.strikes` reads the retained story/frame/row/line/segment/glyph hierarchy,
accepting named and abbreviated stream tags. It exposes native origins, bounds,
frame indices, source-character mappings, glyph IDs and shadow-style dictionaries
without inferring missing advances or treating glyphs as one-to-one characters.
Frame views expose type, explicit origin, matrix and original path coordinates.
These are saved layout observations, not the output of newly shaped text.

`renameStyle` edits only the selected source-backed display name, preserving the
other decoded engine bytes. `records.replaceBinary` uses PdfCore's bounded
ASCII85 encoder and retains the container header, trailing fields and unrelated
native records. Both reject foreign/stale handles. These edits return a new
native snapshot; callers still own the surrounding file-save transaction.
Style naming does not change artwork.

`replaceText(story:, start:, end:, text:)` edits the native model for subsequent
recomposition. Offsets address UTF-16 code units in `story.text`, excluding its
mandatory terminal CR. New characters inherit the character style at the start
offset, including its inline overrides. Each resulting paragraph has its own
run and inherits the style at its first character; inserted CRs split paragraphs,
while deleting a CR joins them. Missing character tables remain inherited. An
omitted paragraph table is materialized from the normal paragraph resource when
multiple paragraphs require separate runs. Source run metadata and unknown style
features survive. Empty CS auxiliary tables are resized; active auxiliary features
and unknown model/view keys reject the edit. LF input, malformed UTF-16, split
surrogate pairs and removal of the terminal CR are rejected. String and run
expansion are bounded before constructing all output dictionaries.

Only the selected model and view are rewritten. Its frames remain, while
`RenderedData` and `Strikes` are removed because their source-character offsets,
glyph IDs and geometry are no longer valid. Other stories, resource tables,
drawing references and the undo-free document stay unchanged. A no-op retains
the original snapshot and cache bytes. This operation does not shape text,
regenerate its display or update the PDF: the host must recompose the affected
story and synchronize its printable/PDF artwork before a complete visual save.
External PROOF experiments report model-driven recomposition in Illustrator
29.2.1, including with absent/incorrect caches; that is a format observation,
not an Adobe reopening qualification of AiKit's own output.

`setCharacterFeatures` applies `AiNativeCharacterChanges` to a UTF-16 selection,
including its paragraph marks if selected. It supports a source-owned font,
point size, leading, horizontal/vertical scale, tracking, baseline displacement,
rotation, kerning modes and explicit OpenType switches/sets. Native point size
and `RefFontSize` are changed together; an active non-point reference mode is
rejected until font-metric conversion is available. Explicit leading defaults
to disabling automatic leading; an explicit `automaticLeading` argument controls
that choice. An omitted table is materialized without flattening normal-style or
paragraph-default inheritance. Resource selections become inline overrides with
their original parent index. Unknown style features and run metadata survive.
Active alternate-glyph overrides reject a font change.

`setParagraphFeatures` applies `AiNativeParagraphChanges` to complete paragraphs
touched by the selection. Its end is exclusive; an empty selection selects the
caret paragraph. Each affected paragraph gets its own run. Alignment, indents,
paragraph spacing, automatic-leading factor, hyphenation, every-line composition,
direction and composer can be changed independently. `inherit` in either change
model removes local overrides and exposes the existing parent/default values;
it does not edit named resources or clear their features. The new API does not
implement the compositor implied by these settings.

Both operations preserve other stories and resource dictionaries and remove only
the selected story's rendered-data/glyph caches. Modified inline styles with
UUIDs receive fresh version-four identities; unchanged fragments retain theirs,
and collisions against the source engine are checked. Applying already-present
local values preserves the original snapshot, layout bytes and UUIDs. Invalid
values, foreign/stale fonts/stories, surrogate boundaries, unknown model/view
fields and paragraph-style boundaries inside a paragraph reject the operation.
Host recomposition and PDF synchronization are still mandatory for visual saves.
Shared parsing defaults to 128 MiB, one million values, 64 nesting levels and
64 MiB per decoded string, with caller-selected tighter limits available.

These are record-level edits. Renaming an artboard changes no painted geometry;
changing a live-shape dimension requires updating its path and appearance too.
The record API does not claim to perform those dependent changes automatically.

## Native CC live shapes

`AiNativeDrawing.decode(records: ...)` reads printable paths and `%_`-prefixed
authoring outlines separately. It retains group/compound topology, paint and
curve operators, named styles, redundant appearance dictionaries and recognized
AI17 metadata alternatives. `liveShapes` associates each authoritative
`ai::LiveShape` dictionary with its outline and printable expansion. Incomplete
associations expose `bindingIssue`; parsing alone does not imply editability.

```dart
final AiNativeDrawing drawing = AiNativeDrawing.decode(
  records: AiNativeRecords.decode(program: program),
);
final AiNativeDrawing moved = drawing.translateLiveShapes(
  shapes: [drawing.liveShapes.first],
  deltaX: 20,
  deltaY: -10,
);
final AiProgram editedProgram = moved.records.program;
```

Translation supports rectangle, ellipse, polygon, star and line handlers with
solid and linear/radial gradient fill/stroke styles, including inside/outside
stroke expansions and opacity. It changes every selected outline/control point, every associated
printable contour and both recorded/redundant canvas centers atomically. Drawing
coordinates have y up; canvas centers have y down. Offsets are source drawing
units, before any host large-canvas scaling. Dimensions, corner parameters,
rotation, styles, unselected artwork and unrelated source bytes are retained.
Source handles cannot be reused against a later snapshot.

The current operation rejects drawing state containing patterns,
clipping, transforms, unsupported effects/metadata or unresolved versioned
artwork. This includes unsupported state outside the selection: the reader does
not yet prove that inherited graphics state is independent of that artwork.
Nested appearance ownership is rejected when dependent copies are unresolved.
Reading and exact source preservation remain available for these documents.

DSC bounds conservatively include the original extent and its translated copy;
they may grow more than the exact new artwork bounds. Artboards remain fixed.
The result is an authoring snapshot: the host must regenerate the PDF appearance
and cached previews before packaging a visual edit. Resizing, rotation,
parameter-driven shape regeneration and complete CC style editing remain open.

### Gradient instances and native paint styles

`AiNativeDrawing.gradients` exposes bounded `Bb`/`BB` instances, their `Bg`
geometry, optional radial `Bh` highlight, absolute `Xm`/`Bm`/`Bc` printing
matrices and the paths consumed inside each instance. The optional `Bb` selector
identifies gradients inside strokes. `AiNativePaintStyle.decode` reads command
lists and gradient instances from owned `FillStyle`, `StrokeStyle` and
`BlendStyle` records without flattening repeated appearance parts.

The CC `Bg` layout includes an aspect ratio and describes the gradient relative
to its artwork. Translation retains those parameters and moves the absolute
printing matrices. Legacy `Bg` geometry without the aspect operand instead
requires moving its matrix translation. Radial highlight offsets, dimensions,
angles, aspect ratios and gradient color resources remain unchanged.

Shared relative styles remain shared. When a selected object's known style
contains positional gradient data, translation allocates a distinct native style
name, copies the complete style with checked source edits and redirects only
selected `XW` references. Unselected users retain the original resource bytes.
All insertion and geometry edits share one bounded atomic transaction.

This provides gradient inspection and synchronized translation, not a complete
gradient editor. Color-stop replacement, regeneration of cached ramps, mesh
gradients along/across strokes and arbitrary appearance filters remain open.
Legacy positional-style copying has synthetic regression coverage; the external
gradient fixtures exercise the recent CC operand layout.

## Source-backed editing

`AiProgram.decode` reads body instructions outside the prolog, setup, procedures,
embedded documents and DSC-protected data. It exposes source spans, nested native
layers, names, visibility, lock/print flags and explicit path segments. Corner
and smooth operators, curve shorthand and paint operators are retained.
`unhandledOperators` and `hasPrivateExtensions` expose unresolved semantics;
neither a path count nor an empty unhandled set proves complete renderability.

`AiNativeEditor.updateLayer` changes native layer names and flags, preserving
version-specific operands and other bytes. CC layer-header flags are updated
when identified; an ordinary legacy first object's lock is not rewritten.
Names use Latin-1 with `name`, or explicit caller-selected bytes with `nameBytes`.
No font or locale encoding is guessed. Handles from another snapshot are rejected.

`replacePath` changes plain geometry while retaining comments and paint.
It refuses programs containing unresolved operators, private editing extensions,
or appearance-owned geometry. In particular, changing only a rendered outline
of a CC live shape would leave its alternate native representation stale.
`apply` is a lower-level atomic byte-edit operation: it checks spans, overlap and
size, then reparses. Callers of that API own semantic consistency.

`AiNativeData.replace` rewrites all owners of an extracted PDF program in its
original compression family. It replaces numbered blocks, removes stale native
thumbnail blocks and retains other producers and private metadata. Its required
`synchronizedPdf` argument must derive from the original PDF graph, retain
metadata references and contain the matching appearance after a visual edit.
The kit cannot establish native/PDF equivalence. Renaming a native layer does
not change painted geometry, so the existing appearance can be reused for that
operation. Mixed native block families on one owner are rejected for rewriting.

When replacing page artwork, use
`AiPdfDocument.forPdfInterchange(pdf: changedDocument)` to remove Illustrator
PieceInfo links while retaining other producers. This prevents stale native
artwork from taking precedence when reopened. Unreferenced original private
objects remain in the generic graph; this operation is not data redaction.
The public `AiPdfDocument(pdf: ...)` constructor preserves an already coherent
native/PDF graph; callers retaining private authoring data own its consistency.

## Native artwork creation

`AiArtwork` writes the documented AI7 operator subset from immutable paths,
groups and layers. `AiArtworkPath` supports open/closed Bézier geometry, gray,
RGB and CMYK fills/strokes, winding rules, width, cap, join, miter and dashes.
Layers retain names, nesting, visibility, locking and printing flags. Hidden
children remain in the file. The generated PostScript includes its own small
drawing prolog; it does not depend on executing an Adobe prolog in Dart.

This is an explicit legacy target. It does not manufacture Illustrator CC
plug-in dictionaries, live effects, ATE text, meshes or proprietary editable
gradient/raster records. `AiProgram` can inspect and edit supported portions of
existing modern programs without converting them to AI7. There is no generic
PostScript interpreter or built-in native-to-PDF renderer.

## Legacy PostScript

DSC inspection skips declared binary/data sections and embedded documents before
collecting title, creator and bounds. Continuations are retained; `(atend)` values
resolve from later concrete declarations. `HiResBoundingBox` takes precedence.
DOS EPS PostScript/preview ranges are validated and the entire envelope is kept.
Encoding returns the exact original source bytes, including unknown data.

`AiPostScript.tokenize` is optional and exposes immutable tokens with source byte
spans and exact Latin-1 lexemes. It recognizes numbers (including exponent and
radix notation), literal/executable names, parenthesized/hex/ASCII85 strings,
array/dictionary/procedure delimiters, comments and DSC-protected data blocks.
Literal procedure braces must balance; array and dictionary delimiters are
runtime operators and may intentionally cross procedure boundaries. No procedure or operator executes;
binary-token formats and arbitrary dynamic PostScript are not an interpreter
contract. Callers can use spans to construct replacement source, then decode
that source again. Changing token objects does not mutate the retained program.

## Limits

`AiLimits.pdf` uses PdfCore's resource policy, including the 128 MiB file ceiling.
DSC defaults allow 1 MiB per continued comment and 100,000 retained comments.
Embedded-document nesting uses the PDF depth limit (128).
Tokenization independently defaults to 128 MiB, 1,000,000 tokens and depth 128.
`AiNativeLimits` separately bounds aggregate PDF-encoded and filtered envelopes
to 128 MiB, aggregate decoded programs to 128 MiB, Zstandard windows to 32 MiB,
and program tokens/depth to 1,000,000/128. Limits are checked before output
growth. Authored artwork uses `AiLimits.pdf` for output bytes, nodes and depth.
Malformed containers raise `FormatException`; invalid limits raise
`ArgumentError`. Unknown formats are rejected rather than treated as raw AI.

## Compatibility evidence

The external corpus contains 37 upstream Inkscape extension-ai fixtures across
AI3, AI7, AI9, AI10, CS–CS6 and CC/current samples: paths, gradients, layers,
colors, raster content, text and opacity. Container checks cover exact legacy
preservation, tokenization, PDF graph rewrite and private-block byte preservation.
Native checks require extraction and structural parsing on every file, verify
the six-layer fixture's names and flags, then rename a layer where present and
read hierarchical records and binary resources, rename native artboards where
present, and reopen rewritten native data. Python zlib and reference Zstandard independently
decode both original and rewritten envelopes (31 PDF fixtures).

The drawing reader associates all 39 live shapes in the corpus. Eight fixtures
exercise translation of those 39 solid/gradient shapes, including 35 private
outlines and redundant metadata copies. The independent Inkscape extension-ai
reader checks all 112 paths (110 moved and two unchanged), 148 canvas-center
fields, translated printing matrices and unchanged relative style commands.
The checker also compares SVG gradient endpoints/centers/foci and color stops.
SVG rendering through Inkscape compares the edited result with an explicitly
translated original: seven cases have zero pixel difference; the radial case
has a maximum mean channel difference of 0.000013/255 in the recorded run.
Librsvg 2.62.4 produced a larger discrepancy for equivalent radial SVGs whose
foci touch or slightly exceed their circles; geometry checks and Inkscape
rendering are therefore required for that case. `tool/verify_live_shapes.py` requires the pinned external
reader and fails when any fixture/output is missing. Its upstream reader reports
some unsupported operators, so this is focused translation evidence, not full
appearance or Adobe reopening validation.

Text validation covers 32 native ATE payloads, with 20 stories across CS–CC
examples. `tool/verify_native_text.py` uses the same pinned independent reader to
decode rewritten ASCII85 and compare entire ATE trees, allowing only the selected
style name to differ. It also compares fonts, frame geometry, run lengths and
every retained glyph-layout node against exported typed projections. The
transformed-text fixture contains ten stories, sixteen frames, twenty-four
effective style ranges, 387 layout nodes and 4,003 cached glyph IDs. Four stories
omit explicit character runs and inherit their style. Named CS point text and
its compact successors resolve the same font and point size. Twenty separate
content edits insert non-BMP characters and a paragraph across all native stories;
the independent checker reconstructs run ownership per UTF-16 unit and compares
the entire engine tree, including untouched stories and removed caches. These
edited native programs are not combined with their original PDF previews.
Forty additional native edits change character and paragraph features separately;
the independent checker verifies complete trees, UTF-16 selection coverage,
inherited run ownership, both size fields and fresh inline UUIDs. Neither the
original resources nor unselected feature values may change.
Newly shaped text,
altered text appearance and Adobe reopening remain outside this check.

Unit tests cover compressed and uncompressed envelopes, split markers, owner
aliases, independent page programs, limits, malformed syntax, atomic edits and
explicit geometry rejection. A VM test renders authored AI7 using Ghostscript
and checks visible, hidden and nonprinting layer behavior. That test explicitly
skips if Ghostscript is unavailable. No Adobe Illustrator installation was used;
native reopening and complete editing compatibility remain unverified.

| Area | Current contract | Remaining work |
| --- | --- | --- |
| CC compression and blocks | Decode/rewrite plain, zlib and Zstandard native programs | Additional producer/version corpus coverage |
| Native layers | Inspect/edit names and visibility/lock/print flags | More private layer appearance semantics |
| Native records and artboards | Typed dictionaries, arrays, object records, ASCII85 resources, artboard bounds/names and scalar edits | Geometry-dependent synchronization and broader semantic models |
| Native ATE text | Stories, UTF-16 runs, resources, retained layout, style naming, content and character/paragraph feature edits with cache invalidation | Shaping, layout regeneration, advanced typography and synchronized text-content saves |
| Paths and live shapes | Inspect native/printable geometry; edit plain paths; translate five CC shape families with solid/gradient appearances; create AI7 paths | Resize/rotate/regenerate live shapes and synchronize remaining positional paints/effects |
| Gradients | Inspect native paint commands and instances; translate vectors/printing matrices; isolate shared positional styles | Edit stops/ramps, full appearance semantics and meshes |
| Groups and paint | Create AI7 groups, solid process fills and strokes | Complete import into typed scene nodes |
| Meshes, effects, plug-ins, raster | Preserve exact source bytes and report unresolved operators | Typed native models, editing and serialization |
| PostScript | Bounded lexical/structural reading and self-contained subset writing | No arbitrary PostScript execution |
| PDF compatibility appearance | Preserve, replace with caller-synchronized graph, or explicit interchange | Native scene rendering belongs to host integration |

## References

- [Adobe's AI format overview](https://www.adobe.com/creativecloud/file-types/image/vector/ai-file.html)
- [Inkscape extension-ai corpus](https://gitlab.com/inkscape/extras/extension-ai)
- [Native data container observations](https://gitlab.com/inkscape/extras/extension-ai/-/blob/1a5f42a0b0407fc869e032420570682048810108/docs/specification_amendments/compression.md)
- [Native hierarchy observations](https://gitlab.com/inkscape/extras/extension-ai/-/blob/1a5f42a0b0407fc869e032420570682048810108/docs/specification_amendments/hierarchy.md)
- [Native text structure observations](https://gitlab.com/inkscape/extras/extension-ai/-/blob/1a5f42a0b0407fc869e032420570682048810108/docs/specification_amendments/text_documents.md)
- [PROOF point-text writing and recomposition experiments](https://github.com/vurglepuddle/PROOF/blob/d822dc5dea265675a0fd5dec550e3e0dcd5988f0/doc/PROOF-ai-native-records.md#point-type-written-2026-10-23)
- [Document/artboard observations](https://gitlab.com/inkscape/extras/extension-ai/-/blob/1a5f42a0b0407fc869e032420570682048810108/docs/specification_amendments/document_data.md)
- [Live-shape structure observations](https://gitlab.com/inkscape/extras/extension-ai/-/blob/1a5f42a0b0407fc869e032420570682048810108/docs/specification_amendments/live_shapes.md)
- [CC gradient observations](https://gitlab.com/inkscape/extras/extension-ai/-/blob/1a5f42a0b0407fc869e032420570682048810108/docs/specification_amendments/gradients.md)
- [Adobe Illustrator 7 file format specification (Adobe document mirror)](https://13thmonkey.org/documentation/fonts/AI7FileFormat.pdf)
- [Zstandard format specification, RFC 8878](https://www.rfc-editor.org/rfc/rfc8878.html)
- [PdfCore reference](../../PdfCore/docs/PDF.md)
