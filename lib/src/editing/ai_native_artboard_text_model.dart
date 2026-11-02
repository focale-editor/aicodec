part of 'package:aicodec/src/model/ai_native_records.dart';

/// Keeps frame and story references in one independent text-engine namespace.
final class _ArtboardTextSnapshot {
  /// Known point, area or path categories in frame resource order.
  final List<int> frames;

  /// Each story's ordered global frame-resource indices.
  final List<List<int>> stories;

  /// Freezes resolved references without rewriting the retained engine payload.
  _ArtboardTextSnapshot({required List<int> frames, required List<List<int>> stories}) : frames = List.unmodifiable(frames), stories = List.unmodifiable(stories.map(List<int>.unmodifiable));
}

/// Requires a portable nonnegative text-local resource or enumeration index.
int _artboardTextIndex(PsEngineValue? value) {
  if (value is! PsEngineNumber || !value.value.isFinite || value.value < 0 || value.value > 9007199254740991 || value.value != value.value.truncate()) {
    throw const FormatException('Invalid text-local index.');
  }
  return value.value.toInt();
}

/// Checks optional numeric geometry without applying any canvas transform.
void _artboardTextCoordinates(PsEngineValue? value, {int? length}) {
  if (value == null) {
    return;
  }
  if (value is! PsEngineArray ||
      (length == null ? value.values.isEmpty || value.values.length.isOdd : value.values.length != length) ||
      value.values.any((value) => value is! PsEngineNumber || !value.value.isFinite || value.value.abs() > 9007199254740991)) {
    throw const FormatException('Invalid retained text coordinates.');
  }
}

/// Qualifies canvas-based point, area and path frames independently of artboards.
int _artboardTextFrame(PsEngineValue value) {
  final PsEngineDictionary frame = _artboardTextDictionary(value, {'0', '1', '2', '97'});
  if (frame['97'] != null && frame['97'] is! PsEngineString || frame['0'] == null && frame['1'] == null) {
    throw UnsupportedError('Retained text frames require explicit canvas geometry and literal identities.');
  }
  _artboardTextCoordinates(frame['0'], length: 2);
  if (frame['1'] case final PsEngineValue path) {
    final PsEngineDictionary curve = _artboardTextDictionary(path, {'0'});
    if (curve['0'] == null) {
      throw const FormatException('A retained text curve has no control points.');
    }
    _artboardTextCoordinates(curve['0']);
  }
  final PsEngineDictionary settings = frame['2'] == null ? PsEngineDictionary(values: {}) : _artboardTextDictionary(frame['2'], {'0', '1', '2', '3', '4', '5', '6', '7', '8', '9', '10', '11', '13'});
  final int kind = settings['0'] == null ? 0 : _artboardTextIndex(settings['0']);
  if (kind > 2 || kind != 0 && frame['1'] == null) {
    throw UnsupportedError('Retained area/path text requires a known frame type and canvas curve.');
  }
  for (final MapEntry<String, PsEngineValue> entry in settings.values.entries) {
    switch (entry.key) {
      case '2':
        _artboardTextCoordinates(entry.value, length: 6);
      case '6':
        _artboardTextCoordinates(entry.value, length: 2);
      case '5':
        if (entry.value is! PsEngineBoolean) {
          throw const FormatException('Invalid text frame row-order flag.');
        }
      case '10' || '11':
        final PsEngineDictionary local = _artboardTextDictionary(entry.value, entry.key == '10' ? {'0', '1'} : {'0', '1', '2', '4', '6', '7', '18'});
        for (final MapEntry<String, PsEngineValue> field in local.values.entries) {
          if (entry.key == '11' && const {'0', '6', '7'}.contains(field.key)) {
            if (field.value is! PsEngineBoolean) {
              throw const FormatException('Invalid text-on-path flip flag.');
            }
          } else if (field.value is! PsEngineNumber) {
            throw const FormatException('Invalid text-local frame setting.');
          }
        }
      default:
        if (entry.value is! PsEngineNumber) {
          throw const FormatException('Invalid text frame setting.');
        }
    }
  }
  return kind;
}

/// Resolves one retained story's frame list without recomposing its text or runs.
List<int> _artboardTextStory(PsEngineValue value, int frameCount) {
  final PsEngineDictionary story = _artboardTextDictionary(value, {'0', '1'});
  final PsEngineDictionary model = _artboardTextDictionary(story['0'], {'0', '5', '6', '10', 'KernRun', 'AlternateGlyphRun', 'HyperlinkRun'});
  final PsEngineValue? text = model['0'];
  if (text is! PsEngineString || text.bytes.length < 2 || !(text.bytes[0] == 254 && text.bytes[1] == 255 || text.bytes[0] == 255 && text.bytes[1] == 254) || !text.text().endsWith('\r')) {
    throw const FormatException('Retained text requires a UTF-16 story and its terminal paragraph mark.');
  }
  if (model.values.entries.any((entry) => entry.key != '0' && entry.value is! PsEngineDictionary)) {
    throw const FormatException('Retained text features require local dictionaries.');
  }
  final PsEngineDictionary view = _artboardTextDictionary(story['1'], {'0', '1', '2'});
  final List<int> frames = [
    for (final PsEngineValue reference in _artboardTextArray(view['0'])) _artboardTextIndex(_artboardTextDictionary(reference, {'0'})['0']),
  ];
  if (frames.any((index) => index >= frameCount) || frames.toSet().length != frames.length) {
    throw const FormatException('Retained text has missing or repeated story frame resources.');
  }
  if (view['1'] != null && view['1'] is! PsEngineDictionary) {
    throw const FormatException('Invalid retained text composition cache.');
  }
  final Set<int> ownedFrames = frames.toSet();
  for (final PsEngineValue strike in _artboardTextArray(view['2'])) {
    _artboardTextStrike(strike, ownedFrames);
  }
  return frames;
}

/// Qualifies cached frame references while retaining text-local glyph data exactly.
void _artboardTextStrike(PsEngineValue value, Set<int> frames) {
  if (value is! PsEngineDictionary || value['99'] is! PsEngineName) {
    throw UnsupportedError('Retained text layout requires an owned tagged node.');
  }
  final String tag = (value['99']! as PsEngineName).value;
  final Set<String> fields = switch (tag) {
    'PC' || 'R' => {'0', '1', '5', '6'},
    'F' => {'0', '1', '5', '6', '10'},
    'L' => {'0', '1', '6', '10', '14', '15'},
    'S' => {'0', '1', '6', '15', '17', '20'},
    'G' => {'0', '1', '5', '8', '9', '10', '11', '12', '13', '20', '24'},
    _ => throw UnsupportedError('Artboard text isolation has no dependency contract for layout tag $tag.'),
  };
  _artboardTextDictionary(value, {'99', ...fields});
  if (tag == 'F' && !frames.contains(_artboardTextIndex(value['10']))) {
    throw const FormatException('Cached text layout references a frame outside its story.');
  }
  for (final PsEngineValue child in _artboardTextArray(value['6'])) {
    _artboardTextStrike(child, frames);
  }
}
