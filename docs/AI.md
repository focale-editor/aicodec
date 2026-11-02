# Illustrator technical reference

This document describes how AiKit represents Illustrator data, which structures it can edit and serialize, and what remains with the host application. Start with the [README](../README.md) for an introduction and the [host contract](HOST.md) for application responsibilities.

AiKit is a pure Dart format package. PdfCore handles PDF containers, ZCodec handles native compression, and PsCore supplies the Adobe text-engine grammar shared with PsdKit. Consumers normally import `package:aikit/aikit.dart`.

## Reading and writing documents

`AiCodec` implements `Codec<AiDocument, List<int>>`. Its converters operate on complete files; direct encoding returns `Uint8List`:

```dart
import 'dart:io';
import 'dart:typed_data';

import 'package:aikit/aikit.dart';

final Uint8List input = await File('input.ai').readAsBytes();
final AiDocument document = const AiCodec().decode(input);
final Uint8List output = const AiCodec().encode(document);
await File('output.ai').writeAsBytes(output, flush: true);
```

Detection uses `%PDF-`, `%!PS-Adobe-` or a DOS binary EPS header, not the filename. Illustrator markers are required by default. `allowGeneric: true` also accepts generic PDF/EPS interchange; it does not turn that content into native AI data. Markers identify a format convention, not the authenticity of a file.

| Container | Model | Encoding behavior |
| --- | --- | --- |
| PDF-backed AI | `AiPdfDocument` | Rewrites the PdfCore object graph, retaining native private data unless explicitly replaced or removed. |
| PostScript AI or EPS | `AiPostScriptDocument` | Returns the retained source bytes, including any DOS EPS envelope and previews. |

PdfCore's limits and restrictions apply to PDF-backed files, including encryption rejection and signature invalidation on a full rewrite. Exact legacy byte preservation does not imply that the PostScript program can be executed or that all its authoring data is understood.

## New native CC documents

`AiNativeDocument.create` creates an immutable native version-24 document without
an input AI, template or copied producer program. Required inputs are artboard
definitions, a nonempty `AiNativeDocumentLayer` tree, title bytes, RGB/CMYK mode
and a timestamp. Every layer specifies its existing `AiNativeLayerDefinition`;
its ordinary paths precede its children in source paint order. A blank document
uses one empty layer and at least one board. Path geometry, colors, opacity,
stroke parameters and ink bounds use `AiNativePathDefinition` and its existing
validation. There is no native-to-PDF rendering step.

The writer initializes a single `Document` dictionary, Recorded artboard array,
active index, NotRecorded last-artboard counter, root-layer count, crop/header
bounds, ruler units/origin and explicit ordinary painting state. Artboard UUIDs
must be canonical and distinct; optional layer/path XML identities share one
uniqueness namespace. The default ink bounds enclose the boards and every supplied
path extent; explicit `inkBounds` replace the board contribution. These are
host-computed bounds, not measured or rendered extents. Names retain their supplied
byte encoding and are escaped as literals. Timestamps are normalized to UTC.
No text snapshots, fonts, color profiles, previews or advanced appearances are
invented. Further qualified data can be added through existing native APIs before
the first save. The normal `(none)` font-header sentinel remains valid for later
artboard edits; mixed or deferred string declarations still reject.

`AiNativeDocument.createPdf` takes the resulting current records, a complete
host-authored `PdfDocument`, explicit `AiNativeDocumentPage` bindings and a UTC
modification timestamp. Each binding must refer to the current artboard record
and its corresponding indirect PDF page, once each and in matching order. The
initial profile requires one native Document, canvas scale one, a version-24
header, explicit color mode, coherent layer counts and distinct board UUIDs.
Known missing/ambiguous native style/gradient references reject. Other native
operators are preserved; packaging has no rendering operator whitelist.

PDF pages must be unrotated with UserUnit one. Their TrimBox dimensions must match
the native board within 0.000001 points; absent TrimBox falls back to CropBox then
MediaBox. Crop/trim must lie inside their containing boxes. Bleed and nonzero PDF
origins remain exact, and the host supplies any required content transforms.
Reachable dangling PDF references, encryption and existing catalog/page
Illustrator attachments (including partial metadata) reject. Other producer
PieceInfo, XMP, content, resources and graph identities are retained.

The writer attaches one shared private dictionary to all pages, with
`ContainerVersion=12`, `CreatorVersion=24`, `RoundtripStreamType=2` and
`RoundtripVersion=24`. Its contiguous `AIPrivateDataN` streams contain the
Zstandard envelope; configurable `blockBytes` defaults to 1 MiB. `NumBlock` and
`LastModified` are initialized, and a shared `AIMetaData` stream contains the full
initial native header through the EndComments line ending. No stale thumbnails
are created. Native byte/token/depth limits and PDF object/stream limits bound
construction. Serialize the returned `AiPdfDocument` with `AiCodec`; the host owns
atomic file persistence. For subsequent saves, extract fresh sources and use the
normal `AiNativeData.replace`/mapped replacement APIs.

See [the runnable example](../example/create_document.dart). Eight synthetic
complete-file cases (new RGB/CMYK blank/multipage documents and subsequent edits)
pass the pinned independent native reader and pypdf; Poppler pixels remain exact
against each supplied host PDF. This is a qualified initial CC serialization
profile, not all Illustrator authoring features, Adobe reopening certification or
an implemented Focale export command. AI7 standalone authoring remains outside
this contract.

## Native programs and immutable edits

`AiNativeData.extract` retrieves authoring data separately from the compatibility PDF. The latter may contain only an Illustrator compatibility warning.

```dart
final List<AiNativeSource> sources = AiNativeData.extract(document);
for (final AiNativeSource source in sources) {
  final AiProgram program = AiProgram.decode(bytes: source.bytes);
  final AiNativeRecords records = AiNativeRecords.decode(program: program);
  print('${program.layers.length} layers; ${records.artboards.length} artboards');
}
```

For PDF files, extraction follows catalog/page `PieceInfo → Illustrator → Private` entries. It collects `AIPrivateDataN` or `AIPDFPrivateDataN` streams in numeric order, validates contiguous numbering, decodes outer PDF filters and excludes recognized leading thumbnail blocks. Shared complete block sequences produce one source with multiple owners; independent native programs remain separate. Do not assume that every file has exactly one source or one source per page. `AiPdfDocument.privateBlocks` exposes the retained stream inventory separately from decompressed native programs.

Supported envelopes are plain `%!PS-Adobe-`, `%AI12_CompressedData` followed by zlib, and `%AI24_ZStandard_Data` followed by Zstandard. Split envelope markers are supported. Unknown blocks and private fields remain in the source graph. `AiNativeSource` retains immutable bytes, compression and catalog/page ownership; `asPostScript()` exposes the program without converting its native version. `AiNativeData.encodeEnvelope` encodes an explicitly selected compression family.

Edits return new snapshots. Obtain layers, paths, frames, resources and other handles from the snapshot being edited; handles from an earlier or foreign snapshot are rejected. Reacquire handles after each edit. Unrelated source bytes are preserved according to the individual API's contract, rather than rebuilding an entire document from the subset of fields AiKit understands.

`AiNativeEditor.apply` is a lower-level byte-edit API. It validates spans, overlap and output size, then reparses the result. Its caller owns semantic consistency between any dependent native records it changes.

## Native capability reports

`AiNativeCapabilityReport.inspect(source: source)` inventories one extracted program. Inspect every source returned by `AiNativeData.extract`; a PDF page is not necessarily a native document. Findings retain the source, catalog/page `owners`, a source-relative `selector` and byte span.

| Data support | Meaning |
| --- | --- |
| `typed` | Named models expose the fields; editing is assessed separately. |
| `preserved` | Original bytes remain available without semantic support. |
| `unsupported` | A known layout or dependency cannot currently be used safely. |
| `malformed` | Structural validation found invalid syntax or values. |
| `uninspected` | A limit or ambiguous parser failure prevented inspection. |

Operations independently report `available`, `requiresValidation` or `unsupported`. `editable` means at least one operation is available, not that the whole object or its children can be edited. The selected operation still validates ownership, state and dependencies.

`limits` bounds parsing and `maxFindings` bounds diagnostics, reserving a truncation finding when needed. `complete` means inspection finished without failure or truncation; preserved and unsupported data may still exist. `AiLimitException` distinguishes resource ceilings from malformed syntax while remaining a `FormatException`. `AiNativeAmbiguousFieldError` identifies a failed unique-field lookup without declaring repeated fields invalid. The report is diagnostic, not a serialization gate.

## Saving native edits with host-supplied representations

`AiNativeData.replace` packages an edited program with an explicitly supplied `synchronizedPdf`. For example, renaming a layer does not alter painted geometry, so its existing PDF appearance can be retained:

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

This example requires one native source containing a layer. For visual edits, the host must supply the matching PDF and any required native printing data, text layouts, pixels or previews. The PDF must derive from the original graph and retain metadata references and owner mappings. AiKit does not render the program or establish visual equivalence between supplied representations.

For several independent programs, construct immutable `AiNativeReplacement(source: ..., program: ...)` entries and call `AiNativeData.replaceAll(replacements: ..., synchronizedPdf: ...)`. Every entry must originate from the same `AiDocument` snapshot. Shared owners are one entry; duplicate/overlapping entries reject. All replacement envelopes and aggregate byte limits are checked before a result is published. Unselected native programs remain unchanged.

`replace` and `replaceAll` verify the catalog reference, page count and ordered page references. They also require the original Illustrator dictionaries and their transitively referenced PDF objects, including unselected programs. The host may replace page contents/resources and unrelated producer metadata. Native metadata mutations, stale extraction handles, a separately reparsed PDF, renumbering, page insertion/removal/reordering and changed alias membership reject atomically. Reacquire all handles after a save; use one batch to save several programs from the same snapshot. Page/artboard remapping is not inferred from counts, bounds or owner order. These two APIs preserve the existing mapping; use the explicit mapped-save contract below for structural changes.

Replacement keeps the original compression family, rewrites every shared owner, removes stale native thumbnail blocks, and preserves other producers and private metadata, with the qualified cached-header synchronization below. Mixed native block families on one owner are rejected. New allocations reserve existing dangling references. Old unreferenced objects may remain; replacement is not a redaction operation. Encode the returned document with `AiCodec`; file persistence and save checkpoints belong to the application.

### Explicit native/PDF page mappings

`AiNativeData.replaceMapped(replacements:, synchronizedPdf:, pageLabels:)` saves one or more selected programs with an explicit resulting PDF page sequence. Each `AiNativePageReplacement` contains the immutable native replacement and ordered `AiNativePageBinding(page:, metadataOwner:)` entries. `page` is a current indirect reference in the host graph. `metadataOwner` is the original extracted source's page index, or null to select its catalog alias as a metadata template. A retained native page must keep its own original metadata owner. A new native attachment copies only Illustrator metadata from the explicitly chosen owner; the host's other producer data remains intact. Original catalog aliases remain attached automatically. No mapping is inferred from bounds, UUIDs or counts.

When the original program is attached to the catalog, `catalogPages` explicitly
declares original PDF pages governed by that program which have no page-native
owner. Supply these declarations to `AiNativePageReplacement` or the artboard
helper before removing such pages. Declarations are immutable and must contain
distinct original pages; a source without a catalog owner cannot claim them, and
separately owned native pages cannot be captured. Retained declared pages must
bind to the same replacement. Removed page objects and their metadata remain
preserved, and reachable references to removed pages still reject. Omitting this
declaration retains the existing refusal to remove unowned pages.

For one top-level native Document with one PDF page per artboard, use `editedArtboards.pageReplacement(source:, pages:)`. Supply every current board exactly once through `AiNativeArtboardPage(artboard:, page:, metadataOwner:)`. This helper freezes the bindings in native board order; the save checks that this order matches the host PDF, including when unrelated pages intervene:

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

The host derives its graph from the original snapshot and supplies page content, resources, boxes and dependent PDF structures. Every added PDF page and every retained page of a selected program must be bound. Pages of unselected programs cannot be deleted or have their relative order changed. New attachments cannot overwrite existing Illustrator metadata, and new page references cannot reuse any original object number, including dangling references. Removed page objects remain unreachable with their original native metadata; their page dictionaries may have been materialized by earlier host edits. This is not data erasure.

Original catalog identity, retained native dictionaries and dependencies of retained/copied metadata stay unchanged. Reachable references to removed pages and newly dangling references reject; preexisting dangling references remain reserved. The host must update destinations, annotations, tags and any other dependent PDF structure. Graph checks do not validate all semantic relationships inside opaque bytes or attest to visual equivalence.

Page labels use numerical PDF positions. If page identities/order/count change, the default `requireUpdated` policy requires the host to replace or remove the existing label tree. Explicit `retainPositions` keeps labels at their numerical positions. Supplied trees must have bounded acyclic structure, ordered unique starts beginning at zero within current pages, consistent limits and valid label styles, prefixes and positive counters. The kit does not infer labels from native board names. Native saved print ranges have their separate edit restrictions.

After encoding and reopening a mapped save, extract its native sources again and decode new artboard handles before the next edit. Metadata-owner indices refer to that reopened snapshot's page order. Reusing pre-reorder indices would select the wrong template for a new page; retaining old source handles rejects.

### Cached native headers

All native save APIs synchronize existing PDF `AIMetaData` streams when the supplied native program changes its initial comment header. The original cache must match either the complete source header through `%%EndComments`, or that header without `%%DocumentFonts`, `%%DocumentNeededFonts` and their `%%+` continuations. The same observed profile is applied to the supplied header, preserving its line endings and unknown comments. No artwork operator is parsed or rendered. A font-filtered cache can stay unchanged after a font-only edit.

If the source has no font declarations, those two profiles are indistinguishable. Introducing fonts then rejects rather than guessing the cache's inclusion policy. Other divergent profiles, missing header terminators and non-comment header data also reject changes that require cache synchronization. Older caches with divergent canvas/resource values remain unqualified for header updates. When the native header is unchanged, all existing caches remain exact, including opaque or divergent data. Missing/null caches are not invented, and unselected programs remain untouched.

New cache streams retain unknown dictionary entries and references while dropping old PDF filter/length declarations. Their bytes are written unfiltered. Shared owners reuse the new stream; references outside the selected owners still reach the old stream. Original native metadata must remain unchanged in the supplied graph: callers supply native/header edits through the replacement program, not by overwriting original metadata objects. Planning happens before graph mutation. Encoded inputs, decoded inputs and cache outputs have separate aggregate bounds using `AiNativeLimits`; header line inspection is bounded by `maxTokens`.

`AiPdfDocument.forPdfInterchange(pdf: ...)` explicitly removes stale Illustrator authoring links from a PDF. It does not synthesize native CC editing records.

## Layers, paths and hierarchical records

`AiProgram.decode` reads body instructions outside prologs, setup, procedures, embedded documents and opaque binary samples. It exposes nested layers, source spans, names, visibility, lock/print flags and path segments. Corner/smooth curve operators, shorthand curves, comments and paint operators are retained. `unhandledOperators` and `hasPrivateExtensions` identify unresolved semantics; neither an empty diagnostic set nor a path count proves complete editability.

