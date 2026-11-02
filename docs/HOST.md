# Package and host responsibilities

AiKit follows the PsdKit/Focale split. It is a pure Dart format package, with
immutable source-backed models, bounded parsers, editing operations on those
models and serialization. Host integration is tracked separately in
[the Focale integration record](FOCALE_INTEGRATION.md), which distinguishes
qualified native families, preserved content and unverified interoperability.

| AiKit | Host application |
| --- | --- |
| Decode containers, native programs and metadata. | Map supported native data into its document model. |
| Expose and edit native layers, paths, text, gradients, meshes and images within documented limits. | Provide tools, selection, undo/redo and interactive rendering. |
| Preserve unknown records and reject unsafe edits. | Choose an explicit fallback for unsupported visual semantics. |
| Write supplied printing contours, text layouts, ramps, pixels and previews. | Shape text, compose layouts, manage color and generate derived representations. |
| Package edited native bytes with the supplied compatibility PDF. | Produce a matching PDF from the same edited document snapshot. |

## Creating a new CC document

1. Call `AiNativeDocument.create` with explicit artboard definitions, layer trees,
   ordinary path definitions, title bytes, RGB/CMYK mode and creation timestamp.
   Supply fresh board UUIDs and optional layer/path XML identities. An empty
   document has at least one artboard and one empty layer. No existing AI is needed.
2. Populate additional supported native data through the existing editing APIs.
   For new text, initialize `AiNativeTextDocument.create` with the actual font,
   size, paint and native text ruler origin, then create and compose stories.
   Insert embedded or linked images through `AiNativeDrawing.createRaster` and
   `createPlacement`, with host-decoded process samples, placement and optional
   link previews. Reacquire artboards from the resulting records before binding PDF pages.
3. Produce the compatibility PDF from the same host document revision. Supply
   complete printing representations for native objects that require them.
4. Call `AiNativeDocument.createPdf` with the records, the host PDF, a modification
   timestamp and one `AiNativeDocumentPage` per current artboard/page in matching
   order. Encode its result with `AiCodec` and persist it atomically in the host.

The initial profile is native version 24 with Zstandard private blocks shared by
all pages and a synchronized full header cache. Page dimensions must match their
boards at TrimBox (falling back to CropBox/MediaBox); bleed and nonzero PDF origins
are preserved. The host supplies content transforms. This initial profile requires
unrotated unit-scale pages and native canvas scale one. Other PDF metadata and
resources remain intact; existing Illustrator attachments reject. Reopen/extract
the saved file and use the ordinary replacement APIs for later edits.

