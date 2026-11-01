part of 'package:aikit/src/model/ai_native_records.dart';

/// Qualified pattern/symbol names, source spans and owned metadata retained together.
typedef _ArtboardResourceScope = ({Set<String> patterns, Set<String> symbols, List<({int start, int end})> ranges, Set<AiNativeContainer> objects});

/// Qualifies direct CC resource artwork without evaluating PostScript programs.
_ArtboardResourceScope _artboardResourceScope(AiNativeLayers layers) {
  final AiNativeRecords records = layers.drawing.records;
  final List<AiToken> tokens = records._projection.tokens;
  final Set<String> patterns = {};
  final Set<String> symbols = {};
  final List<AiNativeDrawing> drawings = [];
  final List<({int start, int end})> ranges = [];
  final Set<AiNativeContainer> objects = {};
  final Map<int, AiNativeResourceUse> references = {for (final AiNativeResourceUse use in layers.structure.resourceUses) use.instruction.start: use};
  bool setup = false;
  int procedure = 0;
  int embedded = 0;
  int root = 0;
  for (int index = 0; index < tokens.length && tokens[index].start < records.program.bodyStart; index++) {
    final AiToken opening = tokens[index];
    while (root < records.roots.length && records.roots[root].end <= opening.start) {
      root++;
    }
    if (root < records.roots.length && opening.start >= records.roots[root].start) {
      continue;
    }
    if (opening.kind == .procedureStart) {
      procedure++;
    } else if (opening.kind == .procedureEnd) {
      procedure--;
    }
    if (procedure != 0 || opening.kind != .comment) {
      continue;
    }
    if (opening.lexeme.startsWith('%%BeginDocument')) {
      embedded++;
    } else if (opening.lexeme == '%%EndDocument') {
      embedded--;
    }
    if (embedded != 0) {
      continue;
    }
    if (opening.lexeme == '%%BeginSetup') {
      setup = true;
    } else if (opening.lexeme == '%%EndSetup') {
      setup = false;
    }
    final bool pattern = opening.lexeme.startsWith('%AI3_BeginPattern:');
    final bool symbol = opening.lexeme == '%AI14_BeginSymbol';
    if (!setup || !pattern && !symbol) {
      continue;
    }
    final List<AiToken> contents = [];
    final String ending = pattern ? '%AI3_EndPattern' : '%AI10_EndSymbol';
    while (++index < tokens.length && tokens[index].start < records.program.bodyStart && !(tokens[index].kind == .comment && tokens[index].lexeme == ending)) {
      final AiToken token = tokens[index];
      if (token.kind == .data || token.kind == .comment && (token.lexeme.startsWith('%AI') || token.lexeme.startsWith('%%'))) {
        throw UnsupportedError('Retained resources cannot hide conditional, embedded or opaque artwork.');
      }
      if (token.kind != .comment) {
        contents.add(token);
      }
    }
    if (index >= tokens.length || tokens[index].start >= records.program.bodyStart || contents.length < (pattern ? 6 : 1)) {
      throw const FormatException('Retained resources require complete boundaries and a literal declaration.');
    }
    final AiToken closing = tokens[index];
    if (contents.any((token) => token.number != null && (!token.number!.isFinite || token.number!.abs() > 9007199254740991))) {
      throw const FormatException('Retained resource values must be finite portable numbers.');
    }
    if (records._projection.isPrivate(opening.start) ||
        records._projection.isPrivate(closing.start) ||
        layers.structure.versions.blocks.any((block) => block.start < closing.end && block.end > opening.start)) {
      throw UnsupportedError('Retained resources require unconditional ordinary declaration boundaries.');
    }
    if (!_artboardPaletteName(contents.first) || records._projection.isPrivate(contents.first.start)) {
      throw const FormatException('Retained resources require an ordinary literal name.');
    }
    if (pattern) {
      _artboardPatternHeader(records, opening, contents);
    }
    if (!(pattern ? patterns : symbols).add(latin1.decode(aiStringBytes(contents.first)))) {
      throw UnsupportedError('Retained resource names must identify a unique definition in their namespace.');
    }
    final int start = contents[pattern ? 4 : 0].end;
    final int end = pattern ? contents.last.start : closing.start;
    final List<AiNativeContainer> metadata = _pathInterval(records.roots, start, end, (record) => record.start).toList();
    final List<AiNativeItem> items = [];
    final _NativeCommandReader reader = _NativeCommandReader(maxDepth: records.program.limits.maxDepth);
    int owner = 0;
    for (final AiToken token in contents.skip(pattern ? 5 : 1).take(contents.length - (pattern ? 6 : 1))) {
      while (owner < metadata.length && metadata[owner].end <= token.start) {
        owner++;
      }
      if (owner < metadata.length && token.start >= metadata[owner].start) {
        if (token.start == metadata[owner].start) {
          reader.finish();
          if (metadata[owner].end > end) {
            throw const FormatException('Resource metadata crosses its declaration boundary.');
          }
          if (pattern) {
            _artboardPatternMetadata(layers, metadata[owner]);
          } else {
            _artboardSymbolMetadata(layers, metadata[owner]);
          }
          items.add(metadata[owner]);
          objects.add(metadata[owner]);
        }
        continue;
      }
      final AiNativeInstruction? instruction = reader.add(token, isPrivate: records._projection.isPrivate(token.start));
      if (instruction != null) {
        items.add(instruction);
      }
    }
    reader.finish();
    drawings.add(_NativeDrawingReader(records: records).readItems(items));
    ranges.add((start: opening.start, end: closing.end));
  }
  for (final AiNativeDrawing drawing in drawings) {
    _artboardResourceArtwork(layers, drawing, references, patterns);
  }
  return (patterns: Set.unmodifiable(patterns), symbols: Set.unmodifiable(symbols), ranges: List.unmodifiable(ranges), objects: Set.unmodifiable(objects));
}

