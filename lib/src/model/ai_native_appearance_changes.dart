part of 'package:aikit/src/model/ai_native_records.dart';

/// Replacement operands for one exact source paint assignment.
///
/// Numeric commands retain their operator and arity, including both authored
/// process-color alternatives. For a dash assignment, values are the new lengths
/// and dashPhase is required. No effective value or color conversion is inferred.
final class AiNativePaintChange {
  /// Exact assignment from the selected appearance's current paint snapshot.
  final AiNativePaintAssignment assignment;

  /// Ordered numeric operands, or dash lengths for an array-valued assignment.
  final List<double> values;

  /// Required dash phase, absent for non-dash assignments.
  final double? dashPhase;

  /// Existing target resource for a precise gradient application change.
  final AiNativeGradientDefinition? gradientDefinition;

  /// Replacement named paint retaining its source ink name and native layout.
  final AiNativeNamedColor? namedColor;

  /// Owns replacement data before any source byte offsets change.
  AiNativePaintChange({
    required this.assignment,
    required List<double> values,
    this.dashPhase,
  }) : values = List.unmodifiable(values),
       gradientDefinition = null,
       namedColor = null {
    if (assignment.namedColor != null) {
      throw ArgumentError('Use the namedColor constructor for named ink assignments.');
    }
    if (assignment.parameter == .gradient) {
      throw ArgumentError('Use the gradient constructor for a gradient application.');
    }
    if ((assignment.parameter == .dash) != (dashPhase != null) || [...values, ?dashPhase].any((value) => !value.isFinite || value.abs() > 9007199254740991)) {
      throw ArgumentError('Paint changes require portable values and a phase only for dash assignments.');
    }
    if (assignment.parameter != .dash && values.length != assignment.numbers!.length) {
      throw ArgumentError('Paint changes must retain the source command operand layout.');
    }
  }

  /// Rebinds exactly one appearance gradient while retaining its placement.
  ///
  /// Use updateSelected to isolate explicitly selected applications of a shared
  /// style, or updateShared with full use coverage. The target must already exist
  /// in the same snapshot. Printing groups are supplied through that transaction.
  AiNativePaintChange.gradient({required this.assignment, required AiNativeGradientDefinition definition}) : values = const [], dashPhase = null, gradientDefinition = definition, namedColor = null {
    if (assignment.gradient == null) {
      throw ArgumentError('A gradient change requires an exact gradient assignment.');
    }
  }

  /// Replaces named ink alternatives/tint without renaming a document separation.
  ///
  /// Shared-style use coverage and host printing groups follow the same atomic
  /// transaction as process paints. This does not redefine unrelated same-name
  /// inks or interpret a native tint as opacity.
  AiNativePaintChange.namedColor({required this.assignment, required AiNativeNamedColor value}) : values = const [], dashPhase = null, gradientDefinition = null, namedColor = value {
    final AiNativeNamedColor? source = assignment.namedColor;
    if (source == null || source.kind != value.kind || !_sameNativeBytes(source.nameBytes, value.nameBytes)) {
      throw ArgumentError('Named paint changes retain the source representation and ink name.');
    }
  }

  /// Replaces one exact transparency assignment using explicit host settings.
  factory AiNativePaintChange.transparency({required AiNativePaintAssignment assignment, required AiNativeTransparency value}) {
    if (assignment.parameter != .transparency) {
      throw ArgumentError('A transparency change requires an owned Xy assignment.');
    }
    return AiNativePaintChange(assignment: assignment, values: value.operands);
  }
}

/// Changes explicit settings or direct child order of one exact appearance part.
final class AiNativeAppearancePartChange {
  /// Current source part, distinct from any other fill or stroke in the tree.
  final AiNativeAppearancePart part;

  /// Replacement for the part's explicitly saved local visibility.
  final bool? visible;

  /// Replacement for an explicitly saved fill winding flag.
  final bool? evenOdd;

  /// Inside/outside replacement for an explicitly saved native offset stroke.
  final AiNativeStrokeAlignment? strokeAlignment;

  /// Replacement for an explicitly saved version-one dash-adjustment flag.
  ///
  /// Dash expansion remains the host's responsibility. Absent fields are not
  /// synthesized by scalar editing; new stroke definitions may supply the flag.
  final bool? adjustDashes;

  /// Host-supplied label bytes when the offset stroke has a saved DisplayString.
  ///
  /// Preserve the original string encoding; the kit does not translate labels.
  final List<int>? alignmentLabelBytes;

  /// Complete permutation of a stack or chain's existing direct child handles.
  ///
  /// Each child keeps its entire subtree. This does not insert, remove or reparent
  /// parts. Paint and setting edits in moved descendants use the original handles.
  final List<AiNativeAppearancePart>? childOrder;

