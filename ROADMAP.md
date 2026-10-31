# AiKit roadmap

This roadmap tracks remaining **Illustrator format data and serialization** work,
starting with recent CC documents and extending older formats afterward.
[docs/AI.md](docs/AI.md) describes the current APIs and limits;
[docs/HOST.md](docs/HOST.md) defines the package/application boundary.

AiKit owns native editable records, immutable edits, preservation and serialization.
Focale owns tools, interactive rendering, text composition, color management and
generation of PDF/previews. Native Focale integration is deferred to a separate
project task. A standalone Illustrator renderer is not a prerequisite for any
milestone below.

## Current baseline

Existing APIs already cover PDF/PostScript containers, plain/zlib/Zstandard native
envelopes, host-supplied PDF packaging, layers, plain paths, hierarchical records,
artboard inspection, qualified live-shape transformations, ATE text edits and
supplied layouts, classic gradients, mesh vertex paint, raster samples, linked
placements and catalog XMP.

These are qualified subsets. General object/resource creation and deletion,
arbitrary appearance editing and creation of a modern CC document from scratch
are not complete. Unknown data is often preserved without being semantically
editable. Native Adobe reopening has not been qualified. No compatibility
percentage is inferred from decoded files or test counts.

## Delivery order

| Milestone | Priority | Depends on | Result |
| --- | --- | --- | --- |
| 1. Save contracts and capability reporting | First | Existing codecs and source snapshots | A dependable boundary for host-supplied representations and explicit unsupported data. |
| 2. Document structure and object lifecycle | CC foundation | 1 | Safe structural edits with consistent ownership and references. |
| 3. Common appearances and geometry | CC core | 2 | Editable fills/strokes, transparency, clips, gradients and live-shape parameters. |
| 4. Text lifecycle and layout serialization | CC core | 2; relevant 3 contracts | More complete native text authoring using host-composed results. |
| 5. Linked and embedded resources | CC core | 2 | Consistent native dependencies, previews and metadata across resource edits. |
| 6. Advanced CC object families | CC extension | 2–3; relevant 4–5 contracts | Incremental mesh, pattern, symbol, brush, blend and effect data support. |
| 7. Modern document creation and version profiles | CC authoring | 1–5 for a declared initial subset | Valid new CC-native documents using supplied compatibility representations. |
| 8. Older Illustrator families | After CC contracts | Reuse qualified 1–7 contracts | Explicit read/edit/write support by older version and feature. |

Interoperability qualification runs through every milestone. Milestones 6 and 7
can advance feature by feature; new-document support need not wait for every
proprietary effect. Start with milestone 1, then establish object ownership in
milestone 2 before widening edits that currently reject unresolved dependencies.

## 1. Save contracts and capability reporting

**Starting point:** extraction, compression, shared-owner replacement and
host-supplied PDF packaging exist. Diagnostics are currently distributed across
`unhandledOperators`, `bindingIssue`, `referenceIssues` and edit rejections.

- [x] Define a coherent capability report separating typed/editable, preserved
  opaque, unsupported and malformed data, with source locations and affected
  owners. An opaque neighboring object must not be presented as editable.
  **Verified:** `AiNativeCapabilityReport` also distinguishes uninspected data
  and operation-specific validation. Eight focused regressions, 287 VM/286 Node
  tests and clean analysis; independent checks recover all 37 pinned sources,
  their PDF owners, 41 layer headers and 181 non-private paths. This qualifies
  the inspection contract, not every reported edit or Adobe reopening.
- [x] Audit and qualify save behavior for several distinct native programs,
  shared catalog/page owners, multiple artboards and PDF page mappings. Explicitly
  reject graph changes that cannot be mapped safely.
  **Verified:** `replaceAll` commits independent programs atomically; both save
  APIs check catalog/page identities and native metadata dependencies. The
  qualified subset preserves existing mappings and rejects remapping. Eight save
  regressions, 295 VM/294 Node tests and clean analysis; independent checks pass
  for 31 pinned PDFs and two synthetic multi-program/multiple-artboard saves,
  covering 35 exact programs and retained metadata/content/resources.
