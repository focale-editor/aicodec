# Complete native AI integration in Focale

This document records the native AI integration requested on 2026-11-01 and its
local acceptance. The implementation log below is chronological: references to
pending tests describe the state of that increment, not the final validation.
Actual Adobe Illustrator exchange remains unverified.

## Implemented host workflows

| Area | Qualified current behavior |
| --- | --- |
| Documents and pages | Initial AI CC documents, shared canvas artwork, multiple artboards and retained page lifecycle with synchronized compatibility PDF. |
| Text, images and shapes | Composed point/rectangular text and font retention, ordinary text lifecycle, embedded/linked image creation and editing, ordinary groups, dynamic shapes and affine transforms. |
| Paint and appearance | Process gradients including hard stops, mesh geometry and interpolation, qualified blending, private group/path edits and exact opacity-mask carriers. |
| Complete appearances | Removal, stacking and reparenting move the complete native/printing pair, its masks and identities together; ordinary neighboring artwork remains independent. |
| Mixed files | Unsupported complete authoring owners remain explicitly preserved, locked printing subtrees. Supported neighbor edits preserve their source and shared styles byte-for-byte, including project recovery and repeated saves. |
| Derived views | Native authoring, host-composed printable content and compatibility PDF use the same revision. PDF synchronization applies the same mask preparation as ordinary PDF export. |

These are bounded native profiles, not arbitrary Illustrator execution. Unknown
ownership or unresolved state retains compatibility fallback. See the final
validation section and the remaining limits below.

## Working rules

- AiKit owns immutable native authoring data and serialization. Focale owns
  composition, rendering, interaction and the compatibility PDF.
- Retain unsupported source data and distinguish preserved objects from editable
  ones. Do not use a flattened PDF as evidence of native export completion.
- Preserve earlier uncommitted work in both repositories. Check the current
  dependency resolution before application tests. Implementation used a local
  AiKit override. Final validation removes it and locks Focale to the pushed AiKit revision.
  The Git dependency library files must match the validated worktree exactly. No package version or publication changes are involved.
- Record the implementation and meaningful verification for each completed step
  below. Leave requirements open until their full acceptance is established.

## Implementation evidence

- Baseline inspected: AiKit contains new-document creation and qualified native
  lifecycle/appearance APIs. Focale's `AiDocumentAdapter.encode` rejects a missing
  `AiOrigin`, topology/paint/page changes; `_nativeScene` admits one simple page.
- `AiNativeTextDocument.create` now initializes compact ATE 7 fonts, normal styles,
  frame/story tables, font headers and independent empty undo-free data. Focused
  tests cover first creation, retained paths/identities, story lifecycle and
  initialization of an existing fontless AI with synchronized header cache.
- `check_native_text_creation.dart` / `verify_native_text_creation.py` produce and
  independently read five native/ATE snapshots and two matching empty AI/PDF
  saves. This proves typography initialization, not Focale-composed glyphs or
  Illustrator editing acceptance. None of the five overall requirements is
  complete yet.
- Focale ADR 0444 was proposed for the broader integration. The current PDF writer
  already includes loose scene roots on every artboard page, allowing shared
  Illustrator artwork to remain one global drawing rather than per-page copies.
  At that initial-text step the Focale adapter had not yet changed; the later
  ordinary CC integration is recorded below.
- Validation of the initial-text step: `dart analyze` reports no issues;
  `dart fix --dry-run` has no fixes; all 1,208 tests pass on both Dart VM and Node.
  Independent text initialization verification passes against pinned inkai
  revision `1a5f42a0b0407fc869e032420570682048810108` with pypdf. Formatting and
  `git diff --check` pass in the changed repositories. This is local evidence.

- `AiNativeDrawing.createRaster` and `createPlacement` now author process pixels,
  alpha, stencils with explicit paint, affine placement, ordinary object attributes,
  sample/XML identities, relative links and previews. File inventories retain shared
  users across later embedding/relinking. Qualified images and paths can be authored
  in interleaved paint order, with separate printing/native scalar restoration.
- A qualified linked relative-directory string is now retained as drawing metadata
  rather than an operand spanning its version block and placement terminator.
  This fixes structure inspection of repeated insertion into linked-image documents.
- Nine image-creation regressions cover existing-owner preservation, group/layer
  insertion, separate private opacity, process spaces/depths/stencils, shared links,
  subsequent editing/saves and bounded rejection. Independent pinned inkai, pypdf
  and Poppler checks pass for two complete image saves, including exact native and
  preview pixels, image/alpha resources, updated header caches and expected PDF
  color patches. The independent reader does not fully model all link metadata;
  explicit link-source assertions supplement its preview checks.
- Initial image insertion remains qualified ordinary root/group/layer authoring.
  It does not complete mask/appearance-owned insertion, arbitrary mixed text/image
  lifecycle or the Focale adapter. No overall requirement is marked complete.
- Final image-step validation: all 1,217 tests pass on both Dart VM and Node;
  `dart analyze` reports no issues, `dart fix --dry-run` has no fixes, formatting
  of the 13 changed Dart files and `git diff --check` pass. Generated image corpus
  files remain ignored. Focale application files were not changed in this step.

- Focale's ordinary CC authoring now supports blank documents, process-painted
  paths, nested layer hierarchy, physical units, explicit backgrounds and multiple
  boards. The native drawing remains global, with no duplication across overlapping
  boards. Board-owned artwork crossing another board still requires a clipping
  contract. Libraries, text, images, live shapes and advanced paints are not yet
  connected to this exporter.
- Native CC reopening retains one global coordinate root and separate artboards.
  It admits qualified ordinary metadata, path opacity and literal stroke dashes.
  Subsequent geometry edits use AiKit's CC path transaction and update the host PDF
  through the retained graph. Nested layer creation reacquires handles from the
  same inventory; newly authored layer names retain UTF-8 on later renames.
- Nine new-document regressions plus existing AI/PDF/source-editing suites pass
  (46 tests). Cases cover blank/native reopen, project serialization, nested paint
  order, atomic rejection, overlapping boards and two successive edited saves.
  The independent `verify_focale_documents.py` check confirms three Focale AI files
  with pinned inkai/pypdf, shared native owners, current header caches and exact
  Poppler pixels against independently composed host reference documents.
- Focale's full analyzer reports 522 informational findings, no errors or warnings;
  no findings target the changed AI/PDF implementation or new tests. These local
  checks do not establish broader native family coverage or Adobe acceptance.
  ADR 0441 remains proposed and all five overall requirements remain open.

- AiKit now exposes `replacePathArtwork` for complete ordinary geometry/process
  appearances with retained metadata and identities. Both native and printing
  state are restored for neighboring artwork; unknown required outgoing values
  reject. Its capability finding requires operation-specific qualification.
  Creation also retains explicit unused stroke metrics and scalar flags.
- Focale connects this transaction to ordinary fill/stroke addition/removal,
  RGB/gray/CMYK values, widths/caps/joins/dashes, opacity, winding, overprint,
  visibility and full locks, including combined geometry changes. Five application
  regressions verify repeated saves, sibling preservation, exact CMYK components,
  legacy ordinary paths, selected object flags and inactive zero-width strokes. Independent inkai/pypdf and
  Poppler checks verify a fourth appearance-edit output with exact reference pixels.
- The expanded Focale AI/PDF/source suites pass all 51 tests. A temporary-directory
  quota failure in the broader run was resolved by using the project volume for
  TMPDIR and concurrency two. This does not change native asset or runtime behavior.
  A final 32-test AI run also covers inactive zero-width strokes and rejects
  device hairlines until Focale has an explicit representation.
  Broader blending modes, per-fill/stroke alpha, gradients, named appearances and
  the other overall requirements remain open.

- Final ordinary-appearance validation: all 1,222 AiKit tests pass on both VM and
  Node. `dart analyze` is clean and the fix dry run has no changes. Focale's full
  analyzer retains 522 informational findings with no errors/warnings, and the
  final changed-file analysis is clean. Formatting and diff checks pass. The four
  independent application outputs verify exact process paints, dash metrics,
  scalar opacity, unselected state, header caches and matching PDF pixels.

- AiKit now exposes mixed ordinary path/layer `reorderArtwork` and `moveArtwork`
  transactions, including global-root destinations, independent native/printing
  state, coherent root counts and explicit saved-view invalidation. Six regression
  cases cover order, reparenting, declarations, divergent state and unsafe handles.
- Focale applies retained attribute edits before changing source indices, then
  creates, deletes, reparents and orders ordinary path/layer owners. It verifies
  identities and parent bindings after each transaction. New host groups become
  native layers; new identities are deterministic for the same document/object
  across retries and project restoration. Imported programs are not rebuilt.
- Eight application regressions cover insertion/duplication, mixed order,
  descendant retention, transformed new parents, reversed ancestry, legacy
  metadata insertion, atomic rejection and empty-canvas reuse. All 60 expanded
  AI/PDF/source-editing tests pass. Five independent application outputs now pass
  inkai/pypdf/header checks and exact Poppler comparisons against host references.
- Final lifecycle validation: the 1,226-test AiKit VM run passes, followed by all
  six focused lifecycle cases including the two added state/view regressions.
  The complete Node run includes all 1,228 tests and passes. AiKit analysis is
  clean and its fix dry run has no changes. Focale changed-file analysis is clean;
  full analysis retains 522 informational findings, without errors or warnings.
  Formatting and both repository diff checks pass. No Adobe exchange is implied.

- Ordinary CC artboards now support creation/duplication, removal, ordering,
  Unicode names and axis-aligned rectangle changes in Focale. Changes apply native
  artwork transactions and explicit `replaceMapped` bindings to a PDF graph
  derived from the original. Retained board UUIDs and PDF page identities survive;
  new board identities remain stable through retries/project restoration.
- Page backgrounds and admitted children become ordinary native artwork in the
  shared drawing. Removing every old board is supported by creating replacements
  first; removing the final resulting board rejects. Active-board replacement and
  creation counters stay coherent. Existing ruler origins and independent native
  crop declarations remain intact. Rotated/skewed pages and children requiring
  unimplemented clipping still reject before persistence.
- AiKit's immutable `catalogPages` declarations now explicitly bind original PDF
  pages governed solely by a source's catalog metadata. This permits their removal
  without inferring ownership. Foreign/duplicate declarations, separately owned
  pages, missing catalog ownership, unbound retained pages, changed removed-page
  metadata and remaining reachable references reject. Focale exercises this with
  complete catalog-only source saves and subsequent native reopening.
- Eight application page cases plus the broader AI/PDF/source suite pass 68 tests.
  Ten generated outputs pass pinned inkai/pypdf and exact Poppler comparisons,
  including Unicode names, native rectangles, page/board identities across saved
  revisions, shared metadata caches and catalog-only ownership. These checks do
  not establish general family coverage or actual Illustrator exchanges.

- Final page-step validation: all 1,230 AiKit tests pass on both VM and Node.
  AiKit analysis is clean and the final fix dry run has no changes. Focale targeted
  analysis is clean; full analysis retains 522 informational findings, with no
  errors or warnings. Formatting and both repository diff checks pass.

### Embedded-image integration

The latest embedded-image integration admits ordinary unconditional body images,
with qualified framing, literal metadata and one modeled native/printing state.
Focale projects process gray/RGB/CMYK and supported packed depths to bounded display
pixels; geometry-only edits keep the original native planes and cache identities.
New images and changed pixels use host-composed RGB8 with optional alpha. Placement
accounts for sample-resolution changes without changing authored display size.
Native UTF-16 image labels decode explicitly, while incomplete code units trigger
preserved-source compatibility fallback. Ordinary neighboring paths can be edited
while their image bytes remain unchanged.

