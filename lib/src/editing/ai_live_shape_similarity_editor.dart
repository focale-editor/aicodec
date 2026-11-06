part of 'package:illustratorkit/src/model/ai_native_records.dart';

/// Plans rotations and uniform scaling in drawing and native canvas coordinates.
final class _LiveShapeSimilarity {
  /// Source snapshot supplying the unique canvas origin and shape ownership.
  final AiNativeDrawing drawing;

  /// Counterclockwise angle in drawing coordinates.
  final double radians;

  /// Positive uniform scale, including corners and strokes.
  final double factor;

  /// Horizontal drawing-space pivot.
  final double pivotX;

  /// Vertical drawing-space pivot, with y upwards.
  final double pivotY;

  /// Canvas ruler origin decoded without touching the text-engine payload.
  late final List<double> origin;

  /// Exact cardinal cosine, or the ordinary trigonometric value.
  late final double cosine;

  /// Exact cardinal sine, or the ordinary trigonometric value.
  late final double sine;

  /// Creates a plan whose validation precedes every source edit.
  _LiveShapeSimilarity({
    required this.drawing,
    this.radians = 0,
    this.factor = 1,
    required this.pivotX,
    required this.pivotY,
  });

  /// Requires bounded transform inputs and an authoritative canvas origin.
  void validate() {
    if (!factor.isFinite ||
        factor <= 0 ||
        factor * factor == 0 ||
        factor > 9007199254740991 ||
        !radians.isFinite ||
        radians.abs() > 2 * pi ||
        [pivotX, pivotY].any((value) => !value.isFinite || value.abs() > 9007199254740991)) {
      throw ArgumentError('A similarity requires a positive bounded scale, an angle in -2π..2π and finite, bounded pivot coordinates.');
    }
    final double quarterTurns = radians / (pi / 2);
    final int? cardinal = quarterTurns == quarterTurns.roundToDouble() ? quarterTurns.toInt() % 4 : null;
    cosine = cardinal == null ? cos(radians) : const [1.0, 0.0, -1.0, 0.0][cardinal];
    sine = cardinal == null ? sin(radians) : const [0.0, 1.0, 0.0, -1.0][cardinal];
    final List<AiNativeContainer> documents = drawing.records.roots.where((record) => record.type == 'AI11TextDocument' && record.end <= drawing.records.program.bodyStart).toList();
    if (documents.length != 1 || documents.single['RulerOrigin']?.numbers?.length != 2) {
      throw UnsupportedError('Native transformation requires one setup text-document canvas ruler origin.');
    }
    origin = documents.single['RulerOrigin']!.numbers!;
    _bounded(origin);
  }

  /// Whether the operation leaves every point and native parameter unchanged.
  bool get isIdentity => factor == 1 && cosine == 1 && sine == 0;

  /// Transforms a drawing-space position without introducing a canvas offset.
  List<double> point(double x, double y) {
    final List<double> changed = _bounded([
      pivotX + factor * (cosine * (x - pivotX) - sine * (y - pivotY)),
      pivotY + factor * (sine * (x - pivotX) + cosine * (y - pivotY)),
    ]);
    if ((x != pivotX || y != pivotY) && changed[0] == pivotX && changed[1] == pivotY) {
      throw ArgumentError('Native transformation collapses a nonzero offset at numeric precision.');
    }
    return changed;
  }

  /// Transforms a canvas position using its stable drawing-to-canvas origin.
  List<double> _canvasPoint(double x, double y) {
    final List<double> moved = point(x - origin[0], origin[1] - y);
    return _bounded([origin[0] + moved[0], origin[1] - moved[1]]);
  }

  /// Updates native shape centers, angles and per-object gradient transforms.
  List<AiSourceEdit> dictionaryEdits(AiLiveShape shape, AiNativeContainer dictionary) {
    final List<AiSourceEdit> edits = [];
    final AiNativeContainer? parameters = dictionary['ai::LiveShape']?.container?['ai::LiveShape::Params']?.container;
    if (parameters != null) {
      final AiNativeEntry x = _parameter(parameters, '${shape.handler}::CenterX');
      final AiNativeEntry y = _parameter(parameters, '${shape.handler}::CenterY');
      final List<double> center = _canvasPoint(x.number!, y.number!);
      edits.addAll([_numberEdit(x.items.single, center[0]), _numberEdit(y.items.single, center[1])]);
      if (factor != 1) {
        edits.addAll(_scaleShapeParameters(shape, parameters, factor));
      }
      final AiNativeEntry angle = _parameter(parameters, '${shape.handler}::${shape.handler == 'ai::Rectangle' ? 'Angle' : 'RotationAngle'}');
      if (radians != 0) {
        edits.add(_numberEdit(angle.items.single, (angle.number! + radians) % (2 * pi)));
      }
    }
    final double previous = _nativeFrameRotation(dictionary) ?? 0;
    if (radians != 0) {
      final double frame = _signedAngle(previous + radians);
      edits.addAll(_nativeFrameRotationEdits(drawing.records, dictionary, dictionary.end, frame));
    }
    edits.addAll(_gradientDictionaryEdits(shape, dictionary));
    return edits;
  }

