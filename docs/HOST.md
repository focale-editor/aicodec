# Package and host responsibilities

AiKit follows the PsdKit/Focale split. It is a pure Dart format package, with
immutable source-backed models, bounded parsers, editing operations on those
models and serialization. Focale integration is a separate, deferred task.

| AiKit | Host application |
| --- | --- |
| Decode containers, native programs and metadata. | Map supported native data into its document model. |
| Expose and edit native layers, paths, text, gradients, meshes and images within documented limits. | Provide tools, selection, undo/redo and interactive rendering. |
| Preserve unknown records and reject unsafe edits. | Choose an explicit fallback for unsupported visual semantics. |
| Write supplied printing contours, text layouts, ramps, pixels and previews. | Shape text, compose layouts, manage color and generate derived representations. |
| Package edited native bytes with the supplied compatibility PDF. | Produce a matching PDF from the same edited document snapshot. |

## Saving an edited PDF-backed AI

1. Decode with `AiCodec` and extract the relevant `AiNativeSource` with
   `AiNativeData.extract`. Keep the original graph and immutable snapshot.
2. Apply supported native edits. Do not replace editable authoring data with a
   flattened compatibility page or modify only one of several dependent records.
3. Supply matching cached layouts, native previews or printing data required by
   the particular edit. Render the compatibility PDF in the application, deriving
   its graph from the original to retain metadata references and owner mappings.
4. Call `AiNativeData.replace(source:, program:, synchronizedPdf:)`, then encode
   the returned `AiPdfDocument` with `AiCodec`. The kit rewrites all shared native
   owners, preserves compression/private metadata and removes stale thumbnails.
5. The application writes the file atomically and advances its save checkpoint
   only after successful persistence.

