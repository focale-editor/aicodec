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

Document settings use the 37 baseline sources and nine additional CC fixtures in
`document_manifest.json`: moved ruler origins, millimeter/centimeter display units
and large canvases with scale 10. The unchanged independent parser verifies 207
numeric header fields, 31 artboards with document/order/identifier ownership and
32 text-document origins across 46 sources. Missing values remain absent. These
are metadata checks, not object lifecycle or PDF page-mapping qualification.

```sh
python3 tool/fetch_corpus.py --manifest document_manifest.json
dart run tool/check_native_document_settings.dart
python3 tool/verify_native_document_settings.py --inkai-source /tmp/extension-ai
```

Structure inspection uses the same 46 sources. The independent reader verifies
220 private/printable paths, 50 layers, 109 ordinary/compound groups, 55 version
blocks, 659 style/gradient declarations, 1,274 uses and 195 saved artboard/XML
identifiers, together with lexical containment/order. Complete resource counts
include setup symbols/patterns and both saved branches. For this count only, the
verified version delimiter comments are removed from an inspection copy because
the upstream parser otherwise discards older branches. Exact unmodified source
fragments separately verify each path, boundary, resource and reference.
Fake delimiters, internal name conditions, immutability, malformed layouts and
budget limits have VM/Node regressions. These are ownership/inventory checks;
existing live-shape tests qualify authoring/printing associations, and Adobe
reopening and general structural edits remain unqualified.

```sh
dart run tool/check_native_structure.dart
python3 tool/verify_native_structure.py --inkai-source /tmp/extension-ai
```

Layer inspection and empty insertion use the same 46 pinned sources. The
unchanged independent reader verifies 50 original layer headers, names, saved
identities, panel-expansion flags, wrappers and direct parents/children. Forty
inserted variants cover root and nested owners, including hidden and locked
sublayers; the root count excludes nested layers. Ten Inkscape-derived headers
contain additional private dictionary fields and reject insertion explicitly.
Byte checks permit only insertion, the applicable root-count change and explicit
saved-view invalidation. All original artwork, private records and state remain
exact. VM/Node cases additionally qualify classic bare layers, raw name bytes,
view continuations, stale handles, unknown/conditional metadata and limits. These
checks do not qualify removal, duplication, movement or Adobe reopening.

```sh
dart run tool/check_native_layers.dart
python3 tool/verify_native_layers.py --inkai-source /tmp/extension-ai
```

Layer movement uses `layers_and_sublayers.ai`, `simple_shapes.ai` and
`simple_shapes_cc.ai`, plus a checksum-pinned synthetic source with ordinary
nested artwork and changing paint. Twelve moves cover sibling reordering,
nonadjacent slots, backward movement, empty destinations and lifting complete
subtrees to the root. Two independently verified insertion prerequisites supply
empty layers that are moved into unchanged opaque artwork. The pinned reader
checks exact identities, complete tree structure, path geometry/counts and known
effective paint/lock/visibility assignments, without resetting paint at layer
boundaries. Byte checks require the complete copied subtree and constrain all
added assignments to original source values; unselected bytes remain exact.
Root counts and explicit view invalidation are checked in the same transaction.
VM/Node regressions additionally cover process-color alternatives, dashes, prefix
metadata, malformed/unknown state, explicit parent inheritance and a 100-layer
batch. The same script additionally verifies two recent native identified
sublayer/subtree copies and one synthetic batch copy, changing only requested
name/identity string spans. Three synthetic identified removals cover complete,
nested and all-root deletion with retained outgoing state. A pinned anonymous AI7
source supplies one further insertion/removal regression. In total, 22 transactions
cover 12 movements, three duplications, four removals and three insertion
prerequisites. Identity-removal qualification now includes the document-only CC
cases described below; unknown document/resource references still reject instead of
being assumed absent. Adobe reopening remains unqualified.

```sh
dart run tool/check_native_layer_lifecycle.dart
python3 tool/verify_native_layer_lifecycle.py --inkai-source /tmp/extension-ai
```

Ordinary path lifecycle uses the anonymous free path in pinned `simple_shapes.ai`
and `simple_shapes_cc.ai`, plus checksum-pinned counted, grouped and state sources. Sixteen
variants cover insertion, duplication, removal, sibling reordering and movement
between ordinary groups. Reordering starts from an independently verified
insertion result. The unchanged native reader verifies geometry, paint, point
counts, effective attributes, owner flags and order; byte checks preserve
every unselected region and allow only supplied ink-bound expansion. Private live
shapes and their records remain untouched. Synthetic cases cover counted closed
endpoints, hidden/locked owners, shared state and emptied groups. Three added
variants qualify reordering and movement in both directions across different
gray/line/dash/lock/visibility assignments. Copies retain their original geometry
and counts; extra assignments must exist in the original source. Changed ancestor
flags require explicit destination inheritance. VM/Node cases additionally cover
all supported state components, process-color alternatives, unknown/malformed
state, output/token limits and a 150-path batch. These cases do not
qualify an Adobe writer profile. These checks do not establish Adobe reopening,
group/layer lifecycle or arbitrary referenced-object editing.

```sh
dart run tool/check_native_path_lifecycle.dart
python3 tool/verify_native_path_lifecycle.py --inkai-source /tmp/extension-ai
```

Ordinary group lifecycle uses the same two pinned recent files. Their free path
is first grouped with its consumed point count and intervening paint assignments;
the independently verified result then supplies duplication, removal and
ungrouping cases. A checksum-pinned synthetic source adds nested groups, changed
gray/line/dash/lock/visibility state, reordering and reparenting. All 13 variants
are decoded with the unchanged independent reader. Checks compare complete object
trees, flags, path geometry/counts, effective attributes and layer outgoing state.
Exact byte checks constrain edits to selected boundaries/subtrees or insertion
points; added assignments must come from the original source. VM/Node tests add
process-color syntax, unknown-state refusal and a 200-group batch. These checks
do not qualify Adobe reopening or referenced/derived group lifecycle.

