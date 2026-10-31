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

## Next native editing work

1. Extend live-shape editing beyond translation: resize/rotate/regenerate shape
   parameters, corners and dependent appearance geometry. Refine exact artwork
   bounds and support nested appearances and larger versioned alternatives.
2. Complete known/active styles, multiple fills/strokes, gradient stops/ramps, transparency,
   compound paths, clipping and appearance expansion without flattening editing
   data into a compatibility preview.
3. Interpret ATE text documents, resources, stories, style runs, frames and layout
   records. Reuse the shared Adobe text-engine work in Focale packages where its
   contracts fit; preserve unknown fields and validate run/index consistency.
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