The image application regressions cover mixed paint order, initial authoring,
project restoration, subsequent affine placement, resolution replacement, packed
gray/alpha, Unicode labels, parent/path edits and atomic rejection. Two generated
outputs extend the independent reader/renderer checks to twelve complete saves.
The subsequent image attribute/lifecycle/link implementation is described below;
private image appearances remain open.
No overall requirement is complete and actual Illustrator exchange is unverified.

Previous embedded-image baseline validation: all 1,232 AiKit tests pass on both VM and Node.
All 75 Focale AI/PDF/source-editing tests pass, including seven image cases.
The twelve regenerated outputs pass pinned inkai/pypdf checks and exact Poppler
comparisons. AiKit analysis and Focale changed-file analysis are clean; fix dry
runs propose no changes. Full Focale analysis retains 522 informational findings,
with no errors or warnings. Formatting and both repository diff checks pass.

### Image attributes, lifecycle and external links — validation pending

The implementation now connects ordinary embedded/linked image creation,
attribute changes (name, opacity, visibility, full lock and overprint), ordering,
reparenting, deletion and duplication. Source-backed copies retain native sample
precision or exact linked previews, independent of regenerated host identities.
Copies receive fresh artwork identities and embedded sample-cache identities.
Complete removed owners update file inventories only when the last use disappears.
Mixed layer and board reference qualification retains these image families.

Focale imports saved linked previews without reading external files. A persisted
`VectorSource.previewOnly` flag prevents editing/incorporating a preview as though
it were the full file. Refresh/replacement supplies resolved pixels for relinking
or incorporation; projects, duplication and resource reports retain provenance.
`AiOrigin.sourcePath` provides the base for relative paths. Save As to a different
folder rebases qualified external links, retaining the PDF and preview pixels;
unresolved relative references reject relocation. Export also checks the existing
source-retention byte limit before publication.

New regression cases cover mixed image transactions, native precision and cache
identities, shared dependency removal, link attributes, preview provenance,
project restoration, refresh/incorporation and relocated documents. They have
**not yet been run**. Per the user's instruction, further analysis and VM/Node/
Flutter/independent-renderer validation are deferred until the requested
implementation work is complete. Text lifecycle reference qualification also now
retains ordinary embedded/linked image neighbors, with an additional unrun
regression. The preceding baseline counts are not evidence
for these changes. Actual Illustrator exchange remains unverified.

### Host glyph capture — validation pending

Focale's existing outline capture now optionally retains each actual shaper glyph:
font program, font-specific ID, logical UTF-16 cluster, paragraph display source,
line index, advance, original contours and the compositor's complete placement.
Contextual slices replay captured glyphs with the same transformations as displayed
ink. Clips remain explicit, spaces retain IDs without invented outlines, and
decorations remain distinct from native font glyphs. Font programs are owned once
per capture batch. The source ranges explicitly address display paragraphs; the AI
adapter must establish their story correspondence before writing native mappings.

`AiTextFontProgram` derives native font names, outline technology, optional versions
and ordered fixed-point variation coordinates from these exact programs, including
hidden axes. Neither a substituted display-family name nor generated glyph IDs are
used. New/extended regressions cover actual CFF ligature IDs, spaces, font sharing,
contextual path/RTL/combining ink and bounded font metadata. They are unrun under the
requested final-only validation policy.

### Initial host text authoring — validation pending

The new-document writer now connects captured glyphs to a native ATE story,
exact font identities, character paints/sizes/tracking/baseline shifts, leading,
point or rectangular area frames, and a composed glyph view. Native glyph
origins are explicit; the actual space glyph from the final style represents the
required CR. Area frames contain both complete native cubic geometry and their
drawing-space confinement. Reserved layer owners retain interleaved paint order
while text resources are initialized after ordinary artwork.

The compatibility PDF receives the exact captured contours, with their character
paints, from the same immutable revision. The user's scene retains editable
text. This avoids a second PDF shaping path with different glyph selection or
kerning. Empty stories retain editable native CR coverage without exporting
Focale's generated empty-paragraph layout spacer as source text.

This initial projection accepts one source paragraph, ordinary point/rectangular
frames without overset, actual one-glyph-per-cluster composition (including
ligatures), horizontal unmodified display text and the explicitly mapped character
features. Linked/path frames, generated display characters, complex many-to-many
clusters, richer appearances and additional paragraph behavior remain open.
The initial authoring implementation alone does not establish editable Focale
reimport. The subsequent reader/edit integration is described below; broader
lifecycle integration and actual Illustrator exchange remain open.

AiKit's typed glyph writer checks source coverage, current font/frame handles,
mapping shape and bounded allocations. Font addition updates literal DSC font
dependencies. New unrun cases cover mappings, later lifecycle operations,
font inventories, real CFF ligature IDs, empty text, area confinement, wrapping,
physical units and interleaved ownership. No tests or analyzer campaign have
been run for this implementation; validation remains deferred as requested.

### Native text reimport and retained revisions — validation pending

The reader resolves complete native font identities from retained project bytes,
ordinary embedded PDF font resources or an exact installed-face resolver. It
compares actual host glyph IDs, clusters and positions before exposing editable
text. Conflicting programs claiming the same identity reject. Permitted complete
font programs are retained as ordinary PDF font resources, with embedding rights
respected and identical programs deduplicated. This adds no private attachment
format; the native ATE font identity remains authoritative.

The same initial point/rectangular, single-paragraph profile now supports retained
content/style revisions, resizing and full nonsingular affine frame placement.
AiKit's `replaceFrame` preserves frame UUIDs and indices, updates the confinement
and invalidates composition. Focale supplies newly captured glyphs and matching
PDF contours. Project restoration keeps exact font programs. Unsupported inherited
text attributes reject native projection instead of silently losing opacity,
visibility, locking or overprint.

Deferred cases cover embedded-font reimport without an installed resolver,
project restoration, successive content/style saves, resized/sheared/reflected
area frames, stable resource identities, named/compact frame replacement and
point/area conversion. These cases have not been executed. This work does not
complete text topology changes, richer typography, broader text carriers or the
remaining appearance/resource/mixed-file requirements.

### Text ownership in mixed trees — validation pending

The source-backed tree transaction now creates text stories, duplicates editable
host text into fresh native resources, removes stories before their containing
layers, and relocates/reorders text among paths, images and layers. Its ledger uses
frame UUIDs rather than assuming drawing order equals story order; references are
reacquired after story/frame compaction. Page transactions use the same text capture
and retained font resources. Focale also reads authoritative private scalar replay
when rebuilding its scene after such operations.

AiKit shares the existing state-preserving subtree movement with isolated text
references. Source moves retain engine bytes and model indices. Generic subtree
copy/deletion explicitly excludes contained text until its model lifecycle is
handled. Reference deletion beside ordinary process text qualifies the complete
main namespace and requires an empty undo namespace; unqualified dependencies
remain protected. The new package and host regressions are written but unrun,
including text/path ordering, reparenting, first text insertion in an existing
document, fresh copies and subsequent story deletion. Broader carriers, appearance
families, mixed unsupported objects and real application exchange remain open.

### Gradient discontinuities in host representations — validation pending

Focale's shared gradient model now retains ordered coincident colour/opacity
stops and nearby distinct stops. Sampling exposes both limits without shifting
positions by an epsilon; reversal, imported midpoints and spline end tangents
retain hard edges. Editing one alpha side keeps the other side. Shader sampling
and PDF opacity-mask composition use these same boundaries.

PDF writing uses separate continuous functions at hard transitions, including a
terminal jump that controls the extended endpoint. Reimport traverses bounded
stitching/sample functions, evaluates exact side limits and retains linear pieces
without adding redundant midpoints on every save. Nonlinear curves still use
explicit sampling; arbitrary calculator-function discontinuities are not inferred.

The model, renderer, function-evaluator and repeated-PDF-save regression cases are
written but not executed. This is preparation for native AI gradients; it does
not yet connect native resource creation/application/rebinding to Focale or claim
Illustrator appearance acceptance. Tests and analysis remain deferred until the
requested implementation work is complete.

### Direct native gradient applications — implementation, validation pending

AiKit now inventories complete direct gradient fills, including their contour,
count and attached identity/name. It can create, replace, copy, convert from/to
ordinary process fills, and retain these owners in mixed layer/group lifecycle
and artboard transactions. Unknown or interleaved ownership remains preserved
without an editable handle. The package serializes explicit stops, ramps and
absolute affine geometry; it does not render gradients.

Focale now connects the initial encoded process-gradient profile to new-document
creation, native reopening, retained paint/geometry edits and mixed object
creation/copy/move/delete. Linear and radial axes retain their complete affine
basis, including nonuniform scale and shear. Radial point focus is carried in
native highlight data. Ordered coincident stops retain hard edges; separate
opacity boundaries are merged into explicit native stops without softening them.
An optional ordinary process stroke retains width, cap/join, dashes and overprint
through the native gradient terminator and participates in state restoration.
RGB ramps include a host-composed CMYK alternative at every sample. Both native
resources and PDF consume the same revision. Content-addressed resources share
identical ramps while a selected change leaves other applications untouched.

This initial profile admits one process color space, straight encoded intervals
(also Classic with zero smoothness), centered midpoints, extended ends and an
interior point focus. Gradient strokes, other interpolation methods, relative CC
imaging layouts, named-ink gradients and richer appearance carriers remain open.
Existing unsupported data is not relabeled editable. Source resources are retained
until explicitly removed after their final reference is gone.

Eleven package lifecycle regressions and nine Focale integration cases have been
written, including independent-render artifacts. They have not been executed;
tests and analysis remain deferred under the user's final-only instruction.
Neither this implementation nor the earlier host/PDF preparation establishes
actual Illustrator round-trip acceptance.

### Native mesh geometry and lifecycle — implementation, validation pending

AiKit now has explicit node position/handle/weight transactions, complete affine
transforms and Cartesian topology replacement. Shared corner positions are
checked atomically; process colors, named inks and intermediate nodes remain
explicit. Patch `/R` values are retained or supplied as literal numeric arrays
without assuming their undocumented interpretation. The package does not create
an interpolator, tessellator or native-to-PDF renderer.

Direct mesh packets now have complete ownership handles, including ordinary
metadata. They support creation without a template, replacement, fresh-identity
copies, mixed layer moves/reordering/removal, containing group/layer lifecycle
and retained artboard transactions. Source and printing scalar state are restored
independently. Unknown fields and unresolved appearance attachments receive no
editable owner.

Twelve geometry/topology and ten artwork lifecycle regressions are written. The
corpus producer also prepares affine and explicit cropped-topology variants for
an independent Python coordinate/ink/neighbor-byte comparison. None of these
new checks has been executed. Focale's separate smooth tensor mapping is connected
below; its broader source coverage and Illustrator acceptance remain open.
Implementing the serialization API alone does not close requirements 2–5.

### Host mesh interpolation model — implementation, validation pending

Inspection of the earlier corpus-derived tensor implementation confirms that
mapping every native cell into Focale's existing Coons/bilinear grid would change
its geometry and colors. Focale now has an explicit smooth tensor mode, shared
cubic boundaries with zero corner mixed derivatives, and geometry-scaled Hermite
process-color interpolation. Single-cell color axes use explicit endpoint secants.
This extends the host model; it does not restore any renderer to AiKit.

Internal grid version 3 retains the selected mode, built-in interpolation profile
and optional full-precision node colors. Existing grid versions keep their previous
behavior. Geometry edits, transposition, project serialization and display sampling
retain the new semantics. Smooth topology insertion rebuilds its new cells and
derivatives and does not claim Coons' exact polynomial restriction guarantee.
Nine model regressions are written but unexecuted. Constant process channels and
alpha remain exact during sampling and topology insertion. See Focale ADR 0444
for this host-side contract.

