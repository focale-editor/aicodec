part of 'ai_native_text.dart';

/// Character and paragraph editing without flattening inherited native styles.
extension AiNativeTextFeatureEditing on AiNativeTextDocument {
  /// Changes character overrides in a UTF-16 range, including paragraph marks.
  ///
  /// Runs are split at the selection boundaries. Other features, parent styles
  /// and resource identities remain unchanged. Modified inline styles receive
  /// fresh identifiers when the source style has one, avoiding one identity for
  /// two differing feature sets. Removing a local override exposes
  /// its inherited value. Point-size edits update both native size fields and
  /// reject active non-point reference modes that require font-metric conversion.
  /// The affected story's saved layout is removed; recomposition and synchronized
  /// printable/PDF output are required exactly as for [replaceText].
  AiNativeTextDocument setCharacterFeatures({required AiNativeTextStory story, required int start, required int end, required AiNativeCharacterChanges changes}) {
    _featureRange(story, start, end);
    final AiNativeTextFont? font = changes.font;
    if (font != null && !fonts.contains(font)) {
      throw ArgumentError('Invalid or foreign Illustrator font resource.');
    }
    if (font != null || changes.inherit.contains(AiNativeCharacterFeature.font)) {
      final PsEngineDictionary model = _dictionary(_field(story.record, '0', 'Model'));
      if (model['AlternateGlyphRun'] case final PsEngineValue table) {
        _emptyAuxiliaryRuns(_dictionary(table), story.modelText);
      }
    }
    if (start == end) {
      return this;
    }
    final Map<(String, String), PsEngineValue?> patch = {
      for (final AiNativeCharacterFeature feature in changes.inherit) (feature._compact, feature._named): null,
      for (final MapEntry<AiNativeCharacterFeature, PsEngineValue> entry in changes._values.entries) (entry.key._compact, entry.key._named): entry.value,
      if (font != null) ('0', 'Font'): PsEngineNumber(value: font.index),
    };
    if (changes._values[AiNativeCharacterFeature.fontSize] case final PsEngineValue size) {
      for (final AiNativeStyledTextRange range in styledRanges(story: story)) {
        if (range.start < end && range.end > start) {
          final int? reference = _optionalIndex(range.characterStyle.value(compactKey: '90', namedKey: 'FontSizeRefType'));
          if (reference != null && reference != 0) {
            throw UnsupportedError('Point-size editing requires conversion from the native font-size reference mode.');
          }
        }
      }
      patch[('89', 'RefFontSize')] = size;
    } else if (changes.inherit.contains(AiNativeCharacterFeature.fontSize)) {
      patch[('89', 'RefFontSize')] = null;
      patch[('90', 'FontSizeRefType')] = null;
    }
    return _setTextFeatures(story: story, start: start, end: end, kind: .character, patch: patch);
  }

  /// Changes the complete paragraphs touched by a UTF-16 selection.
  ///
  /// The end is exclusive; a selection ending at a paragraph's first character
  /// does not include that paragraph. An empty selection edits the paragraph at
  /// the caret, including an empty paragraph. Each touched paragraph receives its
  /// own native runs, split at CR and U+0003 as Illustrator stores them. Forced
  /// breaks remain inside the same logical paragraph for selection purposes.
  /// Direction and composer remain independent. Other stories,
  /// unknown style features and character runs are retained; this story's caches
  /// are invalidated for host recomposition and printable/PDF synchronization.
  AiNativeTextDocument setParagraphFeatures({required AiNativeTextStory story, required int start, required int end, required AiNativeParagraphChanges changes}) {
    _featureRange(story, start, end);
    final int paragraphStart = start == 0 ? 0 : story.modelText.lastIndexOf('\r', start - 1) + 1;
    final int paragraphEnd = story.modelText.indexOf('\r', end == start ? start : end - 1) + 1;
    return _setTextFeatures(
      story: story,
      start: paragraphStart,
      end: paragraphEnd,
      kind: .paragraph,
      patch: {
        for (final AiNativeParagraphFeature feature in changes.inherit) (feature._compact, feature._named): null,
        for (final MapEntry<AiNativeParagraphFeature, PsEngineValue> entry in changes._values.entries) (entry.key._compact, entry.key._named): entry.value,
      },
    );
  }

