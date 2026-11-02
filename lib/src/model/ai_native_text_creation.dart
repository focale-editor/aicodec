part of 'ai_native_text.dart';

/// Initializes a complete empty text namespace without copying producer bytes.
AiNativeTextDocument _createNativeTextDocument(
  AiNativeRecords records,
  AiNativeFontDefinition font,
  double fontSize,
  AiNativeTextProcessColor fillColor,
  List<double> rulerOrigin,
  AiNativeCharacterChanges? characterStyle,
  AiNativeParagraphChanges? paragraphStyle,
  String characterStyleName,
  String paragraphStyleName,
  PsEngineLimits limits,
) {
  limits.validate();
  if (rulerOrigin.length != 2 || rulerOrigin.any((value) => !value.isFinite || value.abs() > 9007199254740991)) {
    throw ArgumentError('Native text initialization requires an explicit portable ruler origin.');
  }
  if (records.containers.any((record) => const {'AI11TextDocument', 'AI11UndoFreeTextDocument', 'AI11Text'}.contains(record.type))) {
    throw ArgumentError('Native text initialization cannot replace an existing text namespace or orphan reference.');
  }
  if (characterStyle?.font != null || characterStyle?.inherit.isNotEmpty == true || paragraphStyle?.inherit.isNotEmpty == true) {
    throw ArgumentError('Initial text styles require local values without source-owned fonts or inherited overrides.');
  }
  for (final String name in [characterStyleName, paragraphStyleName]) {
    _editableText(name);
    if (name.isEmpty || name.contains('\r') || name.contains('\u0000') || name.length > (limits.maxStringBytes - 2) ~/ 2) {
      throw ArgumentError('Initial native text style names require bounded nonempty text.');
    }
  }
  for (final String value in [font.postScriptName, if (font.version != null) font.version!]) {
    if (value.length > (limits.maxStringBytes - 2) ~/ 2 || value.length > (limits.maxBytes - 2) ~/ 2) {
      throw const FormatException('Initial font identity exceeds the text-engine string limit.');
    }
  }
  validateTextLifecycleSource(records: records, textRecords: {});
  final AiProgram program = records.program;
  final List<AiToken> tokens = AiPostScript.tokenize(program.bytes, maxBytes: program.limits.maxDecodedBytes, maxTokens: program.limits.maxTokens, maxDepth: program.limits.maxDepth);
  final List<AiToken> endings = tokens.where((token) => token.kind == .comment && token.lexeme == '%%EndSetup' && token.end == program.bodyStart).toList();
  if (endings.length != 1) {
    throw UnsupportedError('Initial native text requires an explicit complete setup section.');
  }
  final AiNativeCharacterChanges initialCharacter = AiNativeCharacterChanges(
    fontSize: fontSize,
    automaticLeading: true,
    horizontalScale: 1,
    verticalScale: 1,
    tracking: 0,
    baselineShift: 0,
    rotation: 0,
    ligatures: true,
    fillColor: fillColor,
    fillEnabled: true,
    fillVisible: true,
    strokeEnabled: false,
    strokeVisible: true,
    fillFirst: true,
    fillOverprint: false,
    strokeOverprint: false,
    backgroundEnabled: false,
  );
  final AiNativeParagraphChanges initialParagraph = AiNativeParagraphChanges(
    justification: 0,
    firstLineIndent: 0,
    startIndent: 0,
    endIndent: 0,
    spaceBefore: 0,
    spaceAfter: 0,
    automaticLeading: 1.2,
    hyphenate: false,
  );
  final Map<AiNativeCharacterFeature, PsEngineValue> character = {...initialCharacter._values, ...?characterStyle?._values};
  final Map<AiNativeParagraphFeature, PsEngineValue> paragraph = {...initialParagraph._values, ...?paragraphStyle?._values};
  final _TextIdentifiers identifiers = _TextIdentifiers(
    engine: PsEngineDocument.decode(bytes: const [], limits: limits),
  );

  /// Wraps each authored resource and declares its explicit display-list index.
  PsEngineDictionary table(List<PsEngineDictionary> values) => PsEngineDictionary(
    values: {
      '0': PsEngineArray(
        values: [
          for (final PsEngineDictionary value in values) PsEngineDictionary(values: {'0': value}),
        ],
      ),
      '1': PsEngineArray(
        values: [
          for (int index = 0; index < values.length; index++) PsEngineDictionary(values: {'0': PsEngineNumber(value: index)}),
        ],
      ),
    },
  );
  final PsEngineDictionary root = PsEngineDictionary(
    values: {
      '0': PsEngineDictionary(
        values: {
          '1': table([]),
          '5': table([
            PsEngineDictionary(
              values: {
                '0': PsEngineString.fromText(text: characterStyleName),
                '97': PsEngineString(bytes: identifiers.next().codeUnits),
                '6': PsEngineDictionary(
                  values: {
                    '0': PsEngineNumber(value: 0),
                    for (final MapEntry<AiNativeCharacterFeature, PsEngineValue> entry in character.entries) entry.key._compact: entry.value,
                    '89': character[AiNativeCharacterFeature.fontSize]!,
                    '90': PsEngineNumber(value: 0),
                  },
                ),
              },
            ),
          ]),
          '6': table([
            PsEngineDictionary(
              values: {
                '0': PsEngineString.fromText(text: paragraphStyleName),
                '97': PsEngineString(bytes: identifiers.next().codeUnits),
                '5': PsEngineDictionary(values: {for (final MapEntry<AiNativeParagraphFeature, PsEngineValue> entry in paragraph.entries) entry.key._compact: entry.value}),
              },
            ),
          ]),
          '8': table([]),
        },
      ),
      '1': PsEngineDictionary(
        values: {
          '0': PsEngineDictionary(values: {'1': PsEngineNumber(value: 0), '2': PsEngineNumber(value: 0)}),
          '1': PsEngineArray(values: []),
        },
      ),
      '98': PsEngineDictionary(values: {'0': PsEngineNumber(value: 7)}),
    },
  );
  final List<int> bytes = PsEngineCodec.encode(value: root, bareDictionary: true, limits: limits);
  final List<AiSourceEdit> edits = _initialTextFontHeaders(tokens, font.postScriptName, program.bodyStart);
  edits.add(
    AiSourceEdit(
      start: endings.single.start,
      end: endings.single.start,
      bytes: latin1.encode(
        '%AI11_BeginTextDocument\n/AI11TextDocument : /ASCII85Decode ,\n%~>\n${rulerOrigin.join(' ')} /RulerOrigin , ;\n'
        '/AI11UndoFreeTextDocument : /ASCII85Decode ,\n%~>\n;\n%AI11_EndTextDocument\n',
      ),
    ),
  );
  final AiNativeRecords inserted = AiNativeRecords.decode(
    program: AiNativeEditor.apply(program: program, edits: edits),
  );
  final AiNativeRecords seeded = inserted.replaceBinary(container: inserted.containers.singleWhere((record) => record.type == 'AI11TextDocument'), bytes: bytes);
  final AiNativeTextDocument withFont = AiNativeTextDocument.decode(records: seeded, limits: limits).addFont(font: font);
  final AiNativeRecords complete = withFont.records.replaceBinary(
    container: withFont.records.containers.singleWhere((record) => record.type == 'AI11UndoFreeTextDocument'),
    bytes: withFont.engine.bytes,
  );
  final AiNativeTextDocument result = AiNativeTextDocument.decode(records: complete, limits: limits);
  _TextLifecycle(source: result);
  return result;
}

