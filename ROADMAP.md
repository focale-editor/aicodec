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
- [ ] Add artboard creation, removal, resize and reorder with a declared mapping
  to host-supplied PDF pages. Artboards, crop bounds and drawing bounds stay distinct.
  **In progress:** `AiNativeArtboards` now retains explicit document ownership,
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
  also cover rejection of ambiguous saved UUID encodings. The task remains open:
  artboard-specific dependency isolation, print-range remapping, explicit host
  PDF-page mapping and synchronized cached `AIMetaData` headers still require
  implementation and checks. No host integration or native renderer was added.
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
