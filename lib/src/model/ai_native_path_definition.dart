part of 'package:aikit/src/model/ai_native_records.dart';

/// Explicit ordinary geometry and process paints for source-native path creation.
///
/// [artwork] supplies immutable geometry, fill/stroke, winding, lock and line
/// attributes. It is a data value here; creation does not invoke the standalone
/// AI7 document writer. Advanced appearances, guides and private CC shape
/// parameters require their separate native contracts.
final class AiNativePathDefinition {
  /// Geometry and independent process paints to serialize without conversion.
  final AiArtworkPath artwork;

  /// Complete host-computed ink bounds in native y-up document coordinates.
  final AiBoundingBox bounds;

  /// Whether to write the CC `As` point-count convention before geometry.
  final bool counted;

  /// Whether the new object is hidden independently of its ancestors.
  final bool hidden;

  /// Object opacity using the qualified `0 opacity 0 0 0 Xy` layout.
  final double opacity;

  /// Whether the supplied process fill overprints underlying artwork.
  final bool fillOverprint;

  /// Whether the supplied process stroke overprints underlying artwork.
  final bool strokeOverprint;

  /// Optional native display name, independent of XML identity and encoding.
  final List<int>? nameBytes;

  /// Optional fresh portable XML identity for the new path.
  final List<int>? identifierBytes;

  /// Freezes metadata and checks portable values without rendering any ink.
  AiNativePathDefinition({
    required this.artwork,
    required this.bounds,
    this.counted = true,
    this.hidden = false,
    this.opacity = 1,
    this.fillOverprint = false,
    this.strokeOverprint = false,
    List<int>? nameBytes,
    List<int>? identifierBytes,
  }) : nameBytes = nameBytes == null ? null : List.unmodifiable(nameBytes),
       identifierBytes = identifierBytes == null ? null : List.unmodifiable(identifierBytes) {
    if (!opacity.isFinite || opacity < 0 || opacity > 1) {
      throw ArgumentError('Native path opacity must be finite and between zero and one.');
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
