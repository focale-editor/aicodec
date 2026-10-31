import 'package:aikit/src/codec/ai_native_data.dart';
import 'package:aikit/src/model/ai_limit_exception.dart';
import 'package:aikit/src/model/ai_native_records.dart';
import 'package:aikit/src/model/ai_native_text.dart';
import 'package:aikit/src/model/ai_program.dart';
import 'package:pscore/pscore.dart';

part '../codec/ai_native_capability_reader.dart';

/// Separates interpreted format data from preserved and rejected structures.
enum AiNativeDataSupport {
  /// A native model exposes the named data; this does not imply editability.
  typed,

  /// Original bytes survive, but their semantics are not qualified here.
  preserved,

  /// The named native structure or dependency has no supported interpretation.
  unsupported,

  /// Structural validation found invalid data, not just an unknown feature.
  malformed,

  /// Inspection could not finish within its budget or dependency contract.
  uninspected,
}

/// Native feature represented by one source-local capability finding.
enum AiNativeFeature {
  /// Complete source program, including retained prolog and trailer data.
  program,

  /// Layer header; its child artwork has independent findings.
  layer,

  /// Path coordinates and paint consumption.
  path,

  /// Hierarchical native record with potentially opaque semantics.
  record,

  /// Document artboard geometry, name and identity.
  artboard,

  /// Body group or compound topology.
  group,

  /// Authoritative live-shape data and appearance associations.
  liveShape,

  /// Gradient instance geometry.
  gradient,

  /// Shared gradient definition, stops and supplied printing ramps.
  gradientResource,

  /// Mesh packet with native nodes and paint data.
  mesh,

  /// Embedded raster geometry and source samples.
  raster,

  /// Linked placement and its optional cached preview.
  placement,

  /// ATE text engine document and its source references.
  text,

  /// An instruction outside the plain-path structural model.
  instruction,
}

/// Qualification of a specific editing operation, separate from readable data.
enum AiNativeEditSupport {
  /// Existing source guards permit this operation; new values remain validated.
  available,

  /// The API exists but requires operation-specific dependency qualification.
  requiresValidation,

  /// Known source dependencies currently reject this operation.
  unsupported,
}

/// Source-local operation whose support can be reported without rendering.
enum AiNativeEditOperation {
  /// Rename the layer without modifying child artwork.
  layerName,

  /// Change native visibility, lock and printing flags.
  layerFlags,

  /// Insert an empty sibling with a qualified header and a fresh source identity.
  layerInsertion,

  /// Reorder ordinary layer subtrees with retained identities and paint state.
  layerReordering,

  /// Move a layer subtree with explicit destination-parent attribute inheritance.
  layerReparenting,

  /// Copy ordinary layer subtrees with fresh identities for every descendant.
  layerDuplication,

  /// Remove ordinary layer subtrees after qualifying their native references.
  layerRemoval,

  /// Replace ordinary path coordinates with qualified geometry.
  pathGeometry,

  /// Insert ordinary geometry using an existing path's paint and object flags.
  pathInsertion,

  /// Copy an independent path immediately after its source object.
  pathDuplication,

  /// Remove independent geometry and its consumed native point count.
  pathRemoval,

  /// Reorder siblings while preserving their own and outgoing paint state.
  pathReordering,

  /// Move ordinary paths with retained state and explicit destination inheritance.
  pathReparenting,

  /// Wrap consecutive independent sibling paths in an ordinary group.
  groupCreation,

  /// Remove ordinary boundaries while retaining child artwork and state.
  groupDissolution,

  /// Copy an ordinary subtree with its inherited paint and object flags.
  groupDuplication,

  /// Delete a subtree while retaining state needed by following objects.
  groupRemoval,

  /// Reorder siblings with explicit incoming and outgoing state preservation.
  groupReordering,

  /// Move ordinary groups with retained state and explicit destination inheritance.
  groupReparenting,

  /// Change live-shape translation and dependent native geometry.
  liveShapeTranslation,

  /// Change live-shape rotation using its native canvas frame.
  liveShapeRotation,

  /// Uniformly scale live-shape parameters and dependent geometry.
  liveShapeScaling,

  /// Copy a complete bound authoring/printing pair with fresh saved identities.
  liveShapeDuplication,

  /// Removes complete authoring/printing pairs with qualified state and references.
  liveShapeRemoval,

  /// Reorders complete sibling pairs with qualified input and outgoing state.
  liveShapeReordering,