### Native mesh host connection — implementation, validation pending

Focale now projects complete direct Cartesian owners into its smooth tensor mode,
authors those grids in new CC documents and saves retained geometry, handles,
process colors, ordinary object flags and topology. The first admitted profile
has at least two cells per axis, at most twelve nodes per axis, four colored
corners per cell, unit weights, coherent shared controls, one process space and
constant corner opacity. RGB, CMYK and encoded device gray retain floating source
components. Device gray has its own `pdfDeviceGray` value interpretation rather
than being mislabeled as gamma-2.2 gray.

The ordinary tree ledger now includes mesh owners: insertion, exact-grid copies,
mixed ordering, layer moves and deletion retain native ownership. Exact copies
retain literal patch parameters and frame metadata while receiving fresh
identities; ambiguous equal-grid sources with different native parameters reject.
Geometry edits retain `/R` arrays and frame metadata. New grids omit `/R`; topology
changes on parameterized sources require an explicit mapping and currently reject.

Uniform scale, translation, rotation and reflection bake positions and controls.
Nonuniform placement still requires a contract preserving geometry-dependent color
slopes; it is not silently treated as equivalent. Existing Coons grids, compound
boundaries, non-unit weights, varying corner opacity, larger grids, named inks and
unqualified attachments retain the compatibility fallback. Mixed supported and
unsupported owners still need the broader work in requirement 5.

The host PDF writer now emits 16-bit RGB/CMYK/device-gray components from the same
sampled process field. Mesh opacity masks retain floating alpha and process inks
instead of round-tripping through packed previews. Smooth cells use the denser
bounded lattice even when their controls happen to be straight. PDF remains a
derived triangle representation; native AI retains the editable cells.

Ten application regressions and three device-gray checks are written, alongside
the nine model cases. The independent verifier also has a native mesh/PDF fixture.
None has been executed under the final-only testing instruction. This is not
evidence of Illustrator acceptance or completion of the full integration goal.

### Direct live-shape host connection — implementation, validation pending

The adapter now authors and reopens rectangles, full ellipses, polygons/stars
and lines without arrowheads as procedural host geometry. Rectangles support
independent absolute circular corners; regular polygons and stars support their
circular corner parameters, including independent star tips and indents. Source
anchors and every cubic control are compared with the host shape before exposing
editable parameters. Center coordinates use the actual text-document ruler origin;
new shape-only documents initialize a complete empty text namespace with the real
host default font and styles, rather than inserting a dummy ATE record.

AiKit adds `createLiveShape`, `setPathLiveShape` and `replaceDirectLiveShape` for
complete direct owners. The host supplies typed parameters, the exact contour,
process paints, conservative ink bounds and matching PDF. The new local replacement
retains native names/identities and restores following drawing/printing state.
Focale connects retained parameter/paint/opacity changes and tree insertion,
duplication, ordering, layer moves and removal. Bounding-frame angles follow the
placement delta independently of the procedural parameterization.

Sharp rectangles support nonuniform scaling/reflection; shear becomes an explicit
irregular native four-sided polygon and reopens as an affine rectangle. Full
ellipses require orthogonal axes. Sharp polygons permit affine placement, while
stars currently require similarities. Stroked shapes require similarity placement.
Nonuniform rounded geometry, inverted/chamfered corners, ellipse pies, separate
CC printing groups, arrowheads, gradient shape paints and broader appearances require their
additional contracts. These are explicit coverage limits, not completion of the
whole shape or integration requirement.

Ten package and eighteen host regressions are written but unexecuted. Five-family
and reflected rounded-rectangle native/PDF fixtures are added to the independent
verifier, also unexecuted. Formatting
only has been performed under the final-only test instruction; Illustrator
acceptance remains outstanding.

### Circular corners and literal object names — implementation, validation pending

The shape bridge now converts Focale's polygon/star tangent setbacks to actual
native circle radii and back, retaining the independently editable star tip and
indent values. Rectangle corner zero follows the observed native bottom-right
quadrant; the host parameter axes are shifted by a half-turn to preserve its
original contour start, winding and dash phase. Authored radii are the effective
values after the host's existing overlap limits. This does not preserve larger
unfitted slider requests as fictitious native radii.

Direction checks now compare the saved native angles as well as all controls and
centers. Polygon angles account for the native horizontal-side convention rather
than copying the first host vertex direction. Affine fitting selects separated
anchors and removes only zero-length edges, allowing maximally fitted corners
without treating malformed geometry as editable.

These schema interpretations were checked against the pinned Inkscape AI import
reference (`1a5f42a0b0407fc869e032420570682048810108`), its live-shape format notes
and existing rounded-rectangle corpus source data. This is source inspection,
not executed validation or Illustrator certification. No external artwork or
reference implementation was added to the package.

`Ap` is a nonvisual center-point display flag according to Adobe's AI7 format
reference. The host now accepts both boolean values, and native path/shape
replacement preserves assignments in both printing and private interpretations.
`renameObjects` edits literal name aliases on direct paths/shapes/groups while
retaining XML identity and raw artwork. Focale uses it for retained ordinary path
and shape names; name-only saves retain the existing PDF representation.

### Opacity-mask lifecycle — implementation, validation pending

`AiNativeAppearances.createOpacityMasks` and `deleteOpacityMasks` now share the
existing complete printing-owner transaction. Attachments select an exact private
path/group or default to the outer authoring object; missing dictionaries are
created and existing metadata is retained. Several child masks share one complete
printing replacement. Removal deletes the selected field without deleting its
object, other fields or unrelated masks. Mask Art bytes, including counted binary
payloads, are not rewritten by lines.

Appearance binding and mask updates now also qualify masks in a live shape's
authoritative dictionary. Mask creation on a live shape requires no alternate
metadata dictionaries. Printing-side/alternate mask copies remain rejected, and
ordinary geometry transforms/copies retain their mask-synchronization guards.
Resource instances, text carriers, named mask dependencies and identity-bearing
mask lifecycle changes still need their separate contracts. Focale's mask import,
composition and export connection is not established by these package APIs.

Ten regressions cover outer and child ownership, absent/final-field dictionaries,
binary samples, atomic refusal, native identity/cache restrictions and live-shape
creation/update/removal. They are written but unexecuted. Formatting is performed;
tests and analysis remain deferred until the requested implementation is complete.

### Direct-object transparency — implementation, validation pending

`AiNativePathDefinition.transparency` and `replacePathArtwork(transparency:)`
now accept the existing full native transparency value rather than only normal
opacity. Complete explicit tuples flow through direct shape and gradient
authoring; following native/printing state restoration remains shared with the
existing lifecycle transaction. Conflicting opacity shorthand rejects.

Focale maps all sixteen Illustrator blend modes explicitly to its independent
blend enumeration. Path, direct gradient and dynamic-shape import/creation/edit
now retain object opacity, isolation and explicit knockout. Unsupported host-only
blend modes reject. Native inherited knockout and alpha-is-shape need additional
host semantics and still reject; unconnected image/mesh/text carriers cannot
silently discard newly admitted flags. Styled host groups still require their
complete native appearance-owner connection.

PDF composition now creates a knockout transparency group for an opaque single
painted object as well as an ordinary host group. Three package and five host
regressions cover enum mapping, separate state restoration, repeated saves,
gradient/shape carriers, project retention and matching PDF metadata. A sixteen-mode
native/PDF fixture is added to the independent verifier. All remain unexecuted
under the final-only validation instruction; broader appearance/mask integration
and Illustrator exchange remain open.

### Named appearance resources — implementation, validation pending

AiKit can now initialize named appearance resources independently of existing
styles through `createStyle`, and remove unused declarations through
`removeStyles`. Explicit authored basic/compound execution trees reuse existing
process paint, stroke, alignment and transparency definitions. Source-owned graph
children require their separate copy/movement contract. Fresh names, setup
ownership, complete reference scope and allocation limits are enforced.

`applyStyle` selects existing outer or private-child body applications and binds
them to a current style with one complete host printing group per owner. It does
not clone the target resource or change native geometry, masks or identities.
Unselected users remain attached to their former style. Both old/new dependencies
participate in following-state checks, with private scalar restoration only where
the original values can be proved. Resource-local propagation remains separate.

Eight lifecycle and six application regressions are prepared, covering first
resources/new-document saves, basic/nested execution, subsequent editing,
selected child/mask retention, cleanup after rebinding and atomic rejection.
Only formatting and whitespace checks are performed. Focale's full
appearance/mask composition connection remains outstanding, along with the other
requested coverage and final acceptance.

### Initial appearance pairs — implementation, validation pending

`AiNativeAppearances.createArtwork` now accepts a complete host-authored printing
group and private authoring owner with an existing named style. It inserts into
the body, an ordinary group or a current layer without borrowing an existing
appearance object. Private nested/compound/clipping groups and child applications
reuse the established ownership contracts. Qualified authoritative masks can be
supplied with their owner. New identities and mask image cache identifiers are
checked against both retained source and the entire insertion.

The transaction checks the complete provisional owner before publishing a new
snapshot. Scalar inputs must be explicit or provably inherited. Native and
printing outputs are tracked separately, including child styles and private
clipping scopes; restoration protects following retained content. Document
sections, resource declarations and unrelated source owners cannot be captured.
The host supplies the two visual representations, ink bounds and final PDF;
AiKit performs no appearance rendering.

Eight regressions are prepared for first-save native/PDF packaging, nested style
references, compound/clipping owners, opacity masks, separate stream restoration,
identity collisions, detached/opaque input and output limits. They remain
unexecuted under the final-only validation instruction. Formatting and whitespace
checks do not validate behavior. Focale's complete appearance composition bridge
remains open.

### Appearance removal — implementation, validation pending

`removeArtwork` deletes complete current body appearance owners, including private
child applications, native groups/clipping trees, owned opacity masks and
live-shape metadata alternatives. Shared style resources remain declared and can
be removed separately once unused. Geometry, application and identity counts are
checked after serialization; unrelated owners retain their source bytes.

The transaction retains final observable native and printing values separately.
Inner clipping attributes are restored from their scope rather than replayed as
persistent assignments. Unknown effects cannot reach a following read. Selected
identities require complete reference qualification; anonymous deletion can
preserve opaque neighbors when their state remains safe. Reference/dependency
inspection reuses already qualified live-shape owners, including masks, rather
than rejecting them through a narrower duplicate qualification.

Ten regression cases are prepared for first-save removal and unused-style cleanup,
nested applications, stream-specific colors, scoped widths, unknown outputs and
explicit resets, mask/live-shape preservation, opaque references, stale/duplicate
handles, identified mask removal and reversed batches under original limits.
They remain unexecuted. Only formatting and whitespace checks are performed;
the Focale appearance bridge remains open.

### Appearance duplication — implementation, validation pending

`duplicateArtwork` inserts one complete adjacent copy per selected body owner.
Native/printing geometry, private child applications, clipping topology, masks
and live-shape metadata alternatives stay together; named styles remain shared.
The caller supplies exact fresh XML identities for all identified containers,
including mask descendants. Mask raster cache UUIDs are renewed automatically,
while binary samples and placement remain exact. The copy does not add a geometric
offset; Focale supplies the PDF with the corresponding overlap/blending result.

Independent native/printing input replay protects copied geometry and following
source. Required unknown changed inputs reject. Both original and unselected
owners remain byte-exact. Serialization checks topology, application/identity
counts, copied mask cache uniqueness and aggregate limits. Complete-object removal
now includes identified mask descendants under its whole-document reference
check, so such copies can be removed without changing their originals.

