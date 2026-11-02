part of 'package:aikit/src/model/ai_native_records.dart';

/// Native effects with a bounded literal parameter and ownership contract.
enum AiNativeEffectKind {
  /// Signed contour offset before painting.
  offset,

  /// Corner rounding before painting.
  roundCorners,

  /// A colored shadow behind the painted input.
  dropShadow,

  /// A colored glow around the painted input.
  outerGlow;

  /// Exact native plug-in name, independent of its localized title.
  String get plugin => switch (this) {
    .offset => 'Adobe Offset Path',
    .roundCorners => 'Adobe Round Corners',
    .dropShadow => 'Adobe Drop Shadow',
    .outerGlow => 'Adobe Outer Glow',
  };

  /// Whether the filter consumes source geometry before the paint stack.
  bool get geometric => this == .offset || this == .roundCorners;
}

/// Explicit native effect values without an effect renderer or geometry engine.
///
/// The host supplies complete printing/PDF replacements for every affected owner.
/// Unknown filter fields and nonliteral color payloads are not qualified.
final class AiNativeEffect {
  /// Effect schema governing the owned dictionary.
  final AiNativeEffectKind kind;

  /// Signed offset or nonnegative corner radius, in native points.
  final double amount;

  /// Native miter, round or bevel join selector for an offset.
  final int join;

  /// Offset miter ratio before bevel fallback.
  final double miterLimit;

  /// Native blur parameter in points; no sampling is performed here.
  final double blur;

  /// Shadow displacement along the native horizontal UI axis.
  final double horizontal;

  /// Shadow displacement along the native downward UI axis.
  final double vertical;

  /// Effect opacity independent of the complete object's blending.
  final double opacity;

  /// Blend mode of the colored effect.
  final AiNativeBlendMode blendMode;

  /// Literal process color for a shadow or glow; absent for geometric filters.
  final AiColor? color;

  /// Validates a complete fixed effect profile without synthesizing source data.
  AiNativeEffect({
    required this.kind,
    this.amount = 0,
    this.join = 0,
    this.miterLimit = 4,
    this.blur = 0,
    this.horizontal = 0,
    this.vertical = 0,
    this.opacity = 1,
    this.blendMode = .normal,
    this.color,
  }) {
    if (![amount, miterLimit, blur, horizontal, vertical, opacity].every((value) => value.isFinite && value.abs() <= 9007199254740991) ||
        join < 0 ||
        join > 2 ||
        miterLimit < 1 ||
        blur < 0 ||
        opacity < 0 ||
        opacity > 1 ||
        kind == .roundCorners && amount < 0 ||
        kind.geometric == (color != null) ||
        kind.geometric && (blur != 0 || horizontal != 0 || vertical != 0 || opacity != 1 || blendMode != .normal) ||
        !kind.geometric && (amount != 0 || join != 0 || miterLimit != 4) ||
        kind != .offset && (join != 0 || miterLimit != 4) ||
        kind == .outerGlow && (horizontal != 0 || vertical != 0)) {
      throw ArgumentError('Native effects require finite parameters belonging to the selected schema.');
    }
  }

  /// Literal scalar fields serialized in the owned effect dictionary.
  Map<String, double> get realParameters => switch (kind) {
    .offset => {'ofst': amount, 'mlim': miterLimit},
    .roundCorners => {'radius': amount},
    .dropShadow => {'horz': horizontal, 'vert': vertical, 'blur': blur, 'opac': opacity, 'dark': 50},
    .outerGlow => {'blur': blur, 'opac': opacity},
  };

  /// Literal integral fields, including the observed CC expansion hint.
  Map<String, int> get integerParameters => switch (kind) {
    .offset => {'jntp': join},
    .roundCorners => {},
    .dropShadow => {'blnd': blendMode.index, 'csrc': 1, 'Adobe Effect Expand Before Version': 16},
    .outerGlow => {'blnd': blendMode.index, 'Adobe Effect Expand Before Version': 16},
  };

  /// Fixed flags retaining the painted input and the current blur implementation.
  Map<String, bool> get booleanParameters => kind.geometric ? {} : {'usePSLBlur': true, if (kind == .dropShadow) 'pair': true};