  /// Relocates complete pairs across qualified groups and layers.
  liveShapeReparenting,

  /// Attach host-composed geometry to an existing separate printing expansion.
  printingContours,

  /// Attach a complete host-composed group with a retained outgoing paint state.
  printingGroups,

  /// Edit a gradient's stops with host-supplied printing intervals.
  gradientStops,

  /// Edit a radial gradient's native focus.
  gradientFocus,

  /// Change selected mesh vertex colors, inks or opacity.
  meshPaint,

  /// Replace embedded source sample planes.
  rasterPixels,

  /// Change affine image geometry with an explicit frame-angle policy.
  imagePlacement,

  /// Replace a qualified external raster reference and supplied preview.
  relink,

  /// Incorporate host-decoded samples into a native raster.
  embed,

  /// Change text content, requiring new host composition afterward.
  textContent,

  /// Change native text feature runs and resource references.
  textFeatures,

  /// Attach a host-composed layout or explicitly invalidate the selected cache.
  textLayout,
}

/// One immutable editing qualification for the containing source finding.
final class AiNativeEditCapability {
  /// Operation whose source dependencies have been assessed.
  final AiNativeEditOperation operation;

  /// Whether this report establishes availability or requires further validation.
  final AiNativeEditSupport support;

  /// Explains any source restriction or required input-specific validation.
  final String reason;

  /// Retains an assessment without implying that arbitrary new values are valid.
  const AiNativeEditCapability._({required this.operation, required this.support, required this.reason});
}

/// One capability or diagnostic tied to exact native source ownership.
final class AiNativeCapability {
  /// Native snapshot retaining the original bytes and catalog/page owners.
  final AiNativeSource source;

  /// Feature or structural boundary described by this finding.
  final AiNativeFeature feature;

  /// Stable source-relative selector, such as a native byte offset or text index.
  final String selector;

  /// Inclusive byte offset of the smallest known enclosing native source span.
  final int start;

  /// Exclusive end of that span; binary submodels use their enclosing record.
  final int end;

  /// Semantic interpretation, independent of possible edits.
  final AiNativeDataSupport support;

  /// Explains the result, including preserved or unresolved dependencies.
  final String message;

  /// Qualifications for named operations only, never for neighboring artwork.
  final List<AiNativeEditCapability> edits;

  /// Freezes a reader-produced finding with its source ownership.
  AiNativeCapability._({
    required this.source,
    required this.feature,
    required this.selector,
    required this.start,
    required this.end,
    required this.support,
    required this.message,
    List<AiNativeEditCapability> edits = const [],
  }) : edits = List.unmodifiable(edits);

  /// Catalog/page owners affected by editing this source; empty for PostScript.
  List<int?> get owners => source.owners;

  /// Whether at least one named operation has qualified source dependencies.
  bool get editable => support == .typed && edits.any((edit) => edit.support == .available);
}

/// Bounded capability inventory for one independently extracted native program.
///
/// Readable data and editable operations are separate. A layer's editable header
/// never qualifies its children. Unassessed edits explicitly require validation
/// by their native editor. This is neither a renderability claim nor a save gate.
/// Preserve every source, including findings that cannot be interpreted.
final class AiNativeCapabilityReport {
  /// Source snapshot owning every location, selector and affected PDF owner.
  final AiNativeSource source;

  /// Findings in discovery order; overlapping spans describe distinct features.
  final List<AiNativeCapability> findings;

  /// Whether every requested inspection finished without truncation or failure.
  ///
  /// A complete inspection can still find malformed or unsupported data.
  final bool complete;

  /// Inspects native models without modifying the source or generating artwork.
  ///
  /// [maxFindings] bounds diagnostic output; its final slot reports truncation.
  /// [limits] bounds program/record parsing. Unknown dependency parser failures
  /// remain uninspected rather than being declared malformed by guesswork.
  factory AiNativeCapabilityReport.inspect({required AiNativeSource source, AiNativeLimits limits = const AiNativeLimits(), int maxFindings = 100000}) {
    limits.validate();
    if (maxFindings < 1) {
      throw ArgumentError.value(maxFindings, 'maxFindings', 'Must be positive.');
    }
    return _NativeCapabilityReader(source: source, limits: limits, maxFindings: maxFindings).read();
  }

  /// Freezes the report without detaching findings from their immutable source.
  AiNativeCapabilityReport._({required this.source, required List<AiNativeCapability> findings, required this.complete}) : findings = List.unmodifiable(findings);
}
