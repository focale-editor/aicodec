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

## Native artboard state and rectangles

`artboard_manifest.json` pins three CC unit/origin examples, two existing complex
documents and Reuters' five-page `preview-dev.ai` at an explicit Git revision.
The latter is distributed under the `ai2svelte/LICENSE` MIT notice retained in the
manifest; artwork stays outside Git and publication. Its five PDF owners share
one native program, independently extracted from every owner. Active index 4,
selected index 2, LastArtboardID 67 and the separate crop rectangle are checked
without inferring them from PDF page order, count or dimensions.

Nineteen fixed transactions cover six real inspections, six successful rectangle
edits in three CC sources, four checksum-pinned synthetic edits (including mixed
CC pairs/resources) and three immutable refusals. The unmodified reader binds each
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

The lifecycle suite adds twenty-five transactions: fifteen chained creations,
reorderings and removals across the three pinned CC unit/origin examples, and ten
checksum-pinned synthetic transactions with independent active/selection/crop
state and mixed CC/resource owners. The unmodified reader checks complete
Document values, exact retained board records and separator trivia, and all bytes
outside the selected array/scalar/crop changes. Creation counters and replacement
active boards are explicit inputs; these native checks do not establish PDF-page
mapping, cached-header synchronization or Adobe reopening.

```sh
dart run tool/check_native_artboard_lifecycle.dart
python3 tool/verify_native_artboard_lifecycle.py --inkai-source /tmp/extension-ai
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
Reuters artwork. Four checksum-pinned synthetic cases save native artboard
creation, removal, reordering and resizing with explicit PDF pages. Two further
synthetic cases cover multiple programs with selected-only and batch saving.

The unmodified pinned inkai reader decodes the uniquely bound Document fragment
without interpreting opaque drawing operators. Independent checks compare all
native Document values, complete native bytes outside prescribed edits, owner
aliases, metadata templates, updated cached headers, other producer metadata,
host-supplied page identities/boxes/content/resources and retained catalog data.
All nine cases must pass. These checks establish serialization and graph
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