```sh
dart run tool/check_native_group_lifecycle.dart
python3 tool/verify_native_group_lifecycle.py --inkai-source /tmp/extension-ai
```

Cross-layer artwork movement uses the same two pinned recent sources and a
checksum-pinned synthetic program. Four independently checked prerequisites
insert empty layers and group real ordinary paths. Ten movements then transfer
paths/groups to those empty layers or move them forward/backward among nested
hidden/locked synthetic owners. The unchanged external parser verifies complete
trees, own paint/object flags, destination ownership and retained layer identities,
headers, counts and panel declarations. Byte checks allow only the selected
object/count spans, retained outgoing group assignments and copied source state.
No host rendering is involved. VM/Node tests additionally cover unlayered art,
empty groups, stale destinations, malformed metadata, unknown state and budgets.
Referenced/derived-object lifecycle and Adobe reopening remain unqualified.

```sh
dart run tool/check_native_artwork_movement.dart
python3 tool/verify_native_artwork_movement.py --inkai-source /tmp/extension-ai
```

Attached object metadata uses the existing pinned `layers_and_sublayers.ai`
fixture and a checksum-pinned synthetic source with observed XML identity/name
syntax. The external reader verifies five synthetic transactions: path/group
copies with fresh IDs, anonymous deletion, sibling reordering and reparenting.
Checks bind every reported object/dictionary/identifier/count span to the external
parse, compare complete trees and effective paint, and require exact unselected
bytes and source assignment provenance. Five real CC path/group copies, removals
and reordering cases now preserve their bound panel flag and default `XW` style.
Dissolution accepts the qualified neutral mode-nine reset; named or nondefault
style applications still reject. Five further checksum-pinned synthetic
transactions verify nested panel/style metadata and retained path opacity. These
16 cases do not establish general referenced-object editing or Adobe reopening.

```sh
dart run tool/check_native_objects.dart
python3 tool/verify_native_objects.py --inkai-source /tmp/extension-ai
```

Mixed layer/artwork identity lifecycle uses a separate checksum-pinned synthetic
program with nested hidden layers, identified groups/paths, anonymous metadata
and changing paint. Six transactions cover root/batch copies with new layer and
artwork IDs, path/group removal, subtree deletion and removal of all roots. The
unchanged external parser checks both inventories, complete topology, metadata,
point counts, effective state, layer declarations and exact unselected bytes.
The original source has only qualified declarative owners. Four additional
transactions inject an unknown `XMLUID` owner into this source and the pinned
`units-20x40mm_origin_topleft_CC.ai` Document: each allows a distinct fresh copy
and refuses collision with the injected value. The reader independently binds
the injected owner; exact source checks prove provenance and preservation. The
ten transactions do not establish arbitrary reference decoding or Adobe reopening.

```sh
dart run tool/check_native_identity_lifecycle.dart
python3 tool/verify_native_identity_lifecycle.py --inkai-source /tmp/extension-ai
```

Document reference qualification reuses all nine CC files in
`document_manifest.json`. Each identified-layer removal retains exact document,
artboard, profile, header and trailer bytes outside the declared layer/count/view
edits. The unchanged reader verifies every document source span, decoded metadata,
empty reference tables, hierarchy and outgoing state. LittleCMS opens all nine
retained real ICC profiles. Two injected references (an unknown document field
and a nonempty exportable-assets table) must reject with exact source preservation.
A checksum-pinned synthetic source adds identified path/group/subtree removal
beside known document metadata. The 14 transactions qualify this explicit schema;
unknown document fields and unqualified style/text/plug-in dependencies remain unsupported.

```sh
dart run tool/check_native_reference_scope.dart
python3 tool/verify_native_reference_scope.py --inkai-source /tmp/extension-ai
```

Mixed resource/reference qualification uses four source pairs/styles/gradient
fragments from the pinned shape and gradient files and the complete pinned
`units-20x40mm_origin_topleft_CC.ai` document. Each declared assembly is rebuilt
independently from its original native byte spans and explicit initial state;
the reader verifies the selected donor pair, style and gradient records. These
are derived mixed fixtures. The complete four donor files remain exact refusal
cases because their other setup owners still require qualification.
The 18 transactions include four derived-real and six synthetic removals, four
full-source refusals and four synthetic reference/identity refusals. Selected
path/group/layer/pair ownership, unselected bytes, retained style/gradient records,
both metadata branches, scalar state and layer count/view edits are checked
independently. SVG checks compare both views of the derived real fixtures and
printing views of the synthetic fixtures after removing exactly the selected
subtree. Native synthetic version-branch SVG remains unqualified. No source
artwork or generated output is published, and no Adobe reopening is inferred.

```sh
dart run tool/check_native_reference_resources.dart
python3 tool/verify_native_reference_resources.py --inkai-source /tmp/extension-ai
```

Mixed group/layer removal uses declared wrappers around five complete pinned CC
programs and four of the declared document/resource assemblies above. Exact
recipes retain the original pair bytes, setup resources and unrelated artwork;
new layer wrappers explicitly update the root count. These are derived ownership
fixtures, not original Adobe-authored parent groups or newly qualified complete
donor-layer deletions. The 22 fixed transactions contain nine derived-real and
eight synthetic removals plus five exact refusals. The independent reader binds
the selected owners, checks both saved metadata branches, exact retained bytes,
scalar order/privacy, native flags and layer count/view changes. It compares
native/printing SVG for real-derived fixtures and printing SVG for synthetic
versioned fixtures. Synthetic native SVG and Adobe reopening remain unqualified.

```sh
dart run tool/check_native_subtree_removal.dart
python3 tool/verify_native_subtree_removal.py --inkai-source /tmp/extension-ai
```

