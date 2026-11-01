part of 'package:aikit/src/model/ai_native_records.dart';

/// Native path-mask behavior, independent of the path's retained paint operator.
enum AiNativePathMask {
  /// The path does not intersect the current clipping region.
  none,

  /// Intersects the clip using `H W`, without explicitly closing the path.
  open,

  /// Closes the path and intersects the clip using `h W`.
  closed,
}

/// Qualified path ownership, including compound contours and masks.
///
/// Appearance owners expose private contours for inspection and host composition;
/// their presence here does not authorize independent ordinary path edits.
final class AiNativePathTopology {
  /// Exact path handle in the inspected drawing snapshot.
  final AiNativePath path;

  /// Enclosing native groups, ordered from outermost to innermost.
  final List<AiNativeGroup> groups;

  /// Optional owned CC point-count instruction preceding the geometry.
  final AiNativeInstruction? pointCount;

  /// Saved mask controls immediately between geometry and paint.
  final List<AiNativeInstruction> maskControls;

  /// Retains immutable ownership without promoting printable CC expansions.
  AiNativePathTopology._({required this.path, required List<AiNativeGroup> groups, required this.pointCount, required List<AiNativeInstruction> maskControls})
    : groups = List.unmodifiable(groups),
      maskControls = List.unmodifiable(maskControls);

  /// Current mask behavior, separate from whether painting closes the contour.
  AiNativePathMask get mask => maskControls.isEmpty
      ? .none
      : maskControls.first.operator == 'h'
      ? .closed
      : .open;

  /// Innermost compound owner, when the path is one of its contours.
  AiNativeGroup? get compound => groups.where((group) => group.compound).lastOrNull;

  /// Matching graphics-state owner that bounds this path's clipping changes.
  ///
  /// Clipping leaves inside a compound do not save/restore graphics state; the
  /// mask takes effect when the outer compound is consumed.
  AiNativeGroup? get clippingGroup => groups.takeWhile((group) => !group.compound).where((group) => group.opening.operator == 'q').lastOrNull;
}

/// An immutable geometry or mask change to one authoritative ordinary path.
final class AiNativePathEdit {
  /// Owned path to change in the original drawing snapshot.
  final AiNativePath path;

  /// Replacement geometry; null retains every existing geometry instruction.
  final List<AiPathSegment>? segments;

  /// Replacement mask behavior; null retains the current clipping relationship.
  final AiNativePathMask? mask;

  /// Freezes one complete request without changing paint or object identities.
  AiNativePathEdit({required this.path, List<AiPathSegment>? segments, this.mask}) : segments = segments == null ? null : List.unmodifiable(segments) {
    if (segments == null && mask == null) {
      throw ArgumentError('A native path edit requires geometry or mask behavior.');
    }
    if (segments != null &&
        (segments.isEmpty ||
            segments.first.operator != 'm' ||
            segments.skip(1).any((segment) => segment.operator == 'm') ||
            segments.any((segment) => segment.coordinates.any((value) => value.abs() > 9007199254740991)))) {
      throw ArgumentError('Native path edits require one portable contour with an initial moveto.');
    }
  }
}