- [x] Define how the host supplies or invalidates each derived native payload:
  printing expansions, text/layout caches, image/placed previews and thumbnails.
  Extend serialization where a supplied payload cannot yet be attached safely.
  **Verified for the existing qualified families:** `docs/HOST.md` states each supply/invalidation
  policy. `withoutTextLayout` clears selected known text caches without changing
  the model or resources (three regressions and 20 independently decoded story
  invalidations). `withPrintingContours` attaches complete host-supplied geometry
  to separate bound CC shape expansions, preserving authoring records, compound
  groups, paint controls and resources. Nine printing regressions cover immutable
  inputs, batches, limits and atomic rejection, including opaque embedded data.
  Independent checks verify ten variants of five pinned files, 40 expansions and
  84 paths with equivalent curves and unchanged unselected bytes. Thumbnail checks
  qualify selected native invalidation, unselected preservation and host decisions
  for PDF thumbnails; independent save checks cover both synthetic selections.
  CC `As` point counts are synchronized for printing and plain-path replacement,
  including supplied implicit closures and additional contours; ambiguous count
  ownership rejects atomically. Independent verification explicitly checks 68
  updated counts rather than relying on the SVG reader, which ignores them.
  `withPrintingGroups` additionally attaches complete ordinary/compound topology,
  process paints and existing gradient references while preserving outgoing state
  and the source count convention. Nine regressions cover paints, resources,
  immutable inputs, limits and atomic refusal. Independent checks qualify ten
  variants, 40 exact supplied groups and 40 added paths with equivalent ink and
  unchanged private/unselected bytes. Latest full validation: 319 VM/318 Node
  tests and clean format/fix/analysis, using xml 7.0.1. Unknown cache dependencies
  retain an explicit preserve/reject policy; further appearance/resource and object
  families remain in milestones 2–6 rather than being advertised as editable.
- [x] Keep native/PDF packaging independent of a rendering operator whitelist;
  preserve unrelated metadata, references and unknown records.
  **Verified:** the save path only checks byte/envelope and graph-ownership
  contracts; it does not decode drawing commands or consult capability reports.
  Regression saves preserve `FuturePaint`, opaque referenced streams, unselected
  programs and host-supplied artwork/resources. Repeated independent checks pass
  for 31 pinned PDFs and two synthetic partial/batch saves (35 exact programs).

**Acceptance:** synthetic and pinned real files survive decode/edit/save/reopen
with exact edited native data, supplied PDF resources and unselected payloads.
Stale/foreign handles, ambiguous mappings and invalid payloads fail atomically.
Visual agreement is a separate host/interoperability check.

## 2. Document structure and object lifecycle

**Starting point:** layers and paths are source-backed; records expose artboards,
groups and compound topology. There is no general modern object lifecycle API.

- [x] Model document units, ruler origins, artboards, ordering, object identities,
  shared resources and versioned alternatives with explicit ownership.
  **Verified for the qualified structural families:** `AiNativeDocumentSettings` retains header sources, display-unit
  codes, canvas scale and separate artboard/text origins without inferring missing
  values. Artboards retain their owning Document and local order. Five focused
  regressions cover immutable fields, unknown/absent units, conditional/repeated
  declarations, malformed metadata, embedded-document boundaries and limits.
  Nine additional pinned CC files qualify moved origins and large canvases.
  Independent decoding checks 46 sources, 207 header fields, 31 artboards and 32
  text origins. `AiNativeStructure` adds immutable source identities, ordered
  record fields, lexical parents/children, saved artboard/XML identifiers and
  separate authoring/printing links. Both saved version branches remain explicit,
  including nested, empty and newer-only blocks. Known-style/gradient links
  retain resolved, missing, ambiguous and conditional ownership; setup symbol
  and pattern uses are included without claiming semantic editing of those
  families. Twelve structural regressions cover foreign handles, malformed
  boundaries, opaque siblings, duplicate names, internal name conditions and
  aggregate limits. Independent checks verify all 46 sources, 220 paths, 50
  layers, 109 ordinary/compound groups, 55 version blocks, 659 declarations,
  1,274 uses and 195 saved identifiers. Latest validation: 336 VM/335 Node tests
  and clean format/fix/analysis. Unknown dependency schemas stay opaque; no
  global identity or arbitrary lifecycle permission is inferred from source spans.