/// Checks the ordinary tile rectangle and matching pattern wrapper name.
void _artboardPatternHeader(AiNativeRecords records, AiToken opening, List<AiToken> contents) {
  final List<AiToken> label = AiPostScript.tokenize(
    latin1.encode(opening.lexeme.substring('%AI3_BeginPattern:'.length)),
    maxBytes: records.program.limits.maxDecodedBytes,
    maxTokens: records.program.limits.maxTokens,
    maxDepth: records.program.limits.maxDepth,
  );
  if (label.length != 1 || !_artboardPaletteName(label.single) || !_gradientBytesEqual(aiStringBytes(label.single), aiStringBytes(contents.first))) {
    throw const FormatException('Pattern wrapper and declaration names must match.');
  }
  final List<AiToken> bounds = contents.sublist(1, 5);
  if (contents.take(5).any((token) => records._projection.isPrivate(token.start)) ||
      bounds.any((token) => token.number == null) ||
      bounds[0].number! >= bounds[2].number! ||
      bounds[1].number! >= bounds[3].number! ||
      contents.last.kind != .executableName ||
      contents.last.lexeme != 'E' ||
      records._projection.isPrivate(contents.last.start)) {
    throw const FormatException('Pattern setup requires an ordinary nonempty tile rectangle and E terminator.');
  }
}

/// Keeps tile-editor settings and local gradient transforms free of board links.
void _artboardPatternMetadata(AiNativeLayers layers, AiNativeContainer record) {
  _artboardSetupRecord(layers, record);
  if (record.type != 'ArtDictionary' || record.hasBinary) {
    throw UnsupportedError('Retained patterns require qualified art metadata.');
  }
  _referenceFields(
    record,
    {
      'Bool': {
        'AIPattern_Editor_Backing_Tile_Rect',
        'AIPattern_Is_Main_Copy_of_EditGroup',
        'AIPattern_Is_Repeated_Art',
        'AIPattern_Editor_Dim_Copies_Key',
        'AIPattern_Editor_Left_in_Front',
        'AIPattern_Editor_Top_in_Front',
        'AIPattern_Editor_AutoGrow',
      },
      'Int': {'AIPattern_Editor_Preview_Rows', 'AIPattern_Editor_Preview_Cols', 'AIPattern_Editor_Editable_Copy_Loc_Key', 'AIPattern_Editor_Repetition_Type'},
      'Real': {'AIPattern_Editor_Dim_Percent_Key', 'AIPattern_Editor_Tile_Height', 'AIPattern_Editor_Tile_Width', 'AIPattern_Editor_AutoSpacing_H', 'AIPattern_Editor_AutoSpacing_V'},
      'String': {'BBAccumRotation', 'AIArtName', 'Object name'},
    },
    nested: {
      'Adobe_AI9_ArtStyle_Dictionary': (entry) => _referenceFields(_referenceRecord(entry, 'Dictionary'), {
        'RealMatrix': {'CAIGradientTformMatrix'},
      }, notRecorded: true),
    },
  );
  _artboardResourceRotation(record);
}

/// Checks saved rotation values without changing the resource coordinate basis.
void _artboardResourceRotation(AiNativeContainer record) {
  for (final AiNativeEntry entry in record.entries) {
    if (entry.key == 'BBAccumRotation') {
      final double? angle = entry.stringBytes == null ? null : double.tryParse(latin1.decode(entry.stringBytes!));
      if (angle == null || !angle.isFinite || angle.abs() > 9007199254740991) {
        throw const FormatException('Retained resource rotation metadata must be numeric.');
      }
    }
  }
}

/// Retains symbol-local registration grids, identities and appearance metadata.
void _artboardSymbolMetadata(AiNativeLayers layers, AiNativeContainer record) {
  _artboardSetupRecord(layers, record);
  if (record.type != 'ArtDictionary' || record.hasBinary) {
    throw UnsupportedError('Retained symbols require qualified art metadata.');
  }
  _referenceFields(
    record,
    {
      'Bool': {'AI13PatternEnableGuides', 'AI15PixelPerfectSymbolEnablekey', 'PATH_IS_KAPPA_CURVE'},
      'Int': {'AI13PatternExportType', 'AI13PatternRegistrationType', 'AI10 compound shape mode'},
      'RealMatrix': {'AI13Pattern9SliceScalingGridKey'},
      'String': {'BBAccumRotation', 'AIArtName', 'Object name'},
    },
    nested: {
      'Adobe_AI9_ArtStyle_Dictionary': (entry) => _referenceFields(_referenceRecord(entry, 'Dictionary'), {
        'RealMatrix': {'CAIGradientTformMatrix'},
      }, notRecorded: true),
      'AI10_ArtUID': (entry) {
        final AiNativeContainer identity = _referenceRecord(entry, 'XMLUID');
        if (identity.entries.length != 1 ||
            identity.entries.single.key != null ||
            identity.entries.single.type != null ||
            identity.entries.single.stringBytes == null ||
            identity.entries.single.stringBytes!.isEmpty) {
          throw const FormatException('Retained symbol identities require one literal XML identifier.');
        }
      },
    },
  );
  _artboardResourceRotation(record);
}
