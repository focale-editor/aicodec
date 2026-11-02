part of 'package:aicodec/src/model/ai_native_records.dart';

/// Complete scalar parameters for a qualified native live-shape handler.
///
/// Keys omit the handler prefix, for example `Width`, `NumSides` or
/// `CornerRadius::0`. Unknown fields reject; the supplied contour and printing
/// expansion remain host responsibilities when parameters change.
final class AiNativeShapeParameters {
  /// Native rectangle, ellipse, polygon, star or line handler.
  final String handler;

  /// Real dimensions/angles and integral counts or numeric corner choices.
  final Map<String, double> numbers;

  /// Native boolean values, including orientation and regularity.
  final Map<String, bool> flags;

  /// Rectangle corner and rounding choices in their native spelling.
  final Map<String, String> choices;

  /// Owns an immutable, fully checked parameter set.
  AiNativeShapeParameters({required this.handler, required Map<String, double> numbers, Map<String, bool> flags = const {}, Map<String, String> choices = const {}})
    : numbers = Map.unmodifiable(numbers),
      flags = Map.unmodifiable(flags),
      choices = Map.unmodifiable(choices) {
    _validateNativeShapeParameters(this);
  }

  /// Captures known source values without changing handler, dimensions or flags.
  factory AiNativeShapeParameters.fromShape({required AiLiveShape shape}) {
    final Map<String, double> numbers = {};
    final Map<String, bool> flags = {};
    final Map<String, String> choices = {};
    for (final AiNativeEntry entry in shape.parameters.entries.where((entry) => !entry.isQualifier)) {
      final String? key = entry.key;
      if (key == null || !key.startsWith('${shape.handler}::')) {
        throw UnsupportedError('Native shape parameters have an unknown owner.');
      }
      final String name = key.substring(shape.handler.length + 2);
      final String type = _nativeShapeParameterType(shape.handler, name);
      if (entry.type != type) {
        throw const FormatException('Native shape parameter type disagrees with its schema.');
      }
      switch (type) {
        case 'Bool':
          if (entry.boolean == null) {
            throw const FormatException('Invalid native shape boolean.');
          }
          flags[name] = entry.boolean!;
        case 'UnicodeString':
          final String? value = entry.text();
          if (value == null) {
            throw const FormatException('Invalid native corner choice.');
          }
          choices[name] = value;
        default:
          if (entry.number == null) {
            throw const FormatException('Invalid native shape scalar.');
          }
          numbers[name] = entry.number!;
      }
    }
    return AiNativeShapeParameters(handler: shape.handler, numbers: numbers, flags: flags, choices: choices);
  }

  /// Changes explicit fields while preserving every other qualified parameter.
  AiNativeShapeParameters copyWith({Map<String, double> numbers = const {}, Map<String, bool> flags = const {}, Map<String, String> choices = const {}}) =>
      AiNativeShapeParameters(handler: handler, numbers: {...this.numbers, ...numbers}, flags: {...this.flags, ...flags}, choices: {...this.choices, ...choices});
}

/// One host-regenerated shape, including all dependent native representations.
final class AiNativeLiveShapeReplacement {
  /// Source handle from the drawing being edited.
  final AiLiveShape shape;

  /// Complete resulting native parameters, including any explicit family change.
  final AiNativeShapeParameters parameters;

  /// Host-composed authoring contour, with the source closure and paint retained.
  final List<AiPathSegment> segments;

  /// Complete host-composed group for a separate CC printing expansion.
  final List<int>? printing;

  /// Explicit resulting frame angle; null requires absent source frame metadata.
  final double? rotationRadians;

  /// Host-computed complete ink bounds, including strokes and effects.
  final AiBoundingBox bounds;