- [ ] Add qualified create/delete/duplicate/reorder/reparent operations for layers,
  groups and paths, preserving unrelated source and updating all references.
  **In progress:** ordinary anonymous paths support insertion, duplication,
  removal, sibling reordering and same-layer movement across ordinary groups.
  Inherited paint/lock/visibility state is retained; movement rejects intervening
  state assignments. Point counts move with geometry, supplied ink bounds expand
  drawing extents, and private/derived/referenced/version-dependent objects reject.
  Thirteen focused lifecycle regressions cover ownership, atomic refusal, malformed
  counts, immutable input and limits. Independent decoding verifies 13 variants
  from two pinned recent files and synthetic counted/grouped sources, with exact
  unselected-byte preservation. Latest validation: 349 VM/348 Node tests and clean
  format/fix/analysis, using xml 7.0.1. Ordinary anonymous groups additionally
  support grouping/ungrouping, duplication, removal, sibling reordering and
  same-layer reparenting. Explicit source assignments preserve inherited and
  outgoing paint/lock/visibility state, including changed state inside groups;
  unknown required values reject. Sixteen focused group regressions cover nested
  and empty owners, process colors, point counts, attached metadata, atomic
  refusal, limits and a 200-group batch. Independent checks verify 13 group
  variants across two pinned recent files and a synthetic source, including
  complete topology, effective attributes and exact unselected bytes. Latest
  validation: 366 VM/365 Node tests and clean format/fix/analysis.
  `AiNativeLayers` now binds exact wrappers, names, panel expansion, XML identities
  and direct ownership. Qualified empty sibling insertion retains header flags,
  requires fresh identifiers, updates root counts and requires explicit saved-view
  invalidation. Twelve focused regressions cover malformed metadata, conditional
  headers, limits and atomic refusal. Independent checks verify all 50 layers in
  46 pinned sources and 40 inserted variants, preserving every unselected byte;
  ten headers with additional private fields reject. Latest validation: 378 VM/
  377 Node tests and clean format/fix/analysis, using xml 7.0.1. The shared header
  reader retains the independently checked 207 settings fields, 31 artboards and
  32 text origins. Qualified ordinary layer subtrees additionally support sibling
  reordering, movement after a layer and insertion into an empty/nonempty parent.
  IDs and own flags remain exact; parent changes require explicit destination
  inheritance. Source assignments preserve incoming/outgoing paint and object
  state; root counts and explicit view invalidation update atomically. Sixteen
  regressions cover nested ownership, malformed/unknown state, prefixes, limits,
  CMYK/RGB alternatives, dashes and a 100-layer batch. Independent checks qualify
  12 movements and two insertion prerequisites from three pinned recent sources
  and a synthetic program, comparing complete trees, identities, geometry/counts,
  effective attributes and unselected bytes. Latest validation: 394 VM/393 Node
  tests and clean format/fix/analysis, using xml 7.0.1. Ordinary subtrees now also
  support duplication with fresh identities for every descendant and optional
  copied display names, retaining references to the original objects. Removal
  retains outgoing state and permits identified deletion only in a qualified
  declarative reference scope; unknown document/resource owners reject. Ten
  additional regressions cover batch/immutable identity maps, collisions, atomic
  refusal, output/token budgets and remaining state. Independent checks add three
  copies and four removals, including synthetic identified deletion and a pinned
  anonymous AI7 regression: 22 lifecycle transactions now pass. Latest validation:
  404 VM/403 Node tests and clean format/fix/analysis, using xml 7.0.1. Identified
  deletion in real resource-bearing CC documents, referenced artwork and
  opaque/derived subtree lifecycle remain outstanding. Ordinary path reordering
  and movement now preserve source-backed paint/object state across qualified
  assignments. Different ancestor-group flags or depth require explicit
  destination inheritance; unknown required values, malformed state and opaque
  intervals reject. Nine regressions cover all supported components, process
  colors, ancestor flags, unselected bytes, bounds and a 150-path batch.
  Independent checks qualify 16 path transactions, including changed-state
  reordering and movement in both directions with exact source/count preservation.
  Latest validation: 413 VM/412 Node tests, clean format/fix/analysis and all 22
  layer transactions rechecked after sharing the bounded state serializer.
  Paths and ordinary groups additionally support cross-layer movement and direct
  appending to an existing, possibly empty layer. Explicit destination inheritance
  is required across layers or different ancestor-group flags/depths. Paint
  persists across qualified layer headers; layer identities, order, root counts
  and panel state remain exact. Eleven regressions cover nested hidden owners, root
  artwork, empty/anonymous destinations, foreign/stale handles, opaque neighbors
  and parser budgets.
  Independent checks qualify ten movements and four prerequisites in 14 transactions
  from two pinned recent files and a synthetic source. All 13 group and 16 path
  transactions were also rechecked after sharing the bounded state serializer.
  Latest validation: 424 VM/423 Node tests and clean format/fix/analysis. Regenerated
  cross-layer corpus outputs match the independently checked files byte-for-byte.
  Referenced and private/derived artwork lifecycle, plus broader identified-layer
  deletion, remain outstanding. Adobe reopening is unqualified.
  `AiNativeObjects` now binds direct path/group dictionaries, saved XML IDs,
  names and rotation metadata independently of geometry/appearance qualification.
  Whole-object moves/reorders retain metadata; duplication requires fresh IDs for
  every identified copied descendant. Anonymous deletion removes its metadata,
  and dissolution accepts only empty group dictionaries. Sixteen regressions
  cover repeated edits, identity collisions, immutable inputs, limits, layer
  transfers and unsupported/private records. Independent pinned-inkai checks
  initially verified five synthetic transactions and six exact real-file refusals;
  the later group-metadata qualification below supersedes five of those refusals.
  Real CC identified-object editing, identified deletion
  and derived/reference lifecycle remain outstanding; this task stays open.
  Latest validation: 440 VM/439 Node tests, clean format/fix/analysis, all
  65 prior layer/path/group/cross-layer transactions rechecked independently,
  and capability checks repeated on 37 exact sources (41 layer headers and 181
  ordinary paths). No renderer or host integration was introduced.
  Layer copies now accept `artworkIdentifiers` for identified group/path
  descendants, sharing collision checks and an aggregate byte budget with layer
  identities. Identified path/group/subtree deletion now uses one whole-source
  reference qualification, including identified children of anonymous owners.
  Eleven regressions cover mixed IDs, stale/extra handles, namespace collisions,
  unknown reference owners, duplicate identities and byte/token bounds. Six
  independently decoded synthetic transactions verify nested root/batch copies
  and path/group/subtree/all-root removals, including metadata, hierarchy, state,
  counts and unselected bytes. Resource-bearing CC reference resolution and
  private/derived lifecycle remain outstanding; this task stays open.
  Latest validation: 451 VM/450 Node tests, clean format/fix/analysis and all
  76 previous lifecycle/metadata cases regenerated and independently rechecked.
  Group objects now own direct panel flags (`Ae`) and mode-nine default-style
  applications (`9 () XW`) as well as their dictionaries. Copies, deletion,
  reordering and relocation carry the complete attachment spans; identity
  allocation includes prefixed groups and every identified descendant. Qualified
  `0 opacity 0 0 0 Xy` assignments retain inherited/outgoing opacity across groups
  and layers. Twelve regressions cover nested metadata, repeated child edits,
  layer movement, malformed/private/versioned attachments, identities and limits.
  Independent decoding now verifies five actual edits of `layers_and_sublayers.ai`
  (path copy/removal/reorder and group copy/removal), five nested synthetic
  metadata transactions, the five previous identity transactions and exact styled
  ungrouping refusal. Complete topology, panel/style ownership, opacity, counts
  and unselected bytes are checked. Named/other style applications, styled-group
  dissolution, resource-bearing identified deletion and derived/reference
  lifecycle still require their own contracts; this task remains in progress.
  Latest validation: 463 VM/462 Node tests, clean format/fix/analysis, all 71
  previous path/group/layer/movement/combined-identity cases regenerated and
  independently rechecked, plus the 16 object-metadata transactions above.
  Capability checks still recover 37 exact sources, 41 layer headers and 181
  ordinary paths. Adobe reopening and host integration remain unqualified.
