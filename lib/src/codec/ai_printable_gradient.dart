part of 'package:aikit/src/model/ai_native_pdf.dart';

/// Validated classic gradient data, independent of PDF object allocation.
final class _PrintableGradient {
  /// Original body instance and its clip/stroke flags.
  final AiNativeGradient native;

  /// Shared source-backed stops, retaining their original native ordering.
  final AiNativeGradientDefinition definition;

  /// Whether native gray represents black ink in a CMYK document.
  final bool cmyk;

  /// Stops ordered by position for PDF interpolation.
  final List<AiNativeGradientStop> stops;

  /// Absolute native printing transform of the unit gradient.
  late final List<double> matrix;

  /// Unit axial endpoints or radial focal/outer circles.
  late final List<double> coordinates;

  /// The common process color space selected without profile conversion.
  late final String colorSpace;

  /// Normalized channels in the selected PDF process space.
  late final List<List<double>> colors;

  /// Requires explicit printing geometry and representable classic colors.
  _PrintableGradient({required this.native, required this.definition, required this.cmyk}) : stops = [...definition.stops]..sort((first, second) => first.position.compareTo(second.position)) {
    if (native.onStroke || native.geometry.flag == 2 || native.paths.length != 1) {
      throw UnsupportedError('Unsupported native gradient stroke, disabled paint or multiple appearances.');
    }
    for (int index = 1; index < stops.length; index++) {
      if (stops[index].position <= stops[index - 1].position) {
        throw UnsupportedError('Coincident native gradient stops require explicit discontinuity handling.');
      }
    }
    final List<AiNativeInstruction> overall = native.imagingMatrices.where((command) => command.operator == 'Xm').toList();
    final List<AiNativeInstruction> intervals = native.imagingMatrices.where((command) => command.operator == 'Bm').toList();
    if (definition.radial) {
      if (overall.isNotEmpty || intervals.length != 1 || native.imagingMatrices.any((command) => command.operator == 'Bc')) {
        throw UnsupportedError('Radial gradients require one absolute printing matrix.');
      }
      matrix = intervals.single.numbers!;
      final List<double> highlight = native.highlight?.numbers ?? const [0, 0, 0, 0];
      if (highlight[3] < 0 || highlight[3] > 1) {
        throw UnsupportedError('Radial gradient focus lies outside its outer ellipse.');
      }
      final double angle = -highlight[2] * math.pi / 180;
      coordinates = [highlight[3] * math.cos(angle), highlight[3] * math.sin(angle), 0, 0, 0, 1];
    } else {
      if (native.highlight != null || overall.length > 1) {
        throw UnsupportedError('Invalid linear gradient printing geometry.');
      }
      if (overall.isNotEmpty) {
        matrix = overall.single.numbers!;
      } else if (intervals.length == 1 && stops.length == 2 && stops.first.position == 0 && stops.last.position == 100) {
        matrix = intervals.single.numbers!;
      } else {
        throw UnsupportedError('Linear gradients require a complete absolute printing matrix.');
      }
      coordinates = [0, 0, 1, 0];
    }
    final double determinant = matrix[0] * matrix[3] - matrix[1] * matrix[2];
    if (!determinant.isFinite || determinant == 0) {
      throw const FormatException('Degenerate native gradient printing matrix.');
    }
    final Set<AiNativeGradientColorKind> kinds = stops.map((stop) => stop.color.kind).toSet();
    if (kinds.any((kind) => kind != .gray && kind != .cmyk && kind != .rgb) || kinds.contains(AiNativeGradientColorKind.cmyk) && kinds.contains(AiNativeGradientColorKind.rgb) && !cmyk) {
      throw UnsupportedError('Native gradient colors require an explicit common process space.');
    }
    colorSpace = kinds.contains(AiNativeGradientColorKind.cmyk) || cmyk && !kinds.contains(AiNativeGradientColorKind.rgb)
        ? 'DeviceCMYK'
        : kinds.contains(AiNativeGradientColorKind.rgb)
        ? 'DeviceRGB'
        : 'DeviceGray';
    colors = stops.map((stop) {
      final List<double> components = stop.color.components;
      if (colorSpace == 'DeviceCMYK') {
        return stop.color.kind == .gray ? [0.0, 0.0, 0.0, 1 - components.single] : components.take(4).toList();
      }
      return colorSpace == 'DeviceRGB'
          ? stop.color.kind == .gray
                ? List<double>.filled(3, components.single)
                : components.skip(4).toList()
          : components;
    }).toList();
  }
}
