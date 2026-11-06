part of 'package:illustratorkit/src/model/ai_native_records.dart';

/// Synchronizes relative authoring geometry with printable gradient placement.
final class _LiveShapeGradientPlacement implements _LiveShapeGradientEdit {
  /// Source snapshot owning every selected native appearance.
  final AiNativeDrawing drawing;

  /// Resource whose occurrences are edited within each selected shape.
  final List<int> nameBytes;

  /// Relative x/y origin, angle in degrees, positive length and aspect ratio.
  final List<double> placement;

  /// Effective resource, qualified before any instance edits are planned.
  late final AiNativeGradientDefinition definition;

  /// Available source growth, charged before generated commands are allocated.
  late int remaining;

  /// Reuses edits when selected shapes share one source style.
  final Map<int, List<AiSourceEdit>> _instances = {};

  /// Conservative stroke reach at each printable path-consuming instruction.
  late final Map<int, double> _strokeReach = _readStrokeReach();

  /// Captures caller values without retaining mutable input lists.
  _LiveShapeGradientPlacement({required this.drawing, required List<int> nameBytes, required List<double> placement})
    : nameBytes = List.unmodifiable(nameBytes),
      placement = List.unmodifiable(placement);

  @override
  void validate() {
    if (nameBytes.isEmpty ||
        nameBytes.any((value) => value < 0 || value > 255) ||
        placement.any((value) => !value.isFinite || value.abs() > 9007199254740991) ||
        placement[2].abs() > 360 ||
        placement[3] <= 0 ||
        placement[4] <= 0) {
      throw ArgumentError('Gradient placement requires a byte name, bounded origins, an angle in -360..360 and positive length/aspect.');
    }
    final List<AiNativeGradientDefinition> definitions = AiNativeGradientResources.decode(records: drawing.records).definitions
        .where((definition) => _gradientBytesEqual(definition.nameBytes, nameBytes))
        .toList();
    if (definitions.isEmpty) {
      throw ArgumentError('Gradient placement requires a declared source resource.');
    }
    definition = definitions.last;
    final List<double> positions = _positions(definition);
    if (definitions.any((candidate) => candidate.radial != definition.radial || !_sameNativeMatrix(_positions(candidate), positions))) {
      throw const FormatException('Same-name native gradients have ambiguous kinds or stop intervals.');
    }
    if (!definition.radial && (placement[1] != 0 || placement[4] != 1)) {
      throw ArgumentError('Linear gradient placement requires zero vertical origin and unit aspect ratio.');
    }
    for (int index = 1; index < positions.length; index++) {
      if (positions[index] <= positions[index - 1]) {
        throw UnsupportedError('Gradient placement requires distinct source stop positions.');
      }
    }
    remaining = drawing.records.program.limits.maxDecodedBytes - drawing.records.program.bytes.length;
  }

  @override
  void validateShape(AiLiveShape shape) => _validateLiveShapeGradient(drawing, shape, nameBytes);

  @override
  List<AiSourceEdit> resourceEdits() => [];

  @override
  List<AiSourceEdit> instanceEdits(AiNativeGradient gradient) {
    if (!_gradientBytesEqual(gradient.geometry.nameBytes, nameBytes)) {
      return [];
    }
    return _instances.putIfAbsent(gradient.start, () => _editInstance(gradient));
  }

