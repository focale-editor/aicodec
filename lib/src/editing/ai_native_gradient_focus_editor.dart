part of 'package:aicodec/src/model/ai_native_records.dart';

/// Changes polar authoring values and redundant printing offsets together.
AiNativeGradientResources _setNativeGradientFocus(AiNativeGradientResources resources, AiNativeGradientDefinition definition, double angle, double length) {
  if (!resources.definitions.contains(definition) || !definition.radial || !angle.isFinite || angle.abs() > 360 || !_gradientUnit(length)) {
    throw ArgumentError('Expected an owned radial gradient, a finite angle in -360..360 and a focus length in 0..1.');
  }
  if (resources.definitions.any((candidate) => _gradientBytesEqual(candidate.nameBytes, definition.nameBytes) && !candidate.radial)) {
    throw const FormatException('Same-name native gradients have ambiguous linear/radial kinds.');
  }
  final List<AiSourceEdit> edits = [];
  int remaining = resources.records.program.limits.maxDecodedBytes - resources.records.program.bytes.length;
  for (final AiNativeGradient instance in _readGradientInstances(resources.records)) {
    if (!_gradientBytesEqual(instance.geometry.nameBytes, definition.nameBytes)) {
      continue;
    }
    final AiNativeInstruction? highlight = instance.highlight;
    final List<double> previous = highlight?.numbers ?? [0, 0, 0, 0];
    if (!_gradientUnit(previous[3])) {
      throw const FormatException('Invalid native radial focus length.');
    }
    final List<double>? matrix = _radialFocusMatrix(instance);
    final List<double> expected = _radialFocusOffset(matrix, previous[2], previous[3]);
    for (int axis = 0; axis < 2; axis++) {
      if ((previous[axis] - expected[axis]).abs() > 1e-6 + expected[axis].abs() * 1e-10) {
        throw UnsupportedError('Native radial focus disagrees with its printing offset.');
      }
    }
    // Retain Illustrator's original decimal precision when the polar values
    // already match; harmless round-off is not an edit or a cache repair.
    if (previous[2] == angle && previous[3] == length) {
      continue;
    }
    final List<double> values = [..._radialFocusOffset(matrix, angle, length), angle, length];
    if (highlight == null) {
      final String separator = resources.records._projection.isPrivate(instance.geometry.instruction.start) ? '\n%_' : '\n';
      final _GradientResourceWriter writer = _GradientResourceWriter(limit: remaining);
      writer.add('${values.join(' ')} Bh$separator');
      final Uint8List bytes = writer.output.takeBytes();
      remaining -= bytes.length;
      edits.add(AiSourceEdit(start: instance.geometry.instruction.start, end: instance.geometry.instruction.start, bytes: bytes));
    } else {
      for (int index = 0; index < values.length; index++) {
        if (values[index] == previous[index]) {
          continue;
        }
        final AiToken token = highlight.operands[index];
        final _GradientResourceWriter writer = _GradientResourceWriter(limit: remaining + token.end - token.start);
        writer.add(values[index].toString());
        final Uint8List bytes = writer.output.takeBytes();
        remaining += token.end - token.start - bytes.length;
        edits.add(AiSourceEdit(start: token.start, end: token.end, bytes: bytes));
      }
    }
  }
  if (edits.isEmpty) {
    return resources;
  }
  return AiNativeGradientResources.decode(
    records: AiNativeRecords.decode(
      program: AiNativeEditor.apply(program: resources.records.program, edits: edits),
    ),
  );
}

/// Qualifies absolute printing geometry or a nonprinting authoring note.
List<double>? _radialFocusMatrix(AiNativeGradient instance) {
  if (instance.imagingMatrices.isEmpty && instance.geometry.flag == 2) {
    return null;
  }
  if (instance.imagingMatrices.length != 1 || instance.imagingMatrices.single.operator != 'Bm') {
    throw UnsupportedError('Radial focus editing requires one printing matrix or a nonprinting style.');
  }
  final List<double> matrix = instance.imagingMatrices.single.numbers!;
  final double determinant = matrix[0] * matrix[3] - matrix[1] * matrix[2];
  if (matrix.any((value) => !value.isFinite || value.abs() > 9007199254740991) || !determinant.isFinite || determinant == 0) {
    throw const FormatException('Degenerate native radial gradient printing geometry.');
  }
  return matrix;
}

/// Maps the unit-circle focus vector without adding the gradient's center.
List<double> _radialFocusOffset(List<double>? matrix, double angle, double length) {
  if (matrix == null || length == 0) {
    return [0, 0];
  }
  final double radians = (angle % 360) * pi / 180;
  final double x = length * cos(radians);
  final double y = -length * sin(radians);
  final List<double> offset = [matrix[0] * x + matrix[2] * y, matrix[1] * x + matrix[3] * y];
  if (offset.any((value) => !value.isFinite || value.abs() > 9007199254740991)) {
    throw const FormatException('Native radial focus exceeds finite source-coordinate bounds.');
  }
  return offset;
}
