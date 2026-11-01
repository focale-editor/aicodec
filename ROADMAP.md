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
- [x] Add qualified create/delete/duplicate/reorder/reparent operations for layers,
  groups and paths, preserving unrelated source and updating all references.
  **Completed for ordinary owners and the declared bound CC subtree contracts.**
  The implementation history below records each increment; the final paragraph
  defines the completed subset and its remaining separate contracts.
  Ordinary anonymous paths support insertion, duplication,
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
  Identified deletion now qualifies known setup `Document` metadata instead of
  rejecting every document record. Exact scalar/section schemas, empty asset and
  selection tables, empty XML variables/data sets/slices, bounded ICC profile
  ownership and known header/trailer syntax establish the supported reference
  scope. Unknown fields, nonempty reference owners, conditional records and
  executable extensions still reject. Eleven regressions cover path/group/layer
  deletion, preserved metadata, malformed profiles, XML bindings, ambiguous
  ownership, atomic refusal and header token ceilings. Independent checks verify
  nine identified-layer deletions in pinned uncompressed CC files, three synthetic
  artwork/subtree deletions and two exact refusals after injecting real-document
  references. Complete document bytes, artboards, profiles, hierarchy, state and
  unselected data remain exact; LittleCMS opens all nine retained real profiles.
  Referenced artwork, shared-style/text/plug-in dependencies and derived subtree
  lifecycle remain outstanding; the task remains open.
  Latest validation: 474 VM/473 Node tests, clean format/fix/analysis, all 14
  reference-scope transactions independently checked and all 44 existing
  layer, combined-identity and object-metadata transactions regenerated and
  independently rechecked. No Adobe reopening or broader reference support is
  inferred from these results.
  Fresh identity allocation now reserves every explicit native `XMLUID` wrapper,
  including unrecognized/private owners and both saved alternatives. Unresolved
  wrapper shapes reject allocation; anonymous copies retain their existing
  ownership contract. Seven regressions cover decoded escaped/hexadecimal names,
  repeated reservations, all four allocation APIs, embedded-document isolation,
  opaque preservation and atomic refusal. The independent identity suite now
  checks ten transactions: six previous edits plus two fresh copies and two
  collision refusals beside injected unknown wrappers in a synthetic source and
  a pinned CC document. Unknown binary reference schemas remain unresolved;
  this does not complete the lifecycle task.
  Latest validation: 481 VM/480 Node tests, clean format/fix/analysis, all ten
  identity transactions checked independently and all 22 layer/16 object-metadata
  transactions regenerated and independently rechecked. No host integration or
  broader reference qualification was introduced.
  Direct live shapes now retain their native parameters through whole-path,
  group and layer lifecycle operations. Qualification requires one non-private
  authoritative/printable path, known scalar parameters and no separate printing
  group, style or version alternative. Fresh copied IDs, retained source state,
  native shape counts and exact unbound-neighbor bytes are checked atomically.
  Thirteen regressions cover editable copies, identified deletion, reordering,
  grouping, cross-layer movement, subtree operations, malformed metadata and
  bounds. Independent decoding verifies 14 copy/removal transactions on seven
  pinned CC rectangle/ellipse files and seven identified synthetic transactions,
  including exact preservation of unselected private/printing/style records.
  Separate authoring/printing bundles and broader resource-reference lifecycle
  remain outstanding; this task stays open. Latest full validation: 494 VM/493
  Node tests and clean format/fix/analysis, using xml 7.0.1. All 105 existing
  path/group/layer/movement/metadata/identity/reference-scope transactions were
  regenerated and independently checked. Capability checks still recover all
  37 exact sources, 41 layer headers and 181 ordinary paths. No host rendering
  or Adobe reopening is inferred from this structural qualification.
  Complete bound CC authoring/printing pairs now support `duplicateLiveShapes`.
  Private contours, parameters, printing groups, both metadata alternatives and
  shared style/resource references stay together. Identified dictionaries require
  fresh source-wide XML names; unresolved repeated-ID aliases reject. Printing
  and private state are tracked separately, and missing inherited values are
  never replaced with defaults. Fifteen regressions cover atomic batches, editable
  copies, both metadata owners, state replay, point counts, unknown attachments,
  conditional styles, native dash serialization and limits. Independent checks
  verify 22 transactions: 14 successful real-file copies, four synthetic copies
  and four exact refusals, totaling 46 copied pairs. The real-file copies compare
  native and printing SVG geometry/styles/resources; synthetic copies compare
  printing SVG plus independently decoded version alternatives and source flags.
  The pinned SVG dispatcher ignores version-branch lists, so synthetic native SVG
  is explicitly excluded as acceptance evidence. Latest validation: 509 VM/508
  Node tests, clean format/fix/analysis, all 21 direct-shape lifecycle transactions
  independently rechecked and capability checks retaining 37 exact sources,
  41 layer headers and 181 ordinary paths. Pair removal, reordering, reparenting
  and broader resource-reference lifecycle remain outstanding; the task stays
  open. No native Adobe reopening or application rendering was introduced.
  Complete CC pairs now support `removeLiveShapes`, retaining shared styles and
  resources while removing both representations, saved alternatives, counts and
  panel flags. Explicit public/private assignments remain; definite native style
  scalars are replayed from source. Following artwork that reads an unresolved
  removed-style effect before reassignment rejects atomically. Saved identities
  additionally require an unambiguous whole-document reference scope covering
  every paired owner, qualified styles, ordinary artwork and supported document
  metadata. Fourteen regressions cover batches, identified alternatives, state
  projections, scalar replay, dependent neighbors, opaque references, attachments,
  snapshot handles and limits. Independent checks verify 27 transactions and
  71 removed pairs: 17 real-file removals compare native and printing SVG, seven
  synthetic removals compare printing SVG and decoded metadata/state, and three
  exact refusals cover inherited style effects, unknown references and aliases.
  All unselected bytes stay exact. The synthetic version-branch SVG limitation
  remains explicit; no Adobe reopening is claimed. Latest validation: 523 VM/522
  Node tests, clean format/fix/analysis, all 22 pair-copy and 14 reference-scope
  transactions regenerated and independently rechecked. Pair reordering,
  reparenting and broader resource-reference lifecycle remain outstanding; the
  task stays open.
  Complete CC sibling pairs now support `reorderLiveShapes`, retaining exact
  private/printing source blocks, identities, alternatives and shared resources.
  Source provenance distinguishes unchanged unknown attributes from values across
  opaque boundaries; known literal assignments preserve both input streams and
  destination state. Complete scoped gradients no longer invalidate unrelated
  flags. Unknown outgoing attributes require a proof that subsequent artwork does
  not read them before reassignment, separately for native and printing state.
  Sixteen regressions cover permutations, nonconsecutive slots, identities,
  inherited opacity/flags, external records, panel ownership, unchanged orders,
  unknown inputs, outgoing dependencies, stale handles and bounds. Independent
  checks verify 24 transactions and 59 changed pair slots: 12 real-file and six
  synthetic permutations, two unchanged orders and four exact refusals. Native
  records, all unselected bytes and source-derived replay are checked; real SVG
  native/printing paint and geometry retain the requested order. Three printing
  comparisons with inactive stroke-attribute differences additionally produce
  pixel-identical librsvg RGBA images. Synthetic version-branch SVG limitations
  remain explicit. Latest validation: 539 VM/538 Node tests, clean format/fix/
  analysis, all 22 pair-copy and 27 pair-removal transactions regenerated and
  independently rechecked. Pair reparenting and broader resource-reference
  lifecycle remain outstanding; this task stays open. No host integration or
  Adobe reopening is inferred.
  Complete CC pairs now support `moveLiveShapeAfter`, `moveLiveShapeToGroup`
  and `moveLiveShapeToLayer`, including empty destinations. Exact pair blocks,
  identities, alternatives and shared resources travel together; source-derived
  state remains at the old position and restores both interpretations around
  insertion. Dependencies are checked in final source order at both boundaries.
  Different layers or ancestor-group flags/depths require explicit inheritance;
  printing expansions and unresolved/private/compound/clip parents reject.
  Seventeen regressions cover forward/backward moves, parent inheritance in both
  streams, metadata/identity/panel retention, old/new dependencies, malformed
  boundaries, snapshot handles and byte/token growth. Independent checks verify
  32 fixed transactions: 12 real and 12 synthetic moves plus eight exact refusals.
  Native owner trees, pair bytes, alternatives, unselected gaps and scalar replay
  are checked independently, along with real native/printing SVG and synthetic
  printing SVG after exactly the requested parent/order change. Synthetic native
  SVG and Adobe reopening limitations remain explicit. Latest validation:
  556 VM/555 Node tests, clean format/fix/analysis using xml 7.0.1, and all 27
  pair-removal and 24 pair-reordering transactions regenerated and independently
  rechecked. Broader resource-reference lifecycle remains outstanding; this task
  stays open. No Focale integration was introduced.
  Identified ordinary paths, groups and layers now share whole-document reference
  qualification with complete CC pairs. Qualified neighboring pairs, unused literal
  styles, counted gradient banks and private scalar replay are retained exactly;
  resource names stay separate from artwork identities. Wrapped layer boundaries
  preserve distinct ownership on either side of a pair. Thirteen regressions cover
  mixed owners, replay, aliases, conditional resources, malformed counts and opaque
  annotations. Independent checks verify 18 fixed transactions: four removals from
  declared assemblies of five pinned CC sources, six synthetic removals, four full
  donor-file refusals and four synthetic refusals. Assembly recipes are rebuilt
  from exact original fragments and bound to the independent donor parse; these
  derived fixtures do not qualify removal from the complete donor files. Both
  real native/printing views and synthetic printing views retain the requested
  change, resource records, metadata alternatives and all unselected bytes.
  Latest validation: 569 VM/568 Node tests, clean format/fix/analysis, and all 119
  existing pair-copy/removal/reordering/movement and reference-scope transactions
  regenerated and independently rechecked. Group/layer subtrees containing private
  pairs and broader reference-owner schemas remain outstanding; this task stays
  open. Synthetic native SVG and Adobe reopening limitations remain explicit.
  Qualified ordinary group/layer parents now support complete removal of mixed
  subtrees containing CC pairs. Private contours, printing expansions, parameters,
  panel flags and all metadata alternatives are deleted together. Explicit scalar
  state retains its source order/projection, with definite style effects replayed
  for surviving artwork. Dependency checks ignore reads by other deleted children
  but retain their writes; unresolved effects read by surviving objects reject.
  Every removed identity participates in the document reference check, including
  older alternatives and identified children of anonymous parents. Authoritative
  shape counts now handle both versioned and unversioned metadata without counting
  a path-bound pair twice. Fourteen regressions cover nested/mixed owners, atomic
  batches, retained dependencies, privacy, opaque references, partial pairs and
  bounded scalar replay. Independent checks verify 22 fixed transactions: nine
  derived-real and eight synthetic removals plus five exact refusals. Exact wrapper
  recipes around complete pinned CC programs and declared resource assemblies are
  reconstructed independently; source ownership, both metadata branches, retained
  bytes, scalar order/privacy, topology and flags are checked. Both real-derived
  SVG interpretations and synthetic printing SVG retain exactly the requested
  deletion. These derived owners do not qualify complete original donor-layer
  deletion. Latest validation: 583 VM/582 Node tests and clean format/fix/analysis.
  All 101 existing group/layer/direct-shape/pair-removal/reference-resource
  transactions were regenerated and independently rechecked.
  Mixed-subtree copying, reordering and reparenting, plus broader reference-owner
  schemas, remain outstanding; this task stays open. No Focale integration or
  Adobe reopening was introduced, and synthetic native SVG remains unqualified.
  Qualified mixed group/layer subtrees now support copying immediately after
  their original owners. Both representations, native parameters, panel state
  and saved alternatives stay together; shared styles/resources remain exact.
  Ordinary objects retain their source-handle identity keys, while paired IDs
  require the owning metadata dictionaries, including older alternatives. Every
  new name is reserved against the complete source; missing/extra mappings and
  repeated source aliases reject. Input replay tracks both interpretations across
  the whole subtree, distinguishing definite scalar writes from potential/hidden
  style effects. Known ordinary parent metadata no longer prevents subsequent
  native shape transforms; unresolved parent appearances still reject. Seventeen
  regressions cover nested batches, both saved metadata layouts, source-wide ID
  reservations, distinct private/public flags, definite/hidden styles, opaque
  neighbors, bounds and continued editing. Independent checks verify 23 fixed
  transactions: eight derived-real and ten synthetic copies plus five refusals.
  Recipes, copied/unselected bytes, every replacement string, original input
  scalars, native flags and both metadata branches are independently bound. Real
  native/printing SVG and synthetic printing SVG retain the requested duplication;
  one follow-up edit also checks private/printing geometry, main/redundant centers
  and unchanged older metadata. The opacity-source refusal retains its unresolved
  inherited-input limit. Latest validation: 600 VM/599 Node tests and clean
  format/fix/analysis. The existing subtree-removal, paired-shape, group, layer
  and direct-shape suites also pass all 100 independent transactions, bringing
  this validation run to 123 transactions plus the follow-up translation.
  Mixed-subtree reordering/reparenting, grouping/dissolution and broader
  reference-owner schemas remain outstanding; this task stays open.
  No Focale integration or Adobe reopening was introduced, and synthetic native
  SVG remains unqualified.
  Qualified mixed sibling group/layer subtrees now support reordering into their
  selected original slots. Nested ordinary owners, multiple complete CC pairs,
  all saved metadata alternatives, panel flags, headers and identities move as
  exact source bytes. Ordinary and paired siblings may share one permutation;
  aliases and external references remain unchanged. Shared placement/dependency
  logic preserves separate native/printing input and output state, using complete
  owner intervals and source-derived replay; unknown differences still consumed
  by following artwork reject atomically. Thirteen regressions cover complete
  nested owners, several pairs under one parent, selected slots, ordinary/paired
  batches, exact identities, separate state, view invalidation, malformed/foreign
  handles and limits. Independent checks cover 43 fixed transactions: 24
  derived-real and seven synthetic reorderings, four unchanged orders and eight
  refusals. Exact recipes, both metadata branches, all moved/unselected bytes,
  replay at original source/destination boundaries and native/printing flags are
  independently bound. Real native/printing SVG and synthetic printing SVG keep
  the requested parent order; shared resources resolve at their uses and the
  disabled-stroke exception requires identical librsvg pixels. Latest validation:
  613 VM/612 Node tests and clean format/fix/analysis. The existing paired-shape
  reordering/movement/removal and subtree removal/copy suites also pass all 128
  independent transactions, for 171 in this run plus a copied-shape translation.
  Mixed-subtree reparenting, grouping/dissolution and broader reference-owner
  schemas remain outstanding; this task stays open. No Focale integration or
  Adobe reopening was introduced, and synthetic native SVG remains unqualified.
  Qualified mixed group/layer subtrees now support movement and reparenting,
  including group insertion into populated/empty groups, cross-layer group moves,
  whole-layer nesting and lifting after ancestors. `moveGroupToGroup` also accepts
  ordinary-only source parents. Complete native/printing pairs, metadata
  alternatives, ordinary descendants, identities, aliases and headers stay exact.
  Source-backed state retention is shared with mixed-subtree deletion, while
  identity-reference audits remain specific to deletion. Both edited positions
  are checked together; separate native/printing ancestor flags, explicit parent
  inheritance, saved-view invalidation, root counts and required-state refusals
  remain enforced. Eighteen regressions cover both movement directions, empty and
  populated destinations, several pairs under one parent, nested layers, exact
  metadata, unknown dependencies, source ownership and limits. Independent checks
  pass 51 fixed transactions: 24 derived-real and 16 synthetic moves plus 11 exact
  refusals. Recipes, requested native parent trees, both metadata alternatives,
  all ordinary/paired contour flags, exact moved/unselected source, ordered
  retention and source/destination state replay are independently bound. Real
  native/printing SVG and synthetic printing SVG retain whole-owner placement and
  resolved resources; inactive stroke differences require identical librsvg ink.
  Latest validation: 631 VM/630 Node tests and clean format/fix/analysis. The
  existing pair-movement, subtree-removal/reordering, group and layer lifecycle
  suites also pass all 132 independent transactions, for 183 in this run.
  Grouping/dissolution and broader reference-owner schemas remain outstanding;
  this task stays open. Adobe reopening and synthetic native SVG remain
  unqualified, and Focale integration is still deferred.
  Mixed grouping and qualified parent dissolution are now implemented:
  `groupArtwork` accepts consecutive sibling paths, groups and complete CC pairs,
  retaining exact child source, point counts and both metadata alternatives.
  `groupPaths` shares this qualification. Dissolution retains descendants and
  removes parent metadata only with explicit disposal; only deleted parent IDs
  undergo reference checks, so retained descendant aliases are not reassigned.
  Both grouping APIs and dissolution require explicit inheritance for non-neutral
  or unknown native/printing ancestor flags. Applied group styles and opaque
  metadata/reference owners still reject. Twelve regressions cover mixed and
  nested selections, flags in both streams, parent identities, aliases, unselected
  source, stale/foreign handles and limits. Independent native-reader checks pass
  18 fixed transactions: twelve original/derived-real cases across four pinned
  programs, two synthetic edits and four exact refusals, checking requested native
  topology, complete selected owners, exact byte changes and contour state.
  Latest validation: 643 VM/642 Node tests and clean format/fix/analysis. The
  existing ordinary group, artwork movement and direct-shape suites also pass
  all 48 independent transactions, for 66 in this run.
  Broader object/reference-owner schemas and applied-style dissolution still
  require their declared contracts; this lifecycle task remains open. This lot
  establishes native serialization only, without Adobe reopening or host rendering.
  Neutral default-group resets (`9 () XW`) now dissolve with their qualified
  parents. Child opacity, nested resets, complete CC pairs and following state
  remain unchanged; an empty removed group cannot leave its reset attached to an
  earlier sibling. Nondefault/named/private/malformed style applications and resets
  inside an enclosing gradient instance reject instead of being flattened. Five
  regressions and 18 fixed independent
  transactions cover one original real group, four declared real-pair wrappers,
  five synthetic edits and eight refusals. Fifteen native/printing SVG comparisons
  and exact 1024-wide RGBA comparisons pass, without changing the independent
  reader. Latest validation: 648 VM/647 Node tests and clean format/fix/analysis. The
  prior ordinary and mixed grouping suites also pass 31 transactions, for 49
  independent transactions in this run.
  This is a data/serialization change, with no host renderer or Adobe reopening.
  `movePathToGroup` now appends complete ordinary paths, consumed counts and
  direct live-shape metadata into populated or empty groups. Both state streams
  retain consumed paint and flags, including assignments between a count and its
  geometry. Qualified CC siblings retain exact bytes and saved alternatives;
  cross-layer or changed ancestor inheritance remains explicit. Ten regressions
  and 15 independent transactions cover four real-source moves, eight synthetic
  moves and three immutable refusals. Fifteen SVG/pixel comparisons pass for
  eleven moves. The counted-state fixture has native-data validation only because
  the pinned SVG reader clears persistent fill after stroke-only paths. Synthetic
  native branches and Adobe reopening remain unqualified. Latest validation:
  658 VM/657 Node tests and clean format/fix/analysis.
  `AiNativeLayers.create` now creates a first/root layer or appends a last child
  without an existing sibling. Immutable definitions supply explicit qualified
  integer header layouts, native names, fresh optional identities and panel state.
  Existing bytes and LF/CRLF conventions are retained; declared root counts and
  explicitly discarded view mappings update atomically. Eight regressions cover
  recreation after total removal, empty/populated parents, all three layouts,
  changed-width/absent counts, immutable inputs, collisions and original limits.
  Twelve independent transactions verify six real and six synthetic creations,
  with exact source preservation and original/native parent ownership. Latest
  validation: 666 VM/665 Node tests and clean format/fix/analysis.
  `createGroup` now appends a first/root group or an empty last child of an
  ordinary group/layer, with explicit names, fresh optional identities and
  inherited flags. No existing sibling is required. Original bytes, CC pairs,
  layer headers, view declarations and drawing state remain exact; unowned
  expansion/count/note prefixes cannot be captured by the new object. Eight
  regressions cover creation followed by duplication/removal/recreation, empty and
  populated/hidden owners, private-state inheritance and limits. Thirteen fixed
  independent transactions verify seven real and five synthetic creations plus
  one immutable refusal. Latest validation: 674 VM/673 Node tests and clean
  format/fix/analysis. Adobe reopening remains unqualified.
  `createPath` now authors a first/root path or appends to an ordinary group/layer
  without a sibling or template. Immutable definitions supply geometry, process
  paints, line attributes, count/closure, visibility, opacity, overprint, optional
  name/fresh identity and host-computed ink bounds. Known outgoing native and
  printing state is restored independently; unknown required following state
  rejects. Existing source, complete CC pairs and layer/view data remain exact
  apart from the declared drawing-bound union. Eight regressions cover all 48
  color/count/closure/paint combinations, curves, immutable values, created and
  empty parents, subsequent edits and original limits. Eighteen independent
  transactions verify seven real and ten synthetic creations plus one refusal;
  the thirteen prior group-creation transactions also pass after prefix reuse.
  Latest validation: 682 VM/681 Node tests and clean format/fix/analysis.
  This completes creation, deletion, duplication, ordering and reparenting for
  qualified ordinary layers/groups/paths, together with the documented lifecycle
  of complete bound CC pairs and mixed subtrees. Unsupported references reject
  atomically instead of leaving dangling identities. Artboards, compound/clip
  editing, broader reference isolation, appearance families and creation of new
  CC live-shape parameters retain their separate tasks. Adobe reopening remains
  unqualified; no host renderer or derived representation generator was added.
