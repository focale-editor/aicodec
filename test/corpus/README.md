# AiCodec external corpus

The manifests retain pinned source URLs, revisions, sizes, SHA-256 checksums,
licensing and expected outcomes. The main manifest contains 40 fixtures.
Downloaded artwork in `files/` and generated results in `output/` remain ignored
and excluded from publication. Consult each source license before redistribution.

## Maintained tools

Run these seven repository tools from the package root. They cover inspection,
source preservation and broad corpus regressions; individual editing scenarios
belong in the offline Dart tests.

| Tool | Purpose |
| --- | --- |
| `tool/inspect_ai.dart` | Inspect one AI container and its native blocks or PostScript tokens. |
| `tool/fetch_corpus.py` | Download pinned fixtures or verify existing sizes and hashes. |
| `tool/check_corpus.dart` | Decode, write and reopen every main-manifest file; require exact legacy bytes and native private-block preservation. |
| `tool/check_native_corpus.dart` | Exercise native extraction, layer/artboard edits, text resources/layout and shape translation on producer files. |
| `tool/verify_native.py` | Independently decompress original and edited native envelopes. |
| `tool/verify_native_text.py` | Compare text resources, edits, ranges, fonts and layout with the pinned external reader. |
| `tool/verify_live_shapes.py` | Independently compare translated native geometry and rendered printing data. |

## Container and native checks

Dart, Python 3 and the `zstd` executable are required. Fetching is explicit:

```sh
python3 tool/fetch_corpus.py
python3 tool/fetch_corpus.py --verify-only
dart run tool/check_corpus.dart
dart run tool/check_native_corpus.dart
python3 tool/verify_native.py
```

The checkers fail on missing inputs, unexpected outcomes and changed preserved
payloads. Reports and generated documents go to `test/corpus/output/`; remove
that directory before a run when fresh artifacts are required.

For a single file:

```sh
dart run tool/inspect_ai.dart test/corpus/files/simple_shapes_cc.ai
```

## Independent text and shape checks

Use an unchanged checkout of the pinned Inkscape Illustrator reader:

```sh
git clone https://gitlab.com/inkscape/extras/extension-ai.git /tmp/extension-ai
git -C /tmp/extension-ai checkout 1a5f42a0b0407fc869e032420570682048810108
```

Keep it outside AiCodec. These optional checks need a Python environment with
inkex, Pillow, lxml, pypdf 3.x and zstandard. The shape comparison also requires
Inkscape on `PATH`. Neither the reader nor renderer is a runtime dependency.
After `check_native_corpus.dart` has produced its report and native programs:

```sh
python3 tool/verify_native_text.py --reference /tmp/extension-ai
python3 tool/verify_live_shapes.py --inkai-source /tmp/extension-ai
```

The tools check the reader revision and reject modified tracked source. Text
checks cover the main corpus's available stories. Shape checks use eight pinned
files with explicit expected path/live-shape counts. These are bounded
serialization and rendering checks, not Adobe Illustrator reopening certification.

## Offline regressions

```sh
dart analyze
dart test
dart test --platform node
```

These tests run without downloaded artwork. They retain the feature-level cases
for appearances, resources, groups, artboards, meshes, images, text, gradients,
metadata, bounded parsing and repeated saves. New regression cases should extend
these tests instead of adding a paired generator/verifier for each operation.

The specialized corpus scripts were removed after the general checks and host
verification were separated. Their former output directories are not maintained
acceptance commands. Historical evidence remains in Git; this guide lists the
currently reproducible checks.

## Additional source manifests

These manifests retain producer evidence and licensing for optional investigation.
They can be downloaded with `python3 tool/fetch_corpus.py --manifest <filename>`;
add `--verify-only` to avoid downloads. The general checkers above use
`manifest.json`, not these supplementary manifests.

| Manifest | Entries |
| --- | ---: |
| `manifest.json` | 40 |
| `document_manifest.json` | 9 |
| `artboard_manifest.json` | 6 |
| `rotation_manifest.json` | 3 |
| `raster_manifest.json` | 2 |
| `xmp_manifest.json` | 2 |
| `placement_manifest.json` | 1 |
| `mesh_manifest.json` | 1 |
| `direct_shape_manifest.json` | 1 |

## Focale export verification

Focale owns generation of native printing/PDF artwork and its independent export
checks. The maintained command and its helper modules now live in the Focale
repository at `tool/validation/verify_ai_documents/`. Its README documents fixture
generation, dependencies and the single verification entry point. AiCodec does
not require a Focale checkout for its own tests or corpus checks.
