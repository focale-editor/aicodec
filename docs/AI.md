# Illustrator technical reference

This document describes how AiKit represents Illustrator data, which structures
it can edit and serialize, and what remains with the host application. Start with
the [README](../README.md) for an introduction, the [host contract](HOST.md) for
application responsibilities, and the [roadmap](../ROADMAP.md) for remaining work.

AiKit is a pure Dart format package. PdfCore handles PDF containers, ZCodec handles
native compression, and PsCore supplies the Adobe text-engine grammar shared with
PsdKit. Consumers normally import `package:aikit/aikit.dart`.

## Reading and writing documents

`AiCodec` implements `Codec<AiDocument, List<int>>`. Its converters operate on
complete files; direct encoding returns `Uint8List`:

```dart
import 'dart:io';
import 'dart:typed_data';

import 'package:aikit/aikit.dart';

final Uint8List input = await File('input.ai').readAsBytes();
final AiDocument document = const AiCodec().decode(input);
final Uint8List output = const AiCodec().encode(document);
await File('output.ai').writeAsBytes(output, flush: true);
```

Detection uses `%PDF-`, `%!PS-Adobe-` or a DOS binary EPS header, not the filename.
Illustrator markers are required by default. `allowGeneric: true` also accepts
generic PDF/EPS interchange; it does not turn that content into native AI data.
Markers identify a format convention, not the authenticity of a file.

| Container | Model | Encoding behavior |
| --- | --- | --- |
| PDF-backed AI | `AiPdfDocument` | Rewrites the PdfCore object graph, retaining native private data unless explicitly replaced or removed. |
| PostScript AI or EPS | `AiPostScriptDocument` | Returns the retained source bytes, including any DOS EPS envelope and previews. |

PdfCore's limits and restrictions apply to PDF-backed files, including encryption
rejection and signature invalidation on a full rewrite. Exact legacy byte
preservation does not imply that the PostScript program can be executed or that
all its authoring data is understood.

## Native programs and immutable edits

`AiNativeData.extract` retrieves authoring data separately from the compatibility
PDF. The latter may contain only an Illustrator compatibility warning.

```dart
final List<AiNativeSource> sources = AiNativeData.extract(document);
for (final AiNativeSource source in sources) {
  final AiProgram program = AiProgram.decode(bytes: source.bytes);
  final AiNativeRecords records = AiNativeRecords.decode(program: program);
  print('${program.layers.length} layers; ${records.artboards.length} artboards');
}
```

For PDF files, extraction follows catalog/page `PieceInfo → Illustrator → Private`
entries. It collects `AIPrivateDataN` or `AIPDFPrivateDataN` streams in numeric
order, validates contiguous numbering, decodes outer PDF filters and excludes
recognized leading thumbnail blocks. Shared complete block sequences produce
one source with multiple owners; independent native programs remain separate.
Do not assume that every file has exactly one source or one source per page.
`AiPdfDocument.privateBlocks` exposes the retained stream inventory separately
from decompressed native programs.

Supported envelopes are plain `%!PS-Adobe-`, `%AI12_CompressedData` followed by
zlib, and `%AI24_ZStandard_Data` followed by Zstandard. Split envelope markers
are supported. Unknown blocks and private fields remain in the source graph.
`AiNativeSource` retains immutable bytes, compression and catalog/page ownership;
`asPostScript()` exposes the program without converting its native version.
`AiNativeData.encodeEnvelope` encodes an explicitly selected compression family.

Edits return new snapshots. Obtain layers, paths, frames, resources and other
handles from the snapshot being edited; handles from an earlier or foreign
snapshot are rejected. Reacquire handles after each edit. Unrelated source bytes
are preserved according to the individual API's contract, rather than rebuilding
an entire document from the subset of fields AiKit understands.

`AiNativeEditor.apply` is a lower-level byte-edit API. It validates spans,
overlap and output size, then reparses the result. Its caller owns semantic
consistency between any dependent native records it changes.

## Native capability reports

`AiNativeCapabilityReport.inspect(source: source)` inventories one extracted
native program without editing it or generating artwork. Inspect every source
returned by `AiNativeData.extract`; a PDF page is not necessarily a separate
native document. Extraction errors remain errors of that API, before this report
can be constructed.

Each finding retains its immutable source, catalog/page `owners`, a source-relative
`selector` and a `[start, end)` byte span. A failure uses the smallest known enclosing
span; decoded text-engine offsets are not confused with native source offsets.
Overlapping findings describe different aspects of the same bytes.

| Data support | Meaning |
| --- | --- |
| `typed` | A named native model exposes these fields; editing is assessed separately. |
| `preserved` | Original bytes remain available without a claim of semantic support. |
| `unsupported` | A known layout or dependency cannot currently be interpreted or used safely. |
| `malformed` | Structural validation identified invalid syntax or values. |
| `uninspected` | A resource limit or an ambiguous dependency-parser failure prevented inspection. |

Named operations have independent `available`, `requiresValidation` or
`unsupported` assessments. `editable` is true only when at least one operation
is available. Layer name/flag availability concerns the header alone, never its
children. Plain-path availability follows the native editor's dependency guards.
Live shapes, text, gradients, meshes and images retain operation-specific
validation requirements; known shape-binding or image-layout failures explicitly
disable the affected operations. Do not treat `requiresValidation` as availability.

`limits` bounds parsing; `maxFindings` bounds retained diagnostics and reserves
the final slot for an explicit truncation finding if needed. `complete` means
the attempted inspections finished without failure or truncation, not that all
data is understood or editable. It can coexist with preserved data or explicit
reference/binding issues. `AiLimitException` remains a `FormatException` for
existing callers while distinguishing native parser resource ceilings from
malformed syntax. Repeated fields remain preserved;
`AiNativeAmbiguousFieldError` identifies a failed unique-field lookup without
declaring a repeated-field record invalid.

The report is diagnostic, not a serialization gate or a rendering whitelist.
Keep unsupported bytes and let the selected edit validate its inputs. The pinned
corpus check compares 37 exact extracted sources and their PDF owners, plus 41
layer headers and 181 non-private path inventories, against independent readers.
It does not qualify every reported edit or establish Adobe interoperability.

## Saving native edits with host-supplied representations

`AiNativeData.replace` packages an edited program with an explicitly supplied
`synchronizedPdf`. For example, renaming a layer does not alter painted geometry,
so its existing PDF appearance can be retained:

```dart
AiPdfDocument renameFirstLayer({
  required AiPdfDocument document,
  required String name,
}) {
  final AiNativeSource source = AiNativeData.extract(document).single;
  final AiProgram program = AiProgram.decode(bytes: source.bytes);
  final AiProgram renamed = AiNativeEditor.updateLayer(
    program: program,
    layer: program.layers.first,
    name: name,
  );
  return AiNativeData.replace(
    source: source,
    program: renamed.bytes,
    synchronizedPdf: document.pdf,
  );
}
```

