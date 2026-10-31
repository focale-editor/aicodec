# AiKit external corpus

The manifests pin source URLs, revisions, sizes, SHA-256 checksums, licensing and
expected outcomes. The main manifest contains 37 accepted fixtures. Downloads
under `files/` and generated data under `output/` are ignored and excluded from
publication. Source artwork is not redistributed; consult its manifest license
before copying it elsewhere.

Run from the package root. Missing files and unexpected outcomes fail checks;
ordinary `dart test` remains offline and independent of this optional corpus.

```sh
python3 tool/fetch_corpus.py
dart run tool/check_corpus.dart
dart run tool/check_native_corpus.dart
python3 tool/verify_native.py
```

The last check uses Python zlib and the system `zstd` executable to recover native
envelopes independently. To verify downloads without network access or writes:

```sh
python3 tool/fetch_corpus.py --verify-only
```

## Independent reader

Checks using `--inkai-source` require this unchanged external checkout:

```sh
git clone https://gitlab.com/inkscape/extras/extension-ai.git /tmp/extension-ai
git -C /tmp/extension-ai checkout 1a5f42a0b0407fc869e032420570682048810108
```

Keep the checkout outside AiKit. Use a Python environment with inkex, Pillow,
lxml, pypdf 3.x and zstandard. External SVG comparisons require Inkscape; XMP
preservation checks additionally use ExifTool and Poppler. Ghostscript decodes
path string operands in the relinking verifier. No external renderer is a
runtime dependency of AiKit.

The tools compare native data and serialization. They do not package edited
programs with stale original PDF pages. The former native-to-PDF exporter and
its dedicated comparisons were removed. PDF compatibility generation belongs
to the application; see [the host contract](../../docs/HOST.md).

## Native text and shapes

Capability reports check all 37 exact extracted sources and catalog/page owners
with pypdf and independent compression decoding. The pinned native reader checks
41 layer headers and 181 non-private paths, including text-frame confining art.
Opaque findings do not confer editing support. The AI8 linked-image layout is
explicitly unsupported by the binary raster model. These are inspection checks,
not a claim that all reported objects are editable.

```sh
dart run tool/check_native_capabilities.dart
python3 tool/verify_native_capabilities.py --inkai-source /tmp/extension-ai
```

Save checks rename layers without altering painted geometry, retaining existing
PDF artwork and adding an unused host-supplied resource. Independent extraction
and parsing verify 31 pinned PDF fixtures plus two synthetic partial/batch saves,
35 exact native programs, shared owners, opaque metadata and supplied resources.
The synthetic documents include two native artboards and independent programs;
they test serialization, not visual equivalence or Adobe reopening.

```sh
dart run tool/check_native_saves.dart
python3 tool/verify_native_saves.py --inkai-source /tmp/extension-ai
```

After `check_native_corpus.dart`, verify layer/native preservation, 32 ATE payloads,
20 content edits, 60 feature edits, 64 font registrations, 17 supplied layouts
and frame translations. Twenty explicit layout invalidations additionally check
that source text, resources and unselected stories remain unchanged. Text
composition is supplied data, not glyph rendering.
Eight live-shape translation fixtures also compare independently converted SVGs.

```sh
python3 tool/verify_native_text.py --reference /tmp/extension-ai
python3 tool/verify_live_shapes.py --inkai-source /tmp/extension-ai
```

Rotation and uniform scaling use the core fixtures plus three files from
`rotation_manifest.json`. Each has 22 variants across eleven files. Independent
parsing checks native parameters, centers, gradients, frame metadata and retained
resources; external SVG comparisons check transformed geometry. Two irregular
corner variants use printing curves because the reader cannot render their
native path effect. Empty renders fail validation.

```sh
python3 tool/fetch_corpus.py --manifest rotation_manifest.json
dart run tool/check_live_shape_rotation.dart
python3 tool/verify_live_shape_rotation.py --inkai-source /tmp/extension-ai
dart run tool/check_live_shape_scale.dart
python3 tool/verify_live_shape_scale.py --inkai-source /tmp/extension-ai
```

## Native gradients

