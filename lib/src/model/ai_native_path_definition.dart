part of 'package:aikit/src/model/ai_native_records.dart';

/// Explicit ordinary geometry and literal paints for source-native path creation.
///
/// [artwork] supplies immutable geometry, fill/stroke, winding, lock and line
/// attributes. Advanced appearances, guides and private CC shape
/// parameters require their separate native contracts.
final class AiNativePathDefinition {
  /// Geometry and independent process paints to serialize without conversion.
  final AiArtworkPath artwork;

  /// Named fill alternative, mutually exclusive with the artwork's process fill.
  final AiNativeNamedColor? namedFill;

  /// Named stroke alternative, mutually exclusive with the process stroke.
  final AiNativeNamedColor? namedStroke;

  /// Whether either literal fill representation paints the contour.
  bool get filled => artwork.fill != null || namedFill != null;

  /// Whether either literal stroke representation paints the contour.
  bool get stroked => artwork.stroke != null || namedStroke != null;

  /// Complete host-computed ink bounds in native y-up document coordinates.
  final AiBoundingBox bounds;

  /// Whether to write the CC `As` point-count convention before geometry.
  final bool counted;

  /// Whether the new object is hidden independently of its ancestors.
  final bool hidden;

  /// Object opacity using the qualified `0 opacity 0 0 0 Xy` layout.
  final double opacity;

  /// Complete object blending, replacing the normal-opacity shorthand when set.
  ///
  /// Keep [opacity] at its default when supplying this explicit native tuple.
  final AiNativeTransparency? transparency;

  /// Whether the supplied fill overprints underlying artwork.
  final bool fillOverprint;

  /// Whether the supplied stroke overprints underlying artwork.
  final bool strokeOverprint;

  /// Optional native display name, independent of XML identity and encoding.
  final List<int>? nameBytes;

  /// Optional fresh portable XML identity for the new path.
  final List<int>? identifierBytes;

  /// Freezes metadata and checks portable values without rendering any ink.
  AiNativePathDefinition({
    required this.artwork,
    required this.bounds,
    this.namedFill,
    this.namedStroke,
    this.counted = true,
    this.hidden = false,
    this.opacity = 1,
    this.transparency,
    this.fillOverprint = false,
    this.strokeOverprint = false,
    List<int>? nameBytes,
    List<int>? identifierBytes,
  }) : nameBytes = nameBytes == null ? null : List.unmodifiable(nameBytes),
       identifierBytes = identifierBytes == null ? null : List.unmodifiable(identifierBytes) {
    if (namedFill != null && artwork.fill != null || namedStroke != null && artwork.stroke != null) {
      throw ArgumentError('A native paint channel cannot combine process and named colors.');
    }
    if (!opacity.isFinite || opacity < 0 || opacity > 1 || transparency != null && opacity != 1) {
      throw ArgumentError('Native paths require valid opacity or explicit transparency, without conflicting inputs.');
    }
    if ([
      bounds.left,
      bounds.bottom,
      bounds.right,
      bounds.top,
      artwork.strokeWidth,
      artwork.miterLimit,
      artwork.dashPhase,
      ...artwork.dash,
      for (final AiPathSegment segment in artwork.segments) ...segment.coordinates,
    ].any((value) => value.abs() > 9007199254740991)) {
      throw ArgumentError('Created native paths require portable coordinates, bounds and stroke values.');
    }
    if ([...?nameBytes, ...?identifierBytes].any((byte) => byte < 0 || byte > 255)) {
      throw ArgumentError('Native path names and identifiers must contain bytes.');
    }
  }
}