  /// Decodes one complete literal descriptor without guessing missing parameters.
  static AiNativeEffect _decode(AiNativeRecords records, AiNativeContainer filter) {
    final String? plugin = filter['Filter']?.items.firstOrNull is AiNativeToken ? latin1.decode(aiStringBytes((filter['Filter']!.items.first as AiNativeToken).token)) : null;
    final AiNativeEffectKind? kind = AiNativeEffectKind.values.where((kind) => kind.plugin == plugin).singleOrNull;
    final AiNativeContainer? dictionary = filter['Dict']?.container;
    if (kind == null || dictionary == null || dictionary.type != 'Dictionary') {
      throw UnsupportedError('Native effects require a known owned literal dictionary.');
    }
    final Map<String, Set<String>> fields = _artboardStyleParameters[kind.plugin]!;
    _referenceFields(
      dictionary,
      fields,
      notRecorded: true,
      nested: {
        if (!kind.geometric)
          'sclr': (entry) {
            final AiNativeContainer paint = _referenceRecord(entry, 'FillStyle');
            _artboardStyleFields(paint, {'Def'});
          },
      },
    );

    /// Requires the actual scalar and its exact native type.
    double number(String key, String type) {
      if (dictionary[key]?.type != type || dictionary[key]?.number == null) {
        throw UnsupportedError('Native effects require explicit typed $key parameters.');
      }
      return dictionary[key]!.number!;
    }

    /// Requires exact fixed flags instead of silently interpreting other modes.
    void fixed(String key, String type, double value) {
      if (number(key, type) != value) {
        throw UnsupportedError('The native $key effect mode is not qualified.');
      }
    }

    if (kind == .offset && number('jntp', 'Int') != number('jntp', 'Int').truncateToDouble()) {
      throw const FormatException('Offset joins require an integral selector.');
    }
    AiColor? color;
    AiNativeBlendMode blend = .normal;
    if (!kind.geometric) {
      fixed('usePSLBlur', 'Bool', 1);
      if (dictionary['Adobe Effect Expand Before Version'] != null) {
        fixed('Adobe Effect Expand Before Version', 'Int', 16);
      }
      if (kind == .dropShadow) {
        fixed('pair', 'Bool', 1);
        fixed('csrc', 'Int', 1);
        fixed('dark', 'Real', 50);
      }
      final double index = number('blnd', 'Int');
      if (index != index.truncateToDouble() || index < 0 || index >= AiNativeBlendMode.values.length) {
        throw UnsupportedError('Unknown native effect blend mode.');
      }
      blend = AiNativeBlendMode.values[index.toInt()];
      final AiNativeContainer? paint = dictionary['sclr']?.container;
      if (paint == null) {
        throw UnsupportedError('Colored effects require an explicit owned process paint.');
      }
      final AiNativePaintStyle parsed = AiNativePaintStyle.decode(records: records, record: paint);
      final List<AiNativePaintAssignment> colors = parsed.assignments.where((value) => value.parameter == .fillColor).toList();
      if (parsed.assignments.where((value) => value.parameter == .transparency).length != 1 ||
          parsed.assignments.where((value) => value.parameter == .fillOverprint).length != 1 ||
          colors.length != 1 ||
          colors.single.colors.length != 1 ||
          parsed.instructions.any((command) => !const {'g', 'Xa', 'k', 'O', 'Xy', 'XR', 'Xd', 'J', 'j', 'w', 'M', 'd'}.contains(command.operator)) ||
          parsed.assignments.any(
            (value) => value.parameter == .transparency && !_sameEffectNumbers(value.numbers, [0, 1, 0, 0, 0]) || value.parameter == .fillOverprint && !_sameEffectNumbers(value.numbers, [0]),
          )) {
        throw UnsupportedError('Effect colors require one opaque non-overprinting process paint.');
      }
      color = colors.single.colors.single;
    }
    try {
      return AiNativeEffect(
        kind: kind,
        amount: kind.geometric ? number(kind == .offset ? 'ofst' : 'radius', 'Real') : 0,
        join: kind == .offset ? number('jntp', 'Int').toInt() : 0,
        miterLimit: kind == .offset ? number('mlim', 'Real') : 4,
        blur: kind.geometric ? 0 : number('blur', 'Real'),
        opacity: kind.geometric ? 1 : number('opac', 'Real'),
        horizontal: kind == .dropShadow ? number('horz', 'Real') : 0,
        vertical: kind == .dropShadow ? number('vert', 'Real') : 0,
        blendMode: blend,
        color: color,
      );
    } on ArgumentError {
      throw const FormatException('Invalid native effect parameters.');
    }
  }
}

/// Compares explicit scalar state without supplying defaults for absent values.
bool _sameEffectNumbers(List<double>? first, List<double> second) => first != null && first.length == second.length && first.indexed.every((item) => item.$2 == second[item.$1]);