`AiNativeEditor.updateLayer` changes supported layer names and flags without rewriting unrelated object state. Names use Latin-1 through `name`, or explicit bytes through `nameBytes`; no locale encoding is guessed. `replacePath` replaces plain geometry while retaining comments and paint. It rejects unresolved operators, private editing extensions and appearance-owned geometry that would leave alternate representations stale.

When a qualified CC `As` point count precedes a path, `replacePath` updates it with the geometry. Counted closed paths use an explicit closing endpoint; the writer adds a closing line if the supplied last endpoint differs from the first. Duplicate, interleaved, cross-object or inconsistent counts reject atomically. The capability report flags plain paths in counted programs as requiring this additional validation. Sources without counts retain their existing layout.

### Structure and ownership

`AiNativeRecords.decode(program:)` exposes source-backed dictionaries, arrays, objects and binary resources in ordinary and private `%_` syntax. Unknown fields, repeated entries and embedded drawing commands remain ordered. Use `values(key)` for repeated fields; ambiguous single lookups reject. `decodeBinary(maxOutputBytes:)` performs bounded ASCII85 decoding without claiming support for the enclosed format.

`replaceString`, `replaceNumbers` and `replaceBinary` update existing entries and reparse the result. They are low-level record edits: changing a scalar does not synchronize dependent geometry or appearances. Numeric values must be representable on both the Dart VM and JavaScript; string encodings remain explicit.

`AiNativeStructure.decode(drawing:)` indexes lexical parents, child order, paths, groups, layers, records, version blocks and named style/gradient references. `nodeFor`, `parentOf`, `childrenOf` and `entryFor` require exact handles from the same snapshot. Unknown records stay inspectable without gaining editing semantics. `AiNativeVersions` retains both branches of saved version alternatives; no target Illustrator version is selected.

References distinguish `resolved`, `missing`, `ambiguous` and `conditional` uses. Duplicate declarations stay separate, opposite version branches cannot bind each other, and an empty style name is an unnamed application. Unknown plug-in references remain opaque. Structural ownership does not authorize moving arbitrary byte spans.

`AiNativeObjects.decode(drawing:)` associates paths/groups with their attached dictionary, name, saved XML identifier, panel expansion and default-style application. `bindingIssue` reports unqualified ownership or metadata. Inspection can include private, compound and derived objects that ordinary lifecycle methods cannot edit. Layer-header dictionaries belong to `AiNativeLayers` instead.

### Shared lifecycle policies

Native lifecycle operations preserve source-backed metadata, geometry and state rather than reconstructing objects from a partial model. Selections must contain current, distinct, disjoint owned handles. Unknown dependencies reject atomically.

Copies require fresh caller-supplied identities for every identified descendant, including redundant and alternate CC dictionaries. Layer keys use `AiNativeLayer`; ordinary artwork uses its path/group handle; complete CC pairs use each identified `AiNativeContainer`. The reserved XML namespace includes opaque owners and both version branches. Artboard UUIDs and resource names have separate namespaces. Anonymous objects stay anonymous, and existing references continue to target the originals.

Deleting identities requires a qualified whole-source reference inventory, including unselected resources and styles. Anonymous deletion can retain unrelated opaque data. Removing a parent while retaining its children requires `discardMetadata: true` for qualified nonempty metadata; the option does not bypass reference checks or allow unknown fields to be discarded.

Paint persists across ordinary `u/U` groups and `Lb/LB` layers. Editors retain persistent assignments at the old position and restore known input/output state at the destination, separately for native and printing interpretations. Missing values remain unknown; no graphics defaults or color conversion are invented. An unresolved value still read by retained artwork rejects the edit.

Changing layers, ancestor flags or group depth requires explicit `inheritParentFlags: true` where applicable. Objects retain their own flags and inherit the destination ancestors; this does not reproduce their former effective visibility. Geometry remains in native coordinates. Imported affine ancestors must retain their qualified basis unless an operation explicitly supports rebasing.

Bounds supplied by the host describe complete ink, including strokes and effects. Edits conservatively expand drawing bounds, without inferring artboards or PDF pages. Visual changes require matching host-generated representations before saving.

## Native layers

`AiNativeLayers.decode(drawing:)` exposes wrappers, parent/children, byte names, panel expansion, dictionaries and saved identities for the program's layers. `rootCountHeader` counts roots, not descendants; inspection can report a mismatch, but structural editing rejects one. Saved `%AI5_OpenViewLayers` data is opaque and requires explicit `discardViewState: true` when invalidated.

| Operation | Behavior |
| --- | --- |
| `create(definition:, parent:)` | Appends an empty root or child, including the first layer. |
| `insertAfter(after:, ...)` | Inserts an empty layer using a qualified existing header. |
| `duplicate(layers:, identifiers:, artworkIdentifiers:, names:)` | Copies complete subtrees with fresh supplied identities and optional copied names. |
| `remove(layers:)` | Deletes complete subtrees; removing all roots may leave no layers. |
| `reorder(layers:)` | Permutes selected sibling slots; unselected slots stay fixed. |
| `moveAfter(layer:, after:)` / `moveInto(layer:, parent:)` | Moves a complete subtree under the destination's parent. |
| `reorderArtwork(artwork:)` | Permutes selected mixed ordinary-path/layer sibling slots, retaining independent native and printing state. |
| `moveArtwork(artwork:, parent:)` | Appends an ordinary path or complete layer to a layer or the global root; null parent means root. |

`AiNativeLayerDefinition` supplies explicit attributes, name bytes, optional identity and expanded state. Creation accepts qualified integer-valued 10-, 13- or 14-operand `Lb` layouts; it does not invent a CC document profile. Unsupported masks/flags, conditional ownership and malformed headers reject. Declared root counts update; absent declarations remain absent.

Qualified subtrees can include ordinary paths/groups, direct live shapes and complete CC authoring/printing pairs. Opaque children may survive a header-only edit without qualifying for subtree editing. Copies and deletion follow the shared identity/state rules. Reparenting requires explicit inheritance, and self/descendant destinations reject.

Mixed artwork methods accept exact current path/layer handles whose immediate
parent is a layer or the global root. Group-owned direct selections are excluded.
Selections must be disjoint; moving layers updates declared root counts and
requires explicit invalidation of saved view data where applicable. Source names,
identities and qualified subtree metadata survive these operations.

## Native paths and groups

`AiNativeDrawing` provides ordinary path and group lifecycle operations. Qualified direct live shapes can travel with their complete path and known parameter dictionary. Shapes with separate private/printing representations use the complete-pair APIs instead.

| Path operations | Group operations | Behavior |
| --- | --- | --- |
| `createPath` | `createGroup` | Creates an object at the root or inside an owned group/layer without a sibling template. |
| `duplicatePaths` | `duplicateGroups` | Copies whole objects after their originals, with fresh identified descendants. |
| `removePaths` | `removeGroups` | Deletes objects while retaining persistent state needed by following artwork. |
| `reorderPaths` | `reorderGroups` | Permutes selected sibling slots. |
| `movePathAfter` | `moveGroupAfter` | Moves after an owned anchor. |
| `movePathToLayer` | `moveGroupToLayer` | Appends directly to a layer, including an empty one. |
| `movePathToGroup` | `moveGroupToGroup` | Appends inside an ordinary group. |

`createPath` takes an `AiNativePathDefinition` containing immutable `AiArtworkPath` geometry/process paints, host-computed bounds, optional point counts, flags and byte-valued name/identity. Gray, RGB and CMYK components remain in their supplied space. Geometry uses one initial moveto and finite portable coordinates. Counted closed paths receive an explicit closing endpoint. Advanced styles, guides and private shape parameters need their own contracts.

`AiNativePathDefinition.transparency` supplies a complete `AiNativeTransparency`
tuple for direct path, gradient and live-shape authoring. `replacePathArtwork`
accepts the same value for retained edits. Explicit blend mode, isolation,
three-state knockout and alpha-is-shape flags are serialized without composition
or default inference. Supplying complete transparency requires the legacy `opacity`
shorthand to retain its default; conflicting inputs reject. Both native and
printing boundary states are restored for following owners as before. The host
must support the selected flags and supply the matching compatibility PDF.

`replacePathArtwork` replaces one ordinary path's complete geometry and process
appearance while retaining its attached name, XML identity and qualified metadata.
It supports adding/removing fill and stroke, literal width/caps/joins/dashes,
winding, visibility, lock, normal opacity and overprint. The caller supplies
`AiArtworkPath`, ink bounds and complete scalar flags; omitted values are explicit
defaults, not inherited patches. Counted paths retain their count convention.
Native and printing state are restored separately after the selected object;
unknown outgoing values still needed by a neighbor reject atomically. Private or
dynamic shapes, gradient owners, compound/clipping members and opaque metadata
require their existing specialized APIs. The host supplies a matching PDF when
saving; no renderer or color-space conversion runs in AiKit.

`insertPaths(insertions:)` instead inserts `AiNativePathInsertion` geometry after anchors, inheriting each anchor's appearance and count convention. Equal-anchor requests retain input order. Inserting after a direct live shape creates a plain path without copying the native shape definition.

`groupArtwork(paths:, groups:, liveShapes:)` wraps consecutive sibling owners in an anonymous ordinary group; `groupPaths` uses the same contract. Select entire CC pairs through `liveShapes`, never just a printing group or private path. Source order is retained regardless of selection-list order. Overlaps, skipped artwork and opaque intervening owners reject.

`ungroup(groups:)` removes qualified ordinary parents while retaining children, including complete CC pairs. It removes owned neutral panel/default-style attachments; nonempty qualified metadata needs explicit disposal. Applied parent styles and compound/clipping owners require separate contracts. Grouping or dissolution with non-neutral or unknown parent flags requires explicit inheritance.

Known attached names, XML IDs, finite rotation metadata and qualified panel/default-style attachments move with their objects. Unknown dictionaries, references and unsupported parameter extensions remain rejection boundaries. All operations apply the shared state, identity and bounds policies above.

### Direct gradient artwork

`AiNativeDrawing.gradientArtwork` exposes complete qualified direct fills through
`AiNativeGradientArtwork`: an optional `As` count, one contour, its `Bb`/`BB`
application and exclusively attached name/XML identity metadata. Geometry precedes
`Bb`; one `f`/`F` paint follows `Bg`, and `BB` carries no stroke, an open stroke or
a closed stroke consistent with the contour. The resource must
resolve uniquely. Interleaved state, private/conditional owners, live shapes,
unknown metadata and compound/clipping or applied-style ancestors do not qualify.
An inventory handle establishes ownership, not agreement between stops, caches
and the PDF.

`createGradientArtwork(definition:, gradient:)` inserts a complete fill at a
qualified root, layer or ordinary group boundary. The path definition supplies
geometry, scalar attributes, bounds, process fallback and optional fresh metadata.
It requires a fill and permits an ordinary process stroke through `BB`, with
explicit width, cap/join, dashes and overprint. Gradient-painted strokes require
their separate appearance contract. `AiNativeGradientFillDefinition`
supplies an existing name, absolute origin/angle/positive length, nonsingular
six-value affine matrix and optional radial highlight. This uses the documented
absolute `Bg` layout inside a native CC program; it does not infer relative CC
imaging strips or color interpolation.

`replaceGradientArtwork` replaces the complete owned geometry/application while
retaining original metadata. `setPathGradient` converts an ordinary process path
to this owner, and `clearGradientArtwork` converts it back. Replacement definitions
cannot rename or replace the identity. Independent native and printing state is
restored after the transaction. Resources are never silently removed or modified
for other applications.

`duplicateGradientArtwork` copies complete handles and requires fresh supplied
identities for identified source owners. Qualified containing groups/layers also
retain gradient ownership during lifecycle operations. Mixed layer
`reorderArtwork`, `moveArtwork` and `removeArtwork` accept gradient handles;
partial path-only operations continue to reject dependent gradient contours.
Removing the last application allows explicit `AiNativeGradientResources.remove`.
Artboard transactions retain these complete direct owners.

The host composes resource ramps and the matching compatibility PDF. These native
authoring methods contain no renderer. Absolute authoring instances need no
PostScript `Bm`/`Bc` imaging expansion (AI 7 specification, sections 3.5.3–3.5.6);
EPS/print-stream generation and relative cached instances remain separate
contracts. Regression execution and actual Illustrator exchange are pending.

### Ordinary contour geometry and masks

`pathTopology(path:)` exposes a contour's enclosing groups, compound owner, clipping owner, point count and mask controls. `AiNativePathMask.none`, `.open` (`H W`) and `.closed` (`h W`) are independent of the paint operator's closure.

`editPaths(edits:, bounds:)` applies `AiNativePathEdit` geometry/mask requests atomically. Null fields preserve source data. Paint, metadata, order and unselected bytes remain intact; consumed `As` counts and effective closing endpoints are synchronized. Changing a mask requires an existing `q/Q` owner, and compound masks must change consistently as one transaction. Bounds must include ink exposed by relaxing a mask.

| Operation | Contract |
| --- | --- |
| `compoundArtwork` | Wraps consecutive ordinary sibling paths/groups in an anonymous compound owner. |
| `releaseCompounds` | Removes compound parents; released masks become successive intersections in source order. |
| `clipArtwork` | Wraps consecutive siblings in a clipping owner with explicit mask edits. |
| `releaseClippingGroups` | Removes selected scopes and their effective masks, retaining independent nested scopes. |
| `moveContours` | Moves a batch of contours to an ordinary/compound/clipping group. |
| `moveContourGroups` | Moves complete disjoint contour trees to a group, layer or root. |

Entering another compound requires `inheritCompoundAppearance: true`; changed ancestors require the separate parent-inheritance policy. Compounds cannot nest or become empty, and their contours must retain consistent paint and mask roles. Partial compound branches still have stricter ownership restrictions than whole-tree moves.

Effective `q/Q` scopes restore line cap/join, width, miter and dash state. Colors, overprint, fill rules and object flags remain persistent assignments; `q/Q` inside compounds does not create an independent graphics-state scope. No general PostScript execution model is inferred.

Qualified imported SVG metadata, literal transparency, unchanged text and standalone gradients can be retained without granting arbitrary lifecycle edits to those owners. Affine bases and reference identities must remain coherent. Selected private paths, live-shape printing expansions, unresolved dependencies and unknown mask owners reject these ordinary contour operations.

## CC live shapes

`AiNativeDrawing.decode` separates private authoring outlines from printable expansions and retains group/compound topology, styles and recognized versioned metadata. `liveShapes` associates each `ai::LiveShape` record with its dependent geometry. `bindingIssue` identifies incomplete associations.

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

Solid and qualified linear/radial gradient styles include expanded inside/outside strokes. Shared positional styles are copied where necessary so unselected users remain unchanged. Rotation/scaling require an unambiguous native `RulerOrigin`; page or crop bounds cannot substitute for it. Units remain native drawing units, before application large-canvas scaling. Existing frame-angle representation is retained; edited string angles use six decimal places.

