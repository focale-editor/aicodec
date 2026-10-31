part of 'package:aikit/src/model/ai_native_records.dart';

/// Host-composed contours replacing one owned path in a printing expansion.
///
/// This is derived geometry, not a replacement for native shape parameters.
/// Each contour inherits the source path's paint and closure operation. Existing
/// compound groups, paints, gradient references and authoring records stay intact.
/// Wrapped gradient/paint paths currently require one supplied contour.
/// Counted CC paths receive updated `As` headers and explicit closing endpoints.
final class AiNativePrintingContours {
  /// Printing path from the same snapshot as the selected live shape.
  final AiNativePath path;

  /// Ordered contours in the source path's native drawing coordinate system.
  final List<List<AiPathSegment>> contours;

  /// Owns geometry supplied by the host without stroking, tessellating or shaping.
  AiNativePrintingContours({required this.path, required List<List<AiPathSegment>> contours}) : contours = List.unmodifiable(contours.map(List<AiPathSegment>.unmodifiable)) {
    if (contours.isEmpty || contours.any((contour) => contour.isEmpty || contour.first.operator != 'm' || contour.skip(1).any((segment) => segment.operator == 'm'))) {
      throw ArgumentError('Printing contours require nonempty paths with one initial moveto.');
    }
  }
}

/// A complete host-supplied geometry update for one separate CC printing group.
final class AiNativePrintingReplacement {
  /// Live shape whose private authoring geometry remains authoritative.
  final AiLiveShape shape;

  /// One replacement for every path belonging to this shape's printing group.
  final List<AiNativePrintingContours> paths;

  /// Host-computed ink extent in y-up document drawing coordinates.
  ///
  /// The host includes strokes, effects and inherited transforms. AiKit retains
  /// or expands document DSC bounds; it does not render to derive this extent.
  final AiBoundingBox bounds;

  /// Captures the complete selected expansion before source offsets can change.
  AiNativePrintingReplacement({required this.shape, required List<AiNativePrintingContours> paths, required this.bounds}) : paths = List.unmodifiable(paths) {
    if ([bounds.left, bounds.bottom, bounds.right, bounds.top].any((coordinate) => coordinate.abs() > 9007199254740991)) {
      throw ArgumentError('Printing bounds exceed portable native coordinates.');
    }
  }
}
