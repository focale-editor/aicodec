part of 'package:aikit/src/model/ai_native_records.dart';

/// Explicit editable content in a newly authored private appearance tree.
sealed class AiNativeAppearanceElementDefinition {
  /// Prevents mutable external implementations of the authoring grammar.
  const AiNativeAppearanceElementDefinition();
}

/// An independently painted editable contour inside an appearance group.
final class AiNativeAppearancePathDefinition extends AiNativeAppearanceElementDefinition {
  /// Complete process paint, geometry, flags and fresh metadata supplied by host.
  final AiNativePathDefinition definition;

  /// Retains the immutable path definition without composing its printing view.
  const AiNativeAppearancePathDefinition({required this.definition});
}

/// An unpainted prefix contour defining one private group's clipping region.
final class AiNativeAppearanceClipDefinition {
  /// Complete native geometry, with exactly one initial moveto.
  final List<AiPathSegment> segments;

  /// Explicit clipping closure, independent of the unpainted `N` operator.
  final AiNativePathMask mask;

  /// Whether the clip uses even-odd winding instead of nonzero winding.
  final bool evenOdd;

  /// Whether to emit the native point-count convention before the contour.
  final bool counted;

  /// Optional source label for the editable mask contour.
  final List<int>? nameBytes;

  /// Optional fresh native identity, independent of the group's identity.
  final List<int>? identifierBytes;

  /// Owns portable contour data without painting or composing the clipped result.
  AiNativeAppearanceClipDefinition({
    required List<AiPathSegment> segments,
    this.mask = .closed,
    this.evenOdd = false,
    this.counted = true,
    List<int>? nameBytes,
    List<int>? identifierBytes,
  }) : segments = List.unmodifiable(segments),
       nameBytes = nameBytes == null ? null : List.unmodifiable(nameBytes),
       identifierBytes = identifierBytes == null ? null : List.unmodifiable(identifierBytes) {
    if (mask == .none ||
        segments.isEmpty ||
        segments.first.operator != 'm' ||
        segments.skip(1).any((segment) => segment.operator == 'm') ||
        segments.any((segment) => segment.coordinates.any((value) => value.abs() > 9007199254740991)) ||
        [...?nameBytes, ...?identifierBytes].any((byte) => byte < 0 || byte > 255)) {
      throw ArgumentError('Appearance clips require one portable contour, an explicit clipping role and byte metadata.');
    }
  }
}

/// An ordinary or clipped editable group with optional existing named appearance.
final class AiNativeAppearanceGroupDefinition extends AiNativeAppearanceElementDefinition {
  /// Ordered native children, retained separately from the printing expansion.
  final List<AiNativeAppearanceElementDefinition> children;

  /// Optional unpainted prefix mask, separate from the ordered content children.
  final AiNativeAppearanceClipDefinition? clip;

  /// Existing style name; required for the root of a complete appearance pair.
  final List<int>? styleNameBytes;

  /// Optional native String label, independent of the style's resource name.
  final List<int>? nameBytes;

  /// Optional fresh portable object identity.
  final List<int>? identifierBytes;

  /// Explicit object visibility, independent of child visibility.
  final bool hidden;

  /// Explicit object locking, independent of child flags.
  final bool locked;

  /// Freezes children and source strings before any document offsets change.
  AiNativeAppearanceGroupDefinition({
    required List<AiNativeAppearanceElementDefinition> children,
    this.clip,
    List<int>? styleNameBytes,
    List<int>? nameBytes,
    List<int>? identifierBytes,
    this.hidden = false,
    this.locked = false,
  }) : children = List.unmodifiable(children),
       styleNameBytes = styleNameBytes == null ? null : List.unmodifiable(styleNameBytes),
       nameBytes = nameBytes == null ? null : List.unmodifiable(nameBytes),
       identifierBytes = identifierBytes == null ? null : List.unmodifiable(identifierBytes) {
    if (children.isEmpty || [styleNameBytes, nameBytes, identifierBytes].whereType<List<int>>().any((bytes) => bytes.any((byte) => byte < 0 || byte > 255)) || styleNameBytes?.isEmpty == true) {
      throw ArgumentError('Appearance trees require nonempty groups and literal byte names.');
    }
  }
}
