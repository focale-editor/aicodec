part of 'package:illustratorkit/src/model/ai_native_records.dart';

/// Explicit native values for a new ordinary CC artboard.
///
/// Name bytes use the native UnicodeString representation chosen by the caller.
/// The UUID is a fresh canonical hexadecimal UUID, supplied by the host. Bounds
/// use drawing coordinates; the ruler origin uses native canvas coordinates.
final class AiNativeArtboardDefinition {
  /// Immutable native name bytes, without an inferred character encoding.
  final Uint8List nameBytes;

  /// Immutable ASCII UUID bytes in the artboard identity namespace.
  final Uint8List identifierBytes;

  /// Positive native rectangle, independent of crop and drawing bounds.
  final AiBoundingBox bounds;

  /// Explicit two-coordinate native canvas ruler origin.
  final List<double> rulerOrigin;

  /// Selection flag, independent of the active artboard index.
  final bool selected;

  /// Whether Illustrator should treat the supplied name as its default name.
  final bool defaultName;

  /// Positive pixel aspect ratio, retained as a native Real field.
  final double pixelAspectRatio;

  /// Freezes supplied data before any source-dependent validation or allocation.
  AiNativeArtboardDefinition({
    required List<int> nameBytes,
    required List<int> identifierBytes,
    required this.bounds,
    required List<double> rulerOrigin,
    this.selected = false,
    this.defaultName = false,
    this.pixelAspectRatio = 1,
  }) : nameBytes = _artboardDefinitionBytes(nameBytes),
       identifierBytes = _artboardDefinitionBytes(identifierBytes),
       rulerOrigin = List.unmodifiable(rulerOrigin) {
    _nativeArtboardCoordinates([bounds.left, bounds.bottom, bounds.right, bounds.top, ...rulerOrigin, pixelAspectRatio]);
    if (bounds.left == bounds.right || bounds.bottom == bounds.top || rulerOrigin.length != 2 || pixelAspectRatio <= 0) {
      throw ArgumentError('Artboard definitions require positive dimensions, a ruler point and a positive pixel aspect ratio.');
    }
    if (!RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$').hasMatch(latin1.decode(this.identifierBytes))) {
      throw ArgumentError('New artboards require a canonical hexadecimal UUID.');
    }
  }
}

/// Rejects invalid bytes before Uint8List conversion could silently truncate them.
Uint8List _artboardDefinitionBytes(List<int> bytes) {
  if (bytes.any((byte) => byte < 0 || byte > 255)) {
    throw ArgumentError('Artboard names and identifiers require byte values.');
  }
  return Uint8List.fromList(bytes).asUnmodifiableView();
}