Mixed parent copies reuse the same wrapper construction and pinned sources,
selecting later complete pairs where their inherited inputs are known. The 23
fixed transactions cover eight derived-real and ten synthetic copies plus five
refusals, including an unresolved first opacity pair. Every copied XML ID and
optional layer name is bound to its original token; only fresh caller-supplied
names and source-derived input assignments may differ from the selected bytes.
Both saved alternatives, exact unselected bytes, native flags and native/printing
SVG for real-derived sources are checked independently. Synthetic printing SVG
retains the documented native version-branch limitation. A follow-up translation
checks that a copied shape remains editable beneath qualified parent metadata,
including private/printing geometry and unchanged older metadata. No Adobe
reopening or application rendering is inferred.

```sh
dart run tool/check_native_subtree_copy.dart
python3 tool/verify_native_subtree_copy.py --inkai-source /tmp/extension-ai
```

Mixed subtree reordering uses declared nested wrappers around every complete pair
in four existing pinned sources. Original pairs, resources and other source bytes
remain exact in the derived fixtures; wrapper names/identities and layer headers
are independently reconstructed. The 43 fixed transactions cover 24 derived-real
and seven synthetic permutations, four unchanged orders and eight refusals. One
synthetic parent contains several complete pairs. Checks bind complete sibling
owners, both metadata alternatives, exact moved/unselected bytes, source-derived
boundary replay, native/printing flags and the requested SVG parent order. Shared
SVG resources are resolved at their uses; the existing disabled-stroke exception
also requires identical librsvg pixels. Synthetic native SVG and Adobe reopening
retain their documented qualification limits.

```sh
dart run tool/check_native_subtree_reordering.dart
python3 tool/verify_native_subtree_reordering.py --inkai-source /tmp/extension-ai
```

Mixed subtree movement shares the same declared real wrappers and pinned original
source fragments. Its 51 fixed transactions cover 24 derived-real and 16 synthetic
moves plus 11 exact refusals. Synthetic sources add populated/empty destinations,
cross-layer group moves, complete layer nesting/lifting and a parent containing
several pairs. The independent reader binds the requested complete-owner parent
tree, all ordinary/paired contour flags, both metadata alternatives, exact moved
and unselected bytes, ordered state retained at the old location, input/output
replay at the destination and layer root counts. Native/printing SVG for real
sources and synthetic printing SVG follow the declared whole-parent movement,
resolving resources at their uses. Existing disabled-stroke pixel checks and the
synthetic native version-branch limitation remain; no Adobe reopening is inferred.

```sh
dart run tool/check_native_subtree_movement.dart
python3 tool/verify_native_subtree_movement.py --inkai-source /tmp/extension-ai
```

Direct live-shape lifecycle reuses six files in `manifest.json` and
`rotation_manifest.json`; `direct_shape_manifest.json` adds the pinned `styles.ai`
fixture with its source attribution. Fourteen real-file copies/removals retain
direct rectangle/ellipse parameters, rounded corners, opacity and unrelated
private/printing/style records. Seven checksum-pinned synthetic transactions
cover identified path/group copies and removals, cross-layer movement and layer
subtree copy/removal. The unchanged native reader compares complete parsed
programs, parameter dictionaries, point counts, exact byte edits and layer
inventories; synthetic checks also verify full object trees, identity maps and
effective paint. These 21 transactions qualify existing direct shapes, not new
shape creation, separate authoring/printing bundles or Adobe reopening.

```sh
python3 tool/fetch_corpus.py --manifest direct_shape_manifest.json
dart run tool/check_native_direct_shapes.dart
python3 tool/verify_native_direct_shapes.py --inkai-source /tmp/extension-ai
```

Separate authoring/printing pair duplication reuses five pinned files from
`manifest.json`. Fourteen successful real-file transactions cover ellipses,
polygons, stars, lines and linear/radial gradient pairs in four files; four
first-object refusals include `opacity.ai` and retain exact original bytes.
Four checksum-pinned synthetic copies cover batches, separate saved identities
and distinct native/printing flags. The unchanged reader independently binds the
22 requested transactions to complete pairs, native parameters, saved alternatives,
counts and style references. Exact insertion checks retain all unselected bytes;
source flag checks cover values ignored by the reader's SVG conversion. Both
native and printing SVG trees are checked for the real-file copies; synthetic
copies check printing SVG plus independently decoded newer/older dictionaries.
The pinned SVG dispatcher ignores lists returned for those version alternatives,
so synthetic native SVG is not used as acceptance evidence. Compared SVG trees
must equal the original with precisely the selected objects duplicated, including
resolved gradient and path-effect resources. This
does not qualify native Adobe reopening or other lifecycle operations on pairs.

```sh
dart run tool/check_native_shape_lifecycle.dart
python3 tool/verify_native_shape_lifecycle.py --inkai-source /tmp/extension-ai
```

Complete-pair removal reuses the same five pinned real files and seven
checksum-pinned synthetic sources. The fixed 27 transactions cover 17 real-file
and seven synthetic removals (71 pairs), plus three exact refusals for inherited
style state, unknown references and ambiguous identities. Each replacement gap
must contain precisely the independently parsed original state assignments and
unanimous visible style scalars; all bytes outside those gaps remain exact.
Retained pairs, both metadata alternatives and native owner flags are checked
separately. Real-file native/printing SVG and synthetic printing SVG must equal
the original with exactly the selected objects removed. The synthetic native SVG
limitation above remains explicit; this does not certify Adobe reopening.

```sh
dart run tool/check_native_shape_removal.dart
python3 tool/verify_native_shape_removal.py --inkai-source /tmp/extension-ai
```

