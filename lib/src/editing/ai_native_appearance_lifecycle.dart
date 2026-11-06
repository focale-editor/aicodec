part of 'package:illustratorkit/src/model/ai_native_records.dart';

/// Writes an entirely authored execution tree using the existing part grammar.
Uint8List _newNativeAppearanceExecution(AiNativeAppearancePartDefinition definition, AiNativeLimits limits) {
  int visited = 0;

  /// Accounts for wrapper depth and prevents unbounded recursive expansion.
  Uint8List write(AiNativeAppearancePartDefinition definition, int depth) {
    if (++visited > limits.maxTokens || depth + 2 >= limits.maxDepth) {
      throw const AiLimitException(message: 'New style execution exceeds native depth or token limits.');
    }
    return _createdNativeAppearancePart(definition, limits, false, (child) {
      final AiNativeAppearancePartDefinition? created = child.definition;
      if (created == null) {
        throw ArgumentError('New style execution requires authored children, not source-owned parts.');
      }
      return write(created, depth + 1);
    });
  }

  return write(definition, 0);
}

/// Finds a single setup endpoint without guessing a document's section layout.
int _nativeAppearanceSetupEnd(AiNativeRecords records) {
  final List<AiToken> endings = records._projection.tokens.where((token) => token.kind == .comment && token.lexeme == '%%EndSetup' && token.start < records.program.bodyStart).toList();
  if (endings.length != 1 || records._projection.isPrivate(endings.single.start) || records.containers.any((record) => record.start < endings.single.start && record.end > endings.single.start)) {
    throw UnsupportedError('Creating a native style requires one explicit unowned setup boundary.');
  }
  return endings.single.start;
}

/// Creates an unused definition without changing current style application state.
AiNativeAppearances _createNativeAppearanceStyle(AiNativeAppearances model, List<int> name, AiNativeAppearancePartDefinition execution) {
  final AiNativeRecords records = model.structure.drawing.records;
  if (name.isEmpty || model.styles.any((style) => _sameNativeBytes(style.resource.nameBytes, name)) || model.uses.any((use) => _sameNativeBytes(use.nameBytes, name))) {
    throw ArgumentError('A new style requires a fresh nonempty byte name across declarations and references.');
  }
  final List<int> literal = _nativeLiteralString(name, records.program.limits.maxDecodedBytes);
  final int insertion = _nativeAppearanceSetupEnd(records);
  _paintResourceScope(records);
  final Uint8List tree = _newNativeAppearanceExecution(execution, records.program.limits);
  if (literal.length + tree.length + 64 > records.program.limits.maxDecodedBytes - records.program.bytes.length) {
    throw const AiLimitException(message: 'New style declaration exceeds native output limits.');
  }
  final List<int> bytes = [
    ...latin1.encode('\n/KnownStyle : '),
    ...literal,
    ...latin1.encode(' /Name ,\n/ActiveStyle : '),
    ...tree,
    ...latin1.encode(' /Execution ; /Def ;\n'),
  ];
  final AiNativeAppearances result = _nativeAppearanceResult(model, [AiSourceEdit(start: insertion, end: insertion, bytes: bytes)], const []);
  if (result.styles.length != model.styles.length + 1) {
    throw const FormatException('Creating a native style disrupted declaration ownership.');
  }
  final AiNativeAppearance added = result.styles.singleWhere((style) => _sameNativeBytes(style.resource.nameBytes, name));
  if (added.uses.isNotEmpty) {
    throw const FormatException('A new unused style captured an existing native application.');
  }
  final AiNativeLayers layers = AiNativeLayers.decode(drawing: result.structure.drawing);
  _artboardRetainedStyle(
    layers,
    added.resource.definition.source as AiNativeContainer,
    {for (final AiNativeResourceUse use in result.structure.resourceUses) use.instruction.start: use},
    _nativeAppearancePatterns(result, added),
    _nativeStyleBrushes(result.structure.drawing, added.resource.definition.source as AiNativeContainer),
  );
  _nativeAppearanceStyleState(result, added);
  return result;
}

/// Removes whole unused declarations while preserving every unrelated source byte.
AiNativeAppearances _removeNativeAppearanceStyles(AiNativeAppearances model, List<AiNativeAppearance> selected) {
  if (selected.isEmpty || selected.toSet().length != selected.length || selected.any((style) => !model.styles.contains(style))) {
    throw ArgumentError('Style removal requires distinct current declaration handles.');
  }
  final AiNativeRecords records = model.structure.drawing.records;
  for (final AiNativeAppearance style in selected) {
    final AiNativeContainer declaration = style.resource.definition.source as AiNativeContainer;
    if (style.resource.versions.isNotEmpty ||
        declaration.end > records.program.bodyStart ||
        model.styles.where((other) => _sameNativeBytes(other.resource.nameBytes, style.resource.nameBytes)).length != 1 ||
        model.uses.any((use) => _sameNativeBytes(use.nameBytes, style.resource.nameBytes))) {
      throw UnsupportedError('Only unique unconditional unused setup styles can be removed.');
    }
  }
  _paintResourceScope(records);
  final AiNativeAppearances result = _nativeAppearanceResult(model, [
    for (final AiNativeAppearance style in selected) AiSourceEdit(start: style.resource.definition.start, end: style.resource.definition.end, bytes: []),
  ], const []);
  if (result.styles.length != model.styles.length - selected.length) {
    throw const FormatException('Removing native styles disrupted declaration ownership.');
  }
  return result;
}