Resource checks inspect 378 definitions, 1,103 stops and 725 printing intervals.
They verify edited stops, host-supplied ramps, coverage and retained geometry.
Focus checks compare 45 printing instances and 173 authoring notes across the
37 fixtures. Isolation and placement use the 15 linear/nine radial CC shapes,
checking selected/unselected bindings, relative parameters and printing caches.
External SVG checks remain for qualified color and isolation edits.

```sh
dart run tool/check_native_gradients.dart
python3 tool/verify_native_gradients.py --inkai-source /tmp/extension-ai
dart run tool/check_native_gradient_focus.dart
python3 tool/verify_native_gradient_focus.py --inkai-source /tmp/extension-ai
dart run tool/check_live_shape_gradients.dart
python3 tool/verify_live_shape_gradients.py --inkai-source /tmp/extension-ai
dart run tool/check_live_shape_gradient_placement.dart
python3 tool/verify_live_shape_gradient_placement.py --inkai-source /tmp/extension-ai
```

## Native meshes

`mesh_manifest.json` pins one public CC 21.1 educational example with no identified
redistribution license. It and all derived artwork remain ignored/unpublished.
Checks compare 180 patches, 720 corners, extra anchors, source spans, typed inks
and 208 logical vertices with an independent restricted-format Python reader.
Selected process-color, named-ink tint and opacity edits must preserve every
unselected field and surrounding byte. The PDF ink-order check matches native
NChannel components to original Adobe tensor corners; it does not interpolate,
tessellate or render meshes.

```sh
python3 tool/fetch_corpus.py --manifest mesh_manifest.json
dart run tool/check_native_meshes.dart
python3 tool/verify_native_meshes.py
python3 tool/verify_native_mesh_paint.py
python3 tool/verify_native_mesh_inks.py
```

## Raster data and linked placements

Five core fixtures contain 24 images and 20 alpha planes. Native checks compare
sample bytes, placement matrices, translations and 72 pixel/resolution edits.
`raster_manifest.json` adds two deliberately damaged UTF-8-transcoded files;
parsing must reject at the computed boundary without scanning for later markers.

```sh
python3 tool/fetch_corpus.py --manifest raster_manifest.json
dart run tool/check_native_rasters.dart
python3 tool/verify_native_rasters.py --inkai-source /tmp/extension-ai
dart run tool/check_native_raster_edits.dart
python3 tool/verify_native_raster_edits.py --inkai-source /tmp/extension-ai
```

`placement_manifest.json` pins intact `image_linked.ai` from revision
`41bac2967b0f2bd80bc14fce9c8c0dea01283536` as `image_linked_original_cc.ai`.
The later transcoded copy remains a separate rejection fixture. The checks verify
277,504 ARGB preview bytes, translation and three native embedding variants using
explicit preview or host-supplied CMYK samples. Five setup images stay unchanged.
Relinking verifies paths, refreshed/removed previews and preserved geometry.
Affine geometry checks cover 66 embedded and three linked edits, retained pixels,
identities and metadata; two private fuzzy-mask images reject the edit.
Run placement generation before the affine geometry checker.

```sh
python3 tool/fetch_corpus.py --manifest placement_manifest.json
dart run tool/check_native_placements.dart
python3 tool/verify_native_placements.py --inkai-source /tmp/extension-ai
dart run tool/check_native_relinks.dart
python3 tool/verify_native_relinks.py --inkai-source /tmp/extension-ai
dart run tool/check_native_image_geometry.dart
python3 tool/verify_native_image_geometry.py --inkai-source /tmp/extension-ai
```

## Catalog XMP preservation

`xmp_manifest.json` pins Adobe's CS2 `BlueSquare.ai` and ExifTool's `XMP3.xmp`.
The latter is attached as a synthetic metadata carrier. lxml/ExifTool verify
relinked metadata, pypdf checks saved packets and Poppler verifies that existing
PDF artwork is unchanged. This is not a native renderer or a real linked-asset
integration test.

```sh
python3 tool/fetch_corpus.py --manifest xmp_manifest.json
dart run tool/check_xmp_metadata.dart
python3 tool/verify_xmp_metadata.py
```

These checks establish the documented native data contracts only. Adobe
Illustrator reopening, complete effect fidelity and Focale integration remain
separate acceptance work. See [the technical reference](../../docs/AI.md).