Sibling-pair reordering checks four pinned real files and five checksum-pinned
synthetic sources. The fixed 24 transactions cover 12 real-file and six synthetic
permutations (59 changed pair slots), two unchanged orders and four exact refusals.
Complete source blocks retain saved identities and both metadata alternatives;
all unselected gaps remain exact, and inserted scalar assignments must originate
in the source. Native/printing contour flags and synthetic private/public opacity
move with their selected owners. Real-file native/printing SVG and synthetic
printing SVG compare active paint, geometry and resolved resources. Differences
limited to inactive leaf-stroke attributes additionally require exact RGBA pixels
from `rsvg-convert` at 1024 pixels wide; three linear-gradient printing comparisons
exercise this check. The synthetic version-branch SVG limitation remains explicit.

```sh
dart run tool/check_native_shape_reordering.dart
python3 tool/verify_native_shape_reordering.py --inkai-source /tmp/extension-ai
```

Complete-pair movement checks four pinned real files and nine checksum-pinned
synthetic sources. Its 32 fixed transactions cover 12 real and 12 synthetic moves,
plus eight exact refusals. Both metadata branches and all pair bytes stay exact;
only source-backed scalar replay can replace the old span or surround insertion.
An independent group/layer tree verifies the requested order and parent, including
empty groups/layers and explicit visibility/locking inheritance. Both contour-state
streams remain attached to their source pairs. Real native/printing SVG and
synthetic printing SVG compare geometry, active paint, resources and enclosing
appearance after applying exactly the requested relocation to the original tree.
The inactive-stroke pixel check and synthetic native SVG limitations above apply.
No Adobe reopening or host integration is inferred.

```sh
dart run tool/check_native_shape_movement.dart
python3 tool/verify_native_shape_movement.py --inkai-source /tmp/extension-ai
```

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
The synthetic documents include two native artboards, independent programs and
native thumbnails. Selected programs drop their thumbnails; unselected programs
retain every private block exactly. These cases test serialization, not visual
equivalence or Adobe reopening.

```sh
dart run tool/check_native_saves.dart
python3 tool/verify_native_saves.py --inkai-source /tmp/extension-ai
```

Printing-contour attachment checks five pinned CC fixtures with ten first/all
selections, covering 40 supplied shape expansions and 84 printing paths. The host
tool subdivides existing curves without changing their appearance. Independent
parsing evaluates the curves, preserves all paint commands and compares every
byte outside selected groups except declared DSC bounds. It explicitly validates
68 updated CC point counts, which the external SVG converter otherwise ignores.
Private and unselected point-count headers remain unchanged. External SVG comparisons
require nonempty output and unchanged appearance, within the reader's coordinate
rounding. These cases qualify geometry attachment with retained paints/resources;
they do not qualify arbitrary replacement styles or Adobe reopening.

```sh
dart run tool/check_native_printing.dart
python3 tool/verify_native_printing.py --inkai-source /tmp/extension-ai
```

Complete-group attachment uses the same ten selections and 40 expansions. The
host supplies nested groups and one additional zero-area unstroked path per
selection, alongside equivalent subdivided geometry. Independent parsing checks
every exact payload, all unselected bytes, existing private/resource commands,
path-count headers and introduced topology. All ten external SVG comparisons use
the same nonempty-output and difference thresholds as the contour checks.
The pinned SVG reader clears inherited colors after an unpainted `N` path; the
added paths use zero-area `F` fills to retain inherited fill. Stroked fixtures
explicitly set their stroke before painting. The independent reader is unchanged.
These are attachment/preservation checks, not Adobe reopening or proof that
arbitrary supplied artwork matches its private authoring data. Focused unit tests
separately cover paint-state changes, gradient ownership, limits and atomic refusal.