Unknown effects, patterns, clipping, executable transforms, unsupported version branches and unresolved nested appearance ownership reject edits. Unresolved inherited state can block an operation even outside its selection. Conservative DSC bounds retain the original extent and include the transformed artwork; artboards stay fixed. Nonuniform resizing, shear/reflection, fixed-width strokes, fixed corners and parameter-driven shape regeneration are not supported by these operations. The host supplies the corresponding PDF and previews after an edit. `AiNativeEditor.translationBoundsEdits`, `affineBoundsEdits` and `includeBoundsEdits` expose the conservative DSC-bound operations independently.

Complete bound CC pairs additionally support `duplicateLiveShapes`, `removeLiveShapes`, `reorderLiveShapes`, `moveLiveShapeAfter`, `moveLiveShapeToGroup` and `moveLiveShapeToLayer`. Printing groups, private outlines, point counts, panel flags and all saved metadata alternatives travel together; shared styles/resources remain shared. Direct single-path shapes use ordinary path operations.

Copies need fresh IDs for every identified native container. Deletion qualifies all removed identities and preserves definite outgoing scalar effects. Reordering/movement restores native and printing state separately and rejects unresolved values consumed by following artwork. Qualified mixed group/layer subtree operations use the same complete-pair rules. No operation derives printing geometry from native parameters.

### Affine contours and dynamic shape parameters

`AiNativeAffineTransform` stores an invertible `[a, b, c, d, tx, ty]` map in y-up drawing coordinates. Its `scale`, `reflection` and `shear` constructors take an explicit pivot. Scale factors can differ or be negative; shear values are coefficients, not angles. Singular, nonfinite, nonportable and coordinate-collapsing results reject.

`transformPaths(paths:, transform:, bounds:, frameAngles:)` maps ordinary authoritative anchors and cubic controls, including qualified compound and clip contours. Closure, counts, paint, widths, dashes, identities and unselected contours remain intact. Existing frame angles require explicit resulting values through `frameAngles`; they are not inferred from a general affine matrix. This operates on stored contour coordinates and does not expand strokes or transform an entire group implicitly. The host supplies resulting ink bounds and matching PDF/previews.

`transformLiveShapes(shapes:, transform:, bounds:, printing:)` derives parameters for qualified native families with a unique `RulerOrigin`. Every separate CC expansion requires a complete host-composed printing group. Fixed stroke widths and dashes differ from the existing stroke-scaling `scaleLiveShapes` contract. Direct shapes keep their original paint operation. Positional gradients, unknown effects and unresolved dependencies reject.

| Native family | Automatically representable affine changes |
| --- | --- |
| Sharp rectangle | Orthogonal transformed axes retain width/height/angle; nonorthogonal axes become an irregular four-sided polygon. |
| Full ellipse | Orthogonal transformed axes; pie parameters or nonorthogonal axes require host regeneration. |
| Sharp polygon | General affine maps retain its contour and side count, marking nonuniform results irregular with radius unavailable. |
| Star | Similarities and reflection; nonuniform maps require host regeneration. |
| Line | General invertible maps update center, length and direction. |

Rounded shapes accept positive similarities with scaled radii. Nonuniform maps and reflections of rounded shapes require host-regenerated corners and parameters. Reflections require an explicit native winding flag except for lines. Existing frame angles are transformed from their saved first-axis direction; conflicting redundant frame values reject.

`AiNativeParallelogram` exposes a center and two independent half-edge vectors in drawing space. `segments` supplies its four straight sides; `parameters(rulerOriginX:, rulerOriginY:)` supplies canvas-space `ai::Polygon` fields with `NumSides=4`, `IsRegular=false` and `Radius=-11`. The sentinel and irregular-polygon representation are observed in the pinned producer corpus (`simple_shapes.ai`, `simple_shapes_cc.ai`). AiKit does not invent an `ai::Parallelogram` handler. `AiLiveShape.parallelogram` recognizes this geometry after reopening; other quadrilaterals and curved corners return null. A transformed rectangle becomes a polygon, so rectangle-specific corner controls are no longer retained.

`replaceLiveShapes(replacements:)` commits complete `AiNativeLiveShapeReplacement` values atomically: typed `AiNativeShapeParameters`, host-supplied authoring `segments`, complete CC `printing`, explicit nullable `rotationRadians` and ink `bounds`. `fromShape`/`copyWith` preserve known fields while modifying dimensions, corners, ellipse pie angles, polygon side counts, star point counts/radii or line length. The host regenerates matching geometry; AiKit does not verify geometric or visual equivalence between independently supplied parameters, contours and printing artwork. The only family conversion is a sharp rectangle to the qualified parallelogram polygon; unknown fields and incompatible types reject.

Authoritative, redundant and saved alternative metadata are updated together, retaining qualifiers, identities and unrelated bytes. Existing parameter copies must agree. Counts retain closure conventions; printing groups retain outgoing state. Byte/token limits apply to the complete transaction. Saving uses `AiNativeData.replace` with the corresponding host PDF, as for other native edits.

`tool/check_native_affine.dart` emits direct/CC shear and parameter-edit snapshots plus four complete compressed AI saves. `tool/verify_native_affine.py --reference <pinned-extension-ai>` independently checks producer irregular-polygon evidence, native contours/counts/metadata and PDF payloads. These are structural checks, not Illustrator reopen/render certification.

### Host-supplied printing contours

`withPrintingContours(replacements:)` refreshes derived geometry in separate, bound CC live-shape printing groups. Each `AiNativePrintingReplacement` selects a shape from the current drawing, supplies one `AiNativePrintingContours` for every owned appearance path and declares the host-computed ink `bounds`. A batch uses one immutable source snapshot; reacquire all handles from the returned drawing.

Each supplied contour starts with one `m`, followed by native line/cubic segments in the source path's drawing coordinates. It inherits the original paint/closure operation. Compound nesting, paint commands, gradient references, shared styles, private geometry, authoring dictionaries and versioned alternatives remain intact. Multiple contours are accepted only with a self-contained paint operation; wrapped gradient/paint paths require one contour. Coordinates must fit the finite portable range, and generated bytes/tokens obey the source parsing limits. Existing CC `As` counts are updated for every contour, including newly inserted contours. Counted source paths must have one initial moveto and the observed explicit closed endpoint. A supplied implicit closure is written as a closing line; the resulting count includes each anchor once. Uncounted source paths do not acquire new headers. Ambiguous, stale and cross-object count bindings reject.

This operation does not change shape parameters or verify visual equivalence. The host supplies geometry consistent with the authoring records and compatibility PDF, including all stroke/effect expansion. Bounds include inherited transforms and expand document DSC bounds conservatively; artboards remain unchanged. Incomplete/duplicate ownership, foreign or stale handles, nested metadata, unknown local commands and interleaved path-state changes reject atomically. Opaque neighbors outside the selected printing group remain unchanged. Direct authoring paths and arbitrary replacement paint/resource topology are not derived attachment slots. These restrictions govern this edit, not native/PDF packaging.

### Host-supplied printing groups

`AiNativeAppearances.createPathArtwork` authors a standalone private contour with
an existing named appearance and a separate host-supplied printing group. Its
`AiNativePathDefinition` must have null fill and stroke: the contour ends with
`n`/`N`, and the named style owns its visible paints. Geometry, closure, count
convention, flags, name and fresh identity remain on the path, without adding an
authoring group. The definition's bounds cover the complete styled ink. The
transaction shares source ownership, dependency, identity and bounded-output
checks with `createArtwork`. Subsequent mask attachment targets `owner.path`,
geometry changes use `editArtworkPaths`, and paint changes use the named-style
transactions with complete replacement printing. Each save still requires the
matching host PDF; the serializer does not derive pixels or prove equivalence.

`replaceArtworkContours` adds complete standalone contour changes through
`AiNativeAppearanceContourChange`: anchors, open/closed role, visibility and lock.
It retains the source style application, mask Art, names, identities and frames.
Counts follow the new closure. Native flags precede the private contour; printing
flags precede its public group without detaching optional expansion metadata.
Explicit restorations preserve both outgoing interpretations and dictionary
adjacency. Unknown flag state or styles that consume/write those flags reject;
printing coverage must match exactly the selected current body paths. Group
children and live shapes retain their separate contracts. The host supplies
printing for the new revision and its corresponding PDF.

`renameArtworkObjects` changes labels on standalone private contours and private
group descendants through their exact complete body owners. It updates existing
`AIArtName`/`Object name` aliases, preserving declared String/UnicodeString types;
the caller supplies the appropriate bytes. Missing fields acquire an AIArtName
String, including when a metadata dictionary must be created. Empty name fields
and undelimited final metadata entries retain valid framing. Printing artwork,
named-style applications, XML identities, mask Art and geometry remain unchanged;
this nonvisual operation needs no new printing or PDF composition. Printing
objects, mask-local handles, stale handles, incomplete coverage, live shapes and
resource-local owners do not belong to this contract.

`AiNativeAppearances.createGroupArtwork` authors an explicit private ordinary or
clipped group tree from `AiNativeAppearanceGroupDefinition` and
`AiNativeAppearancePathDefinition`. Paths retain their process paints, stroke
settings, full transparency, geometry and fresh metadata. Groups retain their own
flags, labels and optional existing named styles; the root requires a style.
An optional `clip` is an `AiNativeAppearanceClipDefinition` with its own geometry,
open/closed clipping role, winding, count convention and fresh metadata. It emits
an unpainted prefix path inside `q`/`Q`, before the independent content children.
Closed counted masks include their explicit closing endpoint without changing the
`N` paint role. Nested clips retain separate scopes and source identities. Clips
participate in the same aggregate depth, node, output and reference checks.
Printing bytes and ink bounds are supplied independently by the host. This
serializer shares the ordinary path grammar, bounds tree depth/output, and checks
fresh identities and resolved styles across the complete atomic insertion.
It does not flatten children into the supplied expansion. Additional private
image, gradient, text and live-shape children require their respective contracts.
Independent ordinary path, gradient, image/mesh and group insertion now resolves
qualified preceding appearance boundaries and state without treating unknown
neighboring operators as editable.

`withPrintingGroups(replacements:)` accepts `AiNativePrintingGroupReplacement` entries for the same separate, bound CC live-shape expansions. Each entry supplies owned byte data containing exactly one `u`/`U` group and host-computed ink `bounds`. Path counts, ordinary/compound/clipping nesting and local paints can change. Private shape parameters, authoring paths, alternate dictionaries and resource definitions remain unchanged. The host supplies a consistent expansion and compatibility PDF; the kit does not derive artwork from those authoring records or prove visual equivalence.

Each group contains non-private paths with one initial moveto. Source and supplied groups must leave identical effective paint-state assignments, including color representation, opacity, stroke width, caps/joins, miter, dash array/phase, overprint, fill-rule and path flags. Absent assignments use a proven incoming assignment when available; otherwise their inherited value remains unknown. A replacement may introduce local paint only if its final assignment restores that proven value. No default is invented. Transient assignments may differ when the final assignment matches. The qualified attributes are process `g`/`G`, `k`/`K`, `Xa`/`XA`, `O`/`R`, `XR`, `D`, `Ap`, `J`/`j`, `w`, `M`, `d` and the observed `0 opacity 0 0 0 Xy` layout. `Ae` must immediately precede its owned group. Qualified `q/Q` scopes and `h/H W` masks retain effective clipping ownership, including compound masks. Only cap/join/width/miter/dash are restored at effective `Q`; persistent paint assignments still have to match. `q/Q` inside compounds do not establish independent graphics-state scopes. Mask closure participates in count validation even with uppercase paint. See the appearance group contract below for the shared topology restrictions. Qualified `x`/`X`, `Xx`/`XX`, `Xs`/`XS` and `Xz`/`XZ` named colors retain their literal alternatives, names and tint operands. Their outgoing state must also match. `Xd`, executable state and unknown local commands retain separate restrictions. Geometry-only attachment can retain some such controls unchanged under its separate contract.

Complete `Bb`/`BB` gradient fills may reference one existing uniquely named definition. They require one associated filled path, a positive-length `Bg` with flag 1, `BB` flag 0 and an imaging matrix for relative CC geometry. `Bh` requires a radial definition. Gradient-stroke selectors, interleaved state and new or ambiguous resources reject. No renderer is involved in these checks.

Ordinary appearance owners also accept host-composed binary process rasters in their printing group, alone or mixed with paths and effective clipping. `AiNativeRasterSamples.encodePrintingArtwork(matrix:, limits:)` serializes complete public `XG/XN/Xh/XI/XH` framing and optional separate alpha, without object identities, cache metadata, rendering or color conversion. `AiNativeAppearanceArtwork.printingRasters` exposes those derived samples; private authoring paths/groups remain authoritative. Raster placement, depth, flags, byte counts and DSC delimiters use the existing bounded image contract. Private image sections, image dictionaries, linked files, arbitrary payloads and rasters inside compound contours reject. Local inspection does not parse unrelated neighboring image sections. Pure raster expansions currently apply to ordinary appearance pairs; live-shape binding still requires its printable contour contract.

`AiNativeAppearanceReplacement.raster` assembles a complete printing group from explicit process samples, placement and external transparency. It restores the original group's observable assignments using the current source snapshot, including inherited outgoing transparency when provable. Unknown state, stencil pixels, resource-local owners and live shapes reject. The factory does not compose samples or update authoring by itself; apply the result through the native appearance or mask transaction and supply the corresponding PDF on save.

Counted CC source groups must count every path; supplied groups retain this convention whenever both views contain paths, including new paths and explicit closed endpoints. Counts are validated against the supplied geometry, not silently corrected. A raster-only view has no path-count convention; no pending count may cross an image invocation. Byte, token, nesting and portable numeric limits apply before attachment and to the complete result. Document markers, unqualified embedded data and private metadata are forbidden inside the fragment. Batches are atomic and require distinct current source handles. Invalid local syntax/operands throw `FormatException`; unresolved ownership, state, resources or count conventions throw `UnsupportedError`; stale/duplicate handles and invalid constructor arguments throw `ArgumentError`; configured parsing ceilings throw `AiLimitException`.

## Document settings and artboards

`AiNativeDocumentSettings.decode(records:)` exposes the initial numeric header declarations together with their exact `AiToken` spans, top-level `Document` records, ordered artboards and setup `AI11TextDocument` ruler origins. Header inspection stops at the header boundary; embedded documents, procedure comments and declarations in setup/body data cannot replace the owning header's settings. Repeated or version-dependent settings reject rather than choosing a branch. Malformed numeric layouts throw `FormatException`. Parsing retains the source byte/token/depth limits and immutable field collections.

`rulerUnitCode` and `largeRulerUnitCode` retain raw nonnegative codes, including unknown values. `rulerUnit` interprets ordinary codes 0–4 and 6 and large codes 7–10. A present large code takes precedence even when unknown; unknown codes have no inferred enum value. Code 5 remains unqualified. `largeCanvasScale`, `canvasSize`, `templateBox` and `pageOrigin` expose their saved values without unit conversion or substituting defaults when absent.

Artboard bounds use drawing coordinates with y up. `artboard.rulerOrigin` stores the saved artboard origin in canvas coordinates with y down. Each `textRulerOrigins` entry retains its own text-document container and source entry; it is not silently merged with another origin or inferred from a page. Artboards, canvas extent, drawing/ink bounds and compatibility PDF pages remain distinct. This is an inspection contract, not an artboard lifecycle or origin-edit API.

