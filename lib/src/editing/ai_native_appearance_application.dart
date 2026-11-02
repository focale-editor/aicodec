part of 'package:aikit/src/model/ai_native_records.dart';

/// Rebinds exact applications while retaining geometry and both boundary states.
AiNativeAppearances _applyNativeAppearanceStyle(AiNativeAppearances model, AiNativeAppearance appearance, List<AiNativeAppearanceReplacement> artwork) {
  if (!model.styles.contains(appearance) ||
      artwork.isEmpty ||
      artwork.any((replacement) => !identical(replacement.artwork._owner, model)) ||
      artwork.map((replacement) => replacement.artwork.printingGroup).toSet().length != artwork.length) {
    throw ArgumentError('Style application requires a current definition and distinct complete printing owners.');
  }
  if (appearance.resource.versions.isNotEmpty ||
      model.styles.where((style) => _sameNativeBytes(style.resource.nameBytes, appearance.resource.nameBytes)).length != 1 ||
      artwork.any((replacement) => replacement.artwork.resource != null)) {
    throw UnsupportedError('Style application requires a unique unconditional style and body appearance owners.');
  }
  final AiNativeDrawing drawing = model.structure.drawing;
  final List<AiNativeResourceUse> selected = artwork.expand((replacement) => replacement.uses).toList();
  if (selected.toSet().length != selected.length) {
    throw ArgumentError('A selected style application cannot have more than one printing owner.');
  }
  final ({Set<String> reads, Set<String> writes}) target = _nativeAppearanceStyleState(model, appearance);
  final List<AiNativeAppearanceArtwork> retained = _nativeRetainedAppearanceArtwork(model);
  final Map<int, _NativeShapeInputs> original = _shapeCopyInputs(drawing, selected.map((use) => use.instruction.end).toList(), appearanceArtwork: retained);
  final Map<AiNativeResourceUse, AiNativeAppearance> before = {};
  final Map<int, Set<String>> reads = {};
  final Map<int, Set<String>> changed = {};
  final Map<int, Map<String, AiNativeInstruction>> restored = {};
  for (final AiNativeResourceUse use in selected) {
    final AiNativeAppearance? source = model.resolve(use: use);
    if (source == null || use.versions.isNotEmpty || source.resource.versions.isNotEmpty) {
      throw UnsupportedError('Rebinding requires resolved unconditional source applications.');
    }
    before[use] = source;
    final ({Set<String> reads, Set<String> writes}) current = _nativeAppearanceStyleState(model, source);
    reads[use.instruction.end] = {...current.reads, ...target.reads};
    final Set<String> keys = identical(source, appearance) ? {} : {...current.writes, ...target.writes};
    changed[use.instruction.end] = keys;
    restored[use.instruction.end] = {...original[use.instruction.end]!.native}..removeWhere((key, _) => !keys.contains(key));
  }
  final List<AiSourceEdit> edits = _nativeAppearancePrintingEdits(model, artwork);
  final List<int> name = _nativeLiteralString(appearance.resource.nameBytes, drawing.records.program.limits.maxDecodedBytes);
  int remaining = drawing.records.program.limits.maxDecodedBytes;
  for (final AiNativeResourceUse use in selected) {
    if (identical(before[use], appearance)) {
      continue;
    }
    remaining -= name.length;
    if (remaining < 0) {
      throw const AiLimitException(message: 'Style application names exceed native output limits.');
    }
    edits.add(AiSourceEdit(start: use.name.start, end: use.name.end, bytes: name));
  }

  final Set<String> patterns = {
    ..._nativeAppearancePatterns(model, appearance),
    for (final AiNativeAppearance style in before.values) ..._nativeAppearancePatterns(model, style),
  };

  /// Proves unchanged dependent state, replaying old literals only when needed.
  void following(Map<int, Map<String, AiNativeInstruction>> restorations) {
    _sourceFollowingDependencies(
      drawing,
      {
        for (final AiNativeAppearanceReplacement replacement in artwork)
          (start: replacement.artwork.start, end: replacement.artwork.end): (
            commands: replacement.artwork._commands,
            styles: {...replacement.artwork._styleReads, for (final AiNativeResourceUse use in replacement.uses) use.instruction.end: reads[use.instruction.end]!},
            prefix: [],
            suffix: [],
            unresolved: {},
            printingUnresolved: {},
            discard: false,
          ),
      },
      retainedArtwork: retained,
      clipping: true,
      styleChanges: changed,
      styleRestorations: restorations,
      patterns: patterns,
    );
  }

  try {
    following(const {});
  } on UnsupportedError {
    if (restored.values.every((commands) => commands.isEmpty)) {
      rethrow;
    }
    following(restored);
    for (final AiNativeResourceUse use in selected) {
      final Map<String, AiNativeInstruction> commands = restored[use.instruction.end]!;
      if (commands.isNotEmpty) {
        final List<int> bytes = latin1.encode('\n${commands.values.map((command) => _shapeStateText(command, private: true)).join()}');
        remaining -= bytes.length;
        if (remaining < 0) {
          throw const AiLimitException(message: 'Style boundary restoration exceeds native output limits.');
        }
        edits.add(AiSourceEdit(start: use.instruction.end, end: use.instruction.end, bytes: bytes));
      }
    }
  }
  final AiNativeAppearances result = _nativeAppearanceResult(model, edits, artwork.map((replacement) => replacement.artwork.use).toList());
  for (final AiNativeResourceUse use in selected) {
    final AiNativeAppearance? applied = result.resolve(use: result.uses[model.uses.indexOf(use)]);
    if (applied == null || !_sameNativeBytes(applied.resource.nameBytes, appearance.resource.nameBytes)) {
      throw const FormatException('Style application lost its selected source ownership.');
    }
  }
  return result;
}
