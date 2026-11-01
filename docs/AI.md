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

`replace` and `replaceAll` verify the catalog reference, page count and ordered page
references. They also require the original Illustrator dictionaries and their
transitively referenced PDF objects, including unselected programs. The host may
replace page contents/resources and unrelated producer metadata. Native metadata
mutations, stale extraction handles, a separately reparsed PDF, renumbering,
page insertion/removal/reordering and changed alias membership reject atomically.
Reacquire all handles after a save; use one batch to save several programs from
the same snapshot. Page/artboard remapping is not inferred from counts, bounds or
owner order. These two APIs preserve the existing mapping; use the explicit
mapped-save contract below for structural changes.

Replacement keeps the original compression family, rewrites every shared owner,
removes stale native thumbnail blocks, and preserves other producers and private
metadata, with the qualified cached-header synchronization below. Mixed native block families on one owner are rejected. New allocations
reserve existing dangling references. Old unreferenced objects may remain;
replacement is not a redaction operation. Encode the returned document with
`AiCodec`; file persistence and save checkpoints belong to the application.

Independent save checks cover 31 pinned PDF-backed fixtures and two synthetic
multi-program cases: 35 exact native programs, layer-name-only changes, shared
owners, unselected private metadata, page content and supplied PDF resources.
The synthetic cases include two native artboards and partial/batch saves. These
checks establish graph preservation, not visual correspondence or Adobe reopening.

### Explicit native/PDF page mappings

`AiNativeData.replaceMapped(replacements:, synchronizedPdf:, pageLabels:)` saves
one or more selected programs with an explicit resulting PDF page sequence.
Each `AiNativePageReplacement` contains the immutable native replacement and
ordered `AiNativePageBinding(page:, metadataOwner:)` entries. `page` is a current
indirect reference in the host graph. `metadataOwner` is the original extracted
source's page index, or null to select its catalog alias as a metadata template.
A retained native page must keep its own original metadata owner. A new native
attachment copies only Illustrator metadata from the explicitly chosen owner;
the host's other producer data remains intact. Original catalog aliases remain
attached automatically. No mapping is inferred from bounds, UUIDs or counts.

For one top-level native Document with one PDF page per artboard, use
`editedArtboards.pageReplacement(source:, pages:)`. Supply every current board
exactly once through `AiNativeArtboardPage(artboard:, page:, metadataOwner:)`.
This helper freezes the bindings in native board order; the save checks that
this order matches the host PDF, including when unrelated pages intervene:

```dart
final AiNativePageReplacement replacement = editedArtboards.pageReplacement(
  source: originalSource,
  pages: explicitArtboardPages,
);
final AiPdfDocument saved = AiNativeData.replaceMapped(
  replacements: [replacement],
  synchronizedPdf: hostPdf,
);
```

The host derives its graph from the original snapshot and supplies page content,
resources, boxes and dependent PDF structures. Every added PDF page and every
retained page of a selected program must be bound. Pages of unselected programs
cannot be deleted or have their relative order changed. New attachments cannot
overwrite existing Illustrator metadata, and new page references cannot reuse
any original object number, including dangling references. Removed page objects
remain unreachable with their original native metadata; their page dictionaries
may have been materialized by earlier host edits. This is not data erasure.

Original catalog identity, retained native dictionaries and dependencies of
retained/copied metadata stay unchanged. Reachable references to removed pages
and newly dangling references reject; preexisting dangling references remain
reserved. The host must update destinations, annotations, tags and any other
dependent PDF structure. Graph checks do not validate all semantic relationships
inside opaque bytes or attest to visual equivalence.

Page labels use numerical PDF positions. If page identities/order/count change,
the default `requireUpdated` policy requires the host to replace or remove the
existing label tree. Explicit `retainPositions` keeps labels at their numerical
positions. Supplied trees must have bounded acyclic structure, ordered unique
starts beginning at zero within current pages, consistent limits and valid label
styles, prefixes and positive counters. The kit does not infer labels from native
board names. Native saved print ranges have their separate edit restrictions.

After encoding and reopening a mapped save, extract its native sources again and
decode new artboard handles before the next edit. Metadata-owner indices refer
to that reopened snapshot's page order. Reusing pre-reorder indices would select
the wrong template for a new page; retaining old source handles rejects.

Fifteen regressions cover complete mappings, stale/foreign handles, immutable
inputs, metadata templates, catalog aliases, partial batches, opaque artwork,
removed-page destinations, dangling identities, label policies and budgets.
Chained saves additionally retain compound clips, hidden artwork, complete CC
pairs and shared resources across all four artboard operations and reopenings.
Independent checks verify seventeen serialized transactions: fresh page identities in
three pinned real files (including all five pages of the Illustrator 30.6 file),
eight consecutive native lifecycle saves in the pinned RGB/CMYK rectangle files,
four synthetic lifecycle edits and two multi-program partial/batch saves.
The three page-identity-only programs remain byte-identical. Each RGB/CMYK chain
creates a board/page, resizes it, reverses the order, then removes the original
active board/page with an explicit active replacement. Each step reads the
previous serialized result. All native edits are independently decoded; retained
board dictionaries/trivia, bytes outside prescribed edits, supplied PDF
content/resources and metadata templates are compared exactly.
These are serialization checks, not native rendering or Adobe reopening.

### Cached native headers

All native save APIs synchronize existing PDF `AIMetaData` streams when the
supplied native program changes its initial comment header. The original cache
must match either the complete source header through `%%EndComments`, or that
header without `%%DocumentFonts`, `%%DocumentNeededFonts` and their `%%+`
continuations. The same observed profile is applied to the supplied header,
preserving its line endings and unknown comments. No artwork operator is parsed
or rendered. A font-filtered cache can stay unchanged after a font-only edit.

If the source has no font declarations, those two profiles are indistinguishable.
Introducing fonts then rejects rather than guessing the cache's inclusion policy.
Other divergent profiles, missing header terminators and non-comment header data
also reject changes that require cache synchronization. Ten pinned older files
retain different canvas/resource values in their caches; their header-update
contract remains unqualified. When the native header is unchanged, all existing
caches remain exact, including opaque or divergent data. Missing/null caches are
not invented, and unselected programs remain untouched.

New cache streams retain unknown dictionary entries and references while dropping
old PDF filter/length declarations. Their bytes are written unfiltered. Shared
owners reuse the new stream; references outside the selected owners still reach
the old stream. Original native metadata must remain unchanged in the supplied
graph: callers supply native/header edits through the replacement program, not
by overwriting original metadata objects. Planning happens before graph mutation.
Encoded inputs, decoded inputs and cache outputs have separate aggregate bounds
using `AiNativeLimits`; header line inspection is bounded by `maxTokens`.

Nine regressions cover all native compression families, complete/filtered caches,
catalog/page aliases, independent and unselected programs, opaque drawing,
atomic rejection and budgets. Independent pypdf/Zstandard checks cover 32 pinned
PDFs and two synthetic saves: 22 real saves, ten explicit old-profile refusals,
31 updated owner caches and exact native/body/PDF-content/resource preservation.
This includes the five shared owners of the Illustrator 30.6 fixture. These are
serialization checks, not Adobe reopening or visual-equivalence certification.

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
ASCII XML name; collisions with saved native `XMLUID` values reject. Anonymous
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
edits. The additional lifecycle contracts and their reference restrictions follow;
Adobe reopening remains unqualified.

### Layer creation without a template

`AiNativeLayers.create(definition:, parent:, discardViewState:)` appends an empty
root layer or a last child of an owned layer. No existing sibling is required:
it can create the first layer or recreate one after removing every layer.
`AiNativeLayerDefinition` freezes explicit `attributes`, `nameBytes`, optional
`identifierBytes` and panel `expanded` state. It does not infer a CC document
profile, copy opaque metadata or invent a source identity.

The caller supplies one qualified integer-valued 10-, 13- or 14-operand `Lb`
header. Visibility, preview, enabled, printing, dimming, display colors and the
extended flags are validated; multilayer masks, extra operands, nonzero final
14-operand flags and fractional values reject. For example, the observed CC
header `[1, 1, 1, 1, 0, 0, 1, 0, 79, 128, 255, 0, 50, 0]` creates a visible,
enabled, printing layer. These are explicit producer-layout attributes, not a
general target-version policy or an independent document template.

Names use escaped native byte strings; fresh identities share the same whole-
document collision checks as duplication, including opaque `XMLUID` uses. New
layers retain the original LF/CRLF convention. Root counts update only when the
source declares them; absent declarations remain absent. Saved view mappings
require explicit invalidation, including their continuations. Qualified parent
headers can retain opaque children; existing artwork and persistent state remain
byte-exact. Foreign/stale or conditional parents, mismatched root declarations,
unknown header layouts and exceeded original limits fail atomically.

Eight regressions cover first/repeated creation, removal followed by recreation,
empty/populated parents, immutable definitions, names, all three layouts, absent
and changed-width counts, view declarations, opaque neighbors, collisions and
limits. Twelve independently decoded transactions cover six creations in three
pinned real sources and six synthetic creations. The verifier binds the new
empty owner, all original headers/identities and exact insertion/count/view edits;
no appearance or compatibility representation is generated. Adobe reopening
remains unqualified.

### Layer subtree movement

`AiNativeLayers` also moves complete qualified layer subtrees, retaining names,
XML identities, wrappers, panel expansion, the layers' own flags and descendants.
The caller selects immutable handles from the current inventory.

| Operation | Behavior |
| --- | --- |
| `reorder(layers:)` | Assigns the supplied sibling order to the selected source slots; unselected siblings keep their slots. |
| `moveAfter(layer:, after:)` | Inserts the subtree after another layer, using that anchor's parent. An ancestor may be an anchor when lifting a child out. |
| `moveInto(layer:, parent:)` | Appends the subtree before the destination's closing boundary, including an empty destination. |

Reordering requires one immediate parent and disjoint selections. Moving rejects
the selected layer itself or any descendant as the destination. Reparenting
requires explicit `inheritParentFlags: true`: the subtree keeps its own flags
and inherits its destination ancestors' visibility, locking and other layer
attributes. This choice does not rewrite the layer header to approximate its
previous effective visibility. Root counts update when a subtree enters or leaves
the root; saved panel data still requires `discardViewState: true` when present.

Layer boundaries do not supply an assumed paint reset. Source assignments restore
the moved subtree's incoming paint/object state and each affected slot's outgoing
state. A move leaves the selected subtree's persistent assignments at its old
position, without leaving its objects or point counts. Missing required values
reject rather than using guessed defaults. Added assignments are copied from the
original source; geometry, identities and shared resources are not regenerated.