- [x] Add artboard creation, removal, resize and reorder with a declared mapping
  to host-supplied PDF pages. Artboards, crop bounds and drawing bounds stay distinct.
  **Completed for the documented native CC dependency and mapped-save profiles.**
  The implementation history below records each increment; the final paragraph
  states the completed contracts and remaining separate feature families.
  `AiNativeArtboards` now retains explicit document ownership,
  ordered boards, separate `CropAreaActive`, selection, `LastArtboardID` and
  initial crop declarations. A pinned five-page Illustrator 30.6 source confirms
  that active index 4 differs from selected index 2, and that LastArtboardID 67 is
  not the board count. Native rectangle resizing changes only selected coordinates
  and explicitly supplied crop/ruler fields, preserving artwork and drawing
  extents. Nine regressions and 19 independent transactions pass: six real-source
  inspections, six resizes in three CC sources, four synthetic resizes including
  complete CC pairs/resources, and three unchanged dependency refusals. Latest
  validation: 691 VM/690 Node tests and clean format/fix/analysis. The multi-page
  source is qualified for Document inspection only; its body is not fully decoded
  by the independent reader. Native `create`, `remove` and `reorder` now retain
  complete private board dictionaries and their separator trivia. Creation takes
  an explicit fresh UUID, name, rectangle, ruler origin and saved history value;
  active ownership follows index changes, while active removal requires a retained
  replacement. Selection and crop policy remain independent. Thirteen additional
  regressions cover immutable definitions, absent fields, CR/LF syntax, stale
  handles, identity collisions, print-range refusals and original parser budgets.
  Twenty-five independent transactions qualify fifteen chained edits in three
  pinned CC files and ten synthetic edits, including complete CC pairs/resources.
  Full validation: 704 VM/703 Node tests, clean format/fix/analysis; focused cases
  also cover rejection of ambiguous saved UUID encodings. At that stage,
  artboard-specific dependency isolation, print-range remapping and explicit host
  PDF-page mapping still required implementation and checks. Native saving now
  synchronizes exact full/font-filtered `AIMetaData` header copies without parsing
  drawing operators. Unknown caches remain exact for unchanged headers; changed
  headers with divergent or ambiguous cache profiles reject atomically. Nine
  regressions cover compression, aliases, partial batches, original references
  and aggregate limits. Independent checks cover 32 pinned PDFs and two synthetic
  saves: 22 real saves, ten older-profile refusals and 31 updated owner caches,
  including all five owners in the Illustrator 30.6 source. Latest full validation:
  713 VM/712 Node tests and clean format/fix/analysis. Divergent older cache profiles
  remain unqualified. Explicit PDF mapping is now implemented through
  `AiNativeArtboards.pageReplacement` and `AiNativeData.replaceMapped`. Current
  boards bind distinct host pages in native order, with explicit original
  page/catalog metadata templates. Catalog aliases and unselected programs remain
  intact; new-page identity capture, incomplete mappings, reachable deleted-page
  references and newly dangling references reject. Page-label positions require
  supplied labels/removal or an explicit retain policy. Thirteen regressions cover
  these contracts, atomic refusals, stale handles, opaque drawing and limits.
  Nine independent serialized transactions pass: three real page-identity
  replacements with exact native programs (including the five-page CC source),
  four synthetic native lifecycle saves and two multi-program partial/batch saves.
  Native data, cached headers, owner templates and supplied PDF content/resources
  are independently checked. Full validation: 726 VM/725 Node tests and clean
  format/fix/analysis. Existing strict saves (31 pinned PDFs, two synthetic saves,
  35 programs) and header-cache checks (32 pinned PDFs, two synthetic saves,
  31 updated owner caches) were regenerated and independently rechecked.
  Artboard-specific dependency isolation remained outstanding alongside saved
  print-range remapping. `AiNativePrintJob` now exposes separate all flags and
  stored artboard/physical-page selections. Native lifecycle edits remap artboard
  ranges by retained identity, preserve dormant selections and require an explicit
  replacement when deletion exhausts the active print selection. Physical page
  choices use host-supplied `AiNativePrintSelection` counts/indices rather than
  inferred PDF/artboard ordinals. ASCII, BOM-marked UTF-16, fragmented strings and
  existing empty operands retain types/trivia; unknown grammar/encoding, missing
  supplied fields and inspection/output excesses reject atomically.
  Eleven regressions and twenty independent native transactions pass: fifteen
  chained edits in three pinned CC files and five synthetic edits with complete
  CC pairs/resources. Original real ranges are empty; the suite writes explicit
  choices before remapping, and checks complete Document values plus exact
  unselected bytes. Full validation: 737 VM/736 Node tests and clean format,
  fix and analysis. The 19 existing artboard inspections/resizes/refusals and
  25 lifecycle transactions were regenerated and independently rechecked.
  Actual Adobe printing remains unqualified. A separate artboard dependency scope
  now preserves simple process styles, literal plug-in inventories, resolved
  style lists, empty symbol lists and process/registration palettes independently
  of artwork identity deletion. Empty main/undo-free ATE documents retain unused
  typography resources and explicit global ruler origins; unknown owners, active
  text, opaque tokens, conditional wrappers and aggregate inspection excesses
  reject atomically. Thirteen regressions cover namespace separation, all four
  artboard operations, global-coordinate retention, unchanged deletion guards,
  malformed setup and bounded binary parsing. The independent lifecycle suite
  now verifies forty transactions: thirty edits in five pinned real CC files
  (including original RGB/CMYK rectangle setup/text payloads), and ten synthetic
  edits with shared resources. Full validation: 750 VM/749 Node tests and clean
  format, fix and analysis. Populated text and complex resource/object-family
  isolation still remain, so this task stays open.
  Retained-body inspection now separates artboard edits from independent path
  lifecycle permission. Ordinary compound and clipping groups, nested path masks,
  hidden/locked layers and direct identities retain exact source and ordering.
  Complete CC pairs keep their internal checks while their unmodified neighbors
  receive separate whole-body qualification. Eight regressions cover masks,
  geometry/count ownership, opaque neighbors, unchanged child-edit refusals,
  adjacent CC pairs and 250 compounds. Independent lifecycle verification now
  covers 48 transactions (30 pinned real, 18 synthetic), including all retained
  operators and operands in six synthetic compound/clip outcomes. Actual producer
  clipping fixtures and broader object/resource isolation remain unqualified;
  the separate compound/clip editing task below has not been completed by this
  preservation-only extension. Full validation: 758 VM/757 Node tests and clean
  format, fix and analysis. The 19 state/rectangle/refusal transactions and 20
  print-selection transactions were also regenerated and independently rechecked.
  No host integration or native renderer was added.
  End-to-end mapped-save verification now includes eight chained transactions
  in the pinned RGB/CMYK rectangle PDFs: creation, resize, reverse ordering and
  removal of the original active board/page with an explicit active replacement.
  Each step reopens the previous serialized file and reacquires native handles;
  the independent reader verifies that provenance chain, complete Document
  values, exact retained dictionaries/trivia, native bytes outside the edit,
  supplied PDF data and current-page metadata templates. All 17 mapped-save
  transactions pass. Two additional regressions exercise the same save/reopen
  lifecycle with nested compound clips, hidden artwork, complete CC pairs and
  shared resources. Full validation: 760 VM/759 Node tests and clean format,
  fix and analysis. This closes the real edited-native/mapped-PDF validation gap;
  it does not qualify populated text or complex retained resources. Inspection
  of `simple_cc_legacy.ai`, `simple_v2020.ai`, `text_transforms.ai` and
  `flowtext.ai` confirms that their resolved story/frame models still reject
  at retained `AI11Text` ownership, before later setup dependencies are checked.
  Those owners, linked frame/confining-path relationships and independent text
  snapshots remain part of this open artboard dependency task.
  Populated compact ATE 7/9 text now has a retained-dependency contract. Drawing
  references resolve against the explicitly selected main/undo-free snapshot;
  story frame order, cached frame references, point/area/path geometry, global
  origins and owned unpainted confinements remain unchanged. Text identities,
  literal style assignments and scalar fill/stroke flags retain their separate
  namespaces. Unknown owners, schemas, frame kinds, cached tags, executable or
  opaque confinements, dangling references and aggregate inspection excesses
  reject atomically. Nine regressions include linked frames, both snapshots,
  mapped serialization and further editing, malformed input and original limits.
  Twenty-four independent transactions pass in six checksum-pinned carriers:
  four contain exact producer text from the files above (including ten stories
  and sixteen frames in `text_transforms.ai`), and two exercise synthetic
  main/undo-free ownership. The oracle compares both complete ATE payloads,
  origins, drawing references, metadata, confinement commands and retained native
  bytes against the producers and each result. Full validation: 769 VM/768 Node
  tests and clean format, fix and analysis; the existing 48 lifecycle and 19
  state/rectangle/refusal transactions also pass. These carriers qualify retained
  text, not edits of the four full producer documents. Those now pass text/body
  inspection but initially rejected gradient banks before later complex setup
  dependencies were checked. Investigation traced that refusal to font marks,
  not genuinely nested resources: `TE`/`TZ` terminate their opening `[` without
  a closing bracket. Literal font encoding runs, known flags, optional Multiple
  Master weights, matching wrappers and plain font inventories now retain their
  independent namespace. Gradient isolation recognizes the same mark grammar;
  real nested arrays, executable/immediate names, malformed runs and opaque or
  conditional font ownership still reject. Eight additional regressions pass.
  The 24 independent retained-text transactions now also preserve exact producer
  font setup and compare independently decoded encodings with each original and
  outcome. All four full producer files pass gradient-bank qualification and next
  reject gradient palette entries or localized registration colors; complex
  setup-resource isolation therefore keeps this task open. Full validation:
  777 VM/776 Node tests and clean format, fix and analysis. The five existing
  real-source gradient-isolation/color/focus transactions were regenerated and
  independently rechecked after the shared bank-scanner change. No text
  recomposition, host integration or renderer was added.
  Palette retention now covers explicit cell indices, none paints, optional
  legacy/CC cell names, named CMYK/RGB alternatives and their tints, localized
  registration labels, Boolean group flags and resolved gradient instances.
  Palette coordinates, matrices and independent name namespaces remain exact.
  Unknown/conditional/ambiguous resources, malformed cells, opaque/private
  annotations, executable paints and pattern dependencies reject atomically.
  Eight regressions pass. The independent lifecycle suite now checks 54 native
  transactions (30 real, 24 synthetic), including six new palette outcomes with
  complete command/operand and gradient-definition comparisons. The four full
  producer files now reach their pattern palette cells; their pattern artwork
  and later complex setup owners still require qualification, so this task
  remains open. Full validation: 785 VM/784 Node tests and clean format, fix and
  analysis.
  Direct CC pattern definitions now retain ordinary/private paths, compound and
  clipping groups, checked point counts, local editor metadata and uniquely
  resolved gradient instances. Palette fill/stroke references preserve complete
  pattern transforms in a separate name namespace. Unknown/conditional owners,
  malformed topology or operands, executable programs and opaque payloads reject
  atomically. Eight regressions cover all four artboard edits and original limits.
  The independent text/font suite now checks 28 transactions in seven pinned
  carriers, including complete producer pattern/gradient banks and palettes. Each
  real carrier contains two patterns with 102 paths (177 in `flowtext.ai`) and 16
  gradient definitions (20 in `flowtext.ai`); all commands, metadata, references
  and copied source bytes are compared with the original producer and every
  outcome. The 54 existing lifecycle transactions were regenerated and rechecked
  after sharing bounded drawing topology. These carriers qualify retained
  resource data, not full-producer editing: symbol inventories and other setup
  owners, including brush resources, remain unresolved, so this task stays open.
  Full validation: 793 VM/792 Node tests, 82 independent transactions and clean
  format, fix and analysis. No renderer or Focale integration was added.
  Direct CC symbol definitions now share the retained resource-artwork parser.
  Ordinary/private paths and groups, local registration grids, XML identities,
  rotation, named colors and literal blending flags remain exact. Style and
  pattern references resolve to unique unconditional definitions; AI10/AI24 panel
  lists retain their independent order and names, including the observed legacy
  NUL-terminated opening wrapper. Eight regressions cover ownership, limits and
  all four edits. A new independent suite checks twenty transactions with 39
  byte-exact producer symbol definitions and one synthetic identified/style-bound
  symbol. The four real carriers retain the producers' complete text, fonts,
  patterns, gradients and palettes alongside the selected symbols. Complete
  symbol commands/metadata, inventory order and retained bytes are independently
  compared. Full-producer editing still requires symbol masks/blends, additional
  appearance graphs and other setup resource owners; the artboard task stays open.
  Full validation: 801 VM/800 Node tests and clean format, fix and analysis. All
  102 independent transactions pass, including regeneration/rechecks of the
  previous 28 text/pattern and 54 lifecycle outcomes after sharing resource scope.
  Retained symbol opacity masks now keep explicit linked/disabled/clipping/inverted
  flags and complete bounded artwork. Empty, vector, nested and qualified raster
  masks preserve geometry and source coordinates. Process-image framing,
  placement, sample UUID ownership and known raster-observer metadata are checked
  without decoding samples as commands or recompositing the mask. Unknown fields,
  annotations, executable state, malformed frames and unsupported layouts reject
  atomically. Eight regressions and twenty new independent transactions pass.
  Three pinned carriers retain six complete producer masks, including 32-by-32
  and 29-by-30 gray images with every sample byte checked; two synthetic carriers
  cover raster/vector masks. Complete flags, commands, descriptors, source spans
  and the retained producer text/font/pattern data are compared independently.
  The full files now pass mask inspection before later style/dependency refusals;
  their appearance graphs, blend owners, brushes and SVG filters still need
  qualification. This artboard task remains open; no host renderer was added.
  Full validation: 809 VM/808 Node tests, clean format/fix/analysis and all 122
  independent transactions, including the previous 102 symbol/text/lifecycle
  outcomes regenerated and checked against their original sources.
  Retained appearance qualification now has an artboard-specific graph inspector,
  independent of shape-transformation permissions. Ordered chain/stack filters,
  repeated and hidden paints, gradients/patterns and seven local effect families
  retain exact typed parameters. Mode-zero named style applications are indexed
  with their dependencies; empty names no longer create fictitious missing uses.
  Focused cases cover ordinary/private assignments, legacy plug-in identifiers,
  malformed fields, executable or opaque data and unresolved resources. Twenty
  independent transactions compare 50 complete producer symbols and 46 complete
  style graphs, including the full Film masks and styles, plus a synthetic graph.
  The carriers explicitly exclude Band's blend dependencies and Chrome Highlight's
  calligraphic brush reference. Whole producer files still need setup brush,
  SVG-filter, blend and other ownership qualification; the artboard task stays open.
  Full validation: 817 VM/816 Node tests, clean format/fix/analysis and 142
  independent transactions. The previous 122 symbol/text/lifecycle/mask outcomes
  were regenerated and rechecked; all 20 appearance outcomes compare exact
  producer graphs and retained native bytes.
  The original CC legacy symbol panel now retains both NUL-terminated boundary
  comments. The appearance carriers keep all three complete producer panel lists
  in their own saved order, with independent source-tree and byte comparisons.
  Arbitrary embedded/repeated NULs remain rejected; 22 focused VM/Node cases and
  clean format/fix/analysis validate this boundary correction. All twenty
  appearance transactions pass with the exact producer inventories; the three
  full sources now pass panel inspection before the remaining brush owners.
  Direct brush artwork now shares the retained resource parser and image-owner
  checks. Separate brush names, counted compound/clip paths, source metadata and
  named paint/style dependencies remain exact. Direct pattern/symbol images use
  the same bounded process-raster contract, including separate color/alpha planes
  and measured producer count variants. Eight regressions cover all four board
  operations, process colors, private/ordinary samples, hostile binary delimiters,
  resource namespaces, missing/ambiguous uses, malformed ownership and limits.
  Twenty independent transactions compare all 17 producer brush definitions and
  20 RGB/CMYK images. A geometry-bounded raw-plane check complements the pinned
  reader's known loss of one leading RGB byte, so all original pixels are checked.
  The carriers also retain the previous complete appearance/text/resource data.
  Full original CC sources now pass brush inspection before SVG-filter owners;
  calligraphic assignment descriptors and blend dependencies also remain open.
  Full validation: 826 VM/825 Node tests, clean format/fix/analysis and 162
  independent transactions, including regeneration and comparison of all 142
  previous resource/text/lifecycle outcomes. This artboard task remains open.
  Retained SVG-filter collections now qualify complete native XML ownership,
  local scalar primitives and parent-targeted animations without evaluating
  effects. Repeated result names stay in their filter namespace, even when they
  match a native artboard UUID. External resources, scripts, event timing, unknown
  fields, malformed ownership and conditional sections still reject atomically.
  Eight focused regressions cover all four operations and original depth/output
  limits. Twenty independent transactions compare all 72 producer filter trees
  and 24 animations, complete source bytes and the retained brush/appearance/text
  resources. Full original CC sources now pass SVG-filter inspection before the
  calligraphic descriptor refusal; flowtext still stops at Band's blend metadata.
  Full validation: 834 VM/833 Node tests, clean format/fix/analysis and all twenty
  new independent transactions, including producer resource and text comparisons.
  This artboard task remains open pending those dependency owners.
  Retained brush descriptors now resolve plug-in/name identities independently
  of native artwork and artboard IDs. Known calligraphic, art/pattern and bristle
  layouts retain their complete literal fragments; manager-panel order and
  artwork tiles are checked. Calligraphic appearances retain typed parameters,
  owned strokes and matching `GObjRef` descriptors. Eight regressions cover all
  board operations, name escaping, references, unknown/executable data and limits.
  Twenty carrier transactions compare all 36 producer descriptor sections and
  six calligraphic references, plus the complete retained resource/text data.
  Six further transactions now exercise the complete original text_transforms
  program through creation, resize, reorder and removal, with exact independent
  Document and unselected-byte checks. The simple CC originals next require
  additional perspective-grid settings; flowtext still requires Band's blend
  owners. This artboard task remains open; no brush renderer was introduced.
  Full validation: 842 VM/841 Node tests, clean format/fix/analysis and all 26
  independent transactions, including the six complete-source lifecycle edits.
  **Final qualification:** saved Boolean perspective locks/ruler visibility and
  integer active-plane settings now remain exact. Resource-local paired K/A/B
  annotations retain both directly owned endpoint paths and their intermediate
  artwork, without recomputing a blend. Seven regressions cover all four board
  operations, local namespaces, malformed/missing pairs, attachment ownership,
  scalar types, immutable refusal and original limits. Thirty independently
  checked transactions use complete, unmodified producer programs from
  simple_cc_legacy, simple_v2020, text_transforms, flowtext and layers_and_sublayers.
  Every edited Document field, retained board dictionary, resource/text owner and
  unselected byte is checked against the prescribed predecessor. The five source
  PDFs retain pinned provenance and checksums; no setup substitution enables these
  edits. Native create/remove/resize/reorder, independent crop/drawing bounds,
  active/selection/history state, print-range identity remapping, explicit host
  page mappings and full/font-filtered header caches are now implemented and
  verified together. Final checks pass: 849 VM/848 Node tests, clean format/fix/
  analysis and 141 regenerated independent outcomes (30 complete-source, 54
  lifecycle, 20 state/rectangle, 20 print-selection and 17 mapped-save cases).
  Unknown dependency layouts still reject atomically. Editing advanced resource
  families belongs to later milestones; general Adobe reopening and the Reuters
  drawing body remain unqualified. Ordinary compound/clip semantic editing and
  narrowing other whole-source refusals remain the next separate tasks.
