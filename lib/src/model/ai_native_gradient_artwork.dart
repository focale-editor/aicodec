part of 'package:aikit/src/model/ai_native_records.dart';

/// Explicit absolute gradient geometry for a newly authored direct fill.
///
/// The named resource supplies native stops and host-composed ramps. Coordinates
/// use the legacy absolute `Bg` layout, also readable inside a CC document.
/// No colour conversion, clipping expansion or interpolation is inferred.
final class AiNativeGradientFillDefinition {
  /// Exact resource name bytes, resolved in the edited source snapshot.
  final List<int> nameBytes;

  /// Gradient origin in native drawing coordinates.
  final List<double> origin;

  /// Axis angle in degrees.
  final double angle;

  /// Positive native axis length or radial radius.
  final double length;

  /// Explicit native affine coefficients accompanying the axis.
  final List<double> matrix;

  /// Optional native radial highlight operands, without reinterpreting units.
  final List<double>? highlight;

  /// Freezes finite native geometry without supplying a rendering default.
  AiNativeGradientFillDefinition({
    required List<int> nameBytes,
    required List<double> origin,
    required this.angle,
    required this.length,
    required List<double> matrix,
    List<double>? highlight,
  }) : nameBytes = List.unmodifiable(nameBytes),
       origin = List.unmodifiable(origin),
       matrix = List.unmodifiable(matrix),
       highlight = highlight == null ? null : List.unmodifiable(highlight) {
    if (nameBytes.isEmpty ||
        nameBytes.any((value) => value < 0 || value > 255) ||
        origin.length != 2 ||
        matrix.length != 6 ||
        highlight != null && highlight.length != 4 ||
        highlight != null && (highlight[3] < 0 || highlight[3] > 1) ||
        length <= 0 ||
        [angle, length, ...origin, ...matrix, ...?highlight].any((value) => !value.isFinite || value.abs() > 9007199254740991) ||
        matrix[0] * matrix[3] - matrix[1] * matrix[2] == 0) {
      throw ArgumentError('Gradient fills require a named resource, positive axis and finite nonsingular native geometry.');
    }
  }
}

/// A complete direct gradient path, including its count and attached metadata.
///
/// This handle qualifies source ownership, not visual equivalence of its stops,
/// cached ramps and PDF. Unknown or interleaved owners receive no such handle.
final class AiNativeGradientArtwork extends AiNativeItem {
  /// Native application and its exact resource reference.
  final AiNativeGradient gradient;

  /// Single filled contour owned by the application.
  final AiNativePath path;

  /// Optional point count consumed by this contour.
  final AiNativeInstruction? pointCount;

  /// Exclusively attached ordinary name/identity metadata.
  final AiNativeContainer? dictionary;

  /// Creates a source-backed association after validating all intervening data.
  AiNativeGradientArtwork._({required super.start, required super.end, required this.gradient, required this.path, required this.pointCount, required this.dictionary});

  /// Exact portable identity bytes, if supplied by the source.
  Uint8List? get identifierBytes => dictionary?['AI10_ArtUID']?.container?.entries.single.stringBytes;

  /// Literal display-name bytes, retaining their original encoding.
  Uint8List? get nameBytes => (dictionary?['AIArtName'] ?? dictionary?['Object name'])?.stringBytes;
}
