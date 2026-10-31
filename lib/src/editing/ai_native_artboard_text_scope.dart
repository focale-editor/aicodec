part of 'package:aikit/src/model/ai_native_records.dart';

/// Qualifies unused ATE resources without discarding their separate snapshots.
///
/// Empty text documents have no positioned stories or frames. Their font and
/// typography defaults remain in the text resource namespace, and are retained
/// byte-for-byte. Unknown top-level owners and actual text objects still reject.
List<({int start, int end})> _artboardEmptyTextScope(AiNativeLayers layers) {
  final AiNativeRecords records = layers.drawing.records;
  final List<AiNativeContainer> main = records.roots.where((record) => record.type == 'AI11TextDocument').toList();
  final List<AiNativeContainer> undo = records.roots.where((record) => record.type == 'AI11UndoFreeTextDocument').toList();
  if (main.isEmpty && undo.isEmpty) {
    return [];
  }
  if (main.length != 1 || undo.length > 1 || records.containers.any((record) => record.type == 'AI11Text')) {
    throw UnsupportedError('Artboard text isolation requires one empty main document and at most one empty undo-free snapshot.');
  }
  int bytesRemaining = records.program.limits.maxDecodedBytes;
  int nodesRemaining = records.program.limits.maxTokens;
  for (final AiNativeContainer record in [...main, ...undo]) {
    _artboardSetupRecord(layers, record);
    final bool primary = identical(record, main.single);
    final AiNativeEntry? origin = record['RulerOrigin'];
    if (!record.hasBinary ||
        record.entries.length != (primary ? 1 : 0) ||
        primary && (origin == null || origin.type != null || origin.numbers?.length != 2 || origin.numbers!.any((value) => !value.isFinite || value.abs() > 9007199254740991))) {
      throw UnsupportedError('Empty text isolation requires an explicit global ruler origin and exact binary ownership.');
    }
    if (bytesRemaining <= 0 || nodesRemaining <= 0) {
      throw const AiLimitException(message: 'Artboard text dependency inspection exceeds its aggregate budget.');
    }
    final Uint8List bytes = record.decodeBinary(maxOutputBytes: bytesRemaining);
    final PsEngineDocument engine = PsEngineDocument.decode(
      bytes: bytes,
      limits: PsEngineLimits(maxBytes: bytesRemaining, maxNodes: nodesRemaining, maxDepth: records.program.limits.maxDepth, maxStringBytes: bytesRemaining),
    );
    _artboardEmptyTextEngine(engine);
    bytesRemaining -= bytes.length;
    nodesRemaining -= engine.values.length;
  }
  final List<AiToken> wrappers = records._projection.tokens.where((token) => token.kind == .comment && const {'%AI11_BeginTextDocument', '%AI11_EndTextDocument'}.contains(token.lexeme)).toList();
  if (wrappers.isEmpty) {
    return [];
  }
  final AiNativeContainer last = undo.isEmpty ? main.single : undo.single;
  if (wrappers.length != 2 ||
      wrappers.first.lexeme != '%AI11_BeginTextDocument' ||
      wrappers.last.lexeme != '%AI11_EndTextDocument' ||
      wrappers.first.end > main.single.start ||
      main.single.end > last.end ||
      last.end > wrappers.last.start ||
      wrappers.last.end > records.program.bodyStart ||
      wrappers.any((token) => layers.structure.versions.memberships(start: token.start, end: token.end).isNotEmpty)) {
    throw UnsupportedError('Artboard text isolation requires one unconditional ordered text wrapper.');
  }
  return [for (final AiToken token in wrappers) (start: token.start, end: token.end)];
}

/// Requires a known compact ATE dictionary boundary rather than guessing aliases.
PsEngineDictionary _artboardTextDictionary(PsEngineValue? value, Set<String> keys) {
  if (value is! PsEngineDictionary || value.values.keys.any((key) => !keys.contains(key))) {
    throw UnsupportedError('Artboard text isolation encountered an unknown ATE dictionary owner.');
  }
  return value;
}

/// Requires an optional array to contain no active text or frame objects.
void _artboardEmptyTextArray(PsEngineValue? value) {
  if (value != null && (value is! PsEngineArray || value.values.isNotEmpty)) {
    throw UnsupportedError('Artboard isolation of populated text documents requires a separate dependency contract.');
  }
}

