part of 'package:aicodec/src/model/ai_native_records.dart';

/// Reads explicit complete cells while keeping unknown paint commands intact.
List<AiNativePalette> _readNativePalettes(AiNativeRecords records) {
  final List<AiToken> tokens = records._projection.tokens;
  final List<AiNativePalette> result = [];
  int procedures = 0;
  int documents = 0;
  int root = 0;
  for (int index = 0; index < tokens.length && tokens[index].start < records.program.bodyStart; index++) {
    final AiToken token = tokens[index];
    while (root < records.roots.length && records.roots[root].end <= token.start) {
      root++;
    }
    if (root < records.roots.length && token.start >= records.roots[root].start) {
      continue;
    }
    if (token.kind == .procedureStart) {
      procedures++;
    }
    if (token.kind == .procedureEnd) {
      procedures--;
    }
    if (procedures != 0 || token.kind != .comment) {
      continue;
    }
    if (token.lexeme.startsWith('%%BeginDocument')) {
      documents++;
    }
    if (token.lexeme == '%%EndDocument') {
      documents--;
    }
    if (documents != 0 || token.lexeme != '%AI5_BeginPalette') {
      continue;
    }
    final _NativeCommandReader reader = _NativeCommandReader(maxDepth: records.program.limits.maxDepth);
    AiNativeInstruction? opening;
    AiNativeInstruction? closing;
    final List<AiNativeInstruction> paint = [];
    final List<AiNativeSwatch> cells = [];
    bool conditional = false;
    for (index++; index < tokens.length && tokens[index].start < records.program.bodyStart && tokens[index].lexeme != '%AI5_EndPalette'; index++) {
      final AiToken value = tokens[index];
      if (value.kind == .comment) {
        if (value.lexeme.startsWith('%AI') || value.lexeme.startsWith('%%')) {
          conditional = true;
        }
        continue;
      }
      if (records._projection.isPrivate(value.start)) {
        throw UnsupportedError('Palette cells require ordinary source commands.');
      }
      final AiNativeInstruction? command = reader.add(value, isPrivate: false);
      if (command == null) {
        continue;
      }
      if (closing != null) {
        throw const FormatException('Unexpected commands after a palette boundary.');
      }
      if (opening == null) {
        if (command.operator != 'Pb' || command.numbers?.length != 2 || command.numbers!.any((number) => number < 0 || number % 1 != 0)) {
          throw const FormatException('A palette requires two explicit nonnegative indices.');
        }
        opening = command;
      } else if (command.operator == 'Pc') {
        if (paint.isEmpty || command.operands.length > 1 || command.operands.isNotEmpty && !_artboardPaletteName(command.operands.single)) {
          throw const FormatException('Palette cells require paint and an optional literal display name.');
        }
        cells.add(
          AiNativeSwatch._(start: paint.first.start, end: command.end, commands: paint, nameBytes: command.operands.isEmpty ? null : aiStringBytes(command.operands.single).asUnmodifiableView()),
        );
        paint.clear();
      } else if (command.operator == 'PB') {
        if (paint.isNotEmpty || command.operands.isNotEmpty) {
          throw const FormatException('A palette cannot end inside a cell.');
        }
        closing = command;
      } else if (command.operator == 'Pg') {
        if (paint.isNotEmpty ||
            command.operands.length != 3 ||
            !_artboardPaletteName(command.operands[1]) ||
            !{0, 1}.contains(command.operands.first.number) ||
            !{0, 1}.contains(command.operands.last.number)) {
          throw const FormatException('Palette groups must occur between complete cells.');
        }
      } else {
        if (paint.isNotEmpty && (paint.first.operator != 'Bb' || paint.last.operator == 'BB')) {
          throw UnsupportedError('Implicit palette terminators and multiple-paint cells require separate ownership qualification.');
        }
        paint.add(command);
      }
    }
    reader.finish();
    if (index == tokens.length || tokens[index].lexeme != '%AI5_EndPalette' || opening == null || closing == null) {
      throw const FormatException('Unterminated native palette.');
    }
    result.add(AiNativePalette._(start: token.start, end: tokens[index].end, opening: opening, closing: closing, swatches: cells, conditional: conditional));
  }
  return result;
}