For ordinary-only moves, the selected subtree and intervening interval must
contain qualified ordinary paths/groups, known process paint and layer
headers/identity dictionaries.
Private/derived artwork, compound or clipped geometry, unresolved prefixes or
postfixes, conditional records, orphan point counts and unknown state operators
reject. Unrelated opaque siblings outside the interval remain exact. Moving an
empty layer into an opaque parent's ending slot does not require interpreting
that parent's earlier artwork. This is not general opaque-object relocation.

Capabilities report `layerReordering` and `layerReparenting` as
`requiresValidation`. Sixteen focused regressions cover the state, ownership,
limits and explicit policies, including CMYK/RGB alternatives, dashes and a
100-layer batch. Independent checks qualify 12 movements and their two insertion
prerequisites across three pinned recent files and a checksum-pinned synthetic
source. They compare complete decoded trees, identities, path geometry/counts,
known effective attributes and exact unselected bytes. Adobe reopening remains
unqualified.

### Layer duplication and removal

`duplicate(layers:, identifiers:, artworkIdentifiers:, names:)` copies complete
ordinary subtrees immediately after each selected original. Every identified
layer descendant requires one entry in `identifiers`, keyed by its current
`AiNativeLayer` handle. Every identified path/group descendant requires an entry
in `artworkIdentifiers`, keyed by its original drawing handle. Values
must be fresh portable ASCII XML names, distinct from all saved native `XMLUID`
values and every other copy in the transaction. Missing descendants, extra
or foreign handles and collisions reject. Both maps share one identity namespace
and aggregate encoded-byte budget; a new artwork ID cannot reuse a new layer ID.
Anonymous layers and objects stay anonymous.
Reservation includes wrappers in unrecognized record owners, private records and
both saved version branches, using decoded literal/hexadecimal string bytes.
Those values may be declarations or references: reusing either could introduce
a collision or bind a previously unresolved reference to the copy. They remain
unchanged, and repeated existing values do not prevent a distinct new name.
An unresolved `XMLUID` value shape rejects new identity allocation. Anonymous
copies allocate no identities and do not require that extra qualification.
Ordinary string fields, artboard UUIDs and separate embedded documents do not
share this namespace. This is reservation of explicit native wrappers, not
decoding identities hidden inside unknown binary or plug-in encodings.
Optional `names` entries replace existing display-name byte strings in the copies;
other display names and saved expansion flags remain unchanged.

The copy retains exact geometry, counts, flags and nested order. Only supplied
identity/name string tokens change inside the copied source span. Source-backed
assignments preserve inherited and outgoing paint, as for movement. External
references to original identities remain attached to the original objects; this
API does not redirect those references to the copies. Opaque, derived or privately
referenced artwork inside the selected subtree still requires another contract.
Seven reservation regressions cover these boundaries across path/group copies,
subtree copies and empty-layer insertion. Independent checks additionally verify
fresh copies and exact collision refusals beside injected `XMLUID` wrappers in
the synthetic source and one pinned CC document, without changing those owners.

`remove(layers:)` deletes complete selected subtrees and their consumed point
counts, retaining persistent assignments needed by following artwork. Nested
removal can leave an empty parent; selecting every root can leave a zero-layer
native program. Drawing bounds remain conservative instead of shrinking.

