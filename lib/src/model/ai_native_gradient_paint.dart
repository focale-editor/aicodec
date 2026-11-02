part of 'package:aikit/src/model/ai_native_records.dart';

/// Explicit artwork-relative CC gradient placement inside a fill or stroke style.
///
/// The resource supplies editable stops and host-composed ramps. Origin, length,
/// matrix and aspect ratio retain native units; no bounds or printing geometry
/// are inferred. The host supplies the complete appearance expansion and PDF.
final class AiNativeGradientPaint {
  /// Exact byte name of the existing gradient resource.
  final Uint8List nameBytes;

  /// Two coordinates in the native artwork-relative basis.
  final List<double> origin;

  /// Gradient-vector angle in degrees.
  final double angle;

  /// Positive artwork-relative axis length.
  final double length;

  /// Explicit affine coefficients in native operand order.
  final List<double> matrix;

  /// Positive CC aspect-ratio operand, including one for a circular radial fill.
  final double aspectRatio;

  /// Freezes one relative placement without converting coordinates or colors.
  AiNativeGradientPaint({
    required List<int> nameBytes,
    required List<double> origin,
    required this.angle,
    required this.length,
    required List<double> matrix,
    required this.aspectRatio,
  }) : nameBytes = Uint8List.fromList(nameBytes).asUnmodifiableView(),
       origin = List.unmodifiable(origin),
       matrix = List.unmodifiable(matrix) {
    if (nameBytes.isEmpty ||
        nameBytes.any((byte) => byte < 0 || byte > 255) ||
        origin.length != 2 ||
        matrix.length != 6 ||
        ![...origin, angle, length, ...matrix, aspectRatio].every((value) => value.isFinite && value.abs() <= 9007199254740991) ||
        length <= 0 ||
        aspectRatio <= 0 ||
        matrix[0] * matrix[3] - matrix[1] * matrix[2] == 0) {
      throw ArgumentError('Gradient paints require a byte name and finite nonsingular artwork-relative geometry.');
    }
  }

  /// Writes the observed CC style layout with an explicit fill/stroke selector.
  Uint8List _bytes({required bool stroke, required int limit}) {
    final _GradientResourceWriter writer = _GradientResourceWriter(limit: limit);
    writer.add(stroke ? '1 Bb 2 ' : 'Bb 2 ');
    writer.string(nameBytes);
    writer.add(' ${origin.join(' ')} $angle $length ${matrix.join(' ')} $aspectRatio Bg ${stroke ? 1 : 0} BB');
    return writer.output.takeBytes();
  }
}