Eleven regressions are prepared for new-document saves, nested and compound users,
live-shape alternatives, identified mask copy/removal, binary mask samples/cache
identities, independent input flags, unknown inputs, clipping scopes, reversed
batches and successive copies, exact identity coverage, opaque preserved
references and allocation bounds. They remain unexecuted; only formatting and
whitespace checks are performed. Resource-local lifecycle,
Focale's complete appearance bridge and final acceptance remain outstanding.

### Appearance movement — implementation, validation pending

`moveArtwork` now reorders complete body pairs before/after other pairs or appends
them inside qualified ordinary/clipping groups, layers or the document body.
Source bytes, native identities, mask pixels/cache identities and shared styles
remain exact. Changes to inherited flags, depth, layers or clipping ancestry
require the explicit `inheritParentAppearance` option. Compound, private, derived
and applied-appearance parents remain separate ownership contracts.

Removal and insertion retain independent native/printing boundary states.
Required unknown changed inputs and unresolved effects consumed by following
artwork reject before edits. The host supplies actual ink bounds after changes to
clipping/stacking; document bounds are enlarged when necessary, and the host
composes the matching PDF. Result checks cover topology, applications, identities
and exact bytes of qualified moved and retained owners.

Ten regression cases are prepared for repeated reordering, group/layer changes,
explicit clipping inheritance and same-clip siblings, nested styles/live-shape
alternatives, binary masks/cache retention, unsafe state, invalid/derived targets,
opaque preserved references, bounds and allocation limits. They remain unexecuted.
Only formatting and whitespace checks are performed. Focale's complete appearance
connection, broader native families, resource-local lifecycle and final acceptance
remain outstanding.

### Image, link and mesh transparency — implementation, validation pending

AiKit's shared flagged-artwork insertion now accepts a full native transparency
tuple. `AiNativeImageAttributes.transparency` connects raster/link creation and
exact source copying; `AiNativeMeshArtworkDefinition.transparency` connects direct
mesh creation/replacement. The old normal-opacity shorthand remains available.
Retained raster/link `updateAttributes(transparency:)` changes the whole tuple,
restoring native and printable incoming states independently. Opacity-only edits
still retain other flags, and conflicting inputs reject. Sample planes, preview
rows, external paths, cache identities and mesh corner alpha remain independent
of object blending.

Focale imports and writes the sixteen native modes, isolation and explicit
knockout for images, linked images and the existing qualified mesh profile. New
exports, retained edits and lifecycle copies use the complete tuple. Blending-only
changes invalidate the compatibility PDF, including opaque knockout carriers.
The projection retains linked-preview provenance and continues to reject
unrepresented alpha-is-shape/inherited-knockout flags and host-only blend modes.

Six package regressions and four host regressions are prepared for all modes,
independent state restoration, exact payload/cache retention, repeated saves,
copies/reordering, full PDF synchronization and explicit unsupported fallbacks.
One native/PDF fixture is prepared for the deferred independent rendering phase.
No tests or analyzer were run; formatting and whitespace checks only. Styled
groups, opacity-mask projection, text transparency and the broader remaining
requirements are still outstanding.

### Mixed group lifecycle foundation — implementation, validation pending

Inspection of the host group bridge exposed a missing native contract: mixed
lifecycle accepted only direct layer/root children, even though separate ordinary
group APIs already existed. The common lifecycle now accepts complete ordinary
groups and their direct children. `moveArtwork(group:)` appends paths, images,
links, meshes, gradients and complete groups into an ordinary group while retaining
`parent:` for layers and neither for the global root. Reordering and removal use
the same heterogeneous owner list and preserve independent native/printing state.
Layer declarations remain outside ordinary groups; cycles, conflicting targets,
stale handles and private/clipped/conditional/applied parents reject. Group postfix
qualification now stops at the next independently qualified neutral artwork owner
instead of misclassifying its image/mesh payload as group metadata.

`updateGroupAttributes` and explicit `createGroup(hidden:, locked:)` fields now
assign only flags consumed by the ordinary group opening. Native and printing
inputs are restored immediately inside the group, so child state is retained.
Group opacity/blending still requires the separate appearance owner, rather than
being distributed across children.

Six regressions cover mixed reparenting, nested group/image/link order, complete
subtree moves, deletion/dependency cleanup, independent state and invalid parents.
Four more cover group visibility/locking, independent child state, explicit new
group flags and stale/unknown owners. All ten remain unexecuted. Tests and analysis
remain deferred. The Focale group
hierarchy/appearance/mask bridge still needs its implementation; this is its native
lifecycle prerequisite, not completion of that bridge.

### Focale ordinary groups and grouped text — implementation, validation pending

Focale now imports qualified literal ordinary groups as nonisolated hierarchy
owners. A bounded interval merge combines layers/groups with paths, images,
external links, meshes and text in source order; native group IDs retain the
parser's postorder while the transient lifecycle ledger explicitly uses source
preorder. Names (including literal Unicode), visibility, locking and admitted
transforms connect retained editing. Child attributes and image/mesh alpha remain
separate from group flags, and visual changes rebuild the compatibility PDF.
Panel expansion and neutral mode-nine style resets remain attached native data.

The tree writer distinguishes ordinary groups from layers and uses typed group
or layer destinations for mixed creation, moves, reordering and deletion. Copies
create fresh group/object identities while retaining qualified source pixels,
links and mesh data. Nonisolated new host groups use `u/U`; existing isolated
layer mappings remain at layer/root destinations. A layer/isolated host group
cannot be inserted under an ordinary group without its appearance contract.

Ordinary grouped text is now admitted by the native lifecycle's shared ancestor
qualification, retaining the existing engine/profile/reference checks. Group
panel/reset attachments are excluded only when bound and qualified. Focale
reserves text group positions, authors and composes the story, then moves its
complete drawing reference into the current group. Text edits, copies and removal
retain the enclosing groups and coherent global engine references. Clipped,
masked/private or appearance-owned text remains a separate contract.

Four package regressions and eight host regressions are prepared for nested
ownership, mixed child order, group flags/transforms, source payload retention,
reparenting, copies/removal, real-font grouped text, Unicode labels and neutral
metadata. The independent verifier includes a native/PDF group fixture. No tests,
analysis or independent rendering were run; formatting/whitespace checks only.
Composited group appearances and opacity-mask projection remain outstanding,
alongside the other uncompleted requirements.

### Host-composed raster printing — implementation, validation pending

Ordinary appearance pairs now accept public process raster printing, including a
view containing only images. Existing image framing validates exact sample and
alpha planes, portable placement and complete DSC boundaries. Derived images do
not acquire native object or cache identities. `encodePrintingArtwork` supplies
bounded bytes directly from host samples, and `printingRasters` exposes the
derived representation independently of authoritative paths/groups and masks.

The shared printing transaction retains outgoing scalar state, qualified clipping
and path counts where paths exist. Counts cannot cross an image. Artwork creation
and complete-owner lifecycle account for image input dependencies; masks can use
the same complete raster replacement. Binary data is ignored as syntax only
inside qualified image spans, and unrelated image sections are not inspected by
local binding. Private data, image metadata, compound-contour images and unrelated
annotations reject. Pure raster live-shape expansions remain outside their
existing contour-dependent binding contract.

Ten regressions are prepared for sample depths/alpha, retained authoring and
neighbors, vector/raster replacements, counts, creation/copy/move/removal/save,
group mask lifecycle, binary delimiter bytes, clipping, rejected metadata/state
and limits. None have been executed. Tests and analysis remain deferred; this is
the native serialization prerequisite for host-composed group/mask appearances,
not completion of Focale's adapter connection or Illustrator acceptance.

### Focale appearance composition bridge — implementation, validation pending

`AiDocumentAdapter.composeAppearance` now invokes Focale's existing bounded vector
capture with the original scene resources. Isolated group contents and ordinary
object masks are rendered into straight display-RGB and alpha planes. Root opacity
and blending remain separate so overlapping children do not receive the group's
opacity individually. The immutable revision, original owner, capture extent,
native affine placement and host ink bounds travel together in the result.

`replacementFor` connects this output to the native appearance transaction through
`AiNativeAppearanceReplacement.raster`. The kit serializes the supplied samples
and restores provable original printing assignments; unknown inherited state
rejects. Pixel, byte and memory limits precede capture; images and reservations
are released on failure as well as success, and retained buffers are accounted.
Nonisolated groups, external adjustment owners and overprint still require their
backdrop/separation composition contract. This does not yet connect group/mask
projection and authoring mutations to the automatic encode lifecycle.

Six host regressions cover overlapping child opacity, actual mask rendering,
straight alpha, affine placement, native attachment with retained private groups,
unsupported bounds/backdrops and memory cleanup. Two package regressions cover
source state restoration and refusal of unknown transparency. Tests and analysis
remain deferred; formatting and whitespace checks are the only executed checks.

### New-document group appearance authoring — implementation, validation pending

The new-document writer now captures isolated group appearances when opacity,
blend, knockout or an ordinary-group parent requires a native appearance pair.
Process-painted path children and nested groups remain private native authoring
with fresh IDs, names, independent paint/flags and a conduit/blend style per group.
`createGroupArtwork` shares AiKit's ordinary path serializer and validates the
whole typed private tree before atomic insertion. Root blending is not distributed
to children; the derived image and the original-scene PDF are supplied separately.

The host path recipe is shared between ordinary creation and private children.
Aggregate image/capture pixels remain bounded. Native ordinary creation resolves
qualified appearance prefixes and separate scalar state, allowing later paths,
images/meshes, gradients and groups instead of stopping after the first pair.
Unknown owners retain their existing barriers. Four native and three host
regressions cover typed hierarchy, flags/identities/styles, duplicate and unknown
references, mixed following artwork, nested export and PDF content preservation.
An optional group-appearance fixture can be emitted by the host regression.

No tests, analysis or independent renders have run. Native import/projection and
retained edits of these appearance pairs remain outstanding, so Focale still uses
its explicit PDF fallback when reopening them. Private images, gradients, text,
live shapes and native mask authoring need their next connections; this is not
completion of the group/mask or overall interoperability requirements.

### Private group scene projection — implementation, validation pending

Focale now binds ordinary private group appearance pairs before projecting the
scene. Each visible conduit/blend chain supplies explicit group opacity, blend,
isolation and knockout; its private path children retain their own process paint,
geometry and flags. Unknown fields, hidden parts, masks, compound/clipping owners
and other style graphs still require the compatibility import. The corresponding
printing groups and images are excluded from host artwork, while their scalar
state remains part of source-order replay so following owners inherit correctly.
Native path and group indices remain tied to the full native inventory, including
private authoring, rather than the public printing-path list.

Five additional regressions are prepared for nested native reopening without
image duplication, no-op/project round trips, ordinary-neighbor edits with exact
pair preservation, mixed source ordering, explicit refusal of unconnected private
mutations and compatibility fallback for hidden style parts. None have run.
Retained appearance edits and complete-owner lifecycle still need their atomic
host-composed transactions; the adapter rejects those mutations explicitly while
allowing unchanged pairs during ordinary neighboring edits. Tests and analysis
remain deferred. This is not Illustrator acceptance or completion of the goal.

### Retained private group blending — implementation, validation pending

Retained saves now prepare one host composition per changed complete private group
owner. Outer and nested opacity, blend mode, isolation and knockout changes select
the exact native group application through its unchanged authoring child route.
AiKit's `updateSelected` copies/rebinds that application and replaces its complete
printing view; other users of a shared style retain their original definition.
Qualified unused source styles remain preserved and projectable after a selection
is rebound. All source handles are reacquired after each immutable transaction.

