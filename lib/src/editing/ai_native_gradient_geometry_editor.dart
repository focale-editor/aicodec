part of 'package:aikit/src/model/ai_native_records.dart';

/// Keeps linear printing intervals aligned with an edited global resource.
final class _GradientGeometryEditor {
  /// Source records and every same-name resource being replaced.
  final AiNativeGradientResources resources;

  /// Last effective definition before all same-name definitions are rewritten.
  final AiNativeGradientDefinition definition;

  /// New stops, already checked to have nondecreasing positions.
  final List<AiNativeGradientStop> stops;

  /// Remaining bytes after the resource replacements, checked before expansion.
  int remaining;

  /// Binds geometry repair to the same immutable source and output budget.
  _GradientGeometryEditor({required this.resources, required this.definition, required this.stops, required this.remaining});

  /// Finds every referencing drawing, style and setup instance atomically.
  List<AiSourceEdit> edits() {
    final List<double> previous = definition.stops.map((stop) => stop.position / 100).toList()..sort();
    final List<double> next = stops.map((stop) => stop.position / 100).toList();
    if (definition.radial || previous.length == next.length && previous.indexed.every((entry) => entry.$2 == next[entry.$1])) {
      return [];
    }
    final List<AiSourceEdit> result = [];
    for (final AiNativeGradient instance in _readGradientInstances(resources.records)) {
      if (_gradientBytesEqual(instance.geometry.nameBytes, definition.nameBytes)) {
        result.addAll(_instance(instance, previous, next));
      }
    }
    return result;
  }

  /// Repartitions cached ramp strips without moving their overall native axis.
  List<AiSourceEdit> _instance(AiNativeGradient instance, List<double> previous, List<double> next) {
    final List<AiNativeInstruction> overall = instance.imagingMatrices.where((matrix) => matrix.operator == 'Xm').toList();
    final List<AiNativeInstruction> strips = instance.imagingMatrices.where((matrix) => matrix.operator == 'Bm').toList();
    final List<AiNativeInstruction> caps = instance.imagingMatrices.where((matrix) => matrix.operator == 'Bc').toList();
    if (strips.isEmpty && caps.isEmpty) {
      return [];
    }
    if ([previous, next].any((positions) => positions.toSet().length != positions.length)) {
      throw UnsupportedError('Linear hard stops require host-composed printing artwork without cached interval strips.');
    }
    if (instance.highlight != null || overall.length > 1 || strips.length != previous.length - 1 || caps.length > 2) {
      throw UnsupportedError('Unsupported linear gradient printing interval layout.');
    }
    final List<AiNativeInstruction> ordered = instance.imagingMatrices.where((matrix) => matrix.operator != 'Xm').toList();
    final AiNativeInstruction? before = ordered.first.operator == 'Bc' ? ordered.first : null;
    final AiNativeInstruction? after = ordered.last.operator == 'Bc' ? ordered.last : null;
    if (caps.length != (before == null ? 0 : 1) + (after == null ? 0 : 1) || before == null && previous.first != next.first || after == null && previous.last != next.last) {
      throw UnsupportedError('Gradient endpoint editing requires matching exterior printing caps.');
    }
    final List<double> first = strips.first.numbers!;
    final double span = previous[1] - previous.first;
    final double axisX = overall.isEmpty ? first[0] / span : overall.single.numbers![0];
    final double axisY = overall.isEmpty ? first[1] / span : overall.single.numbers![1];
    final List<double> matrix = [
      axisX,
      axisY,
      first[2],
      first[3],
      if (overall.isEmpty) first[4] - previous.first * axisX else overall.single.numbers![4],
      if (overall.isEmpty) first[5] - previous.first * axisY else overall.single.numbers![5],
    ];
    final double determinant = matrix[0] * matrix[3] - matrix[1] * matrix[2];
    if (matrix.any((value) => !value.isFinite) || !determinant.isFinite || determinant == 0) {
      throw const FormatException('Degenerate native gradient printing geometry.');
    }
    for (int index = 0; index < strips.length; index++) {
      _requireMatrix(strips[index].numbers!, _strip(matrix, previous[index], previous[index + 1]));
    }
    final List<AiSourceEdit> result = [];
    for (final (AiNativeInstruction?, bool) cap in [(before, true), (after, false)]) {
      if (cap.$1 case final AiNativeInstruction instruction) {
        final List<double> old = instruction.numbers!;
        final double position = cap.$2 ? previous.first : previous.last;
        _requireMatrix(
          [old[2], old[3], old[4] + (cap.$2 ? old[0] : 0), old[5] + (cap.$2 ? old[1] : 0)],
          [matrix[2], matrix[3], matrix[4] + position * axisX, matrix[5] + position * axisY],
        );
        final double delta = (cap.$2 ? next.first : next.last) - position;
        if (delta == 0) {
          continue;
        }
        final List<double> changed = [
          old[0] + (cap.$2 ? delta : -delta) * axisX,
          old[1] + (cap.$2 ? delta : -delta) * axisY,
          old[2],
          old[3],
          old[4] + (cap.$2 ? 0 : delta * axisX),
          old[5] + (cap.$2 ? 0 : delta * axisY),
        ];
        final double scale = axisX.abs() >= axisY.abs() ? changed[0] / axisX : changed[1] / axisY;
        if (!scale.isFinite || scale <= 0) {
          throw UnsupportedError('Edited gradient exceeds its exterior printing caps.');
        }
        _requireMatrix(changed.take(2).toList(), [scale * axisX, scale * axisY]);
        result.add(_replace(instruction, [changed]));
      }
    }
    for (final AiNativeInstruction extra in strips.skip(1)) {
      result.add(_replace(extra, []));
    }
    result.add(_replace(strips.first, Iterable.generate(next.length - 1, (index) => _strip(matrix, next[index], next[index + 1]))));
    return result;
  }