- [x] Support editing ordinary native compound paths and clipping relationships
  without treating a CC object's printable expansion as its authoritative model.
  **In progress:** `pathTopology` exposes ordinary compound/clip ancestry, mask
  controls and owned point counts. Atomic `editPaths` requests replace contours
  and local mask behavior while retaining paint, identities, metadata and group
  order. Counts follow effective paint/mask closure, and compound mask changes
  require every affected contour together. Host-supplied ink bounds remain
  independent of boards. Selected private/direct-shape/printing paths reject;
  complete CC neighbors remain exact. Nine regressions cover native controls,
  immutable batches, malformed ownership, original limits and 400-contour edits.
  Twelve independent synthetic edits and three checksum-pinned producer refusals
  pass. The producer shape compounds are derived; the Inkscape CC compounds still
  require imported SVG metadata qualification. Successful full-producer edits,
  general reparenting and broader relationship qualification remain outstanding;
  Adobe reopening remains unqualified.
  Validation: 858 VM/857 Node tests pass, followed by 19 focused VM/Node checks
  after caching retained-body inspection per immutable snapshot and adding the
  operation-specific capability entry. All fifteen independent cases pass again;
  formatting, fixes and analysis are clean.
  Compound creation/release now wrap or dissolve complete ordinary contour trees,
  including direct and grouped masks, without rewriting child state or identities.
  Parent metadata disposal and flag inheritance are explicit; removed identities
  undergo whole-source reference qualification. Complete CC and compact-text
  neighbors remain retained, while selected text or derived geometry rejects.
  Ten new regression cases and ten independent synthetic transactions cover these
  operations, including 200 disjoint compound releases. The task remains open for
  full-producer edits, clip-owner lifecycle and general relationship movement.
  Validation: 868 VM/867 Node tests pass; ten focused checks on both runtimes also
  cover the final refusal of text inside a released compound. All ten new and
  fifteen existing independent topology cases pass. Formatting, analysis, fix
  dry-run, Python compilation and diff checks are clean.
  Clipping creation/release now applies complete mask transactions, preserves
  independent nested scopes, synchronizes compound leaf kinds and restores saved
  contour attributes. Compound lifecycle also accounts for the `q/Q` scopes that
  become effective or ineffective across compound boundaries. Effective masks
  require an outer clip owner; unknown state and unsupported appearance changes
  reject. Eleven regressions and eleven independent transactions cover the new
  behavior. Nine transactions additionally preserve every contour and final state
  through the unchanged pinned Adobe prolog in Ghostscript, in printing and
  private-scalar projections. This remains format-data validation, not Adobe UI
  certification. Full-producer edits and general relationship movement remain open.
  Validation: 879 VM/878 Node tests pass, alongside all 36 independent topology,
  compound and clipping transactions. Formatting, analysis, fix dry-run, Python
  compilation and diff checks are clean.
  **Producer contour edits:** known imported SVG document/view metadata, group
  import flags and paired literal affine records can now remain exact during
  native contour edits. Literal non-neutral transparency assignments are retained
  without replay or composition. Ownership errors remain distinct from metadata
  schema limitations; metadata lifecycle and reference deletion are not implicitly
  enabled. Eight regressions cover masks, reference retention, malformed records,
  scalar modes, CC neighbors and limits. Six independent transactions now edit
  outer, inner or all five contours in the complete original Inkscape CC programs,
  including the current-version fixture. Their setup, identities, metadata,
  matrices, transparency state and all unselected source bytes remain exact.
  Broader producer lifecycle and general relationship movement remain outstanding;
  this does not qualify Adobe reopening.
  Validation: 887 VM/886 Node tests and all 40 independent topology/compound/clip
  cases pass. Eight focused checks on each runtime also cover the final style and
  conditional-owner guards. Formatting, analysis, fixes and diff checks are clean.
  **Contour relationships:** `moveContours` relocates or reorders atomic contour
  batches across ordinary, compound and clip owners. Counts, identities and exact
  metadata travel together; intervening source assignments stay in place. Both
  scalar projections preserve consumed and outgoing attributes, including shared
  compound paint at `*U`. Compound entry, parent flags and mask changes have
  explicit policies. Imported affine ancestors remain identical; no coordinate
  rebasing is inferred. Twelve regressions include derived insertion anchors,
  empty branches, mixed paint modes, hidden layers and 200-contour mask batches.
  Eleven independent transactions include four moves in complete original CC
  programs and 22 Adobe-prolog attribute checks through Ghostscript. Full owner
  movement and broader producer lifecycle remain outstanding; this task stays
  open and Adobe reopening remains unqualified.
  Validation: 899 VM/898 Node tests and all 51 independent topology, compound,
  clipping and movement cases pass. Formatting, analysis, fix dry-run, Python
  compilation and diff checks are clean.
  **Complete contour trees:** `moveContourGroups` moves disjoint ordinary,
  compound and clip owners to a group, layer or document root, with exact owned
  bytes and identities. Scoped attributes and deferred compound paint have
  separate read/write analysis. Unknown output is accepted only after proving
  it cannot reach a retained consumer, including across saved clipping scopes;
  unknown final values still reject. Thirteen regressions cover metadata,
  inheritance, count ownership, immutable failures and 100 masked-tree batches.
  Twelve independent transactions include four complete-producer moves into the
  named-view group and back to the original layer, plus 24 Adobe-prolog state
  projections. No source setup is replaced. Broader producer creation/dissolution
  and partial compound-branch movement remain open; Adobe reopening remains
  unqualified.
  Validation: 912 VM/911 Node tests pass, followed by ten focused capability
  checks on each runtime. All 63 independent topology/compound/clip/movement cases
  pass after regenerating the previous 51. Formatting, analysis, fix dry-run,
  Python compilation and diff checks are clean.
  **Complete-producer lifecycle:** imported compound creation/dissolution and
  clipping creation/release now retain qualified child metadata and literal
  transparency. Explicit parent disposal checks surviving named-view targets;
  missing/ambiguous/deleted references and discarded affine bases reject.
  Reference qualification retains known fonts, gradients, styles, palettes, local
  SVG filters, empty main/undo-free text engines and document provenance in their
  separate namespaces. Unknown/populated reference owners retain their guards.
  Released scopes can leave an unknown intermediate attribute only after proving
  it is overwritten before consumption in both interpretations, accounting for
  every released boundary and surviving saved scope. Ten new regressions and
  eight independent transactions exercise the two complete original Inkscape CC
  programs. Exact surviving bytes, contours/counts/masks and both scalar streams
  pass; sixteen Adobe-prolog projections check contour and final attributes.
  Partial compound-branch movement remains open; Adobe reopening is unqualified.
  Validation: 922 VM/921 Node tests pass, followed by 21 focused checks on each
  runtime for the final provenance-fragment guard. All 71 independent contour transactions
  and 32 reference-scope/resource cases pass after regeneration. Formatting,
  analysis, fix dry-run, Python compilation and diff checks are clean.
  **Final branch qualification:** ordinary branches now move within, out of or
  into qualified compounds. Exiting materializes deferred common paint; entering
  another compound explicitly adopts its appearance and paint mode while retaining
  contour closure. Literal source assignments remain exact, with additional replay
  accounting for clipping scopes that become active or inactive. Both scalar
  projections retain group flags, consumed paint and outgoing state; unknown-value
  proofs use the actual enclosing compound/clip scopes. Empty identified branches,
  nested compounds, mixed mask roles and incompatible compound grammar reject
  atomically. Twelve regressions include multi-leaf mask branches, unknown deferred
  consumption, source immutability, original limits and 100-branch batches.
  Sixteen independent transactions verify complete hierarchy, identities, geometry,
  counts, masks, scalar state and exact source patches, with 32 Adobe-prolog state
  projections through Ghostscript. Four moves use complete CC producer programs
  prepared only by adding two ordinary group delimiters around an existing contour;
  the independent verifier proves those preparations byte for byte. The qualified
  ordinary compound/clip editing task is complete; Adobe UI reopening remains
  unqualified, and narrowing unrelated whole-source refusals is the next task.
  Validation: 934 VM/933 Node tests pass. All 87 independent contour transactions
  pass after regenerating the preceding 71. Formatting, analysis, fix dry-run,
  Python compilation and diff checks are clean.