See [the runnable example](../example/create_document.dart) and
[the initial-document contract](AI.md#new-native-cc-documents). This makes new
native AI packaging available to a host; it does not integrate Focale's export
command or establish Adobe Illustrator reopening/rendering acceptance.

Focale's embedded-image projection now connects initial creation and later
placement/pixel changes. The host composes RGB8 plus optional alpha from one scene
revision and supplies the matching PDF. Display decoding does not replace retained
native samples during geometry-only edits: original process channels, depth and
cache identities remain unchanged. Source layout validation alone does not qualify
private appearance state. The subsequent linked-image and mixed-lifecycle
implementation connects exact native copies, ordinary attribute changes,
ordering/reparenting/deletion, linked refresh/incorporation and qualified image
retention in page transactions. These changes await the final combined validation.
Linked imports retain saved-preview provenance and never resolve external files
implicitly; refresh supplies full file pixels before incorporation. Relocated
saves require resolved paths and update native file inventories.

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

For ordinary source tree changes, retain stable host-to-native bindings through
every mutation. `AiNativeLayers.reorderArtwork` orders mixed path/layer slots;
`moveArtwork` accepts a layer or global-root destination. Reacquire handles after
each transaction and validate identities and parent associations. Focale's
ordinary projection now connects these methods with path/layer creation and
deletion, supplies repeatable new identities, and composes a matching PDF. Other
native families require their own complete bindings.

For page structure changes, use `AiNativeData.replaceMapped` with explicit
resulting page bindings. Declare original pages governed only by catalog-native
metadata through `catalogPages` before removing them; this never captures pages
with separate native owners. Focale now connects ordinary CC page creation,
duplication, deletion, reordering, renaming and rectangle changes, with one global
drawing, retained board/PDF identities and matching page content. Page backgrounds
become ordinary native paths. Rotated/skewed pages and board-owned artwork needing
unimplemented clipping still reject.

The mapping uses `AiNativePageReplacement` bindings. `AiNativeArtboards.pageReplacement` binds one
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

### Mixed ordinary group hierarchy

Use exact `AiNativeGroup` handles alongside paths, gradients, meshes, images and
links in `AiNativeLayers.reorderArtwork` and `removeArtwork`. These operations also
accept direct children of qualified ordinary groups. `moveArtwork(group:)` moves
an owner into a group; `parent:` selects a layer and omitting both selects the
document root. Supplying both destinations, moving into one's descendants or
placing a native layer under a group rejects. Complete group moves/removals carry
their children, metadata and XML identities; image payloads and linked file
inventories follow the existing mixed-owner preservation rules.

`updateGroupAttributes` and the optional `createGroup(hidden:, locked:)` fields
set the ordinary group's own visibility and locking. Their assignments restore
native/printing state immediately inside the group, retaining each child's
original settings. Names use `renameObjects`; native identities remain intact.

The host explicitly accepts ancestor flag/depth changes through
`inheritParentFlags` and recomposes the matching PDF. This extends the shared
lifecycle contract; it does not turn ordinary `u/U` grouping into a composited
appearance, or qualify clipped/private groups, text engine profiles or opacity
masks. Focale now imports these ordinary groups as nonisolated hierarchy owners and
connects names, visibility, locking, admitted transforms and mixed child lifecycle.
Nonisolated newly authored groups use native `u/U` ownership; the established
isolated layer mapping remains at layer/root destinations. Isolated groups inside
ordinary groups and composited/masked groups require the appearance bridge.
Ordinary grouped text retains its global coordinates and engine namespace; the
host composes its glyphs and full PDF at the same immutable revision.

### Complete image and mesh object blending

`AiNativeImageAttributes.transparency` supplies complete native blending for new
and copied rasters/links. `AiNativeMeshArtworkDefinition.transparency` supplies the
same tuple for mesh creation/replacement. Keep their normal `opacity` shorthand
at its default when supplying a full tuple. Retained image/link
`updateAttributes(transparency:)` replaces all five object flags, whereas
`opacity:` retains the other native/printing flags; supplying both rejects.
The two outgoing state views are restored independently. Object opacity remains
separate from image sample alpha, linked preview alpha and mesh corner opacity.

Focale connects the sixteen native blend modes, opacity, isolation and explicit
knockout on these qualified direct carriers, including creation, retained saves
and lifecycle copies. It rebuilds the compatibility PDF for blending-only edits
and retains original pixels, links and mesh color/alpha data. Inherited knockout,
alpha-is-shape and appearance/mask-owned carriers still require their broader
host contracts. The new image/mesh transparency regressions are prepared and
remain unexecuted until the final validation campaign.

## Derived representations

Keep the native edit and every derived representation tied to the same immutable
document revision. A retained preview is not evidence that it matches an edit.
The following contracts describe the currently qualified subsets:

| Payload | Host input and serialization | Invalidation/preservation policy |
| --- | --- | --- |
| Compatibility PDF | Supply `synchronizedPdf` from the original graph to `replace`/`replaceAll`, or explicit page bindings to `replaceMapped` for structural changes. | Rebuild affected artwork, resources and dependent PDF structures; nonvisual edits may retain them. The kit verifies graph ownership, not visual equivalence. |
| PDF `AIMetaData` header cache | Include the edited header in the replacement native program; the kit copies qualified full/font-filtered headers. | Preserve caches for unchanged native headers; reject divergent or ambiguous profiles when a header changes. Shared selected owners reuse the new stream. |
| Color and gradient resources | `AiNativeGradientResources.create/remove` updates counted banks; ordered equal-position stops retain hard edges and both native/fallback records. `AiNativeSwatches` creates/removes explicit process, named and gradient palette cells. Exact `AiNativePaintChange.gradient` and `.namedColor` work through selected/shared appearance transactions. | Supply ramps, complete printing groups and matching PDF/previews. Regenerate cached linear strips for changed hard-stop positions; a new hard-stop resource can be bound to one matrix-free native paint note while the host supplies ordinary printing contours. Keep tint semantics and alternate color components explicit. Resource deletion requires no remaining applications; lifecycle rejects opaque/populated-text reference owners. Named paint edits retain ink names and do not redefine all document inks. |
| Ordinary process appearances | `replacePathArtwork` accepts complete path geometry, process paints, stroke metrics, opacity shorthand or explicit `AiNativeTransparency`, and flags. It retains source names/identities and restores both outgoing states. | Supply host ink bounds and the matching PDF from the same revision. Unknown required outgoing values and specialized appearance owners reject; this does not edit named styles or gradient resources. |
| Named appearance resources | `createStyle` creates an unused explicit execution tree; `removeStyles` deletes unused definitions after reference qualification. `applyStyle` rebinds exact body applications to an existing style with one complete printing group per owner, including selected private children. | Compose the target style and supply matching printing/PDF data on application. Names cannot capture existing references; opaque dependency scopes block lifecycle. Geometry, identities, masks and unselected applications remain attached. Resource-instance propagation requires its separate contract. |
| Appearance object lifecycle | `createArtwork` inserts one complete supplied native/printing pair into the body, an ordinary group or a current layer. Qualified private path/group/clip and live-shape owners reuse `artworkFor`; child applications resolve existing styles. `removeArtwork` removes complete body owners and their identified mask descendants with qualified references. `duplicateArtwork` adds adjacent complete copies with exact fresh metadata identities and renewed mask raster cache UUIDs. `moveArtwork` reorders or reparents whole pairs while retaining identities/cache IDs and both boundary states; changed layers/group flags/clipping ancestry require explicit `inheritParentAppearance`. | Supply both geometries, actual ink bounds and the matching PDF on creation; supply updated ink bounds/PDF on movement and the updated PDF on removal or copying, including stacking, clipping and blending. Initialize styles first when absent. The kit validates ownership without composing or comparing appearance. Resource-local lifecycle, unsupported parent coordinate rebasing and new complete-appearance copies in Focale remain separate work. |
| Direct gradient fills | `gradientArtwork` qualifies complete single-contour applications and metadata. Create/replace/copy, process-to-gradient conversion, reverse conversion and mixed layer lifecycle retain source identities and independent scalar state. | Supply an existing resource with composed ramps, explicit absolute affine geometry, fallback process paint, ink bounds and matching PDF. Focale connects encoded process intervals with centered midpoints, hard stops and opacity, including new files and retained lifecycle; see the integration record for validation evidence. Gradient strokes, relative cached applications, other interpolation methods and broader appearance owners retain their separate contracts. |
| Affine contours and dynamic shapes | `transformPaths` maps qualified ordinary contours with explicit frame angles. `transformLiveShapes` derives representable parameters, converting sharp sheared rectangles to native irregular polygons. `AiNativeParallelogram` exposes their center/half-edges; `replaceLiveShapes` saves complete typed parameters and contours atomically across native metadata copies. | Supply ink bounds and matching PDF/previews. Every CC pair needs a complete regenerated printing group, with unchanged outgoing state. These affine methods retain stroke widths/dashes. Regenerate geometry for nonuniform rounded shapes, pie/sheared ellipses and nonuniform stars; gradients and unknown positional dependencies reject. Supplied geometry/parameters require host consistency checks. See [the affine contract](AI.md#affine-contours-and-dynamic-shape-parameters). |
| Literal artwork names | `renameObjects` updates existing display-name aliases or adds a direct name to qualified path/shape/group owners. XML identity and source artwork remain exact. | Supply name bytes in the host's chosen encoding. Retain the existing PDF for name-only changes. Unknown selected metadata and private appearance owners retain separate naming contracts. |
| Direct live-shape authoring | `createLiveShape` creates one explicit painted contour and native parameters; `setPathLiveShape` promotes an ordinary contour; `replaceDirectLiveShape` updates a direct shape's parameters and process appearance while retaining name/identity and following state. | Supply canvas-relative parameters, matching host contours, ink bounds, frame direction and PDF. The kit does not derive geometry or certify correspondence. Separate CC expansions retain `replaceLiveShapes`; the Focale direct-family bridge is implemented but awaits final tests and external acceptance. |
| Native printing expansions | `withPrintingContours` retains paint/resource topology; `withPrintingGroups` attaches complete host-composed ordinary groups containing compound/clipping trees with process paints and references to existing gradients. Both target separate, bound CC live-shape expansions. Qualified transforms update bound private/printing records together; gradient edits accept explicit printing ramps. | Retain native authoring data and supply host-computed ink bounds. Complete groups must preserve outgoing state and the source point-count convention. Qualified masks retain effective q/Q scope and explicit h/H W controls; geometry-only replacement and live-shape transforms retain their stricter restrictions. New resources and unresolved local dependencies require their own editing contracts; do not reuse stale expansions after an unsupported edit. |
| Native transparency and opacity masks | Existing `AiNativeTransparency` assignments retain their literal semantics; new blend/fill/stroke parts accept complete explicit transparency. `artworkFor(use:).opacityMasks` binds body path/group/child and authoritative live-shape masks; `artworkDrawing` exposes qualified vector/group/image syntax. `updateOpacityMasks`, `createOpacityMasks` and `deleteOpacityMasks` require one full printing group per owner. | Compose masks and blending in the host, then supply matching complete printing and PDF representations. Flags preserve artwork bytes; new/changed raster payloads require absent or fresh unique cache UUIDs. Creation/deletion require mask artwork without native object identities; live-shape creation requires no alternate metadata. No effective defaults or mask pixels are generated. Printing/alternate mask copies, text/resource-instance masks and named mask dependencies remain outside this transaction. |
| Native appearance edits | `AiNativeAppearances.artworkFor(use:)` binds private contours, qualified private ordinary/compound/clipping groups or live shapes to separate printing groups. `authoring` exposes the native owner; nullable `path`/`group` getters distinguish it, and `metadata` retains outer/nested dictionaries. `nestedUses` exposes private named child applications; `authoringFor(use:)` resolves their exact native path/group. Select them explicitly through `AiNativeAppearanceReplacement.uses`, with one complete printing group per enclosing owner. Supply `AiNativeAppearanceReplacement` through `artwork` to `updateSelected`/`updateShared`; `printing` retains the live-shape shorthand. | Supply matching groups and complete ink bounds with native paint/part edits. Shared edits require every user and full reference scope. Native contours, group topology and metadata stay exact; changed state may not leak into following artwork. Only explicit selected uses are rebound; retained children do not count as shared coverage. Nested literal styles share their enclosing printing owner. Per-use dependency checks and any private scalar restoration protect unselected siblings inside that owner. `groupContours` exposes private masks and their effective clip owners for host composition. Resource-local pairs expose their exact `resource` and original global style handles. Resource changes require qualified whole-source references and `dependents` for every affected pattern-style application, including transitive resource owners and nested uses sharing one printing group. Secondary replacements retain their native styles and names. Resource-local bounds do not enlarge document bounds or alter pattern rectangles; each resource must retain outgoing state. Unreferenced qualified symbol/brush artwork can be edited; connected brush descriptors, direct pattern consumers without printing ownership and unknown instance links still reject. See the [resource transaction contract](AI.md#native-artwork-resource-ownership). Qualified clipping trees retain exact mask geometry and scoped contour state; opacity-mask resources and unknown inner data remain separate contracts. Where required, the kit restores provable original scalar state with private commands; missing or divergent values still reject. Version-one dash-adjustment flags can be saved or authored explicitly; the host computes adjusted dash geometry. The kit validates ownership and state without rendering the result. |
| Text composition | Supply `withTextLayout` frame/line/segment positions in the documented native coordinate space. | Content/feature edits, including qualified process paints, overprint, stroke settings and paint flags, clear known caches only for the edited story. Text colors require explicit host components without profile conversion; paint enablement and visibility remain independent. `withoutTextLayout(story:)` also clears them after external dependency changes, preserving text/styles/frames. Recompose before saving; unknown view fields reject. |
| Typed glyph composition | Supply `withGlyphLayout` and actual `AiNativeTextGlyphLayout` records for compact CC point/area frames. Each segment represents one source shaping cluster. | Keep actual font handles, IDs and individual origins; provide a real space glyph for each native CR. One-to-many and many-to-one maps are explicit; many-to-many maps and inserted characters use the raw composed-view contract. Bounds and all matching PDF contours come from the same host composition. |
| Text lifecycle and complete-save checks | Create/copy/remove stories and linked frames through `AiNativeTextLifecycle`; attach actual host-composed glyph views with `withComposedText`, then call `validateTextForSave` before packaging with the matching PDF. | Qualified ordinary CC/CS text references and frame display lists update together. Flow edits clear composition; copied resources receive fresh identities. Affected raw-story cache identifiers are removed. Unknown owners, effects and opaque dependent caches reject. Validation checks structure and coverage, not glyph correctness or native/PDF visual equivalence. See the [text lifecycle contract](AI.md#text-and-frame-lifecycle). |
| Embedded image samples | Supply complete `AiNativeRasterSamples` through the raster editor or placement embedding operation. | Qualified replacements renew affected sample identities. Unknown dependent caches reject; the kit does not decode a replacement file or convert its profile. |
| Linked-object preview | Supply explicit RGB/alpha samples to `relink`; retain the path/directory values to refresh only the preview's meaning. | Explicit `preview: null` removes the preview. Geometry edits may retain unchanged preview pixels. Unsupported layouts/dependencies reject. |
| Native thumbnail blocks | No replacement-image writer is currently qualified. | Saving a selected program drops its old leading thumbnail blocks; unselected programs keep theirs. |
| PDF page thumbnails | The host supplies or removes `/Thumb` in its PDF graph, using PdfCore page attributes/resources. | The kit retains the supplied graph; it cannot infer which pages changed visually from native owner indices. |
| Unknown derived payloads | Preserve opaque bytes while their dependencies remain unchanged. | Do not modify a dependency until its attachment/update or invalidation contract is qualified. |

Cache invalidation is an intermediate editing state. It does not certify an
Illustrator-ready save, and packaging complete native bytes is not a substitute
for a qualified dependency update. Attachment contracts for further object families
and unresolved cache relationships remain outside the qualified contracts above.

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

## Complete appearances and masks in Focale

`AiDocumentAdapter.composeAppearance` captures qualified groups and objects through
Focale's existing compositor, with bounded memory/pixel admission and resource
release on every exit. Root opacity/blend remains separate from the straight
RGB/alpha samples. `AiComposedAppearance.replacementFor` supplies those samples to
`AiNativeAppearanceReplacement.raster`, retaining source-proven outgoing state.
AiKit serializes the supplied result; it does not derive or compare appearance.

Retained group/path edits bind exact authoring routes after each mutation. Geometry,
process paints, blends, clipping and opacity-mask changes share a complete-owner
capture and the same PDF revision. `renameArtworkObjects` permits name-only saves
without recomposing either representation. Native identity, styles and mask data
remain attached. Nonuniform stroked transforms and overprint composition need
explicit expanded/separation-aware contracts.

`AiNativeOpacityMask.encodeVectorArtwork` supplies native process paths/groups,
line metrics, opacity and labels. `authoringForMask` resolves each exact path/group
carrier. Focale connects creation, removal, content and settings edits, including
empty and clipped masks, inverted/disabled masks and linked or stationary placement.
Its PDF synchronization uses the ordinary export mask preparation, so these flags
are applied consistently. Additional mask content families, named references and
non-neutral density/feather remain bounded by their own contracts.

Focale's lifecycle ledger treats each complete native/printing pair as one owner
for deletion, stacking and reparenting. Derived printing images and private/mask
children are excluded from ordinary source inventories. Qualified unsupported
native owners can instead be represented by locked printing subtrees; supported
neighbor edits preserve their complete bytes and shared styles. Unknown ownership
or outgoing state retains compatibility fallback. Preserved mixed owners do not
admit topology/page changes or changes to their ancestors.

These profiles have regression and independent-reader evidence recorded in
[FOCALE_INTEGRATION.md](FOCALE_INTEGRATION.md). They do not establish arbitrary
Illustrator execution or an Adobe round trip.

## Scope change

The development renderer APIs `AiNativePdf`, `AiNativePlacementResolver`,
`AiNativeMeshInterpolation`, `AiNativeMeshSurface`, `AiNativeMeshColorResolver`
and `AiNativeMeshes.validateAppearance` have been removed. Native mesh records,
geometry, colors, inks and lifecycle remain in AiKit. Focale owns interpolation,
composition, PDF generation and editing tools. Replace native-to-PDF calls with
the host export path and package its result through `AiNativeData.replace`.
Standalone AI7 document creation remains outside this contract; legacy source
preservation and generic PDF interchange remain available.