`AiNativeArtboards.decode(records:, document:)` selects one explicit Document owner; omitting `document` requires exactly one. `activeIndex`/`activeArtboard`, `selectedArtboards`, `lastArtboardId` and `cropBounds` are independent saved data. The last ID is not a count or array index. Missing fields remain absent; malformed or ambiguous owners reject.

| Operation | Required policy |
| --- | --- |
| `resize(artboard:, bounds:, cropBounds:, rulerOrigin:)` | Positive drawing rectangle; explicit crop policy and optional ruler-origin change. |
| `create(definition:, index:, lastArtboardId:, cropBounds:, activate:)` | Explicit name, fresh canonical UUID, bounds and canvas ruler origin; insertion and activation choices. |
| `reorder(artboards:, cropBounds:)` | Every current board exactly once. |
| `remove(artboards:, activeArtboard:, cropBounds:)` | Retain at least one board; provide a retained active replacement if the active board is removed. |

A null `cropBounds` preserves the saved crop header. Creating a board requires an explicitly larger `lastArtboardId` only when the original field exists; missing fields stay absent. Reordering/removal preserve creation history. Coordinates and all retained artwork stay in place, including when the first board changes. These methods do not alter the global text origin or infer a PDF-page mapping.

Structural edits require qualified private array entries, unique portable identities and a known retained-dependency scope. Ordinary compound/clipping artwork, complete CC pairs, literal styles/palettes, qualified pattern/symbol/brush artwork, mask resources, local SVG-filter trees and saved perspective controls can remain exact. Retaining their fields does not make their visual semantics editable.

Qualified compact ATE 7/9 main and undo-free snapshots can retain stories, linked frames, typography resources and caches. Compact ATE 11 retention additionally requires both snapshots to contain no stories or frames. Unknown text profiles, drawing/reference owners, cache fields, executable resources and unresolved dependencies reject the affected edit. The original text and graphics coordinate bases remain unchanged.

