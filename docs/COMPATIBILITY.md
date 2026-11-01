# Native compatibility status

AiKit implements bounded Illustrator data inspection, source-preserving native
editing and serialization. Rendering, composition and tools belong to the host;
Focale integration is deferred. See [the responsibility split](HOST.md) and the
[detailed format contracts](AI.md).

## Implemented data contracts

- PDF/PostScript container detection, immutable snapshots and exact legacy bytes.
- Plain, zlib and Zstandard native envelopes, shared-owner rewriting and saving
  with a host-supplied PDF. Zstandard uses published ZCodec 0.2.6.
- Atomic multi-program saves preserve existing page identities and native graph
  dependencies; stale/foreign sources and implicit page remapping reject.
- Native layers, plain paths, hierarchical records and artboards.
- First/root/nested ordinary layer, group and path creation without existing
  siblings; qualified removal, copying, reordering and reparenting preserve
  ownership, identities and both state projections. Path creation accepts explicit
  geometry/process paint and host-computed bounds, without generating a PDF.
- Source-owned ruler units, canvas scale and coordinate metadata; artboards retain
  document ownership/order and separate artboard/text ruler origins.
- Independent active-artboard, selection, crop and saved LastArtboardID fields;
  qualified native rectangle resizing with explicit crop/ruler choices. General
  artboard lifecycle and synchronization of page mappings/cached headers remain open.
- Source identities, ordered record fields, saved artboard/XML artwork identifiers
  and lexical owners. Version alternatives remain separate; qualified style and
  gradient references report missing, ambiguous and conditional ownership.
- Source-local capability reports distinguish typed data, qualified operations,
  opaque preservation, unsupported structures, malformed data and inspection limits.
- Ordered named appearance trees retain multiple fills/strokes, exact part and
  parameter ownership, shared uses, local visibility, qualified stroke alignment
  and literal paint/dash assignments. Qualified active-style and process-only
  SimpleStyle changes synchronize
  selected or shared CC users with host-supplied printing groups, including saved
  alignment labels. Stack/chain child permutations support nested orders and
  simultaneous source setting edits without dropping or reparenting subtrees.
  Two complete CC programs qualify selected process-fill and stack-order edits
  with independent native/printing comparisons. Unknown effects remain preserved;
  other user families, part creation/removal/reparenting and global complete-producer appearance
  editing are still open. Conditional setup inventories and unresolved following
  text state remain explicit rejection boundaries.
- Qualified CC live-shape translation, rotation and uniform scaling, including
  dependent printing geometry, gradients and shared-style isolation.
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
- Gradient stops, printing ramps supplied by the host, focus, selected resource
  isolation and relative placement edits.
- Native mesh inventory, process-color/ink-tint/opacity vertex edits with shared
  corner updates; source geometry and unknown data remain preserved.
- Embedded raster samples and alpha, replacement pixels, linked placements,
  explicit previews, relinking and affine geometry edits.
- Catalog XMP dependencies and source-preserving resource updates.
- Typed AI7 creation with layers, groups and simple path appearances.

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

No Adobe Illustrator reopening validation or native Focale integration acceptance
has been performed. A PDF view, preserved private record or accepted file does
not establish native editability. Do not infer a compatibility percentage from
fixture or test counts.