/// Extends literal font inventories without dropping unrelated declared fonts.
List<AiSourceEdit> _initialTextFontHeaders(List<AiToken> tokens, String font, int bodyStart) {
  final AiToken? end = tokens.where((token) => token.kind == .comment && token.lexeme == '%%EndComments' && token.start < bodyStart).firstOrNull;
  if (end == null) {
    throw UnsupportedError('Initial text creation requires a complete native header.');
  }
  final List<AiSourceEdit> edits = [];
  final StringBuffer missing = StringBuffer();
  for (final String name in ['%%DocumentFonts', '%%DocumentNeededFonts']) {
    final List<AiToken> fields = tokens.where((token) => token.kind == .comment && token.start < end.start && token.lexeme.startsWith('$name:')).toList();
    if (fields.length > 1) {
      throw UnsupportedError('Initial text creation requires unique font header inventories.');
    }
    if (fields.isEmpty) {
      missing.writeln('$name: $font');
      continue;
    }
    final AiToken field = fields.single;
    final String value = field.lexeme.substring(name.length + 1).trim();
    if (value == '(none)') {
      edits.add(AiSourceEdit(start: field.start, end: field.end, bytes: latin1.encode('$name: $font')));
    } else if (value.contains('(') || value.contains(')')) {
      throw UnsupportedError('Font authoring requires literal header inventories rather than deferred DSC fields.');
    } else if (!value.split(RegExp(r'\s+')).contains(font)) {
      edits.add(AiSourceEdit(start: field.end, end: field.end, bytes: latin1.encode(' $font')));
    }
  }
  if (missing.isNotEmpty) {
    edits.add(AiSourceEdit(start: end.start, end: end.start, bytes: latin1.encode(missing.toString())));
  }
  return edits;
}
