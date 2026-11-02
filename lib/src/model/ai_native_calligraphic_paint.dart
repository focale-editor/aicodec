part of 'package:aicodec/src/model/ai_native_records.dart';

/// Fixed elliptical nib parameters and a literal calligraphic brush reference.
///
/// Native diameter is measured in points, roundness in percent and angle in
/// degrees. Variable or device-dependent nibs retain their source descriptors
/// but need a separate authoring contract. This value never generates outlines.
final class AiNativeCalligraphicPaint {
  /// Exact referenced name in the calligraphic descriptor namespace.
  final Uint8List brushNameBytes;

  /// Major nib diameter before the stroke's own width multiplier.
  final double diameter;

  /// Minor/major diameter ratio expressed as a native percentage.
  final double roundness;

  /// Native nib angle in degrees relative to the horizontal axis.
  final double angle;

  /// Freezes one fixed nib and rejects invalid or nonportable native values.
  AiNativeCalligraphicPaint({required List<int> brushNameBytes, required this.diameter, required this.roundness, required this.angle})
    : brushNameBytes = Uint8List.fromList(brushNameBytes).asUnmodifiableView() {
    if (brushNameBytes.isEmpty ||
        brushNameBytes.any((byte) => byte < 0 || byte > 255) ||
        ![diameter, roundness, angle].every((value) => value.isFinite && value.abs() <= 9007199254740991) ||
        diameter <= 0 ||
        roundness < 0 ||
        roundness > 100) {
      throw ArgumentError('Calligraphic paints require a byte name and valid finite nib dimensions.');
    }
  }

  /// Version-one descriptor payload with equal limits and fixed input selectors.
  Uint8List get descriptorPayload => Uint8List.fromList(latin1.encode('1 $diameter $diameter $roundness $roundness $angle $angle 0 0 0 0')).asUnmodifiableView();

  /// Reads a complete fixed nib dictionary without inventing absent parameters.
  factory AiNativeCalligraphicPaint._decode(AiNativeContainer filter) {
    final AiNativeContainer? parameters = filter['Dict']?.container;
    if (parameters == null || parameters.type != 'Dictionary') {
      throw UnsupportedError('Calligraphic paints require an owned parameter dictionary.');
    }
    for (final String key in ['AngleVariation', 'DiameterVariation', 'RoundnessVariation', 'AngleDependsOn', 'DiameterDependsOn', 'RoundnessDependsOn', 'AngleRelativeTo']) {
      final AiNativeEntry? field = parameters[key];
      if (field?.type != (key.endsWith('Variation') ? 'Real' : 'Int') || field?.number != 0) {
        throw UnsupportedError('Editable calligraphic paints require fixed absolute nib parameters.');
      }
    }
    for (final String key in ['Angle', 'Diameter', 'Roundness']) {
      if (parameters[key]?.type != 'Real' || parameters[key]?.number == null) {
        throw UnsupportedError('Calligraphic paints require explicit numeric nib dimensions.');
      }
    }
    final AiNativeContainer? reference = parameters['Brush']?.container;
    final List<AiNativeItem>? values = reference?['PluginObject']?.items;
    if (reference?.type != 'GObjRef' ||
        reference?.entries.length != 1 ||
        values == null ||
        values.length != 2 ||
        values.any((value) => value is! AiNativeToken || !_artboardPaletteName(value.token)) ||
        latin1.decode(aiStringBytes((values.last as AiNativeToken).token)) != AiNativeBrushKind.calligraphic.plugin) {
      throw UnsupportedError('Calligraphic paints require one literal brush reference.');
    }
    try {
      return AiNativeCalligraphicPaint(
        brushNameBytes: aiStringBytes((values.first as AiNativeToken).token),
        diameter: parameters['Diameter']!.number!,
        roundness: parameters['Roundness']!.number!,
        angle: parameters['Angle']!.number!,
      );
    } on ArgumentError {
      throw const FormatException('Native calligraphic paints contain invalid nib dimensions.');
    }
  }
}