  /// Validates source ownership and UTF-16 selection boundaries before edits.
  void _featureRange(AiNativeTextStory story, int start, int end) {
    _checkPosition(story, start);
    if (end < start || end > story.modelText.length) {
      throw RangeError.range(end, start, story.modelText.length, 'end');
    }
    _textBoundary(story.modelText, start);
    _textBoundary(story.modelText, end);
  }

  /// Splits only selected runs and replaces their local feature dictionary.
  AiNativeTextDocument _setTextFeatures({
    required AiNativeTextStory story,
    required int start,
    required int end,
    required AiNativeTextStyleKind kind,
    required Map<(String, String), PsEngineValue?> patch,
  }) {
    if (patch.isEmpty) {
      return this;
    }
    final PsEngineDictionary model = _dictionary(_field(story.record, '0', 'Model'));
    final PsEngineDictionary view = _dictionary(_field(story.record, '1', 'View'));
    _knownTextKeys(model, {'0', 'Text', '5', 'ParagraphRun', '6', 'StyleRun', '10', 'StorySheet', 'KernRun', 'AlternateGlyphRun', 'HyperlinkRun'}, 'model');
    _knownTextKeys(view, {'0', 'Frames', '1', 'RenderedData', '2', 'Strikes'}, 'view');
    final bool named = model.values.containsKey('Text');
    final String compact = kind == .character ? '6' : '5';
    final String name = kind == .character ? 'StyleRun' : 'ParagraphRun';
    final PsEngineDictionary? table = _optionalDictionary(_field(model, compact, name));
    final List<AiNativeTextRun> source = kind == .character ? story.characterRuns : story.paragraphRuns;
    final List<_TextEditRun> runs = source.isEmpty
        ? [_TextEditRun(record: _inheritedTextRun(kind, named, story.modelText.length), length: story.modelText.length)]
        : [for (final AiNativeTextRun run in source) _TextEditRun(record: run.record, length: run.length)];
    final _TextEditBudget budget = _TextEditBudget(remaining: engine.limits.maxNodes);
    final _TextIdentifiers identifiers = _TextIdentifiers(engine: engine);
    final List<_TextEditRun> output = [];
    int offset = 0;
    bool changed = false;
    for (final _TextEditRun run in runs) {
      final int limit = offset + run.length;
      if (kind == .paragraph && limit < story.modelText.length && !_paragraphRunBreak(story.modelText.codeUnitAt(limit - 1))) {
        throw const FormatException('Illustrator paragraph style boundary lies inside a paragraph.');
      }
      if (limit <= start || offset >= end) {
        _appendTextRun(output, run.record, run.length, budget);
      } else {
        final int first = offset < start ? start : offset;
        final int last = limit > end ? end : limit;
        _appendTextRun(output, run.record, first - offset, budget);
        final PsEngineDictionary edited = _patchTextRun(run.record, kind, named, patch, identifiers);
        changed |= !identical(edited, run.record);
        if (kind == .paragraph) {
          int paragraph = first;
          while (paragraph < last) {
            final int paragraphEnd = _paragraphRunEnd(story.modelText, paragraph);
            budget.take();
            output.add(_TextEditRun(record: edited, length: paragraphEnd - paragraph));
            paragraph = paragraphEnd;
          }
        } else {
          _appendTextRun(output, edited, last - first, budget);
        }
        _appendTextRun(output, run.record, limit - last, budget);
      }
      offset = limit;
    }
    if (!changed) {
      return this;
    }
    final PsEngineDictionary rewritten = _editedTextTable(table ?? PsEngineDictionary(values: {named ? 'RunArray' : '0': PsEngineArray(values: [])}), output);
    final PsEngineDocument edited = engine.replaceValues(
      replacements: {
        if (table != null) table: rewritten else model: PsEngineDictionary(values: {...model.values, named ? name : compact: rewritten}),
        view: _textViewWithoutCaches(view),
      },
    );
    return _withEngine(edited);
  }
}

/// Creates an inline selection that retains native normal-style inheritance.
PsEngineDictionary _inheritedTextRun(AiNativeTextStyleKind kind, bool named, int length) => PsEngineDictionary(
  values: {
    named ? 'RunData' : '0': PsEngineDictionary(values: {named ? (kind == .character ? 'StyleSheet' : 'ParagraphSheet') : '0': PsEngineDictionary(values: {})}),
    named ? 'Length' : '1': PsEngineNumber(value: length),
  },
);