  /// Requires a real scalar rather than guessing native shape parameter types.
  AiNativeEntry _parameter(AiNativeContainer parameters, String name) {
    final AiNativeEntry? entry = parameters[name];
    if (entry?.type != 'Real' || entry?.number == null) {
      throw FormatException('Native transformation requires a real $name parameter.');
    }
    return entry!;
  }

  /// Keeps CC authoring, printing and radial-highlight coordinates coherent.
  List<AiSourceEdit> gradientEdits(AiNativeGradient gradient, {required bool style}) {
    final AiNativeGradientGeometry geometry = gradient.geometry;
    if (!geometry.relativeToArtwork) {
      throw UnsupportedError('Native transformation requires the qualified CC relative gradient layout.');
    }
    if (style || geometry.flag == 2 && gradient.imagingMatrices.isEmpty) {
      final List<double>? highlight = gradient.highlight?.numbers;
      if (geometry.flag != 2 ||
          gradient.imagingMatrices.isNotEmpty ||
          !_sameNativeMatrix(geometry.matrix, [1, 0, 0, 1, 0, 0]) ||
          highlight != null && (!_gradientUnit(highlight[3]) || !_sameNativeMatrix(highlight.take(2).toList(), [0, 0]))) {
        throw UnsupportedError('Native transformation requires a relative identity-matrix style note.');
      }
      return [];
    }
    final List<AiSourceEdit> edits = _matrixEdits(geometry.instruction.operands.skip(geometry.nameIndex + 5).take(6).toList(), canvas: true);
    for (final AiNativeInstruction matrix in gradient.imagingMatrices) {
      edits.addAll(_matrixEdits(matrix.operands, canvas: false));
    }
    if (gradient.highlight case final AiNativeInstruction highlight) {
      final List<double>? matrix = _radialFocusMatrix(gradient);
      final List<double> values = highlight.numbers!;
      final List<double> expected = _radialFocusOffset(matrix, values[2], values[3]);
      if (!_gradientUnit(values[3]) || !_sameNativeMatrix(values.take(2).toList(), expected)) {
        throw UnsupportedError('Native transformation requires a coherent radial highlight.');
      }
      final List<double> offset = _bounded([factor * (cosine * values[0] - sine * values[1]), factor * (sine * values[0] + cosine * values[1])]);
      for (int axis = 0; axis < 2; axis++) {
        edits.add(_numberEdit(AiNativeToken._(token: highlight.operands[axis]), offset[axis]));
      }
    }
    return edits;
  }

  /// Composes a similarity onto source-backed matrix operands in the chosen frame.
  List<AiSourceEdit> _matrixEdits(List<AiToken> tokens, {required bool canvas}) {
    final List<double> matrix = _matrix(tokens.map((token) => token.number!.toDouble()).toList(), canvas: canvas);
    return [for (int index = 0; index < 6; index++) _numberEdit(AiNativeToken._(token: tokens[index]), matrix[index])];
  }

  /// Composes with the y-up drawing frame or the y-down native canvas frame.
  List<double> _matrix(List<double> previous, {required bool canvas}) {
    final double determinant = previous[0] * previous[3] - previous[1] * previous[2];
    if (!determinant.isFinite || determinant == 0) {
      throw const FormatException('Native transformation requires nonsingular gradient matrices.');
    }
    final double rotationSine = canvas ? -sine : sine;
    final List<double> translation = canvas ? _canvasPoint(previous[4], previous[5]) : point(previous[4], previous[5]);
    final List<double> changed = _bounded([
      _scaleNativeLength(cosine * previous[0] - rotationSine * previous[1], factor),
      _scaleNativeLength(rotationSine * previous[0] + cosine * previous[1], factor),
      _scaleNativeLength(cosine * previous[2] - rotationSine * previous[3], factor),
      _scaleNativeLength(rotationSine * previous[2] + cosine * previous[3], factor),
      ...translation,
    ]);
    final double changedDeterminant = changed[0] * changed[3] - changed[1] * changed[2];
    if (!changedDeterminant.isFinite || changedDeterminant == 0) {
      throw ArgumentError('Native transformation produces a numerically singular gradient matrix.');
    }
    return changed;
  }

