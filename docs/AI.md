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
a global swatch changes all its users. Isolating a single object, adding/removing
resources, hard stops, meshes, gradients along/across strokes and flattened appearance
regeneration remain further work. `AiNativePdf` synchronizes supported classic
gradient fills and page-aligned strokes; other gradient appearances still require
host rendering. Definition-local comments are regenerated with the edited resource;
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
This low-level method cannot establish native/PDF equivalence. Renaming a native layer does
not change painted geometry, so the existing appearance can be reused for that
operation. Mixed native block families on one owner are rejected for rewriting.
New blocks use PdfCore allocation, reserving existing dangling references.

### Native printable paths to PDF

`AiNativePdf.render(program:, bounds:)` creates a one-page PDF from the native
printable instruction stream. `bounds` is an explicit positive-size rectangle in
native y-up coordinates. It does not guess an artboard from artwork bounds or
paint private authoring outlines a second time. The supported subset includes
gray/RGB/CMYK paths, curve shorthands, fill/stroke attributes, dashes, winding
rules, ordinary/compound groups, clipping groups and layer visibility/printing.
Native drawing state persists across group boundaries until changed.

The five-value `Xy` form supports opacity, the sixteen standard blend modes,
group isolation and knockout, with its shape flag zero. A `6 () XW` modifier
applies the blend state captured at `Xd` to the preceding path or group. Both
`Xd` flags must be zero or one; they do not repaint an already expanded object.
A group without `Xd` uses the current state. A `9 () XW` plain-group marker
introduces no independent opacity. Fill and stroke are
painted inside one transparency form before applying object opacity, avoiding
double compositing where they overlap. Compound paths use their final paint
state once, including contours nested in ordinary `u`/`U` groups. Later state
changes cannot rewrite that captured compound paint. A clip persists only inside
its enclosing mask group; translucent
paint on the clipping path itself is rejected. Nonprinting and hidden layers
are validated even though they do not paint.

Classic linear and radial gradient fills use the retained absolute `Xm`/`Bm`
printing matrices, preserving transformed axes, elliptical aspect ratios and
focal offsets without approximating shape bounds. Linear fills require one
overall `Xm`, or a single full-interval `Bm` for a two-stop resource. Radial fills
require one `Bm`; `Bh` angle and distance determine the unit focal point.
The `Bg` clipping flag controls the fill clip, and `BB` can add a solid stroke
after that clip is restored. Missing or singular printing geometry rejects export.
A compound's final contour can carry the shared gradient: all contours then
clip one shading, preserving holes under the native nonzero or even-odd rule.
The optional solid stroke covers every contour after that shading clip is
restored; object opacity applies to the complete fill/stroke once. A complete
`Bb`/`Bg`/`BB` appearance note with no painted path draws nothing and cannot leak
into the next object. Its unused resource name does not require rendering.

Unexpanded `1 Bb` gradient strokes retain native path geometry, width, dashes,
caps, joins and miter limits through PDF shading patterns. They require one
`S`/`s` appearance, `Bg` flag 1 and `BB` flag 1 or 2; flag 2 closes the stroke.
Linear and radial fields use the same absolute printing matrices and interpolation
as fills. A local Form XObject establishes the pattern's initial coordinate
space so that page origins, artboard cropping and enclosing transparency groups
move the path and gradient together. Stop opacity affects only this stroke;
object and group opacity remain separate. Combined `B`/`b` paints inside a
stroke-gradient instance reject export: separate native fill and stroke
appearances are required. This covers gradients applied across page coordinates,
not gradients following or crossing a curved centerline.

Color stops become shared PDF functions in their process color space. Gray can
join RGB or CMYK stops without a color-profile conversion; gray in an explicitly
CMYK document becomes black ink only. RGB alternatives can join CMYK in a CMYK
document. Other mixed/named colors require a host color policy. Midpoints at or
above 50% use a power curve; those below 50% use its mirrored form. Constant
endpoint intervals cover stops that do not reach zero or one hundred percent.
Stop opacity uses the same interpolation and geometry in a separate DeviceGray
soft mask, independent of the painting color space and object/group opacity.
This reauthors vector shading functions from the stops; it does not quantize
colors through the retained byte ramp or execute its printing prolog.

