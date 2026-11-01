part of 'package:aikit/src/model/ai_native_records.dart';

/// Qualified pattern names, source spans and owned metadata retained together.
typedef _ArtboardPatternScope = ({Set<String> names, List<({int start, int end})> ranges, Set<AiNativeContainer> objects});

/// Qualifies direct CC pattern artwork without evaluating old PostScript tiles.
_ArtboardPatternScope _artboardPatternScope(AiNativeLayers layers) {
  final AiNativeRecords records = layers.drawing.records;
  final List<AiToken> tokens = records._projection.tokens;
  final Set<String> names = {};
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
    if (!setup || !opening.lexeme.startsWith('%AI3_BeginPattern:')) {
      continue;
    }
    final List<AiToken> contents = [];
    while (++index < tokens.length && tokens[index].start < records.program.bodyStart && tokens[index].lexeme != '%AI3_EndPattern') {
      final AiToken token = tokens[index];
      if (token.kind == .data || token.kind == .comment && (token.lexeme.startsWith('%AI') || token.lexeme.startsWith('%%'))) {
        throw UnsupportedError('Retained patterns cannot hide conditional, embedded or opaque artwork.');
      }
      if (token.kind != .comment) {
        contents.add(token);
      }
    }
    if (index >= tokens.length || tokens[index].start >= records.program.bodyStart || contents.length < 6) {
      throw const FormatException('Retained pattern setup requires complete boundaries and a tile rectangle.');
    }
    final AiToken closing = tokens[index];
    if (contents.any((token) => token.number != null && (!token.number!.isFinite || token.number!.abs() > 9007199254740991))) {
      throw const FormatException('Retained pattern values must be finite portable numbers.');
    }
    if (records._projection.isPrivate(opening.start) ||
        records._projection.isPrivate(closing.start) ||
        layers.structure.versions.blocks.any((block) => block.start < closing.end && block.end > opening.start)) {
      throw UnsupportedError('Retained patterns require unconditional ordinary declaration boundaries.');
    }
    final List<AiToken> label = AiPostScript.tokenize(
      latin1.encode(opening.lexeme.substring('%AI3_BeginPattern:'.length)),
      maxBytes: records.program.limits.maxDecodedBytes,
      maxTokens: records.program.limits.maxTokens,
      maxDepth: records.program.limits.maxDepth,
    );
    if (label.length != 1 || !_artboardPaletteName(label.single) || !_artboardPaletteName(contents.first) || !_gradientBytesEqual(aiStringBytes(label.single), aiStringBytes(contents.first))) {
      throw const FormatException('Pattern wrapper and declaration names must match.');
    }
    final List<AiToken> bounds = contents.sublist(1, 5);
    if (contents.take(5).any((token) => records._projection.isPrivate(token.start)) ||
        bounds.any((token) => token.number == null || !token.number!.isFinite || token.number!.abs() > 9007199254740991) ||
        bounds[0].number! >= bounds[2].number! ||
        bounds[1].number! >= bounds[3].number! ||
        contents.last.kind != .executableName ||
        contents.last.lexeme != 'E' ||
        records._projection.isPrivate(contents.last.start)) {
      throw const FormatException('Pattern setup requires an ordinary nonempty tile rectangle and E terminator.');
    }
    if (!names.add(latin1.decode(aiStringBytes(contents.first)))) {
      throw UnsupportedError('Retained pattern names must identify a unique setup definition.');
    }
    final List<AiNativeContainer> metadata = _pathInterval(records.roots, contents[4].end, contents.last.start, (record) => record.start).toList();
    final List<AiNativeItem> items = [];
    final _NativeCommandReader reader = _NativeCommandReader(maxDepth: records.program.limits.maxDepth);
    int owner = 0;
    for (final AiToken token in contents.skip(5).take(contents.length - 6)) {
      while (owner < metadata.length && metadata[owner].end <= token.start) {
        owner++;
      }
      if (owner < metadata.length && token.start >= metadata[owner].start) {
        if (token.start == metadata[owner].start) {
          reader.finish();
          if (metadata[owner].end > contents.last.start) {
            throw const FormatException('Pattern metadata crosses its declaration boundary.');
          }
          _artboardPatternMetadata(layers, metadata[owner]);
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
    _artboardPatternArtwork(layers, _NativeDrawingReader(records: records).readItems(items), references);
    ranges.add((start: opening.start, end: closing.end));
  }
  return (names: Set.unmodifiable(names), ranges: List.unmodifiable(ranges), objects: Set.unmodifiable(objects));
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
  for (final AiNativeEntry entry in record.entries) {
    if (entry.key == 'BBAccumRotation') {
      final double? angle = entry.stringBytes == null ? null : double.tryParse(latin1.decode(entry.stringBytes!));
      if (angle == null || !angle.isFinite || angle.abs() > 9007199254740991) {
        throw const FormatException('Retained pattern rotation metadata must be numeric.');
      }
    }
  }
}
