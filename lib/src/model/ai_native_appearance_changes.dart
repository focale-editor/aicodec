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

  /// Owns replacement data before any source byte offsets change.
  AiNativePaintChange({
    required this.assignment,
    required List<double> values,
    this.dashPhase,
  }) : values = List.unmodifiable(values) {
    if ((assignment.parameter == .dash) != (dashPhase != null) || [...values, ?dashPhase].any((value) => !value.isFinite || value.abs() > 9007199254740991)) {
      throw ArgumentError('Paint changes require portable values and a phase only for dash assignments.');
    }
    if (assignment.parameter != .dash && values.length != assignment.numbers!.length) {
      throw ArgumentError('Paint changes must retain the source command operand layout.');
    }
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
    List<int>? alignmentLabelBytes,
    List<AiNativeAppearancePart>? childOrder,
    List<AiNativeAppearanceChild>? children,
  }) : alignmentLabelBytes = alignmentLabelBytes == null ? null : List.unmodifiable(alignmentLabelBytes),
       childOrder = childOrder == null ? null : List.unmodifiable(childOrder),
       children = children == null ? null : List.unmodifiable(children) {
    if (visible == null && evenOdd == null && strokeAlignment == null && childOrder == null && children == null) {
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
