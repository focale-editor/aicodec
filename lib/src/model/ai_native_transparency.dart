part of 'package:illustratorkit/src/model/ai_native_records.dart';

/// Native Illustrator blend modes, without application compositing behavior.
enum AiNativeBlendMode {
  /// Normal compositing.
  normal,

  /// Multiply compositing.
  multiply,

  /// Screen compositing.
  screen,

  /// Overlay compositing.
  overlay,

  /// Soft-light compositing.
  softLight,

  /// Hard-light compositing.
  hardLight,

  /// Color-dodge compositing.
  colorDodge,

  /// Color-burn compositing.
  colorBurn,

  /// Darken compositing.
  darken,

  /// Lighten compositing.
  lighten,

  /// Difference compositing.
  difference,

  /// Exclusion compositing.
  exclusion,

  /// Hue compositing.
  hue,

  /// Saturation compositing.
  saturation,

  /// Color compositing.
  color,

  /// Luminosity compositing.
  luminosity,
}

/// Explicit native knockout state, retaining inheritance as a distinct value.
enum AiNativeKnockout {
  /// Disables knockout at this owner.
  off,

  /// Enables knockout at this owner.
  on,

  /// Uses the parent owner's knockout state.
  inherit,
}

/// Literal transparency data shared by paint, object and group assignments.
///
/// Values do not establish which artwork consumes a command. Keep the original
/// style part or drawing command ownership; the host resolves inheritance and
/// composites the result. Enum indices match Adobe's native codes.
final class AiNativeTransparency {
  /// Blend mode applied when compositing the owner into its backdrop.
  final AiNativeBlendMode blendMode;

  /// Opacity between zero and one, independent of the owner's color.
  final double opacity;

  /// Whether blending within the owner is isolated from its outer backdrop.
  final bool isolated;

  /// Explicit knockout choice, including unresolved parent inheritance.
  final AiNativeKnockout knockout;

  /// Whether opacity and the mask define the knockout shape.
  final bool alphaIsShape;

  /// Captures explicit native settings without composing or inferring defaults.
  AiNativeTransparency({
    required this.blendMode,
    required this.opacity,
    required this.isolated,
    required this.knockout,
    required this.alphaIsShape,
  }) {
    if (!_gradientUnit(opacity)) {
      throw ArgumentError.value(opacity, 'opacity', 'Expected a finite value between zero and one.');
    }
  }

  /// Decodes one literal Xy command, preserving its raw source on the caller.
  ///
  /// Malformed tuples throw [FormatException]; unknown codes throw
  /// [UnsupportedError]. The containing native snapshot remains unchanged.
  factory AiNativeTransparency.decode({required AiNativeInstruction instruction}) {
    if (instruction.operator != 'Xy') {
      throw ArgumentError('Native transparency requires an Xy instruction.');
    }
    _artboardRetainedOpacity(instruction);
    final List<double> values = instruction.numbers!;
    return AiNativeTransparency(
      blendMode: AiNativeBlendMode.values[values[0].toInt()],
      opacity: values[1],
      isolated: values[2] == 1,
      knockout: AiNativeKnockout.values[values[3].toInt()],
      alphaIsShape: values[4] == 1,
    );
  }

  /// Immutable operands in native Xy order, ready for a source paint change.
  List<double> get operands => List.unmodifiable([blendMode.index.toDouble(), opacity, if (isolated) 1.0 else 0.0, knockout.index.toDouble(), if (alphaIsShape) 1.0 else 0.0]);
}