- [ ] Add artboard creation, removal, resize and reorder with a declared mapping
  to host-supplied PDF pages. Artboards, crop bounds and drawing bounds stay distinct.
- [ ] Support editing ordinary native compound paths and clipping relationships
  without treating a CC object's printable expansion as its authoritative model.
- [ ] Narrow conservative whole-document refusals only after proving the selected
  object's inherited state and dependencies are isolated.

**Acceptance:** nested groups, shared resources, hidden/locked objects, multiple
artboards and unselected opaque content retain identity and ordering after each
operation. No dangling references or partially updated alternate records remain.

## 3. Common appearances and geometry

**Starting point:** qualified live shapes support translation, rotation and
uniform scaling. Classic gradients have stop/focus edits, selected resource
isolation and relative placement. General appearance editing remains incomplete.

- [ ] Expose ordered multiple fills/strokes and selected appearance parts, shared
  style ownership, stroke alignment/dashes and supported native paint settings.
- [ ] Add native opacity, blend, isolation, knockout and opacity-mask records,
  including mask artwork, linked/disabled/inverted state and dependent references.
  These are data contracts; compositing remains in the application.
- [ ] Extend color/swatches to qualified global and spot-color ownership, tint
  alternatives and profile metadata. Require explicit host color conversion.
- [ ] Add gradient resource lifecycle, hard stops and qualified newer layouts,
  along/across-stroke data and general instance placement. Continue accepting
  host-composed ramps instead of implementing a color/rendering engine.
