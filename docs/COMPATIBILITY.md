# Native Illustrator compatibility work

The target is native editing compatibility, starting with recent CC files and
then older formats. Decoding or preserving a feature is not evidence that it is
editable. Adobe Illustrator reopening remains a separate acceptance check.

## Implemented foundations

- PDF and legacy containers, exact legacy preservation, immutable snapshots and
  bounded syntax parsing.
- Native plain/zlib/Zstandard envelopes, shared-owner rewriting and independent
  original/rewritten byte comparisons. Zstandard uses published ZCodec 0.2.6.
- Native layers and source-backed flag/name edits; plain path geometry edits
  with explicit rejection of unresolved appearance dependencies.
- Hierarchical native dictionaries, arrays, objects, ASCII85 binary resources,
  source-backed scalar edits and typed native artboards.
- Source-backed private/printable paths, compound groups, live-shape/style
  associations and AI17 metadata alternatives. Atomic translation of five live
  shape families with solid and linear/radial gradient appearances, including
  expanded strokes and redundant native centers. Native gradient/paint records,
  synchronized printing matrices and isolated positional style copies. Eight
  independently checked translation fixtures.
- Self-contained AI7 creation for layers, groups and simple path appearance,
  checked with Ghostscript.
- Published PsCore 0.2.2 EngineData grammar reused by PsdKit and AiKit. Typed ATE fonts,
  styles, stories, UTF-16 runs and frame references; preserved unknown layout,
  source-backed style naming and bounded ASCII85 rewriting.
- Named CS and compact CC text keys, omitted run tables inheriting normal styles,
  bounded parent-style resolution and paragraph character defaults. Typed cached
  layout nodes and glyph IDs, frame matrices and paths. The expanded corpus has
  37 files, including transformed, linked-area, path and point text.
- Native UTF-16 content replacement with style inheritance, CR/forced-break span splitting,
  explicit cache invalidation, bounded expansion and rejection of unresolved
  auxiliary features. Twenty story edits checked by an independent decoder;
  composing the new display and PDF remains host work.
- Native character/paragraph overrides, selected-run splitting, inherited-feature
  restoration, paired point-size fields and separate inline style identities.
  Sixty formatting edits compared independently across the twenty stories,
  including whole-paragraph selections spanning forced line breaks;
  typography settings are authored, not implemented as a new compositor.
- Native font registration with stable existing indices, fresh identities,
  PostScript/TrueType metadata, signed variation coordinates and display lists.
  Sixty-four additions checked independently; font loading and embedding remain
  host responsibilities.
- Host-composed point/area frame, line and segment position writing, with source
  coverage, linked-frame ownership, explicit overflow, compact reordered ranges
  and automatic-hyphen maps. Seventeen layouts and fourteen hyphens checked
  independently; glyph shaping, path geometry and synchronized PDF remain pending.
- Point/area/path frame translation, including selected linked frames and their
  native confinement paths. Existing affine matrices and local glyph caches are
  preserved; 26 frames and 13 paths are checked independently, plus one partial
  linked-frame selection. Complex confinement appearances and synchronized PDF
  saves still require further work.

## Next native editing work

1. Extend live-shape editing beyond translation: resize/rotate/regenerate shape
   parameters, corners and dependent appearance geometry. Refine exact artwork
   bounds and support nested appearances and larger versioned alternatives.
2. Complete known/active styles, multiple fills/strokes, gradient stops/ramps, transparency,
   compound paths, clipping and appearance expansion without flattening editing
   data into a compatibility preview.
3. Extend ATE resource/story/run views into synchronized content and feature
   editing: complete advanced composition semantics, shape glyphs, regenerate
   frames and cached strikes, and synchronize printable/PDF output. Extend
   typography fixtures beyond Latin text and cover undo-free references.
4. Model linked/embedded raster data, meshes, brushes, patterns, symbols, effects
   and plug-in records with explicit editing contracts.
5. Synchronize native artwork and PDF compatibility output through the host scene
   integration, then validate reopening in Illustrator on representative files.
6. Extend legacy operator execution and native writing with bounded execution,
   resource handling and independent rendering checks.

## Evidence required for each addition

Use synthetic regression cases and pinned real fixtures, preserve data outside
the edited feature, run VM and Node tests, and compare with an independent
decoder or renderer. Record remaining unsupported semantics in `docs/AI.md`.
No compatibility percentage is inferred from the number of accepted files.