`AiNativePdf.save(source:, program:, pageBounds:)` rebuilds compatibility pages
and replaces their native data together. It requires a PDF-backed source with
one extracted native program, including programs aliased by multiple owners.
Provide one native drawing rectangle for every existing PDF page; dimensions
must match each MediaBox, with ordinary page units. Existing page origins,
page trees, metadata, annotation references, original resource bindings and
other producers' private data remain intact. Native blocks retain their original
compression family and all owners receive the same program. Stale PDF page
thumbnails and native thumbnail blocks are removed. The source remains unchanged
if compilation, page mapping or allocation fails. Unreferenced old objects remain
in the graph; this is not data redaction.

The edited program must already contain synchronized printable expansions, as
produced by supported live-shape translations. `XW` known-style markers require
a bound live shape with an existing printable appearance. This method does not
regenerate those expansions from opaque authoring records. Gradients along/across strokes,
coincident stops, multiple independent appearances within a gradient,
newer interpolation methods, text,
rasters, patterns, spot colors, overprint, embedded drawing data, nested compound
mask groups and unknown drawing commands currently reject the entire export. This
includes unsupported commands inside hidden layers. No Adobe prolog executes.

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
PostScript interpreter; `AiNativePdf` separately renders its supported declarative
printable subset.

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
content edits insert non-BMP characters, a forced break and a paragraph across
all native stories; the independent checker reconstructs run ownership per UTF-16 unit and compares
the entire engine tree, including untouched stories and removed caches. These
edited native programs are not combined with their original PDF previews.
Sixty additional native edits change character and paragraph features separately,
including twenty paragraph edits across newly inserted forced-break spans;
the independent checker verifies complete trees, UTF-16 selection coverage,
inherited run ownership, both size fields and fresh inline UUIDs. Neither the
original resources nor unselected feature values may change.
Sixty-four synthetic font registrations across the 32 engine documents check
PostScript/TrueType identifiers, version and signed variation fields, fresh UUIDs
and display-list updates. The independent decoder requires exact semantic
preservation outside the appended entries. These identities do not claim the
existence of installed font programs or newly rendered glyphs.
A separate Linux integration probe used TextShaperLib revision
`b8918526633258a626dec08e6fc591712509fc04` and its original `curves.otf` fixture.
It registered `FocaleOutlineFixture`, assigned it at 32 points, replaced the
story with `fi O`, and shaped three glyphs at UTF-16 clusters 0, 2 and 3.
AiKit retained the resulting source-segment positions 0, 9.6 and 32 points,
plus the final CR at 54.4 points. The independent ATE reader verified the
registered font, selected style, source ranges and positions. This exercised
host composition without adding a native engine dependency to AiKit; it did not
write GlyphStrike caches or a PDF appearance.
Seventeen point/area stories also have their frame/line/segment positions
reauthored through the composition API. The independent reader compares absolute
origins (allowing only 1e-8 point floating-point regrouping), source ranges, bounds,
selection metrics and fourteen automatic-hyphen insertions. Other engine data
must remain identical. Three path-layout writes explicitly reject missing
per-glyph geometry. These are source-position checks; old glyph caches are not
represented as newly shaped text, and no new rendered appearance is claimed.
Twenty-six native frame resources are translated across the CS/CC text fixtures.
The independent reader requires unchanged engine trees except for their matrix
offsets and checks all thirteen accompanying confinement paths. The transformed
text fixture also moves only its first linked-area frame: exactly one confinement
path changes, with the other fifteen frame resources and their paths retained.
The body comparison checks unrelated operators and metadata as well as native
text references; local cached glyph data remains unchanged.
Newly shaped text,
altered text appearance and Adobe reopening remain outside this check.

Unit tests cover compressed and uncompressed envelopes, split markers, owner
aliases, independent page programs, limits, malformed syntax, atomic edits and
explicit geometry rejection. A VM test renders authored AI7 using Ghostscript
and checks visible, hidden and nonprinting layer behavior. That test explicitly
skips if Ghostscript is unavailable. No Adobe Illustrator installation was used;
native reopening and complete editing compatibility remain unverified.