- [ ] Add live-shape parameter edits, nonuniform resize, reflection/shear and
  explicit stroke/corner scaling policies. Keep native parameters, authoritative
  paths and supplied/qualified printing expansions consistent in one transaction.

**Acceptance:** edits distinguish selected appearance parts from shared/global
resources. Private and printing records agree; unselected users remain unchanged.
Unsupported effects or conflicting caches reject rather than being flattened or
silently dropped. Mask and transparency data have independent decoding checks.

## 4. Text lifecycle and layout serialization

**Starting point:** named CS/compact CC ATE views, UTF-16 content/feature edits,
font registration, supplied source-position layouts and frame translation exist.
Text caches, auxiliary tables and undo-free models still limit some edits.

- [ ] Add qualified story/frame creation, deletion, duplication and frame linking,
  plus point/area/path geometry changes and named style/resource lifecycle.
- [ ] Resolve main-model, drawing-reference and undo-free relationships with an
  explicit preservation/update policy; do not invent unsupported alternate data.
- [ ] Extend auxiliary feature tables, reference-size modes and script-specific
  records currently rejected by content or style edits.
- [ ] Extend serialization of host-composed named CS and compact CC layouts,
  reordered/hyphenated mappings and per-glyph/path data where the format is known.
- [ ] Add fixtures for mixed scripts, right-to-left and vertical text, linked
  frames, overflow, font variations and non-BMP selections.

**Acceptance:** source ranges, style inheritance, resource indices and frame
references remain consistent. Supplied layouts round-trip without reshaping;
invalid coverage is rejected. Adobe reopening confirms editable text and styles
for each qualified profile. Glyph shaping, font fallback and line breaking stay
outside AiKit.

## 5. Linked and embedded resources

**Starting point:** qualified native binary rasters support pixel replacement and
affine edits. CC raster links support relinking, embedding and supplied previews;
XMP references are edited through a separate explicit inventory.

- [ ] Extend raster/preview layouts, source color/profile metadata and supported
  dependent cache fields using real samples. Preserve unsupported encodings.
- [ ] Add qualified external/embedded vector resources, including PDF/EPS placed
  artwork, with opaque original payload preservation and explicit ownership.
- [ ] Model resource identity and shared uses across native declarations, placed
  objects and catalog XMP. Offer an atomic operation only where the mapping is
  established; identical paths alone do not prove identity.
- [ ] Support source-backed PostScript XMP and additional dependency schemas
  without rewriting unrelated XML or synthesizing asset history.
- [ ] Expand explicit host-supplied preview/representation attachment and removal
  policies for missing or replaced resources.