For independent native programs in one file, use `AiNativeData.replaceAll` with
`AiNativeReplacement` entries extracted from the same document snapshot. It saves
the batch atomically while retaining unselected programs. Reacquire handles after
every save. The synchronized graph must retain catalog/page identities and order,
the original native-owner dictionaries and every referenced native metadata object.
Copying or importing a newly parsed PDF with matching object numbers is insufficient.
These two APIs reject page additions, removals, reordering and renumbering.
For page structure changes, use `AiNativeData.replaceMapped` with explicit
`AiNativePageReplacement` bindings. `AiNativeArtboards.pageReplacement` binds one
current board to each supplied PDF page and orders them by native board order.
Retained native pages keep their original metadata owner; new native attachments
require an explicit original page/catalog template. The kit preserves catalog
aliases and unselected programs, and rejects incomplete or conflicting mappings.
The host supplies the complete resulting PDF graph, including updated destinations,
annotations, tags and page labels. Removed source page objects retain their native
metadata but must be unreachable. Page labels require replacement/removal after
remapping, or explicit `retainPositions`; native names are not PDF labels.
See the [mapped-save contract](AI.md#explicit-nativepdf-page-mappings) for graph
checks and the exact native lifecycle limits.

`program` contains the edited native bytes; `synchronizedPdf` contains the
host-produced representation of the same edit. AiKit does not render either
representation or prove they look equivalent. Nonvisual edits, such as renaming
a layer, may reuse the existing PDF. Visual edits must not reuse stale artwork.
No native rendering operator whitelist gates this serialization path.

Supply the edited initial native header with the replacement program. The kit
updates existing `AIMetaData` caches matching the original full header or its
observed font-filtered form. It preserves unknown caches when the native header
is unchanged and rejects header changes with unqualified cache layouts. Do not
modify original cache objects in the host graph; selected owners receive new
streams while unselected references retain their original data. See the
[cached-header contract](AI.md#cached-native-headers) for limits and font-profile
ambiguities. This synchronization does not establish a PDF-page mapping.

Native saved print choices are separate from compatibility PDF mappings. Artboard
edits remap qualified stored artboard ranges by identity. If removing every printed
board, provide an explicit replacement selection instead of silently switching to
all. Physical print pages may be tiled; the host supplies their resulting count
and selected indices through `pagePrinting: AiNativePrintSelection(...)` whenever
an edit leaves a nonempty saved physical range. Null selection indices explicitly
mean all and clear that range. This updates existing native settings without
generating print pages or changing unrelated printer choices. See the
[native print contract](AI.md#native-print-selections-during-artboard-edits).

Native artboard edits preserve the global coordinate basis and all retained
artwork. Qualified compact ATE 7/9 main and undo-free snapshots, linked frames,
text ruler origin and typography resources stay byte-exact.
Changing the first board does not move the drawing or infer a new text origin.
Unknown text profiles and unresolved dependency families still require their own
qualification; preserving a resource does not make it editable.
Qualified ordinary compound and clipping groups can also remain exact during an
artboard edit. Their geometry, masks, metadata and child order stay in place;
this does not grant the host independent path/group lifecycle operations on
their members. Text-based and multilayer masks remain unqualified.

## Derived representations

Keep the native edit and every derived representation tied to the same immutable
document revision. A retained preview is not evidence that it matches an edit.
The following contracts describe the currently qualified subsets:

| Payload | Host input and serialization | Invalidation/preservation policy |
| --- | --- | --- |
| Compatibility PDF | Supply `synchronizedPdf` from the original graph to `replace`/`replaceAll`, or explicit page bindings to `replaceMapped` for structural changes. | Rebuild affected artwork, resources and dependent PDF structures; nonvisual edits may retain them. The kit verifies graph ownership, not visual equivalence. |
| PDF `AIMetaData` header cache | Include the edited header in the replacement native program; the kit copies qualified full/font-filtered headers. | Preserve caches for unchanged native headers; reject divergent or ambiguous profiles when a header changes. Shared selected owners reuse the new stream. |
| Native printing expansions | `withPrintingContours` retains paint/resource topology; `withPrintingGroups` attaches complete host-composed ordinary/compound groups with process paints and references to existing gradients. Both target separate, bound CC live-shape expansions. Qualified transforms update bound private/printing records together; gradient edits accept explicit printing ramps. | Retain native authoring data and supply host-computed ink bounds. Complete groups must preserve outgoing state and the source point-count convention. New resources, clipping and unresolved local dependencies require their own editing contracts; do not reuse stale expansions after an unsupported edit. |
| Text composition | Supply `withTextLayout` frame/line/segment positions in the documented native coordinate space. | Content/feature edits clear known caches. `withoutTextLayout(story:)` also clears them after external dependency changes, preserving text/styles/frames. Recompose before saving; unknown view fields reject. |
| Embedded image samples | Supply complete `AiNativeRasterSamples` through the raster editor or placement embedding operation. | Qualified replacements renew affected sample identities. Unknown dependent caches reject; the kit does not decode a replacement file or convert its profile. |
| Linked-object preview | Supply explicit RGB/alpha samples to `relink`; retain the path/directory values to refresh only the preview's meaning. | Explicit `preview: null` removes the preview. Geometry edits may retain unchanged preview pixels. Unsupported layouts/dependencies reject. |
| Native thumbnail blocks | No replacement-image writer is currently qualified. | Saving a selected program drops its old leading thumbnail blocks; unselected programs keep theirs. |
| PDF page thumbnails | The host supplies or removes `/Thumb` in its PDF graph, using PdfCore page attributes/resources. | The kit retains the supplied graph; it cannot infer which pages changed visually from native owner indices. |
| Unknown derived payloads | Preserve opaque bytes while their dependencies remain unchanged. | Do not modify a dependency until its attachment/update or invalidation contract is qualified. |

Cache invalidation is an intermediate editing state. It does not certify an
Illustrator-ready save, and packaging complete native bytes is not a substitute
for a qualified dependency update. Attachment contracts for further object families
and unresolved cache relationships remain tracked in `ROADMAP.md`.

Printing-contour attachment updates derived geometry only. It neither regenerates
shape parameters nor checks that the supplied curves match them. Keep authoring
records, supplied contours and the compatibility PDF on the same document revision.
Existing compound groups and paint commands remain intact. Additional contours
may repeat a self-contained paint operation; wrapped gradient/paint paths require
one contour. CC point counts are updated for every supplied contour, with explicit
closed endpoints. Unknown local state, nested authoring metadata, incomplete ownership
and stale handles reject atomically. Unknown neighboring objects stay unchanged.
The host computes ink bounds including strokes, effects and inherited transforms;
the kit conservatively expands DSC bounds without changing artboards or rendering.

Complete-group attachment may change path counts, nesting and local paints. It
retains the native authoring records and existing resource definitions, and checks
the attributes left after the supplied group. An inherited value absent from the
original group is unknown: the kit neither invents defaults nor inserts resets.
The host must preserve that boundary while composing the new expansion. Existing
gradient references must resolve uniquely and match the supplied instance type.
See [the printing-group contract](AI.md#host-supplied-printing-groups) for qualified
commands and rejection policies. These checks establish serialization safety;
the host still ensures that authoring data, expansion and PDF describe the same edit.

For explicit PDF interchange, `AiPdfDocument.forPdfInterchange` removes stale
Illustrator authoring links. It does not synthesize CC native editing data.
Legacy source preservation and typed AI7 authoring remain separate APIs.

## Scope change

The development APIs `AiNativePdf`, `AiNativePlacementResolver`,
`AiNativeMeshInterpolation`, `AiNativeMeshSurface` and `AiNativeMeshColorResolver`
have been removed, along with their standalone renderer and dedicated tests.
The renderer-only `AiNativeMeshes.validateAppearance` entry point was also
removed; native edits retain their own appearance ownership checks.
Native mesh records, colors, inks and vertex editing remain available.
Replace native-to-PDF calls with the host's export path, then use
`AiNativeData.replace` to package the result. Do not move a rendering engine back
into the kit to make saving possible.

This scope change does not establish complete Illustrator compatibility.
Unsupported records remain preserved or explicitly rejected by edits as documented
in [AI.md](AI.md). Native integration and reopening in Focale, followed by Adobe
Illustrator interoperability checks, require their own later acceptance work.