Ordinary object edits consume their original native indices before appearance
printing is replaced. The final native program and host PDF use the same edited
scene; no intermediate partial style revision is returned. Captures and final
native images share an aggregate pixel limit, including linked previews. Geometry,
metadata, masks and lifecycle changes within these private groups still require
additional authoring transactions. Independent capture of a nonisolated outer
group continues to reject because it requires the external backdrop.

Four further host regressions are prepared: simultaneous outer/nested changes
with matching sample planes and PDF, repeated saves and untouched child geometry;
a combined ordinary-neighbor edit; isolation of one shared-style application; and
refusal of backdrop-dependent capture. The earlier group-blend rejection case is
replaced by these save cases; the private child mutation guard remains covered.
No tests, analyzer, independent rendering or Illustrator exchange have run for
this increment. Only formatting and whitespace checks have been performed.

### Private appearance geometry — implementation, validation pending

AiKit now provides `AiNativeAppearances.editArtworkPaths` for complete body
appearance owners. Selected private contours and host printing replacements are
written atomically; point counts and closed endpoints follow the new geometry.
Source closure, clipping/compound roles, paint, masks, identities and references
remain retained. Optional explicit frame directions apply to private paths and
groups. The transaction rejects stale/missing/extra ownership, mask-role changes,
derived printing geometry, resource-local owners and live-shape parameter bypass.
It reuses the existing bounded contour writer, extended for closed clipping paths.

Focale's retained appearance preparation now records private child routes for
geometry as well as styles. Anchor/control changes and private-group transforms
are baked into native coordinates. Ordinary ancestor transforms feed both native
contours and the composed printing placement, while PDF normalization transfers
the inherited transform to the private root before clearing ordinary parent
transforms. Existing native frame metadata follows the same affine direction.
Geometry, blend changes and ordinary neighboring edits can share one final save.
Paint and metadata changes remain separate, and stroked transforms currently
require isometry to avoid leaving widths and dashes unsynchronized.

Six native regressions cover private counts/metadata/neighbor preservation,
nested and compound children, clipping mask closure variants, exact ownership,
live-shape rejection and output limits. Five host regressions cover curved anchor
edits with identities and same-revision pixels/PDF, reflection/shear/nonuniform
unstroked resizing, ordinary-parent placement, combined geometry/style/neighbor
changes and refusal of unsupported stroke deformation. None have run. Formatting
and whitespace checks are the only executed checks; the overall goal remains open.


### Private process paints and scaled strokes — implementation, validation pending

AiKit's `replaceArtworkPaths` now accepts complete process paint/geometry changes
for independent private group children with complete printing-owner coverage.
Fill/stroke creation and removal, closure/counts, winding, width/cap/join/miter,
dash arrays/phase, visibility/lock, overprint and full transparency are serialized
without replacing child metadata or style references. Known original scalar
values are restored after the child's dictionary. The shared dependency walker
models explicit replacement writes/reads and rejects unknown outgoing values that
following artwork consumes before a definite reassignment. Clipping ancestors
remain supported for independent children; compound/mask contours and attached
child styles retain their dedicated contracts.

Focale prepares complete private paint recipes alongside geometry/frame changes
and selected group blends. All operations use the single final-owner capture;
source handles are rebound between immutable transactions. Uniform scaling,
including reflection, changes stroke widths and absolute dash metrics with native
geometry. Nonuniform stroked transforms still require expanded native appearance.
Private names/metadata and gradient resources keep their guards; overprint capture
continues to require separation-aware composition.

Seven native regression cases cover scalar restoration, metadata/identity/neighbor
preservation, fill/stroke roles and repeated closure changes, unknown-state reads
versus overwrites, multiple same-line child changes, clipping ancestors, output
limits and exact ownership/style guards. Host regressions replace the
former process-paint refusal with same-revision native/pixels/PDF assertions,
repeated visibility/paint saves, uniform stroke scaling, unpainted open contours
and the remaining metadata guard. Tests and analysis have not run, by request.


### Private clipping projection and retained saves — implementation, validation pending

Focale now imports private `q`/`Q` appearance groups whose first child is one
unpainted independent clipping contour. The contour becomes a group `VectorMask`,
with native geometry/identity retained in source instead of duplicated as a painted
child. Nested clips and private groups without named blend applications are
qualified explicitly. Painted/compound or multiple sequential mask owners still
require their broader projection; opacity-mask artwork remains a separate family.

Retained edits use native authoring routes rather than displayed child indices.
Mask outlines, descendant geometry/paints and group blending can therefore share
one final capture and PDF. Affine transforms carry masks and children together;
existing mask metadata follows the geometry transaction. Source `H`/`h` roles and
point counts remain coherent, while disabling/removing masks or changing winding
still requires a native role transaction. The scene reader also restores native
line width/cap/join/miter/dashes at clipping exits, including derived printing
scopes, without restoring persistent paints or object flags.

Six deferred host regressions cover open/closed mask projection, combined mask,
paint and blend saves with native identities and matching pixels/PDF, repeated
saves, nested affine placement, unstyled clipping groups, scoped stroke metrics,
and rejection of unsupported role changes. No tests or analyzer were run.


### New-document private clipping authoring — implementation, validation pending

AiKit's typed private group definition now accepts `AiNativeAppearanceClipDefinition`.
Each optional prefix clip supplies one immutable native contour, explicit open or
closed clipping, winding, count convention and optional fresh name/identity. The
writer shares the bounded path serializer, emits an unpainted mask inside `q`/`Q`,
and keeps nested scopes and all ordinary content children independent. The root's
host printing view, identity/reference checks and outgoing-state checks remain the
same complete-owner transaction.

Focale now detects enabled single-contour group masks during new-document export,
prepares one complete appearance capture and authors the native clip alongside its
private children. Mask coordinates follow the same composed ancestor transform;
fresh mask identities and source labels remain separate from group identities.
Newly exported clipped groups use the preceding native import and retained-edit
connections. Disabled/frame/compound masks, other carriers and nonisolated outer
captures remain separate work, without implicit flattening or dropped mask data.

Three native regression cases cover open/closed counted/uncounted clips, metadata
and identities, nested scopes and following ordinary artwork, invalid role/data
and duplicate identities. Three host cases cover creation without a template,
same-revision printing/PDF and a subsequent outline edit, transformed nested masks,
and unsupported mask metadata rejection. Tests and analyzer remain deferred; only
formatting and whitespace checks have run.


### Typed opacity-mask artwork and carrier binding — implementation, validation pending

The existing mask lifecycle takes exact Art bytes. AiKit now exposes
`AiNativeOpacityMask.encodeVectorArtwork` so hosts can provide immutable process
paths/groups instead of writing private AI syntax themselves. The bounded writer
retains explicit colors/line metrics/transparency, counted geometry, escaped labels
and nested clipping groups; empty masks remain explicit. It emits either source
representation with complete `X=`/`X+` boundaries. Named applications and XML
identities reject under the existing mask-reference restrictions.

`AiNativeAppearanceArtwork.authoringForMask` now resolves each current mask to its
exact authoritative outer/child path or group. This will let Focale bind masks by
carrier instead of inferring ownership from their source order. Mask-local content
stays inside its Art payload and never gains an independent printing owner.

Six native regression cases cover typed payload attachment and nested clips,
repeated replacement/removal without identity loss, private/public prefixes and
escaped names, dependency rejection, exact carrier selection including stale and
foreign handles, and bounded output. These tests have not run. Focale composition
already has luminance masks and an enabled flag, but native linked placement,
clipping background and inversion still need explicit projection/save handling;
this increment does not claim that connection is complete.

## Opacity mask coverage semantics in Focale (implementation, validation deferred)

Focale now retains `maskInverted` and `maskClips` in immutable vector objects and
project serialization. The shared compositor receives inversion and the luminance
background through `LayerMaskSource`: artwork is isolated over black/white,
coverage is then complemented if requested, and density/feather follow. Alpha
masks ignore the background parameter. Defaults preserve existing files.

The bounded mask capture, editable pixel-mask projection and SVG/PDF preparation
consume those same parameters. Derived grayscale masks reset consumed flags;
export reporting exposes mask rasterization and vector-only review refuses it.
Explicit object reconstruction in stroke expansion, projective transformation
and PDF alpha preparation carries the new fields. Pixel-mask editing also resets
consumed flags when publishing its already-composed coverage.

Regression cases were added for numeric alpha/luminance coverage, translucent
mask paint, both backgrounds, inversion, density, optimized/unoptimized
composition, immutable persistence, disabled masks and derived export capture.
They have not run; analyzer and tests remain deferred as requested. Native AI
mask projection/save and linked/unlinked placement remain outstanding. This
increment establishes host coverage semantics, not complete AI mask support.

## Unlinked opacity-mask affine placement in Focale (validation deferred)

Focale objects now retain `maskLinked` (default true) through immutable copies,
project JSON, derived object reconstruction and pixel-layer/clipboard projection.
The existing vector mask panel exposes linking. Canvas selection transforms and
inspector/action deltas use `ObjectTransformTargets.writeVector`, which reuses
`LayerMaskTransform` to keep an unlinked mask fixed in the owner's parent space.
Disabled masks compensate too. Singular owner placements reject explicitly.
Internal reference-frame copies remain ordinary copies: regrouping or export
must not be interpreted as an authored movement relative to the mask.

Portable transform recording recognizes the automatic compensation, records the
delta without serializing unchanged mask payloads, and replays the compensation
with other supported property edits. Independent mask edits and reference-frame
copies do not masquerade as that portable delta. Pixel-mask editing retains its
link setting when returning to the vector document.

The vector mask panel now inverts its retained coverage flag without rasterizing
editable content. Layer mask thumbnails use the shared compositor, including
background, inversion, density and feather, even when coverage is disabled.
Regression cases cover affine families, nested selections, disabled/linked masks,
serialization, action recording/replay and refusal, undoable panel actions and
numeric thumbnail coverage. None has run; analyzer/tests remain deferred.
Native AI projection/save and non-affine deformation coverage are still pending.

## Native opacity-mask vector projection (implementation, validation deferred)

Focale's native appearance inventory now binds each mask to the exact carrier
returned by `authoringForMask`. Private outer groups, child groups and independent
private paths attach the mask as auxiliary editable content; the Art payload is
never inserted into the visible document hierarchy or replayed into owner state.
Clipping contours cannot silently acquire an unprojected opacity-mask carrier.

The host reader projects process-colored paths and ordinary/clipping groups,
retaining scalar paints, line metrics, opacity, visibility, locks and labels.
Nested mask metadata uses the same reader. Each drawing gets an independent
paint-state scope, q/Q line metrics restore, and native layers are excluded from
the mask-local hierarchy. Empty masks remain explicit. All four native settings
map to the host's luminance mask fields. Aggregate mask complexity is bounded to
10,000 host objects and 32 nested masks.

Images, gradients, dynamic shapes, compound contours and unqualified operators
inside mask payloads still require their specific host projections; they reject
rather than disappear. This increment does not yet implement changed-mask save
or initial Focale mask export. Native mask lifecycle APIs remain available in
AiKit for that next connection.

Deferred regression fixtures construct native masks with independent host printing
and PDF, then cover exact root/group/path carrier binding, private clipping,
all empty-mask background/inversion combinations, disabled content and an
unchanged save/reopen. Tests and analysis have not run.

## Retained native opacity-mask transactions (validation deferred)

Retained private appearances now prepare mask creation, settings/content updates
and deletion alongside path geometry, process paint and selected group blending.
Each change addresses its carrier by the original private child route and rebinds
after prior mutations. All operations use the same final host-composed printing
capture; the enclosing save supplies the corresponding PDF revision.

