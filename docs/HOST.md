# Package and host responsibilities

AiKit follows the PsdKit/Focale split. It is a pure Dart format package, with
immutable source-backed models, bounded parsers, editing operations on those
models and serialization. Focale integration is a separate, deferred task.

| AiKit | Host application |
| --- | --- |
| Decode containers, native programs and metadata. | Map supported native data into its document model. |
| Expose and edit native layers, paths, text, gradients, meshes and images within documented limits. | Provide tools, selection, undo/redo and interactive rendering. |
| Preserve unknown records and reject unsafe edits. | Choose an explicit fallback for unsupported visual semantics. |
| Write supplied text layouts, ramps, pixels and previews. | Shape text, compose layouts, manage color and generate derived representations. |
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
Page/artboard remapping needs a separate qualified structural-edit contract; the
current save API rejects additions, removals, reordering and renumbering.

`program` contains the edited native bytes; `synchronizedPdf` contains the
host-produced representation of the same edit. AiKit does not render either
representation or prove they look equivalent. Nonvisual edits, such as renaming
a layer, may reuse the existing PDF. Visual edits must not reuse stale artwork.
No native rendering operator whitelist gates this serialization path.

## Derived representations

Keep the native edit and every derived representation tied to the same immutable
document revision. A retained preview is not evidence that it matches an edit.
The following contracts describe the currently qualified subsets:

| Payload | Host input and serialization | Invalidation/preservation policy |
| --- | --- | --- |
| Compatibility PDF | Supply `synchronizedPdf` from the original graph to `replace`/`replaceAll`. | Rebuild affected artwork and resources; nonvisual edits may retain them. The kit verifies graph ownership, not visual equivalence. |
| Native printing expansions | Existing qualified shape transforms update their bound private/printing records together; gradient edits accept explicit printing ramps. | General replacement of host-composed printing groups is still unqualified. Do not discard those groups or reuse stale expansions after an unsupported edit. |
| Text composition | Supply `withTextLayout` frame/line/segment positions in the documented native coordinate space. | Content/feature edits clear known caches. `withoutTextLayout(story:)` also clears them after external dependency changes, preserving text/styles/frames. Recompose before saving; unknown view fields reject. |
| Embedded image samples | Supply complete `AiNativeRasterSamples` through the raster editor or placement embedding operation. | Qualified replacements renew affected sample identities. Unknown dependent caches reject; the kit does not decode a replacement file or convert its profile. |
| Linked-object preview | Supply explicit RGB/alpha samples to `relink`; retain the path/directory values to refresh only the preview's meaning. | Explicit `preview: null` removes the preview. Geometry edits may retain unchanged preview pixels. Unsupported layouts/dependencies reject. |
| Native thumbnail blocks | No replacement-image writer is currently qualified. | Saving a selected program drops its old leading thumbnail blocks; unselected programs keep theirs. |
| PDF page thumbnails | The host supplies or removes `/Thumb` in its PDF graph, using PdfCore page attributes/resources. | The kit retains the supplied graph; it cannot infer which pages changed visually from native owner indices. |
| Unknown derived payloads | Preserve opaque bytes while their dependencies remain unchanged. | Do not modify a dependency until its attachment/update or invalidation contract is qualified. |

Cache invalidation is an intermediate editing state. It does not certify an
Illustrator-ready save, and packaging complete native bytes is not a substitute
for a qualified dependency update. General printing-group attachment and other
unresolved cache relationships remain tracked in `ROADMAP.md`.

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