This example requires one native source containing a layer. For visual edits,
the host must supply the matching PDF and any required native printing data,
text layouts, pixels or previews. The PDF must derive from the original graph
and retain metadata references and owner mappings. AiKit does not render the
program or establish visual equivalence between supplied representations.

For several independent programs, construct immutable
`AiNativeReplacement(source: ..., program: ...)` entries and call
`AiNativeData.replaceAll(replacements: ..., synchronizedPdf: ...)`. Every entry
must originate from the same `AiDocument` snapshot. Shared owners are one entry;
duplicate/overlapping entries reject. All replacement envelopes and aggregate
byte limits are checked before a result is published. Unselected native programs
remain unchanged.

Both save APIs verify the catalog reference, page count and ordered page
references. They also require the original Illustrator dictionaries and their
transitively referenced PDF objects, including unselected programs. The host may
replace page contents/resources and unrelated producer metadata. Native metadata
mutations, stale extraction handles, a separately reparsed PDF, renumbering,
page insertion/removal/reordering and changed alias membership reject atomically.
Reacquire all handles after a save; use one batch to save several programs from
the same snapshot. Page/artboard remapping is not inferred from counts, bounds or
owner order. This contract currently preserves the existing mapping only.

Replacement keeps the original compression family, rewrites every shared owner,
removes stale native thumbnail blocks, and preserves other producers and private
metadata. Mixed native block families on one owner are rejected. New allocations
reserve existing dangling references. Old unreferenced objects may remain;
replacement is not a redaction operation. Encode the returned document with
`AiCodec`; file persistence and save checkpoints belong to the application.

Independent save checks cover 31 pinned PDF-backed fixtures and two synthetic
multi-program cases: 35 exact native programs, layer-name-only changes, shared
owners, unselected private metadata, page content and supplied PDF resources.
The synthetic cases include two native artboards and partial/batch saves. These
checks establish graph preservation, not visual correspondence or Adobe reopening.

`AiPdfDocument.forPdfInterchange(pdf: ...)` explicitly removes stale Illustrator
authoring links from a PDF. It does not synthesize native CC editing records.

## Layers, paths and hierarchical records

`AiProgram.decode` reads body instructions outside prologs, setup, procedures,
embedded documents and opaque binary samples. It exposes nested layers, source
spans, names, visibility, lock/print flags and path segments. Corner/smooth curve
operators, shorthand curves, comments and paint operators are retained.
`unhandledOperators` and `hasPrivateExtensions` identify unresolved semantics;
neither an empty diagnostic set nor a path count proves complete editability.

`AiNativeEditor.updateLayer` changes supported layer names and flags without
rewriting unrelated object state. Names use Latin-1 through `name`, or explicit
bytes through `nameBytes`; no locale encoding is guessed. `replacePath` replaces
plain geometry while retaining comments and paint. It rejects unresolved
operators, private editing extensions and appearance-owned geometry that would
leave alternate representations stale.

When a qualified CC `As` point count precedes a path, `replacePath` updates it
with the geometry. Counted closed paths use an explicit closing endpoint; the
writer adds a closing line if the supplied last endpoint differs from the first.
Duplicate, interleaved, cross-object or inconsistent counts reject atomically.
The capability report flags plain paths in counted programs as requiring this
additional validation. Sources without counts retain their existing layout.

### Layer ownership and empty insertion

`AiNativeLayers.decode(drawing:)` associates each original `AiLayer` with its
matching optional `%AI5_BeginLayer`/`%AI5_EndLayer` wrapper, direct parent/children,
native name bytes, saved `AE` panel expansion and attached `ArtDictionary`.
`identifier` exposes a known `AI10_ArtUID` even when other dictionary fields
remain opaque. `bindingIssue` distinguishes unqualified ownership/header layouts
from malformed numeric attributes or unmatched boundaries, which throw.

`rootCountHeader` retains `%AI5_NumLayers`, which counts root layers rather than
all nested layers. Missing declarations remain absent. `rootCountMatches` exposes
stale declarations for inspection; structural editing rejects a mismatch.
`viewHeader` and `viewComments` retain `%AI5_OpenViewLayers` and continuations.
Their numbers are not interpreted as layer indices.

```dart
final AiNativeLayers layers = AiNativeLayers.decode(drawing: drawing);
final AiNativeLayer template = layers.layers.first;
final AiNativeLayers inserted = layers.insertAfter(
  after: template,
  nameBytes: 'New layer'.codeUnits,
  identifierBytes: template.identifier == null ? null : 'New_layer_unique'.codeUnits,
  discardViewState: true,
);
final AiProgram changed = inserted.drawing.records.program;
```

This inserts an empty sibling, retaining the selected header's flags, operand
layout and DSC wrapper convention. Names are explicit bytes, safely escaped as
PostScript strings. Identified templates require a caller-supplied fresh portable
ASCII XML name; collisions with existing XML artwork identities reject. Anonymous
templates stay anonymous. A present `AE` becomes zero for the new panel entry.
No artwork, paint assignment or original identity is copied into the new layer.

The qualified header layouts have 10, 13 or 14 operands; the last operand of the
14-operand layout must be zero. Additional dictionary fields, multilayer masks,
conditional headers, unresolved attached metadata and non-layer parents reject.
Opaque child artwork may remain untouched in the selected template. This does
not grant lifecycle operations on that artwork or permission to copy its private
records. Existing root counts update atomically; nested insertion preserves them.
A saved layer-view mapping requires explicit `discardViewState: true`, removing
that declaration and its continuations because its reference schema is not yet
qualified. The default refuses to invalidate it implicitly.

Source limits, immutable snapshots and stale/foreign-handle checks apply to the
whole transaction. `layerInsertion` is reported as `requiresValidation`.
Twelve focused regressions cover wrappers, metadata, malformed input, limits and
atomic refusal. Independent decoding checks all 50 original layers in 46 pinned
sources and 40 inserted variants, including hidden/locked nested owners. Ten
headers with additional private fields remain explicitly unsupported. Exact-byte
checks preserve all unselected source and only allow the declared count/view
edits. Layer removal, duplication, reordering/reparenting and Adobe reopening
remain unqualified.

### Ordinary path lifecycle

`AiNativeDrawing` supports the following operations on independent ordinary
paths. Select handles from the current drawing; empty, repeated, foreign and
stale selections reject before any source edit is applied.