Settings-only edits leave native Art bytes intact. Changed content uses AiKit's
typed vector mask encoder, with final ancestor/object transforms folded into
mask geometry. This also saves the host's inverse mask placement after an unlinked
owner move. Imported virtual whole-Art groups are not emitted as a new nested
group on every save. Actual clipping, hidden/locked groups and renamed wrappers
remain authored structure. Empty whole-mask payloads remain explicit.

Process contours, ordinary local groups/clips and rectangle coverage can be
created as editable native mask paths. Density/feather, alpha-only masks, nested
mask rewrites, named group blending, richer content families and referenced mask
identities retain their explicit rejection contracts. Existing complex payloads
remain byte-exact during settings-only changes when import supports them. Initial
mask export from new Focale documents is still a separate pending connection.

Deferred regressions cover settings plus group blending with byte-preserved Art,
repeated clipped-mask repaint without wrapper growth, delete/recreate on an exact
child carrier, and an unlinked transformed owner with stationary native mask
geometry. Each checks saved printing samples and matching PDF against the edited
host revision, then reopens it. Tests and analysis are still not executed.

## Initial masks inside native group appearances (validation deferred)

The new-document writer now captures an isolated group when it or a descendant
owns an opacity mask, including an otherwise plain group. Before capture it
qualifies mask vectors and their final native transforms through the same typed
mask recipe used by retained saves. Source authoring remains separate from the
composed image.

Fresh group/path identities bind every mask to its exact newly created carrier.
After creating the private group tree, one native mask transaction attaches all
outer/child group/path masks with their four settings and the same host printing
capture. The original scene supplies the final PDF. Multiple masks on different
carriers in one owner do not acquire separate printing ownership.

Deferred new-document regressions cover simultaneous root, child-group and path
masks, disabled/unlinked/inverted settings, a masked child triggering an otherwise
plain group's appearance, native carrier names, printing samples, matching PDF,
full host appearance and a changed save after reopening. Tests and analysis remain
deferred.

Standalone masked leaves are connected in the subsequent increment below.
Masked pass-through groups without an isolated appearance ancestor still require
their backdrop-dependent carrier connection. Richer mask
content and non-neutral coverage controls retain the previously documented
limits; this increment does not mark overall mask or AI integration complete.

## Typed standalone appearance contours (validation deferred)

AiKit now exposes `createPathArtwork` for a private unpainted contour whose
existing named style supplies the paints. Its independent host printing remains
a complete group, but no group is introduced into native authoring. The ordinary
path serializer retains closure/counts, flags, label and fresh XML identity;
painted path definitions reject instead of silently discarding their paints.
The complete-pair insertion retains existing ownership, identity, dependency and
bounded-output checks.

Deferred regressions cover open/closed counted/uncounted creation, exact path
mask attachment, disabled/unlinked/inverted settings, geometry editing followed
by a full native/PDF save, preservation before following ordinary artwork, and
atomic rejection of ambiguous paints, missing styles or duplicate identities.
No tests or analysis were run for this increment.

The following increment connects this serialization prerequisite to Focale.

## Standalone masked process paths in Focale (validation deferred)

Initial export now captures masked process contours directly, including under an
ordinary pass-through parent. It authors a private unpainted path, a named chain
containing an explicit fill/stroke stack and whole-object blend, and the separate
host printing image. The mask attaches to the path's own metadata; no authoring
group is synthesized.

Import qualifies that complete style graph and its literal paint dictionaries.
Independent process colors, centered stroke metrics/dashes, winding and outer
blending project onto the path, whose `n`/`N` role does not mean absent paints.
The style's scalar output is replayed at its actual source application for
following artwork. Hidden, extended, inherited, repeated or otherwise ambiguous
paint stacks retain compatibility fallback.

Retained saves reuse complete-owner geometry and mask transactions. Paint changes
create and apply a fresh style to the exact selected owner, preserving the old
declaration and any other users. Printing and PDF use the same host revision.
Mask settings, content, removal and recreation share the existing path/group mask
transaction. At that increment, empty paint stacks, gradients, named inks and
richer private families remained outside the projection. Named inks are connected
in the later private-appearance increment below.

Added deferred cases cover fill-only/stroke-only/combined paints under a
pass-through parent, following artwork, no-op byte preservation, exact path mask
ownership, unlinked placement during geometry/paint edits, mask removal, matching
printing/PDF and unknown-style fallback. No tests or analyzer were executed, and
actual Illustrator exchange remains unverified.

## Standalone contour closure and flags (validation deferred)

AiKit's `replaceArtworkContours` updates complete standalone private contours and
their printing groups together. It preserves the source style use, metadata and
mask bytes, synchronizes counted closure, and restores original native/public
flags after the selected owner. Printing dictionaries and optional expansion
commands keep their exact ownership. Unknown flag inputs reject explicitly.

Focale uses this transaction for open/closed, visible/hidden and locked/unlocked
changes. Those edits no longer force a duplicate style when paints are unchanged.
Geometry/frame edits, paint edits and mask edits can join the same prepared save,
using one host capture and the same PDF revision.

New deferred cases cover repeated open/closed and flag cycles, counted and
uncounted contours, printing expansion/dictionary ownership, exact mask and style
preservation, following native/public state, stale or incomplete ownership and
unknown restoration inputs. Focale cases compare repeated saved printing/PDF and
reopened visibility, locking, closure and rendered appearance with neighboring
artwork. No tests or analysis have been run for this increment.

## Private authoring display names (validation deferred)

AiKit now renames standalone private paths and private groups/descendants through
`renameArtworkObjects`, with exact complete-owner coverage. Existing alias types,
identities, style applications, geometry, printing and mask Art remain unchanged.
The shared name writer also fills empty string fields and correctly appends a
name after a final dictionary field without a comma.

Focale prepares source-encoded labels by stable private child route and applies
them after any geometry, paint and mask changes. A name-only revision skips
appearance composition entirely and retains the original printing bytes. Names
can also join one visual save without interfering with source handle rebinding.
Mixed alias encodings and richer metadata retain explicit qualification.

Deferred regressions cover simultaneous parent/child names, missing dictionaries,
empty aliases, final field delimiters, exact printing/style/mask preservation,
rejected printing or mask-local handles, source immutability, standalone naming
and a subsequent combined name/paint/mask save. Tests and analysis are not run.

## Mixed appearance placement anchors (validation deferred)

Complete appearance movement now accepts `beforeObject`/`afterObject` for qualified
ordinary artwork, in addition to complete appearance anchors. Positions encompass
counts and metadata; layer/image wrappers rebind only through exact source handles.
Private and derived descendants reject. The existing independent native/printing
state restoration and inheritance policy apply at both movement slots.

Deferred regressions cover repeated movement around a counted named contour,
separate scalar state, complete group/layer boundaries, stale handles, printing
descendants and conflicting destinations. This is a package prerequisite: the
Focale lifecycle ledger still needs complete appearance ownership and must not
drop its guard merely because precise placement is available. Tests and analysis
have not run for this increment.

## Complete appearance lifecycle ledger (validation deferred)

Focale's native lifecycle ledger now treats each imported outer appearance as one
owner. Its private children, masks and printing images remain inside that owner;
ordinary path/group/image inventories exclude those derived source spans.
Identity, parent and stacking checks run against the complete outer pair.

Source-backed saves prepare retained private edits before structural mutations,
then remove complete missing appearances, reparent retained pairs and order mixed
sibling slots. Ordinary relative order is applied separately, followed by exact
complete-pair placement. AiKit's ordinary-slot permutation and path repainting
now retain qualified neighboring appearance state in both interpretations.
Private/printing contours still cannot be repainted as independent objects.

Deferred regressions cover masked path/group deletion with an ordinary neighbor
edit, interleaved ordering, reparenting into an ordinary group and deletion after
reopening. They compare reopened pixels and compatibility content where applicable.
Tests and analysis remain deferred. New appearance copies, broader ordinary
subtree mutations containing appearances and mixed unsupported source preservation
still require their remaining integration; this entry does not certify those paths.

The next requested work is mixed-file preservation and complete validation.

## Mixed preserved appearances (validation deferred)

Focale now retains qualified complete appearances whose authoring profile is not
projectable as locked printing subtrees. Public ordinary paths and process images
use the existing host projection; no printable descendant is promoted to editable
native authoring. Known outgoing state is obtained from AiKit in one batch and
replayed before following supported objects.

`AiOrigin.preservedObjects` persists explicit reasons through project recovery.
Supported neighbor content edits keep the original private pair, masks and shared
style declarations byte-exact, verified before save. This initial mixed contract
retains topology/pages and the preserved owners' ancestor attributes. Unresolved
state, unknown ownership and unsupported printing still use full PDF fallback.
Broader mixed lifecycle and public compound/clipping printing remain further work.

Deferred cases cover state inspection and immutable/foreign handles, compound
authoring with raster or vector printing, ordinary neighbor repaint, exact source
retention, project recovery, repeat saves and rejected proxy/ancestor changes.
No tests or analysis have run for this increment; no Illustrator exchange is
claimed by these synthetic regression fixtures.

## Remaining compatibility limits

- Mixed preserved owners retain topology, pages and ancestor attributes. Broader
  mixed lifecycle and public compound/clipping printing need explicit contracts.
- Arbitrary source-appearance copies, broader mutations of containing ordinary
  subtrees, complex/threaded/path text, pattern/brush/symbol/effect authoring and
  arbitrary named resource libraries are not certified by this integration.
- Native document save checks and independent readers do not establish an actual
  Focale → Illustrator → Focale editing exchange. That platform check remains open.

## Final local validation

On 2026-11-02, with Dart 3.13.5 / Flutter 3.47.7 on Linux:

- AiKit: 1,443 tests pass on VM and Node. The final explicit preview-branch
  compatibility change also passes 36 focused Node cases and a repeated complete
  VM suite. `dart analyze` reports no issues; formatting and diff checks pass.
- Focale: all 470 tests in the final extended campaign pass with the Git-locked
  dependencies, after incorporating the concurrent upstream changes. They cover
  AI/PDF/device-gray round trips, mesh rendering/interchange, gradient precision,
  editor masks, text capture, project recovery and source editing. The analyzer reports no
  errors or warnings (550 informational lints remain across the application).
- Both corpus runners report 40/40 required outcomes; manifest size/checksum
  verification passes. New documents, text creation/lifecycle, colors, affine
  changes, images, transparency and masks pass their independent verifiers.
- The unchanged pinned inkai revision
  `1a5f42a0b0407fc869e032420570682048810108`, pypdf and Poppler verify 22
  Focale-authored AI saves, including exact PDF pixels, page ownership, native
  geometry, image samples, header caches and repeated edits. Independent mesh
  geometry and the two producer appearance/rendering checks also pass.
- The pinned parser does not model every placement/header construct. Explicit
  source assertions supplement its link-state interpretation; its reference code
  remains unchanged. Unchanged bounds now retain their lexical spelling.

Validation found and corrected outgoing appearance-state restoration, layer/group
flag ownership, text-container projection, image incorporation terminators, PDF
page identity, complete-mask PDF preparation and exact DeviceGray interpretation.
The editable-font fixture explicitly permits editable incorporation; preview-only
fonts retain their original restrictions. No Illustrator exchange is claimed.

## Fresh appearance insertion in existing AI files

Focale now shares its initial appearance authoring implementation with the retained
native lifecycle writer. New isolated groups and standalone masked process paths
can be inserted into existing layers, ordinary groups and the global canvas. Native
styles, private descendants, exact mask carriers and supplied printing are created
together with deterministic fresh identities. The lifecycle ledger preserves complete
pair ownership and mixed sibling order, while the final PDF uses the same revision.