  /// Writes source-aware commands without turning private styles into operators.
  AiSourceEdit _replace(AiNativeInstruction instruction, Iterable<List<double>> matrices) {
    final _GradientResourceWriter writer = _GradientResourceWriter(limit: remaining + instruction.end - instruction.start);
    final String separator = resources.records._projection.isPrivate(instruction.start) ? '\n%_' : '\n';
    bool first = true;
    for (final List<double> matrix in matrices) {
      if (!first) {
        writer.add(separator);
      }
      first = false;
      if (matrix.any((value) => !value.isFinite)) {
        throw const FormatException('Gradient printing matrix exceeds finite coordinates.');
      }
      writer.add('${matrix.join(' ')} ${instruction.operator}');
    }
    final Uint8List bytes = writer.output.takeBytes();
    remaining += instruction.end - instruction.start - bytes.length;
    return AiSourceEdit(start: instruction.start, end: instruction.end, bytes: bytes);
  }

  /// Computes a unit printing strip from two global ramp positions.
  List<double> _strip(List<double> matrix, double start, double end) {
    final double axisX = (end - start) * matrix[0];
    final double axisY = (end - start) * matrix[1];
    if (end <= start || axisX == 0 && axisY == 0) {
      throw const FormatException('Gradient printing interval collapses at floating-point precision.');
    }
    return [axisX, axisY, matrix[2], matrix[3], matrix[4] + start * matrix[0], matrix[5] + start * matrix[1]];
  }

  /// Allows decimal serialization noise while rejecting conflicting placements.
  void _requireMatrix(List<double> actual, List<double> expected) {
    for (int index = 0; index < actual.length; index++) {
      if (!expected[index].isFinite || (actual[index] - expected[index]).abs() > 1e-6 + expected[index].abs() * 1e-10) {
        throw UnsupportedError('Inconsistent native gradient printing matrices.');
      }
    }
  }
}