**Acceptance:** shared assets remain shared; selected replacement does not alter
unselected uses. Native paths, declarations, previews and qualified XMP references
agree after saving. Resolution, file access, decoding, resampling and profile
conversion are host responsibilities, using sibling kits where appropriate.

## 6. Advanced CC object families

Deliver each family as an independently qualified increment:

- [ ] **Meshes:** native vertex/control-handle geometry and topology edits,
  intermediate nodes, additional weights/layouts and resource/private ownership.
  Maintain shared corner consistency; do not add interpolation or tessellation.
- [ ] **Patterns and symbols:** definitions, instances, transforms, shared resource
  editing and local overrides with reference-preserving serialization.
- [ ] **Brushes and variable-width strokes:** native definitions, assignments,
  width profiles and dependencies on host-supplied expanded artwork.
- [ ] **Blends, warps and envelopes:** editable source objects and native parameters,
  with explicit attachment/invalidation of derived geometry.
- [ ] **Effects and plug-ins:** typed known descriptors, ordered appearance chains
  and retained opaque payloads. Unknown third-party plug-ins remain preserved;
  changing dependencies must reject until a safe contract is available.

**Acceptance:** independently decoded records verify parameters, references and
unselected bytes. Illustrator reopening verifies editability for the specific
family and version. Preserving an unknown plug-in payload does not complete that
plug-in's semantic support.

## 7. Modern document creation and version profiles

**Starting point:** typed creation targets AI7. Modern edits require an existing
source; packaging an arbitrary PDF does not create a CC-native document.

- [ ] Define an explicit CC writer profile for the first qualified feature subset,
  mandatory document/resource records, identities, counts and version markers.
- [ ] Construct a new native document without a borrowed opaque template, using
  supplied PDF, previews, layouts and other required derived representations.
- [ ] Extend supported features incrementally as their individual native writers
  become qualified; report every unavailable feature before encoding.
- [ ] Add explicit target-version compatibility rules. Reject lossy downgrades
  unless an application deliberately supplies a documented interchange result.

**Acceptance:** newly created files reopen as native editable Illustrator
objects, not merely PDF artwork. A second native save preserves those objects,
resource identities and unrelated data. Validation records the exact writer
profile and Illustrator version; no blanket CC-compatibility claim is inferred.

## 8. Older Illustrator families

Reuse modern contracts where the native structures match, then qualify each
older family separately. Existing byte preservation and AI7 creation remain valid
without implying complete legacy editing support.

- [ ] Establish a versioned corpus for CS-era PDF-backed files and older AI/EPS
  programs, including optional DOS previews and differing text/image layouts.
- [ ] Extend declarative native models and writers for older layer, path, paint,
  gradient, text, raster and placed-file records, including `XF` where qualified.
- [ ] Add save policies for changed PostScript programs and envelope previews;
  retain untouched source exactly and require supplied replacement previews when
  needed. Do not leave edited source paired with stale previews silently.
- [ ] Qualify supported target-version conversion feature by feature and expose
  unsupported constructs explicitly.

**Acceptance:** each supported family has independent decode/write checks and
version-appropriate reopening evidence. Dynamic or arbitrary PostScript remains
preserved/unsupported; implementing a general interpreter is outside this roadmap.

## Validation required for every milestone

- [ ] Add focused VM/Node tests for the changed parser, edit and writer contracts,
  including malformed input, limits, immutable snapshots and atomic refusal.
- [ ] Pin real fixtures with provenance, license, revision, size and checksums;
  keep artwork and generated outputs outside Git/publication.
- [ ] Compare edited and unselected native data with an independent reader.
  Round-tripping through AiKit alone is not interoperability evidence.
- [ ] Record Adobe reopening/resaving results where available, including version,
  supported edit and preserved features. Mark missing evidence as unqualified.
- [ ] Update the technical reference and capability matrix with exact support and
  remaining restrictions, without carrying forward removed rendering results.

A milestone is complete only for its declared feature/version subset. Focale
integration and interactive behavior require their own later validation. Their
deferral does not justify replacing native authoring data with a PDF preview, and
it does not require reintroducing a rendering engine into AiKit.
