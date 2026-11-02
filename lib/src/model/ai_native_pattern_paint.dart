part of 'package:aikit/src/model/ai_native_records.dart';

/// Literal pattern placement retaining native parameters and the saved matrix.
///
/// The nine placement operands are `px py sx sy angle rf r k ka`. Their values
/// remain distinct from the six matrix entries; this class does not compose or
/// render them. Hosts may use the canonical placement with an explicit matrix.
final class AiNativePatternPaint {
  /// Exact byte name of the referenced pattern declaration.
  final Uint8List nameBytes;

  /// Saved placement operands, including the Boolean reflection selector.
  final List<double> placement;

  /// Native affine matrix in `a b c d tx ty` order.
  final List<double> matrix;

  /// Freezes a literal placement without resolving the document namespace.
  AiNativePatternPaint({required List<int> nameBytes, List<double> placement = const [0, 0, 1, 1, 0, 0, 0, 0, 0], required List<double> matrix})
    : nameBytes = Uint8List.fromList(nameBytes).asUnmodifiableView(),
      placement = List.unmodifiable(placement),
      matrix = List.unmodifiable(matrix) {
    if (nameBytes.isEmpty ||
        nameBytes.any((byte) => byte < 0 || byte > 255) ||
        placement.length != 9 ||
        matrix.length != 6 ||
        [...placement, ...matrix].any((value) => !value.isFinite || value.abs() > 9007199254740991) ||
        !const {0, 1}.contains(placement[5])) {
      throw ArgumentError('Pattern paints require a byte name, nine portable placement operands and six matrix entries.');
    }
  }

  /// Reads a literal fill/stroke pattern, or returns null for another paint.
  static AiNativePatternPaint? decode({required AiNativeInstruction instruction}) {
    if (!const {'p', 'P'}.contains(instruction.operator)) {
      return null;
    }
    final List<AiToken> operands = instruction.operands;
    if (operands.length != 18 ||
        !_artboardPaletteName(operands.first) ||
        operands[10].kind != .arrayStart ||
        operands.last.kind != .arrayEnd ||
        [...operands.sublist(1, 10), ...operands.sublist(11, 17)].any((token) => token.number == null)) {
      throw const FormatException('Pattern paints require a literal name, placement and six-value matrix.');
    }
    try {
      return AiNativePatternPaint(
        nameBytes: aiStringBytes(operands.first),
        placement: operands.sublist(1, 10).map((token) => token.number!.toDouble()).toList(),
        matrix: operands.sublist(11, 17).map((token) => token.number!.toDouble()).toList(),
      );
    } on ArgumentError {
      throw const FormatException('Pattern paints contain invalid portable placement values.');
    }
  }

  /// Serializes bounded literals for a selected fill or stroke channel.
  Uint8List _bytes({required bool stroke, required int limit}) {
    final List<int> name = _nativeLiteralString(nameBytes, limit);
    final List<int> tail = latin1.encode(' ${placement.join(' ')} [${matrix.join(' ')}] ${stroke ? 'P' : 'p'}');
    if (name.length + tail.length > limit) {
      throw const AiLimitException(message: 'Pattern paint exceeds the native output limit.');
    }
    return Uint8List.fromList([...name, ...tail]);
  }
}
