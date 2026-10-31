# Illustrator format and editing reference

AiKit owns native editable data and serialization. The application owns rendering,
composition and derived representations; see [the host contract](HOST.md).

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
offset, including its inline overrides. Native paragraph runs end at both CR
and U+0003 forced breaks, and inherit the style at their first character. A forced
break stays inside the logical paragraph; deleting either break joins its native
spans. Missing character tables remain inherited. An
omitted paragraph table is materialized from the normal paragraph resource when
multiple native spans require separate runs. Source run metadata and unknown style
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

`addFont(font: AiNativeFontDefinition(...))` appends a CoolType resource and returns
an immutable snapshot whose `fonts.last` is the newly registered face. The host
supplies its actual PostScript name, PostScript/CFF or TrueType technology,
optional version string and signed 16.16 variation coordinates in the font's axis
order. No font program is loaded, installed or embedded by this operation.
Existing indices, styles, stories and caches remain unchanged. An existing font
display list receives the new index; an absent list stays absent. Font-set
metadata is retained, malformed display references reject the write, and engine
string/node limits still apply. Every addition receives a fresh ASCII UUID;
identical names are not merged because font versions and variable instances can
differ. Use the returned font and story with `setCharacterFeatures` to select it.

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
caret paragraph. Selection expands to CR boundaries and therefore includes all
forced-break spans in the same logical paragraph. Authored native runs remain
split at each CR or U+0003. Alignment, indents,
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
fields and paragraph-style boundaries inside a native span reject the operation.
Host recomposition and PDF synchronization are still mandatory for visual saves.

`withTextLayout` accepts immutable `AiNativeTextFrameLayout`,
`AiNativeTextLineLayout` and `AiNativeTextSegmentLayout` data from a host compositor.
Coordinates are native points with y down: frame origins use the retained layout
space, line origins are frame-relative, and segment origins are line-relative.
The API writes the observed PC/F/R/R/L/S source-position hierarchy. It does not
measure fonts, shape glyphs, break lines or invent GlyphStrike caches. Optional
selection metrics and local line bounds are written only when supplied.
The story's model, font/style resources, frame geometry/references and other
stories stay unchanged; old rendered-data and glyph caches are removed.

All frames must belong to the same snapshot and match the story's complete
resource order. Lines progress through the logical source; their segments may
use visual order, with explicit UTF-16 ranges. Gaps, overlaps, split surrogate
pairs, breaks inside a line, coordinate overflow and excessive node allocation
reject the write. `overflowStart` explicitly declares an uncomposed suffix;
without it, coverage must include the final CR. Empty linked frames and wholly
uncomposed stories are represented explicitly. Compact word-reorder mappings can
be authored for right-to-left segments. Compact automatic-hyphen insertion maps
retain a terminal generated hyphen without inserting it into editable text;
this form requires a terminal BMP source character and the end of a composed line.
Named CS reordered/hyphenated mappings and per-glyph path geometry remain explicit
refusals. Host shaping, glyph adjustments, print/PDF synchronization and Adobe
reopening qualification remain separate work.

`translateFrames(frames:, deltaX:, deltaY:)` translates a distinct, source-owned
selection of point, area or path frames in drawing points (y up). It adds the
translation to the frame matrix's canvas offsets, with y reversed. Matrices may
already rotate, shear or reflect the frame; their linear components stay intact.
An omitted matrix becomes an explicit translated identity. Frame positions,
Bezier control points, text/style runs, local layout and glyph bounds remain in
their original pre-matrix space and are preserved exactly outside the selected
frame resources. This operation does not require new shaping or line breaking.

Every main-model drawing reference to a selected frame has its `/ConfiningPath`
coordinates translated in drawing space, preserving curve shorthand, corner
operators and nonpositional state. One frame within linked text may move without
changing the other frames or their order. `AiNativeArt.decode` exposes the
bounded commands and nested metadata used for these paths without executing
PostScript. The editor accepts one unpainted path with optional retained rotation
metadata. Embedded transforms, painted/compound paths, live-shape metadata,
unknown frame/view semantics, missing drawing references, ambiguous main text
documents and nonfinite output are explicit refusals. Failed edits leave the
source snapshot unchanged.

The shared `AiNativeEditor.translationBoundsEdits` expands DSC bounds to contain
both original and moved artwork, skipping embedded documents and procedures;
artboards and ruler origins remain fixed. Whole-file native text effects,
undo-free appearance copies, printable/PDF artwork and thumbnails still belong
to the host's synchronized save transaction. This operation does not claim an
Illustrator reopening or independent pixel-rendering qualification.
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
clipping, arbitrary executable transforms, unsupported effects/metadata or unresolved versioned
artwork. This includes unsupported state outside the selection: the reader does
not yet prove that inherited graphics state is independent of that artwork.
Nested appearance ownership is rejected when dependent copies are unresolved.
Reading and exact source preservation remain available for these documents.

DSC bounds conservatively include the original extent and its translated copy;
they may grow more than the exact new artwork bounds. Artboards remain fixed.
The result is an authoring snapshot: the host must regenerate the PDF appearance
and cached previews before packaging a visual edit. Nonuniform resizing,
parameter-driven shape regeneration and complete CC style editing remain open.

`rotateLiveShapes(shapes:, radians:, pivotX:, pivotY:)` rotates the same five
families around an explicit drawing-space pivot. Positive angles rotate
counterclockwise in y-up coordinates; the input is bounded to -2π..2π. A unique
setup `AI11TextDocument.RulerOrigin` supplies the stable canvas origin. Artboard
positions, page origins and crop rectangles are not substitutes for that field.
Missing or ambiguous canvas origins reject rotation without changing the source.
Units remain native drawing units, before any large-canvas scaling.

Each selected private/printable control point and every recorded/redundant center
rotates in its own coordinate system. Rectangle `Angle` and other handlers'
`RotationAngle` values advance in radians, normalized to 0..2π. Existing
`BBAccumRotation` fields retain their scalar/string representation and update to
six decimals; absent fields are added with a zero starting frame angle. The
separate frame angle stays in the signed full-turn range. Dimensions, corner
parameters, stroke widths/dashes, cubic-curve flags and unselected objects remain
unchanged. Zero and complete-turn requests retain the original snapshot.

