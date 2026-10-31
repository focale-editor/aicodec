part of 'ai_native_text.dart';

/// Source-backed content editing that explicitly requires new composition.
extension AiNativeTextEditing on AiNativeTextDocument {
  /// Replaces a UTF-16 range and invalidates the selected story's saved layout.
  ///
  /// Offsets address [AiNativeTextStory.text], excluding its mandatory final
  /// paragraph mark. Inserted characters inherit the character style at [start].
  /// Each resulting paragraph inherits the style of its first character. Use
  /// carriage returns for paragraphs and U+0003 for forced line breaks; line
  /// feeds and malformed UTF-16 are rejected rather than normalized silently.
  ///
  /// Frames, resources, unknown style features and other stories are retained.
  /// Glyph strikes and rendered-data caches are removed, so the host must
  /// recompose this story and regenerate its printable/PDF appearance before
  /// presenting or saving a synchronized document. This does not shape text.
  /// Unknown model/view fields and nonempty auxiliary runs reject the edit.
  AiNativeTextDocument replaceText({required AiNativeTextStory story, required int start, required int end, required String text}) {
    if (!stories.contains(story)) {
      throw ArgumentError('Invalid or foreign Illustrator text story.');
    }
    if (start < 0 || end < start || end >= story.modelText.length) {
      throw RangeError('Text edit must leave the final Illustrator paragraph mark intact.');
    }
    _textBoundary(story.modelText, start);
    _textBoundary(story.modelText, end);
    _editableText(text);
    final int length = story.modelText.length - (end - start) + text.length;
    if (length > (engine.limits.maxStringBytes - 2) ~/ 2 || length > (engine.limits.maxBytes - 2) ~/ 2) {
      throw const FormatException('Edited Illustrator text exceeds the engine byte limit.');
    }
    if (story.modelText.substring(start, end) == text) {
      return this;
    }
    final PsEngineDictionary model = _dictionary(_field(story.record, '0', 'Model'));
    final PsEngineDictionary view = _dictionary(_field(story.record, '1', 'View'));
    _knownTextKeys(model, {'0', 'Text', '5', 'ParagraphRun', '6', 'StyleRun', '10', 'StorySheet', 'KernRun', 'AlternateGlyphRun', 'HyperlinkRun'}, 'model');
    _knownTextKeys(view, {'0', 'Frames', '1', 'RenderedData', '2', 'Strikes'}, 'view');
    final String content = story.modelText.replaceRange(start, end, text);
    final _TextEditBudget budget = _TextEditBudget(remaining: engine.limits.maxNodes);
    final Map<String, PsEngineValue> changed = {...model.values, _textKey(model, '0', 'Text'): PsEngineString.fromText(text: content)};
    if (story.paragraphRuns.isEmpty && content.indexOf('\r') != content.length - 1) {
      final int? normal = normalParagraphStyleIndex;
      if (normal == null || normal >= paragraphStyles.length) {
        throw UnsupportedError('Multiline Illustrator text requires a resolvable normal paragraph style.');
      }
      final bool named = model.values.containsKey('Text');
      final PsEngineDictionary record = PsEngineDictionary(
        values: {
          named ? 'RunData' : '0': PsEngineDictionary(values: {named ? 'ParagraphSheet' : '0': PsEngineNumber(value: normal)}),
          named ? 'Length' : '1': PsEngineNumber(value: content.length),
        },
      );
      changed[named ? 'ParagraphRun' : '5'] = _editedTextTable(
        PsEngineDictionary(values: {named ? 'RunArray' : '0': PsEngineArray(values: [])}),
        _paragraphTextRuns([_TextEditRun(record: record, length: content.length)], content, budget),
      );
    }
    for (final (String compact, String named, List<AiNativeTextRun> runs) in [('6', 'StyleRun', story.characterRuns), ('5', 'ParagraphRun', story.paragraphRuns)]) {
      if (runs.isEmpty) {
        continue;
      }
      final PsEngineDictionary table = _dictionary(_field(model, compact, named));
      final List<_TextEditRun> pieces = _spliceTextRuns(
        runs: [for (final AiNativeTextRun run in runs) _TextEditRun(record: run.record, length: run.length)],
        start: start,
        end: end,
        inserted: text.length,
        budget: budget,
      );
      changed[_textKey(model, compact, named)] = _editedTextTable(table, named == 'ParagraphRun' ? _paragraphTextRuns(pieces, content, budget) : pieces);
    }
    for (final String name in ['KernRun', 'AlternateGlyphRun', 'HyperlinkRun']) {
      final PsEngineValue? value = model[name];
      if (value == null) {
        continue;
      }
      final PsEngineDictionary table = _dictionary(value);
      final List<_TextEditRun> runs = _emptyAuxiliaryRuns(table, story.modelText);
      changed[name] = _editedTextTable(table, _spliceTextRuns(runs: runs, start: start, end: end, inserted: text.length, budget: budget));
    }
    final PsEngineDocument edited = engine.replaceValues(
      replacements: {
        model: PsEngineDictionary(values: changed),
        view: _textViewWithoutCaches(view),
      },
    );
    return _withEngine(edited);
  }
}

/// Bounds newly retained run fragments before allocating engine dictionaries.
final class _TextEditBudget {
  /// Remaining lower bound on writable run nodes.
  int remaining;

  /// Shares the document's node budget across all edited run tables.
  _TextEditBudget({required this.remaining});

  /// Accounts for a run dictionary and its mandatory length value.
  void take() {
    if (remaining < 2) {
      throw const FormatException('Edited Illustrator text exceeds the engine node limit.');
    }
    remaining -= 2;
  }
}

