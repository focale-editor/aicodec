part of 'package:aicodec/src/model/ai_native_records.dart';

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
  /// The host includes strokes, effects and inherited transforms. AiCodec retains
  /// or expands document DSC bounds; it does not render to derive this extent.
  final AiBoundingBox bounds;

  /// Captures the complete selected expansion before source offsets can change.
  AiNativePrintingReplacement({required this.shape, required List<AiNativePrintingContours> paths, required this.bounds}) : paths = List.unmodifiable(paths) {
    if ([bounds.left, bounds.bottom, bounds.right, bounds.top].any((coordinate) => coordinate.abs() > 9007199254740991)) {
      throw ArgumentError('Printing bounds exceed portable native coordinates.');
    }
  }
}

/// A complete printing group composed by the host for one bound CC live shape.
///
/// Supply one `u`/`U` group with ordinary or compound paths, process paints and
/// qualified references to existing gradient definitions. Authoring records and
/// resources stay in the owning document. The outgoing paint state must match
/// the source group so unselected following objects retain their appearance.
final class AiNativePrintingGroupReplacement {
  /// Source-backed shape owning the derived group to replace.
  final AiLiveShape shape;

  /// Owned group bytes, without a document header, setup or private metadata.
  final Uint8List _bytes;

  /// Host-computed complete ink bounds in y-up document drawing coordinates.
  final AiBoundingBox bounds;

  /// Captures a host-composed group without interpreting its rendered appearance.
  AiNativePrintingGroupReplacement({required this.shape, required List<int> bytes, required this.bounds}) : _bytes = Uint8List.fromList(bytes) {
    if (bytes.any((byte) => byte < 0 || byte > 255) || [bounds.left, bounds.bottom, bounds.right, bounds.top].any((coordinate) => coordinate.abs() > 9007199254740991)) {
      throw ArgumentError('Printing groups require byte data and portable ink bounds.');
    }
  }

  /// Immutable supplied bytes; validation uses the owning program's limits.
  Uint8List get bytes => _bytes.asUnmodifiableView();
}