| Operation | Behavior |
| --- | --- |
| `duplicatePaths(paths:)` | Copies each selected path immediately after its original, retaining geometry, paint, internal ordinary comments and optional point counts. |
| `removePaths(paths:)` | Removes geometry/paint and its consumed point count. Persistent state and conservative drawing bounds remain. |
| `insertPaths(insertions:)` | Inserts supplied geometry after each anchor, inheriting its paint, flags and count convention. Multiple insertions at the same anchor retain input order. |
| `reorderPaths(paths:)` | Places selected siblings into their existing source slots in the requested order, carrying geometry, paint and count syntax together. |
| `movePathAfter(path:, after:)` | Moves a path after an anchor, optionally across ordinary group boundaries within one containing layer. |

`AiNativePathInsertion` freezes supplied `segments` and requires host-computed
ink `bounds`. Geometry has one initial moveto and portable finite coordinates.
Counted closed paths receive a closing endpoint when needed. Bounds expand the
existing drawing extent without changing artboards or PDF pages. All operations
reparse under the original source limits and return immutable snapshots.

These APIs accept anonymous paths whose ownership and inherited appearance are
isolated. Private paths, live-shape expansions, gradients, compound/clip members,
version alternatives, attached identities, tags, notes and unresolved metadata
reject. Qualification includes ordinary parent groups/layers and postfix records,
even when state assignments separate an object from its metadata. A completed
bound live shape does not by itself make the next ordinary path an expansion.
Unselected opaque setup or sibling data can remain unchanged outside that scope.

Persistent paint, lock and visibility assignments stay at their source positions.
Reordering or moving additionally requires an interval with no state assignments,
opaque data or metadata. Ordinary `u`/`U` boundaries do not save and restore paint;
only `movePathAfter` may cross them. Cross-layer moves and moves across different
paint states remain unsupported. These operations do not create or remove groups,
layers, shared resources or referenced identities. Capabilities report all five
operations as requiring selection-specific validation.

Independent checks cover 13 variants across two pinned recent Illustrator files
and synthetic counted/grouped sources, including retained ownership, inherited
controls, exact unselected bytes and counts. Adobe reopening remains unqualified.
Saving changed geometry requires matching PDF artwork supplied by the host.

### Ordinary group lifecycle

`AiNativeDrawing` also supports anonymous ordinary `u`/`U` owners. A selected
group can contain nested ordinary groups, qualified paths and process-paint or
object-state assignments. Empty owners are supported. Batch selections must be
owned, distinct and disjoint; selecting an ancestor and descendant together
rejects before editing.

| Operation | Behavior |
| --- | --- |
| `groupPaths(paths:)` | Wraps consecutive sibling paths in one group, preserving source order, consumed point counts and intervening qualified assignments. |
| `ungroup(groups:)` | Removes only the selected boundaries; child objects, nested groups and state remain. |
| `duplicateGroups(groups:)` | Copies each complete subtree immediately after its original, replaying known source assignments to preserve inherited and outgoing state. |
| `removeGroups(groups:)` | Removes the subtree's objects and counts, retaining its persistent assignments for following artwork. |
| `reorderGroups(groups:)` | Places selected siblings into their existing slots in the requested order, restoring each slot's original outgoing state. |
| `moveGroupAfter(group:, after:)` | Moves a subtree after an anchor, optionally into its different group parent within the same layer. |

Ordinary groups do not save and restore paint. The editor tracks explicit source
assignments for gray/RGB/CMYK fill and stroke, overprint, width, dashes, caps,
joins, miter limit, fill/path flags, locking and visibility. Color representations
are copied without conversion. Missing values stay unknown; no renderer or
default graphics state is invented. An operation that needs to restore an unknown
value rejects. Source values can become known again after an opaque boundary
only through explicit assignments.