  /// Complete replacement children for a stack or chain.
  ///
  /// Omitted children are removed; retained handles may move between changed
  /// parents but must occur once in the resulting tree. Copies retain their
  /// original snapshot, independently of edits to the retained source part.
  /// This is mutually exclusive with [childOrder].
  final List<AiNativeAppearanceChild>? children;

  /// Captures an explicit change; missing fields are not filled with defaults.
  AiNativeAppearancePartChange({
    required this.part,
    this.visible,
    this.evenOdd,
    this.strokeAlignment,
    this.adjustDashes,
    List<int>? alignmentLabelBytes,
    List<AiNativeAppearancePart>? childOrder,
    List<AiNativeAppearanceChild>? children,
  }) : alignmentLabelBytes = alignmentLabelBytes == null ? null : List.unmodifiable(alignmentLabelBytes),
       childOrder = childOrder == null ? null : List.unmodifiable(childOrder),
       children = children == null ? null : List.unmodifiable(children) {
    if (visible == null && evenOdd == null && strokeAlignment == null && adjustDashes == null && childOrder == null && children == null) {
      throw ArgumentError('An appearance part change requires a supplied setting.');
    }
    if (children != null && childOrder != null) {
      throw ArgumentError('Appearance children and childOrder cannot be combined on one parent.');
    }
    if (alignmentLabelBytes != null && (strokeAlignment == null || alignmentLabelBytes.any((byte) => byte < 0 || byte > 255))) {
      throw ArgumentError('An alignment label requires an alignment change and native byte data.');
    }
  }
}

/// Complete paint and geometry for one retained private group child.
final class AiNativeAppearancePathChange {
  /// Current authoritative contour inside a complete appearance group.
  final AiNativePath path;

  /// Explicit geometry, closure, process colors and stroke/locking attributes.
  final AiArtworkPath artwork;

  /// Literal named fill, exclusive with the process fill in [artwork].
  final AiNativeNamedColor? namedFill;

  /// Literal named stroke, exclusive with the process stroke in [artwork].
  final AiNativeNamedColor? namedStroke;

  /// Explicit opacity when no complete transparency tuple is supplied.
  final double opacity;

  /// Complete blending settings, with opacity kept at its default when supplied.
  final AiNativeTransparency? transparency;

  /// Visibility independent of ancestor visibility.
  final bool hidden;

  /// Whether the process fill overprints underlying artwork.
  final bool fillOverprint;

  /// Whether the process stroke overprints underlying artwork.
  final bool strokeOverprint;

  /// Retains immutable values without replacing names, identities or source frames.
  AiNativeAppearancePathChange({
    required this.path,
    required this.artwork,
    this.namedFill,
    this.namedStroke,
    this.opacity = 1,
    this.transparency,
    this.hidden = false,
    this.fillOverprint = false,
    this.strokeOverprint = false,
  }) {
    if (namedFill != null && artwork.fill != null || namedStroke != null && artwork.stroke != null) {
      throw ArgumentError('Private paint channels cannot contain both process and named colors.');
    }
    if (!opacity.isFinite || opacity < 0 || opacity > 1 || transparency != null && opacity != 1) {
      throw ArgumentError('Private path paint requires valid opacity or an explicit transparency tuple.');
    }
  }
}

/// Complete geometry and flags for a standalone styled private contour.
///
/// Named paints, metadata, identities and opacity-mask artwork remain owned by
/// the source. The host supplies replacement printing and the matching PDF.
final class AiNativeAppearanceContourChange {
  /// Current standalone authoring path obtained through its complete owner.
  final AiNativePath path;

  /// Complete new anchors, without an extra endpoint required only by counting.
  final List<AiPathSegment> segments;

  /// Explicit contour closure, serialized as the unpainted `n` or `N` role.
  final bool closed;

  /// Visibility of the native path and its complete printing owner.
  final bool hidden;

  /// Locking of the native path and its complete printing owner.
  final bool locked;

  /// Freezes one portable contour without changing its named paints or identity.
  AiNativeAppearanceContourChange({required this.path, required List<AiPathSegment> segments, required this.closed, required this.hidden, required this.locked})
    : segments = List.unmodifiable(segments) {
    if (segments.isEmpty ||
        segments.first.operator != 'm' ||
        segments.skip(1).any((segment) => segment.operator == 'm') ||
        segments.any((segment) => segment.coordinates.any((value) => value.abs() > 9007199254740991))) {
      throw ArgumentError('Standalone appearance contours require one portable path with an initial moveto.');
    }
  }
}
