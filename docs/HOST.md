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

`program` contains the edited native bytes; `synchronizedPdf` contains the
host-produced representation of the same edit. AiKit does not render either
representation or prove they look equivalent. Nonvisual edits, such as renaming
a layer, may reuse the existing PDF. Visual edits must not reuse stale artwork.
No native rendering operator whitelist gates this serialization path.

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
