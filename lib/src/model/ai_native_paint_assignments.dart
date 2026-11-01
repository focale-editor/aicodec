part of 'package:aikit/src/model/ai_native_records.dart';

/// Literal native paint settings whose scalar layouts are qualified.
enum AiNativePaintParameter {
  /// Process fill color, retaining both alternatives when explicitly present.
  fillColor,

  /// Process stroke color, retaining both alternatives when explicitly present.
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

  /// Retains the assignment after validating its specific operand grammar.
  const AiNativePaintAssignment._({required this.parameter, required this.instruction});

  /// Numeric operands in native order, or null for an array-valued dash command.
  List<double>? get numbers => instruction.numbers;

  /// Authored process colors, without choosing or converting dual alternatives.
  ///
  /// Seven-operand Xa/XA commands retain CMYK followed by RGB. Other settings
  /// return an empty list; named, pattern and gradient paints stay in the full
  /// command inventory and are not relabeled as process colors.
  List<AiColor> get colors {
    if (parameter != .fillColor && parameter != .strokeColor) {
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
List<AiNativePaintAssignment> _nativePaintAssignments(List<AiNativeInstruction> instructions) {
  final List<AiNativePaintAssignment> assignments = [];
  for (final AiNativeInstruction instruction in instructions) {
    final AiNativePaintParameter? parameter = switch (instruction.operator) {
      'g' || 'k' || 'Xa' => .fillColor,
      'G' || 'K' || 'XA' => .strokeColor,
      'O' => .fillOverprint,
      'R' => .strokeOverprint,
      'w' => .strokeWidth,
      'J' => .lineCap,
      'j' => .lineJoin,
      'M' => .miterLimit,
      'd' => .dash,
      'XR' => .evenOdd,
      'Xd' => .fillStrokeFlags,
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
    } else {
      _nativeArtworkStateKey(instruction);
    }
    assignments.add(AiNativePaintAssignment._(parameter: parameter, instruction: instruction));
  }
  return List.unmodifiable(assignments);
}
