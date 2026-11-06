part of 'package:illustratorkit/src/model/ai_native_records.dart';

/// Reads an explicit frame angle independently of the artwork geometry.
double? _nativeFrameRotation(AiNativeContainer? dictionary) {
  final AiNativeEntry? entry = dictionary?['BBAccumRotation'];
  if (entry == null) {
    return null;
  }
  final double? value = switch (entry.type) {
    'String' || 'UnicodeString' => double.tryParse(entry.text() ?? ''),
    'Real' => entry.number,
    _ => null,
  };
  if (value == null || !value.isFinite || entry.items.isEmpty) {
    throw UnsupportedError('Unrecognized native frame-angle metadata.');
  }
  return value;
}

/// Updates or adds the explicitly supplied frame angle using observed precision.
List<AiSourceEdit> _nativeFrameRotationEdits(AiNativeRecords records, AiNativeContainer? dictionary, int end, double? radians) {
  final AiNativeEntry? entry = dictionary?['BBAccumRotation'];
  if (radians == null) {
    if (entry != null) {
      throw ArgumentError('An existing frame angle requires an explicit replacement value.');
    }
    return [];
  }
  final String angle = (radians.abs() < 0.0000005 ? 0.0 : radians).toStringAsFixed(6);
  if (entry != null) {
    final bool string = const {'String', 'UnicodeString'}.contains(entry.type);
    final double previous = _nativeFrameRotation(dictionary)!;
    if (previous == radians || previous == double.parse(angle)) {
      return [];
    }
    return [
      AiSourceEdit(start: entry.items.first.start, end: entry.items.first.end, bytes: latin1.encode(string ? '($angle)' : angle)),
      for (final AiNativeItem fragment in entry.items.skip(1)) AiSourceEdit(start: fragment.start, end: fragment.end, bytes: []),
    ];
  }
  if (dictionary != null) {
    final AiToken closing = records._projection.tokens.singleWhere((token) => token.end == dictionary.end && token.lexeme == ';');
    final bool private = records._projection.isPrivate(closing.start);
    return [AiSourceEdit(start: closing.start, end: closing.start, bytes: latin1.encode('($angle) /String (BBAccumRotation) ,\n${private ? '%_' : ''}'))];
  }
  // Authoring dictionaries are private metadata even after printable artwork.
  return [AiSourceEdit(start: end, end: end, bytes: latin1.encode('\n%_/ArtDictionary :\n%_($angle) /String (BBAccumRotation) ,\n%_;'))];
}