/// Chooses an existing alias or the surrounding model's spelling for new fields.
String _featureKey(PsEngineDictionary record, String compact, String name, bool named) {
  _field(record, compact, name);
  return record.values.containsKey(compact)
      ? compact
      : record.values.containsKey(name) || named
      ? name
      : compact;
}

/// Patches only local features, wrapping resource selections in a parent link.
PsEngineDictionary _patchTextRun(PsEngineDictionary record, AiNativeTextStyleKind kind, bool named, Map<(String, String), PsEngineValue?> patch, _TextIdentifiers identifiers) {
  final PsEngineDictionary data = _dictionary(_field(record, '0', 'RunData'));
  final String selectionName = kind == .character ? 'StyleSheet' : 'ParagraphSheet';
  final PsEngineValue selection = _field(data, '0', selectionName)!;
  final String parent = kind == .character ? '5' : '6';
  final String featuresKey = kind == .character ? '6' : '5';
  final PsEngineDictionary style = selection is PsEngineDictionary ? selection : PsEngineDictionary(values: {named ? 'Parent' : parent: selection});
  final PsEngineDictionary features = _optionalDictionary(_field(style, featuresKey, 'Features')) ?? PsEngineDictionary(values: {});
  final Map<String, PsEngineValue> values = {...features.values};
  bool changed = false;
  for (final MapEntry<(String, String), PsEngineValue?> entry in patch.entries) {
    final (String compact, String name) = entry.key;
    final String key = _featureKey(features, compact, name, named);
    final PsEngineValue? previous = features[key];
    final PsEngineValue? next = entry.value;
    if (next == null) {
      changed |= values.remove(key) != null;
    } else if (!_sameTextScalar(previous, next)) {
      values[key] = next;
      changed = true;
    }
  }
  if (!changed) {
    return record;
  }
  return PsEngineDictionary(
    values: {
      ...record.values,
      _featureKey(record, '0', 'RunData', named): PsEngineDictionary(
        values: {
          ...data.values,
          _featureKey(data, '0', selectionName, named): PsEngineDictionary(
            values: {
              ...style.values,
              if (_field(style, '97', 'UUID') != null) _featureKey(style, '97', 'UUID', named): PsEngineString.fromText(text: identifiers.next()),
              _featureKey(style, featuresKey, 'Features', named): PsEngineDictionary(values: values),
            },
          ),
        },
      ),
    },
  );
}

/// Allocates fresh native text identities without colliding with source UUIDs.
final class _TextIdentifiers {
  /// Source inspected only if an edit actually needs a new identifier.
  final PsEngineDocument _engine;

  /// Identifiers already present in the source or allocated during this edit.
  late final Set<String> _used = {
    for (final PsEngineValue value in _engine.values)
      if (value is PsEngineDictionary)
        if ((value['97'] ?? value['UUID']) case final PsEngineString identifier) identifier.text().toLowerCase(),
  };

  /// Portable pseudo-random bytes for format identities, never security tokens.
  late final Random _random = Random();

  /// Reserves known identifiers throughout the bounded engine snapshot.
  _TextIdentifiers({required this._engine});

  /// Authors a UUID without reusing an existing native resource's identity.
  String next() {
    for (int attempt = 0; attempt < 16; attempt++) {
      final List<int> bytes = List.generate(16, (_) => _random.nextInt(256));
      bytes[6] = (bytes[6] & 15) | 64;
      bytes[8] = (bytes[8] & 63) | 128;
      final String hex = bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
      final String identifier = '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
      if (_used.add(identifier)) {
        return identifier;
      }
    }
    throw StateError('Could not allocate a distinct Illustrator text identifier.');
  }
}

/// Compares supported scalar feature values without re-encoding source lexemes.
bool _sameTextScalar(PsEngineValue? first, PsEngineValue second) => switch ((first, second)) {
  (PsEngineNumber(value: final first), PsEngineNumber(value: final second)) => first == second,
  (PsEngineBoolean(value: final first), PsEngineBoolean(value: final second)) => first == second,
  _ => false,
};

/// Retains frame references and removes caches tied to the prior composition.
PsEngineDictionary _textViewWithoutCaches(PsEngineDictionary view) => PsEngineDictionary(
  values: {
    for (final MapEntry<String, PsEngineValue> entry in view.values.entries)
      if (entry.key == '0' || entry.key == 'Frames') entry.key: entry.value,
  },
);
