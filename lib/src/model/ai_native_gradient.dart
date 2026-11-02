part of 'package:aikit/src/model/ai_native_records.dart';

/// Native gradient geometry, preserving the legacy and CC operand layouts.
final class AiNativeGradientGeometry {
  /// Exact Bg instruction, including its optional flag and aspect ratio.
  final AiNativeInstruction instruction;

  /// Position of the gradient-name string in the original operand list.
  final int nameIndex;

  /// Validates the two documented operand layouts without converting units.
  factory AiNativeGradientGeometry._({required AiNativeInstruction instruction}) {
    final List<AiToken> operands = instruction.operands;
    final int nameIndex = operands.isNotEmpty && operands.first.number != null ? 1 : 0;
    if (operands.length != nameIndex + 11 && operands.length != nameIndex + 12 ||
        !const {AiTokenKind.string, AiTokenKind.hexString}.contains(operands[nameIndex].kind) ||
        operands.skip(nameIndex + 1).any((token) => token.number == null) ||
        nameIndex == 1 && !const {0, 1, 2}.contains(operands.first.number) ||
        operands.length == nameIndex + 12 && operands.last.number! <= 0) {
      throw const FormatException('Invalid native gradient geometry.');
    }
    return AiNativeGradientGeometry._checked(instruction: instruction, nameIndex: nameIndex);
  }

  /// Retains checked source tokens and their variant-specific layout.
  const AiNativeGradientGeometry._checked({required this.instruction, required this.nameIndex});

  /// Gradient resource name without selecting a document text encoding.
  Uint8List get nameBytes => aiStringBytes(instruction.operands[nameIndex]).asUnmodifiableView();

  /// Native clipping/render flag, defaulting to zero when omitted.
  int get flag => nameIndex == 0 ? 0 : instruction.operands.first.number!.toInt();

  /// Whether this is the CC layout with an explicit aspect-ratio operand.
  ///
  /// Its origin/length describe the artwork-relative gradient vector. The legacy
  /// layout uses page coordinates. Unknown future layouts are not guessed.
  bool get relativeToArtwork => instruction.operands.length == nameIndex + 12;

  /// Origin in the coordinate system identified by [relativeToArtwork].
  List<double> get origin => List.unmodifiable(instruction.operands.skip(nameIndex + 1).take(2).map((token) => token.number!.toDouble()));

  /// Gradient-vector angle in degrees.
  double get angle => instruction.operands[nameIndex + 3].number!.toDouble();

  /// Gradient-vector length in native units, or a relative factor in CC.
  double get length => instruction.operands[nameIndex + 4].number!.toDouble();

  /// Six affine coefficients retained in their native operand order.
  List<double> get matrix => List.unmodifiable(instruction.operands.skip(nameIndex + 5).take(6).map((token) => token.number!.toDouble()));

  /// Radial aspect ratio, or null when absent in the legacy layout.
  double? get aspectRatio => relativeToArtwork ? instruction.operands.last.number!.toDouble() : null;
}

/// A bounded Bb/BB gradient instance in artwork or a native paint style.
final class AiNativeGradient extends AiNativeItem {
  /// Opening gradient command, including the optional stroke-selector operand.
  final AiNativeInstruction opening;

  /// Native gradient resource reference and vector geometry.
  final AiNativeGradientGeometry geometry;

  /// Optional radial highlight command; its position is relative to the origin.
  final AiNativeInstruction? highlight;

  /// Absolute printing matrices from Xm, Bm and Bc, in source order.
  final List<AiNativeInstruction> imagingMatrices;

  /// Closing gradient command and original stroke/closure flag.
  final AiNativeInstruction closing;

  /// Paths painted inside this instance; empty for a style resource.
  final List<AiNativePath> paths;

  /// Creates a complete source-backed instance after structural checks.
  AiNativeGradient._({
    required this.opening,
    required this.geometry,
    required this.highlight,
    required List<AiNativeInstruction> imagingMatrices,
    required this.closing,
    required List<AiNativePath> paths,
  }) : imagingMatrices = List.unmodifiable(imagingMatrices),
       paths = List.unmodifiable(paths),
       super(start: opening.start, end: closing.end);

  /// Whether the optional Bb selector applies the gradient inside the stroke.
  bool get onStroke => opening.numbers?.singleOrNull == 1;
}

/// An interpreted command list inside a native fill, stroke, blend or simple style.
final class AiNativePaintStyle {
  /// Original style container, retaining unknown native fields.
  final AiNativeContainer record;

  /// Native commands in the style's Def or Paint entry, with exact source spans.
  final List<AiNativeInstruction> instructions;

  /// Validated gradient instances without flattening multiple style parts.
  final List<AiNativeGradient> gradients;

  /// Ordered literal paint assignments, including repeated settings.
  ///
  /// These are source assignments, not composed or inherited appearance values.
  /// Unknown commands remain in [instructions]; no defaults are synthesized.
  late final List<AiNativePaintAssignment> assignments = _nativePaintAssignments(instructions, gradients: gradients);

  /// Reads one paint style from an existing immutable records snapshot.
  factory AiNativePaintStyle.decode({required AiNativeRecords records, required AiNativeContainer record}) {
    if (!records._ownedContainers.contains(record) || !const {'FillStyle', 'StrokeStyle', 'BlendStyle', 'SimpleStyle'}.contains(record.type)) {
      throw ArgumentError('Expected a paint style owned by this native snapshot.');
    }
    final AiNativeEntry? definition = record[record.type == 'SimpleStyle' ? 'Paint' : 'Def'];
    if (definition == null || definition.items.any((item) => item is! AiNativeToken)) {
      throw const FormatException('Native paint style has no command definition.');
    }
    final _NativeCommandReader reader = _NativeCommandReader(maxDepth: records.program.limits.maxDepth);
    final List<AiNativeInstruction> instructions = [];
    for (final AiNativeToken item in definition.items.cast<AiNativeToken>()) {
      final AiNativeInstruction? command = reader.add(item.token, isPrivate: false);
      if (command != null) {
        instructions.add(command);
      }
    }
    reader.finish();
    return AiNativePaintStyle._(
      record: record,
      instructions: instructions,
      gradients: _readNativeGradients(instructions: instructions, paths: []),
    );
  }

  /// Creates an immutable command and gradient view.
  AiNativePaintStyle._({required this.record, required List<AiNativeInstruction> instructions, required List<AiNativeGradient> gradients})
    : instructions = List.unmodifiable(instructions),
      gradients = List.unmodifiable(gradients);
}