CC gradient printing matrices rotate in drawing coordinates, while accumulated
`Bg` matrices rotate in the y-down canvas frame. Radial highlight offsets rotate
as vectors; their normalized polar focus stays fixed. Qualified nonprinting
relative style notes retain their identity matrices and zero highlight offsets.
The object-specific `Adobe_AI9_ArtStyle_Dictionary.CAIGradientTformMatrix` is
updated or inserted, using the observed `NotRecorded` dictionary layout. Existing
copies must agree with all the object's gradient appearances. Shared known-style
resources stay byte-exact; unsupported positional styles and older gradient
layouts reject rotation. Subsequent translations retain a qualified accumulated
matrix and move its printing appearance normally.

The same dependency restrictions apply to rotation as to translation. DSC bounds
conservatively include the original and rotated whole extent, retaining stroke
margins; fixed artboards may clip rotated artwork. The result still requires a
synchronized PDF save and regeneration of other previews/effects by the host.
`AiNativeEditor.affineBoundsEdits` exposes the corresponding bounded conservative
DSC operation independently of shape editing.

Rotation qualification covers 42 live shapes in eleven pinned files, each at a
quarter turn and an oblique angle. The independent reader checks native centers,
angles, frame metadata, gradient transforms, highlights and unchanged setup
resources. Twenty SVG comparisons use native authoring shapes; two use printable
curves because the pinned reader cannot render the irregular-corner path effect.
Those corner parameters are still checked independently, and empty renders fail
validation. The maximum SVG mean channel difference is below 0.00218/255.
Eighteen saved native programs are recovered byte-exactly. Thirty-two PDF page
comparisons use transformed original Adobe appearances; four use a Ghostscript
rectangle reference because the moved-artboard fixture contains only Adobe's
missing-PDF-content notice. The maximum PDF mean channel difference is below
0.06142/255, with identical flat pixels and gradient-field differences at most
one channel level. Edge coverage differs between transformed PDF rectangle
operators and equivalent explicit paths. Adobe reopening and frame-tool behavior
remain unqualified.

`scaleLiveShapes(shapes:, factor:, pivotX:, pivotY:)` uniformly scales the same
five families about an explicit drawing-space pivot. The finite positive factor
scales dimensions, corner radii, authoring/printable control points, stroke widths,
dash lengths and dash phase together. Angles, winding, corner modes, side/point
counts and fixed artboards remain unchanged. The observed `Radius = -11` marker
on irregular polygons (`IsRegular = false`) remains unavailable; their paths carry
the geometry. Other negative dimensional values reject the operation. A factor of
one returns the original snapshot after common source/origin validation.

Printable and private stroke distances are tracked separately. The selection
receives explicit scaled inherited values, its internal distance commands scale,
and both original states are restored after each complete object. Known styles
are copied once per selected shared resource; fill/stroke/blend distance commands,
including inside/outside stroke definitions, change only in the copies. Original
resources and unselected appearances remain intact. Gradient matrices and cached
object transforms scale in their respective drawing/canvas frames. Radial
Cartesian highlights scale while polar focus parameters remain fixed.