- [x] Narrow conservative whole-document refusals only after proving the selected
  object's inherited state and dependencies are isolated.
  **Retained gradient qualification:** bounded standalone `Bb/BB`
  instances now remain exact beside ordinary contour edits and movement. Each
  reference must resolve to one unconditional gradient definition in its own
  resource namespace. Complete geometry/count ownership is checked independently
  of legacy/CC gradient operands; paths spanning incomplete gradient consumption,
  state/metadata/group crossings and conditional/ambiguous resources still reject.
  Gradient contours remain derived, and complete native/printing shape pairs keep
  their previous ownership contract. Gradient effects remain unknown scalar
  barriers: geometry edits do not change state, while movement must prove its
  inherited and outgoing attributes without defaults. Nine regressions cover these
  rules, lifecycle neighbors, immutability, limits and 100 shared-resource instances.
  Seventeen independent outcomes include thirteen successful synthetic edits and
  four exact refusals. The complete original linear/radial CC fixtures still stop
  at their ATE 11 snapshots in that initial increment; the independent reader confirms that version and empty
  main/undo-free frame/story inventories. No setup substitution enables a success.
  Full source patches, gradient definitions/instances, ordinary hierarchy and
  scalar state pass, including sixteen Adobe-prolog projections for ordinary
  attributes only. That increment does not qualify gradient rendering or Adobe reopening.
  Validation: 943 VM/942 Node tests and all 104 independent contour outcomes pass
  after regenerating the previous 87. Formatting, analysis, fix dry-run, Python
  compilation and diff checks are clean.
  **Completed — empty ATE 11 isolation:** each independently owned main/undo-free
  snapshot now retains its empty frame/story namespaces and optional bounded
  composer descriptor. Unknown owners, opaque tokens, populated ATE 11 snapshots,
  malformed descriptors and dangling displays still reject. Eight regressions
  cover contour edits/movement, identified deletion, artboard lifecycle, mixed
  versions, exact binary preservation and aggregate source byte/node budgets.
  Six successful transactions edit two explicitly appended ordinary branches in
  the complete linear/radial CC producer programs. The independent verifier proves
  each preparation as one prescribed insertion; no original setup or artwork is
  substituted. Both text snapshots, gradient definitions/instances, private shape
  data and unselected bytes remain exact. The original derived contours continue
  to reject ordinary editing. The expanded gradient suite has 23 outcomes and 32
  Adobe-prolog state projections, with private source indices retained explicitly
  in the printing projection. The isolation task is complete for these qualified
  boundaries; unknown dependencies still require their own feature contracts in
  later milestones. This does not qualify populated ATE 11 editing, gradient
  rendering or Adobe UI reopening.
  Validation: 951 VM/950 Node tests pass, together with all 110 independent contour
  outcomes and 32 reference-scope/resource cases after regeneration. Formatting,
  analysis, fix dry-run, Python compilation and diff checks are clean.

