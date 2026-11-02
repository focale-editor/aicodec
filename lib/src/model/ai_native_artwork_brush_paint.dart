part of 'package:aicodec/src/model/ai_native_records.dart';

/// Fixed artwork brush parameters referencing a separate native descriptor.
///
/// Source artwork belongs to the brush resource namespace. The host composes
/// the printing representation; this value never expands a brush along a path.
final class AiNativeArtworkBrushPaint {
  /// Artistic or repeated-pattern brush family.
  final AiNativeBrushKind kind;

  /// Exact descriptor identity within the selected plug-in namespace.
  final Uint8List brushNameBytes;

  /// Artwork height multiplier, independent of the stroke width.
  final double scaling;

  /// Gap as a fraction of the natural side-tile length.
  final double spacing;

  /// Native repeat fitting: zero stretches, one adds space.
  final int adjustment;

  /// Supported literal real fields shared by the two artwork brush plug-ins.
  static const Set<String> realFields = {'Scaling', 'Spacing', 'MinScaling', 'MaxScaling', 'StartSegmentLength', 'EndSegmentLength'};

  /// Supported literal integer fields, including the producer expansion hint.
  static const Set<String> integerFields = {'ScaleYDependsOn', 'Colorization', 'UpsideDown', 'Counterclockwise', 'Adjustment', 'Adobe Effect Expand Before Version'};

  /// Explicit stretch and fold flags in the native dictionary.
  static const Set<String> booleanFields = {'Segmented', 'FoldAdjustment', 'Proportional'};

  /// Freezes fixed monochrome artwork parameters and rejects invalid values.
  AiNativeArtworkBrushPaint({required this.kind, required List<int> brushNameBytes, this.scaling = 1, this.spacing = 0, this.adjustment = 0})
    : brushNameBytes = Uint8List.fromList(brushNameBytes).asUnmodifiableView() {
    if (!const {AiNativeBrushKind.art, AiNativeBrushKind.pattern}.contains(kind) ||
        brushNameBytes.isEmpty ||
        brushNameBytes.any((byte) => byte < 0 || byte > 255) ||
        !scaling.isFinite ||
        scaling <= 0 ||
        scaling > 9007199254740991 ||
        !spacing.isFinite ||
        spacing < 0 ||
        spacing > 9007199254740991 ||
        !const {0, 1}.contains(adjustment) ||
        kind == .art && (scaling != 1 || spacing != 0 || adjustment != 0)) {
      throw ArgumentError('Artwork brushes require a literal identity and fixed finite fitting parameters.');
    }
  }

  /// Version-two descriptor with side, outer, inner, start and end artwork names.
  ///
  /// Empty optional slots stay empty. Automatic corner generation is disabled.
  Uint8List descriptorPayload({required List<List<int>> tileNames}) {
    if (tileNames.length != 5 ||
        tileNames.first.isEmpty ||
        tileNames.any((name) => name.any((byte) => byte < 32 || byte > 255 || byte == 47)) ||
        tileNames.any((name) => latin1.decode(name).trim() != latin1.decode(name)) ||
        kind == .art && tileNames.skip(1).any((name) => name.isNotEmpty)) {
      throw ArgumentError('Artwork descriptors require five unambiguous literal tile slots.');
    }
    return Uint8List.fromList(latin1.encode('2 / ${tileNames.map(latin1.decode).join('/ ')}/ 0 0/ 0 1 / ${kind == .art ? 3 : 1} 1 $scaling $spacing $scaling 0 0 0 $scaling $adjustment 0 0 0 0 1'))
        .asUnmodifiableView();
  }

  /// Reads the qualified fixed, tint-colored, nonsegmented parameter profile.
  factory AiNativeArtworkBrushPaint._decode(AiNativeContainer filter, AiNativeBrushKind kind) {
    final AiNativeContainer? parameters = filter['Dict']?.container;
    if (parameters == null || parameters.type != 'Dictionary') {
      throw UnsupportedError('Artwork brushes require an owned parameter dictionary.');
    }
    for (final MapEntry<String, Set<String>> group in {'Real': realFields, 'Int': integerFields, 'Bool': booleanFields}.entries) {
      for (final String key in group.value) {
        if (key == 'Adobe Effect Expand Before Version') {
          continue;
        }
        if (parameters[key]?.type != group.key || parameters[key]?.number == null) {
          throw UnsupportedError('Artwork brushes require complete typed fixed parameters.');
        }
      }
    }
    final double scale = parameters['Scaling']!.number!;
    for (final MapEntry<String, num> field in {
      'MinScaling': scale,
      'MaxScaling': scale,
      'ScaleYDependsOn': 0,
      'Colorization': 1,
      'UpsideDown': 0,
      'Counterclockwise': 0,
      'StartSegmentLength': 0,
      'EndSegmentLength': 0,
      'Segmented': 0,
      'FoldAdjustment': 1,
      'Proportional': 0,
    }.entries) {
      if (parameters[field.key]?.number != field.value) {
        throw UnsupportedError('Artwork brush variation, segmentation or colorization is not qualified.');
      }
    }
    final AiNativeContainer? reference = parameters['Brush']?.container;
    final List<AiNativeItem>? values = reference?['PluginObject']?.items;
    if (reference?.type != 'GObjRef' ||
        reference?.entries.length != 1 ||
        values == null ||
        values.length != 2 ||
        values.any((value) => value is! AiNativeToken || !_artboardPaletteName(value.token)) ||
        latin1.decode(aiStringBytes((values.last as AiNativeToken).token)) != kind.plugin) {
      throw UnsupportedError('Artwork brushes require one literal matching descriptor reference.');
    }
    final double adjustment = parameters['Adjustment']!.number!;
    if (adjustment != adjustment.truncateToDouble()) {
      throw const FormatException('Brush fitting must be an integer.');
    }
    try {
      return AiNativeArtworkBrushPaint(
        kind: kind,
        brushNameBytes: aiStringBytes((values.first as AiNativeToken).token),
        scaling: scale,
        spacing: parameters['Spacing']!.number!,
        adjustment: adjustment.toInt(),
      );
    } on ArgumentError {
      throw const FormatException('Invalid fixed artwork brush parameters.');
    }
  }
}