/// Resolves one editable palette without merging saved alternative branches.
AiNativePalette? _nativeSwatchPalette(AiNativeSwatches model, AiNativePalette? requested) {
  if (requested != null && !model.palettes.contains(requested)) {
    throw ArgumentError('Palette creation requires a current palette handle.');
  }
  if (requested == null && model.palettes.length > 1) {
    throw ArgumentError('Select one explicit palette in a multiple-palette source.');
  }
  final AiNativePalette? palette = requested ?? model.palettes.singleOrNull;
  if (palette?.conditional == true) {
    throw UnsupportedError('Palette lifecycle requires unconditional cells.');
  }
  return palette;
}

/// Inserts one literal paint/name cell while preserving surrounding group bytes.
AiNativeSwatches _createNativeSwatch(AiNativeSwatches model, List<int> name, List<int> paint, AiNativePalette? requested, AiNativeSwatch? before) {
  if (name.isEmpty ||
      name.any((byte) => byte < 0 || byte > 255) ||
      model.palettes.expand((palette) => palette.swatches).any((swatch) => swatch.nameBytes != null && _sameNativeBytes(swatch.nameBytes!, name))) {
    throw ArgumentError('Swatch creation requires an unused nonempty display name.');
  }
  final AiNativePalette? palette = _nativeSwatchPalette(model, requested);
  if (before != null && (palette == null || !palette.swatches.contains(before))) {
    throw ArgumentError('Insertion requires a cell in the selected palette.');
  }
  _paintResourceScope(model.records);
  final AiProgram program = model.records.program;
  final List<int> label = _nativeLiteralString(name, program.limits.maxDecodedBytes);
  final List<int> cell = [...paint, 10, ...label, ...latin1.encode(' Pc\n')];
  final int position;
  final List<int> bytes;
  if (palette == null) {
    final List<AiToken> ends = model.records._projection.tokens.where((token) => token.kind == .comment && token.lexeme == '%%EndSetup' && token.start < program.bodyStart).toList();
    if (ends.length != 1) {
      throw UnsupportedError('Palette creation requires one explicit setup boundary.');
    }
    position = ends.single.start;
    bytes = [...latin1.encode('%AI5_BeginPalette\n0 0 Pb\n'), ...cell, ...latin1.encode('PB\n%AI5_EndPalette\n')];
  } else {
    position = before?.start ?? palette.closing.start;
    bytes = [...cell];
  }
  final AiNativeSwatches result = AiNativeSwatches.decode(
    records: AiNativeRecords.decode(
      program: AiNativeEditor.apply(
        program: program,
        edits: [AiSourceEdit(start: position, end: position, bytes: bytes)],
      ),
    ),
  );
  _paintResourceScope(result.records);
  return result;
}

/// Removes cells only after checking named-ink references outside the selection.
AiNativeSwatches _removeNativeSwatches(AiNativeSwatches model, List<AiNativeSwatch> swatches) {
  final List<AiNativeSwatch> owned = model.palettes.expand((palette) => palette.swatches).toList();
  if (swatches.isEmpty || swatches.toSet().length != swatches.length || swatches.any((swatch) => !owned.contains(swatch))) {
    throw ArgumentError('Swatch removal requires distinct current handles.');
  }
  if (model.palettes.any((palette) => palette.conditional && palette.swatches.any(swatches.contains))) {
    throw UnsupportedError('Saved alternative palette cells cannot be removed independently.');
  }
  _paintResourceScope(model.records);
  final Set<String> inkNames = {
    for (final AiNativeSwatch swatch in swatches)
      if (swatch.namedColor case final AiNativeNamedColor color) latin1.decode(color.nameBytes),
  };
  final List<AiNativeSwatch> ordered = [...swatches]..sort((first, second) => first.start.compareTo(second.start));
  int selected = 0;
  if (inkNames.isNotEmpty) {
    for (final AiToken token in model.records._projection.tokens) {
      while (selected < ordered.length && ordered[selected].end <= token.start) {
        selected++;
      }
      if (selected < ordered.length && token.start >= ordered[selected].start && token.end <= ordered[selected].end) {
        continue;
      }
      if (const {AiTokenKind.string, AiTokenKind.hexString}.contains(token.kind) && inkNames.contains(latin1.decode(aiStringBytes(token)))) {
        throw UnsupportedError('A named ink still has references outside the removed palette cells.');
      }
    }
  }
  return AiNativeSwatches.decode(
    records: AiNativeRecords.decode(
      program: AiNativeEditor.apply(
        program: model.records.program,
        edits: [for (final AiNativeSwatch swatch in swatches) AiSourceEdit(start: swatch.start, end: swatch.end, bytes: [])],
      ),
    ),
  );
}