The qualified private process-path/group subset is unchanged. Retained source
children cannot be silently regenerated inside a fresh pair; unsupported conversions
are rejected before saving. Exact duplication of arbitrary source appearance graphs
and further private families remain separate work. Integration regressions cover
creation, nested masks, clipping, repeated saves and preserved neighbor bytes.

Validation on 2026-11-02: all 479 tests in the extended Focale AI/PDF campaign pass,
including nine new lifecycle cases. Full application analysis retains the existing
550 informational lints, with no errors or warnings; formatting and scoped fix
checks pass. The independent verifier checks 34 complete saves: the previous 22
plus 12 new group/path appearances at layer, ordinary-group and canvas scope across
two revisions. It checks exact mask carriers/settings, native identities, composed
image state, current header caches and exact Poppler PDF pixels. AiKit runtime
sources are unchanged by this addition. No Adobe Illustrator exchange is claimed.

## Global named-ink alternatives in AiKit

The package now exposes one source-backed ink inventory and an atomic redefinition
transaction across ordinary paints, appearance styles, palette cells, gradients,
mesh declarations and literal DSC alternatives. Native names and tints remain
unchanged; all required device alternatives come from the host. Complete printing
owners and gradient ramps must be supplied with the change. Unknown cross-references
and unsupported text/color-book dependencies are explicitly rejected.

This supplies the package operation for document-wide ink changes. Focale's
ordinary custom-color bridge below consumes it; further named-color families and
resource-dependent printing still require host integration.

Validation on 2026-11-02: all 1,459 AiKit tests pass on both Dart VM and Node,
including 16 global-ink regressions. Analysis, formatting and the scoped fix check
pass. The unchanged pinned inkai reader and pypdf independently verify four
complete compressed saves over two revisions: exact names/tints, palette cells,
paired gradient banks and ramps, mesh alternatives/controls, DSC caches, shared
appearance printing and supplied PDF streams. Independent color, transparency and
opacity-mask checks also pass. These checks establish stored representation and
reference consistency, not native/PDF visual equivalence or Illustrator interchange.

## Shared custom-color masters in Focale

Focale projects literal `x`/`X` and `Xx`/`XX` CMYK/RGB custom colors into its
existing document-color library. Byte-based identities are stable across saves;
display labels do not identify native resources. PDF spot plates retain exact
native name bytes, including legacy non-UTF8 names. Each admitted ink has a
consistent device alternative; incompatible same-name alternatives reject native
projection rather than collapse distinct appearances.