This operation includes corner and stroke scaling. Fixed-width strokes, fixed
corner radii, nonuniform resizing, reflections and shearing require separate
shape/appearance regeneration. The rotation origin and dependency restrictions
also apply, including rejection of unknown effects and legacy gradient layouts.
DSC bounds conservatively include the original and transformed extent. As with
rotation, the host must synchronize PDF appearances and other previews; Adobe
reopening and editing-tool behavior remain unqualified. Illustrator exposes
separate corner and stroke/effect scaling controls in its
[Transform panel](https://helpx.adobe.com/illustrator/desktop/manage-objects/reshape-transform-objects/transform-panel-overview.html).

Uniform-scale qualification uses the same eleven pinned files and 42 live shapes
at factors 0.5 and 1.5. The independent parser checks dimensional parameters,
unchanged angles and sentinel values, both inherited stroke states, copied styles,
gradient matrices and focus. Twenty native-authoring SVG comparisons and two
printable-curve comparisons have a maximum mean channel difference below
0.00625/255. Reference SVG path effects are baked before scaling: otherwise
Inkscape evaluates offset distances after the transform, producing a fixed-width
reference. Empty renders fail; flat pixels match exactly and smooth gradient
fields differ by at most one channel level. Eighteen saved native programs are
recovered exactly. The 36 PDF comparisons (32 Adobe appearances and four known
Ghostscript rectangles) have a maximum mean channel difference below
0.000066/255, with equal flat pixels and gradient fields within one channel level.

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

Legacy positional-style copying has synthetic regression coverage; the external
gradient fixtures exercise the recent CC operand layout.

### Global gradient colors and printing ramps

`AiNativeGradientResources.decode(records:)` reads setup `Bd`/`BD` definitions,
including nonprinting swatches, from the bounded native token projection. It
skips embedded documents, procedures and hierarchical records. Definitions retain
byte names, linear/radial kind, source-order stops, lower-precision `BS` fallback
stops and `Br` printing intervals. Native private `Bs` data takes precedence;
legacy single-stop syntax is also recognized. Counts and color/channel layouts
are checked rather than inferred from a successful tokenization.

`AiNativeGradientColor` models gray, CMYK, RGB with an explicit CMYK alternative,
custom CMYK/RGB and newer named CMYK/RGB colors. Names retain their byte encoding
and tint semantics. `AiNativeGradientStop` separates color, opacity, midpoint and
position, with an explicit opacity-wrapper flag. `AiNativeGradientRamp` handles
the seven native process/custom-color channel layouts. Channels hold immutable
samples or a native numeric constant; newer normalized constants are retained
without silently converting them to legacy byte values.

`replaceStops(definition:, stops:, ramps:)` replaces every definition sharing the
selected byte name in one transaction. Supply stops in strictly increasing
position order and one host-composed printing interval per adjacent pair, in
increasing interval order. The writer updates the count, both stop
representations and the complete printing ramp. Names, resource counts, gradient
kind and overall gradient placement remain unchanged.
Native linear stops are written in descending position order and radial stops
in ascending order, matching all 296 linear and 82 radial corpus definitions.
Unknown structural metadata/operators, mixed same-name kinds, foreign handles,
coincident stops and excessive expansion reject the edit. Older stop syntax
requires opaque style-zero-through-four colors without an opacity wrapper.

When linear stop positions change, every referencing `Bb`/`BB` instance is
checked, including printable/private drawing, styles, nested art, patterns and
palette resources. Each `Bm` strip is rebuilt for its new interval along the
unchanged `Xm` axis. Older instances without `Xm` recover that whole axis from
the first source interval and validate all remaining strips against it. The
cross-axis extent stays fixed. Exterior `Bc` caps follow the first/last stop
while keeping their far edges fixed. Missing caps reject endpoint moves;
inconsistent strip counts, transforms, cap boundaries, singular geometry,
unmatched commands or excessive expansion reject the whole transaction.
Complete matrix-free notes and radial matrices remain untouched. Procedures,
embedded documents, strings and binary payloads cannot supply executable
gradient references. Color-only changes retain geometry verbatim. Matrix-local
formatting/comments may be regenerated; other source bytes are preserved.

Ramp composition, color profiles, tint/separation conversion and named-color
registration belong to the host. AiKit requires explicit intervals to avoid
retaining stale caches; it does not prove that caller-supplied samples reproduce
the supplied stops. Replacing
a global swatch changes all its users. Selected live shapes can first isolate a
resource as described below. General resource creation/removal, hard stops,
meshes, gradients along/across strokes and flattened appearance
regeneration remain host responsibilities. Definition-local comments are regenerated with the edited resource;
external bytes are preserved.

The independent corpus check compares all 378 definitions, 1,103 authoritative
stops, their fallback records and 725 printing intervals across 37 files. It
rewrites a resource in each of the 23 files containing gradients, checks seven
color layouts and verifies that unrelated resources and drawing commands are
unchanged. Independent parsing also checks linear strip coverage, fixed exterior
cap edges and unchanged gradient placement, including the color variants whose
first stop moves from zero to ten percent. Four additional real pattern variants
exercise private commands and three-, four- and five-stop resources, moving both
endpoints and adding/removing intervals. Across these runs, 139 linear caches
are rebuilt among 1,848 independently inspected instances (including repeated
source instances across variants). Legacy matrices without `Xm`, unsupported
layouts and output limits also have focused synthetic regressions.
For the linear/radial CC fixtures, 24 instances are independently converted to SVG
and rendered against the original geometry with explicitly replaced expected
stops: both pixel comparisons are exact. These checks cover RGB stops and opacity
at midpoint 50, not Illustrator reopening, print-engine ramp interpolation or
arbitrary color-profile equivalence.

### Global radial gradient focus

`AiNativeGradientResources.setRadialFocus(definition:, angle:, length:)` changes
the focus of every instance referencing the selected resource's byte name.
This is an explicit global operation, including shared styles, swatches, private
art and setup patterns; it does not isolate one object's appearance. The native
angle is in degrees, from -360 through 360, and the length is a fraction of the
unit radius in 0..1. The same-name definitions must all be radial and the handle
must belong to the source snapshot.

Each printable instance must have one nonsingular `Bm` matrix and no linear
printing matrices. Its four `Bh` operands retain both the polar authoring focus
and the redundant Cartesian printing offset. The latter is the linear part of
`Bm` applied to `(length*cos(angle), -length*sin(angle))`; the gradient center
is not added. This handles rotated, elliptical, reflected and skewed axes.
Existing offsets must agree with the old polar values within serialization
tolerance. Nonprinting flag-two style notes with no imaging matrix retain zero
offsets, including the older CS layout without an aspect-ratio operand. Other
matrix-free layouts, conflicting offsets and singular or excessive coordinates
reject the entire transaction.

An absent `Bh` denotes a centered focus and is inserted when needed, preserving
private comment prefixes. Exact polar no-ops keep original source precision.
Only the focus operands change: stops, sampled ramps, geometry, named resource
definitions and unrelated bytes remain intact. Procedures and embedded documents
are not interpreted. Output growth remains bounded by the native byte limit.
The host must regenerate the PDF appearance and flattened effects after editing.
For a local edit, first isolate the resource on selected live shapes as described
below. Relative CC placement can be edited independently through `setLiveShapeGradientPlacement`;
arbitrary affine gradient editing and Illustrator reopening remain separate work.

The dedicated corpus checker edits all radial resources across the same 37
pinned files. An independent parser verifies 45 printing instances and 173
authoring notes, with exact preservation outside the focus operands.

### Selected live-shape gradient resources

`AiNativeDrawing.isolateLiveShapeGradient(shapes:, sourceNameBytes:, nameBytes:)`
gives a selection its own copy of a named resource. The resulting drawing can be
passed to `AiNativeGradientResources.decode` before calling `replaceStops` or
`setRadialFocus` on the new definition. Those global operations then affect only
the selected users of that copy. This covers all occurrences of the source name
within each selected object, including fills, strokes and private notes; it does
not select an individual appearance part.

The editor copies the complete definition in each matching counted `Bn` setup
bank and increments that bank's count. Printing/nonprinting placement, ramps,
fallback stops and original definitions are retained. Matching known styles are
copied once per source style, receive unused names and are bound only to selected
`XW` references. Original styles, swatches and unselected object bytes remain
unchanged. Geometry, focus, colors, artboards and bounds initially stay identical.

Both names are nonempty raw byte strings. The new name must differ from the
source and be unused by every parsed definition and instance, including dangling
references. Names are escaped without assuming a character encoding. Each
selected shape must own a matching printable gradient and, if present, a matching
known style. The same five live-shape families and resolved drawing/style
dependencies required for native transformations apply. Missing or inconsistent
bank counts, multiple matching definitions within one bank, mixed same-name
linear/radial kinds, unresolved appearances and excessive output reject the
transaction. Embedded documents, procedures and literal arrays/dictionaries
cannot supply executable bank counts.

For a radial selection, using names encoded with `dart:convert`:

```dart
final AiNativeDrawing isolated = drawing.isolateLiveShapeGradient(
  shapes: [drawing.liveShapes.first],
  sourceNameBytes: drawing.gradients.first.geometry.nameBytes,
  nameBytes: latin1.encode('Selected gradient'),
);
final AiNativeGradientResources resources = AiNativeGradientResources.decode(
  records: isolated.records,
);
final AiNativeGradientDefinition definition = resources.definitions.firstWhere(
  (definition) => latin1.decode(definition.nameBytes) == 'Selected gradient',
);
final AiNativeGradientResources focused = resources.setRadialFocus(
  definition: definition,
  angle: 37,
  length: 0.375,
);
```

After a visual edit, regenerate PDF appearances and dependent previews before
saving through `AiNativeData.replace`. Plain-path selection, arbitrary appearance graphs, resource deletion and Adobe reopening
remain separate work.

The pinned CC linear/radial corpus selects three of fifteen and three of nine
shapes respectively. Five variants cover isolation alone, selected colors and
selected radial focus. Independent parsing checks original resources/styles,
new bindings and every selected/unselected body command. All four native SVG
comparisons are pixel-exact.

### Relative CC gradient placement

`AiNativeDrawing.setLiveShapeGradientPlacement(shapes:, nameBytes:, originX:,
originY:, angle:, length:, aspectRatio:)` edits every occurrence of one named
gradient inside the selected live shapes. It changes the native relative
parameters and printable geometry together, including copied known styles and
private nonprinting notes. Original shared styles, other objects, source resource
definitions, colors, ramps, native shape parameters and path coordinates remain
unchanged. Accumulated `Bg` matrices and `CAIGradientTformMatrix` records are
retained; this operation changes the paint inside the object.

Angles are in degrees within -360..360, counterclockwise in drawing coordinates.
Length and aspect must be positive, with finite bounded values throughout.
Linear gradients require `originY: 0` and `aspectRatio: 1`: the x origin and
length are fractions of the shape's extent along the chosen gradient angle.
For radial gradients, the origin is measured from the center of the shape in
fractions of its width and height; positive y points downwards. The radius is
`length * sqrt((width * (originX - 0.5))² +
(height * (originY - 0.5))²) / sqrt(2)`, before applying angle, aspect and the
retained object transform. Zero-radius or numerically singular results reject
the edit.

The editor removes the accumulated object's linear transform before measuring
the appropriate axis-aligned or angle-aligned bounds. Cubic extrema and the
native `v`/`y` shorthand curves are measured exactly, rather than using control
point boxes. Existing printing geometry must agree with the source relative
parameters before it is rewritten. Radial edits replace the single `Bm` matrix
and recalculate Cartesian `Bh` offsets while retaining the polar focus. Linear
edits retain each stop interval and rebuild the overall matrix, strips and both
exterior caps. Coverage comes from the fixed artwork bounds, with inherited
stroke width/miter reach and antialiasing margins. Repeated placements do not
recursively enlarge previous printing rectangles. Subsequent `replaceStops`
edits can repartition those strips normally.

```dart
final AiNativeDrawing placed = drawing.setLiveShapeGradientPlacement(
  shapes: [drawing.liveShapes.first],
  nameBytes: drawing.gradients.first.geometry.nameBytes,
  originX: 0.15,
  originY: 0,
  angle: 37,
  length: 0.75,
);
```

This requires the CC relative layout, flag-one clipped printable appearances,
resolved stroke state, identity-matrix flag-two style notes and the same qualified
live-shape dependencies as other native edits. Linear sources require one `Xm`
and complete, aligned `Bm` intervals; their printing matrices must be contiguous.
Mixed same-name kinds/intervals, legacy geometry, unclipped appearances, stale
focus or placement caches and unsupported dependencies reject the transaction.
Exact no-ops retain the original snapshot. New source bytes remain bounded.
The host regenerates PDF appearances and previews before saving.
General affine shear/reflection of paint,
plain-path selection and arbitrary appearance/effect graphs remain further work.

The dedicated corpus covers the 15 linear and nine radial CC shapes with full
and partial selections, including partial placement after object rotation and
uniform scaling. Independent parsing checks all retained geometry/metadata,
new style bindings, relative parameters, focus offsets and strip/cap coverage.

## Native mesh inventory

`AiNativeMeshes.decode(records:, bodyOnly:)` reads explicit `/Mesh X!` packets
through their matching `/End X!`. The default includes setup/resource artwork;
`bodyOnly: true` restricts inspection to the native drawing body. Procedures,
PostScript literal arrays/dictionaries, strings, binary payloads and embedded
documents do not supply mesh openings. Both ordinary and private packets retain
original source spans; each field preserves its `AiNativeInstruction` and exact
operand tokens.

The qualified schema is version 2 with `/Cartesian` topology. `size` and each
patch's `firstIndex`/`secondIndex` use the original index axes rather than
guessing screen row directions. The reader requires unique, in-range patches
covering the declared grid and four `/N` corners per patch. Allocation is bounded
by actual token counts, never by an unchecked product of grid dimensions.
Missing declarations, repeated positions, truncated nodes, mixed command
representations and incomplete packets throw `FormatException`. Other schema
versions and topology types throw `UnsupportedError`; the owning source program
remains intact.

Patch nodes stay in cyclic source order, including `/A` anchors and `/S`
subdivision points before the first corner. Positions, both source-order
control points and weights are exposed without dropping intermediate nodes or
welding duplicated neighboring corners. Version-two corners carry explicit
opacity and unconverted color components. The initial space is DeviceGray;
each `/CS` declaration applies to following corners, including across patch
boundaries. Gray, RGB and CMYK arities and normalized components are checked.
Separation and NChannel declarations with device alternatives expose immutable
`inks` with original name bytes, alternative components and declared component
counts. `deviceName` remains null for named spaces. Other unknown spaces retain
their entire declaration with a null `componentCount`; their node tail is still
decoded without interpreting or converting their components. The `R` record,
non-unit weights and unknown fields are retained
without claiming their evaluation.

`inks` retains lexical declaration order. In NChannel that order is reversed
when the operand stack supplies the color components. Each corner's `inkTints`
pairs ink definitions with tint values in component order. For example, lexical
Yellow/Magenta/Cyan declarations and `[0.14 0.79 0.67]` components mean Cyan 0.14,
Magenta 0.79 and Yellow 0.67. Separation has one component. This accessor returns
an empty list for process/unknown spaces and non-corner nodes. It does not
convert arbitrary spot inks to their device alternatives.

The dedicated SHA-256-pinned CC 21.1 example has 180 patches, 720 colored corners,
eight additional anchors and eleven subdivision points. An independent Python
reader extracts the native stream with pypdf/zlib and compares every field,
source span and node. It verifies three gray, 671 CMYK and 46 NChannel corners;
the NChannel declarations contain either Black or Yellow/Magenta/Cyan ink
alternatives. The recovered 3,609,317 native bytes match exactly. The PDF includes
a type-seven shading. A separate independent check decodes its 1,747 tensor
patches and verifies all 46 named-ink corner assignments against the stored
CMYK components, within half an 8-bit component step. This checks corner colors,
not interpolation or rendered native mesh geometry. The external artwork is
ignored and excluded from publication; its manifest records the public source
and absence of an explicit redistribution license.

`mesh.vertices` indexes the Cartesian grid's logical vertices. Corner order
maps a patch `(i, j)` to `(i, j)`, `(i+1, j)`, `(i+1, j+1)`, `(i, j+1)`.
Intermediate nodes do not change that order. A vertex retains all one, two or
four source occurrences and their distinct handles. Duplicate positions must
agree exactly; a mismatch throws rather than welding by proximity. The CC
fixture independently verifies all 208 logical vertices and their ownership.

`paintVertices(mesh:, changes:)` accepts `AiNativeMeshVertexPaint` selections
with an explicit `AiNativeMeshProcessColor`, named-ink `tints`, and/or normalized
opacity. Gray, RGB and CMYK input has an explicit model and component count; no
color conversion is implicit. Every selected vertex's occurrences change together. Other native
colors, weights, geometry and intermediate nodes stay intact. A new `/CS` switch
is restricted to the changed corner, restoring the previous declaration for
subsequent nodes, including named-ink alternatives. Already local switches are
reused during repeated edits. Opacity-only changes preserve color syntax exactly;
qualified exact no-ops return the same snapshot.

`tints` replaces components in `vertex.corners.first.inkTints` order and is
mutually exclusive with `color`. Every corner copy must use the same ordered
named inks, including byte-exact names and equal device alternatives; mismatches
reject atomically. Tint edits update only changed numeric tokens, preserving
all `/CS` declarations and unchanged component spelling. The immutable input
must have the source component count and finite values between zero and one.
Process colors and unresolved spaces reject tint editing instead of guessing
an ink mapping.

```dart
final AiNativeMesh mesh = meshes.meshes.single;
final AiNativeMeshVertex vertex = mesh.vertices.singleWhere(
  (vertex) => vertex.firstIndex == 1 && vertex.secondIndex == 1,
);
final AiNativeMeshes edited = meshes.paintVertices(
  mesh: mesh,
  changes: [
    AiNativeMeshVertexPaint(
      vertex: vertex,
      color: AiNativeMeshProcessColor(space: .rgb, components: [0.8, 0.2, 0.1]),
      opacity: 0.7,
    ),
  ],
);
```

Only direct printable body meshes with independent appearance ownership are
qualified. Resource/private copies, version-dependent artwork, unknown mesh
fields, unqualified source color spaces when recoloring, dependent object
dictionaries and unresolved parent appearances reject the transaction. Plain
group `9 () XW` markers carry no extra appearance and remain supported.
Foreign or repeated selections reject atomically; output remains bounded by the
source program's limits. The corpus makes five selected vertex edits covering
14 corner occurrences, a separate whole-mesh opacity edit covering all
720 corners, and a named-ink edit of two vertices covering eight corner copies.
An independent reader checks every affected/unaffected color and
ink declaration, every retained geometry token, and exact surrounding bytes.
Global and body-only inventory are also compared after mark-based setup ramps.

These are native authoring edits. The host supplies matching PDF appearances and
previews before saving. Mesh interpolation, tessellation and color management
belong to the application. Geometry/topology editing, broader mesh layouts,
older versions and Adobe reopening remain further work.

## Native raster images

`AiNativeRasters.decode(records:, bodyOnly:)` reads embedded binary `XI` image
sections in setup resources and artwork, including private `%_` records. Each
immutable image retains its source spans, matrix, image-space bounds, dimensions,
component depth, process channel count, producer flags and optional alpha plane.
The historical `h` operand is the number of columns and `w` the number of rows,
as confirmed by independent image decoding and the original PDF. Color samples
are interleaved; alpha is a separate plane after all color samples. Packed rows
retain byte padding. Supported depths are 1, 2, 4, 8 and 16 bits per component.
Decoding performs no profile conversion or external-file access.

The tokenizer recognizes the `XI` invocation inside a declared raster data block
and leaves its samples opaque. It derives their size from the validated header,
including alpha, before checking the exact `%%EndData` boundary. Observed CS/CC
counts may omit alpha or include one extra byte. These specific variants are
accepted only with an exact geometry-derived boundary; arbitrary count repairs
and searching the pixels for an end marker are forbidden. Private binary bodies
stay opaque before and after native comment projection, even when pixels contain
PostScript syntax, `%_` prefixes or fake end markers. Corrupt text-transcoded
samples reject native parsing instead of becoming drawing commands. Container
DSC inspection shares the same geometry-bounded skip for recognized public and
private raster sections, including separate alpha planes. Generic DSC data
retains its original declared-count behavior outside these sections.

`rasters.translate(images:, deltaX:, deltaY:)` edits both `XI` and redundant `Xh`
placement offsets in one immutable snapshot. Samples, file links, pixel UUIDs,
rotation/scale metadata and other images stay unchanged; DSC drawing bounds expand
conservatively. Images must belong to the snapshot and have consistent known
placement commands. Enclosing clipping paths, groups and artboards are separate
objects. This operation does not replace pixels, resize images, fetch linked
`XF` data or regenerate image caches.

`rasters.replacePixels(image:, samples:)` accepts owned `AiNativeRasterSamples`
with explicit dimensions, component depth, process channels, color bytes and
optional alpha bytes. It replaces one image atomically; byte-identical planes
and layouts return the original snapshot. Sample buffers must contain complete
rows and valid byte values, including padding. No resampling or color conversion
is implicit: callers supply the final pixels. Sixteen-bit samples are big-endian.

A resolution change compensates both `XI` and `Xh` matrices so the placed image
extent, reflection and shear remain unchanged. Image bounds and dimensions,
depth, process flags, `XN` and the exact binary DSC count update together. `XG`
retains the source path and records the embedded copy as modified. An attached
`ArtDictionary` is recognized only immediately after the raster, optionally
following bare `N`; unrelated later object records are not borrowed.

Existing `AI24 ImageRawDataUUID` and `AI24 ImageAlphaRawDataUUID` entries receive
fresh UUIDs when their respective planes or sample layouts change. Other images
sharing the old UUID remain unchanged. Absent identity entries stay absent;
malformed existing identities reject the edit. Stable object metadata, including
names, rotation and original-scale records, is preserved. These identity policies
are based on observed CC/CS records; they have not been qualified by reopening in
Adobe Illustrator. They do not regenerate opaque effect or plug-in caches.

Editing requires a qualified native process-color layout. Alpha
authoring is limited to the observed extended CS/CC headers; legacy 20-operand
headers can retain or replace opaque/stencil pixels but do not gain invented
alpha semantics. Use `AiNativeData.replace` with matching host-supplied PDF
artwork to save the edited program and discard stale document thumbnails. Editing setup resources or
private originals does not regenerate dependent opaque appearances.

`rasters.setPlacement(image:, matrix:, rotationRadians:)` sets the complete affine
placement without resampling. Both `XI` and `Xh` matrices update atomically. Pixel
dimensions, source links, sample UUIDs, color/alpha planes and original-scale
metadata remain unchanged. For `[a, b, c, d, tx, ty]`, an embedded pixel `(x, y)`
maps to `(a*x - c*y + tx, b*x - d*y + ty)`. This supports host-composed resizing,
rotation, reflection and shear. The matrix must be finite and nonsingular; all
mapped corners must remain representable within the native coordinate limit.

`image.frameRotationRadians` exposes the independent `BBAccumRotation` editing
frame angle. The matrix does not determine this metadata uniquely. The setter
therefore requires an explicit nullable `rotationRadians`: a finite angle within
−2π to 2π updates/adds the field, while null preserves its absence and rejects an
existing field. Changed angles use six decimal places, matching observed Adobe
string records. Existing String, UnicodeString and Real field types are retained;
new fields use String. Split strings update atomically. Qualified no-op edits
retain exact source spelling, including higher-precision unchanged angles.

Geometry edits accept only known identity/name fields, original scale and frame
rotation. Unknown cache/relationship fields, including fuzzy-mask and accumulated
shear metadata, reject the edit. A matrix can express shear without synthesizing
those unqualified editing caches. Enclosing groups, clipping paths, effects,
resource owners and artboards remain separate objects whose synchronization is a
host responsibility. For printable body images, existing DSC bounds expand to
include all four new corners and never shrink. Setup/private image edits do not
expand printable bounds. Nested documents, procedures and deferred DSC headers
remain intact. `AiNativeEditor.includeBoundsEdits` exposes the same conservative
extent policy for other qualified editors.

## Native linked placements

`AiNativePlacements.decode(records:, bodyOnly:)` reads `%AI5_BeginPlace` sections
with a backtick placement command and matching `~` terminator. Immutable objects
retain their affine matrix, local rectangle, file type, producer extensions,
path bytes, optional relative directory, saved preview and attached object
dictionary. Paths are decoded from PostScript escaping without guessing their
encoding. Public and private `%_` sections must be internally consistent.

The shared tokenizer and DSC reader bound `%AI26_BeginPlacedObjectPreview` from
its five integer fields: width, height, row bytes, bit depth and format. Exactly
one space separates the last field from the binary samples. The computed row
length must meet the closing marker exactly; neither reader searches pixel bytes
for a delimiter. Numeric header prefixes, row padding and fake native/DSC syntax
inside samples stay opaque. Unknown color layouts remain inspectable when their
byte boundaries are valid. `preview.toSamples()` explicitly converts the observed
32-bit, format-17 straight ARGB layout into RGB and separate alpha planes; it
does not premultiply colors or treat the preview as the full-resolution link.

`placements.translate(objects:, deltaX:, deltaY:)` moves qualified CC raster
placements and expands DSC bounds while retaining paths, preview rows and object
metadata. Editing requires file type 1, extensions `4 4 0`, matching `IncludeFile`
and path references, a nonsingular matrix and the observed versioned relative-path
and preview sections. Unknown flags, comment semantics or version branches reject
editing; their source remains available for preservation. Enclosing groups,
clipping paths and artboards remain separate objects.

`placements.embed(object:, samples:)` accepts `AiNativeRasterSamples` explicitly
resolved and decoded by the host. The kit does not access the filesystem, resolve
URLs, guess file formats or convert profiles. It replaces the link and preview
with a binary native `XI` raster, retaining the placed extent through a resolution
change, reflection or shear. The qualified placement's local y axis points down.
The newly composed raster origin snaps within one nanopoint of whole-point
coordinates to avoid extra pixel rows from ruler-origin cancellation. Scale,
rotation, shear and existing embedded-raster transforms remain unchanged.
Object names, identities, rotation and original-scale fields stay attached;
unqualified dictionary fields reject conversion. A `DocumentFiles` dependency is
removed only when no other native string or `IncludeFile` reference uses the path.
Shared references retain it. Native output and sample sizes remain bounded.

The host can deliberately pass `object.preview!.toSamples()` as a reduced-resolution
fallback. That choice is never implicit. The application regenerates matching
appearances after embedding.

`placements.relink(object:, pathBytes:, relativeDirectoryBytes:, preview:)`
changes one qualified raster reference in an immutable snapshot. All arguments
are explicit: a null relative directory removes that versioned section, and a
null preview removes the saved picture. A non-null preview must contain eight-bit
RGB and optional straight alpha; opaque alpha is authored as 255. New rows use
the observed tightly packed ARGB, format-17 layout. The host supplies final
preview pixels; decoding, resizing and color conversion are not implicit.
Equivalent paths, relative directories and preview pixels return the original
snapshot, including original padding and numeric spelling.

The path operand, `IncludeFile`, relative directory, preview and `DocumentFiles`
declarations update together. Paths retain caller-selected encoded bytes; native
string operands use octal quoting and DSC filenames stay on one line. Empty
filenames, ASCII controls, leading/trailing ASCII spaces and the reserved
`(atend)` marker reject authoring. Non-ASCII bytes are never Unicode-trimmed.
Relative directory strings are quoted independently, so their bytes cannot
introduce native syntax. Declared files unrelated to the edited link stay listed.
Shared uses retain the old path; the new path is not duplicated. Header/trailer
declarations and continuations are updated, while nested document and procedure
comments remain untouched. A missing declaration is added after the native
header, or in an explicitly deferred trailer; a missing required boundary rejects.

Relinking preserves the native matrix, local rectangle, numerical source spelling
and stable object metadata. The rectangle is a placed coordinate space, not an
inferred external pixel size. A host choosing a different image retains that
extent; this operation does not infer new geometry from resolution or metadata.
Unknown placement/object-cache semantics reject the edit. Native preview output,
dependency declarations and the complete edited source remain bounded. Global
PDF/XMP dependency manifests are preserved, not regenerated by this native edit.
Use the separate `AiXmpMetadata` API below to update explicitly mapped catalog
references after saving the native/PDF change.

`object.validateRasterLayout()` exposes qualification separately, and
`object.rasterMatrix(width:, height:)` supplies an immutable pixel-to-native
transform for host adapters using the same placed extent and origin policy.
The host resolves file paths and supplies decoded pixels; AiKit never opens links.
External PDF/EPS placed artwork, older `XF` links, opaque effect-cache
regeneration and Adobe reopening remain unqualified.

`placements.setPlacement(object:, matrix:, rotationRadians:)` provides the same
explicit affine/frame edit for qualified raster links. A linked matrix maps its
existing local rectangle with `(a*x + c*y + tx, b*x + d*y + ty)`; its local y axis
points down. The local rectangle, file path, relative directory, saved preview
and declarations remain unchanged. `object.frameRotationRadians` reads its frame
metadata. The host supplies a regenerated PDF appearance when saving the native
link. Resizing pixels, changing a source file and
changing its placed geometry are separate operations.
Catalog XMP placement-resolution fields are preserved, not recomputed by the
native geometry edit; update them separately when the host maintains that data.

### Catalog XMP dependencies

`AiXmpMetadata.fromPdf(document:)` reads a PDF catalog's UTF-8 XML metadata stream;
`parse(source:)` reads a standalone packet. An absent catalog packet returns null.
The immutable `resources` inventory includes top-level `xmpMM:Manifest` references
and `xmpMM:Ingredients` items for the current document. Namespace URIs, rather than
prefix spellings, identify fields. Manifest `rdf:Seq`/`rdf:Bag`, ingredient
`rdf:Bag`, inline `rdf:parseType="Resource"`, nested `rdf:Description`, abbreviated
attribute fields and simple `rdf:resource` values are supported. History,
`DerivedFrom`, pantry records, other subjects and page/image packets are separate
metadata and are not interpreted as current placed-object references.

Each resource exposes its kind, inventory index, exact Unicode path, optional
document/instance IDs and optional manifest link form. No URI unescaping,
filesystem lookup, path normalization or native-byte encoding guess is performed.
The inventory order is not a native placed-object identity. Shared resources and
embedded artwork can also occur in these arrays; the host must establish the
mapping and select every reference affected by its edit explicitly.

`relink(resources:, filePath:, documentId:, instanceId:)` replaces the selected
resource structures together. Null identifiers remove stale identities; supplied
IDs must describe the new asset. Old `alternatePaths` are cleared. Qualified
edits accept only path, document ID, instance ID and an ordered list of plain
fallback paths. Managed, extended or part-specific reference fields reject the
edit instead of silently losing their semantics. Other manifest fields, including
link form and placement resolution, remain unchanged and require host policy if
the corresponding placement changes. Document IDs, save dates, pantry entries
and history are not synthesized.

Only the selected resource elements are reserialized. All surrounding packet
text, comments, prefixes, padding and unknown metadata stay exact, including
unselected identical paths. No-op edits return the original snapshot. UTF-8 BOMs
are retained. XML line endings and literal attribute whitespace follow XML 1.0
value normalization without changing retained source text. `AiXmpLimits` bounds
UTF-8 bytes, depth and events/attributes before tree construction, and bounds the
rewritten packet. DTDs, undefined entities, invalid characters, non-UTF-8 XML
declarations, malformed XML and ambiguous dependency structures reject.
This is a qualified dependency reader/editor, not a complete RDF/XMP validator;
unrelated property schemas are preserved without interpretation.

After synchronizing native artwork and PDF pages, call
`changedMetadata.writeTo(document: savedDocument)`. This explicitly replaces the
catalog packet using fresh stream/catalog objects; shared original page/image
metadata and the native data remain unchanged. Old unreferenced objects are
retained, so changing a path is not a redaction operation. These APIs do not
currently read or rewrite XMP embedded inside a PostScript program.

## Source-backed editing

`AiProgram.decode` reads body instructions outside the prolog, setup, procedures,
embedded documents and opaque sample bytes. A recognized raster `XI` invocation
inside DSC data is retained separately from its pixels. It exposes source spans, nested native
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
This low-level method cannot establish native/PDF equivalence.
Renaming a native layer does
not change painted geometry, so the existing appearance can be reused for that
operation. Mixed native block families on one owner are rejected for rewriting.
New blocks use PdfCore allocation, reserving existing dangling references.

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
PostScript interpreter or native rendering engine.

## Legacy PostScript

DSC inspection skips declared binary/data sections and embedded documents before
collecting title, creator and bounds. Continuations are retained; `(atend)` values
resolve from later concrete declarations. `HiResBoundingBox` takes precedence.
DOS EPS PostScript/preview ranges are validated and the entire envelope is kept.
Encoding returns the exact original source bytes, including unknown data.

Native binary raster counts may omit alpha or include an extra byte. Inspection
uses the shared raster geometry reader to skip the actual complete sample planes,
including private `%_` images. Fake DSC declarations within these bytes cannot
change document metadata or establish Illustrator provenance. The preceding
raster header is bounded by `maxCommentBytes`, the PDF object limit for tokens
and the PDF depth limit before the sample boundary is inspected.

Placed previews likewise use checked header-derived byte boundaries and keep
their ARGB rows opaque during DSC inspection.

For a damaged or unsupported native raster or preview boundary, `AiPostScriptDocument.dscIssue`
records the declaration's byte offset relative to `postScriptBytes` and a reason.
Only earlier comments are returned; the decoder does not search subsequent image
bytes for a plausible delimiter or claim to have read trailer metadata. Source
bytes, including a DOS EPS envelope, remain available for exact encoding.
A null issue means this inspection reached the end of the section, not that
PostScript execution or all native authoring semantics are supported. Invalid
generic DSC counts and embedded-document nesting still reject decoding.
`tool/inspect_ai.dart` reports partial metadata explicitly and exits unsuccessfully.

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

The [external corpus guide](../test/corpus/README.md) lists the executable checks,
pinned fixtures and independent readers. Native extraction, edits, preservation
and serialization have separate tests. External SVG rendering of edited native
programs can additionally check geometry without introducing a renderer in AiKit.

`ai_native_test.dart` checks host-supplied PDF pages with plain, zlib and Zstandard
native envelopes, shared owners, retained private metadata and an opaque native
appearance state. Saving and reopening must retain both supplied representations;
AiKit does not infer their visual equivalence. Original snapshots stay immutable.

The former native-to-PDF exporter, mesh interpolation and their dedicated visual
suites were removed to enforce the format-package boundary. Their previous
rendering results are historical and are not current compatibility claims.
There is no Adobe Illustrator reopening validation and no Focale integration
acceptance yet. Preserved opaque content is not claimed to be natively editable.

## References

- [Adobe XMP resource-reference fields](https://github.com/adobe/xmp-docs/blob/e2573ad7e7959e657b1aed704546e19319cb4f5d/XMPNamespaces/XMPDataTypes/ResourceRef.md)
- [Adobe XMP media-management properties](https://github.com/adobe/xmp-docs/blob/e2573ad7e7959e657b1aed704546e19319cb4f5d/XMPNamespaces/xmpMM.md)
- [Adobe DSC specification](https://web.mit.edu/PostScript/Adobe/Documents/5001.DSC_Spec.pdf), pages 45–46: counted data can include its invoking operator.
- [Adobe PDF Reference 1.7](https://opensource.adobe.com/dc-acrobat-sdk-docs/pdfstandards/pdfreference1.7old.pdf), section 4.6.3: tensor-patch control ordering and bilinear PDF mesh colors.
- [Adobe's AI format overview](https://www.adobe.com/creativecloud/file-types/image/vector/ai-file.html)
- [Inkscape extension-ai corpus](https://gitlab.com/inkscape/extras/extension-ai)
- [Native data container observations](https://gitlab.com/inkscape/extras/extension-ai/-/blob/1a5f42a0b0407fc869e032420570682048810108/docs/specification_amendments/compression.md)
- [Native hierarchy observations](https://gitlab.com/inkscape/extras/extension-ai/-/blob/1a5f42a0b0407fc869e032420570682048810108/docs/specification_amendments/hierarchy.md)
- [Native text structure observations](https://gitlab.com/inkscape/extras/extension-ai/-/blob/1a5f42a0b0407fc869e032420570682048810108/docs/specification_amendments/text_documents.md)
- [PROOF point-text writing and recomposition experiments](https://github.com/vurglepuddle/PROOF/blob/d822dc5dea265675a0fd5dec550e3e0dcd5988f0/doc/PROOF-ai-native-records.md#point-type-written-2026-10-23)
- [PROOF placed-file and preview observations](https://github.com/vurglepuddle/PROOF/blob/d822dc5dea265675a0fd5dec550e3e0dcd5988f0/doc/PROOF-ai-native-records.md)
- [Document/artboard observations](https://gitlab.com/inkscape/extras/extension-ai/-/blob/1a5f42a0b0407fc869e032420570682048810108/docs/specification_amendments/document_data.md)
- [Live-shape structure observations](https://gitlab.com/inkscape/extras/extension-ai/-/blob/1a5f42a0b0407fc869e032420570682048810108/docs/specification_amendments/live_shapes.md)
- [CC gradient observations](https://gitlab.com/inkscape/extras/extension-ai/-/blob/1a5f42a0b0407fc869e032420570682048810108/docs/specification_amendments/gradients.md)
- [Adobe Illustrator 7 file format specification (Adobe document mirror)](https://13thmonkey.org/documentation/fonts/AI7FileFormat.pdf)
- [Zstandard format specification, RFC 8878](https://www.rfc-editor.org/rfc/rfc8878.html)
- [PdfCore reference](../../PdfCore/docs/PDF.md)