`A` retains its native locking flag. `Xw` retains the persistent visibility flag
(0 visible, 1 hidden), also documented in the
[IgnoCodeLib author's writer reference](https://paulhertz.net/ignocodelib/reference/com/ignotus/aifile/AIFileWriter.html).
The independent checks compare these stored flags; they do not certify UI behavior.

Creation inserts the opening before the first selected path's consumed `As`
header when present, including any attributes between that header and geometry.
The new group's flags inherit that source position. Duplication/movement can add
source-backed assignments before or after the copied group; all bytes outside
the selected intervals and insertion points remain exact. Deletion retains the
group's outgoing assignments even when its objects disappear. Drawing bounds
remain conservative because these operations retain or remove existing geometry.

Private/derived owners, compound/clip children, version alternatives, attached
identities, tags, expansion flags, notes, unknown state and metadata comments
reject. Moving cannot cross layers or opaque/private intervals; source and anchor
groups cannot contain one another. Shared styles, effects and referenced group
identities need separate lifecycle contracts. Group capabilities therefore remain
selection-dependent, with compound/private/clip topology explicitly unsupported.

Sixteen focused regressions include changed inherited state, nested and empty
owners, process-color syntax, atomic refusal, parser limits and a 200-group batch.
The independent reader verifies 13 variants across two pinned recent files and a
synthetic source with state changes: full owner topology, object flags, paths,
counts, effective paint, layer outgoing state and exact unselected source bytes.
Adobe reopening remains unqualified. Save matching host-supplied PDF artwork
whenever the edit changes visible output or ordering.

### Hierarchical records

`AiNativeRecords.decode` exposes dictionaries, arrays, objects and binary
resources in ordinary and `%_`-prefixed syntax. Source offsets, multiline and
adjacent strings, unknown record types and embedded drawing commands survive.
Repeated object fields remain ordered through `values(key)`; ambiguous single
lookups reject. `decodeBinary(maxOutputBytes: ...)` uses bounded ASCII85 decoding.
Decoding a binary resource does not establish support for its internal format.

`records.artboards` exposes recorded names, identifiers, active flags, bounds and
optional artboard ruler origins. Each board retains its owning `Document` record
and local `index` in `ArtboardArray`, independently of PDF pages. A saved identifier
is not a proof of global uniqueness. Optional UUID, selection and origin fields
are validated when present. `replaceString`, `replaceNumbers` and `replaceBinary`
update existing source-backed entries and reparse the records. Numeric writes
validate native types and VM/JavaScript representability; string encodings remain
explicit. These are record edits: changing a dimension through a scalar setter
does not automatically update dependent paths, appearances or artboards.

### Document settings and coordinate ownership

`AiNativeDocumentSettings.decode(records:)` exposes the initial numeric header
declarations together with their exact `AiToken` spans, top-level `Document`
records, ordered artboards and setup `AI11TextDocument` ruler origins. Header
inspection stops at the header boundary; embedded documents, procedure comments
and declarations in setup/body data cannot replace the owning header's settings.
Repeated or version-dependent settings reject rather than choosing a branch.
Malformed numeric layouts throw `FormatException`. Parsing retains the source
byte/token/depth limits and immutable field collections.

`rulerUnitCode` and `largeRulerUnitCode` retain raw nonnegative codes, including
unknown values. `rulerUnit` interprets ordinary codes 0–4 and 6 and large codes
7–10. A present large code takes precedence even when unknown; unknown codes
have no inferred enum value. Code 5 remains unqualified. `largeCanvasScale`,
`canvasSize`, `templateBox` and `pageOrigin` expose their saved values without
unit conversion or substituting defaults when absent.

Artboard bounds use drawing coordinates with y up. `artboard.rulerOrigin` stores
the saved artboard origin in canvas coordinates with y down. Each
`textRulerOrigins` entry retains its own text-document container and source entry;
it is not silently merged with another origin or inferred from a page. Artboards,
canvas extent, drawing/ink bounds and compatibility PDF pages remain distinct.
This is an inspection contract, not an artboard lifecycle or origin-edit API.

### Structure, identities and saved alternatives

`AiNativeStructure.decode(drawing:)` indexes source-owned layers, groups,
compound/clip groups, private and printable paths, records, version blocks,
gradient declarations and remaining body instructions. Nodes retain direct
lexical parents and child order. Unknown records and instructions remain in the
index without acquiring editing semantics. `nodeFor`, `parentOf`, `childrenOf`
and `entryFor` reject foreign handles. Ordered record fields retain their exact
owner and local index, including repeated object fields and unkeyed entries.

Node identity belongs to one immutable snapshot, not to an offset in another
revision. Saved `ArtboardUUID` and `AI10_ArtUID`/`XMLUID` values have separate
namespaces and exact dictionary-field ownership. Their bytes are immutable;
equal values do not merge objects or prove global uniqueness. An artwork
dictionary's XML identifier alone does not identify a neighboring path.
`shapes` exposes the drawing reader's existing authoring-path, printing-group,
printing-dictionary and alternate-dictionary bindings separately from lexical
parenthood. An unresolved `shape.bindingIssue` remains authoritative.

`AiNativeVersions.decode(records:)` retains matched `%AI*_Begin_Content_if_version_gt`
blocks, their major/minor condition, optional alternate and closing markers.
Both branches survive, including empty and newer-only branches. `memberships`
reports outer-to-inner ownership for a whole source interval. A span enclosing a
complete block has no membership in that block; a span crossing a boundary
rejects. Strings, procedures, embedded documents and binary payloads cannot
contribute version delimiters. No target Illustrator version is selected.

Named resource links currently cover `KnownStyle`/mode-one `XW` and global
`Bd`/complete `Bg` instances. The index includes qualified uses inside native
`Art`, paint styles and setup pattern/symbol artwork; inspecting those references
does not implement pattern/symbol editing. References outside indexed structural
nodes keep a null lexical owner and exact instruction offsets. Declaration
memberships follow the source name, including conditions inside its record.
Duplicate definitions remain separate. A use is `resolved`, `missing`,
`ambiguous` or `conditional`; `usesOf` includes potential conditional/ambiguous
dependencies. Opposite branches of the same block cannot bind each other.
Conditions in separate blocks are not assumed equivalent. Unknown plug-in
dependency schemas remain opaque.

The inventory rejects crossing lexical owners, references/names split across
version boundaries, unresolved qualified style layouts and malformed saved
identifiers. It bounds combined ownership depth and declaration/reference
association work with the source limits. Duplicate known-style names no longer
prevent drawing inspection, but dependent live-shape edits still reject unresolved
style ownership. This inventory supplies structural evidence, not permission to
move or delete arbitrary byte spans. The ordinary-path operations above apply
their own guards; broader lifecycle operations remain in `ROADMAP.md`.

## Editable text

`AiNativeTextDocument.decode(records: ...)` reads `AI11TextDocument` with PsCore.
Choose a container explicitly when several exist. Named CS keys and compact CC
keys retain their original syntax; ambiguous aliases reject. The separate
`AI11UndoFreeTextDocument` is not silently merged into the current model.

The view exposes fonts, character/paragraph styles, frame resources, stories and
`AI11Text` drawing references. Unknown engine fields remain accessible through
immutable PsCore values and retained bytes. `referenceIssues` reports unresolved
references and cyclic/excessive style inheritance, including drawing references
to the undo-free model; it is not a complete typography validator.

`story.modelText` includes the mandatory terminal CR; `story.text` omits that mark.
Offsets and run lengths count UTF-16 code units. Present run tables must cover
the source text, including its terminal mark, without splitting surrogate pairs.
Omitted tables inherit normal styles. `characterStyleAt`, `paragraphStyleAt` and
`styledRanges` resolve bounded parent chains, paragraph character defaults and
local overrides. Missing fields stay null instead of receiving guessed defaults.

```dart
final AiNativeTextDocument text = AiNativeTextDocument.decode(records: records);
final AiNativeTextStory story = text.stories.first;
final AiNativeTextDocument changed = text.replaceText(
  story: story,
  start: 0,
  end: story.text.length,
  text: 'Bonjour Illustrator',
);
final AiProgram changedProgram = changed.records.program;
```

### Text and style edits

`replaceText` inherits character formatting at the insertion start, adjusts
native paragraph runs at CR and U+0003 forced breaks, and preserves unrelated
stories/resources. A forced break remains inside the same logical paragraph.
LF input, malformed UTF-16, split surrogate pairs, removal of the terminal CR,
active unsupported auxiliary features and unknown model/view dependencies reject.

`setCharacterFeatures` accepts `AiNativeCharacterChanges` for a selected range:
font, size, leading, scale, tracking, baseline, rotation, kerning mode and explicit
OpenType switches/sets. Point size and `RefFontSize` change together; unresolved
non-point reference modes and alternate-glyph dependencies reject relevant edits.
`setParagraphFeatures` accepts `AiNativeParagraphChanges` for whole paragraphs
touched by an end-exclusive selection, including their forced-break spans.
Alignment, indents, spacing, hyphenation, direction and composer settings are
stored data; AiKit does not implement the selected compositor.

Both change models support `inherit` to remove local overrides without modifying
named parent resources. Unknown style features survive qualified edits. Changed
inline styles receive fresh identities when required; unchanged fragments retain
theirs. `renameStyle` changes only a style's display name.

Content and feature edits invalidate the selected story's rendered-data/glyph
caches. Exact no-ops retain the original snapshot. The host must recompose edited
text and provide matching native printing/PDF representations before saving.
`withoutTextLayout(story:)` explicitly invalidates the same known caches when an
external dependency changes without changing the text model. It retains frame
references, styles, resources, other stories and the undo-free payload; unknown
view fields and stale story handles reject. Repeating it on an already cleared
view returns the same snapshot. This intermediate state still requires host
composition before a synchronized save. See the [derived-payload policy](HOST.md#derived-representations).

### Fonts, frames and supplied layouts

`addFont` registers an `AiNativeFontDefinition` with a host-supplied PostScript
name, technology, optional version and signed 16.16 variation coordinates in
font-axis order. It preserves existing indices and resources, allocates a fresh
identity and returns the new font as `fonts.last`. It does not load or embed a
font, deduplicate equal names, or choose a fallback face.

`story.strikes` exposes saved frame/row/line/segment/glyph observations, including
origins, bounds, character mappings and glyph IDs. A glyph is not assumed to
represent one character. Retained caches are not newly composed text.

`withTextLayout` writes host-supplied `AiNativeTextFrameLayout`,
`AiNativeTextLineLayout` and `AiNativeTextSegmentLayout` data. Layout coordinates
use native y-down points: line origins are frame-relative and segment origins
are line-relative. Frames must match the story's resource order; UTF-16 coverage,
visual-order mappings, overflow and allocation limits are checked. Supply
`overflowStart` for an uncomposed suffix. Compact reordering and qualified
terminal automatic-hyphen maps are supported; named CS equivalents and per-glyph
path geometry remain unsupported. No font measurement or GlyphStrike generation
is performed.

`translateFrames` moves selected point, area or path frames in y-up drawing
coordinates. It updates frame matrices and corresponding native confinement
paths while retaining local text/layout data and unselected linked frames.
It accepts qualified unpainted confinement geometry; ambiguous text documents,
missing references, complex appearances and unresolved frame metadata reject.
`AiNativeArt.decode` exposes bounded confinement commands and nested metadata
without executing PostScript. DSC bounds expand conservatively while artboards
remain fixed. Printable
appearances, undo-free copies and effect caches still require host coordination.

## CC live shapes

`AiNativeDrawing.decode` separates private authoring outlines from printable
expansions and retains group/compound topology, styles and recognized versioned
metadata. `liveShapes` associates each `ai::LiveShape` record with its dependent
geometry. `bindingIssue` identifies incomplete associations.

```dart
final AiNativeDrawing drawing = AiNativeDrawing.decode(records: records);
final AiNativeDrawing moved = drawing.translateLiveShapes(
  shapes: [drawing.liveShapes.first],
  deltaX: 20,
  deltaY: -10,
);
final AiProgram movedProgram = moved.records.program;
```

Qualified rectangles, ellipses, polygons, stars and lines support these edits:

| Operation | Native changes | Coordinate contract |
| --- | --- | --- |
| `translateLiveShapes` | Authoring outlines, printable contours, centers and supported gradient placements. | Drawing points, y up; recorded canvas centers are adjusted in y-down space. |
| `rotateLiveShapes` | Geometry, centers, angles, frame metadata and dependent gradient transforms. | Explicit drawing-space pivot; radians in −2π..2π, positive counterclockwise. |
| `scaleLiveShapes` | Geometry, dimensions, corners, strokes, dashes and dependent gradient/style copies. | Explicit pivot and finite positive uniform factor; strokes and corners scale together. |

Solid and qualified linear/radial gradient styles include expanded inside/outside
strokes. Shared positional styles are copied where necessary so unselected users
remain unchanged. Rotation/scaling require an unambiguous native `RulerOrigin`;
page or crop bounds cannot substitute for it. Units remain native drawing units,
before application large-canvas scaling. Existing frame-angle representation is
retained; edited string angles use six decimal places.

Unknown effects, patterns, clipping, executable transforms, unsupported version
branches and unresolved nested appearance ownership reject edits. Unresolved
inherited state can block an operation even outside its selection. Conservative
DSC bounds retain the original extent and include the transformed artwork;
artboards stay fixed. Nonuniform resizing, shear/reflection, fixed-width strokes,
fixed corners and parameter-driven shape regeneration are not supported by these
operations. The host supplies the corresponding PDF and previews after an edit.
`AiNativeEditor.translationBoundsEdits`, `affineBoundsEdits` and
`includeBoundsEdits` expose the conservative DSC-bound operations independently.

### Host-supplied printing contours

`withPrintingContours(replacements:)` refreshes derived geometry in separate,
bound CC live-shape printing groups. Each `AiNativePrintingReplacement` selects a
shape from the current drawing, supplies one `AiNativePrintingContours` for every
owned appearance path and declares the host-computed ink `bounds`. A batch uses
one immutable source snapshot; reacquire all handles from the returned drawing.

Each supplied contour starts with one `m`, followed by native line/cubic segments
in the source path's drawing coordinates. It inherits the original paint/closure
operation. Compound nesting, paint commands, gradient references, shared styles,
private geometry, authoring dictionaries and versioned alternatives remain intact.
Multiple contours are accepted only with a self-contained paint operation;
wrapped gradient/paint paths require one contour. Coordinates must fit the finite
portable range, and generated bytes/tokens obey the source parsing limits.
Existing CC `As` counts are updated for every contour, including newly inserted
contours. Counted source paths must have one initial moveto and the observed
explicit closed endpoint. A supplied implicit closure is written as a closing
line; the resulting count includes each anchor once. Uncounted source paths do
not acquire new headers. Ambiguous, stale and cross-object count bindings reject.

This operation does not change shape parameters or verify visual equivalence.
The host supplies geometry consistent with the authoring records and compatibility
PDF, including all stroke/effect expansion. Bounds include inherited transforms
and expand document DSC bounds conservatively; artboards remain unchanged.
Incomplete/duplicate ownership, foreign or stale handles, nested metadata,
unknown local commands and interleaved path-state changes reject atomically.
Opaque neighbors outside the selected printing group remain unchanged. Direct
authoring paths and arbitrary replacement paint/resource topology are not derived
attachment slots. These restrictions govern this edit, not native/PDF packaging.

### Host-supplied printing groups

`withPrintingGroups(replacements:)` accepts `AiNativePrintingGroupReplacement`
entries for the same separate, bound CC live-shape expansions. Each entry supplies
owned byte data containing exactly one `u`/`U` group and host-computed ink `bounds`.
Path counts, ordinary/compound nesting and local paints can change. Private shape
parameters, authoring paths, alternate dictionaries and resource definitions remain
unchanged. The host supplies a consistent expansion and compatibility PDF; the kit
does not derive artwork from those authoring records or prove visual equivalence.

Each group contains non-private paths with one initial moveto. Source and supplied
groups must leave identical explicit paint-state assignments, including color
representation, opacity, stroke width, caps/joins, miter, dash array/phase,
overprint, fill-rule and path flags. Absent assignments mean unknown inherited
state, not defaults. Transient assignments may differ when the final assignment
matches. The qualified attributes are process `g`/`G`, `k`/`K`, `Xa`/`XA`,
`O`/`R`, `XR`, `D`, `Ap`, `J`/`j`, `w`, `M`, `d` and the observed
`0 opacity 0 0 0 Xy` layout. `Ae` must immediately precede its owned group.
Spot-color commands, `Xd`, clipping, executable state and unknown local commands
have no full-group replacement contract yet. Geometry-only attachment can retain
some such controls unchanged under its separate contract.

Complete `Bb`/`BB` gradient fills may reference one existing uniquely named
definition. They require one associated filled path, a positive-length `Bg`
with flag 1, `BB` flag 0 and an imaging matrix for relative CC geometry. `Bh`
requires a radial definition. Gradient-stroke selectors, interleaved state and
new or ambiguous resources reject. No renderer is involved in these checks.

Counted CC source groups must count every path; supplied groups retain this
convention, including new paths and explicit closed endpoints. Counts are validated
against the supplied geometry, not silently corrected. Uncounted groups stay
uncounted. Byte, token, nesting and portable numeric limits apply before attachment
and to the complete result. Document markers, embedded data and private metadata
are forbidden inside the fragment. Batches are atomic and require distinct current
source handles. Invalid local syntax/operands throw `FormatException`; unresolved
ownership, state, resources or count conventions throw `UnsupportedError`;
stale/duplicate handles and invalid constructor arguments throw `ArgumentError`;
configured parsing ceilings throw `AiLimitException`.

## Gradients and paint styles

`AiNativeDrawing.gradients` exposes `Bb`/`BB` instances, relative `Bg` geometry,
radial `Bh` focus and absolute `Xm`/`Bm`/`Bc` printing matrices. It retains the
paths consumed by each instance and any gradient-stroke selector.
`AiNativePaintStyle.decode` reads owned fill, stroke and blend command lists
without flattening repeated appearance parts.

`AiNativeGradientResources.decode` reads global `Bd`/`BD` definitions, including
nonprinting swatches, native `Bs` stops, fallback `BS` stops and `Br` printing
intervals. Byte names, stop order, opacity wrappers and numeric channel forms
are retained. Gray, RGB/CMYK, custom and newer named colors expose their recorded
alternatives and tint data; no color-profile conversion is implicit.
`AiNativeGradientColor`, `AiNativeGradientStop` and `AiNativeGradientRamp` provide
the immutable color, stop and channel data used by resource edits.

### Stops, focus and resource ownership

`replaceStops(definition:, stops:, ramps:)` updates every definition sharing the
selected byte name. Supply strictly increasing stop positions and one
host-composed ramp per adjacent pair. The writer updates native/fallback stops,
counts and printing intervals; it writes linear stops descending and radial
stops ascending. It does not prove that supplied ramps reproduce the stops.

Moving linear stops also updates all qualified strip/cap references while keeping
the overall gradient axis fixed. Legacy matrices without `Xm` require consistent
recoverable geometry. Missing caps, unmatched references, mixed same-name kinds,
unknown metadata, coincident stops and excessive expansion reject. Resource-local
formatting may be regenerated; unrelated bytes remain intact.

`setRadialFocus(definition:, angle:, length:)` changes all instances using a
resource, including shared styles and private artwork. Angles are degrees in
−360..360 and length is a normalized radius in 0..1. Authoring polar values and
Cartesian printing offsets update together; inconsistent or singular source
geometry rejects. This is a global edit, not selection-local recoloring.

`isolateLiveShapeGradient` first copies a named gradient and matching styles for
selected live shapes, updating bank counts and selected bindings. The new byte
name must be unused. Decode resources from the returned drawing before editing
that copy. All occurrences inside the selection change together; individual
appearance-part selection, general resource creation/removal and hard stops
remain unsupported.

### Relative gradient placement

`setLiveShapeGradientPlacement` updates relative parameters and printing geometry
for a named gradient in selected qualified CC live shapes. It retains paths,
shape parameters, colors, ramps, unselected styles and the accumulated object
transform. Source relative/printing geometry must agree before editing.

Angles use degrees in −360..360; length and aspect ratio must be positive.
Linear gradients require `originY: 0` and `aspectRatio: 1`: x origin and length
are fractions of the shape's extent along the selected angle. Radial origins
are measured from the center in fractions of width/height, with positive y down.
Their radius is `length * sqrt((width * (originX - 0.5))² +
(height * (originY - 0.5))²) / sqrt(2)`, before angle, aspect and retained object
transform. Degenerate results reject.

The operation requires the qualified CC clipped layout, resolved stroke state
and consistent strip/cap coverage. Arbitrary affine paint changes, legacy
placement layouts, plain-path selections and unresolved appearance graphs remain
unsupported. Color management, ramp composition and PDF generation belong to the
host; native gradient resource modeling and serialization belong to AiKit.

## Mesh data

`AiNativeMeshes.decode(records:, bodyOnly:)` reads `/Mesh X!` packets through
`/End X!`. The default includes resources; `bodyOnly: true` restricts the inventory
to the drawing body. The supported schema is version 2, Cartesian topology.
Other versions/topologies reject typed decoding while the source stays intact.

Each mesh retains index axes, patches, source fields and cyclic node order,
including `/N` corners, `/A` anchors and `/S` subdivision points. Positions,
source-order handles, weights, opacity, unknown fields and intermediate nodes
are preserved. Patch coverage and ranges are checked without allocating from an
unchecked grid-size product. Unknown color spaces retain their declarations.
Known gray/RGB/CMYK arities and normalized components are validated.

Separation/NChannel `inks` preserve lexical declaration order and device
alternatives. Corner `inkTints` pairs tints in component order, which reverses
lexical ink order for NChannel. It does not convert spot inks to process colors.
`mesh.vertices` groups each logical vertex's one, two or four corner occurrences;
duplicated positions must agree exactly. Handles remain distinct.

```dart
final AiNativeMeshes meshes = AiNativeMeshes.decode(records: records);
final AiNativeMesh mesh = meshes.meshes.first;
final AiNativeMeshes painted = meshes.paintVertices(
  mesh: mesh,
  changes: [
    AiNativeMeshVertexPaint(
      vertex: mesh.vertices.first,
      color: AiNativeMeshProcessColor(space: .rgb, components: [0.8, 0.2, 0.1]),
      opacity: 0.7,
    ),
  ],
);
```

`paintVertices` updates every selected corner occurrence atomically. It accepts
process color, named-ink `tints`, opacity, or compatible combinations; `color`
and `tints` are mutually exclusive. Tint edits require matching ordered inks and
alternatives across all copies. Color switches stay local; unselected geometry,
weights, colors and declarations remain intact.

Editing is limited to direct printable body meshes with independent appearance
ownership. Resource/private copies, unresolved parent/object dependencies,
unknown mesh fields and incompatible color declarations reject edits. Native
geometry/topology editing is unfinished. Interpolation, tessellation and color
management are application responsibilities.

## Embedded raster images

`AiNativeRasters.decode(records:, bodyOnly:)` reads binary `XI` images in setup,
body and private records. Samples are interleaved process colors followed by a
separate alpha plane, with packed row padding preserved. Supported component
depths are 1, 2, 4, 8 and 16 bits; 16-bit samples are big-endian. Width/height,
bounds, producer flags, source spans and both `XI`/`Xh` matrices remain explicit.
No profile conversion is performed.

Binary boundaries come from validated image geometry, including alpha, before
checking the exact DSC terminator. Recognized count variants are accepted only
when that boundary matches. Sample bytes remain opaque even if they contain
PostScript tokens or fake end markers. Corrupt/transcoded data is not repaired
by searching for a later marker.

| Operation | Behavior |
| --- | --- |
| `translate` | Updates both native matrices, retaining samples and metadata. |
| `replacePixels` | Writes host-supplied `AiNativeRasterSamples`; adjusts dimensions, flags and matrices to retain the placed extent when resolution changes. |
| `setPlacement` | Writes a host-supplied affine matrix and explicit frame-angle policy without resampling. |

Replacement samples must contain complete rows. Changed planes/layouts renew
existing sample UUIDs while stable object identities and unrelated images remain
unchanged. Absent UUID fields stay absent. A retained source link is marked as
modified. Legacy stencil layouts can retain/replace pixels but do not acquire
invented alpha fields; alpha authoring requires qualified extended headers.

For `[a, b, c, d, tx, ty]`, embedded pixels map to
`(a*x - c*y + tx, b*x - d*y + ty)`. `rotationRadians` separately controls the
editing-frame angle: a finite value updates/adds it; null preserves absence and
rejects an existing field. It cannot be inferred uniquely from the matrix.
Unknown cache/relationship fields, including unresolved mask/shear metadata,
reject geometry edits. Enclosing clips, effects, groups, resources and artboards
are separate dependencies. The host supplies matching appearances after edits.

## Linked placements and previews

`AiNativePlacements.decode` reads CC placement sections, retaining raw path bytes,
relative directory, local bounds, affine matrix, file type, extensions, preview
and object dictionary. Preview byte boundaries are checked from their headers;
unknown bounded pixel layouts stay preserved. `preview.toSamples()` explicitly
converts qualified format-17 straight ARGB into RGB and separate alpha. It never
silently substitutes that preview for the full-resolution linked resource.

Qualified raster edits require file type 1, extensions `4 4 0`, consistent paths
and `IncludeFile` references, known versioned metadata and a nonsingular matrix.
The kit never opens files, resolves URLs or selects image decoders.

| Operation | Behavior |
| --- | --- |
| `translate` / `setPlacement` | Changes geometry while retaining link paths, preview data and local bounds. |
| `embed(object:, samples:)` | Replaces a link with host-decoded native raster samples while retaining placed extent and qualified metadata. |
| `relink(object:, pathBytes:, relativeDirectoryBytes:, preview:)` | Updates path operands, declarations, relative directory and explicitly supplied or removed preview. |

Embedding removes an old file dependency only when no other native reference
uses it. Relinking uses caller-selected path bytes and escapes native strings;
ambiguous/control-containing paths and unresolved metadata reject. Null relative
directory or preview arguments explicitly remove those records. New previews
use qualified 8-bit RGB with optional alpha. Neither operation resamples pixels
or changes catalog XMP automatically.

Linked matrices map local coordinates to `(a*x + c*y + tx, b*x + d*y + ty)`;
the local y axis points down. `rasterMatrix(width:, height:)` exposes the
corresponding pixel-to-native transform; `validateRasterLayout()` checks the
qualified layout independently. Frame-angle policy matches embedded rasters.
External PDF/EPS artwork, older `XF` links and dependent effect caches remain
unsupported for these edits.

## Catalog metadata

`AiXmpMetadata.fromPdf(document:)` reads catalog XMP; `parse(source:)` reads a
standalone UTF-8 packet. `resources` exposes current-document `xmpMM:Manifest`
and `xmpMM:Ingredients` references using namespace URIs. History, pantry,
`DerivedFrom`, other subjects and page/image metadata remain separate.

`relink(resources:, filePath:, documentId:, instanceId:)` updates explicitly
selected references, removes stale identifiers when null and clears alternate
paths. Native placement identity is not inferred from inventory order or equal
filenames. Managed, extended or part-specific references reject edits; unrelated
packet text, comments, namespaces, padding and metadata remain exact.

After the native/PDF save, `writeTo(document:)` installs the changed catalog
packet without changing shared original page/image packets. Old unreferenced
objects remain, so this is not redaction. PostScript-embedded XMP is not currently
read or rewritten by these APIs. XML limits apply before tree construction;
DTDs, undefined entities, non-UTF-8 declarations and ambiguous structures reject.

## Creating AI7 artwork and inspecting legacy files

`AiArtwork` writes an explicit AI7 subset from immutable layers, groups and
`AiArtworkPath` nodes. It supports open/closed Bézier paths, gray/RGB/CMYK paints,
fill rules, caps, joins, widths, miters and dashes. Layer visibility, locking and
printing flags survive; hidden children remain in the file. The generated
PostScript contains its own small prolog, which AiKit does not execute.

This is not a modern CC document constructor. It does not invent live-effect,
ATE, mesh, gradient or raster authoring records. Existing modern programs can be
inspected and edited within their documented contracts without conversion to AI7.

Legacy DSC inspection retains comments and continuations, resolves `(atend)`
metadata and prefers high-resolution bounds. Declared data and embedded documents
are skipped. DOS EPS section/preview ranges are checked and the entire envelope
is retained. Raster/placement previews use the same bounded binary readers as
native inspection.

`AiPostScriptDocument.dscIssue` reports a damaged or unsupported native binary
boundary with its offset relative to `postScriptBytes`. Only earlier comments
are exposed; later bytes are not searched for plausible metadata. Exact source
encoding remains possible. A null issue means inspection reached the end, not
that the document is executable or completely editable.

`AiPostScript.tokenize` exposes immutable source spans and Latin-1 lexemes for
numbers, names, strings, arrays, dictionaries, procedures, comments and protected
data blocks. It does not execute operators. Procedure braces must balance;
array/dictionary delimiters can cross procedure boundaries. Dynamic PostScript
and binary-token execution are outside the package contract.

## Supported data

“Editable subset” means that the APIs above can change qualified structures and
write them back. “Preserved” means retained source, not semantic editing support.
These statuses do not imply complete Illustrator compatibility.

| Feature | Read | Write/edit | Limit |
| --- | --- | --- | --- |
| PDF-backed AI and legacy containers | Yes | Yes | PDF graphs are rewritten; unchanged legacy bytes are preserved exactly. |
| Plain/zlib/Zstandard native envelopes | Yes | Yes | Shared owners and original compression retained on replacement. |
| Native layers | Headers, names, identities, wrappers and direct ownership | Header edits and qualified empty sibling insertion | Additional private header fields, masks, unresolved ownership and implicit view invalidation reject; removal/copy/move remain unqualified. |
| Ordinary native paths | Source-backed geometry and paint | Geometry and qualified ordinary-path lifecycle | Moves across changed state, dependent or unresolved ownership reject. |
| Ordinary native groups | Source topology and qualified declarative state | Group/ungroup, duplicate, remove, reorder and same-layer moves | Anonymous owners only; unknown required state, references, private/derived objects and cross-layer moves reject. |
| Hierarchical records and artboards | Source-owned settings, order, identifiers and origins | Existing record edits | No general document/artboard lifecycle API. |
| Source structure and version alternatives | Ordered owners, saved identifiers, both branches and qualified shared references | Inspection; existing edit contracts still apply | No target-version selection or unknown plug-in reference resolution. |
| CC live shapes | Five qualified families | Translate, rotate, uniform scale; supplied printing contours and qualified complete groups | Parameter changes, general affine resizing and unresolved printing dependencies remain incomplete. |
| ATE text, fonts, runs and frames | Named CS / compact CC | Editable subset; supplied layouts | Shaping and composition belong to the host. |
| Gradient resources and placement | Qualified classic layouts | Stops, focus, isolation, relative CC placement | Host supplies ramps; general appearance/resource editing is incomplete. |
| Cartesian mesh version 2 | Yes | Vertex color, tint and opacity | Geometry/topology edits incomplete; rendering belongs to the host. |
| Embedded raster samples | Qualified binary layouts | Pixels and affine placement | Explicit host pixels; unresolved caches reject edits. |
| CC linked rasters and previews | Qualified layouts | Relink, embed and affine placement | No filesystem resolution or general vector-link editing. |
| Catalog XMP dependencies | Qualified structures | Explicit selected-reference edits | No automatic native/XMP identity mapping. |
| New AI7 artwork | Yes | Typed subset | No creation of complete native CC documents. |
| Other effects, brushes, patterns, symbols and plug-ins | Source preserved where parsing permits | No general semantic writer | Recognizing a record does not qualify dependent edits. |

## Safety and platform behavior

AiKit has no Flutter or native rendering dependency. File access, resource
resolution, interactive tools and persistence belong to the application. Parsers
and edits use immutable snapshots and explicit resource limits:

| Policy | Default ceilings |
| --- | --- |
| `AiLimits.pdf` | PdfCore policy, including a 128 MiB file ceiling and depth 128. |
| DSC comments | 1 MiB per continued comment; 100,000 retained comments. |
| `AiNativeLimits` | 128 MiB aggregate encoded/filtered envelopes and decoded programs; 32 MiB Zstandard window; 1,000,000 tokens; depth 128. |
| Standalone tokenization | 128 MiB, 1,000,000 tokens, depth 128. |
| Shared text-engine parsing | 128 MiB, 1,000,000 values, depth 64, 64 MiB per decoded string. |
| `AiXmpLimits` | 8 MiB UTF-8 packet, 100,000 nodes/events including attributes, depth 64. |

Limits are checked before relevant allocation/output growth; they are not a
whole-process memory cap. Malformed structures raise `FormatException`; invalid
arguments or foreign handles raise `ArgumentError`; unqualified semantic
operations use `UnsupportedError`. Unknown containers are rejected, not treated
as arbitrary raw AI. An edit's rejection leaves the original snapshot intact.

## Corpus validation and compatibility

Run the package's offline checks with `dart analyze`, `dart test` and
`dart test --platform node`. The [external corpus guide](../test/corpus/README.md)
contains the required generators, pinned fixture manifests and independent
verification commands. Downloads and generated artwork remain ignored and
excluded from publication; provenance and licensing stay in the manifests.

Validation distinguishes native extraction, unchanged preservation, semantic
edits and save/reopen behavior. Independent readers check source records and
unselected data; external SVG rendering can additionally check qualified native
geometry without adding a renderer to AiKit. Host-supplied PDF/native save tests
check that both representations survive; they cannot prove visual equivalence.

Adobe Illustrator reopening and native Focale integration remain unqualified.
Past results from the removed native-to-PDF exporter are not current support
claims. Remaining package work is tracked in [ROADMAP.md](../ROADMAP.md).

## References

- [Adobe Illustrator 7 file format specification (mirror)](https://13thmonkey.org/documentation/fonts/AI7FileFormat.pdf)
- [Adobe DSC specification (mirror)](https://web.mit.edu/PostScript/Adobe/Documents/5001.DSC_Spec.pdf)
- [Adobe XMP resource references](https://github.com/adobe/xmp-docs/blob/e2573ad7e7959e657b1aed704546e19319cb4f5d/XMPNamespaces/XMPDataTypes/ResourceRef.md)
- [Adobe XMP media-management properties](https://github.com/adobe/xmp-docs/blob/e2573ad7e7959e657b1aed704546e19319cb4f5d/XMPNamespaces/xmpMM.md)
- [Native compression observations](https://gitlab.com/inkscape/extras/extension-ai/-/blob/1a5f42a0b0407fc869e032420570682048810108/docs/specification_amendments/compression.md)
- [Native hierarchy observations](https://gitlab.com/inkscape/extras/extension-ai/-/blob/1a5f42a0b0407fc869e032420570682048810108/docs/specification_amendments/hierarchy.md)
- [Native layer observations](https://gitlab.com/inkscape/extras/extension-ai/-/blob/1a5f42a0b0407fc869e032420570682048810108/docs/specification_amendments/layers.md)
- [Native text observations](https://gitlab.com/inkscape/extras/extension-ai/-/blob/1a5f42a0b0407fc869e032420570682048810108/docs/specification_amendments/text_documents.md)
- [Native document/artboard observations](https://gitlab.com/inkscape/extras/extension-ai/-/blob/1a5f42a0b0407fc869e032420570682048810108/docs/specification_amendments/document_data.md)
- [Native live-shape observations](https://gitlab.com/inkscape/extras/extension-ai/-/blob/1a5f42a0b0407fc869e032420570682048810108/docs/specification_amendments/live_shapes.md)
- [Native gradient observations](https://gitlab.com/inkscape/extras/extension-ai/-/blob/1a5f42a0b0407fc869e032420570682048810108/docs/specification_amendments/gradients.md)
- [Inkscape extension-ai corpus](https://gitlab.com/inkscape/extras/extension-ai)
- [PROOF native-record observations](https://github.com/vurglepuddle/PROOF/blob/d822dc5dea265675a0fd5dec550e3e0dcd5988f0/doc/PROOF-ai-native-records.md)
- [Zstandard specification, RFC 8878](https://www.rfc-editor.org/rfc/rfc8878.html)
- [PdfCore reference](../../PdfCore/docs/PDF.md)
