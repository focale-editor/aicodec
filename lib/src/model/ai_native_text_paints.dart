part of 'ai_native_text.dart';

/// Process color coordinates retained by an ATE SimplePaint record.
enum AiNativeTextColorSpace {
  /// One gray component between zero and one.
  gray,

  /// Red, green and blue components between zero and one.
  rgb,

  /// Cyan, magenta, yellow and black components between zero and one.
  cmyk,

  /// Lightness from zero to 100 and a/b coordinates from -128 to 127.
  lab,
}

/// Explicit process components without implicit profile or color conversion.
final class AiNativeTextProcessColor {
  /// The saved component model, independent of document working space.
  final AiNativeTextColorSpace space;

  /// Immutable components in the order described by [space].
  final List<double> components;

  /// Requires the complete finite component tuple for the selected model.
  AiNativeTextProcessColor({required this.space, required List<double> components}) : components = List.unmodifiable(components) {
    final int count = switch (space) {
      .gray => 1,
      .rgb || .lab => 3,
      .cmyk => 4,
    };
    if (components.length != count ||
        components.indexed.any((entry) {
          final double value = entry.$2;
          final double minimum = space == .lab && entry.$1 != 0 ? -128 : 0;
          final double maximum = space == .lab ? (entry.$1 == 0 ? 100 : 127) : 1;
          return !value.isFinite || value < minimum || value > maximum;
        })) {
      throw ArgumentError('Invalid native text process color components.');
    }
  }

  /// Encodes the qualified fixed-prefix color layout using compact field names.
  PsEngineDictionary _paint() => PsEngineDictionary(
    values: {
      '99': const PsEngineName(value: 'SimplePaint'),
      '0': PsEngineDictionary(
        values: {
          '0': PsEngineNumber(value: space.index),
          '1': PsEngineArray(
            values: [
              PsEngineNumber(value: 1),
              ...components.map((value) => PsEngineNumber(value: value)),
            ],
          ),
        },
      ),
    },
  );
}

/// One source paint retaining unsupported resource links and future fields.
final class AiNativeTextPaint {
  /// Original immutable payload, including unqualified extensions.
  final PsEngineDictionary record;

  /// Keeps the exact feature payload separate from its interpreted process color.
  const AiNativeTextPaint._({required this.record});

  /// Saved paint tag, without inferring a default for an absent descriptor.
  String? get tag => switch (_field(record, '99', 'StreamTag')) {
    null => null,
    PsEngineName(:final String value) => value,
    _ => throw const FormatException('Invalid native text paint tag.'),
  };

  /// Qualified process color, or null for an unsupported descriptor or layout.
  ///
  /// Unknown fields, tags, component models and non-unit leading values remain
  /// available through [record]. Malformed known numeric tuples reject explicitly.
  AiNativeTextProcessColor? get color {
    if (tag != 'SimplePaint' || record.values.keys.any((key) => !const {'99', 'StreamTag', '0', 'Color'}.contains(key))) {
      return null;
    }
    final PsEngineDictionary color = _dictionary(_field(record, '0', 'Color'));
    final int? type = _optionalIndex(_field(color, '0', 'Type'));
    final PsEngineValue? values = _field(color, '1', 'Values');
    if (color.values.keys.any((key) => !const {'0', 'Type', '1', 'Values'}.contains(key)) || type == null || type >= AiNativeTextColorSpace.values.length) {
      return null;
    }
    if (values is! PsEngineArray || values.values.any((value) => value is! PsEngineNumber)) {
      throw const FormatException('Invalid native text color components.');
    }
    final List<double> components = values.values.cast<PsEngineNumber>().map((value) => value.value.toDouble()).toList();
    if (components.isEmpty || components.first != 1) {
      return null;
    }
    try {
      return AiNativeTextProcessColor(space: AiNativeTextColorSpace.values[type], components: components.sublist(1));
    } on ArgumentError {
      throw const FormatException('Invalid native text process color tuple.');
    }
  }
}

/// Exposes a paint payload without flattening its resource or extension fields.
AiNativeTextPaint? _textPaint(PsEngineValue? value) => value == null ? null : AiNativeTextPaint._(record: _dictionary(value));

/// Recognizes only explicit native process-color feature patches.
bool _textPaintFeature(String compact) => const {'53', '54', '79'}.contains(compact);

/// Retains per-level source aliases when replacing a qualified process paint.
PsEngineDictionary _textPaintReplacement(PsEngineValue? previous, PsEngineDictionary next, bool named) {
  final PsEngineDictionary old = previous == null ? PsEngineDictionary(values: {}) : _dictionary(previous);
  final PsEngineDictionary oldColor = previous == null ? PsEngineDictionary(values: {}) : _dictionary(_field(old, '0', 'Color'));
  final PsEngineDictionary color = next['0']! as PsEngineDictionary;
  return PsEngineDictionary(
    values: {
      _featureKey(old, '99', 'StreamTag', named): next['99']!,
      _featureKey(old, '0', 'Color', named): PsEngineDictionary(
        values: {
          _featureKey(oldColor, '0', 'Type', named): color['0']!,
          _featureKey(oldColor, '1', 'Values', named): color['1']!,
        },
      ),
    },
  );
}

/// Copies portable nonnegative dash lengths; an empty array means a solid line.
PsEngineArray _textDashArray(List<double> values) {
  if (values.any((value) => !value.isFinite || value < 0 || value > 9007199254740991) || values.isNotEmpty && values.every((value) => value == 0)) {
    throw ArgumentError('Native text dashes require portable nonnegative lengths and a nonzero cycle.');
  }
  return PsEngineArray(values: values.map((value) => PsEngineNumber(value: value)).toList());
}

/// Reads a saved dash array without synthesizing a solid-stroke default.
List<double>? _textDashes(PsEngineValue? value) {
  if (value == null) {
    return null;
  }
  final List<double> result = _array(value).map((value) => _number(value) ?? (throw const FormatException('Invalid native text dash length.'))).toList();
  try {
    _textDashArray(result);
  } on ArgumentError {
    throw const FormatException('Invalid native text dash array.');
  }
  return List.unmodifiable(result);
}