The host maps the native paper-fraction operand to its ink fraction (`1 - tint`),
following Adobe's AI7 file format specification, section 5.4, pages 60–61:
[Adobe specification mirror](https://13thmonkey.org/documentation/fonts/AI7FileFormat.pdf).
AiKit continues to preserve the native operand without interpreting it.

Editing a shared master updates all admitted native references using `AiNativeInks`,
reprojects the canonical device alternatives and regenerates the matching PDF spot
plates. Subsequent geometric edits use this new immutable baseline, so a combined
master/path change cannot accidentally detach each paint into a process color.
Project persistence and repeated saves retain the shared identities.

This bridge covers ordinary custom-color artwork in retained legacy and CC files.
The authoring extension below adds initial palettes and per-object tint changes.
Deleting referenced native resources, renaming,
`Xs`/`Xz` semantics, and global revisions needing composed appearance, gradient or
mesh representations remain additional work. Such mutations reject before saving.
Native color alternatives are converted by Focale when needed, never by AiKit.

Validation on 2026-11-02: the combined host campaign passes 275 cases; the final
eight-case focused run additionally verifies CC artboard/object identity retention.
Application analysis has no errors or warnings and retains the 550 existing
informational lints. The pinned independent native reader, pypdf and Poppler pass
38 complete saves, including four new CMYK/RGB shared-ink revisions. The new checks
assert exact native alternatives and names, inverse native/PDF tints, PDF Separation
functions and exact rendered pixels against the host reference PDFs. No Illustrator
reopen/editability exchange is claimed.

## Initial spot palettes and local named paints

New Focale documents now serialize their CMYK/RGB spot masters into native palette
cells before authoring artwork. Unused masters survive save/reopen. Palette and
artwork paints retain the same exact native ink identity; two host masters cannot
silently introduce conflicting native names. Shared process-color libraries and
nonlinear or non-device spot functions still require their own typed contracts.

Ordinary paths accept independent named fill/stroke channels when created or
repainted. A local tint change keeps the shared definition and other applications
unchanged, including inherited outgoing state. Retained documents can create a new
path using an existing ink or add a fresh master and its first application in one
save. Unused palette masters can be removed after AiKit proves that no references
remain outside their cells. Host resource IDs are rebound to canonical native byte
identities before the remaining object edits; existing masters and paths remain
unchanged. Direct live-shape creation and parameter replacement
preserve named paints, as do gradient strokes and conversion from a gradient to a
named solid fill. Private paint stacks retain their separate complete-appearance
requirements; they cannot silently flatten a named paint into process channels.

Literal process/named palette cells are now qualified as independent of ATE
indices during text initialization and story lifecycle. Their complete source
bytes remain unchanged. Conditional, compound-gradient and unrecognized cells
still reject; this does not authorize global edits of ATE named colors.

Validation on 2026-11-02: all 1,467 package tests pass on VM and Node, including
seven named-path cases and one palette/text lifecycle regression. Package analysis,
formatting and scoped fix checks pass. Fourteen focused host ink tests pass.
Independent verification covers 40 complete host saves, with two additional
initial-palette/local-tint revisions checking unused masters, native state at each
contour, inverse PDF ink amounts and exact PDF pixels. The final Node run includes
the repaired absent-named-paint case; the serializer uses explicit nullable-channel
checks instead of destructuring nullable records. No Illustrator exchange is claimed.

## Named paints in private appearances

The host now binds custom CMYK/RGB inks in standalone fill/stroke styles, private
group contours and opacity-mask Art to the same document color table. Initial
creation and selected paint edits retain exact names and independent tints.
Style application replay retains both its execution position and the original
paint assignment position, so following artwork receives the correct named state.

Global master revisions supply freshly composed printing for every editable
appearance owner, including mask coverage, and then derive the compatibility PDF
from the canonical native revision. Combined geometry/lifecycle edits are saved
first, before ink-driven printing replacement can renumber native path handles.
Ink-dependent preserved owners, named gradient/mesh composition and separation-aware
overprint captures retain explicit rejection. Illustrator exchange remains an
external acceptance requirement.

Validation on 2026-11-02: all 1,475 package tests pass on VM and Node, including
eight private named-paint and mask-reference cases. Package analysis is clean;
formatting and scoped fixes pass. The 288 AI/PDF/source/prepress/color host tests
pass, including six new private-ink cases. Application analysis has no errors or
warnings (550 existing informational lints). Independent readers and Poppler pass
48 complete saves, including eight private-ink revisions with exact native
alternatives, mask references, refreshed printing and reference PDF pixels.
This remains local format/rendering evidence, without Illustrator certification.

## Ink revisions in mixed documents

A global custom-ink revision retains unrelated preserved appearance pairs after
AiKit proves that neither their authoring nor printing interpretation consumes the
ink, directly, through a style/resource, or through inherited paint. Their complete
source bytes, masks and referenced style definitions remain exact. Focale composes
only affected editable owners and the resulting compatibility PDF. An affected
preserved owner still rejects the revision atomically.

User changes to preserved proxies and ancestors are checked before any printing
replacement can renumber projected paths. Reprojection then binds canonical native
IDs; exact source checks remain mandatory. Regression cases cover vector/raster
printing, optional editable appearances before the preserved pair, two revisions,
a simultaneous neighbor translation, and rejection of ink in preserved authoring
or mask Art. Independent checks bind the preserved compound through the external
parser, compare all saved owner/style spans and render the final PDF against the
host reference. Illustrator exchange remains a separate external acceptance gate.

Validation on 2026-11-02: all 1,482 package tests pass on VM and Node, including
seven dependency/retention regressions. Package analysis is clean. The 294
AI/PDF/source/prepress/color host tests pass; full application analysis reports no
errors or warnings (550 existing informational lints). Formatting and scoped fix
checks pass. Independent native/PDF readers and Poppler validate 56 complete saves,
including eight mixed-ink revisions with byte-exact owner/style/mask/printing
preservation and matching reference PDF pixels. This is local evidence; no real
Illustrator round trip has been performed.

## Supported neighbor lifecycle in mixed documents

Preserved complete pairs participate in the host's native lifecycle ledger as
opaque appearance owners. Their printable descendants never become independent
editable paths or images. Focale can create, delete, duplicate, reparent and reorder
supported neighbors while retaining each preserved pair's parent chain, ancestor
attributes and complete native data. Page edits and direct preserved reparenting
remain rejected.

Source indices may change when an editable appearance is inserted or removed.
Preservation therefore matches complete source bytes with multiplicity and checks
all referenced style definitions, rather than reusing the old appearance index.
Regressions combine neighbor deletion, creation of a new appearance and ordinary
group, reparenting, duplication, stacking changes, project recovery and two complete
saves beside vector/raster printing. Independent readers check retained compounds,
style/mask/printing bytes, native object names/order and exact reference PDF pixels.

Validation on 2026-11-02: 1,486 package tests pass on VM and Node, including four
ordinary-neighbor movement/removal regressions. The final focused Node run also
checks local anonymous deletion against the final reference guard. All 297
AI/PDF/source/prepress/color host tests pass, including three mixed-lifecycle
regressions. Package analysis is clean; application analysis has no errors or
warnings (550 existing informational lints). Formatting and scoped fixes pass.
Independent native/PDF readers and Poppler verify 60 complete saves, including four
new mixed-lifecycle revisions. Actual Illustrator exchange remains unverified.

## Artboards in mixed documents

Mixed documents now use the existing artboard lifecycle without freezing every
page rectangle. Focale can resize, rename, add, duplicate, reorder and remove pages
while retaining the single shared native drawing. New page backgrounds and children
remain ordinary native artwork; deleting a page does not discard that shared art.

The page transaction checks complete preserved owner/style bytes after both artwork
and artboard edits and before encoding the synchronized PDF. Preserved proxies and
their ancestor chains remain protected. Existing page geometry, identity, minimum
page count and native metadata guards still apply. Regressions combine vector/
raster printing with two repeated page transactions, fresh background/child
artwork, supported neighbor changes and project recovery. Independent readers
check stable retained native/PDF page identities, current headers, one shared
native program, exact preserved bytes and rendered pixels on every output page.

AiKit's mixed-container lifecycle now retains complete qualified appearance
children when moving or reordering ordinary groups/layers. Removing a complete
container removes its owned pairs while keeping shared styles and restoring both
boundary states. Source byte spans, nested style dependencies and native clipping
scopes remain distinct from ordinary children; partial representation selections
continue to reject. Regressions cover both container families, clipped authoring,
separate inherited native/printing paints and atomic partial-selection rejection.

Local validation passes 1,491 package tests on both VM and Node, 300 Focale
AI/PDF/source/prepress/color tests, and 64 independent complete-save checks. The
four new mixed-page outputs retain page/board identities and exact preserved data
with matching per-page Poppler pixels. Package analysis is clean; host analysis
has no errors or warnings (550 existing informational lints). Formatting and
scoped fix checks pass. Actual Illustrator exchange remains unverified.

### Reusable native artwork declarations

AiKit now provides `AiNativeArtworkResources.create`, `replaceUnused` and `remove`
for literal pattern tiles, symbol masters and brush artwork, with dependency,
identity, symbol-panel and source-preservation checks. Focale can supply their
native artwork without introducing rendering into the format package. This does
not yet connect Focale's tiling/symbol/brush models: instance serialization,
application descriptors, dependent printing and effect authoring remain separate
integration work. The acceptance producer verifies unused native libraries and
unchanged host PDF pages; it does not certify an Illustrator exchange.

Local validation for this package lot passes 1,504 VM and 1,504 Node tests,
including 13 resource lifecycle regressions. Analysis and formatting are clean;
`dart fix --dry-run` has no proposed fixes. The independent reader/container/pixel
checks pass all nine successive saves. Focale's source and Git dependency pin are
unchanged in this lot; no new host integration or Adobe acceptance is claimed.

### Vector pattern applications in Focale

The adapter connects typed pattern fill/stroke styles to complete private path
owners. New files retain local tile vectors and affine placement independently
of their host printing image. Reopening projects editable vector tiling paints;
retained tile-color and placement edits replace the selected complete appearance.
Byte-identical declarations are reused, and old referenced declarations/styles
remain source-owned. Project persistence retains this editable scene data.

Current qualification covers rectangular positive repeats matching tile bounds,
literal local paths/groups/clips and canonical placement plus an affine matrix.
Other repeat layouts, isolated tile groups, local image/text/nested-resource
content need broader connections. `ai_pattern_test.dart` covers creation,
copying, reordering, deletion,
shared tiles, successive edits and project persistence. It emits eight
initial/edited/reopened PDF comparisons for `tool/verify_focale_patterns.py`.
Independent native parsing does not render AI patterns and does not establish
acceptance by Illustrator.

Removing an identified owner qualifies retained resource namespaces instead of
rejecting every file with a pattern bank. Retained literal references matching
its identity still reject atomically, as do unknown or executable dependencies.
The original style and independent resource declarations remain byte-preserved.

Local validation passes 1,512 package tests on both VM and Node, including eight
pattern/reference regressions, and 305 Focale AI/PDF/source/prepress/color tests.
The 64 existing independent save checks and eight pattern comparisons pass; the
latter inspect native tile colors/geometry, resource references, placement and
original/reopened host PDF pixels. Package analysis is clean; host analysis has
no errors or warnings (550 existing informational lints). Formatting and scoped
fix checks pass. These results do not certify native rendering or editability
in Illustrator.

### Fixed calligraphic brush applications

New standalone open spines can retain a native calligraphic brush, stroke paint
and same-revision printing/PDF. Import projects the fixed nib and editable spine;
subsequent nib, color, width and similarity-placement edits replace the complete
selected appearance. Byte-identical descriptor payloads are reused. Copying and
removing owners retain the independent descriptor and named-style library.
Project persistence retains the brush inputs instead of serialized outline caches.

AiKit additionally provides complete descriptor lifecycle operations for art,
pattern and bristle brush libraries. Their application/geometry connections in
Focale remain separate work. Current host qualification covers one open spine,
fixed nibs with roundness at least five percent, no pressure profile or dashes,
and similarity placement. Other brush families still require their native
connections. Host outline folds
or exhausted geometry budgets fail atomically with the original source intact.

`ai_brush_test.dart` emits six initial/edited/reopened comparisons for the
independent native/container/PDF verifier. The reader checks literal nib metrics
and descriptor references but does not execute Adobe's brush engine; actual
Illustrator appearance and editability remain unverified.

Local validation passes 1,523 package tests on both VM and Node and 310 Focale
AI/PDF/source/prepress/color tests. Eleven package regressions cover descriptor
references, panel ownership, fixed-nib coherence and byte budgets. Independent
checks pass twelve descriptor-library saves, the 64 previous complete-save
checks, eight pattern comparisons and six calligraphic comparisons. Package
analysis is clean; host analysis has no errors or warnings. Formatting and scoped
fix checks pass. Native brush execution and editing in Illustrator remain
unverified.

### Retained ordinary paths acquiring appearances

Focale routes an existing ordinary single contour through `convertPathArtwork`
when it acquires a qualified vector pattern, fixed calligraphic brush or luminance
mask. The native object retains its XML identity, parent and stacking slot;
source metadata is retained, with explicit name edits applied first. The host
composes the complete printing view and synchronized PDF from the same revision.
The transient lifecycle ledger changes family only after successful conversion,
so reparenting, sibling ordering and multiple conversions share one atomic save.
On reopening, the scene uses its normal `ai-appearance-*` projection identity.
Dynamic shape conversion retains its separate contract. Independent native/PDF
checks do not establish Illustrator acceptance.

Native `UnicodeString` object names now reuse the explicit UTF-16 reader used by
image/group dictionaries. Conversion leaves unchanged names byte-preserved;
explicit renaming retains the saved scalar type and encoding.

The package validation passes 1,528 tests on both VM and Node, including five
conversion regressions for metadata/identity retention, inherited state,
sequential promotion, absent metadata, point-count conventions and atomic
rejections. Package analysis, formatting and fix checks pass. Six independent
original/reopened comparisons cover pattern, calligraphic and masked conversions,
in addition to the prior 78 native/container/PDF checks. Illustrator execution
and editability remain unverified.

### Pattern and calligraphic children in private appearance groups

Focale now authors and projects independent pattern/calligraphic styles on
private group contours, including nested groups and child opacity masks. Native
styles and resource references remain editable; one composed printing owner and
same-revision PDF represent the enclosing group. Initial group creation, first
styling of retained direct children, selected paint/placement revisions and
whole-owner copying, reordering and deletion use the existing source transaction.
Named child closure, visibility and locking edits retain their own masks and
identities without changing parent flags. Shared tile and brush resources are
reused or retained for other applications.

The same tile/nib qualification applies as for standalone contours. Dynamic shape children, other brush families and broader
effects still require their authoring contracts. Acceptance tooling inspects
nested applications, references, identities, masks and original/reopened host
PDF pixels. It does not execute Illustrator's native brush/pattern engines.

The grouped-paint verifier uses exact Poppler comparisons at 144 dpi and exact
Ghostscript comparisons at 72 dpi for both original and reopened scenes. Original
same-revision exports also retain the exact Poppler check at 72 dpi. Poppler's
72 dpi sampling differs for the tiny initial tile when equivalent scaling moves
between a containing transparency form and its pattern matrix; both additional
checks agree without pixel tolerances. Pattern matrices remain relative to the
parent content stream as specified in
[ISO 32000-1, section 8.7.2](https://opensource.adobe.com/dc-acrobat-sdk-docs/standards/pdfstandards/pdf/PDF32000_2008.pdf);
no PDF exporter coordinate change is needed for this lot.

Local validation passes 1,534 package tests on both VM and Node and 321 Focale
AI/PDF/source/prepress/color tests. Six package regressions cover child style
attachment, exact application selection, masks/identities, closure/flags,
clipping rejection and atomic byte-limit failure. Package analysis is clean;
host analysis retains 550 existing informational lints with no errors or warnings.
Formatting and scoped fix checks pass.
The complete independent host verifier passes 92 native/container/PDF comparisons,
including eight grouped-paint views; the 13 existing independent group lifecycle
variants also pass. Illustrator rendering and editability remain unverified.

### Creating, removing and moving private appearance children

Focale now plans private hierarchy changes inside a retained complete owner.
Existing paths/groups keep their native source bindings while new subtrees use
the shared typed writer and resource installation. A fresh group can wrap retained
children without changing their identities. Selected attribute/geometry/style
edits consume the original routes before the final hierarchy transaction, so
simultaneous paint edits, renaming, reordering and reparenting remain coherent.
New child/group masks attach to their freshly authored native identities.

Removing a child removes its owned masks and applications after reference checks;
independent styles, tiles and brush descriptors remain available to other users.
The last child may leave an empty ordinary group with its original identity.
Clipping contours remain attached to their source groups. Dynamic shape children
and other unconnected families retain their explicit guards; they are not silently recreated.

`ai_group_topology_test.dart` covers fresh groups around existing masked children,
new painted/masked paths, selected brush and label edits, successive saved child
removal/reordering, empty groups and atomic rejection of unbound transfers.
`verify_focale_group_topology.py` checks actual nested source order, masks, resource
references and retained identities, then compares original/reopened PDF views
with exact Poppler pixels at 144 dpi and Ghostscript pixels at 72 dpi. The original
same-revision view also retains its exact Poppler comparison at 72 dpi. Native
Illustrator rendering and editability remain unverified.

Local validation passes 1,542 package tests on both VM and Node and 324 Focale
AI/PDF/source/prepress/color tests. Eight package regressions cover retained and
fresh groups, masks/identities, clipping, inherited boundary state, unknown
references, empty owners, byte budgets and atomic invalid-plan rejection. Six
new independent topology views join the previous 92 native/container/PDF
comparisons. Package analysis is clean; host analysis retains 550 existing
informational lints with no errors or warnings. Formatting and scoped fix checks
pass. These checks do not establish Illustrator rendering or editability.


### Transferring private children between complete appearances

The retained host planner binds all editable private children to their original
complete owner and route, then computes their final ancestor placement. Geometry,
paint, label and mask changes consume the original bindings before one atomic
`replaceArtworkTrees` call updates every affected owner. Source and destination
printing expansions come from their final host trees. A fresh wrapper may contain
a transferred child; groups may become empty without losing their identity.

Retained metadata and mask identities travel with the subtree. Shared styles,
tiles and brush descriptors are retained; moved identities are not treated as
removed references. Complete roots, preserved proxies, ordinary outside artwork
and resource-local instances retain their separate lifecycle contracts. Duplicate
host ownership rejects before serialization. Tests exercise bidirectional moves,
changed masks/brushes, transformed fresh wrappers, return moves into an emptied
owner, native references and original/reopened PDF comparisons. When the original
complete owner is removed in the same host edit, its transferred children leave
before the ordinary lifecycle removes the remaining pair. A fresh complete owner
requires its own source-binding contract; retained child IDs cannot silently turn
into newly authored identities there.


Local package validation passes 1,546 tests on both VM and Node with clean
analysis. Four new native regressions cover bidirectional transfers, referenced
identities, atomic invalid plans and restored following state. The independent
host verifier passes all 104 native/container/PDF comparisons, including six
original/reopened transfer views and simultaneous source-owner removal. Final
Focale Git-dependency suite evidence is recorded in ADR 0444. Illustrator
rendering and editability remain unverified.


### Inspecting symbol instance bindings

AiKit now exposes `AiNativeSymbols`: exact source records, raw relative matrices,
byte-preserving symbol names, resource-local ownership and explicit missing,
ambiguous or conditional resolution. Equal pattern or brush names do not bind
symbol instances. Malformed/repeated fields remain inspectable instead of being
replaced by defaults; association work has its own aggregate token budget.

This supplies the reference inventory needed for Focale's symbol table and
instance synchronization. It does not yet connect symbol instances to host objects
or qualify their printing/cache ownership. The pinned external parser contains
an observed instance-field fixture; the inspected pinned artwork corpus contains
no complete symbol-instance specimen. Relative-to-canvas conversion, native
instance writing and actual Illustrator acceptance therefore remain unverified.
The existing resource mutation guards are unchanged.


Local validation passes all 1,554 package tests on both VM and Node. Eight new
regressions cover namespaces, raw byte names, relative matrices, conditional and
ambiguous bindings, opaque/local records, malformed fields, immutable handles and
bounded association work. The pinned independent reader confirms eight references
across four synthetic sources. Analysis, formatting and scoped fix checks pass.
These checks establish inspection behavior only; instance authoring and real
Illustrator exchange remain outstanding.