Save the edited program with matching host pages through the [explicit page mapping](#explicit-nativepdf-page-mappings) contract, including the [cached header](#cached-native-headers) policy. Preserving a resource during an artboard edit does not grant independent editing permission for that resource.

### Native print selections during artboard edits

`AiNativeArtboards.printJob` exposes the selected Document's existing `NotRecorded/AI11 Print JobInfo Dict` as `AiNativePrintJob`, or null when absent. `allArtboards` and `allPages` retain separate optional zero/one integer flags. `artboardRangeBytes` and `pageRangeBytes` preserve exact decoded strings, including encoding markers. Empty ranges, missing fields and dormant selections under an all flag stay distinct. `artboardIndices` returns the stored zero-based selection; `pageIndices(pageCount:)` requires the host's physical output count. Neither getter equates printed pages with artboards or compatibility PDF pages.

The qualified range grammar is a comma-separated list of positive one-based numbers and inclusive ascending ranges, including an open upper endpoint (`2-`). Whitespace and repeated/overlapping selections are accepted; inspection returns sorted distinct indices. Endpoints must fit the declared count, and expansion has a `maxTokens` budget that also counts repeated selections. ASCII and explicit UTF-16 BOM encodings are supported. Unmarked multibyte encodings and other range grammars reject; malformed flags and out-of-range endpoints raise format errors.

Creation, reordering and removal remap stored artboard selections by retained board identity. New boards are not added to an explicit saved selection. All flags retain their meaning independently; dormant nonempty ranges are remapped too. An unchanged numerical selection keeps its exact source spelling. Changed ranges use compact one-based intervals while retaining encoding, field type and unrelated trivia. If removal exhausts an active or unspecified selection, the edit requires an explicit replacement; a dormant range under `allArtboards: true` may become empty without changing that flag.

All four lifecycle methods accept optional `artboardPrinting` and `pagePrinting` values of `AiNativePrintSelection(count:, indices:)`. Null `indices` explicitly selects all and clears the corresponding stored range; otherwise supply a nonempty list of distinct zero-based indices. Inputs are validated and frozen. The artboard count must equal the resulting native count. Both the all flag and range field must already exist when supplying a choice; this API does not invent absent print dictionaries or fields. A supplied choice may replace an unqualified range grammar when its string encoding and field ownership are known.

Physical printed-page ranges cannot be remapped from board ordinals: Illustrator can tile an artboard across several sheets or ignore artboard boundaries. When a geometry, ordinal or stored artboard-selection edit leaves a nonempty physical page range, supply `pagePrinting` from the host's print layout. This also applies to dormant physical ranges; the kit never guesses a new page count. For example, `AiNativePrintSelection(count: 12, indices: [0, 5, 11])` writes `1,6,12` and selects range mode, while `AiNativePrintSelection(count: 12, indices: null)` writes the all-pages flag and an empty range. This is serialization of a supplied selection, not printing, tiling or page composition. See Adobe's [printing guide](https://helpx.adobe.com/illustrator/using/setting-documents-printing.html) for the distinction between artboard and physical-page output.

## Editable text

`AiNativeTextDocument.decode(records: ...)` reads `AI11TextDocument` with PsCore. Choose a container explicitly when several exist. Named CS keys and compact CC keys retain their original syntax; ambiguous aliases reject. The separate `AI11UndoFreeTextDocument` is not silently merged into the current model.

The view exposes fonts, character/paragraph styles, frame resources, stories and `AI11Text` drawing references. Unknown engine fields remain accessible through immutable PsCore values and retained bytes. `referenceIssues` reports unresolved references and cyclic/excessive style inheritance, including drawing references to the undo-free model; it is not a complete typography validator.

`story.modelText` includes the mandatory terminal CR; `story.text` omits that mark. Offsets and run lengths count UTF-16 code units. Present run tables must cover the source text, including its terminal mark, without splitting surrogate pairs. Omitted tables inherit normal styles. `characterStyleAt`, `paragraphStyleAt` and `styledRanges` resolve bounded parent chains, paragraph character defaults and local overrides. Missing fields stay null instead of receiving guessed defaults.

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

`replaceText` inherits character formatting at the insertion start, adjusts native paragraph runs at CR and U+0003 forced breaks, and preserves unrelated stories/resources. A forced break remains inside the same logical paragraph. LF input, malformed UTF-16, split surrogate pairs, removal of the terminal CR, active unsupported auxiliary features and unknown model/view dependencies reject.

`setCharacterFeatures` accepts `AiNativeCharacterChanges` for a selected range: font, size, leading, scale, tracking, baseline, rotation, kerning mode and explicit OpenType switches/sets, plus the qualified text paints and strokes described below. Point size and `RefFontSize` change together; unresolved non-point reference modes and alternate-glyph dependencies reject relevant edits. `setParagraphFeatures` accepts `AiNativeParagraphChanges` for whole paragraphs touched by an end-exclusive selection, including their forced-break spans. Alignment, indents, spacing, hyphenation, direction and composer settings are stored data; AiKit does not implement the selected compositor.

Both change models support `inherit` to remove local overrides without modifying named parent resources. Unknown style features survive qualified edits. Changed inline styles receive fresh identities when required; unchanged fragments retain theirs. `renameStyle` changes only a style's display name.

Content and feature edits invalidate the selected story's rendered-data/glyph caches. Exact no-ops retain the original snapshot. The host must recompose edited text and provide matching native printing/PDF representations before saving. `withoutTextLayout(story:)` explicitly invalidates the same known caches when an external dependency changes without changing the text model. It retains frame references, styles, resources, other stories and the undo-free payload; unknown view fields and stale story handles reject. Repeating it on an already cleared view returns the same snapshot. This intermediate state still requires host composition before a synchronized save. See the [derived-payload policy](HOST.md#derived-representations).

### Text and frame lifecycle

`AiNativeTextDocument.create(records:, font:, fontSize:, fillColor:, rulerOrigin:)`
initializes a compact ATE 7 namespace in a native program without text owners. It
requires an explicit setup and header, retains qualified identified paths/layers,
and creates a host-identified font, normal character/paragraph styles, empty
frame/display/story tables and an independent empty undo-free namespace. The
host supplies actual font technology/version/axes; no font bytes or glyphs are
invented. Initial plain filled-text defaults include unit horizontal/vertical
scale, automatic leading of 1.2, zero spacing/rotation/tracking, enabled visible
fill and disabled stroke/background. `characterStyle` and `paragraphStyle`
override those defaults with the existing typed changes. Foreign font handles and
inheritance requests reject because the new styles have no parent. Style names
are UTF-16, and created resources have fresh identities.

The supplied native text ruler origin is independent of each artboard's ruler
origin. Existing main/undo-free namespaces and orphan `AI11Text` records reject
initialization. Literal DSC font inventories are extended, retaining other
declared font names; deferred/ambiguous headers and unqualified reference owners
reject. Initializer output can be saved using new-document packaging, or added to
an existing fontless AI through ordinary replacement with synchronized header
caches. Creation does not imply composed text or a matching visual PDF.

`createStory` appends a new UTF-16 story with explicit or resolvable normal character/paragraph styles and one or more `AiNativeTextFrameDefinition` values. Select an owned `AiLayer`, or omit it to insert at the drawing root. The main text document supplies typography and the ruler coordinate basis; initialize it with `AiNativeTextDocument.create` when absent.

```dart
final AiNativeTextDocument created = textDocument.createStory(
  text: 'Bonjour',
  frames: [AiNativeTextFrameDefinition.point(x: 120, y: 80)],
  layer: textDocument.records.program.layers.first,
);
final AiNativeTextDocument copied = created.duplicateStory(
  story: created.stories.last,
);
```

`duplicateStory` appends an independent story and fresh frame/inline-style UUIDs while sharing font and named style resources. Its drawing objects follow the last source frame. It preserves model text, frame geometry, antialiasing and explicit frame rotation, but discards the clone's old composition and raw-data identity. `removeStory` deletes its drawing objects and exclusively owned frame resources, then compacts story/frame indices, frame display lists and qualified retained frame strikes.

`insertFrame(story:, index:, frame:)` inserts a new resource into the story's linked flow. `duplicateFrame(frame:)` copies geometry immediately after its source in that flow; it does not copy the story's content. `removeFrame(frame:)` preserves the content and requires at least one remaining frame. Remove the story explicitly to delete its final frame. Flow changes clear the affected story's composition; other stories' qualified frame strikes are renumbered when global resource indices shift. Remapping a retained opaque rendered-data cache rejects until it is cleared/recomposed. Drawing metadata referring to changed raw story data is removed, including after index compaction.

`replaceFrame(frame:, definition:)` updates complete frame geometry and its drawing
confinement together, retaining the global index, UUID, story flow and neighboring
resources. It supports point/area/path definitions under the same ownership
contract. The definition supplies the replacement antialiasing and optional
rotation metadata. All composition and raw-data caches for the owning story are
invalidated; the host must recompose before saving. Replacing a frame does not
change the content or infer geometry from a PDF representation.

Point definitions use ATE y-down coordinates. Set `named: true` for named CS point records. General definitions supply a native resource dictionary plus the matching unpainted `X=`/`X+` confinement bytes for area/path frames. The host owns the correspondence between the two coordinate spaces; the kit validates bounded structure without deriving curves. Glyph composition for path text remains outside the complete-save validation below.

This first lifecycle contract covers one main namespace, named CS or compact ATE 7/9, exclusively owned frames, and ordinary unconditional drawing records at the root, in layers or in ordinary `u/U` groups. It retains qualified native `Document` metadata, typography and the separate undo-free payload. Active undo-free drawing references, orphan/shared/repeated frames, unknown index-bearing fields, populated auxiliary runs, external reference owners, legacy text, clipped/private/conditional group parents, applied appearances, separate printing expansions and unknown setup/drawing dependencies reject atomically. Existing XML artwork identities require their own reference contract and are not silently copied or deleted. Preserved data outside this subset does not become lifecycle-editable.

Ordinary grouped text uses the same global frame/story namespace and canvas
coordinates. Group parents require the shared ownership checks: literal public
boundaries, qualified metadata and ordinary ancestry. Neutral group style resets
and panel expansion fields are retained without becoming text-engine references.
Story/frame duplication follows the existing final drawing reference and therefore
retains that group's parent; deletion and index compaction leave enclosing group
identities intact. This does not qualify opacity-masked, clipped or appearance-owned
text, or introduce new text engine/composition profiles.

`AiNativeLayers.textArtwork` exposes qualified compact native drawing records for
`moveArtwork` and `reorderArtwork`. These operations retain the complete reference
and attached metadata, leave the text engine bytes unchanged, preserve inherited
native state and restore outgoing state around neighboring artwork. Frame geometry
does not change during a hierarchy move. Unsupported text remains an opaque state
boundary rather than becoming movable. Generic layer copy/removal cannot clone or
orphan text resources: use story/frame lifecycle first. Ordinary identified artwork
may be removed beside independently qualified process text; unknown features,
auxiliary cross-references and populated undo namespaces still reject that deletion.

### Composed text and complete-save checks

`withComposedText(story:, view:, bounds:, overflowStart:)` attaches a complete **host-supplied** native ATE view for point/area text. Unlike the source-position-only `withTextLayout`, this view must contain printable `GlyphStrike` leaves. The kit checks frame order, hierarchy, UTF-16 coverage, paragraph/forced-break boundaries, nonempty glyph leaves and allocation bounds. A ligature is not assumed to map one glyph to one character. Declare an intentionally uncomposed suffix with `overflowStart`, including zero for fully overset text.

`withGlyphLayout` supplies a typed compact-CC alternative using the same frame,
line and segment layouts, with `AiNativeTextGlyphLayout` leaves on each segment.
Each segment is one logical shaping cluster. It accepts one-to-one mappings,
several UTF-16 units contracted into one glyph, or one unit expanded into several
glyphs. Many-to-many maps, inserted hyphens and named CS glyph caches still use
the explicit view contract. Glyphs retain source-owned font handles, actual font
IDs, individual origins and host bounds. The kit never reads a font or computes
an advance. A CR must have an explicit `paragraphMark` leaf containing a real
space glyph selected by the host; no hard-coded whitespace glyph ID is assumed.
Coverage, font ownership, finite accumulated origins and allocation limits are
checked before the native view is attached. Rendering and Illustrator acceptance
for the new typed writer remain pending final integration validation.

Appending a font now extends literal `DocumentFonts` and `DocumentNeededFonts`
inventories in complete DSC documents. Deferred `(atend)` inventories reject
rather than receiving an invalid mixed declaration. Headerless native fragments
keep their namespace-only behavior; existing font resource indices are retained.

The host supplies actual font-specific glyph IDs, metrics, advances, mappings and shadow styles for the edited model. The kit does not shape text, validate glyph/font equivalence, or certify the supplied view's visual appearance. Opaque `RenderedData` caches are excluded from this attachment contract. Existing `AI24 TextStoryRawDataUUID` references on the selected story are removed; qualified rotation metadata, unrelated stories and undo-free bytes remain intact. The host also supplies complete y-up ink bounds for conservative DSC expansion.

Before packaging, call `validateTextForSave(overflowStarts: ...)` on the current snapshot. It rejects missing glyph composition, stale or foreign overflow handles and unresolved native ownership. This is an opt-in structural gate: general `AiNativeData.replace`/`replaceAll` serialization remains independent of rendering support. It cannot detect a host deliberately supplying visually stale glyph data of the same source length.

A complete save uses that composed native program with the host's matching PDF graph, derived from the original PDF, then reopens the encoded AI. The host must regenerate/remove affected PDF resources and previews as described in [HOST.md](HOST.md). Neither attaching a view nor passing the structural gate proves visual equivalence with the PDF.

Regression acceptance covers creation, copying, linked-frame insertion/removal, deletion, cache identity invalidation, resource/strike compaction and a second save after reopening a compressed PDF-backed AI. `tool/check_native_text_lifecycle.dart` generates twelve synthetic CC/CS snapshots and two complete saved files; `tool/verify_native_text_lifecycle.py --reference <pinned-inkai-checkout>` checks their ATE data, drawing references and PDF text using independent readers. Synthetic glyph IDs deliberately test serialization rather than font shaping. This evidence is not Adobe Illustrator reopen/render certification or acceptance of every producer profile.

### Text paints and strokes

`AiNativeCharacterStyle.fillPaint`, `strokePaint` and `backgroundPaint` expose immutable `AiNativeTextPaint` payloads after resolving the existing style hierarchy. Each retains its complete source `record` and saved `tag`. Its `color` is a typed `AiNativeTextProcessColor` only for a qualified `SimplePaint` with literal process components and the observed fixed leading value of one. Unknown tags, fields, color models and other leading values retain their source and return null for `color`; malformed known tuples and ambiguous compact/named aliases reject.

The component models are gray, RGB and CMYK in zero-to-one coordinates, and Lab with L in zero to 100 and a/b in -128 to 127. Components describe the saved model; they do not infer document profiles, convert between spaces or supply alternate color values. Compact color dictionaries use `/0` for `Type` and `/1` for `Values`, as observed in the complete producers.

`AiNativeCharacterChanges` accepts `fillColor`, `strokeColor` and `backgroundColor` as explicit process tuples. It also accepts the independent enabled/visible flags, fill-before-stroke order, overprint, line cap/join, width, miter limit, dash offset/array and background enablement. Missing settings stay null when reading; assigning a color does not enable or reveal its paint. Width is nonnegative, cap/join use native values zero through two, and miter limit is at least one. Dash offset may be negative. Dash lengths are nonnegative, an empty array denotes a solid stroke, and a nonempty all-zero cycle rejects. Numeric stroke inputs must be finite and portable between the Dart VM and JavaScript.

These edits split only the selected UTF-16 runs, retain named parents and local extensions, preserve each existing field spelling, and allocate fresh local style identities when necessary. `inherit` removes selected local paint/stroke overrides without changing independent flags or named resources. Equal local paints and dash arrays preserve the original snapshot, including exact numeric lexemes and layout caches. A changed paint invalidates the selected story's composition through the same feature-edit contract; other stories, frame resources, drawing records and the undo-free snapshot stay exact. Recomposition remains the host's task.

Color replacement or inheritance requires qualified process paint in every selected resolved range. Named colors, patterns, gradients and future paint descriptors remain inspectable; this API does not silently replace an unsupported paint payload. Text blending records and general shared text-style lifecycle have separate contracts. These ATE edits do not relax `AiNativeAppearances` reference checks or qualify global pattern-resource changes through opaque text paints.

### Fonts, frames and supplied layouts

`addFont` registers an `AiNativeFontDefinition` with a host-supplied PostScript name, technology, optional version and signed 16.16 variation coordinates in font-axis order. It preserves existing indices and resources, allocates a fresh identity and returns the new font as `fonts.last`. It does not load or embed a font, deduplicate equal names, or choose a fallback face.

`story.strikes` exposes saved frame/row/line/segment/glyph observations, including origins, bounds, character mappings and glyph IDs. A glyph is not assumed to represent one character. Retained caches are not newly composed text.

`withTextLayout` writes host-supplied `AiNativeTextFrameLayout`, `AiNativeTextLineLayout` and `AiNativeTextSegmentLayout` data. Layout coordinates use native y-down points: line origins are frame-relative and segment origins are line-relative. Frames must match the story's resource order; UTF-16 coverage, visual-order mappings, overflow and allocation limits are checked. Supply `overflowStart` for an uncomposed suffix. Compact reordering and qualified terminal automatic-hyphen maps are supported; named CS equivalents and per-glyph path geometry remain unsupported. No font measurement or GlyphStrike generation is performed.

`translateFrames` moves selected point, area or path frames in y-up drawing coordinates. It updates frame matrices and corresponding native confinement paths while retaining local text/layout data and unselected linked frames. It accepts qualified unpainted confinement geometry; ambiguous text documents, missing references, complex appearances and unresolved frame metadata reject. `AiNativeArt.decode` exposes bounded confinement commands and nested metadata without executing PostScript. DSC bounds expand conservatively while artboards remain fixed. Printable appearances, undo-free copies and effect caches still require host coordination.

## Ordered native appearances

`AiNativeAppearances.decode(structure:)` exposes every source `KnownStyle` declaration, including duplicate names and unused styles. Each `AiNativeAppearance` retains its resource owner, original definition and potential named uses. `resolve(use:)` returns a definition only for a uniquely resolved reference from the same snapshot. Missing, ambiguous and conditional references remain explicit; selecting a part does not isolate one user of a shared style.

Active styles expose a preorder `parts` inventory, with `parentIndex` and ordered `childIndices` preserving the complete `Execution` tree. Stacks and chains stay distinct. Hidden parts, repeated fills/strokes and effect-local paint fields keep their original owners. `forSource(record:)` selects an exact part handle; foreign/stale handles reject. `SimpleStyle` exposes its separate `simplePaint` commands. Unknown definitions and filter nodes keep their original records.

Each part exposes its literal filter-name bytes and both flags, optional local visibility, native `FillOrStroke` selector, parameter dictionary and ordered paint payloads. Absent visibility remains null; it is not resolved through ancestors. `FillOrStroke` is a saved native field, not the host's UI selection. Known fill parts expose explicit `UseEvenOdd` values. Ordinary stroke descriptors identify centered alignment only when no contradictory offset field is present. `Adobe Stroke Offset` with the qualified built-in module locator exposes explicit inside/outside alignment; absent flags and external modules do not acquire a default alignment. Future descriptor flags, unknown parameters and opaque effects are retained without execution or semantic editing claims.

`AiNativePaintStyle.assignments` exposes source-ordered literal process colors, overprint, width, cap/join, miter limit, dash lengths/phase, winding and both `Xd` flags. Repeated assignments remain separate, including across unknown commands; these are not effective or inherited values. Seven-operand `Xa`/`XA` retains both authored CMYK and RGB alternatives. Dash phase can be negative and an empty array explicitly means a solid stroke. Named ink assignments expose `namedColor` while returning no process `colors`. Gradient assignments expose their exact `gradient` instance. Patterns and unknown commands remain in the full command inventory without invented color values. No defaults, color conversion or appearance composition are synthesized. Literal assignments are validated when their view is requested, with the original portable numeric and parsing limits.

### Selected-part and shared-style changes

`updateSelected(appearance:, paints:, parts:, artwork:, printing:, nameBytes:)` copies a qualified style under a fresh byte name and rebinds only explicitly selected users. `updateShared(...)` updates the original definition, requiring coverage of every named use and a qualified whole-source reference scope. Unused qualified styles need no printing group. Literal process and qualified named paints in `SimpleStyle` can be edited. Exact gradient rebinding targets qualified active-style paint parts; simple-style gradients and unknown commands retain separate restrictions.

`artworkFor(use:)` binds a qualified named application to its authoritative private contour/group/live shape and separate ordinary printing group. `authoring`, nullable `path`/`group`, `metadata`, `groupContours` and `resource` expose ownership without flattening private compound or clipping topology. An enclosing clipping parent must retain its masks and saved contour state.

`AiNativeAppearances.editArtworkPaths` replaces selected authoritative private
contours and their complete supplied printing groups in one immutable transaction.
Select paths through the current owner's `path` or `groupContours`; several child
edits share one outer printing replacement. Only geometry changes are admitted by
this API: closure, paint, native clipping/compound roles, masks, identities, style
applications and other metadata remain retained. Owned `As` counts and explicit
closed endpoints follow the new geometry, including closed clipping contours whose
paint operator is `N`. Optional `frameAngles` updates private path/group frame
metadata; omitted angles retain their saved values. Native live shapes still need
their parameter-and-contour transaction, and resource-local geometry requires
instance-dependent printing coverage. Every supplied owner must contain a selected
contour; missing, extra, stale or derived-printing selections reject. The host
supplies complete ink bounds and the same-revision compatibility PDF.


`AiNativeAppearances.replaceArtworkPaths` supplies complete geometry and direct
process paints for independent children of retained private group owners. Each
`AiNativeAppearancePathChange` specifies fill/stroke presence, closure, winding,
line metrics, visibility/lock, overprint and opacity or a full transparency tuple.
The transaction updates point counts and leaves child dictionaries, identities,
frame metadata and group style applications intact. It writes explicit private
state before the contour and restores known original values after its metadata.
Unknown original values require a source-order proof that no following path,
group, image or style reads the changed state before it is assigned again.
Multiple changed children share one complete supplied printing group. Compound
contours, mask contours, children with attached named styles, single-path owners,
live shapes and resource-local owners keep their separate contracts; clipping
ancestors may remain around an independent ordinary child. Printing and the
compatibility PDF still come from the same host revision.


For each affected owner, supply one complete `AiNativeAppearanceReplacement(artwork:, bytes:, bounds:)` through `artwork`. The `printing` parameter retains `AiNativePrintingGroupReplacement` as a live-shape shorthand. Both can participate in one transaction, but ownership must not overlap.

`nestedUses` inventories qualified named child applications. `authoringFor(use:)` returns the exact child path/group; a child has no independent printing boundary. Select children explicitly through replacement `uses`, with one complete printing group for their enclosing owner. Retaining a child in that group does not select it or satisfy shared-use coverage. The writer checks state at each application to protect unselected siblings.

| Change model | Behavior |
| --- | --- |
| `AiNativePaintChange` | Changes an exact assignment; retains its operator, operand count and authored color alternatives. |
| `AiNativeAppearancePartChange` | Changes qualified visibility, winding, alignment and stroke settings. Offset-stroke labels require explicit source-encoded bytes. |
| `childOrder` | Permutes every current direct child of a stack/chain without changing ownership. |
| `children` with `AiNativeAppearanceChild` | Retains, copies, creates, removes or reparents children; mutually exclusive with `childOrder` on the same parent. |
| `AiNativeAppearancePartDefinition` | Creates process or named fills/strokes, explicit blend parts, stacks/chains and conduits with explicit paint/settings. |

Copies retain their original snapshot, not simultaneous edits to the original. Retained children must occur once; cycles, stale/foreign handles and edits to removed parts reject. Unknown effects and parameters are preserved but do not qualify for these changes.

`strokeSettings` exposes saved version and dash-adjustment fields. Existing `adjustDashes` edits require the qualified version-one dictionary and an existing Boolean; new stroke definitions may supply the field explicitly. The host computes adjusted dash geometry. Dash arrays/phase remain explicit; no profile conversion or composed defaults are generated.

Native edits, selected-style copies/rebinding and supplied groups are one atomic transaction. Groups follow the printing-group contract, including counts, masks, resources and identical outgoing printing state. Changed native state must not leak into following artwork. Where provable, the writer restores uniform explicitly visible original scalar values privately after selected applications; unknown or divergent values still reject. Private restoration cannot repair a printing-state dependency.

Ambiguous/conditional styles, captured names, incomplete shared coverage, enclosing applied styles and conflicting replacements reject. Resource-local users additionally require the transaction described below. Text users, opacity-mask resources and unqualified instance dependencies do not acquire support merely because their style is inspectable.

### Named appearance lifecycle and application

`AiNativeAppearances.createStyle(nameBytes:, execution:)` initializes a named
`KnownStyle`/`ActiveStyle` resource without a preexisting appearance. Its execution
is an explicit `AiNativeAppearancePartDefinition` tree: basic fill/stroke/blend or
conduit, or nested stacks/chains. Children must use
`AiNativeAppearanceChild.create`; source-owned children cannot be silently moved
or copied into a new resource. Native process alternatives or literal named paints, stroke alignment,
dash settings, visibility and complete transparency use the existing part writer.
No geometry or printing content is generated.

Creation requires a fresh nonempty byte name across declarations and references,
one explicit setup boundary, and a qualified reference scope. It creates an unused
style and preserves all body bytes. `removeStyles(styles:)` deletes current
distinct unused setup declarations after whole-source reference qualification;
referenced, conditional, duplicate or opaque dependency scopes reject atomically.
Unused definition changes need no new visual PDF; applying a style does.

`applyStyle(appearance:, artwork:)` rebinds selected existing body applications to
one current uniquely declared style. Supply the complete host-composed printing
group once per owner; `AiNativeAppearanceReplacement.uses` can select outer or
private child applications. Native contours, group topology, identities and mask
fields remain attached. Unselected users retain their original style and no new
style is cloned. Following-state checks cover both old and new style reads/writes;
where necessary, provable old scalar values are replayed privately. Missing or
divergent required values reject. Resource-local applications require their
dependent-instance propagation contract and are not admitted by this method.

The existing `updateShared`/`updateSelected` transactions also edit newly authored
styles. Basic execution roots now use the same literal-field validation as compound
roots. Focale's complete named-appearance/mask connection remains integration work.

### Initial appearance artwork

`AiNativeAppearances.createArtwork(bytes:, bounds:, parent:, layer:)` inserts one
complete host-authored appearance pair into the body, an ordinary group or a
current layer. At most one parent selector may be supplied. Bytes contain optional
explicit scalar inputs, one public printing group, its empty `6 () XW` boundary,
private authoring geometry and metadata, and one final public `1 (name) XW`.
Private ordinary, compound and clipping groups may retain qualified child style
applications. Bound live-shape pairs use the same existing ownership contract.
Every referenced style must already resolve uniquely in the destination; use
`createStyle` first when initializing a document without appearance resources.

The transaction binds the inserted pair before publishing a new snapshot. It
rejects captured outside geometry, additional public applications, detached
content, document-section changes, unknown inherited scalar inputs and opaque
metadata. New object identities must be portable and fresh across the document
and the entire insertion. Qualified masks may accompany authoritative metadata;
their artwork cannot introduce native object identities, and raster cache
identifiers must be absent or fresh and unique. Allocation and parser limits apply
to both the inserted data and the complete resulting program.

Native and printing state are tracked independently, including private child
styles and qualified clipping scopes. The writer restores provable incoming
values after the pair; unknown differences must be shown irrelevant to following
artwork. Existing owners and declarations retain their source bytes. The returned
snapshot exposes the new object through `artworkFor` with current handles.

The host supplies native geometry, printable geometry, actual ink bounds and the
matching compatibility PDF on full save. This API proves ownership and dependency
coherence; it does not render or compare those representations. Resource-local
creation and Focale's full appearance composition connection require their
separate lifecycle contracts.

### Appearance object removal

`AiNativeAppearances.removeArtwork(artwork:)` removes distinct current body owners
returned by `artworkFor`. Each transaction removes the entire printing/native
pair, its metadata, qualified masks and private child applications. Native group
and clipping subtrees and bound live-shape alternatives leave together. Shared
style definitions remain declared; an unused style can subsequently be removed
through `removeStyles`. The host supplies the updated compatibility PDF on save.

Removal preserves the observable boundary state in both interpretations. Known
printing outputs are retained publicly and native outputs privately; transient
attributes restored by an inner clipping scope are not replayed as persistent
values. Unknown style outputs must be overwritten before following artwork reads
them. This check spans all selected owners in source order, even when the caller
supplies them in another order. Unselected owners retain exact source bytes.

Deleting object identities additionally requires a qualified whole-document
reference scope and unambiguous identities, including identified mask descendants.
Anonymous owners can leave beside opaque preserved content when no unresolved
state reaches it. Resource-local owners, stale handles, duplicate selections and
overlapping owners reject. Original allocation limits apply to
the replay and complete output; topology, retained applications and identity
counts are checked after serialization. Qualified live-shape owners are reused
by reference and dependency inspection, including authoritative masks, without
reclassifying them as ordinary unqualified geometry.

### Appearance object duplication

`AiNativeAppearances.duplicateArtwork(artwork:, identifiers:)` copies distinct
complete body owners immediately after their original source. Each copy retains
its native/printing geometry, child applications, group and clipping topology,
opacity masks and live-shape metadata alternatives. All named styles stay shared;
the method does not clone declarations or apply a geometric offset. The host
composes the updated compatibility PDF, including any overlap/blending effects.

The `identifiers` map must cover exactly every identified metadata container in
the selected source spans, including identified mask descendants. Each replacement
must be a fresh portable XML name, unique across the source and the entire batch.
Repeated saved identities reject pending an explicit alias contract. Existing
references to the original objects retain their original targets. Raster cache
identity fields in copied masks are renewed automatically with distinct UUIDs;
sample planes, binary framing, placement and mask flags remain unchanged.

Source inputs are compared with the copy's insertion state independently in the
native and printing interpretations. Necessary known values are replayed before
the copied pair; required unknown changed inputs reject rather than acquiring
defaults. Outgoing effects and following dependencies are checked before applying
the batch. Internal clipping scopes retain their actual boundary state. Supplied
order does not change placement: each selected owner receives one adjacent copy.
The result checks geometry, resource applications, identity counts and copied mask
cache uniqueness under the original aggregate output limits. Unselected and
original owners remain byte-exact. Resource-local copying and relocation use
separate dependency contracts and are not provided by this adjacent-copy method.

### Appearance object movement

`stateAtArtwork` exposes known scalar values after a current complete body owner,
or immediately before one of that owner's printing rasters. `statesAfterArtwork`
inspects distinct complete endpoints in a single source traversal. Each immutable
result distinguishes native and printable assignments; missing values have no
invented defaults, and unknown sets identify assignments invalidated by unresolved
source operations. This is source-state inspection, not appearance composition or
permission to edit private/printing descendants independently.

`AiNativeAppearances.moveArtwork(artwork:, bounds:, before:, after:, beforeObject:,
afterObject:, parent:, layer:, inheritParentAppearance:)` relocates a complete body pair without changing
its geometry, identities, mask samples/cache IDs or shared styles. Supply at most
one destination selector: before/after a different complete pair, beforeObject/
afterObject an ordinary artwork handle, or append inside
a current public ordinary/clipping group or layer. With no selector, append to
the document body. Repeated moves reacquire handles from the returned snapshot.

Ordinary anchors use the mixed-artwork ownership contracts for paths, groups,
layers, gradients, meshes, embedded/linked images and isolated text references.
Insertion occurs outside the complete source span, including point counts and
metadata. Layer and image inventory wrappers are rebound through exact source
handles; equal offsets from another decoded snapshot do not qualify. Private,
printing and mask descendants of an appearance cannot serve as independent
anchors. Ordinary ancestors remain subject to their existing qualification;
this does not make opaque native content editable.

Both source and destination ancestry must be qualified. Private, compound,
derived and applied-appearance parents cannot receive independent pairs. Moving
across layers, changing group depth/flags or entering/leaving a different clipping
ancestor requires explicit `inheritParentAppearance: true`. Reordering within the
same qualified clipping context does not itself change inheritance. This option
accepts the target context; it does not rebase geometry or flatten masks.

The host supplies actual resulting ink bounds and the corresponding compatibility
PDF, including changed stacking, clipping and inherited visibility. Document
bounds are enlarged when required. Known outgoing values are retained at the
former slot; source inputs and original destination outputs are restored around
the moved bytes in each interpretation. Unresolved effects must not reach a
following read, and required changed unknown inputs reject. The transaction checks
the entire removal/insertion before applying edits under the original limits.

Ordinary `AiNativeLayers.reorderArtwork` permutations can retain qualified
appearance pairs between their selected slots. Their state contributes to the
native/printing dependency checks without making their descendants independent
selected owners. `replacePathArtwork` likewise resolves neighboring complete
appearances when qualifying an ordinary path and restoring its outgoing state;
selecting a private or printing descendant requires the appearance transaction.
These contracts do not imply general ordinary subtree mutation of private owners.
It then verifies topology, application order, identity counts and exact bytes of
every qualified retained/moved owner. Resource-local relocation and coordinate
rebasing across unsupported parent metadata remain separate contracts.

## Native transparency and opacity masks

`AiNativeTransparency` remains the common literal `Xy` model: sixteen blend modes,
opacity, isolation, three knockout states and alpha-is-shape. Existing assignments
use `AiNativePaintChange.transparency` with selected/shared appearance transactions.
Fill/stroke transparency and a whole-object `BlendStyle` are separate applications;
none of these fields is an inferred effective value.

`AiNativeAppearancePartDefinition(kind: .blend, transparency: ...)` creates a new
blend part in an existing stack/chain. Fill/stroke definitions also accept the
complete `transparency` value. The legacy `opacity` shorthand remains available
for normal blending; supplying both a complete value and a nondefault shorthand
rejects. The existing child transaction can retain, create, replace or remove blend
parts on qualified paths, groups, nested named users and live shapes. Exact owner
selection, shared coverage, native state checks and host printing remain mandatory.

`AiNativeOpacityMask.decode(records:, record:)` exposes the four explicit flags
(`linked`, `disabled`, `clipping`, `inverted`) and source-preserved `artworkBytes`.
Only literal fields with complete `X=`/`X+` boundaries qualify for this typed view.
`artworkDrawing` additionally checks vector/group/raster syntax for host composition;
unknown commands and named resource dependencies reject that getter while raw
artwork remains preserved. It does not render luminance, alpha or inverted pixels.

`AiNativeOpacityMask.encodeVectorArtwork(records:, elements:, private:)` writes
complete `X=`/`X+` payloads from immutable process-path and group definitions.
Paints, line metrics, opacity, names and optional group clips use the same bounded
native serializers as ordinary authoring. Empty artwork is explicit. The first
boundary has no line prefix; subsequent commands use the requested representation,
so the result can be passed directly to mask creation/update. Escaped names are
not interpreted as comments or drawing commands. Named group applications and XML
identities reject because mask lifecycle currently lacks their reference contract.
This method serializes mask artwork; it does not compute luminance, clip background,
inversion or the host's matching composed printing view.

`artworkFor(use:).opacityMasks` binds masks on an ordinary CC authoring path/group
and its private child dictionaries to their complete printing owner. Clipping-path
contours remain a separate model. `authoringForMask(mask:)` resolves the exact
current private path/group carrying a selected mask, including child and live-shape
carriers; foreign/stale handles reject. Nested mask-artwork descendants remain in
the Art payload rather than acquiring independent printing ownership.
Flags can be changed without touching mask
artwork, including recursive masks, counted raster samples, placement and image
identities. A live shape can bind a mask in its authoritative dictionary; masks
in printing or alternate metadata copies reject. Geometry transformations and
copies keep their separate mask-synchronization restrictions.

```dart
final AiNativeAppearanceArtwork owner = appearances.artworkFor(use: selectedUse);
final AiNativeAppearances changed = appearances.updateOpacityMasks(
  changes: [
    AiNativeOpacityMaskChange(
      mask: owner.opacityMasks.single,
      settings: const AiNativeOpacityMaskSettings(
        linked: true,
        disabled: false,
        clipping: true,
        inverted: false,
      ),
    ),
  ],
  artwork: [
    AiNativeAppearanceReplacement(
      artwork: owner,
      bytes: hostPrintingGroup,
      bounds: hostInkBounds,
    ),
  ],
);
```

Several selected masks can share one supplied printing group. Omitted, duplicate,
stale and unrelated owners reject. Optional `artworkBytes` replace the complete Art
payload, including its `X=`/`X+` boundaries and source-private line representation.
Vector, empty and inline process-raster replacements are qualified using the same
retained-mask grammar. Replacement cannot introduce/discard XML artwork identities
or named style/gradient dependencies. Image cache UUIDs, when supplied with changed
artwork, must be valid, fresh and unique; absent cache identities are allowed.
Unchanged payloads keep their identifiers. Unknown fields, executable mask commands,
conditional owners and source/output-limit violations reject atomically.

`createOpacityMasks(masks:, artwork:)` attaches explicit
`AiNativeOpacityMaskAttachment(artwork:, target:, settings:, artworkBytes:)`
definitions to current private paths or groups. `target` defaults to the owner's
authoring object; exact child handles select private descendants. Missing object
dictionaries are created, existing fields retain their bytes and a second mask on
the same target rejects. Complete native Art bytes include `X=`/`X+` and the
matching private representation; counted binary payloads are never line-rewritten.
Live-shape attachment requires no alternate metadata dictionaries.

`deleteOpacityMasks(masks:, artwork:)` removes selected fields while keeping the
owning geometry, remaining dictionary fields and unselected masks. Multiple masks
inside one private group require its printing replacement only once. Creation and
removal use the same current-owner and printing-state checks as updates. New mask
artwork cannot introduce XML identities; removing identity-bearing mask artwork
rejects pending a reference-aware lifecycle contract. New raster cache identities
must be absent or valid, fresh and unique. Source and output limits apply before a
new snapshot is exposed.

Resource-instance propagation, named dependencies, text masks and redundant mask
metadata copies still need their own ownership contracts. Disabling a mask
preserves its native artwork. Saving requires the matching host PDF through
`AiNativeData.replace`; stale native thumbnails follow the existing invalidation
policy. These are data/serialization checks, not Adobe visual acceptance.

## Native artwork resource ownership

`AiNativeArtworkResources.decode(structure:)` inventories complete pattern, symbol and brush declarations; `AiNativeAppearances.artworkResources` exposes the same association. Definitions retain namespace, literal name, source spans, pattern rectangle and version memberships. Equal names in different namespaces, duplicate declarations and conditional alternatives remain separate.

Local `items`, `paths`, `groups`, `gradients`, `metadata`, `tokens` and `rasters` retain absolute source positions and resource-local coordinates. Private authoring and ordinary printing data stay distinct. Unknown payloads remain available without execution. Local paths are inspection handles, not body-edit handles.

`forUse(use:)` identifies the exact containing resource, or null outside these declarations; `uses` retains known style/gradient references. This is not a complete instance or plug-in dependency graph. Qualified pairs can be bound through `artworkFor(use:)`, whose `resource` points to their declaration.

Resource-local `updateSelected`/`updateShared` transactions require a qualified whole-source reference scope. Supply `dependents: List<AiNativeAppearanceReplacement>` for every affected pattern-style application, including nested uses and transitive resource owners. Secondary replacements retain their style definitions, reference names, native geometry and metadata. Recursive resources, ambiguous definitions and incomplete coverage reject.

Resource replacements use local bounds and point counts; they do not expand document bounds or change pattern tile rectangles. Dependent body replacements do expand document bounds. Every resource must retain outgoing state independently.

Qualified unreferenced patterns, symbols and brushes can be edited. Connected brush descriptors, direct pattern consumers without a printing owner, unknown instance links, unresolved text/mask dependencies and unsupported reference schemas reject. Preserving such resources during another operation is a separate, narrower contract.

## Gradients and paint styles

`AiNativeDrawing.gradients` exposes `Bb`/`BB` instances, relative `Bg` geometry, radial `Bh` focus and absolute `Xm`/`Bm`/`Bc` printing matrices. It retains the paths consumed by each instance and any gradient-stroke selector. `AiNativePaintStyle.decode` reads owned fill, stroke, blend and simple-style command lists without flattening repeated appearance parts.

`AiNativeGradientResources.decode` reads global `Bd`/`BD` definitions, including nonprinting swatches, native `Bs` stops, fallback `BS` stops and `Br` printing intervals. Byte names, stop order, opacity wrappers and numeric channel forms are retained. Gray, RGB/CMYK, custom and newer named colors expose their recorded alternatives and tint data; no color-profile conversion is implicit. `AiNativeGradientColor`, `AiNativeGradientStop` and `AiNativeGradientRamp` provide the immutable color, stop and channel data used by resource edits.

### Stops, focus and resource ownership

`replaceStops(definition:, stops:, ramps:)` updates every definition sharing the selected byte name. Supply nondecreasing stop positions and one host-composed ramp per adjacent pair. The writer updates native/fallback stops, counts and printing intervals; it writes linear stops descending and radial stops ascending. It does not prove that supplied ramps reproduce the stops.

Moving linear stops also updates all qualified strip/cap references while keeping the overall gradient axis fixed. Legacy matrices without `Xm` require consistent recoverable geometry. Missing caps, unmatched references, mixed same-name kinds, unknown metadata and excessive expansion reject. Coincident stops in changed cached linear strips require the host-composed printing contract below. Resource-local formatting may be regenerated; unrelated bytes remain intact.

`setRadialFocus(definition:, angle:, length:)` changes all instances using a resource, including shared styles and private artwork. Angles are degrees in −360..360 and length is a normalized radius in 0..1. Authoring polar values and Cartesian printing offsets update together; inconsistent or singular source geometry rejects. This is a global edit, not selection-local recoloring.

`isolateLiveShapeGradient` first copies a named gradient and matching styles for selected live shapes, updating bank counts and selected bindings. The new byte name must be unused. Decode resources from the returned drawing before editing that copy. All occurrences inside that selection change together. Use the exact appearance-assignment API below to isolate one paint application.

### Gradient lifecycle and hard stops

`AiNativeGradientResources.create(nameBytes:, radial:, stops:, ramps:)` creates a new CC definition in every existing counted `Bn` bank, retaining printing/nonprinting placement and unrelated source. An explicit setup without banks receives its first bank. Names must be nonempty and unused by declarations or applications. `remove(definition:)` removes every same-name definition, including its gradient wrappers, and adjusts every affected count. Existing drawing, style or palette references prevent removal; remove/rebind those applications first. Handles belong to one immutable source snapshot.

Lifecycle operations qualify the whole source reference graph before writing. Opaque reference owners, unresolved resources, populated ATE dependencies and conditional gradient banks remain rejection boundaries. Creation does not copy arbitrary procedure bodies or silently introduce new prologs. Numeric, token and aggregate output limits apply.

Stops now allow equal adjacent positions with distinct ordered colors: the earlier stop is the incoming side and the later stop the outgoing side in caller order. Positions must be nondecreasing with a positive total extent. Supply one `AiNativeGradientRamp` per adjacent pair, including the zero-width transition; no epsilon displacement or synthetic interpolation is used. Linear serialization reverses the entire stop sequence, including equal-position order; radial serialization retains caller order. Both authoritative and compatibility copies are written coherently.

For linear positional edits, existing cached `Bm` interval strips cannot be repartitioned through a hard stop automatically. The host supplies a complete regenerated printing group, possibly using ordinary contours instead of strips. Matrix-free native style/palette notes and radial whole-gradient matrices can retain their placement. An unchanged existing position sequence does not reinterpret its geometry. Native stop changes and supplied ramps alone do not prove that flattened artwork or PDF content has been refreshed.

### Exact applications and named paints

`AiNativePaintStyle.assignments` includes one `AiNativePaintParameter.gradient` per exact `Bb`/`BB` application. Select the assignment from the desired appearance part, then use `AiNativePaintChange.gradient(assignment:, definition:)` through `AiNativeAppearances.updateSelected` or `updateShared`. The target resource must already exist in the same snapshot, with the same linear/radial kind. Placement/focus and other paint applications retain their bytes. Cached interval geometry additionally requires matching stop positions; matrix-free notes can bind a new hard-stop resource.

`updateSelected` isolates the style for the explicitly supplied users and changes only the chosen assignment. Another fill using the same gradient stays bound to its original resource. `updateShared` requires every user and printing owner. Complete printing groups, outgoing-state validation, resource-dependent expansion coverage, and native state checks remain mandatory. This also covers retained nested users under the existing appearance ownership contract. No visual correspondence between host groups and native gradient values is inferred.

`AiNativeNamedColor` exposes five exact native layouts: legacy CMYK `x`/`X`, generic CMYK/RGB `Xx`/`XX` with selectors zero/one, named CMYK `Xs`/`XS`, and explicit CMYK+RGB `Xz`/`XZ` with selector one. `AiNativePaintAssignment.namedColor` retains component alternatives, raw name bytes and the native tint operand. Tint is not opacity; AiKit neither inverts it nor converts components between profiles.

`AiNativePaintChange.namedColor` changes those literal components/tints in qualified active or simple appearances, retaining the source representation and ink name. Selected/shared use isolation and complete printing synchronization follow the same contract as process paints. This is broader named-paint editing, not a document-wide ink redefinition: unrelated same-name paints, ATE named colors, mesh ink declarations and external color-book records are not rewritten. Ink renaming and unsupported selectors reject.

### Global named-ink alternatives

Ordinary path authoring also accepts literal named channels through
`AiNativePathDefinition.namedFill`/`namedStroke` and the corresponding
`replacePathArtwork` arguments. Each channel is exclusive with its process color.
Creation and replacement serialize the original named-color kind, alternatives,
name bytes and tint operand; outgoing native and printing states are restored for
following artwork. Direct live shapes retain these channels during complete
parameter/artwork replacement. Gradient contours may have a named stroke.
Unpainted private appearance carriers and clipping contours cannot acquire a named
paint implicitly. These fields do not redefine another resource or compose any
printing representation. Hosts may create palette cells separately to retain
unused masters.

`AiNativeAppearancePartDefinition.namedColor` authors each of those five literal
layouts in fill/stroke parts, exclusively with `colors`. Private group path
replacement accepts `AiNativeAppearancePathChange.namedFill`/`namedStroke`, with
the same process-channel exclusivity. The complete printing owner remains
mandatory, and outgoing state is restored for unchanged siblings. Named mask
paths use the existing complete path definitions in the host-supplied Art tree.

`AiNativeInks.decode(records:)` groups exact byte-name references in literal
fill/stroke paints, native style trees, palette cells, qualified opacity-mask Art,
authoritative/compatibility
gradient stops and mesh Separation/NChannel declarations. A palette's display
label remains independent of the ink identity. The inventory is not permission to
edit opaque same-name references.

`redefine(ink:, cmyk:, rgb:, gray:, ramps:, artwork:)` changes every qualified
alternative of one ink atomically. Supply the device alternatives required by the
source; AiKit does not convert between them. Original ink names, tint operands,
mesh tint order, geometry, object identities and unrelated ink values remain
intact. Literal `CMYKCustomColor`/`RGBCustomColor` DSC declarations and continuation
lines are synchronized without changing the document's ink-name list.

Each affected gradient name requires one current definition key and freshly
composed ramps; all its counted banks and both stop copies are updated together.
Duplicate banks must agree on authoritative stops. Every complete appearance pair
requires one host-supplied printing replacement using `printingOwners` handles;
nested applications share their outer pair. Unchanged expansions may supply their
original bytes. These complete inputs prevent forgotten resource-driven printing
caches; their visual equivalence and the matching PDF remain host responsibilities.

Whole-source dependency qualification and same-name reference coverage precede the
transaction. Unknown references, populated text-engine dependencies, unsupported
mesh metadata, conditional owners, missing device alternatives or incomplete
printing/ramps reject without changing the source. Changed symbol artwork and
referenced brush artwork also reject until their instance caches can be replaced;
ink dependencies propagate through pattern/style references under an explicit work
limit. Color-book payloads, ATE named colors and ink renaming need further typed
contracts. Global operations are reported as requiring validation, never
universally available.

### Palette color and gradient cells

`AiNativeSwatches.decode(records:)` exposes palettes, authored groups and source-owned `AiNativeSwatch` cells, including display-name bytes, process alternatives, named paints and gradient applications. Unsupported cell commands remain inspectable. Native palette display labels are distinct from named-ink identities and gradient resource names.

`createProcess`, `createNamed` and `createGradient` insert a literal cell into a selected palette; the first palette can be created in an explicit setup. `before` inserts within an existing cell's group; otherwise creation appends to the final group. RGB can retain an explicit CMYK alternative. Gradient cells require a current resource handle; a new named cell also requires an unused ink identity to avoid implicitly redefining existing applications. Display-name collisions, stale handles and ambiguous palette selection reject.

`remove(swatches:)` deletes complete selected cells without changing groups or applied artwork. Referenced named inks reject, including uncertain same-name literal references elsewhere; the host must first resolve their applications. Removing a gradient cell does not delete its global definition, but can make that resource eligible for separate removal. Saved conditional palette branches and opaque reference owners are preserved and excluded from lifecycle edits. This cell model requires explicit `Pc` boundaries; legacy implicit terminators require separate ownership qualification.

The offline regressions include native/PDF save and reopen checks. `tool/check_native_colors.dart` and `tool/verify_native_colors.py --reference <pinned-extension-ai>` independently verify four complete AI saves, both stop copies, exact application bindings, named alternatives/tints, palettes and bank deletion. This is structural acceptance, not Adobe reopen/render certification.

### Relative gradient placement

`setLiveShapeGradientPlacement` updates relative parameters and printing geometry for a named gradient in selected qualified CC live shapes. It retains paths, shape parameters, colors, ramps, unselected styles and the accumulated object transform. Source relative/printing geometry must agree before editing.

Angles use degrees in −360..360; length and aspect ratio must be positive. Linear gradients require `originY: 0` and `aspectRatio: 1`: x origin and length are fractions of the shape's extent along the selected angle. Radial origins are measured from the center in fractions of width/height, with positive y down. Their radius is `length * sqrt((width * (originX - 0.5))² + (height * (originY - 0.5))²) / sqrt(2)`, before angle, aspect and retained object transform. Degenerate results reject.

The operation requires the qualified CC clipped layout, resolved stroke state and consistent strip/cap coverage. Arbitrary affine paint changes, legacy placement layouts, plain-path selections and unresolved appearance graphs remain unsupported. Color management, ramp composition and PDF generation belong to the host; native gradient resource modeling and serialization belong to AiKit.

## Mesh data

`AiNativeMeshes.decode(records:, bodyOnly:)` reads `/Mesh X!` packets through `/End X!`. The default includes resources; `bodyOnly: true` restricts the inventory to the drawing body. The supported schema is version 2, Cartesian topology. Other versions/topologies reject typed decoding while the source stays intact.

Each mesh retains index axes, patches, source fields and cyclic node order, including `/N` corners, `/A` anchors and `/S` subdivision points. Positions, source-order handles, weights, opacity, unknown fields and intermediate nodes are preserved. Patch coverage and ranges are checked without allocating from an unchecked grid-size product. Unknown color spaces retain their declarations. Known gray/RGB/CMYK arities and normalized components are validated.

Separation/NChannel `inks` preserve lexical declaration order and device alternatives. Corner `inkTints` pairs tints in component order, which reverses lexical ink order for NChannel. It does not convert spot inks to process colors. `mesh.vertices` groups each logical vertex's one, two or four corner occurrences; duplicated positions must agree exactly. Handles remain distinct.

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

`paintVertices` updates every selected corner occurrence atomically. It accepts process color, named-ink `tints`, opacity, or compatible combinations; `color` and `tints` are mutually exclusive. Tint edits require matching ordered inks and alternatives across all copies. Color switches stay local; unselected geometry, weights, colors and declarations remain intact.

`editGeometry(mesh:, changes:, bounds:)` changes explicit node positions, first/second
native handles and weights. Every occurrence of a moved shared corner must agree
in the resulting transaction. Handles are not welded automatically. Intermediate
anchors/subdivision points retain their separate seven-value layout. Numeric
edits leave other tokens, color declarations, opacity and patch parameters intact.
`transform(mesh:, transform:, bounds:)` maps every position and control point
through one nonsingular affine basis while retaining weights and paint. Distinct
source points cannot silently collapse through floating-point rounding.
Transforms and full replacements require an explicit host `rotationRadians` when
the source has `BBAccumRotation`; they cannot silently retain a stale frame angle.
Local node edits retain the frame orientation unless a separate transform changes it.

`replaceTopology(mesh:, definition:, bounds:)` accepts a complete
`AiNativeMeshDefinition`: dimensions, uniquely indexed cells, cyclic nodes, colors,
opacity and explicit weights. Four colored corners per cell and exact shared
positions are required. `AiNativeMeshPatchDefinition.nativeParameters` carries an
explicit numeric `/R` array, or null to omit it. AiKit does not assign an assumed
rotation or subdivision meaning to those values. `fromSource` constructors retain
qualified node data and named inks without converting their tints. Unknown fields,
reference-valued parameters and ambiguous parameter ownership reject replacement.

`drawing.meshArtwork` exposes complete independently owned packets with their
optional terminator, name and identity. `createMeshArtwork` inserts an explicit
`AiNativeMeshArtworkDefinition` into a qualified root, group or layer, even when the
document has no existing mesh. `replaceMeshArtwork` changes geometry/topology and
ordinary object flags while retaining metadata. `transparency` accepts the complete
native blend/opacity/isolation/knockout/alpha-is-shape tuple independently of corner
opacity; leave the normal `opacity` shorthand at its default when supplying it.
`duplicateMeshArtwork` requires
fresh identities for existing identified owners. Complete mesh handles participate
in mixed layer reorder/move/removal, containing group/layer copies and artboard
transactions. Native and printing scalar state are restored independently; mesh
field declarations never become surrounding path paint assignments. These APIs
do not certify a particular host's interpretation of the mesh surface.

Editing is limited to direct printable body meshes with independent appearance
ownership. Resource/private copies, unresolved parent/object dependencies, unknown
mesh fields and incompatible color declarations reject edits. Lifecycle handles
also exclude attached appearance bindings and clipped/compound parents. Callers
supply complete ink bounds and regenerate the synchronized PDF/previews.
Interpolation, tessellation and color management remain application responsibilities.
The new geometry, topology and lifecycle regressions are written but their
execution is deferred to the final validation campaign.

## Ordinary group visibility and locking

`updateGroupAttributes(group:, hidden:, locked:)` changes only flags consumed by
an ordinary group's opening `u` command. Null arguments retain their source value.
Assignments restore both native and printable state immediately after the opening,
so existing child attributes, image/mesh alpha and following artwork remain exact.
Repeated equal assignments are no-ops. `createGroup(hidden:, locked:)` can supply
the same explicit flags for a new empty group while retaining the existing
`inheritParentFlags` acknowledgement for inherited ancestry/current flags.

These operations do not distribute group blending to children. Whole-group
opacity, blending and masks belong to the appearance contract. Private, clipped,
compound, conditional or applied-appearance groups and unknown required incoming
state reject. The host recomposes the PDF when visibility changes. Display names
remain available through `renameObjects` without changing source identities.

## Ordinary image attributes and mixed lifecycle

`AiNativeRasters.updateAttributes` and `AiNativePlacements.updateAttributes` change
object transparency, visibility, full locking, overprint and literal names on
owned ordinary images. `opacity` changes only that scalar, retaining other native
and printing flags independently. `transparency` instead replaces all five flags
in both representations; supplying both arguments rejects. Distinct incoming
native and printing states are restored afterwards. Names retain explicit String/UnicodeString
encoding. Pixel planes, preview rows, file paths, XML identities and sample caches
remain unchanged by attribute-only edits.

`AiNativeLayers.rasters` and `placements` expose exact snapshot handles accepted
by `reorderArtwork`, `moveArtwork` and `removeArtwork`, together with ordinary
paths, complete groups and layers. Ordinary `AiNativeGroup` handles participate in
mixed sibling ordering and removal, including nested groups and retained image,
link, gradient and mesh children. `moveArtwork(group:)` appends into a qualified
ordinary group; `parent:` remains the layer destination, and supplying both rejects.
Group/layer/root moves retain native identities and independent native/printing
boundary states. Changing group depth or inherited flags requires the existing
`inheritParentFlags` acknowledgement. Native layers cannot be group children.
Clipped, compound, private, conditional and applied-appearance group parents retain
their separate contracts. Transactions require complete unconditional owners,
qualified ancestors, explicit scalar dependencies and inspected references.
Deletion removes unused DocumentFiles references after complete owner removal;
shared references survive. Unknown metadata or clipped/private ownership rejects.

`AiNativeDrawing.copyRaster` copies native sample bytes, bit depth, channels and
qualified metadata under a required fresh artwork identity and fresh sample UUIDs.
`copyPlacement` retains exact preview rows and external reference bytes under a
fresh artwork identity. Both accept explicit placement/attributes and qualified
root/group/layer destinations. Cross-document copies require the host to rebase
relative paths. Generic subtree copying of image-bearing owners still rejects;
hosts can author destination layers and copy their qualified children explicitly.
These extensions are implemented with regression cases pending the final combined
validation campaign; they do not establish Adobe application acceptance.

## Native image creation

`AiNativeDrawing.createRaster(definition:, parent:, layer:)` inserts a complete
`AiNativeRasterDefinition` into an ordinary group, layer or the global drawing.
It writes bounded process samples, optional straight alpha, both placement
matrices, fresh sample UUIDs and optional fresh XML identity/name. Stencils require
an explicit process color. `AiNativeImageAttributes` supplies lock, visibility,
normal opacity or complete `transparency`, and overprint. Keep `opacity` at its
default when supplying the complete tuple. This also applies to `copyRaster` and
`copyPlacement`; creation and copying never multiply sample alpha by object
opacity. Placement bounds expand without moving artboards.

`createPlacement` accepts `AiNativePlacementDefinition` with encoded path bytes,
a local downward-y rectangle, affine matrix, optional relative directory and
host-provided eight-bit RGB/alpha preview. It creates file-type-one CC placement
syntax and updates DocumentFiles declarations atomically. Paths are never opened.
The created link remains compatible with relink, placement and embedding APIs;
shared file references survive embedding or relinking another user.

Both operations append within the explicitly selected parent and preserve existing
owners. Qualified image metadata and binary payloads establish independent object
boundaries, allowing subsequent images and ordinary paths in the same paint order.
Native and printing scalar states are restored independently. Unknown incoming
attributes, conditional parents, private printing expansions, unqualified metadata,
identity collisions, nonportable geometry and aggregate resource overruns reject.
Creation does not attach an image to an existing opacity mask or appearance tree.
The host still supplies the matching PDF and resolves actual linked pixels.

The drawing reader retains qualified relative-directory strings as metadata, not
operands of the following placement terminator. Two complete synthetic saves are
checked independently for native samples/preview/placement, updated file references,
PDF image/alpha resources and exact Poppler pixels. This is not Illustrator acceptance.

## Embedded raster images

`AiNativeRasters.decode(records:, bodyOnly:)` reads binary `XI` images in setup, body and private records. Samples are interleaved process colors followed by a separate alpha plane, with packed row padding preserved. Supported component depths are 1, 2, 4, 8 and 16 bits; 16-bit samples are big-endian. Width/height, bounds, producer flags, source spans and both `XI`/`Xh` matrices remain explicit. No profile conversion is performed.

Binary boundaries come from validated image geometry, including alpha, before checking the exact DSC terminator. Recognized count variants are accepted only when that boundary matches. Sample bytes remain opaque even if they contain PostScript tokens or fake end markers. Corrupt/transcoded data is not repaired by searching for a later marker.

`AiNativeRasters.validateSourceLayout(image:)` qualifies an exact owned handle's
complete raster framing, process layout and literal object metadata without
changing samples. Unknown cache fields and annotations reject. This checks the
image itself; the host must also qualify its enclosing appearance, ownership and
native/printing state. Ordinary contour edits can retain these qualified image
neighbors byte-for-byte, including their metadata. This does not qualify image
removal or arbitrary mixed-subtree lifecycle.

Focale now projects qualified embedded process images to a bounded RGBA8 display
source while retaining the original native samples. Unchanged pixels preserve
their source space, depth, row padding and cache identities through placement
edits. Newly composed or replaced pixels use host RGB8 with optional alpha; the
native placement accounts for changes in sample resolution. Source-backed image
attribute/lifecycle changes, linked images, broader appearances and image-bearing
page transactions remain separate integration work.

| Operation | Behavior |
| --- | --- |
| `translate` | Updates both native matrices, retaining samples and metadata. |
| `replacePixels` | Writes host-supplied `AiNativeRasterSamples`; adjusts dimensions, flags and matrices to retain the placed extent when resolution changes. |
| `setPlacement` | Writes a host-supplied affine matrix and explicit frame-angle policy without resampling. |

Replacement samples must contain complete rows. Changed planes/layouts renew existing sample UUIDs while stable object identities and unrelated images remain unchanged. Absent UUID fields stay absent. A retained source link is marked as modified. Legacy stencil layouts can retain/replace pixels but do not acquire invented alpha fields; alpha authoring requires qualified extended headers.

For `[a, b, c, d, tx, ty]`, embedded pixels map to `(a*x - c*y + tx, b*x - d*y + ty)`. `rotationRadians` separately controls the editing-frame angle: a finite value updates/adds it; null preserves absence and rejects an existing field. It cannot be inferred uniquely from the matrix. Unknown cache/relationship fields, including unresolved mask/shear metadata, reject geometry edits. Enclosing clips, effects, groups, resources and artboards are separate dependencies. The host supplies matching appearances after edits.

## Linked placements and previews

`AiNativePlacements.decode` reads CC placement sections, retaining raw path bytes, relative directory, local bounds, affine matrix, file type, extensions, preview and object dictionary. Preview byte boundaries are checked from their headers; unknown bounded pixel layouts stay preserved. `preview.toSamples()` explicitly converts qualified format-17 straight ARGB into RGB and separate alpha. It never silently substitutes that preview for the full-resolution linked resource.

Qualified raster edits require file type 1, extensions `4 4 0`, consistent paths and `IncludeFile` references, known versioned metadata and a nonsingular matrix. The kit never opens files, resolves URLs or selects image decoders.

| Operation | Behavior |
| --- | --- |
| `translate` / `setPlacement` | Changes geometry while retaining link paths, preview data and local bounds. |
| `embed(object:, samples:)` | Replaces a link with host-decoded native raster samples while retaining placed extent and qualified metadata. |
| `relink(object:, pathBytes:, relativeDirectoryBytes:, preview:)` | Updates path operands, declarations, relative directory and explicitly supplied or removed preview. |

Embedding removes an old file dependency only when no other native reference uses it. Relinking uses caller-selected path bytes and escapes native strings; ambiguous/control-containing paths and unresolved metadata reject. Null relative directory or preview arguments explicitly remove those records. New previews use qualified 8-bit RGB with optional alpha. Neither operation resamples pixels or changes catalog XMP automatically.

Linked matrices map local coordinates to `(a*x + c*y + tx, b*x + d*y + ty)`; the local y axis points down. `rasterMatrix(width:, height:)` exposes the corresponding pixel-to-native transform; `validateRasterLayout()` checks the qualified layout independently. Frame-angle policy matches embedded rasters. External PDF/EPS artwork, older `XF` links and dependent effect caches remain unsupported for these edits.

## Catalog metadata

`AiXmpMetadata.fromPdf(document:)` reads catalog XMP; `parse(source:)` reads a standalone UTF-8 packet. `resources` exposes current-document `xmpMM:Manifest` and `xmpMM:Ingredients` references using namespace URIs. History, pantry, `DerivedFrom`, other subjects and page/image metadata remain separate.

`relink(resources:, filePath:, documentId:, instanceId:)` updates explicitly selected references, removes stale identifiers when null and clears alternate paths. Native placement identity is not inferred from inventory order or equal filenames. Managed, extended or part-specific references reject edits; unrelated packet text, comments, namespaces, padding and metadata remain exact.

After the native/PDF save, `writeTo(document:)` installs the changed catalog packet without changing shared original page/image packets. Old unreferenced objects remain, so this is not redaction. PostScript-embedded XMP is not currently read or rewritten by these APIs. XML limits apply before tree construction; DTDs, undefined entities, non-UTF-8 declarations and ambiguous structures reject.

## Inspecting legacy files

`AiArtworkPath`, `AiColor` and `AiColorSpace` are immutable inputs for editing native paths in existing documents. Standalone AI7 document creation is outside the package contract. Existing legacy files retain bounded inspection and exact byte preservation.

Legacy DSC inspection retains comments and continuations, resolves `(atend)` metadata and prefers high-resolution bounds. Declared data and embedded documents are skipped. DOS EPS section/preview ranges are checked and the entire envelope is retained. Raster/placement previews use the same bounded binary readers as native inspection.

`AiPostScriptDocument.dscIssue` reports a damaged or unsupported native binary boundary with its offset relative to `postScriptBytes`. Only earlier comments are exposed; later bytes are not searched for plausible metadata. Exact source encoding remains possible. A null issue means inspection reached the end, not that the document is executable or completely editable.

`AiPostScript.tokenize` exposes immutable source spans and Latin-1 lexemes for numbers, names, strings, arrays, dictionaries, procedures, comments and protected data blocks. It does not execute operators. Procedure braces must balance; array/dictionary delimiters can cross procedure boundaries. Dynamic PostScript and binary-token execution are outside the package contract.

## Supported data

“Editable subset” means the named operations can serialize qualified native changes. “Preserved” means retained source, not semantic editing support. None of these statuses implies complete Illustrator compatibility.

| Feature | Read | Write/edit | Main boundary |
| --- | --- | --- | --- |
| PDF-backed AI and legacy containers | Yes | Yes | PDF graphs are rewritten; unchanged legacy bytes remain exact. |
| Plain/zlib/Zstandard native programs | Yes | Yes | Original compression and shared ownership retained. |
| Layers, paths, groups and attached metadata | Yes | Editable subset | Qualified state/references; fresh copied IDs and explicit parent inheritance. |
| Compound paths and clipping | Qualified topology | Editable subset | Explicit mask ownership and compound appearance; no Boolean geometry engine. |
| Records, settings and artboards | Yes | Editable subset | Explicit crop, print and PDF-page policies; known retained dependencies. |
| Source identities and version alternatives | Yes | Preserved by qualified edits | No target-version conversion or unknown plug-in reference resolution. |
| Ordered appearances | Named trees and literal settings | Editable subset | Complete affected-user coverage and host-supplied printing groups. |
| CC live shapes | Five qualified families, including irregular-polygon parallelograms | Similarities, qualified affine changes, host-supplied parameter/contour transactions and complete-pair lifecycle | Host owns regeneration and printing; arbitrary effects and positional dependencies remain excluded. |
| ATE text, fonts, runs and frames | Named CS / compact CC | Editable subset and supplied layouts | Host composition; unresolved caches/shared dependencies reject. |
| Gradients and palettes | Qualified resources, instances and cells | Creation/removal, ordered hard stops, exact application rebinding, named paints, focus and CC placement | Host ramps/printing; opaque references, ATE/color-book ink redefinition and unsupported caches remain excluded. |
| Cartesian version-2 meshes | Yes | Paint, geometry, explicit topology and direct object lifecycle | New geometry/lifecycle validation pending; no tessellation. |
| Embedded rasters and linked previews | Qualified layouts | Samples, affine placement, relink and embed | Host pixels/decoders; unresolved dependent caches reject. |
| Setup pattern/symbol/brush artwork | Source-owned inventory | Qualified appearance transactions | Complete transitive dependencies; general instances remain incomplete. |
| Catalog XMP | Qualified references | Explicit selected-reference changes | No inferred native/XMP identity mapping. |
| New AI documents | CC version 24 | Initial boards, layers, paths, text resources and images; host PDF packaging | Focale integration and Adobe acceptance remain open; standalone AI7 creation is excluded. |
| Other effects, resources and plug-ins | Source preserved where parsing permits | No general semantic writer | Recognition does not qualify dependent edits. |

Unknown records and unsupported layouts are retained when safe; edits reject dependencies they cannot update coherently. Consult the relevant API's Dartdoc for exact arguments and guards, and [the host contract](HOST.md) for derived-representation responsibilities.

## Safety and platform behavior

AiKit has no Flutter or native rendering dependency. File access, resource resolution, interactive tools and persistence belong to the application. Parsers and edits use immutable snapshots and explicit resource limits:

| Policy | Default ceilings |
| --- | --- |
| `AiLimits.pdf` | PdfCore policy, including a 128 MiB file ceiling and depth 128. |
| DSC comments | 1 MiB per continued comment; 100,000 retained comments. |
| `AiNativeLimits` | 128 MiB aggregate encoded/filtered envelopes and decoded programs; 32 MiB Zstandard window; 1,000,000 tokens; depth 128. |
| Standalone tokenization | 128 MiB, 1,000,000 tokens, depth 128. |
| Shared text-engine parsing | 128 MiB, 1,000,000 values, depth 64, 64 MiB per decoded string. |
| `AiXmpLimits` | 8 MiB UTF-8 packet, 100,000 nodes/events including attributes, depth 64. |

Limits are checked before relevant allocation/output growth; they are not a whole-process memory cap. Malformed structures raise `FormatException`; invalid arguments or foreign handles raise `ArgumentError`; unqualified semantic operations use `UnsupportedError`. Unknown containers are rejected, not treated as arbitrary raw AI. An edit's rejection leaves the original snapshot intact.

## Corpus validation and compatibility

Run the package's offline checks with `dart analyze`, `dart test` and `dart test --platform node`. The [external corpus guide](../test/corpus/README.md) contains the required generators, pinned fixture manifests and independent verification commands. Downloads and generated artwork remain ignored and excluded from publication; provenance and licensing stay in the manifests.

Validation distinguishes native extraction, unchanged preservation, semantic edits and save/reopen behavior. Independent readers check source records and unselected data; external SVG rendering can additionally check qualified native geometry without adding a renderer to AiKit. Host-supplied PDF/native save tests check that both representations survive; they cannot prove visual equivalence.

Adobe Illustrator reopening and native Focale integration remain unqualified.

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

### Direct live-shape authoring

`AiNativeDrawing.createLiveShape` creates one ordinary painted contour and attaches
a complete `AiNativeShapeParameters` dictionary. `setPathLiveShape` promotes an
existing qualified ordinary contour, retaining its original name, identity and
other admitted literal metadata. The caller supplies the canvas-relative center,
all dimensions/angles, contour, ink bounds and synchronized PDF. Line handlers
require open contours; rectangle/ellipse/polygon/star handlers require closed
contours. The package never generates or certifies shape geometry from parameters.

`replaceDirectLiveShape` replaces typed parameters, contour and complete process
appearance together. The path definition must omit name and identity; both remain
source-owned. Existing frame rotation requires an explicit resulting angle. Sharp
rectangle-to-irregular-four-sided-polygon conversion uses the same explicit family
transition as `replaceLiveShapes`. Separate CC printing expansions, alternatives
and unknown handlers reject here and retain their existing dedicated contracts.

Complete direct scalar shape dictionaries, mesh owners and gradient owners may be
retained while initializing or editing the independent native text namespace.
Unknown references and incomplete owners still reject. The added authoring and
Focale integration regressions await the requested final validation phase.

### Literal native artwork names and center display

`AiNativeDrawing.renameObjects(names:)` edits display-name bytes on qualified
current path/group handles, including direct live shapes. It replaces all existing
`AIArtName`/`Object name` aliases while retaining their scalar types, or adds one
private `AIArtName` field when absent. XML identity, geometry, paint and other
metadata remain source-owned. Empty selections, stale handles, invalid bytes,
opaque selected metadata and output-limit violations reject atomically. Since
this is nonvisual metadata, the existing matching PDF may be retained.

`replacePathArtwork` and `replaceDirectLiveShape` retain the source `Ap` center-point
display setting, including separate public/private assignments located inside a
replaced counted span. Newly created ordinary paths keep their explicit default.
This flag controls Illustrator's center marker, not fill/stroke rendering. Focale
now admits both defined values instead of rejecting the visible-center variant.

The host's circular corner bridge uses effective fitted rectangle radii and
converts polygon/star tangent setbacks to actual circle radii. Native rectangle
corner ordering and initial quadrant, native polygon rotation convention, all
cubic controls and native centers are checked together. This interpretation uses
the existing pinned Inkscape AI reference format notes and corpus; regressions and the independent export verifier are included in the final
local integration validation. No Illustrator exchange result is implied.

Newly authored linked preview blocks include an explicit empty
`%AI17_Alternate_Content` branch, keeping following artwork visible to readers
that expect both version branches. Existing qualified blocks without that empty
branch remain readable and editable; their bytes are preserved when unchanged.
