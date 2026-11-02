# Native compatibility status

AiKit implements bounded Illustrator data inspection, source-preserving native
editing and serialization. Rendering, composition and tools belong to the host;
Focale integration is partial and tracked in [its acceptance record](FOCALE_INTEGRATION.md). See [the responsibility split](HOST.md) and the
[detailed format contracts](AI.md).

## Implemented data contracts

- New native version-24 CC documents without an input AI: RGB/CMYK modes, boards,
  nested layers, ordinary paths, fresh host identities and coherent initial
  headers. First-save packaging attaches shared Zstandard blocks and header caches
  to explicitly matched host PDF pages. Subsequent native edits use the existing
  save APIs. Eight complete saves pass independent native/PDF and unchanged host
  pixel checks. Focale now connects an ordinary-path authoring/reopen subset;
  broader export integration and Adobe reopening remain unverified.
- Qualified ordinary CC/CS text story and linked-frame creation, duplication and
  deletion, with compacted references, renewed clone identities and explicit
  composition invalidation. Unknown external owners and appearance dependencies
  reject; this does not qualify all text-bearing Illustrator files.
- Initial compact ATE 7 namespaces in fontless native documents, with explicit
  host fonts, normal styles, frame/story tables, independent undo-free data and
  synchronized declared font headers. Identified ordinary paths and expanded
  layer headers remain intact through subsequent text lifecycle edits.
- Host-supplied printable ATE views for point/area text and an opt-in structural
  complete-save check. Synthetic full-file acceptance uses independent ATE/PDF
  readers; font shaping and Adobe reopen/render acceptance remain unverified.

- PDF/PostScript container detection, immutable snapshots and exact legacy bytes.
- Plain, zlib and Zstandard native envelopes, shared-owner rewriting and saving
  with a host-supplied PDF. Zstandard uses published ZCodec 0.2.6.
- Atomic multi-program saves preserve existing page identities and native graph
  dependencies; stale/foreign sources and implicit page remapping reject.
- Native layers, plain paths, hierarchical records and artboards.
- Complete ordinary path geometry/process-appearance replacement with retained
  names and identities, independent native/printing state restoration, fill/stroke
  lifecycle, scalar opacity, stroke metrics and explicit flags. Focale connects
  this transaction for its qualified ordinary paths and composes the matching PDF;
  broader appearance families remain outside this initial application path.
- First/root/nested ordinary layer, group and path creation without existing
  siblings; qualified removal, copying, reordering and reparenting preserve
  ownership, identities and both state projections. Path creation accepts explicit
  geometry/process paint and host-computed bounds, without generating a PDF.
- Mixed ordinary path/layer ordering and moves to a layer or global root, with
  independent native/printing state and explicit saved-view invalidation. Focale
  connects ordinary path/layer creation, duplication, deletion and reparenting,
  retaining source identities and assigning repeatable fresh identities to new
  objects. Other native object families remain separate.
- Source-owned ruler units, canvas scale and coordinate metadata; artboards retain
  document ownership/order and separate artboard/text ruler origins.
- Independent active-artboard, selection, crop and saved LastArtboardID fields;
  qualified native rectangle resizing with explicit crop/ruler choices, creation,
  removal and reordering. Explicit native/PDF page mappings retain owner metadata
  and synchronize header caches; catalog-governed source pages require declarations
  before removal. Focale connects ordinary CC page lifecycle and rectangle edits,
  including repeated saves with one global drawing; broader families remain open.
- Source identities, ordered record fields, saved artboard/XML artwork identifiers
  and lexical owners. Version alternatives remain separate; qualified style and
  gradient references report missing, ambiguous and conditional ownership.
- Source-local capability reports distinguish typed data, qualified operations,
  opaque preservation, unsupported structures, malformed data and inspection limits.
- Ordered named appearance trees retain multiple fills/strokes, exact part and
  parameter ownership, shared uses, local visibility, qualified stroke alignment
  and literal paint/dash assignments. Qualified active-style and process/named
  SimpleStyle changes synchronize
  selected or shared CC users with host-supplied printing groups, including saved
  alignment labels. Stack/chain child permutations support nested orders and
  simultaneous source setting edits without dropping or reparenting subtrees.
  Explicit replacement children additionally support removal, reparenting,
  original snapshot copies and new process fills/strokes, stacks/chains and
  conduits. Cycles, duplicate retained ownership and edits to removed parts
  reject; new native state must remain safe for following artwork.
  Two complete CC programs qualify selected/shared process-fill, stack-order and fill-creation edits
  with independent native/printing comparisons. Unknown effects remain preserved;
  qualified retained resources and complete palette alternatives remain exact.
  Both branches are inspected without selecting a version. Other user families,
  uncovered resource-local users, populated constraints and unresolved following
  text state remain explicit boundaries.
- Qualified CC live-shape translation, rotation and uniform scaling, including
  dependent printing geometry, gradients and shared-style isolation.