`check_native_pdf.dart` regenerates and translates eight fixtures.
Six have original PDFs: Poppler compares their original and explicitly shifted
artwork with the rebuilt pages, while pypdf and Python zlib/Zstandard independently
recover the saved native bytes. Two native-only live-shape fixtures use the
pinned AI reader's printable stream converted through SVG and Inkscape to PDF;
private shape reconstruction is excluded because it changes expanded contours.
Two additional saves change the shared gradient resource to three RGB stops with
opacity. Their references replace only the original PDF's color/alpha functions.
All eighteen render comparisons pass at 1,200 pixels wide. The fifteen linear
instances match exactly before/after translation and recoloring. Radial outlines
retain more coordinate precision than their original PDF rectangles; their mean
channel difference is below 0.068/255, concentrated at boundary pixels. Other
means remain below 0.02/255; unchanged flat colors are required. Gradient fields
away from sharp boundaries must agree within one channel level. Native data in
the six translated and two recolored saves is decoded independently.
The moved opacity fixture has a small boundary difference
from native `756.999999999999` versus original PDF `757` coordinates. Nine further
pixel probes check whole-object fill/stroke opacity, a Multiply group, clip scope,
hidden layers and nonprinting layers. Other blend modes and Adobe reopening are
not independently qualified by these probes. Two real nonlinear swatches also
compare generated PDF function values with their independently decoded Adobe
printing samples, covering midpoints below and above fifty percent. This is
471 samples across four channels, with maximum difference below 0.5/255.
This is evidence for classic interpolation, not general color-profile equivalence.

The separate `pdf_manifest.json` adds two complete CC random-gradient drawings
and `styles.ai`, which contains an unexpanded gradient stroke. The
`check_native_pdf_compounds.dart` tool saves all three complete drawings, then
edits their six, six and two painted gradient resources respectively to three
RGB stops with opacity. Both random-gradient documents include a gradient-filled
compound used as an expanded stroke, transformed fields, appearance notes and
solid strokes over gradients. Independent Poppler comparisons against the
original PDFs, and against original PDFs with only their shading functions and
opacity masks replaced, pass at 1,920 × 1,080. All six mean channel differences
are below 0.0004/255, with unchanged flat pixels and one-level agreement inside
gradient fields. The independent reader verifies edited native stops and cached
matrix coverage; pypdf and Python zlib/Zstandard recover all six saved programs.
Eight further pixel probes require real nonzero/even-odd holes, grouped contours,
object/stop opacity, strokes outside the fill clip and nonpainting gradient notes.
For `styles.ai`, the reference retains Adobe's original shading pattern and
geometry, replacing only shared color functions and adding a stroke opacity mask.
Its mean channel differences are below 0.0001/255, before and after the edit.
`check_native_pdf_strokes.dart` and `verify_native_pdf_strokes.py` additionally
check 18 pixels for open/closed strokes, dashes, round/butt caps, cubic geometry,
linear/radial fields and object/group/stop opacity. Two whole-page comparisons
are exact after saving with different native drawing rectangles and nonzero PDF
MediaBox origins; the saved native program is independently recovered unchanged.
These are complete-page compatibility checks for these fixtures; they do not
qualify arbitrary native effects or Adobe reopening.

| Area | Current contract | Remaining work |
| --- | --- | --- |
| CC compression and blocks | Decode/rewrite plain, zlib and Zstandard native programs | Additional producer/version corpus coverage |
| Native layers | Inspect/edit names and visibility/lock/print flags | More private layer appearance semantics |
| Native records and artboards | Typed dictionaries, arrays, object records, ASCII85 resources, artboard bounds/names and scalar edits | Geometry-dependent synchronization and broader semantic models |
| Native ATE text | Stories, UTF-16 runs, font registration, style/content/feature edits, forced-break spans, host-composed point/area positions and frame/confinement translation | Shaping, glyph-cache generation, new path composition, advanced typography and synchronized text-content saves |
| Paths and live shapes | Inspect native/printable geometry; edit plain paths; translate five CC shape families with solid/gradient appearances; create AI7 paths | Resize/rotate/regenerate live shapes and synchronize remaining positional paints/effects |
| Gradients | Inspect/translate instances; isolate positional styles; replace global stops and host-composed ramps; render classic process-color fills/strokes with midpoint and opacity functions | Color-managed ramp composition, isolated object colors, hard stops, gradients along/across strokes, newer methods and meshes |
| Groups and paint | Create AI7 groups, solid process fills and strokes; render native compound paths, clipping and object/group transparency | Complete import into typed scene nodes and broader transparency fixtures |
| Meshes, effects, plug-ins, raster | Preserve exact source bytes and report unresolved operators | Typed native models, editing and serialization |
| PostScript | Bounded lexical/structural reading and self-contained subset writing | No arbitrary PostScript execution |
| PDF compatibility appearance | Regenerate supported printable paths and classic gradient fills/strokes, saving them with native data; preserve or replace other graphs explicitly | Text, gradients along/across strokes, rasters, unresolved effects and host scene integration |

## References

- [Adobe PDF Reference 1.6](https://opensource.adobe.com/dc-acrobat-sdk-docs/pdfstandards/pdfreference1.6.pdf), sections 4.6.3 and 4.9.1: shading patterns and initial form coordinate spaces.
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
