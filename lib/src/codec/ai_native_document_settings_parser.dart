part of 'package:aicodec/src/model/ai_native_records.dart';

/// Reads bounded numeric fields from the owning initial document header.
Map<String, AiNativeHeaderField> _nativeNumericHeader(AiNativeRecords records, Set<String> fields) {
  final Map<String, AiNativeHeaderField> header = {};
  final RegExp field = RegExp('^%{1,2}(${fields.map(RegExp.escape).join('|')}):\\s*(.*?)\\s*\$');
  final RegExp beginVersion = RegExp(r'^%(AI\d+)_Begin_Content_if_version_gt:');
  final RegExp alternateVersion = RegExp(r'^%(AI\d+)_Alternate_Content$');
  final RegExp endVersion = RegExp(r'^%(AI\d+)_End_Versioned_Content$');
  int embedded = 0;
  int procedures = 0;
  final List<({String prefix, bool alternate})> versions = [];
  for (final AiToken token in records._projection.tokens) {
    if (token.kind != .comment) {
      if (embedded == 0) {
        break;
      }
      if (token.kind == .procedureStart) {
        procedures++;
      } else if (token.kind == .procedureEnd) {
        procedures--;
      }
      continue;
    }
    if (procedures != 0) {
      continue;
    }
    if (embedded == 0 &&
        (const {'%%EndComments', '%%BeginProlog', '%%EndProlog', '%%BeginSetup', '%%EndSetup', '%%PageTrailer', '%%Trailer', '%%EOF'}.contains(token.lexeme) || token.lexeme.startsWith('%%Page:'))) {
      break;
    }
    final String comment = token.lexeme;
    if (comment.startsWith('%%BeginDocument')) {
      embedded++;
    } else if (comment == '%%EndDocument') {
      embedded--;
      continue;
    }
    if (embedded != 0) {
      continue;
    }
    final RegExpMatch? beginning = beginVersion.firstMatch(comment);
    final RegExpMatch? alternate = alternateVersion.firstMatch(comment);
    final RegExpMatch? ending = endVersion.firstMatch(comment);
    if (beginning != null) {
      if (versions.length >= records.program.limits.maxDepth) {
        throw const AiLimitException(message: 'Document header alternatives exceed the nesting limit.');
      }
      versions.add((prefix: beginning[1]!, alternate: false));
    } else if (alternate != null) {
      if (versions.isEmpty || versions.last.alternate || versions.last.prefix != alternate[1]) {
        throw const FormatException('Unmatched or repeated alternate header branch.');
      }
      versions[versions.length - 1] = (prefix: versions.last.prefix, alternate: true);
    } else if (ending != null) {
      if (versions.isEmpty || versions.last.prefix != ending[1]) {
        throw const FormatException('Unmatched version boundary in document settings.');
      }
      versions.removeLast();
    }
    final RegExpMatch? match = field.firstMatch(comment);
    if (match == null) {
      continue;
    }
    final String key = match[1]!;
    if (versions.isNotEmpty || header.containsKey(key)) {
      throw UnsupportedError('Document setting $key has conditional or repeated ownership.');
    }
    final List<double> values = [];
    for (final String text in match[2]!.split(RegExp(r'\s+'))) {
      final double? value = double.tryParse(text);
      if (value == null || !value.isFinite || value.abs() > 9007199254740991) {
        throw FormatException('Invalid numeric document setting $key.');
      }
      values.add(value);
    }
    header[key] = AiNativeHeaderField._(token: token, values: values);
  }
  if (versions.isNotEmpty || embedded != 0) {
    throw const FormatException('Unterminated document settings section.');
  }
  return header;
}

/// Reads only source-owned header declarations and explicit document fields.
AiNativeDocumentSettings _nativeDocumentSettings(AiNativeRecords records) {
  final Map<String, AiNativeHeaderField> header = _nativeNumericHeader(records, {'AI5_RulerUnits', 'AI24_RulerUnitsLarge', 'AI24_LargeCanvasScale', 'Canvassize', 'AI3_TemplateBox', 'PageOrigin'});
  for (final MapEntry<String, AiNativeHeaderField> entry in header.entries) {
    final List<double> values = entry.value.values;
    final bool valid = switch (entry.key) {
      'AI5_RulerUnits' || 'AI24_RulerUnitsLarge' => values.length == 1 && values.single >= 0 && values.single == values.single.truncateToDouble(),
      'AI24_LargeCanvasScale' => values.length == 1 && values.single > 0,
      'Canvassize' => const {1, 2}.contains(values.length) && values.every((value) => value > 0),
      'AI3_TemplateBox' => values.length == 4,
      'PageOrigin' => values.length == 2,
      _ => false,
    };
    if (!valid) {
      throw FormatException('Invalid document setting layout for ${entry.key}.');
    }
  }
  final List<AiNativeContainer> documents = records.roots.where((record) => record.type == 'Document').toList();
  for (final AiNativeContainer document in documents) {
    for (final String section in ['Recorded', 'NotRecorded']) {
      final AiNativeEntry? entry = document[section];
      if (entry != null && entry.container?.type != 'Dictionary') {
        throw FormatException('Invalid native Document $section section.');
      }
    }
  }
  final List<AiNativeTextRulerOrigin> origins = [];
  for (final AiNativeContainer document in records.roots.where((record) => record.type == 'AI11TextDocument' && record.end <= records.program.bodyStart)) {
    final AiNativeEntry? entry = document['RulerOrigin'];
    if (entry == null) {
      continue;
    }
    if (entry.numbers?.length != 2) {
      throw const FormatException('Invalid text-document ruler origin.');
    }
    origins.add(AiNativeTextRulerOrigin._(document: document, entry: entry));
  }
  return AiNativeDocumentSettings._(records: records, header: header, documents: documents, artboards: records.artboards, textRulerOrigins: origins);
}