  /// Captures one immutable transaction without generating shape or stroke curves.
  AiNativeLiveShapeReplacement({required this.shape, required this.parameters, required List<AiPathSegment> segments, required this.bounds, required this.rotationRadians, List<int>? printing})
    : segments = List.unmodifiable(segments),
      printing = printing == null ? null : List.unmodifiable(printing) {
    if (segments.isEmpty ||
        segments.first.operator != 'm' ||
        segments.skip(1).any((segment) => segment.operator == 'm') ||
        segments.any((segment) => segment.coordinates.any((coordinate) => coordinate.abs() > 9007199254740991))) {
      throw ArgumentError('Native live-shape replacement requires one portable authoring contour.');
    }
    if (printing != null && printing.any((byte) => byte < 0 || byte > 255) || rotationRadians != null && (!rotationRadians!.isFinite || rotationRadians!.abs() > 2 * pi)) {
      throw ArgumentError('Invalid native printing bytes or frame angle.');
    }
    _nativeTopologyBounds(bounds);
  }
}

/// Rejects unknown schemas and invalid numeric ranges before allocating edits.
void _validateNativeShapeParameters(AiNativeShapeParameters parameters) {
  final Set<String>? fields = _shapeParameters[parameters.handler];
  if (fields == null) {
    throw UnsupportedError('Unsupported native shape handler ${parameters.handler}.');
  }
  for (final MapEntry<String, double> entry in parameters.numbers.entries) {
    final String type = _nativeShapeParameterType(parameters.handler, entry.key);
    if (!fields.contains(entry.key) ||
        !{'Real', 'Int'}.contains(type) ||
        !entry.value.isFinite ||
        entry.value.abs() > 9007199254740991 ||
        type == 'Int' && entry.value != entry.value.truncateToDouble()) {
      throw ArgumentError('Invalid native numeric parameter ${entry.key}.');
    }
    final bool sentinel = parameters.handler == 'ai::Polygon' && entry.key == 'Radius' && entry.value == -11 && parameters.flags['IsRegular'] == false;
    if (!sentinel && (entry.key.contains('Radius') || {'Width', 'Height', 'Length'}.contains(entry.key)) && entry.value < 0 || {'Width', 'Height', 'Length'}.contains(entry.key) && entry.value == 0) {
      throw ArgumentError('Native shape dimensions and radii must be nonnegative, with positive extents.');
    }
    if ({'Angle', 'RotationAngle', 'PieStartAngle', 'PieEndAngle'}.contains(entry.key) && entry.value.abs() > 2 * pi ||
        entry.key == 'NumSides' && entry.value < 3 ||
        entry.key == 'NumPoints' && entry.value < 2 ||
        entry.key == 'InitialQuadrant' && (entry.value < 0 || entry.value > 3)) {
      throw ArgumentError('Native shape angle, count or quadrant is outside its range.');
    }
    if (entry.key.contains('Type') && (entry.value < 0 || entry.value > (entry.key.contains('Rounding') ? 1 : 3))) {
      throw ArgumentError('Unknown native corner mode.');
    }
  }
  for (final String name in parameters.flags.keys) {
    if (!fields.contains(name) || _nativeShapeParameterType(parameters.handler, name) != 'Bool') {
      throw ArgumentError('Invalid native shape flag $name.');
    }
  }
  for (final MapEntry<String, String> entry in parameters.choices.entries) {
    final Set<String> values = entry.key.startsWith('RoundingType::') ? {'Invalid', 'Absolute', 'Relative'} : {'Invalid', 'Normal', 'Inverted', 'Chamfer'};
    if (!fields.contains(entry.key) || _nativeShapeParameterType(parameters.handler, entry.key) != 'UnicodeString' || !values.contains(entry.value)) {
      throw ArgumentError('Invalid native corner choice ${entry.key}.');
    }
  }
  final Set<String> required = {
    'CenterX',
    'CenterY',
    if (parameters.handler == 'ai::Rectangle') 'Angle' else 'RotationAngle',
    ...switch (parameters.handler) {
      'ai::Rectangle' || 'ai::Ellipse' => {'Width', 'Height'},
      'ai::Polygon' => {'Radius', 'NumSides'},
      'ai::Star' => {'Radius1', 'Radius2', 'NumPoints'},
      _ => {'Length'},
    },
  };
  if (!parameters.numbers.keys.toSet().containsAll(required)) {
    throw ArgumentError('Native shape parameters require complete center, angle and dimensions/counts.');
  }
}
