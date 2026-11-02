part of 'package:aicodec/src/model/ai_native_records.dart';

/// Literal native paint settings whose scalar layouts are qualified.
enum AiNativePaintParameter {
  /// Process or named fill color, retaining authored alternatives.
  fillColor,

  /// One exact fill or stroke gradient application, including its source geometry.
  gradient,

  /// Process or named stroke color, retaining authored alternatives.
  strokeColor,

  /// Fill overprint flag.
  fillOverprint,

  /// Stroke overprint flag.
  strokeOverprint,

  /// Stroke width in native source units.
  strokeWidth,

  /// Native line-cap code: butt, round or projecting square.
  lineCap,

  /// Native line-join code: miter, round or bevel.
  lineJoin,

  /// Stroke miter-limit ratio.
  miterLimit,

  /// Dash lengths and phase in native source units.
  dash,

  /// Native even-odd winding flag.
  evenOdd,

  /// Both native Xd flags in their saved order.
  fillStrokeFlags,

  /// Literal opacity, blend mode, isolation, knockout and alpha-shape settings.
  transparency,
}

/// A literal dash pattern without normalization, scaling or inherited defaults.
final class AiNativeDashPattern {
  /// Original ordered lengths; an empty list explicitly requests a solid stroke.
  final List<double> lengths;

  /// Original phase, including valid negative values.
  final double phase;

  /// Freezes a checked native dash assignment.
  AiNativeDashPattern._({required List<double> lengths, required this.phase}) : lengths = List.unmodifiable(lengths);
}

/// One source-backed paint assignment rather than a flattened effective style.
final class AiNativePaintAssignment {
  /// Native parameter written by this command.
  final AiNativePaintParameter parameter;

  /// Exact source command and operands.
  final AiNativeInstruction instruction;

  /// Complete source gradient for an exact application assignment.
  final AiNativeGradient? gradient;

  /// Retains the assignment after validating its specific operand grammar.
  const AiNativePaintAssignment._({required this.parameter, required this.instruction, this.gradient});

  /// Numeric operands in native order, or null for named colors and dash arrays.
  List<double>? get numbers => instruction.numbers;

  /// Explicit transparency for this assignment, or null for other parameters.
  AiNativeTransparency? get transparency => parameter == .transparency ? AiNativeTransparency.decode(instruction: instruction) : null;

  /// Named color for this literal assignment, retaining its exact native layout.
  AiNativeNamedColor? get namedColor => AiNativeNamedColor.decode(instruction: instruction);

  /// Literal pattern placement for this exact fill or stroke assignment.
  AiNativePatternPaint? get pattern => AiNativePatternPaint.decode(instruction: instruction);

  /// Authored process colors, without choosing or converting dual alternatives.
  ///
  /// Seven-operand Xa/XA commands retain CMYK followed by RGB. Other settings
  /// return an empty list; named, pattern and gradient paints stay in the full
  /// command inventory or their typed assignment and are not relabeled as process colors.
  List<AiColor> get colors {
    if (parameter != .fillColor && parameter != .strokeColor || namedColor != null || pattern != null) {
      return const [];
    }
    final List<double> values = instruction.numbers!;
    return List.unmodifiable([
      if (values.length == 7) ...[
        AiColor(space: .cmyk, channels: values.take(4).toList()),
        AiColor(space: .rgb, channels: values.skip(4).toList()),
      ] else
        AiColor(
          space: values.length == 1
              ? .gray
              : values.length == 3
              ? .rgb
              : .cmyk,
          channels: values,
        ),
    ]);
  }

  /// Dash data for this exact assignment, or null for other parameters.
  AiNativeDashPattern? get dash => parameter != .dash
      ? null
      : AiNativeDashPattern._(
          lengths: instruction.operands.sublist(1, instruction.operands.length - 2).map((token) => token.number!.toDouble()).toList(),
          phase: instruction.operands.last.number!.toDouble(),
        );
}

/// Reads local literal assignments without executing unknown intervening commands.
List<AiNativePaintAssignment> _nativePaintAssignments(List<AiNativeInstruction> instructions, {List<AiNativeGradient> gradients = const []}) {
  final Map<int, AiNativeGradient> applications = {for (final AiNativeGradient gradient in gradients) gradient.opening.start: gradient};
  final List<AiNativePaintAssignment> assignments = [];
  for (final AiNativeInstruction instruction in instructions) {
    if (applications[instruction.start] case final AiNativeGradient gradient) {
      assignments.add(AiNativePaintAssignment._(parameter: .gradient, instruction: instruction, gradient: gradient));
      continue;
    }
    final AiNativePaintParameter? parameter = switch (instruction.operator) {
      'g' || 'k' || 'Xa' || 'x' || 'Xx' || 'Xs' || 'Xz' || 'p' => .fillColor,
      'G' || 'K' || 'XA' || 'X' || 'XX' || 'XS' || 'XZ' || 'P' => .strokeColor,
      'O' => .fillOverprint,
      'R' => .strokeOverprint,
      'w' => .strokeWidth,
      'J' => .lineCap,
      'j' => .lineJoin,
      'M' => .miterLimit,
      'd' => .dash,
      'XR' => .evenOdd,
      'Xd' => .fillStrokeFlags,
      'Xy' => .transparency,
      _ => null,
    };
    if (parameter == null) {
      continue;
    }
    if (parameter == .fillStrokeFlags) {
      final List<double>? values = instruction.numbers;
      if (values?.length != 2 || values!.any((value) => value != 0 && value != 1)) {
        throw const FormatException('Invalid native paint display flags.');
      }
    } else if (parameter == .transparency) {
      _artboardRetainedOpacity(instruction);
    } else if (const {'p', 'P'}.contains(instruction.operator)) {
      AiNativePatternPaint.decode(instruction: instruction);
    } else {
      _nativeArtworkStateKey(instruction);
    }
    assignments.add(AiNativePaintAssignment._(parameter: parameter, instruction: instruction));
  }
  return List.unmodifiable(assignments);
}