  /// Updates the observed per-object style transform without editing shared styles.
  List<AiSourceEdit> _gradientDictionaryEdits(AiLiveShape shape, AiNativeContainer dictionary) {
    final List<double>? original = _shapeGradientTransform(drawing, shape);
    if (original == null) {
      return [];
    }
    final AiNativeContainer? cached = dictionary['Adobe_AI9_ArtStyle_Dictionary']?.container;
    final List<double> changed = _matrix(original, canvas: true);
    if (cached != null) {
      final AiNativeEntry? entry = cached['CAIGradientTformMatrix'];
      if (cached.type != 'Dictionary' ||
          !cached.notRecorded ||
          cached.entries.any((entry) => !const {'NotRecorded', 'CAIGradientTformMatrix'}.contains(entry.key)) ||
          entry?.type != 'RealMatrix' ||
          entry?.numbers?.length != 6 ||
          !_sameNativeMatrix(entry!.numbers!, original)) {
        throw UnsupportedError('Inconsistent or unsupported native accumulated gradient metadata.');
      }
      return [for (int index = 0; index < 6; index++) _numberEdit(entry.items[index], changed[index])];
    }
    if (dictionary['Adobe_AI9_ArtStyle_Dictionary'] != null) {
      throw UnsupportedError('Unsupported native accumulated gradient metadata.');
    }
    final AiToken closing = drawing.records._projection.tokens.singleWhere((token) => token.end == dictionary.end && token.lexeme == ';');
    final String separator = drawing.records._projection.isPrivate(closing.start) ? '\n%_' : '\n';
    return [
      AiSourceEdit(
        start: closing.start,
        end: closing.start,
        bytes: latin1.encode('/Dictionary : /NotRecorded ,$separator${changed.join(' ')} /RealMatrix (CAIGradientTformMatrix) ,$separator; (Adobe_AI9_ArtStyle_Dictionary) ,$separator'),
      ),
    ];
  }

  /// Expands existing drawing extents conservatively, retaining stroke margins.
  List<AiSourceEdit> boundsEdits() {
    final List<double> translation = point(0, 0);
    return AiNativeEditor.affineBoundsEdits(program: drawing.records.program, matrix: [factor * cosine, factor * sine, -factor * sine, factor * cosine, ...translation]);
  }

  /// Rejects overflow before numeric tokens or source bounds are serialized.
  List<double> _bounded(List<double> values) {
    if (values.any((value) => !value.isFinite || value.abs() > 9007199254740991)) {
      throw ArgumentError('Native transformation exceeds finite source-coordinate limits.');
    }
    return values;
  }

  /// Retains accumulated frame angles within the observed signed full turn.
  double _signedAngle(double value) => value >= 0 ? value % (2 * pi) : -(-value % (2 * pi));
}

/// Allows serialization noise between redundant native geometry fields.
bool _sameNativeMatrix(List<double> first, List<double> second) =>
    first.length == second.length && first.indexed.every((entry) => (entry.$2 - second[entry.$1]).abs() <= 1e-6 + entry.$2.abs() * 1e-10);

/// Reads only the qualified accumulated-gradient metadata layout.
List<double>? _nativeGradientTransform(AiNativeContainer dictionary) {
  final AiNativeEntry? field = dictionary['Adobe_AI9_ArtStyle_Dictionary'];
  if (field == null) {
    return null;
  }
  final AiNativeContainer? cached = field.container;
  final AiNativeEntry? matrix = cached?['CAIGradientTformMatrix'];
  if (cached == null ||
      cached.type != 'Dictionary' ||
      !cached.notRecorded ||
      cached.entries.any((entry) => !const {'NotRecorded', 'CAIGradientTformMatrix'}.contains(entry.key)) ||
      matrix?.type != 'RealMatrix' ||
      matrix?.numbers?.length != 6) {
    throw UnsupportedError('Unsupported native accumulated-gradient metadata.');
  }
  return matrix!.numbers;
}

/// Requires one common CC transform for all gradient appearances of a shape.
List<double>? _shapeGradientTransform(AiNativeDrawing drawing, AiLiveShape shape) {
  final List<AiNativeGradient> gradients = drawing.gradients
      .where((gradient) => gradient.geometry.flag != 2 && (gradient.paths.any(shape.appearancePaths.contains) || gradient.start >= shape.start && gradient.end <= shape.end))
      .toList();
  if (gradients.isEmpty) {
    return null;
  }
  final List<double> matrix = gradients.first.geometry.matrix;
  if (gradients.any((gradient) => !gradient.geometry.relativeToArtwork || !_sameNativeMatrix(matrix, gradient.geometry.matrix))) {
    throw UnsupportedError('Native shape gradients require one common accumulated CC transform.');
  }
  return matrix;
}