**Acceptance:** nested groups, shared resources, hidden/locked objects, multiple
artboards and unselected opaque content retain identity and ordering after each
operation. No dangling references or partially updated alternate records remain.

## 3. Common appearances and geometry

**Starting point:** qualified live shapes support translation, rotation and
uniform scaling. Classic gradients have stop/focus edits, selected resource
isolation and relative placement. General appearance editing remains incomplete.

- [ ] Expose ordered multiple fills/strokes and selected appearance parts, shared
  style ownership, stroke alignment/dashes and supported native paint settings.
  In progress: `AiNativeAppearances` now retains complete ordered stack/chain
  trees, exact selected-part handles and shared/ambiguous/conditional style uses.
  Multiple and effect-local paints remain separate. Qualified stroke alignment,
  winding, literal process colors, overprint, width/cap/join/miter, dash and `Xd`
  assignments are exposed without composed values or inherited defaults. Unknown
  descriptors and source extensions remain available. The independent reader
  compares all 98 styles, 834 parts and 135 uses from six complete untouched CC
  programs plus one synthetic fixture.
  `updateSelected` now isolates qualified CC users under an explicit fresh name;
  `updateShared` requires every dependent user and a qualified whole-source
  reference scope. Exact paint-assignment and saved part-field changes attach all
  host-supplied printing groups and bounds atomically. Native geometry and saved
  alternatives remain unchanged. Alignment changes also require the host's label
  bytes when a saved DisplayString exists. Unknown effects, caches, unresolved
  following state and incomplete coverage reject. Capabilities report validation
  requirements, not unconditional editability. Eight independent synthetic
  transactions compare all original/edited trees and the exact full-file delta.
  Process-only `SimpleStyle` definitions now share the selected/shared editing
  contract through their separate paint payload. Explicit assignments determine
  outgoing state; disabled paints and inherited defaults are not inferred from
  `Xd`. Eight regressions cover isolation, shared changes, inherited dependencies,
  unused styles, complete-pair copy/removal, capability reporting and rejection
  of unknown, conditional or repeated owners. Geometry transforms retain their
  previous active-style boundary.
  Two complete original CC producer programs (`simple_shapes.ai` and
  `simple_shapes_cc.ai`) now qualify selected process-fill transactions without
  setup or neighbor substitution. Independent decoding covers every original and
  edited style/part/use; the entire byte delta permits only the copied style,
  selected reference, matching supplied printing paint and bounds spelling.
  Independent InkAI/Inkscape output confirms the white-to-cyan fill change:
  44,274 changed pixels per fixture, identical alpha/green/blue and no red
  increase. This qualifies those supplied expansions, not Adobe reopening or
  arbitrary effect rendering.
  `AiNativeAppearancePartChange.childOrder` now permutes every direct child of
  an existing stack or chain, preserving whole subtrees. Nested orders compose
  with paint/setting changes against the original handles. Private/ordinary
  boundary crossings, stale/foreign/missing/duplicate children and unresolved
  following state reject atomically. Pure permutations retain provably identical
  explicit noncolor scalar state only when all parts are visible and no inherited
  value is required; winding must also agree with each saved fill flag.
  Eight regressions cover these contracts. Three more synthetic transactions
  independently verify isolated/shared stack order and nested chain/stack order
  with simultaneous field changes, including the complete expected byte delta.
  Two further transactions reorder the complete producer programs' original
  stroke/conduit/fill stacks. Host-supplied printing places the existing inside
  stroke below a white rectangle following the native authoritative contour.
  Every output RGBA pixel matches a separately composed SVG reference; each file
  lightens 1,308 edge pixels. The expected antialiasing/alpha change is checked
  against that reference, while unselected artwork and native subtrees remain
  exact. This does not establish Adobe UI reopening or arbitrary effect output.
  `AiNativeAppearancePartChange.children` now replaces complete child lists with
  explicit retained handles, original snapshot copies and new immutable part
  definitions. It supports creation/removal/reparenting, extraction from removed
  ancestors and nested changes, while rejecting cycles, duplicate ownership,
  foreign handles and edits targeting removed/source-only parts. New process
  fills/strokes, stacks/chains and conduits have explicit settings; offset strokes
  require host label bytes. Source comments/private prefixes and copied subtrees
  remain exact. Expansion and parsing remain bounded. Newly introduced state
  is checked against following artwork; unchanged scalar proofs compare both
  original and resulting trees. Twelve regressions cover these contracts.
  Seven independent synthetic transactions verify all original/edited trees and
  the exact complete-file delta, including all authored kinds and process stroke
  spaces/alignment/settings. Two additional complete-producer transactions create
  a cyan fill above each original stack. Original native parts and printing paths
  remain exact, the copied styles grow from six to seven parts, and every output
  RGBA pixel matches a separate SVG composition above the original fill/stroke.
  The creation changes 44,274 pixels per fixture, including 1,308 green/blue edge
  pixels and 874 alpha samples. These checks qualify the supplied expansions;
  the synthetic lifecycle groups qualify serialization/state, not visual output.
  Shared edits now inspect complete retained pattern/symbol/brush resources and
  every palette alternative at complete-cell boundaries. Nested and newer-only
  branches remain exact; split operands, paints, gradients or palette boundaries
  reject. Resource-local style uses join the required coverage. Document scope
  retains observed recorded snapping flags, the PDF hyperlink-export flag and
  empty constraint arrays; populated constraints remain unqualified. Identity
  deletion keeps its stricter resource boundary. Nine regressions cover these
  contracts and source/limit preservation.
  A new synthetic shared transaction retains all resources and nested palettes
  with an exact independently checked byte delta. Six further transactions edit
  the original shared styles in both complete producer programs, covering color,
  order and new fills. All native inventories and complete-file deltas pass;
  each output matches every RGBA pixel of the corresponding selected edit.
  Independent projections additionally decode both 65-cell producer palette
  alternatives and all three synthetic nested paths. Actual edits use untouched
  complete sources, with no discarded setup or neighbors.
  `artworkFor(use:)` now binds qualified ordinary private contours to their
  separate printing groups without inventing live-shape parameters. Immutable
  `AiNativeAppearanceArtwork`/`AiNativeAppearanceReplacement` handles join the
  existing selected/shared API; mixed live-shape and ordinary users can be edited
  atomically. Optional object names, identities and rotation metadata stay exact.
  Lexical/version crossings, unknown metadata, stale/duplicate owners,
  inconsistent point counts and unresolved following dependencies reject.
  Following ordinary pairs and independent contours use the same qualified
  source boundary. Ten regressions cover these contracts, including limits.
  Six complete-producer transactions recolor the two ordinary strokes in each
  `stroke_styles.ai`, `fill_stroke_test_cc.ai` and `fill_stroke_test.ai` program.
  All original/edited styles, parts and uses pass independent decoding; exact
  whole-program byte oracles preserve all native geometry and neighbors.
  Every RGBA pixel matches a separate original-SVG stroke recoloring, with
  identical alpha. Centered strokes change 1,786/1,800 pixels; inside strokes
  change 3,594/3,573 pixels in both counted and uncounted sources.
  Full-source shared changes in these new producers still reject advanced dash
  dictionaries or `GenAIRecorded`. The corpus checks require those rejections;
  synthetic mixed/shared transactions pass. Resource/group/text users, broader
  producer support and unresolved state consumed by following `AI11Text` owners
  remain open.
  Validation: 1021 VM/1020 Node tests and all 40 corpus container outcomes pass.
  Six new complete-producer transactions pass independent byte/tree/pixel checks;
  the sixteen existing synthetic appearance edits and twelve previous complete
  producer transactions pass again. All 54 independent artboard lifecycle
  transactions passed after the preceding palette-scope change. The earlier
  98-style/834-part/135-use inventory and 37-source capability checks remain
  inspection evidence, not editing acceptance for the new producers. Formatting,
  analysis, fix dry-run, Python compilation and diff checks are clean.
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