- Nonuniform scale, reflection and shear for qualified ordinary contours and
  representable live shapes, with fixed strokes and host-supplied CC expansions.
  Sharp sheared rectangles become editable irregular-polygon parallelograms.
  Complete typed parameter changes save host-regenerated contours and all native
  metadata copies together; unsupported positional dependencies still reject.
- Host-supplied contours and complete groups for separate, bound CC printing
  expansions. Complete groups allow new path/nesting/paint topology with process
  colors and existing gradients, preserving outgoing state, native authoring data
  and resource definitions. Unknown local dependencies reject.
- ATE fonts, stories, UTF-16 runs and styles; native content/feature editing,
  host-composed layouts and frame translation. PsCore 0.2.2 supplies EngineData.
- Ordinary contour/compound/clip lifecycle keeps qualified gradient neighbors
  and empty ATE 11 main/undo-free snapshots unchanged. Movement proves inherited
  and outgoing state; private/printing shape contours remain protected. Unknown
  dependencies and populated ATE 11 still require separate qualification.
- Counted gradient creation/removal, palette process/named/gradient cell lifecycle,
  ordered hard stops with explicit ramps, and exact appearance-gradient rebinding.
  Selected/shared named paint edits retain their native alternatives, ink names and
  tint semantics. Host-composed printing remains mandatory; cached linear hard-stop
  strip regeneration, global ink redefinition and opaque reference owners retain
  explicit boundaries. Focus and relative placement edits remain available.
- Explicit transparency part creation and existing selected/shared `Xy` edits.
  Existing masks on ordinary body path/group/child appearances expose four flags
  and qualified vector/group/raster artwork. Atomic flag/Art updates require full
  host printing owners; named dependencies, live shapes and resource instances
  still reject. Seven complete AI saves pass independent native/PDF checks, including
  two unchanged producer raster payloads and an active PDF soft mask. Adobe reopening/rendering is unverified.
- Native mesh inventory, process-color/ink-tint/opacity vertex edits with shared
  corner updates; source geometry and unknown data remain preserved.
- Explicit mesh coordinates/handles/weights, affine transforms and complete
  Cartesian topology replacement are implemented, alongside direct creation,
  replacement, duplication and mixed layer/group lifecycle. These additions have
  local regression coverage and an independent source-data oracle. Actual
  Illustrator exchange remains unverified. Unknown fields,
  unresolved appearance bindings and unsupported carriers remain preserved.
- New embedded and linked raster insertion in ordinary roots/groups/layers, with
  explicit placement/state, sample identities, previews and file dependencies.
  Subsequent image/path insertion preserves paint order and both state projections;
  unknown inherited state or appearance-owned parents reject. Two complete saves
  pass independent sample/preview/PDF and matching host pixel checks.
- Embedded raster samples and alpha, replacement pixels, linked placements,
  explicit previews, relinking and affine geometry edits.
- Exact-handle embedded source-layout validation and byte-preserved qualified
  image neighbors during ordinary contour edits. Focale connects initial embedded
  RGB8/alpha authoring, native process-image reopening and subsequent placement
  or pixel replacement; unchanged native sample depth and planes survive. Linked
  image integration and source-backed attributes/lifecycle are now implemented
  with local regression coverage recorded in `FOCALE_INTEGRATION.md`.
- Catalog XMP dependencies and source-preserving resource updates.

## Remaining native work

Extend source-backed models and serialization for unsupported native appearance,
shape, text, mesh, brush, pattern, symbol, effect and plug-in data, starting with
CC files. Each edit needs explicit ownership, preservation and rejection rules.
Extend older formats after the CC contracts are qualified. Arbitrary PostScript
execution, glyph shaping, mesh tessellation and standalone PDF generation are
outside the kit's scope.

## Evidence and limitations

Run VM/Node regression tests and the relevant pinned [corpus checks](../test/corpus/README.md).
Independent readers compare native records, source bytes and edited geometry.
Some native edits also have external SVG rendering checks. Existing PDF/XMP
preservation can be verified with Poppler without rendering native art in AiKit.
The removed native-to-PDF export suites are not current acceptance criteria.

No Adobe Illustrator reopening validation or complete native Focale integration
acceptance has been performed. The ordinary Focale subset has the bounded local
evidence recorded in [FOCALE_INTEGRATION.md](FOCALE_INTEGRATION.md). A PDF view, preserved private record or accepted file does
not establish native editability. Do not infer a compatibility percentage from
fixture or test counts.

### Image integration validation

Ordinary embedded/linked image attribute updates, exact native copies and mixed
layer lifecycle are implemented; linked preview provenance, refresh/incorporation
and Save As path rebasing are connected in Focale. VM/Node and Focale regression cases exercise these changes; independent
readers check complete saves, sample bytes, dependency metadata and PDF pixels.
See [the integration record](FOCALE_INTEGRATION.md) for the final local evidence. Private image appearances and Adobe acceptance remain open.