  /// Qualifies both representations before changing any numeric source token.
  List<AiSourceEdit> _editInstance(AiNativeGradient gradient) {
    final AiNativeGradientGeometry geometry = gradient.geometry;
    final List<double> previous = [...geometry.origin, geometry.angle, geometry.length, geometry.aspectRatio ?? 1];
    if (!geometry.relativeToArtwork || previous[3] <= 0 || !definition.radial && (previous[1] != 0 || previous[4] != 1 || gradient.highlight != null)) {
      throw UnsupportedError('Gradient placement requires the qualified CC relative geometry layout.');
    }
    _placementFinite(previous);
    final bool note = gradient.imagingMatrices.isEmpty;
    final List<double> highlight = gradient.highlight?.numbers ?? [0, 0, 0, 0];
    List<double>? target;
    if (note) {
      if (geometry.flag != 2 || !_sameNativeMatrix(geometry.matrix, [1, 0, 0, 1, 0, 0]) || !_sameNativeMatrix(highlight.take(2).toList(), [0, 0])) {
        throw UnsupportedError('Gradient placement requires identity-matrix nonprinting style notes.');
      }
    } else {
      if (gradient.paths.isEmpty || geometry.flag != 1) {
        throw UnsupportedError('Gradient placement requires owned clipped printable curves.');
      }
      final List<double> original = _placementFrame(gradient, definition.radial, previous);
      target = _placementFrame(gradient, definition.radial, placement);
      if (definition.radial) {
        final List<double>? matrix = _radialFocusMatrix(gradient);
        if (matrix == null || !_sameNativeMatrix(matrix, original) || !_sameNativeMatrix(highlight.take(2).toList(), _radialFocusOffset(matrix, highlight[2], highlight[3]))) {
          throw UnsupportedError('Radial printing geometry disagrees with relative authoring placement.');
        }
      } else {
        _validateLinear(gradient, original);
      }
    }
    if (!_gradientUnit(highlight[3])) {
      throw const FormatException('Invalid radial focus in native gradient placement.');
    }
    if (previous.indexed.every((entry) => entry.$2 == placement[entry.$1])) {
      return [];
    }
    final List<AiToken> parameters = [
      ...geometry.instruction.operands.skip(geometry.nameIndex + 1).take(4),
      geometry.instruction.operands.last,
    ];
    final List<AiSourceEdit> edits = [
      for (int index = 0; index < parameters.length; index++)
        if (previous[index] != placement[index]) _number(parameters[index], placement[index]),
    ];
    if (target != null) {
      if (definition.radial) {
        final AiNativeInstruction matrix = gradient.imagingMatrices.single;
        edits.addAll([for (int index = 0; index < 6; index++) _number(matrix.operands[index], target[index])]);
        if (gradient.highlight case final AiNativeInstruction focus) {
          final List<double> offset = _radialFocusOffset(target, highlight[2], highlight[3]);
          edits.addAll([
            for (int index = 0; index < 2; index++)
              if (offset[index] != highlight[index]) _number(focus.operands[index], offset[index]),
          ]);
        }
      } else {
        edits.addAll(_linearEdits(gradient, target));
      }
    }
    return edits;
  }

  /// Requires source strips and exterior caps aligned to the native gradient axis.
  void _validateLinear(AiNativeGradient gradient, List<double> frame) {
    final List<AiNativeInstruction> overall = gradient.imagingMatrices.where((matrix) => matrix.operator == 'Xm').toList();
    final List<AiNativeInstruction> strips = gradient.imagingMatrices.where((matrix) => matrix.operator == 'Bm').toList();
    final List<AiNativeInstruction> caps = gradient.imagingMatrices.where((matrix) => matrix.operator == 'Bc').toList();
    final List<double> positions = _positions(definition);
    if (overall.length != 1 || strips.length != positions.length - 1 || caps.length > 2) {
      throw UnsupportedError('Linear gradient placement requires one overall matrix and complete printing strips.');
    }
    final List<double> source = overall.single.numbers!;
    final List<double> local = _placementProduct(_placementInverse(frame), source);
    if (!_sameNativeMatrix([local[0], local[1], local[2], local[4]], [1, 0, 0, 0]) || local[3] <= 0) {
      throw UnsupportedError('Linear printing geometry disagrees with relative authoring placement.');
    }
    for (int index = 0; index < strips.length; index++) {
      if (!_sameNativeMatrix(strips[index].numbers!, _placementProduct(source, [positions[index + 1] - positions[index], 0, 0, 1, positions[index], 0]))) {
        throw UnsupportedError('Linear printing intervals disagree with their resource stops.');
      }
    }
    final List<AiNativeInstruction> ordered = gradient.imagingMatrices.where((matrix) => matrix.operator != 'Xm').toList();
    for (final AiNativeInstruction cap in caps) {
      final bool before = identical(cap, ordered.first);
      if (!before && !identical(cap, ordered.last)) {
        throw UnsupportedError('Linear exterior caps interrupt the printing strips.');
      }
      final List<double> local = _placementProduct(_placementInverse(source), cap.numbers!);
      if (local[0] <= 0 || !_sameNativeMatrix([local[1], local[2], local[3], local[5], local[4] + (before ? local[0] : 0)], [0, 0, 1, 0, if (before) positions.first else positions.last])) {
        throw UnsupportedError('Linear exterior cap boundaries disagree with the resource stops.');
      }
    }
  }