/// One retained run dictionary with an edited UTF-16 length.
final class _TextEditRun {
  /// Original style and any unknown run metadata.
  final PsEngineDictionary record;

  /// Number of UTF-16 code units in the edited story.
  final int length;

  /// Creates a run fragment without copying its source metadata.
  const _TextEditRun({required this.record, required this.length});
}

/// Rejects an edit boundary inside a valid surrogate pair.
void _textBoundary(String text, int offset) {
  if (offset > 0 && offset < text.length && text.codeUnitAt(offset - 1) >= 0xd800 && text.codeUnitAt(offset - 1) <= 0xdbff && text.codeUnitAt(offset) >= 0xdc00 && text.codeUnitAt(offset) <= 0xdfff) {
    throw ArgumentError('Illustrator text edit splits a UTF-16 surrogate pair.');
  }
}

/// Validates new text without normalizing paragraph or forced-break semantics.
void _editableText(String text) {
  for (int index = 0; index < text.length; index++) {
    final int unit = text.codeUnitAt(index);
    if (unit == 10) {
      throw ArgumentError('Use carriage returns for Illustrator paragraphs or U+0003 for forced line breaks.');
    }
    if (unit >= 0xd800 && unit <= 0xdbff) {
      if (++index >= text.length || text.codeUnitAt(index) < 0xdc00 || text.codeUnitAt(index) > 0xdfff) {
        throw ArgumentError('Illustrator text contains an unpaired UTF-16 surrogate.');
      }
    } else if (unit >= 0xdc00 && unit <= 0xdfff) {
      throw ArgumentError('Illustrator text contains an unpaired UTF-16 surrogate.');
    }
  }
}

/// Refuses unmodeled position-dependent data instead of retaining stale offsets.
void _knownTextKeys(PsEngineDictionary record, Set<String> allowed, String context) {
  for (final String key in record.values.keys) {
    if (!allowed.contains(key)) {
      throw UnsupportedError('Cannot edit Illustrator text with unknown $context field /$key.');
    }
  }
}

/// Preserves the authored field spelling and rejects ambiguous aliases.
String _textKey(PsEngineDictionary record, String compact, String named) {
  _field(record, compact, named);
  return record.values.containsKey(compact) ? compact : named;
}

/// Splices complete source spans, inheriting the style at the insertion point.
List<_TextEditRun> _spliceTextRuns({required List<_TextEditRun> runs, required int start, required int end, required int inserted, required _TextEditBudget budget}) {
  final List<_TextEditRun> output = [];
  int offset = 0;
  for (final _TextEditRun run in runs) {
    final int limit = offset + run.length;
    if (offset < start) {
      _appendTextRun(output, run.record, (limit < start ? limit : start) - offset, budget);
    }
    if (offset <= start && start < limit) {
      _appendTextRun(output, run.record, inserted, budget);
    }
    if (limit > end) {
      _appendTextRun(output, run.record, limit - (offset > end ? offset : end), budget);
    }
    offset = limit;
  }
  return output;
}

/// Joins only fragments sharing the exact same source run dictionary.
void _appendTextRun(List<_TextEditRun> output, PsEngineDictionary record, int length, _TextEditBudget budget) {
  if (length == 0) {
    return;
  }
  final bool joins = output.isNotEmpty && identical(output.last.record, record);
  if (!joins) {
    budget.take();
  }
  final int previous = joins ? output.removeLast().length : 0;
  output.add(_TextEditRun(record: record, length: previous + length));
}

/// Produces one run per paragraph using the style at its first code unit.
List<_TextEditRun> _paragraphTextRuns(List<_TextEditRun> runs, String text, _TextEditBudget budget) {
  final List<_TextEditRun> output = [];
  int runIndex = 0;
  int runEnd = runs.first.length;
  int start = 0;
  while (start < text.length) {
    while (runEnd <= start) {
      runEnd += runs[++runIndex].length;
    }
    final int end = text.indexOf('\r', start) + 1;
    budget.take();
    output.add(_TextEditRun(record: runs[runIndex].record, length: end - start));
    start = end;
  }
  return output;
}

/// Rewrites run lengths while retaining table, style and per-run metadata.
PsEngineDictionary _editedTextTable(PsEngineDictionary table, List<_TextEditRun> runs) => PsEngineDictionary(
  values: {
    ...table.values,
    _textKey(table, '0', 'RunArray'): PsEngineArray(
      values: [
        for (final _TextEditRun run in runs)
          PsEngineDictionary(
            values: {
              ...run.record.values,
              _textKey(run.record, '1', 'Length'): PsEngineNumber(value: run.length),
            },
          ),
      ],
    ),
  },
);

/// Allows CS auxiliary tables only when every run carries no active features.
List<_TextEditRun> _emptyAuxiliaryRuns(PsEngineDictionary table, String text) {
  final List<_TextEditRun> runs = [];
  int offset = 0;
  final PsEngineValue? array = _field(table, '0', 'RunArray');
  if (array is! PsEngineArray) {
    throw const FormatException('Missing Illustrator auxiliary text run array.');
  }
  for (final PsEngineValue value in array.values) {
    final PsEngineDictionary record = _dictionary(value);
    if (_dictionary(_field(record, '0', 'RunData')).values.isNotEmpty) {
      throw UnsupportedError('Cannot edit Illustrator text with active auxiliary run features.');
    }
    final int length = _index(_field(record, '1', 'Length'));
    if (length == 0 || length > text.length - offset) {
      throw const FormatException('Invalid Illustrator auxiliary text run length.');
    }
    offset += length;
    _textBoundary(text, offset);
    runs.add(_TextEditRun(record: record, length: length));
  }
  if (offset != text.length) {
    throw const FormatException('Illustrator auxiliary text runs do not cover the story.');
  }
  return runs;
}