```sh
dart run tool/check_native_printing_groups.dart
python3 tool/verify_native_printing_groups.py --inkai-source /tmp/extension-ai
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

## Mixed artwork grouping and dissolution

The grouping suite uses four existing pinned real sources, declared exact wrappers
and checksum-pinned synthetic fixtures. It checks 18 fixed transactions: twelve
real/derived grouping and dissolution cases, two synthetic mixed/identified cases
and four refusals. The unmodified native reader binds complete selected owners,
requested parent topology, retained pair alternatives and local state. Exact byte
checks restrict edits to group boundaries and explicitly discarded parent metadata;
qualified identity removal preserves descendants. Both streams' parent flags are
checked separately. Adobe reopening and host rendering are not established.

```sh
dart run tool/check_native_subtree_grouping.dart
python3 tool/verify_native_subtree_grouping.py --inkai-source /tmp/extension-ai
```

## Neutral default-group reset dissolution

This suite reuses five pinned real sources, four declared pair-wrapper recipes
and checksum-pinned synthetic programs with explicit canvas origins. Eighteen
fixed transactions cover original, nested, empty and mixed parent dissolution,
plus eight style-ownership refusals. The unchanged reader verifies exact selected
owners, topology, metadata disposal and retained children; 15 native/printing SVG
comparisons and exact 1024-wide librsvg RGBA comparisons verify neutral reset
removal. SVG normalization only unwraps anonymous groups with no visual attributes
or opacity one, while pixel checks use the original trees. Synthetic native
version-branch SVG and Adobe reopening remain unqualified.

```sh
dart run tool/check_native_group_resets.dart
python3 tool/verify_native_group_resets.py --inkai-source /tmp/extension-ai
```

Path-to-group movement appends counted ordinary paths or direct live shapes to
empty/populated parents. Three manifest-pinned real sources receive one declared
empty group at a fixed layer boundary; their original bytes remain exact. Four
synthetic programs pin changed scalar state, identified/hidden parents and mixed
CC siblings. The independent verifier fixes all 15 requests, binds complete path
and metadata owners, checks point counts, both projections' consumed state,
native topology and all unselected bytes. Four real and eight synthetic moves
pass; three requests refuse atomically when inheritance or following state is
unresolved. Fifteen SVG and exact 1024-wide RGBA comparisons cover eleven moves.
The counted-state fixture is checked as native data only: upstream SVG
`PathContextManager.attach_path` clears persistent fill on a stroke-only path,
which prevents a correct comparison of the following reused fill. Synthetic
native version-branch SVG and Adobe reopening remain unqualified. The reader is
unchanged. Generated programs, SVGs, images and reports stay outside publication.

```sh
dart run tool/check_native_path_group_movement.dart
python3 tool/verify_native_path_group_movement.py --inkai-source /tmp/extension-ai
```

Creation without a layer template has twelve fixed transactions. Six append
explicit CC headers at the root or inside existing layers in three original
manifest-pinned files; six synthetic cases create a first layer with each
qualified layout, cross the nine-to-ten root-count boundary and append to empty
or populated parents. Names, identities, header attributes and panel flags are
independent expected values. The verifier decodes every old/new layer and proves
that only the empty wrapper and permitted count/view declarations changed. No
artwork, paint, resources or unselected source bytes change. This is native-data
qualification, without new rendering or Adobe reopening claims.

```sh
dart run tool/check_native_layer_creation.dart
python3 tool/verify_native_layer_creation.py --inkai-source /tmp/extension-ai
```

Group creation without existing siblings has thirteen fixed transactions. Seven
append an empty group at the root, in a layer or in an ordinary parent in three
original pinned files; five synthetic cases cover first creation, empty/populated
parents, complete CC siblings and explicit flag inheritance. One missing-policy
request refuses immutably. The independent reader binds original destinations,
requires exactly one empty owner and its declared metadata, checks both contour
state projections and retains every complete pair/version alternative, layer
header and unselected byte. No renderer or derived representation is introduced.

```sh
dart run tool/check_native_group_creation.dart
python3 tool/verify_native_group_creation.py --inkai-source /tmp/extension-ai
```

Path creation without existing siblings has eighteen fixed transactions. Seven
append explicit geometry at the root or in an owned group/layer in three pinned
real files; ten synthetic cases cover the first path, gray/RGB/CMYK paints,
unpainted/fill-only/stroke-only paths, uncounted open geometry, empty/populated
parents and complete CC siblings. One unresolved following-fill request refuses
immutably. Checksums pin every synthetic original. The unmodified reader verifies
the supplied geometry, point counts, process paints, names/identities and parent
ownership; old consumed state remains unchanged in both projections. Exact byte
comparison permits only the new object, source-backed scalar replay and the
declared drawing-bound union. Pair alternatives, layer data, resources and other
unselected bytes remain exact. These are native-data checks, without claiming
Adobe reopening or host representation generation.

```sh
dart run tool/check_native_path_creation.dart
python3 tool/verify_native_path_creation.py --inkai-source /tmp/extension-ai
```

## Ordinary contour geometry and masks

The topology suite prescribes twelve edits over three checksum-pinned synthetic
native programs: nested compound contours with identities, an initially open
path inside a clipping group, and complete CC pairs beside an ordinary compound.
Geometry replacement, consistent compound mask assignment, open/closed masks,
mask removal and combined edits retain every unselected owner. Predecessor files,
selected contour indices and replacement coordinates are fixed independently of
the Dart report. The reader binds each reported span to its own parse, compares
complete path geometry/paint/owners/counts and permits only the requested source
patches plus the explicit drawing-bound union.

Seven further cases use `manifest.json` provenance. `simple_shapes_cc.ai` still
refuses edits to derived CC compound expansions. Three transactions each on
`inkscape_minimized_ai_cc.ai` and `inkscape_minimized_ai_cc_current.ai` edit an
outer contour, an inner contour or all five compound contours. Independent PDF
extraction must equal the complete original program; setup and metadata are never
substituted to enable editing. The reader prescribes the selected indices and
replacement geometry, and verifies every remaining byte, including imported SVG
metadata, native identities, transforms and transparency commands. All nineteen
cases must run. These six producer edits establish contour-data preservation;
they do not certify arbitrary compound/clip lifecycle or Adobe reopening. No
renderer or supplied source artwork is modified.

```bash
dart run tool/check_native_path_topology.dart
python3 tool/verify_native_path_topology.py --inkai-source /tmp/extension-ai
```

The compound lifecycle suite adds ten transactions over six checksum-pinned
synthetic programs: ordinary nested branches, direct masks, grouped mask leaves,
complete neighboring CC pairs, identified-parent metadata disposal and the release
of 200 compounds. Selections, predecessor snapshots and exact source boundaries
are prescribed by the verifier independently of the Dart writer. The unmodified
native reader checks every contour's geometry, paint, counts, private status and
new ancestry. Exact-byte checks permit only the requested compound delimiters and
explicit parent attachments to change. These are format-data checks; they do not
qualify Adobe reopening or a real producer's complete compound-editing workflow.

```bash
dart run tool/check_native_compound_lifecycle.dart
python3 tool/verify_native_compound_lifecycle.py --inkai-source /tmp/extension-ai
```

The clipping lifecycle suite adds eleven prescribed transactions over seven
checksum-pinned synthetic sources. The independent reader checks geometry, mask
counts, effective group ancestry, normalized compound leaves and all retained
bytes. Restoration instructions must come from actual source assignments. Nine
transactions additionally use Ghostscript's interpreter with the unchanged Adobe
prolog from `manifest.json`'s `inkscape_minimized_ai7.ai` (CC 27.3.1 exporting the
legacy format). Every contour and the final boundary retain cap/join/width/miter/
dash values, in printing and exposed-private-scalar projections. The two cases
with complete CC pairs use native-data checks; the legacy prolog does not execute
their opaque authoring records. This does not certify Adobe's UI or render the
document. The prolog's existing provenance, licensing and checksum apply; no
downloaded implementation or artwork is copied into package source.

```bash
dart run tool/check_native_clipping_lifecycle.dart
python3 tool/verify_native_clipping_lifecycle.py --inkai-source /tmp/extension-ai
```

The contour movement suite adds eleven prescribed transactions: compound entry
and extraction, reordering, direct anchors, mask assignment/removal, a 200-contour
batch and four moves in the complete original Inkscape CC native programs.
Synthetic inputs are checksum-pinned; the two producer PDFs retain their existing
manifest provenance and independent native extraction checks. The unmodified
reader binds each reported owner, group, count and metadata span to its own parse.
Expected source indices, destination ancestry, paint inheritance and mask changes
are prescribed independently of the Dart report. Every path's consumed attributes,
group/final state and exact unselected bytes are compared, including both native
and printing state. Replay instructions must use actual source assignments.

All eleven transactions additionally execute the same pinned Adobe legacy prolog
with Ghostscript, checking stroke attributes at contour consumption and every
group/final boundary in both scalar projections (22 checks). Modern transparency
and opaque metadata are checked as native data, without executing their content.
This does not render the document, certify Adobe reopening or qualify arbitrary
compound/clip owner lifecycle. Generated outputs and the downloaded prolog remain
outside publication.

```bash
dart run tool/check_native_contour_movement.dart
python3 tool/verify_native_contour_movement.py --inkai-source /tmp/extension-ai
```

## Native artboard state and rectangles

`artboard_manifest.json` pins three CC unit/origin examples, two existing complex
documents and Reuters' five-page `preview-dev.ai` at an explicit Git revision.
The latter is distributed under the `ai2svelte/LICENSE` MIT notice retained in the
manifest; artwork stays outside Git and publication. Its five PDF owners share
one native program, independently extracted from every owner. Active index 4,
selected index 2, LastArtboardID 67 and the separate crop rectangle are checked
without inferring them from PDF page order, count or dimensions.

Twenty fixed transactions cover six real inspections, eight successful rectangle
edits in four CC sources, four checksum-pinned synthetic edits (including mixed
CC pairs/resources) and two immutable refusals. The nested-layer source now also
qualifies both resize variants with its complete producer setup. The unmodified reader binds each
reported Document span to its full parse, compares all document fields, and
requires exact original bytes outside the requested coordinate/crop tokens. The
large Reuters source remains inspection-only: upstream body-parser warnings are
outside the separately parsed Document metadata check. PDF-page remapping,
`AIMetaData` updates and Adobe reopening are not established by this suite.

```sh
python3 tool/fetch_corpus.py --manifest artboard_manifest.json
dart run tool/check_native_artboards.dart
python3 tool/verify_native_artboards.py --inkai-source /tmp/extension-ai
```

The lifecycle suite checks fifty-four transactions: thirty resizes, creations,
reorderings and removals across the three pinned CC unit/origin examples and the
RGB/CMYK rectangle fixtures already pinned in `manifest.json`, plus twenty-four
checksum-pinned synthetic transactions with independent active/selection/crop
state and mixed CC/resource owners. The unmodified reader checks complete
Document values, exact retained board records and separator trivia, and all bytes
outside the selected array/scalar/crop changes. Creation counters and replacement
active boards are explicit inputs; these native checks do not establish PDF-page
mapping, cached-header synchronization or Adobe reopening. The rectangle sources
retain their full plug-in/style/palette inventories, unused text resources and
separate main/undo-free snapshots. Exact external-byte comparisons also retain
their text ruler origins, template boxes and canvas declarations while the first
board is resized, inserted before, reordered or removed.

The added `synthetic-topology` source contains a hidden layer, nested ordinary
and compound groups, three path masks inside two clipping groups, five counted
paths and direct object identities. All six native edit variants retain exact
independently parsed operators and operands as well as complete external bytes.
The fixture's SHA-256 is pinned in the verifier. These synthetic masks follow the
AI file-format `h/H W` path-mask contract; no new real producer clipping fixture
or Adobe reopen result is implied by their acceptance.

The `synthetic-palette` source adds six cells, including localized registration,
named CMYK/RGB alternatives, none paint and a shared gradient, plus two palette
groups. All six edit variants retain the independently parsed palette commands,
names, flags, coordinates and referenced gradient definition. A shared spelling
with a removed artboard UUID remains in the distinct paint namespace. Its
checksum and complete transaction set are pinned in the verifier; this synthetic
source does not qualify producer pattern resources.

```sh
dart run tool/check_native_artboard_lifecycle.dart
python3 tool/verify_native_artboard_lifecycle.py --inkai-source /tmp/extension-ai
```

The retained-text suite checks 28 artboard transactions in seven checksum-pinned
carriers. Four copy exact text setup blocks, global origins, drawing references,
confinement curves and attached metadata from `simple_cc_legacy.ai`,
`simple_v2020.ai`, `text_transforms.ai` and `flowtext.ai`, already pinned in
`manifest.json`. Three synthetic sources exercise separate main/undo-free model
selection and a counted clipping/gradient pattern. The text transformations fixture contributes ten stories and sixteen
point, area and path frames, including linked frames and retained glyph caches.

The unmodified inkai reader independently decodes both binary snapshots and all
body text references, compares the copied data against the original producer,
resolves each drawing-to-story-to-frame selection and checks every result. Whole
native byte comparisons permit only the declared Document/crop edits. The carriers
also retain the producers' complete font setup and font-name headers. The
independent reader compares encoding marks, declarations, names and flags with
the original producers and all edited outcomes; source checks retain every font
setup byte. Each real carrier additionally retains the producer's complete
pattern/gradient banks and palette, including both patterns: 102 paths in each
of the first three sources and 177 in `flowtext.ai`, with 16 and 20 gradient
definitions respectively. The oracle compares complete pattern commands and
metadata, gradient commands/operands and palette references with the producer
and every outcome, while requiring byte-exact copied resource sections. These
are explicitly synthetic artboard carriers with original producer text, fonts
and resources; they do not claim full-source artboard edit support for those
four files. Symbol inventories and other complex owners, including brush
resources, still require separate qualification.

```sh
dart run tool/check_native_artboard_text.dart
python3 tool/verify_native_artboard_text.py --inkai-source /tmp/extension-ai
```

The retained-symbol suite checks twenty further transactions in five pinned
carriers. Four extend the text/font/pattern carriers above with complete selected
producer symbols and an explicit panel inventory. Twelve definitions from each
of the first three producers contain 65 paths; three from `flowtext.ai` contain
167 paths, for 39 copied definitions altogether. Selection is fixed in both
tools, rather than skipping whichever definitions happen to fail. Every selected
definition remains byte-identical to its original producer section. The external
reader compares complete symbol commands and metadata, names, inventory order,
gradient references and all text/font/pattern data against the originals and
each edited result. A synthetic source separately checks private counted geometry,
blending flags, a resolved style and an XML artwork ID equal to an artboard UUID.
Whole-native comparisons permit only the declared Document/crop edits.

These carriers qualify resource retention, not symbol-instance editing or full
producer artboard edits. The separate mask suite below qualifies retained mask
payloads. The appearance suite below checks additional complete style graphs;
blend owners, brush and SVG-filter resources still need qualification.

```sh
dart run tool/check_native_artboard_symbols.dart
python3 tool/verify_native_artboard_symbols.py --inkai-source /tmp/extension-ai
```

The retained-mask suite adds twenty transactions in five pinned carriers. Three
copy both complete `Film` mask dictionaries from `simple_cc_legacy.ai`,
`simple_v2020.ai` and `text_transforms.ai` into an explicitly synthetic symbol
owner. Each has a 32-by-32 and a 29-by-30 gray image, with 1,024 and 870 bytes of
samples. The independent reader compares every mask flag, artwork command, image
descriptor, sample byte and attached dictionary with the original producers and
every edited result. Exact source-section checks retain the full copied mask
owners; Document/crop edits are the only permitted native changes. The carriers
also retain and independently compare the producers' text, fonts, gradients,
patterns and palettes. Two synthetic sources cover raster and vector masks with
separate symbol/artboard identities.

This suite isolates mask retention; the appearance suite below includes complete
`Film` symbols and their style dependencies. Neither suite establishes acceptance
of the complete original producer document.

```sh
dart run tool/check_native_artboard_masks.dart
python3 tool/verify_native_artboard_masks.py --inkai-source /tmp/extension-ai
```

The retained-appearance suite checks twenty further transactions. Four real
carriers copy 50 complete symbols and 46 complete style definitions, including
all fifteen symbols of each of the first three producers and five from
`flowtext.ai`. The blend source `Band` and the style `Chrome Highlight`, which
references a calligraphic brush, are explicitly excluded pending their dependency
contracts. No part of a retained symbol or style is stripped. Source provenance,
these exact selections and constructed-carrier hashes are independently checked.
The first three carriers also retain the producer's complete panel inventory in
its original order, independently of definition order. This includes both
NUL-terminated AI10 boundary comments from `simple_cc_legacy.ai`; the oracle
compares the original panel syntax tree and exact source section.

The external reader compares all ordered style parts, descriptor fields, paint
commands, masks and raster samples against the original producers and every
edited result. Mode-zero and mode-one named uses resolve; unnamed applications
remain unchanged without inventing a missing style. All producer text, fonts,
gradients, patterns and palettes remain independently checked as well. A synthetic
case adds hidden paint parts, advanced local blending and an effect whose title
equals an artboard identity. Whole-native checks permit only the prescribed
Document/crop changes. These tests establish retention, not effect execution,
general appearance editing or complete-producer artboard acceptance.

```sh
dart run tool/check_native_artboard_styles.dart
python3 tool/verify_native_artboard_styles.py --inkai-source /tmp/extension-ai
```

The retained-brush suite adds twenty transactions over four real carriers and
one synthetic source. It copies all seventeen complete brush-artwork definitions
from the four producers, including twenty raster images: fifteen 168-by-62 CMYK
images and five 201-by-106 RGB images, each with a separate alpha plane. The
carriers also keep the qualified complete styles, symbols, masks, text, fonts,
gradients, patterns and palettes from the appearance suite. Source provenance,
carrier checksums, exact copied sections and full independent syntax trees are
compared before and after every native edit.

The pinned reader omits a leading ASCII-space byte from the RGB color plane in
`flowtext.ai`. A supplementary independent check therefore reads both planes
from the original bytes using the decoded dimensions and exact `XI` framing.
It checks the computed end boundary and compares every color/alpha byte, including
that leading byte, without searching samples for `EndData`. Whole-native
checks still permit only the prescribed Document/crop changes. This qualifies
brush artwork retention; calligraphic/other assignment descriptors, SVG-filter
and blend owners still need separate qualification for complete-producer edits.

```sh
dart run tool/check_native_artboard_brushes.dart
python3 tool/verify_native_artboard_brushes.py --inkai-source /tmp/extension-ai
```

The retained SVG-filter suite adds twenty transactions over four real carriers
and one synthetic source. It copies all 72 producer filter trees and their 24
animations in the exact original collections. The pinned independent reader
compares every native XML field, attribute, child and scalar value, while full
collection-byte comparisons also preserve attribute order and native trivia.
The same carriers retain all previously qualified brushes, color/alpha planes,
appearance graphs, symbols, masks, text, fonts, patterns, gradients and palettes;
these are compared to the original producer data again after each edit.

The synthetic graph deliberately shares an artboard's spelling in SVG IDs and
repeated local result names. Creation, resizing, reordering and removal change
only the prescribed Document/crop fields. The carriers still exclude Band's
blend dependency and Chrome Highlight's calligraphic brush descriptor. Full
original files now pass filter inspection before those remaining owners; this
does not establish end-to-end producer-file editability or Adobe reopening.
No filter evaluation, animation execution or host renderer is involved.

```bash
dart run tool/check_native_artboard_svg_filters.dart
python3 tool/verify_native_artboard_svg_filters.py --inkai-source /tmp/extension-ai
```

The brush-descriptor suite retains all 36 producer plug-in sections, including
their four ordered brush panels, and all six calligraphic references from the
three complete Chrome Highlight appearances. The independent parser compares
literal fragments, complete parameters and plug-in/name pairs; panel references
and artwork-tile dependencies resolve independently. The twenty carrier
transactions also compare all original appearance, brush/raster, SVG-filter and
text resources. The synthetic case shares names across four brush namespaces
and native artboard IDs; its compound appearance wrapper matches the independent
reader's supported execution representation. Direct basic-filter execution is
covered by the VM/Node regressions separately.

Six additional lifecycle transactions operate on the complete original
`text_transforms.ai` native program, including creation before/after the original,
resizing, reordering, and deletion of the new or original active board. Their
predecessor chain, exact requested Document changes, retained board dictionary
trivia and every byte outside those edits are checked independently. This
qualifies complete native-program operations for that fixture; Adobe reopening
and host-supplied PDF composition remain separate. The two simple CC originals
required additional perspective-grid settings, and `flowtext.ai` required Band's
blend ownership at that stage; the complete-source suite below covers both.

```bash
dart run tool/check_native_artboard_brush_descriptors.dart
python3 tool/verify_native_artboard_brush_descriptors.py --inkai-source /tmp/extension-ai
```

The complete-source suite exercises thirty transactions across the original
`simple_cc_legacy.ai`, `simple_v2020.ai`, `text_transforms.ai`, `flowtext.ai` and
`layers_and_sublayers.ai` programs. The first four use `manifest.json`; the fifth
uses `artboard_manifest.json`. All revisions, source sizes and checksums are
verified before independently extracting the original native bytes. No producer
setup, resource, drawing or text record is removed or replaced to enable an edit.

Each source undergoes six prescribed lifecycle steps: resize, create before the
original, reverse that order, remove the new board, separately create an active
board after the original, then remove the original. The verifier binds every
step to its specified predecessor and checks complete Document values, board
dictionary trivia and exact bytes outside the intended changes. All retained
appearance, symbol, mask, brush/sample, descriptor, filter and text resources
are independently parsed again. Band's endpoint annotations must belong to the
first and last of the same group's ten saved paths; the intermediate artwork
stays exact. Perspective locks, ruler visibility and active-plane fields retain
their original types and values. These checks establish native preservation,
not blend generation, Adobe reopening or host PDF composition.

```bash
dart run tool/check_native_artboard_complete_sources.dart
python3 tool/verify_native_artboard_complete_sources.py --inkai-source /tmp/extension-ai
```

## Native print selections

The print-job suite reuses the three CC unit/origin fixtures pinned in
`artboard_manifest.json` and a checksum-pinned synthetic source containing complete
CC pairs and shared resources. Each source undergoes five chained transactions:
explicit print selection, artboard creation, reordering, removal and resizing.
Physical printed-page counts and selections are supplied independently of native
artboard counts. The three real sources originally have empty saved ranges;
these cases validate editing those existing producer fields, not real-file
examples of nonempty saved selections or Adobe print-dialog interoperability.

The unmodified pinned inkai reader compares complete Document values, native
artboard identities, active/history state, all flags and independently expected
ranges. Byte comparisons limit changes to the intended board/coordinate/scalar
and print operands, retaining field types, unrelated printer settings, artwork,
resources and all other source data. All twenty transactions must pass.

```sh
dart run tool/check_native_print_jobs.dart
python3 tool/verify_native_print_jobs.py --inkai-source /tmp/extension-ai
```

## Cached native headers

The header-cache suite reuses the 31 PDFs in `manifest.json` and the five-page
Reuters fixture in `artboard_manifest.json`. It changes only the native Creator
header, then independently extracts every owner and compares the supplied native
bytes, full/font-filtered cache profile, remaining metadata, page content and
resources. Twenty-two real saves and two checksum-pinned synthetic saves update
31 owner caches; ten older sources explicitly refuse their divergent canvas or
resource cache layouts. The synthetic partial/batch cases retain catalog aliases,
independent programs and unselected caches. The Reuters aliases share one new
cache stream. These checks do not infer any artboard-to-page mapping or establish
Adobe reopening.

```sh
dart run tool/check_native_metadata_headers.dart
python3 tool/verify_native_metadata_headers.py
```

## Explicit native/PDF page mappings

The mapped-save suite reuses three pinned PDFs: `simple_cc_legacy.ai`,
`simple_v2020_no_pdf_data.ai` and the five-page `reuters-preview-dev.ai`. It replaces
the first page identity using explicitly supplied original artwork and metadata
templates, retaining exact native programs. It does not semantically edit the
Reuters artwork. The pinned `rgb_rectangle.ai` and `cmyk_rectangle.ai` each add
four consecutive saves: create a board/page before the original, resize it,
reverse both orders, then remove the original active board/page with an explicit
active replacement. Every step decodes the previous serialized result before
reacquiring native handles. The independent verifier requires that exact
predecessor chain, beginning with each checksum-verified original PDF. New pages
explicitly copy the original page's native metadata; their host-supplied PDF
content and boxes are serialization inputs, not an inferred native rendering.
Four checksum-pinned synthetic cases save native artboard
creation, removal, reordering and resizing with explicit PDF pages. Two further
synthetic cases cover multiple programs with selected-only and batch saving.

The unmodified pinned inkai reader decodes the uniquely bound Document fragment
without interpreting opaque drawing operators. Independent checks compare all
native Document values, retained board dictionaries and separator trivia,
complete native bytes outside prescribed edits, owner
aliases, metadata templates, updated cached headers, other producer metadata,
host-supplied page identities/boxes/content/resources and retained catalog data.
All seventeen cases must pass. These checks establish serialization and graph
preservation, not native rendering, appearance generation or Adobe reopening.

```sh
dart run tool/check_native_page_saves.dart
python3 tool/verify_native_page_saves.py --inkai-source /tmp/extension-ai
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