  /// Rebuilds finite strips and caps covering the fixed printable artwork.
  List<AiSourceEdit> _linearEdits(AiNativeGradient gradient, List<double> frame) {
    final List<AiNativeInstruction> matrices = gradient.imagingMatrices;
    final List<AiNativeItem> between = drawing.items.where((item) => item.start >= matrices.first.start && item.end <= matrices.last.end).toList();
    if (between.any((item) => item is! AiNativeInstruction || !const {'Xm', 'Bm', 'Bc'}.contains(item.operator))) {
      throw UnsupportedError('Gradient placement requires contiguous printing matrices.');
    }
    final List<double> inverse = _placementInverse(frame);
    final AiBoundingBox bounds = _placementBounds(gradient.paths, [1, 0, 0, 1, 0, 0]);
    final double margin = 2 + _strokeMargin(gradient);
    final List<List<double>> corners = [
      for (final double x in [bounds.left - margin, bounds.right + margin])
        for (final double y in [bounds.bottom - margin, bounds.top + margin]) _placementPoint(inverse, x, y),
    ];
    final List<double> positions = _positions(definition);
    final double left = min(positions.first, corners.map((point) => point[0]).reduce(min)) - 1;
    final double right = max(positions.last, corners.map((point) => point[0]).reduce(max)) + 1;
    final double top = corners.map((point) => point[1]).reduce(min) - 1;
    final double bottom = corners.map((point) => point[1]).reduce(max) + 1;
    final List<(String, double, double)> intervals = [
      ('Xm', 0, 1),
      ('Bc', left, positions.first),
      for (int index = 1; index < positions.length; index++) ('Bm', positions[index - 1], positions[index]),
      ('Bc', positions.last, right),
    ];
    final AiNativeInstruction first = matrices.first;
    final _GradientResourceWriter writer = _GradientResourceWriter(limit: remaining + first.end - first.start);
    final String separator = first.isPrivate ? '\n%_' : '\n';
    for (final (String, double, double) interval in intervals) {
      final List<double> matrix = _placementProduct(frame, [interval.$3 - interval.$2, 0, 0, bottom - top, interval.$2, top]);
      _placementInverse(matrix);
      if (interval != intervals.first) {
        writer.add(separator);
      }
      writer.add('${matrix.join(' ')} ${interval.$1}');
    }
    final Uint8List bytes = writer.output.takeBytes();
    remaining += first.end - first.start - bytes.length;
    return [
      AiSourceEdit(start: first.start, end: first.end, bytes: bytes),
      for (final AiNativeInstruction extra in matrices.skip(1)) AiSourceEdit(start: extra.start, end: extra.end, bytes: []),
    ];
  }

  /// Sorted unit positions independent of native linear/radial source ordering.
  List<double> _positions(AiNativeGradientDefinition resource) => resource.stops.map((stop) => stop.position / 100).toList()..sort();

  /// Requires resolved printable stroke state for every consumed centerline.
  double _strokeMargin(AiNativeGradient gradient) {
    double margin = 0;
    if (gradient.onStroke) {
      for (final AiNativePath path in gradient.paths) {
        final double? reach = _strokeReach[path.paint.start];
        if (reach == null) {
          throw UnsupportedError('Gradient placement requires resolved printable stroke distances.');
        }
        margin = max(margin, reach);
      }
    }
    return margin;
  }

  /// Reads inherited printable width/miter state, including graphics saves.
  Map<int, double> _readStrokeReach() {
    double width = 1;
    double miter = 10;
    final List<(double, double)> stack = [];
    final Set<int> paints = drawing.paths.where((path) => !path.isPrivate).map((path) => path.paint.start).toSet();
    final Map<int, double> reach = {};
    for (final AiNativeInstruction instruction in drawing.items.whereType<AiNativeInstruction>().where((instruction) => !instruction.isPrivate)) {
      if (instruction.operator == 'q') {
        stack.add((width, miter));
      } else if (instruction.operator == 'Q') {
        if (stack.isEmpty) {
          throw const FormatException('Unbalanced native stroke graphics state.');
        }
        (width, miter) = stack.removeLast();
      } else if (const {'w', 'M'}.contains(instruction.operator)) {
        final List<double>? values = instruction.numbers;
        if (values?.length != 1 || values!.single < (instruction.operator == 'w' ? 0 : 1)) {
          throw const FormatException('Invalid native width or miter limit.');
        }
        if (instruction.operator == 'w') {
          width = values.single;
        } else {
          miter = values.single;
        }
      }
      if (paints.contains(instruction.start)) {
        reach[instruction.start] = _placementFinite([width * miter]).single;
      }
    }
    if (stack.isNotEmpty) {
      throw const FormatException('Unterminated native stroke graphics state.');
    }
    return reach;
  }

  /// Replaces one bounded numeric token, charging output growth before allocation.
  AiSourceEdit _number(AiToken token, double value) {
    _placementFinite([value]);
    final _GradientResourceWriter writer = _GradientResourceWriter(limit: remaining + token.end - token.start);
    writer.add(value.toString());
    final Uint8List bytes = writer.output.takeBytes();
    remaining += token.end - token.start - bytes.length;
    return AiSourceEdit(start: token.start, end: token.end, bytes: bytes);
  }
}