/// Checks domain boundaries before retaining unused font and typography payloads.
void _artboardEmptyTextEngine(PsEngineDocument engine) {
  final PsEngineDictionary root = _artboardTextDictionary(engine.root, {'0', '1', '98'});
  if (root['98'] case final PsEngineValue version) {
    final PsEngineDictionary header = _artboardTextDictionary(version, {'0'});
    if (header['0'] is! PsEngineNumber || (header['0']! as PsEngineNumber).value != 9) {
      throw UnsupportedError('Artboard text isolation requires the qualified compact ATE version.');
    }
  }
  final PsEngineDictionary resources = _artboardTextDictionary(root['0'], {'1', '2', '3', '4', '5', '6', '8', '9'});
  for (final MapEntry<String, PsEngineValue> entry in resources.values.entries) {
    final PsEngineDictionary table = _artboardTextDictionary(entry.value, {'0', '1'});
    if (entry.key == '8') {
      _artboardEmptyTextArray(table['0']);
      _artboardEmptyTextArray(table['1']);
      continue;
    }
    final PsEngineValue? definitions = table['0'];
    if (definitions is! PsEngineArray) {
      throw UnsupportedError('Unused text resources require an explicit resource array.');
    }
    for (final PsEngineValue value in definitions.values) {
      final PsEngineDictionary wrapper = _artboardTextDictionary(value, {'0'});
      if (wrapper['0'] is! PsEngineDictionary) {
        throw UnsupportedError('Unused typography resources require owned dictionaries.');
      }
    }
    final PsEngineValue? display = table['1'];
    if (display != null) {
      if (display is! PsEngineArray) {
        throw const FormatException('Invalid text resource display list.');
      }
      for (final PsEngineValue value in display.values) {
        final PsEngineValue? index = _artboardTextDictionary(value, {'0'})['0'];
        if (index is! PsEngineNumber || index.value < 0 || index.value >= definitions.values.length || index.value != index.value.truncate()) {
          throw const FormatException('Text display list references an absent resource.');
        }
      }
    }
  }
  final PsEngineDictionary objects = _artboardTextDictionary(root['1'], {'0', '1', '2', '3'});
  _artboardEmptyTextArray(objects['1']);
  if (objects['0'] case final PsEngineValue settings) {
    _artboardTextSettings(settings);
  }
  for (final String key in ['2', '3']) {
    if (objects[key] != null && objects[key] is! PsEngineDictionary) {
      throw const FormatException('Invalid unused normal text features.');
    }
  }
  if (engine.values.any((value) => value is PsEngineToken)) {
    throw UnsupportedError('Artboard text isolation cannot qualify opaque ATE tokens.');
  }
}

/// Checks text preferences without accepting arbitrary document-level extensions.
void _artboardTextSettings(PsEngineValue value) {
  final PsEngineDictionary settings = _artboardTextDictionary(value, {'0', '1', '2', '3', '4', '5', '6', '7', '8', '9', '11', '15', '16', '17'});
  for (final MapEntry<String, PsEngineValue> field in settings.values.entries) {
    switch (field.key) {
      case '0':
        final PsEngineDictionary hidden = _artboardTextDictionary(field.value, {'0', '1'});
        if (hidden['0'] != null && hidden['0'] is! PsEngineNumber) {
          throw const FormatException('Invalid alternate glyph font index.');
        }
        _artboardTextStringTable(hidden['1'], {'0', '1'});
      case '9':
        _artboardTextStringTable(field.value, {'0', '1', '2', '3', '4'}, numericKey: '0');
      case '15':
        final PsEngineDictionary language = _artboardTextDictionary(field.value, {'0'});
        if (language['0'] != null && language['0'] is! PsEngineString) {
          throw const FormatException('Invalid text language provider.');
        }
      case '8' || '16':
        if (field.value is! PsEngineBoolean) {
          throw const FormatException('Invalid Boolean text preference.');
        }
      default:
        if (field.value is! PsEngineNumber) {
          throw const FormatException('Invalid numeric text preference.');
        }
    }
  }
}

/// Qualifies literal glyph mappings and locale quote preferences without execution.
void _artboardTextStringTable(PsEngineValue? value, Set<String> keys, {String? numericKey}) {
  if (value == null) {
    return;
  }
  if (value is! PsEngineArray) {
    throw const FormatException('Text character preferences require an array.');
  }
  for (final PsEngineValue item in value.values) {
    final PsEngineDictionary record = _artboardTextDictionary(item, keys);
    for (final MapEntry<String, PsEngineValue> field in record.values.entries) {
      if (field.key == numericKey ? field.value is! PsEngineNumber : field.value is! PsEngineString) {
        throw const FormatException('Invalid text character preference.');
      }
    }
  }
}