Removing an identity requires stronger reference qualification than copying it.
The qualified identified-source subset contains ordinary declarative artwork,
complete CC authoring/printing pairs, qualified layer/path/group metadata,
literal native styles, counted gradient banks and explicitly checked setup
`Document` records. Unknown resource records, opaque owners, unqualified executable
sections, structured comments and ambiguous selected identities reject. Known DSC
metadata, numeric document headers and layer count/view declarations are allowed.
Saved header version branches retain their separate known values. The exact
standard `gsave annotatepage grestore showpage` trailer is preserved; arbitrary
PostScript remains outside this declarative contract. This deliberately does
not infer the absence of references from a missing literal name: Adobe UID
references can be stored in document dictionaries, as described by the
[Adobe dictionary suite](https://ai-sdk-2020.84.nz/html/struct_a_i_dictionary_suite).
Documents with unresolved artwork/resource references therefore retain a stricter
removal restriction than duplication.
Anonymous subtrees retain their local ownership/state checks and may be removed
beside unrelated opaque siblings. An identified descendant still activates the
reference checks even when the selected root is anonymous. The same whole-source
check now governs identified path and group deletion, including every identified
descendant of an anonymous group. Known names/rotation fields do not imply
references, but unqualified fields or owners cannot be ignored.

Document qualification checks each known field's exact owning section and scalar
type. Supported metadata includes artboard descriptors, page/grid/bleed settings,
save options and observed PDF/print presets. The exportable-asset dictionary,
saved-selection arrays and ink-reference table must be empty. Native XML metadata
must have the known structural tree with empty variable definitions, sample data
sets and slices; unknown children, attributes or values reject. Other nonempty
reference owners cannot be cleared implicitly. Color-profile data must have the
expected binary owner, matching declared/ICC header lengths and `acsp` signature.
Profile decoding uses the original byte ceiling, and structured annotations
outside its binary payload still reject. Custom screening code, unknown fields,
repeated owners and conditional document records remain unqualified. These checks
permit deletion; they do not edit settings, validate every ICC tag, or introduce
color management.

The same reference qualification now applies to identified paths, groups, layers
and complete CC pairs. Every neighboring pair must have qualified geometry,
metadata alternatives, shared styles and resource ownership. Private scalar
assignments left by earlier pair edits are allowed; unknown private instructions
remain unqualified. Ordinary objects before or after a wrapped layer retain their
separate ownership from adjacent pairs and their printing expansions.

Retained `KnownStyle` declarations, including unused styles, require literal
supported filter graphs without opaque annotations or external plug-ins. Gradient
resources require complete parsed stops/ramps, matching source wrappers, ordinary
unconditional boundaries and correct `Bn` bank counts. Balanced nonprinting
setup sections retain their original placement. Intervening structured comments
remain subject to reference checks; numeric count tokens cannot hide them.
Style/gradient names have their own namespaces: a resource name equal to a removed
artwork identity remains unchanged. Resource definitions, uses, compatibility
stops and cached ramps are preserved exactly; this does not delete or retarget
resources or nonempty saved-selection/asset references.

Thirteen regressions cover mixed-owner removal, private scalar replay, unused
styles, separate identity namespaces, layer boundaries, ambiguous references,
conditional resources, malformed counts and hidden metadata. The independent
suite checks 18 fixed transactions: four removals from declared assemblies of
five pinned real sources, six synthetic removals and eight exact refusals.
Each real assembly retains an entire CC document source and inserts one exact
donor pair, its style and selected gradient definitions with explicit initial
state. Its recipe is independently reconstructed and every fragment is bound to
the original native parse. These are derived fixtures, not successful removal
from the four complete donor files: those still reject their unqualified setup
owners. Checks retain exact resource and unselected source bytes, both pair
metadata branches, layer declarations and native/printing appearance. Synthetic
native SVG remains limited by the external reader's version-branch dispatcher.
Complete mixed-parent movement is described separately below;
Adobe reopening and broader reference-owner schemas remain unqualified.

Both APIs validate disjoint owned selections, complete output/token budgets,
root-count updates and explicit saved-view invalidation atomically. Capability
reports expose `layerDuplication` and `layerRemoval` as `requiresValidation`.
Ten additional regressions cover immutable inputs, batch copies, identities,
reference refusals, deletion, limits and remaining state. Independent checks add
three duplications and four removals: recent native sublayer/subtree copies,
synthetic nonempty identified deletion and an anonymous AI7 insertion/removal
regression. They verify decoded identities, trees, geometry/counts, paint state
and exact bytes outside authorized source/string spans. General referenced
deletion, opaque/derived lifecycle and Adobe reopening remain unqualified.
Eleven reference-scope regressions additionally cover identified path/group/layer
removal beside document metadata, malformed profiles, unknown fields, nonempty
reference tables, XML bindings, conditional ownership, executable sections and
header token limits. Independent checks verify nine identified-layer deletions in
pinned uncompressed CC sources and three synthetic artwork/subtree deletions.
All document bytes, artboards, decoded profiles and unselected data remain exact;
LittleCMS also opens the real retained ICC profiles. Two injected real-document
references reject without changing any source byte. This does not qualify
deletion beside arbitrary shared styles, text engines or plug-in data.

### Attached object metadata

`AiNativeObjects.decode(drawing:)` exposes immutable path/group associations with
an optional directly attached `ArtDictionary`. Groups also retain their preceding
panel `expansion` instruction, decoded `expanded` flag and postfix
`styleApplication`. `forSource` requires an exact
handle from that drawing. Each object retains its lexical `node`, original
`source`, complete `start`/`end`, dictionary, saved XML `identifier`, and source
name fields. `liveShape` retains any native shape associated with that path's
direct dictionary; a non-null association alone does not grant lifecycle edits.
Layer-header dictionaries keep their separate `AiNativeLayers`
ownership. Inspection includes private/compound/derived objects without granting
ordinary lifecycle permission. `bindingIssue` reports unqualified metadata;
malformed identity syntax still fails structural validation.

Ordinary lifecycle currently qualifies empty dictionaries and the observed
`AI10_ArtUID`, `AIArtName`, `Object name` and finite `BBAccumRotation` fields.
Names preserve their string type and original bytes. These records do not change
persistent paint state. Bare and `%_` syntax are retained; interleaved operators,
version boundaries, repeated dictionaries, private appearance fields, SVG import
records and unknown reference fields remain separate dependencies.

Direct live shapes can participate when their single non-private path is also
their complete appearance, without a separate printing group, appearance
dictionary, style or version alternative. The attached `ai::LiveShape` definition
must contain exactly a known handler and its parameter dictionary. Only the
handler's known scalar parameter keys/types and optional boolean
`PATH_IS_KAPPA_CURVE` metadata qualify; unknown, nested or reference-bearing
extensions reject. Structural edits carry the entire path and dictionary without
rebuilding geometry or interpreting a rendering result. Copies retain editable
parameters and use fresh IDs under the same identity contract. Group and layer
subtree operations count and preserve all qualified direct shape children.
Removal deletes their native parameters with their geometry. Insertion after a
shape creates a plain path, without copying its native definition. Separate
private/printing pairs, gradients and conditional alternatives still require
their own lifecycle contracts. Unbound neighboring shapes retain exact source
bytes and binding status after every structural edit.

Group lifecycle also qualifies an immediately preceding `0 Ae`/`1 Ae` and an
immediately following `9 () XW`, optionally after the group's dictionary. The
first retains the Layers-panel expansion; the second applies default style to
that group without changing the persistent path-opacity assignment. Complete
object boundaries include both attachments. Named styles, other `XW` modes,
private/conditional syntax, repeated attachments and intervening native metadata
remain unqualified. These associations follow the pinned independent reader's
[operator descriptions](https://gitlab.com/inkscape/extras/extension-ai/-/blob/1a5f42a0b0407fc869e032420570682048810108/docs/specification_amendments/commands.md).

Path/group movement and reordering carry all qualified attachments with the object.
Insertion occurs after the anchor's complete metadata, leaving the new path anonymous.
`duplicatePaths` and `duplicateGroups` take an `identifiers` map keyed by original
path/group handles. Supply exactly one fresh portable XML name for every copied
identified object, including group descendants. Source-wide collisions, extra or
foreign handles and missing identities reject atomically. Anonymous objects stay
anonymous. Only the copied identifier string tokens change; names, rotation,
geometry, remaining dictionary bytes and references to originals stay exact.

Deletion removes the attached dictionary with its object. Identified path/group
deletion uses the whole-source reference qualification described above; an
unknown neighboring owner prevents it even outside the selected subtree. Ungrouping
preserves child metadata and removes empty group dictionaries. Discarding a
nonempty qualified dictionary requires `discardMetadata: true`; group names,
identities and rotation are then removed rather than transferred to a child.
Only the removed parent identities undergo the whole-source reference check.
Ungrouping removes an owned panel flag and the qualified neutral `9 () XW` group
reset. Named styles, blend applications and private reset commands still require
separate appearance contracts. Layer movement retains child object identities.
Layer duplication requires fresh child IDs through `artworkIdentifiers`; layer
removal checks all child identities against the same qualified reference scope.

Sixteen regressions cover whole-object edits, nested copies, repeated operations,
immutable identity maps, stale handles, unknown dictionaries, counts, byte/token
limits, layer transfer and capability findings. Independent pinned-inkai checks
verify five synthetic identity transactions, including complete topology, decoded
metadata, effective paint and exact unselected bytes. Twelve additional regressions
qualify panel/style ownership and persistent path opacity through nested copies,
reordering, removal, child edits and cross-layer moves, with malformed/private
attachments, identity maps, unknown required state and parser limits.
Five independently checked edits of `layers_and_sublayers.ai` now qualify path
copy/removal/reordering and group copy/removal, preserving its panel flag, three
empty dictionaries and default group style. Dissolving that styled group still
rejects without changing the source. Five more synthetic transactions compare
nested panel/style ownership, effective opacity and exact unselected bytes.
Eleven further regressions cover combined layer/artwork identity allocation,
copy-map ownership and cross-map collisions, identified deletion, anonymous owners
with identified descendants, immutable inputs and aggregate byte/token ceilings.
Six additional independently decoded synthetic transactions qualify root/batch
copies and path/group/subtree/all-layer removals, comparing complete hierarchy,
metadata, effective paint, point counts and exact unselected bytes. No new IDs or
references are inferred for an unsupported resource owner.
This is not evidence of successful identified-object editing in resource-bearing
real CC files or Adobe reopening. Wider dependencies remain in the roadmap.

Thirteen direct-shape regressions cover parameter ownership, editable copies,
identified deletion, ordering, cross-layer/group movement, subtree copies and
removal, grouping/ungrouping, insertion, stale handles and limits. Unknown
parameters, private/derived pairs and unresolved prefixes reject atomically.
Independent checks qualify 14 copy/removal transactions on seven pinned CC files
with direct rectangles or ellipses, including rounded corners and opacity, plus
seven identified synthetic path/group/layer transactions. Complete native
parameters, hierarchy, source counts and unselected private/style records remain
exact. This does not qualify new shape creation or every known shape handler.

### CC authoring/printing pair duplication

`AiNativeDrawing.duplicateLiveShapes(shapes:, identifiers:)` copies complete bound
CC pairs immediately after their originals. Each pair includes its optional panel
flag, ordinary/compound printing group, redundant dictionary, private authoring
contour, recorded native parameters, older metadata alternative and final named
style application. Existing styles and gradient definitions remain shared and
unchanged. The operation never derives either representation from the other.
Direct single-path shapes continue to use `duplicatePaths`.

The selection must contain distinct handles from the current snapshot. Qualified
parents are ordinary groups or layers; an outer condition, private parent,
unresolved prefix/postfix or hidden payload prevents copying. Local dictionaries
require known scalar fields, and referenced styles/resources require unique,
unconditional ownership. Rectangle corner selectors retain their string encoding;
polygon/star selectors retain their numeric encoding. Known filter fields are
typed literals. Unknown plug-ins or reference-bearing extensions reject. Owned
printing and private point counts travel with their respective paths. Whole saved
metadata alternatives remain intact; no target version is chosen or synthesized.

`identifiers` maps each identified `AiNativeContainer` within the copied pair to
one fresh portable XML name. This includes redundant and alternate dictionaries
when they have their own saved IDs. Supply exactly these owners. Allocation uses
the source-wide reserved XML namespace, including opaque records; stale/extra
handles, missing IDs and collisions reject the batch. Only the copied identity
strings change; existing references still refer to their original objects.
Repeated identities within the selection reject until their alias relationship
has an explicit copy contract.

Copies retain inherited state separately for the printing stream and the native
stream that also includes private commands. Source values are replayed only when
the original can change an attribute read by its copy. The complete pair restores
its original outgoing assignments. Known-style paint parts contribute their
literal dependencies without executing filters or generating contours. Ambiguous
incoming values are not replaced with assumed defaults. In particular, some first
objects in the corpus lack an explicit inherited `D` value and remain rejected.
Malformed, conditional or opaque neighboring state cannot establish a value.
The `liveShapeDuplication` capability therefore requires operation-specific
validation, even when the pair is bound.

Fifteen regressions cover batches, editable copies, metadata identities, version
alternatives, panel flags, separate printing/private attributes, native dash
serialization, unknown fields/plug-ins, stale handles and limits. The optional
corpus checks copies of ellipses, polygons, stars, lines and linear/radial gradient
pairs, plus identified synthetic pairs and exact first-object refusals. Its
unchanged independent reader compares complete records, source bytes and native
owner flags. Fourteen real-file transactions compare both native and printing
SVG geometry/styles/resources. Four synthetic transactions compare printing SVG
and both independently decoded metadata alternatives: the pinned SVG dispatcher
ignores the lists returned for versioned dictionaries, so its native SVG is not
used as evidence for those cases. Four first-object refusals retain exact bytes. These
checks do not establish Adobe reopening or deletion, reordering and reparenting
of separate authoring/printing pairs. Saving updated PDF artwork still requires
a matching representation supplied by the host.

### CC authoring/printing pair removal

`AiNativeDrawing.removeLiveShapes(shapes:)` removes each selected complete pair,
including its printing groups, private contour, point counts, panel flag and all
saved metadata alternatives. It retains the shared styles, gradient resources,
document bounds and every unselected source byte. Selection handles must belong
to the current immutable snapshot; direct single-path shapes use `removePaths`.

Public and private scalar assignments within removed objects remain in their
original order and source projection. Definite scalar assignments from a known
style are replayed privately when every visible paint part that assigns the
attribute agrees on its value. Color clearing, hidden parts and other uncertain
outgoing effects are not synthesized. The remaining source is checked for reads
of these unresolved attributes before explicit reassignment. A following path,
group or style that depends on one rejects the complete transaction. Unused
terminal effects need no replacement. This qualifies first-object removal even
when duplication cannot establish the object's incoming state.

Deleting saved identities additionally requires a document-wide reference check.
Every paired owner and its style must qualify; ordinary artwork/layers and the
existing declarative document metadata contract cover the remaining source.
Both newer and older dictionary IDs must be unambiguous. Unknown setup resources,
unused unqualified styles, reference-bearing extensions or unresolved owners
prevent identified deletion. No shared resources are deleted or renamed.
The `liveShapeRemoval` capability requires operation-specific validation.

Fourteen regressions cover batches, identities, two state projections, definite
style replay, dependent following artwork, reference refusals, owned attachments,
snapshot handles and limits. Independent validation covers 27 transactions and
71 deleted pairs: 17 real-file removals compare native and printing SVG; seven
synthetic removals compare printing SVG, decoded alternatives and native flags;
three refusals retain exact source bytes. Replacement gaps contain only parsed
source assignments and qualified style scalars; every other byte remains exact.
The synthetic native SVG limitation described above still applies. These checks
do not establish Adobe reopening, pair reordering or pair reparenting.

### CC authoring/printing pair reordering

`AiNativeDrawing.reorderLiveShapes(shapes:)` places complete selected pairs into
their existing sibling slots in the requested order. Unselected slots remain
unchanged. All selected pairs must have the same immediate native parent; an
unchanged valid order returns the original snapshot. Private contours, printing
groups, panel flags, counts, both metadata alternatives and saved identities move
as exact source blocks. Shared resources and opaque external reference records
remain unchanged; no identities are allocated or deleted.

Incoming and outgoing attributes are tracked separately for printing and native
interpretation. Known source assignments restore values around relocated pairs.
An unknown value can remain unchanged only when its source provenance agrees;
opaque or conditional boundaries cannot establish equivalence. Qualified complete
gradient fills retain their scoped procedure changes without invalidating unrelated
global flags. Unknown required input values reject instead of receiving defaults.

When a destination's original outgoing value is unknown, each following source
dependency is checked until explicit reassignment. Both native and printing reads
must remain valid; private assignments cannot restore printing state. Attributes
unused by subsequent artwork need no synthesized value. In particular, inactive
stroke attributes can differ in a derived printing stream while its explicit
`stroke:none` retains identical ink. Authoritative native records remain exact.
The `liveShapeReordering` capability therefore requires operation-specific checks.

Sixteen regressions cover complete permutations, nonconsecutive slots, saved
identities, opaque references, both state projections, panel flags, unchanged
orders, unknown provenance, outgoing dependencies, snapshot handles and limits.
Independent checks verify 24 transactions: 12 real-file and six synthetic
permutations, two unchanged orders and four exact refusals. Pair bytes, metadata
alternatives, unselected gaps, source-derived replay and both contour-state streams
are checked independently. Real-file native/printing SVG and synthetic printing
SVG retain geometry, active paint and resolved resources in the requested order.
The only permitted SVG attribute differences are inactive leaf-stroke settings;
those cases additionally require pixel-identical RGBA output from librsvg. The
synthetic version-branch SVG limitation still applies. This does not establish
Adobe reopening or cross-parent pair movement.

### CC authoring/printing pair movement

`moveLiveShapeAfter(shape:, after:)` relocates one complete pair after another.
`moveLiveShapeToGroup(shape:, group:)` appends it before an ordinary group's
closing boundary, and `moveLiveShapeToLayer(shape:, layer:)` appends it directly
to a layer. Empty groups and layers are valid destinations. Handles must belong
to the current snapshot; self anchors, printing expansions, private/compound/clip
parents, conditional ownership and unresolved parent metadata reject.

Private contours, printing groups, counts, panel flags, both saved metadata
alternatives and identities move as an exact source block. No identity is removed
or allocated, so external reference records remain unchanged. Layer headers,
declarations and saved panel state remain in place. Parent changes leave geometry
in document coordinates; no host rendering or layout generation is performed.

Changing layers, ancestor-group depth or inherited group visibility/locking
requires `inheritParentFlags: true`. Ancestor flags are compared independently
in printing and private interpretations. The opt-in accepts the destination's
parent flags; it does not bypass state, metadata or dependency qualification.

Explicit source assignments and definite style scalars remain at the old
location. Source-derived prefixes restore the pair's inputs at the insertion
point, and suffixes restore known destination values. Dependencies are checked
in final lexical order at both boundaries, including unknown native style effects
and independent printing state. Private reassignment cannot hide a printing
dependency. Required unknown input or unresolved subsequent reads reject
atomically; aggregate byte/token limits also apply to replay growth.
The `liveShapeReparenting` capability therefore requires operation-specific checks.

Seventeen regressions cover forward/backward movement, empty destinations,
cross-layer and ancestor-flag inheritance, exact pair bytes, metadata alternatives,
external references, source/destination dependencies, malformed boundaries,
snapshot handles and parser limits. The independent movement suite uses four
pinned real files and nine checksum-pinned synthetic sources. Its 32 fixed
transactions cover 12 real and 12 synthetic moves plus eight exact refusals.
It checks complete pair bytes, both metadata branches, literal unselected gaps,
source-backed scalar replay, both contour-state streams and independently parsed
parent trees. Real native/printing SVG comparisons and synthetic printing SVG
comparisons verify the requested relocation with retained enclosing appearance.
The earlier restrictions on inactive stroke attributes and synthetic native SVG
apply. These checks do not certify Adobe reopening or general object reparenting.

### Ordinary path lifecycle

`AiNativeDrawing` supports the following operations on independent ordinary
paths. Select handles from the current drawing; empty, repeated, foreign and
stale selections reject before any source edit is applied.

| Operation | Behavior |
| --- | --- |
| `createPath(definition:, parent:, layer:)` | Appends explicit ordinary geometry and paint at the root or inside an owned group/layer; no sibling or template is required. |
| `duplicatePaths(paths:, identifiers:)` | Copies each complete qualified path and its metadata after the original; identified paths require fresh supplied IDs. |
| `removePaths(paths:)` | Removes geometry/paint and its consumed point count. Persistent state and conservative drawing bounds remain. |
| `insertPaths(insertions:)` | Inserts supplied geometry after each anchor, inheriting its paint, flags and count convention. Multiple insertions at the same anchor retain input order. |
| `reorderPaths(paths:)` | Places selected siblings into their existing source slots in the requested order, carrying geometry, paint and count syntax together. |
| `movePathAfter(path:, after:, inheritParentFlags:)` | Moves a path after an anchor; different layers, ancestor flags or depth require explicit destination inheritance. |
| `movePathToLayer(path:, layer:, inheritParentFlags:)` | Appends a path directly to an existing, possibly empty layer without changing its header or saved panel data. |
| `movePathToGroup(path:, group:, inheritParentFlags:)` | Appends a complete path and its metadata inside an existing ordinary group, including an empty destination. |

`AiNativePathInsertion` freezes supplied `segments` and requires host-computed
ink `bounds`. Geometry has one initial moveto and portable finite coordinates.
Counted closed paths receive a closing endpoint when needed. Bounds expand the
existing drawing extent without changing artboards or PDF pages. All operations
reparse under the original source limits and return immutable snapshots.

`AiNativePathDefinition` supplies immutable `AiArtworkPath` geometry and process
paints, host-computed ink `bounds`, an optional point count, hidden/opacity and
overprint values, and optional byte-valued name and fresh XML identity. The
artwork model is used only as a data value; native creation does not call its
standalone AI7 writer. Gray, RGB and CMYK channels remain in their supplied space.
Open/closed lines and cubic shorthand retain their operators. Fill-only,
stroke-only, combined and unpainted paths have explicit consumed state, with
line width, caps, joins, miter and dashes when stroked. Counted closed paths receive
an explicit closing endpoint if needed. Coordinates and line values must be
finite and portable; opacity uses the qualified `0 opacity 0 0 0 Xy` layout.

Creation accepts a root, ordinary group or qualified layer, including a newly
created or emptied owner. Parent flags remain inherited. It restores known
outgoing native and printing state separately and rejects when a following old
object needs an overwritten value that cannot be recovered. A fresh path cannot
capture an existing count, expansion flag, note or dictionary. Only the inserted
object, necessary scalar replay and the union of declared drawing bounds change;
layers, saved views, artboards, existing identities and complete CC alternatives
remain untouched. The caller supplies updated PDF artwork when saving.

Eight regressions cover the first path, 48 process-color/closure/count/paint
combinations, cubic and shorthand curves, empty/populated/hidden parents,
subsequent duplication/removal, both state projections, immutable metadata and
limits. Eighteen fixed independent transactions verify seven creations in three
pinned real sources, ten synthetic creations and one immutable refusal. The
reader checks geometry, counts, metadata, native ownership, both consumed paint
projections, exact unselected bytes and declared bounds. This qualifies ordinary
native data creation; new private live-shape parameters, advanced appearances,
whole CC document creation and Adobe reopening remain separate contracts.

These APIs accept paths whose ownership, metadata and inherited appearance are
isolated. Qualified attached identities move with their artwork and require
fresh replacements for duplication, as described above. Identified deletion
requires a qualified whole-source reference scope. Private paths, live-shape expansions, gradients, compound/clip members, version
alternatives, tags, notes and unresolved metadata reject. Qualification includes ordinary parent groups/layers and postfix records,
even when state assignments separate an object from its metadata. A completed
bound live shape does not by itself make the next ordinary path an expansion.
Unselected opaque setup or sibling data can remain unchanged outside that scope.

Persistent paint, lock and visibility assignments stay at their source positions.
Reordering and movement can replay known source assignments around the copied
geometry to retain its own attributes and restore the destination's outgoing
state. The qualified components are gray/RGB/CMYK fill and stroke, overprint,
line width/dashes/caps/joins/miter, path/fill flags, locking, visibility and the
observed `0 opacity 0 0 0 Xy` layout with finite opacity in `[0, 1]`.
Other `Xy` layouts, including the `-1 --` sentinel, remain unqualified.
Color alternatives retain their exact syntax without conversion. Missing values
stay unknown; moving a known value to a position where the original value cannot
be restored rejects. Opaque intervals, interleaved metadata, malformed state and
unowned point counts also reject atomically.

Ordinary `u`/`U` boundaries do not save and restore paint; movement can cross
them while retaining source state. Ancestor groups retain their original flags. Different ancestor
depth or lock/visibility flags require `inheritParentFlags: true`: the moved path
keeps its own attributes and accepts destination-group inheritance. Equal known
ancestor states, or values with the same unchanged unknown provenance, need no
extra policy. Cross-layer movement always requires explicit destination
inheritance and qualified layer headers; paint continues across those headers.
These operations do not create or remove groups, layers or shared resources,
and do not delete or redirect existing referenced identities. Capabilities report lifecycle operations as requiring
selection-specific validation.

Nine additional regressions cover changed process paints, all qualified state
components, ancestor inheritance, unknown/malformed state, unselected opaque
bytes, budgets and a 150-path permutation. Independent checks cover 16 variants
across two pinned recent Illustrator files and checksum-pinned synthetic
counted/grouped/state sources, including retained ownership, effective path and
owner flags, exact unselected bytes and counts. Added assignments must match
original source values. Adobe reopening remains unqualified.
Saving changed geometry requires matching PDF artwork supplied by the host.

`movePathToGroup` carries the complete consumed `As` count, any qualified scalar
assignments between that count and geometry, and attached path metadata. Their
persistent effects remain at the old slot for following artwork. At the new slot,
only consumed incoming state is replayed, and outgoing destination state is
restored. Native and printing projections are checked separately. Qualified
direct live shapes retain their parameter dictionary; partial CC pairs cannot be
selected as paths. Complete neighboring CC pairs may be crossed without changing
their bytes or saved alternatives. This also supports appending within the same
parent and crossing layers with explicit inheritance. Compound, clipping, private
and unresolved destination groups remain unsupported.

Ten regressions cover empty/populated parents, both directions, counted state,
direct shapes, identified references, hidden layers, stale handles and limits.
Independent checks cover 15 fixed transactions: four successful moves in three
pinned real sources, eight synthetic moves and three immutable refusals. Native
topology, point counts, consumed paint in both projections, all pair alternatives
and moved/unselected bytes are checked. Fifteen SVG/pixel comparisons qualify the
requested placement for the other eleven successful moves. The counted-state
case has native-data validation only: the pinned SVG reader's `attach_path`
incorrectly clears persistent fill after a stroke-only path, so its following
fill cannot serve as an appearance oracle. Synthetic native version branches and
Adobe reopening remain unqualified; no reader or host rendering code is changed.

### Ordinary group lifecycle

`AiNativeDrawing` also supports qualified ordinary `u`/`U` owners. A selected
group can contain nested ordinary groups, qualified paths and process-paint or
object-state assignments. Empty owners are supported. Batch selections must be
owned, distinct and disjoint; selecting an ancestor and descendant together
rejects before editing.

| Operation | Behavior |
| --- | --- |
| `createGroup(parent:, layer:, nameBytes:, identifierBytes:, inheritParentFlags:)` | Appends an empty ordinary group at the root or inside an owned group/layer without existing siblings. |
| `groupPaths(paths:, inheritParentFlags:)` | Wraps consecutive sibling paths in one group, preserving source order, consumed point counts and intervening qualified assignments. |
| `groupArtwork(paths:, groups:, liveShapes:, inheritParentFlags:)` | Wraps consecutive mixed sibling owners, keeping complete CC pairs and their alternatives together. |
| `ungroup(groups:, discardMetadata:, inheritParentFlags:)` | Removes selected boundaries and explicitly discarded parent metadata; children and local state remain. |
| `duplicateGroups(groups:, identifiers:)` | Copies the complete subtree with fresh supplied IDs for every identified group/path and restored incoming/outgoing state. |
| `removeGroups(groups:)` | Removes the subtree's objects and counts, retaining its persistent assignments for following artwork. |
| `reorderGroups(groups:)` | Places selected siblings into their existing slots in the requested order, restoring each slot's original outgoing state. |
| `moveGroupAfter(group:, after:, inheritParentFlags:)` | Moves a subtree after an anchor, with explicit inheritance for different layers or ancestor-group flags/depths. |
| `moveGroupToLayer(group:, layer:, inheritParentFlags:)` | Appends a complete ordinary subtree directly to an existing, possibly empty layer. |
| `moveGroupToGroup(group:, parent:, inheritParentFlags:)` | Appends a complete ordinary parent inside another, including an empty destination and qualified CC descendants. |

Ordinary groups do not save and restore paint. The editor tracks explicit source
assignments for gray/RGB/CMYK fill and stroke, overprint, width, dashes, caps,
joins, miter limit, fill/path flags, locking, visibility and qualified `Xy` opacity. Color representations
are copied without conversion. Missing values stay unknown; no renderer or
default graphics state is invented. An operation that needs to restore an unknown
value rejects. Source values can become known again after an opaque boundary
only through explicit assignments.

`createGroup` requires at most one group or layer destination. It writes only the
new `u`/`U` boundaries and explicitly supplied name/identity fields. Anonymous
groups have no dictionary; names are escaped native bytes and identities must
be fresh across all saved `XMLUID` owners and uses. Current object flags and
ancestor flags remain inherited, with explicit `inheritParentFlags` for unknown
or non-neutral current locking/visibility in either projection. It writes no
paint assignments, layer declarations, view invalidations or derived artwork.
The source's LF/CRLF convention is retained. Existing unowned `Ae`, point counts,
notes and unresolved prefixes cannot become attached to the new owner.

Eight regressions cover first creation, duplication/removal/recreation, empty and
populated parents, newly created/hidden layers, metadata, complete CC siblings,
explicit flags, stale handles and limits. Thirteen fixed independent transactions
cover seven creations in three pinned real sources, five synthetic creations and
one immutable refusal. Complete pair alternatives, contour flags in both
projections, original layer headers and every unselected byte remain exact. The
independent tree gains only the requested empty child and metadata. This qualifies
native creation without a renderer; Adobe reopening remains unqualified.

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

Except for complete-pair subtree lifecycle below, private/derived owners,
compound/clip children, version alternatives, opaque
metadata, tags, unbound expansion flags, notes and unknown state reject. Known identities,
names, panel flags and default-style attachments stay with their objects. Nonempty
group dictionaries need explicit disposal during dissolution; applied group styles reject.
Moving cannot cross opaque/private intervals; source and anchor groups cannot contain
one another. Shared styles, effects and references in
resource-bearing documents need separate lifecycle contracts. Group capabilities therefore remain
selection-dependent, with compound/private/clip topology explicitly unsupported.

Sixteen focused regressions include changed inherited state, nested and empty
owners, process-color syntax, atomic refusal, parser limits and a 200-group batch.
The independent reader verifies 13 variants across two pinned recent files and a
synthetic source with state changes: full owner topology, object flags, paths,
counts, effective paint, layer outgoing state and exact unselected source bytes.
Adobe reopening remains unqualified. Save matching host-supplied PDF artwork
whenever the edit changes visible output or ordering.

### Mixed artwork grouping and group dissolution

`groupArtwork(paths:, groups:, liveShapes:)` wraps consecutive sibling owners in
one anonymous ordinary group. The three lists may be mixed and input order does
not change source order. Select complete CC pairs through `liveShapes`, including
all saved metadata alternatives; selecting just a printing group or private path
rejects. Direct live shapes can also be selected through their path handles.
Nested ordinary subtrees, qualified object metadata, point counts and intervening
scalar assignments remain exact. Different immediate owners, overlapping
selections, skipped artwork and opaque intervening owners reject atomically.
`groupPaths` delegates to the same contract for ordinary paths.

The new group inherits the source flags at its opening. Both grouping APIs and
`ungroup` require `inheritParentFlags: true` if the added/removed parent has
non-neutral or unknown lock/visibility flags in either the native or printing
stream. Without it, both flags must be known zero. Dissolution preserves each
child's local assignments and makes it inherit the remaining ancestors; it does
not transfer the removed parent's flags onto children. No rendering or new paint
values are generated. This also tightens the previous ordinary-only APIs: callers
that deliberately change such parent inheritance must now opt in.

`ungroup(groups:)` accepts disjoint ordinary parents containing qualified complete
CC pairs. It removes only the selected opening/closing boundaries and owned panel
flag, empty dictionary and neutral mode-nine default reset. `discardMetadata: true`
additionally permits removal of
qualified names, rotation and identities, with a whole-source reference audit for
only the deleted parent IDs. Descendant IDs, including retained aliases, are not
reallocated or deleted. An ambiguous parent identity, unknown reference owner,
applied parent style, opaque metadata, compound/clip owner or partial pair rejects.
Explicit disposal never bypasses these qualification checks.

Twelve regressions cover mixed selection, source order/counts, nested parents,
exact pairs and alternatives, parent-only identity disposal, retained descendant
aliases, opaque references, both flag streams, malformed ownership and bounds.
Independent native-reader checks pass 18 fixed transactions: twelve group/dissolve
operations over four pinned real programs and declared wrappers, two synthetic
mixed/identified cases and four exact refusals. They bind selected byte owners,
requested hierarchy, both streams' contour flags and parent policies, while
requiring every unchanged byte and complete pair to remain exact. These establish
native serialization contracts; Adobe reopening, interactive rendering and
host-supplied PDF/preview regeneration remain separate acceptance work.

Neutral group resets also have a separate acceptance gate. Only the existing
ordinary-object schema's nonprivate `9 () XW` command with an empty name qualifies;
other modes, named styles, malformed operands and repeated attachments reject.
A reset inside an enclosing gradient instance also rejects because that appearance
owner must be handled as a whole.
Removing that command with its parent leaves child opacity, nested group resets,
complete CC pairs and following scalar state unchanged. An empty group cannot
leave its reset attached to an earlier sibling. No group appearance is distributed
or composited by the kit.

Five additional regressions cover disjoint parents, empty groups, complete paired
descendants, enclosing gradient ownership and eight refused style forms. Independent checks verify 18 fixed
transactions: one original real file (`layers_and_sublayers.ai`), four declared
wrappers around pinned real CC pairs, five synthetic edits and eight refusals.
Exact native byte/topology checks are complemented by 15 native/printing SVG
comparisons and identical 1024-wide librsvg RGBA images. Only anonymous SVG groups
without visual attributes, or with opacity exactly one, are normalized for the
structural comparison; image comparisons use the original SVG trees. Synthetic
native version-branch rendering and Adobe reopening remain unqualified.

### Mixed group/layer subtree removal

`removeGroups(groups:)` and `AiNativeLayers.remove(layers:)` also accept qualified
ordinary parents containing complete CC authoring/printing pairs. Each pair's
printing expansion, private contour, native parameters, panel flag and saved
metadata alternatives are removed together. Nested ordinary groups, layers and
paths retain their ownership rules; partial pairs, unknown attachments, compound
authoring parents and unresolved conditional owners reject the entire operation.
Group dissolution retains the children under the separate contract above.

Deletion retains explicit scalar assignments in their original source order and
projection, plus definite scalar effects from removed native styles. Dependency
checks exclude reads by artwork removed in the same transaction, while retaining
its writes. Any unqualified effect still read by surviving artwork before an
explicit reassignment rejects. This applies across disjoint selected roots and
both printing/native interpretations. No graphics defaults or appearance engine
are introduced. Shared setup resources and every unselected source byte stay
exact; layer root counts and explicitly discarded saved views are the only
additional edits. The original byte/token budgets apply to the complete result.

Every deleted identity, including older saved metadata alternatives and anonymous
parents' identified descendants, participates in the whole-document reference
check. Anonymous subtrees can still be removed beside unrelated opaque data.
Authoritative live shapes are counted once even when their dictionary also binds
to a path, keeping versioned and unversioned CC sources consistent.

Fourteen regressions cover mixed and nested owners, batches, both metadata
layouts, private replay, retained dependencies, aliases, opaque references,
partial pairs, exact handles and bounded scalar restoration. The independent
suite checks 22 transactions: nine derived-real and eight synthetic removals,
plus five exact refusals. Five real fixtures add declared ordinary wrappers to
exact spans of complete pinned CC sources; four reuse declared document/pair/style/
gradient assemblies with a new layer and updated root count. These are derived
ownership fixtures, not newly qualified whole original donor-layer deletions.
Independent parsing verifies the recipes, complete selected owners, both metadata
branches, exact unselected bytes, source-derived scalar order/privacy, topology
and flags. Native/printing SVG is compared for real-derived fixtures; synthetic
fixtures retain the external reader's documented native version-branch limitation
and compare printing SVG. Adobe reopening remains unqualified.

### Mixed group/layer subtree copies

`duplicateGroups(groups:, identifiers:)` and `AiNativeLayers.duplicate(...)`
also copy the qualified mixed parents described above, inserting each complete
copy immediately after its original. The printing expansion, private contour,
parameters, panel state and all metadata alternatives stay together. Shared
styles and gradients retain their original names and definitions. Every byte
outside the inserted copies and explicitly updated layer declarations remains
unchanged, including the original parents and their descendants.

Ordinary paths/groups retain their existing identity-map keys. For complete CC
pairs, supply fresh XML names using each identified `AiNativeContainer` handle
in `identifiers` or `artworkIdentifiers`: the main dictionary, redundant printing
dictionary and older alternatives are distinct saved owners. Layer identities
still use `AiNativeLayer` keys in the separate layer map. Missing/extra keys,
collisions with any saved source XML name, and repeated source aliases reject.
Optional layer names change only the copied header's string. No identities are
allocated implicitly, and resource names do not become artwork IDs.

The complete subtree's read-before-write dependencies are tracked in source
order for printing and native interpretation separately. Copies restore only
incoming components that their source can change. Literal assignments and
definite unanimous style scalars establish known values before later child reads;
potential or hidden style effects do not. Unknown required input values reject
instead of receiving graphics defaults. Repeating the complete source graph from
the qualified input preserves its outgoing effects without discarding styles or
reconstructing private appearance. The aggregate byte/token limits still apply.

Qualified ordinary parent dictionaries containing identities, names and other
supported scalar metadata no longer block subsequent native shape transforms.
Unresolved parent metadata or applied appearance still rejects, using the same
ordinary-owner qualification as lifecycle operations.

Seventeen regressions cover nested/group/layer batches, fresh IDs in both saved
layouts, source-wide reservations, private/public flags, definite/hidden style
effects, following artwork, bounds and editable copies. Independent checks cover
23 fixed transactions: eight derived-real copies, ten synthetic copies and five
exact refusals. Real wrappers and document/resource assemblies are reconstructed
from pinned original bytes. Checks bind every selected owner and replacement
string, exact copied/unselected bytes, source-derived input scalars, both metadata
branches, native flags and real native/printing SVG. Synthetic printing SVG is
checked with the existing native version-branch limitation. A follow-up edit
also checks the copied shape's private/printing geometry, main and redundant
centers, unchanged older metadata and all unselected source bytes. The remaining
opacity-source refusal has unresolved inherited input; no Adobe reopening or
general mixed-subtree reparenting is inferred from these copy checks.

### Mixed group/layer subtree reordering

`reorderGroups(groups:)` and `AiNativeLayers.reorder(layers:)` permute complete
qualified mixed sibling subtrees into the selected original slots. Nested ordinary
owners, complete authoring/printing pairs, both saved metadata alternatives,
panel flags, names and identities move as exact source bytes. Selected ordinary
siblings may participate in the same permutation. Unselected siblings retain
their source slots. Source aliases and external references remain unchanged;
reordering allocates or deletes no identities.

Each placed subtree restores the original source inputs that it reads before
assignment, separately for native and printing interpretation. Its complete final
state, including later ordinary assignments after a pair, is compared with the
original destination's outgoing state. Known differences receive source-derived
scalar replay. Unknown differences are accepted only when no subsequent retained
or replacing object reads them before a definite assignment. The shared
dependency visitor treats whole replacements as owned intervals rather than
splitting their private pairs. Unchanged unknown source origins do not require
invented defaults; private restoration cannot conceal a printing dependency.

Thirteen focused regressions cover nested group/layer permutations, selected-slot
ordering, multiple complete pairs under one parent, exact metadata and IDs,
ordinary/paired sibling batches, opaque references, inherited flags, unknown
following state, private/printing separation, saved-view invalidation,
malformed/foreign handles and byte limits. Reparenting has a separate contract
below; grouping and dissolution use the contract above. Save matching
host-supplied PDF artwork for a changed order; AiKit produces no interactive or
compatibility rendering as part of these edits.

Independent verification covers 43 fixed transactions: 24 reorderings of declared
wrappers around four pinned real sources, seven synthetic reorderings, four
unchanged orders and eight refusals. Recipes retain every original pair exactly;
the reader independently binds balanced sibling owners, both metadata branches,
all moved/unselected bytes and replay values at their original source/destination
boundaries. Real native/printing SVG and synthetic printing SVG follow the
requested parent order, resolving shared resources at each use. The existing
disabled-stroke exception also requires identical librsvg pixels. First-pair
unknown printing inputs and unresolved following native paint remain explicit
refusals. Synthetic native SVG and Adobe reopening remain unqualified.

### Mixed group/layer subtree movement

`moveGroupAfter`, `moveGroupToLayer`, `AiNativeLayers.moveAfter` and
`AiNativeLayers.moveInto` also move complete qualified mixed subtrees. The new
`moveGroupToGroup(group:, parent:, inheritParentFlags:)` appends an ordinary parent
inside a populated or empty group, retaining ordinary children and complete CC
pairs. Native/printing representations, every metadata alternative, parent and
child identities, names, panel flags and headers remain exact source bytes.
No identity is removed or allocated, so retained aliases and opaque external
references do not require the deletion-specific reference audit.

Source and destination ancestors must have qualified ordinary ownership.
Changing layer parents or ancestor-group flags/depth requires explicit
`inheritParentFlags: true`, checked in both interpretations. The moved owner
retains its own attributes and inherits its destination's ancestors; headers
are not changed to approximate former effective visibility. Descendant/self
destinations and partial printing/private owners reject. A layer may be lifted
after an ancestor. Root counts and explicit saved-view invalidation follow the
existing layer contract.

The original location retains persistent literal assignments and definite native
style scalars in source order, without geometry, point counts or orphaned style
applications. The destination restores source inputs and its original outgoing
state separately for native and printing interpretation. A single dependency
pass checks both edits together, visiting complete moved/retained owners. Unknown
differences still consumed before an assignment reject; no default paint or
visibility is invented. This shared retention also applies to mixed-subtree
deletion, whose identity-reference checks remain mandatory.

Eighteen regressions cover forward/backward movement, several pairs under one
parent, populated/empty destinations, same-depth native/printing ancestor flags,
cross-layer moves, nested layer lifting, root counts, exact headers and identities,
opaque references/aliases, required input and following-state refusals, view-state
invalidation, source handles and bounds. The kit serializes the native changes;
the host supplies matching PDF/preview representations. Grouping/dissolution use
the contract above; arbitrary private parent schemas and Adobe reopening remain
separate work.

Independent checks cover 51 fixed transactions: 24 moves of declared wrappers
around four pinned real sources, 16 synthetic moves and 11 exact refusals.
Complete source recipes and all original pair fragments are independently bound.
The reader verifies the requested native parent tree, both saved metadata
alternatives, all ordinary and paired contour flags, exact moved/unselected
bytes, ordered retention at the origin and replay at the original boundaries.
Root declarations and retained layer headers are independently decoded. Real
native/printing SVG and synthetic printing SVG retain the requested whole-owner
placement and resolved resources; disabled-stroke differences still require exact
librsvg pixels. The synthetic native version-branch limitation remains explicit;
these checks do not establish Adobe reopening or Focale integration.

### Cross-layer artwork movement

Paths and ordinary group subtrees can move after another object or be appended
directly to an existing layer. `movePathToLayer` and `moveGroupToLayer` accept an
`AiLayer` from the current drawing's `records.program.layers`; stale and foreign
handles reject. Appending directly also supports an empty destination and lifting
an object out of its current ordinary group. Moving after an unlayered anchor can
return artwork to the document root.

Changing layers requires `inheritParentFlags: true`. Objects keep their own
attributes and accept the destination ancestors' layer/group flags. Changing
ancestor-group depth or lock/visibility state uses the same explicit policy,
including within one layer. The interval must contain qualified ordinary objects,
state assignments and known layer headers only. Private/derived objects, unknown
metadata, masks and ambiguous layer ownership remain unsupported. Selected source
and destination headers and their ancestors must qualify; malformed root counts
reject. An explicit inheritance policy does not bypass any dependency check.

Paint persists across `Lb`/`LB`; qualified names, expansion flags and identity
dictionaries do not clear it. Source assignments preserve the moved object's
input state and restore outgoing state at its destination. Moving a group leaves
its persistent assignments at the old position for following artwork. The shared
bounded serializer tracks unknown-value provenance instead of equating values
across unrelated opaque boundaries. No defaults or colors are synthesized.

Layer topology, headers, identities, root-count and saved-view declarations remain
exact. Moving artwork therefore does not require discarding layer-panel state.
Native drawing bounds remain conservative. Existing PDF/page mapping stays in
place; updated visible artwork must come from the host's supplied representation.

Eleven regressions cover nested hidden/locked owners, empty and anonymous layers,
root artwork, direct-layer insertion, ancestor inheritance, unknown/malformed
state, stale handles, retained opaque neighbors and budgets. Independent checks
verify 14 transactions: ten movements plus two layer-insertion and two grouping
prerequisites. Two pinned
recent files supply real ordinary artwork; a checksum-pinned synthetic source
covers movement in both directions, nested owners and outgoing paint. Checks
compare complete object trees, attributes, paths/counts, exact layer declarations
and unselected bytes; added assignments must come from the source. Existing 13
group and 16 path transactions remain qualified. Referenced/private artwork
lifecycle and Adobe reopening remain unqualified.

### Hierarchical records

`AiNativeRecords.decode` exposes dictionaries, arrays, objects and binary
resources in ordinary and `%_`-prefixed syntax. Source offsets, multiline and
adjacent strings, unknown record types and embedded drawing commands survive.
Repeated object fields remain ordered through `values(key)`; ambiguous single
lookups reject. `decodeBinary(maxOutputBytes: ...)` uses bounded ASCII85 decoding.
Decoding a binary resource does not establish support for its internal format.

`records.artboards` exposes recorded names, identifiers, selection flags, bounds and
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

### Artboard state and native lifecycle

`AiNativeArtboards.decode(records:, document:)` retains one explicit Document
owner and its ordered artboards. Omitting `document` requires exactly one owner.
`activeEntry`/`activeIndex` read `Recorded/CropAreaActive`; `activeArtboard` follows
that index. `selectedArtboards` reads each board's independent
`IsArtboardSelected` flag. These values must not be conflated: the pinned
Illustrator 30.6 fixture has active index 4 and selected index 2. Its
`LastArtboardID` is 67 for five boards; `lastArtboardId` retains that saved integer
without interpreting it as a count or array index. Missing fields remain absent.
Out-of-range active indices, malformed fields and ambiguous owners reject.

`cropHeader` and `cropBounds` expose the initial program `AI3_Cropmarks`
declaration separately from board rectangles, ruler origins, drawing bounds and
PDF media/crop/trim/art boxes. Repeated or conditional crop headers reject.

`resize(artboard:, bounds:, cropBounds:, rulerOrigin:)` changes one current owned
rectangle without moving native artwork. Bounds require positive dimensions and
finite portable coordinates. The required `cropBounds` argument is an explicit
policy: null preserves the saved crop declaration, while a supplied rectangle
replaces its existing numeric value independently. An optional two-coordinate
`rulerOrigin` replaces the existing field; omitted origins remain exact. Missing
crop/origin fields cannot be invented by this operation. Active/selection state,
names, identities, ordering and drawing/ink bounds remain unchanged. A no-op
returns the current immutable model; changed data reparses under its original
limits. Foreign and stale handles reject.

`AiNativeArtboardDefinition` freezes a new board's native name bytes, fresh
canonical UUID bytes, drawing rectangle and explicit canvas ruler origin.
Selection and default-name flags are independent; pixel aspect ratio defaults to
one and the ordinary writer emits zero display marks. Name encoding is supplied
by the caller, as with other native UnicodeString writers.

`create(definition:, index:, lastArtboardId:, cropBounds:, activate:)` inserts at
an explicit position. An existing `LastArtboardID` requires an explicitly supplied
larger portable integer; an absent field requires null and remains absent. The
counter is not derived from the board count, UUID, name or position. Existing
active ownership follows its shifted index; `activate: true` instead designates
the new board and requires an existing active-index field. An empty native array
can receive its first board without inventing omitted state fields.

`reorder(artboards:, cropBounds:)` requires every current source board exactly
once. `remove(artboards:, activeArtboard:, cropBounds:)` removes whole entries,
retains at least one board, and requires a retained replacement only when the
active board is removed. Removal and reordering retain creation history. Selection
flags, UUIDs, names, ruler origins and exact dictionaries follow retained boards;
array separator trivia moves with its preceding record. These operations do not
move or delete artwork. Crop policy remains explicit and independent throughout.

Structural operations currently require private native array entries and unique
portable ASCII saved identities. Unqualified identity encodings reject rather
than bypassing collision checks. Operations preserve LF, CRLF and CR line endings
and support an omitted final comma. Saved artboard print ranges follow retained
identities; physical printed-page ranges require a supplied update as described
below. Fresh UUIDs cannot reuse
existing declarations, including case variants. Foreign/stale handles, duplicate
selections, missing replacement-active policies and output/parser limits reject
atomically.

Artboard edits have a separate retained-dependency scope. Qualified ordinary
artwork, complete CC pairs and shared literal resources remain exact. This scope
also accepts literal `SimpleStyle` paints, qualified `ActiveStyle` graphs, plug-in name inventories,
existing style-name lists, resolved symbol lists and qualified process/named-color
and gradient/pattern palettes. These are preserved declarations, not permission to
execute plug-ins, edit symbol instances or synthesize artwork.

Retained active styles keep ordered chain/stack filters, repeated fill/stroke
parts, visibility, blending and filter-local typed dictionaries. Named colors,
pattern paints and complete gradient instances use the same bounded reference
checks as retained resources. Known local descriptors cover stroke offset,
feather, rounded corners, offset path, drop shadow, outer glow and transformation.
Their recorded parameters and legacy module names remain exact, including
inactive parts and numeric values expressed in the existing document basis.
Only each filter's known fields and owned paint records qualify; unknown fields,
external plug-ins, executable values, duplicate keys, opaque annotations and
missing/ambiguous named resources reject. No filter is executed, recomputed or
made transformable by this artboard-only retention contract. Brush references
and other appearance families still need their own dependency qualification.

Palette indices, cell order, optional names, none paints (`Pn`) and group names
with their two Boolean flags (`Pg`) remain exact. `Xs` CMYK and `Xz` RGB/CMYK
alternatives retain literal byte names and unit tints; names are not interpreted
as artboard identities or restricted to an English registration label. Palette
gradients require a complete fill `Bb`/`BB` instance, flag-two geometry and one
unconditionally resolved setup definition. Their palette-local coordinates and
printing matrices remain unchanged. Missing/ambiguous resources, malformed or
overlapping cells, private operands, opaque annotations and executable paints
reject. This retention contract does not grant swatch,
gradient or pattern lifecycle edits.

Direct CC pattern definitions retain their literal byte names, nonempty tile
rectangles, ordinary/private artwork and local editor metadata. Ordinary,
compound and clipping groups, path geometry, owned masks and point counts are
checked without instantiating tiles. Gradient instances require unique
unconditional definitions and cannot cross group, state or metadata boundaries.
Qualified tile-editor flags, dimensions, rotation and local gradient transforms
retain their original coordinates. Palette `p`/`P` references resolve in the
separate pattern namespace and preserve offsets, scales, rotation, reflection,
shear and six-value matrices. Duplicate/missing names, conditional boundaries,
unknown metadata, executable tile programs and opaque payloads reject. Old
PostScript string-program tiles remain outside this direct-artwork contract.

Direct `%AI14_BeginSymbol` definitions share those bounded artwork checks and
retain their literal name and complete ordinary/private geometry. Symbol-local
registration type, nine-slice grid, pixel-perfect flag, compound-shape mode,
rotation and XML artwork identities remain distinct from artboard identities.
Pattern paints and named mode-zero/one `XW` style assignments require unique
unconditional definitions; unnamed mode-zero/one applications and empty
mode-six/nine assignments are retained. Named fill/stroke colors,
literal opacity, blend mode, isolation, knockout and alpha-as-shape flags remain
exact. The retained scalar domains follow the Adobe SDK's
[blend-style definitions](https://ai-sdk-2020.84.nz/html/_a_i_mask_8h), without
compositing or evaluating the appearance. AI10/AI24 panel inventories require
distinct ordinary literal names that resolve to qualified symbols; the observed
AI10 opening and closing comments with a terminal NUL are retained verbatim. Unlisted
definitions may remain unused. Unknown metadata, nested resource declarations,
unqualified payloads and executable state still reject. Symbol instances
and definition lifecycle remain separate editing contracts.

Symbol `AI9_Mask` dictionaries retain explicit `Linked`, `Disabled`, `Clipping`
and `Inverted` Boolean fields together with a complete `X=`/`X+` artwork field.
Empty, vector, nested and qualified raster masks preserve their source basis.
Mask raster sections use the existing bounded `XI` decoder and require complete
`XG`/`XN`/`Xh`/`XI`/`XH` process-image metadata with consistent placement. The
opaque sample interval remains exact; raster and DSC boundaries must belong to
that image and cannot hide unrelated annotations. An immediate empty `AI5_File`
comment is retained without accessing a file. Sample UUIDs, original scale and
the fuzzy-mask flag are accepted only on that raster's attached dictionary.
The known `AI Auto Rasterize` property observer is retained as a literal name.
Flags, nested artwork, binary sizes, geometry/counts and references are checked
within the original program limits. Unknown mask fields, external execution,
unsupported raster layouts or incomplete ownership reject atomically. This is
retention during artboard edits; mask editing and recomposition remain separate.

Direct `%AI8_BeginBrushPattern` artwork uses the same retained-resource contract.
Brush names have their own namespace, with literal unique declarations and
unconditional complete boundaries. Empty/vector resources, counted compound and
clipping paths, local metadata and resolved style/gradient/pattern references
remain exact. Direct process images also qualify inside pattern and symbol
definitions. Gray, RGB and CMYK samples retain their existing separate alpha
plane, source placement, sample UUIDs and original scale. An image dictionary
must be attached to that image; matching string values do not create artboard
dependencies.

All raster sections use the bounded source decoder. Geometry determines color
and alpha sizes even for producers whose `BeginData` count covers only color;
sample bytes cannot supply resource, record or DSC delimiters. Unknown image
layouts, opaque annotations, executable values, unrelated data and crossing
owners reject before any edit. These rules qualify resource preservation during
artboard changes. Brush assignment descriptors, calligraphic `GObjRef` ownership,
brush-instance editing and synthesized stroke geometry remain separate contracts.

Native `%AI10_BeginSVGFilter` collections retain every ordered `SVGFilter`/`Def`
tree with its complete XML-node envelopes, literal attributes and child arrays.
The artboard inspector recognizes local scalar filter primitives, lighting and
component-transfer children, plus parent-targeted `animate`/`set` records with
literal clock timing. The observed Illustrator `resultScale` parameter remains
literal. Filter IDs and repeated `in`/`in2`/`result` names are independent of
native artboard identity: SVG defines these result names within a filter, not
as document object references. See the W3C
[filter dependency rules](https://www.w3.org/TR/SVG11/filters.html#FilterPrimitiveInAttribute)
and [animation target rules](https://www.w3.org/TR/SVG11/animate.html#TargetElement).

All saved numeric parameters, order, visibility-related values and animations
remain source-backed. This is dependency qualification, not SVG evaluation or
validation of rendering results; existing unresolved local result names are not
rewritten. Scalar color/opacity presentation declarations cannot contain URLs,
CSS escapes, external profiles or variable expressions. External images, hrefs,
scripts, event timing, nonlocal animation targets, unknown fields and conditional
or incomplete section ownership reject atomically. Original parser and output
limits still apply. Filter editing, animation execution and rendering belong to
separate contracts; no rendering engine is introduced here.

One setup `AI11TextDocument` and an optional `AI11UndoFreeTextDocument` can be
retained with compact ATE versions 7 and 9. Point, area and path frames use
explicit canvas geometry; story frame lists and cached frame references resolve
within the selected snapshot. Ordinary unconditional `AI11Text` records select
the main or undo-free story/frame namespace explicitly. An empty or missing
undo-free model cannot satisfy a reference to that model. Linked frames retain
their original order and transforms. Fonts, typography and composition caches
remain byte-identical; the global text ruler origin must be explicit and is unchanged.
Template-box, page-origin and canvas-scale declarations remain exact, even when
the first board moves or changes size. Binary bytes and node counts share bounds
across both snapshots. Area/path drawing references require an owned unpainted
confinement curve with literal `X=`/`X+` boundaries, checked point counts and
qualified rotation metadata. Direct text identities and names are preserved.
Named mode-zero/one style assignments must resolve to a setup definition; empty
mode-zero/one/six/nine assignments and ordinary Boolean fill/stroke flags are retained without applying
their paints.

Unknown engine owners, frame categories, cached node tags/fields, opaque tokens,
conditional/ambiguous wrappers, dangling story/frame/display indices and unknown
setup or artwork dependencies reject. Named CS text schemas and live-shape,
painted or executable confinements remain unqualified here. Retaining populated
text does not grant creation/deletion of stories, frame reflow or cache regeneration.
Artwork identity deletion retains its separate, stricter reference qualification.

Retained font setup recognizes the mark-based `TE`/`TZ` grammar from AI7
section 3.3. A font mark ends at its operator, not at a `]`; it cannot make later
counted gradient banks appear nested. Literal glyph runs have bounded byte-code
indices, and font declarations retain their names, known direction/script flags,
optional numeric Multiple Master weights and matching encoding wrappers. Plain
font-name header inventories and `%AI55J_Tsume: None` are preserved. Immediate
name lookups, opaque annotations, conditional ownership, malformed runs and
unknown wrappers reject. Font names do not become artboard or artwork identities.
The same mark recognition fixes gradient isolation after font declarations;
actual nested arrays and dictionaries still cannot own copied gradient banks.

The retained body may contain ordinary compound paths (`*u`/`*U`) and clipping
groups (`q`/`Q`), including nested groups, direct metadata and hidden/locked layer
owners. Path masks retain their exact `h`/`H`, `W` and paint sequence within an
owned clipping group. Geometry must remain contiguous; saved point counts must
belong to one path and match its explicit closure convention. Private/versioned
ordinary paths, stray mask controls, text/multilayer masks, unknown commands and
opaque annotations remain unqualified. Complete CC pairs use their existing
internal dependency checks; neighboring retained compounds are checked separately.
This permits artboard changes without granting deletion, movement or independent
editing of the compound/clip children.

The operations edit native data only: host-supplied compatibility pages and
cached headers must also be synchronized before a complete save. The save APIs now
update qualified PDF `AIMetaData` header copies and accept explicit PDF page
mappings as described above. Broader artboard isolation for unqualified text
profiles and complex setup resource/object families remains in the open roadmap task.

Nine regressions cover independent state, multiple owners, exact source changes,
explicit crop/origin choices, CC pairs/resources, malformed input, conditional
ownership and limits. Nineteen independent transactions cover six real-source
inspections, six resizes in three pinned CC sources (including large canvases and
moved origins), four synthetic resizes and three unchanged refusals. The large
five-page fixture's native qualification is inspection-only: the independent reader also reports
unsupported body operators, so only its separately bound Document metadata is
qualified. Explicit page-identity replacement preserves that complete native body
and verifies its supplied PDF separately. No native rendering or Adobe reopening
is claimed.
Thirteen further lifecycle regressions cover creation, active replacement,
permutations, absent fields, exact source retention, line endings, immutable
definitions, identity collisions, unknown dependencies and aggregate limits.
Thirteen dependency-scope regressions additionally cover retained setup/text
owners, namespace separation, exact global coordinates, unchanged artwork-deletion
refusals, malformed data and aggregate binary inspection limits. Forty independent
lifecycle transactions initially qualified thirty edits in five pinned CC sources and ten
synthetic edits, including complete CC pairs and shared gradients. The real set
includes the RGB and CMYK rectangle documents with their complete original setup
inventories and empty text-engine snapshots. The independent reader compares complete Document values,
exact retained dictionaries/separator trivia and every byte outside the declared
array/scalar/crop edits.

Eight further regressions cover retained compound/clip topology, complete CC
pairs on either side, exact metadata, malformed masks/counts, unchanged child-edit
refusals and a 250-compound batch. The lifecycle suite initially checked 48 transactions:
30 in the same five real sources and 18 synthetic edits. The added topology
fixture is synthetic and checksum-pinned; all six outcomes also retain the exact
independently parsed drawing commands, including one compound, two clipping
groups, three mask paths and five point counts. These checks do not qualify a
real Adobe-produced clipped document or editable compound/clip topology.

Eight palette regressions cover all four artboard operations, legacy unnamed
cells, localized and byte-valued names, groups, resolved gradients, malformed
ownership and unchanged artwork-deletion refusals. Six further independently
verified transactions bring the lifecycle suite to 54 (30 real, 24 synthetic).
The new checksum-pinned synthetic palette retains six cells, two groups, named
colors and a gradient whose name coincides with a removed artboard UUID. The
external reader checks every palette command/operand and the referenced gradient
definition alongside complete Document values and exact unselected native bytes.

Nine populated-text regressions cover both compact versions, point/area/path
frames, linked references, independent undo-free namespaces, a mapped PDF save,
malformed/opaque dependencies and original depth/node limits. Independent checks
verify 28 native artboard edits in seven checksum-pinned carriers. Four carriers
copy the exact font setup, ATE snapshots, origins, drawing references, confinement geometry
and attached metadata from pinned CC files; three synthetic carriers exercise
main/undo-free ownership and a counted clipping/gradient pattern. The independent parser compares all copied text with
the original producers and all outcomes, including 16 frames across ten stories
in `text_transforms.ai`. Font encodings are independently compared with the
producer and every outcome, and their complete source setup remains byte-exact.
Eight additional regressions cover font marks, all four artboard operations,
gradient isolation, malformed declarations and unchanged deletion guards. These
checks now also retain each producer's complete pattern/gradient banks and palette.
Each real carrier has two patterns with 102 paths (177 in `flowtext.ai`) and 16
gradient definitions (20 in `flowtext.ai`). Independent comparisons cover all
pattern commands/metadata, gradient commands/operands, palette references and
exact source bytes. Eight pattern regressions cover all four edits, private and
ordinary tiles, empty definitions, clipping/count ownership, resource references,
malformed transforms, unsupported execution and original depth limits.
These carriers do not qualify artboard edits of the full producer files.
Eight symbol regressions additionally cover all four artboard edits, separate
resource/identity namespaces, ordinary/private/empty definitions, old inventory
wrappers, complete blending flags, named colors, malformed ownership and limits.
A separate independent suite checks twenty transactions in five pinned carriers:
39 exact producer symbol definitions across the same four CC sources, plus one
synthetic symbol with a resolved style and an XML ID equal to an artboard UUID.
The reader compares complete symbol commands and metadata, inventory order,
resource references, producer text/fonts/patterns/gradients and all retained
bytes. The first three real carriers have twelve symbols and 65 symbol paths
each; `flowtext.ai` contributes three symbols and 167 paths.

Eight mask regressions cover all four edits, all Boolean flag combinations,
ordinary/private/empty/vector/nested masks, hostile sample bytes, malformed
framing and original limits. A further twenty independent transactions use
three carriers with both exact producer mask dictionaries plus two synthetic
raster/vector carriers. Each real carrier retains 32-by-32 and 29-by-30 gray
rasters: 1,024 and 870 exact sample bytes respectively. The reader compares every
mask field, nested command, raster descriptor and sample with the producer and
each result, alongside text/font/pattern data and whole-source preservation.
These masks come from the `Film` symbol; its other appearance dependencies are
not removed from, or claimed qualified in, the original document. Full producers
still require further style references/appearance graphs, blend owners, brushes
and SVG filters before artboard edits can be qualified end to end.
Adobe reopening remains unqualified.

### Native print selections during artboard edits

`AiNativeArtboards.printJob` exposes the selected Document's existing
`NotRecorded/AI11 Print JobInfo Dict` as `AiNativePrintJob`, or null when absent.
`allArtboards` and `allPages` retain separate optional zero/one integer flags.
`artboardRangeBytes` and `pageRangeBytes` preserve exact decoded strings, including
encoding markers. Empty ranges, missing fields and dormant selections under an
all flag stay distinct. `artboardIndices` returns the stored zero-based selection;
`pageIndices(pageCount:)` requires the host's physical output count. Neither
getter equates printed pages with artboards or compatibility PDF pages.

The qualified range grammar is a comma-separated list of positive one-based
numbers and inclusive ascending ranges, including an open upper endpoint (`2-`).
Whitespace and repeated/overlapping selections are accepted; inspection returns
sorted distinct indices. Endpoints must fit the declared count, and expansion
has a `maxTokens` budget that also counts repeated selections. ASCII and explicit
UTF-16 BOM encodings are supported. Unmarked multibyte encodings and other range
grammars reject; malformed flags and out-of-range endpoints raise format errors.

Creation, reordering and removal remap stored artboard selections by retained
board identity. New boards are not added to an explicit saved selection. All flags
retain their meaning independently; dormant nonempty ranges are remapped too.
An unchanged numerical selection keeps its exact source spelling. Changed ranges
use compact one-based intervals while retaining encoding, field type and unrelated
trivia. If removal exhausts an active or unspecified selection, the edit requires
an explicit replacement; a dormant range under `allArtboards: true` may become
empty without changing that flag.

All four lifecycle methods accept optional `artboardPrinting` and `pagePrinting`
values of `AiNativePrintSelection(count:, indices:)`. Null `indices` explicitly
selects all and clears the corresponding stored range; otherwise supply a nonempty
list of distinct zero-based indices. Inputs are validated and frozen. The artboard
count must equal the resulting native count. Both the all flag and range field
must already exist when supplying a choice; this API does not invent absent
print dictionaries or fields. A supplied choice may replace an unqualified range
grammar when its string encoding and field ownership are known.

Physical printed-page ranges cannot be remapped from board ordinals: Illustrator
can tile an artboard across several sheets or ignore artboard boundaries. When a
geometry, ordinal or stored artboard-selection edit leaves a nonempty physical
page range, supply `pagePrinting` from the host's print layout. This also applies
to dormant physical ranges; the kit never guesses a new page count. For example,
`AiNativePrintSelection(count: 12, indices: [0, 5, 11])` writes `1,6,12` and selects
range mode, while `AiNativePrintSelection(count: 12, indices: null)` writes the
all-pages flag and an empty range. This is serialization of a supplied selection,
not printing, tiling or page composition. See Adobe's
[printing guide](https://helpx.adobe.com/illustrator/using/setting-documents-printing.html)
for the distinction between artboard and physical-page output.

Print updates share the artboard edit's atomic byte transaction and original
parser/output limits. No-op edits retain existing physical ranges. Eleven
regressions cover identity remapping, exhausted selections, explicit flags,
physical counts, UTF-16, fragmented strings, empty operands, malformed input,
limits and saving through explicit PDF mappings. Twenty independently decoded
transactions cover five chained edits in three pinned CC sources and a synthetic
source with complete CC pairs/resources. The real fixtures initially contain
empty ranges; the suite writes explicit selections, then remaps them through
creation, reordering, removal and resizing. Complete Document values and every
byte outside the declared edits are checked. Native Adobe print-dialog reopening
and actual printed output remain unqualified.

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

Named resource links currently cover `KnownStyle`/mode-zero/one `XW` and global
`Bd`/complete `Bg` instances. The index includes qualified uses inside native
`Art`, paint styles and setup pattern/symbol/brush artwork; inspecting those references
does not implement pattern/symbol editing. References outside indexed structural
nodes keep a null lexical owner and exact instruction offsets. Declaration
memberships follow the source name, including conditions inside its record.
Duplicate definitions remain separate. A use is `resolved`, `missing`,
`ambiguous` or `conditional`; `usesOf` includes potential conditional/ambiguous
dependencies. Opposite branches of the same block cannot bind each other.
Conditions in separate blocks are not assumed equivalent. Unknown plug-in
dependency schemas remain opaque.
An empty `XW` name is an unnamed application, not a missing named-style use;
it remains in the source command inventory without an invented resource link.
Malformed mode-zero applications now raise `FormatException` consistently with
mode-one applications, rather than being left as opaque unsupported state.

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
| Object metadata | Direct path/group dictionaries, names, saved XML IDs and group panel/default-style attachments | Whole-object movement/copy; qualified identity removal; qualified parent dissolution with explicit metadata disposal | Unknown/private fields and references reject; copied descendants need fresh IDs; identified deletion requires a qualified whole-source reference scope. |
| Native layers | Headers, names, identities, wrappers and direct ownership | Header edits, empty insertion, qualified ordinary-subtree lifecycle and complete mixed CC-subtree copy/removal/reordering/movement | Additional private fields, masks and unresolved ownership/state reject; identified deletion requires a qualified reference scope; reparenting and view invalidation require explicit policies. |
| Ordinary native paths | Source-backed geometry, paint and qualified attached metadata | Explicit path creation without a sibling; geometry and qualified lifecycle with fresh copied IDs and retained source state | Unknown required state and dependent/unresolved ownership reject; movement across different layers or ancestor flags requires explicit inheritance. |
| Ordinary native groups | Source topology and qualified declarative state | Group/ungroup, duplicate, remove, reorder and qualified moves; complete mixed CC-subtree grouping/dissolution/copy/removal/reordering/movement | Qualified metadata/identity policies apply; unknown required state and unresolved references reject; group dissolution needs explicit metadata/parent-flag policies and rejects applied styles. |
| Hierarchical records and artboards | Source-owned settings, order, identifiers, separate active/selection/crop state, origins and print selections | Qualified native creation, removal, resizing and complete reordering; artboard print-range remapping and supplied physical-page selections; explicit host PDF page mappings and full/font-filtered cached-header synchronization | Private arrays and qualified whole-source dependencies only. Compact ATE 7/9 text, qualified appearance/brush resources and local SVG-filter trees can remain unchanged. Calligraphic assignment, blend ownership and divergent cached-header profiles remain incomplete. Unknown print-range grammars/encodings require explicit qualified replacements. |
| Source structure and version alternatives | Ordered owners, saved identifiers, both branches and qualified shared references | Inspection; existing edit contracts still apply | No target-version selection or unknown plug-in reference resolution. |
| CC live shapes | Five qualified families | Translate, rotate, uniform scale; complete pair copies/removal/reordering/movement; supplied printing contours and qualified groups | Parameter changes, general affine resizing and unresolved printing dependencies remain incomplete; movement requires qualified parent/state ownership. |
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
- [Adobe SDK UID reference contract (documentation mirror)](https://ai-sdk-2020.84.nz/html/struct_a_i_u_i_d_r_e_f_suite)
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
