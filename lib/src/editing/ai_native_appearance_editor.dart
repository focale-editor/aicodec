part of 'package:aikit/src/model/ai_native_records.dart';

/// Changes selected native fields and their supplied expansions in one snapshot.
AiNativeAppearances _editNativeAppearance(
  AiNativeAppearances model,
  AiNativeAppearance appearance,
  List<AiNativePaintChange> paints,
  List<AiNativeAppearancePartChange> parts,
  List<AiNativePrintingGroupReplacement> printing,
  List<AiNativeAppearanceReplacement> artwork,
  List<AiNativeAppearanceReplacement> dependents,
  List<int>? nameBytes,
) {
  if (!model.styles.contains(appearance) || paints.isEmpty && parts.isEmpty) {
    throw ArgumentError('Appearance editing requires an owned style and explicit changes.');
  }
  final AiNativeDrawing drawing = model.structure.drawing;
  final AiProgram program = drawing.records.program;
  final AiNativeContainer declaration = appearance.resource.definition.source as AiNativeContainer;
  if (appearance.resource.versions.isNotEmpty ||
      model.styles.where((style) => _sameNativeBytes(style.resource.nameBytes, appearance.resource.nameBytes)).length != 1 ||
      appearance.parts.any((part) => const {AiNativeAppearancePartKind.effect, AiNativeAppearancePartKind.opaque}.contains(part.kind))) {
    throw UnsupportedError('Appearance editing requires a unique unconditional definition with qualified parts.');
  }
  final AiNativeLayers layers = AiNativeLayers.decode(drawing: drawing);
  _artboardRetainedStyle(layers, declaration, {for (final AiNativeResourceUse use in model.structure.resourceUses) use.instruction.start: use}, _nativeAppearancePatterns(model, appearance), {});
  final ({Set<String> reads, Set<String> writes}) state = _nativeAppearanceStyleState(model, appearance);
  final List<AiSourceEdit> styleEdits = _nativeAppearanceChanges(model, appearance, paints, parts);
  final List<AiNativeAppearanceReplacement> replacements = [...artwork];
  for (final AiNativePrintingGroupReplacement replacement in printing) {
    if (!drawing.liveShapes.contains(replacement.shape)) {
      throw ArgumentError('Appearance expansions require current shape handles.');
    }
    final AiNativeResourceUse? use = appearance.uses.where((use) => use.instruction.end == replacement.shape.end).singleOrNull;
    if (use == null) {
      throw UnsupportedError('Each supplied expansion must belong to the selected appearance.');
    }
    replacements.add(
      AiNativeAppearanceReplacement(
        artwork: model.artworkFor(use: use),
        bytes: replacement.bytes,
        bounds: replacement.bounds,
      ),
    );
  }
  final List<AiNativeResourceUse> selected = replacements.expand((replacement) => replacement.uses).toList();
  final List<AiNativeAppearanceReplacement> all = [...replacements, ...dependents];
  if (selected.toSet().length != selected.length ||
      all.any((replacement) => !identical(replacement.artwork._owner, model)) ||
      all.map((replacement) => replacement.artwork.printingGroup).toSet().length != all.length ||
      dependents.expand((replacement) => replacement.uses).toSet().length != dependents.fold(0, (count, replacement) => count + replacement.uses.length)) {
    throw ArgumentError('Appearance expansions require distinct current artwork handles.');
  }
  if (selected.any((use) => !appearance.uses.contains(use) || !identical(model.resolve(use: use), appearance))) {
    throw UnsupportedError('Each supplied expansion must belong to a uniquely bound user of the selected style.');
  }
  final List<AiNativeAppearanceArtwork> retained = _nativeRetainedAppearanceArtwork(model);
  final List<AiNativeResourceUse> owners = all.map((replacement) => replacement.artwork.use).toList();
  final bool resourceEdit = replacements.any((replacement) => replacement.artwork.resource != null);
  if (!resourceEdit && dependents.isNotEmpty) {
    throw ArgumentError('Dependent expansions require a selected resource appearance.');
  }
  final Set<String> patterns = resourceEdit || nameBytes == null
      ? model.styles.any((style) => _nativeAppearancePatternPaints(style).isNotEmpty)
            ? model._patternNames
            : const {}
      : _nativeAppearancePatterns(model, appearance);
  final Map<AiNativeResourceUse, Set<String>> affected;
  if (nameBytes == null || resourceEdit) {
    final _ArtboardResourceScope resources = _artboardResourceScope(layers);
    final _ArtboardBrushScope brushes = _artboardBrushScope(layers, resources.brushes);
    final Map<int, AiNativeLayer> headers = _layerHeaderItems(layers);
    _nativeReferenceScope(
      layers,
      headers,
      bodyDictionaries: _nativeReferenceBody(layers, headers, inspect: _nativeAppearanceInterval, qualifyShapeNeighbors: false, clipping: true, appearanceArtwork: retained, patterns: patterns),
      retainedResources: resources,
      retainedBrushes: brushes,
    );
    affected = resourceEdit ? _nativeAppearanceDependents(model, replacements, dependents, brushes) : {};
  } else {
    affected = {};
  }
  final List<AiSourceEdit> edits = _nativeAppearancePrintingEdits(model, all);
  if (nameBytes == null) {
    if (appearance.uses.length != selected.length || appearance.uses.any((use) => !selected.contains(use))) {
      throw UnsupportedError('A shared appearance change must cover every source use and its printing owner.');
    }
    edits.addAll(styleEdits);
  } else {
    if (replacements.isEmpty ||
        nameBytes.isEmpty ||
        model.styles.any((style) => _sameNativeBytes(style.resource.nameBytes, nameBytes)) ||
        model.uses.any((use) => _sameNativeBytes(use.nameBytes, nameBytes))) {
      throw ArgumentError('Selected appearance editing requires users and a fresh nonempty style name.');
    }
    final List<int> encoded = _nativeLiteralString(nameBytes, program.limits.maxDecodedBytes);
    final AiNativeEntry naming = declaration['Name']!;
    final Uint8List copy = AiNativeEditor.copyRange(
      program: program,
      start: declaration.start,
      end: declaration.end,
      edits: [
        ...styleEdits,
        AiSourceEdit(start: naming.items.single.start, end: naming.items.single.end, bytes: encoded),
      ],
    );
    edits.add(
      AiSourceEdit(
        start: declaration.end,
        end: declaration.end,
        bytes: [
          10,
          if (drawing.records._projection.isPrivate(declaration.start)) ...[37, 95],
          ...copy,
          10,
        ],
      ),
    );
    for (final AiNativeResourceUse use in selected) {
      edits.add(AiSourceEdit(start: use.name.start, end: use.name.end, bytes: encoded));
    }
  }
  final Set<String> changedState = {
    for (final AiNativePaintChange change in paints)
      if (change.assignment.gradient case final AiNativeGradient gradient)
        if (gradient.onStroke) 'stroke' else 'fill'
      else if (_nativeArtworkStateKey(change.assignment.instruction) case final String key)
        key
      else
        ...state.writes,
    if (parts.isNotEmpty) ...{...state.writes, 'XR'},
  };
  final AiNativeAppearances updated = _nativeAppearanceResult(model, edits, owners);
  final AiNativeAppearance changed = updated.styles.singleWhere((style) => _sameNativeBytes(style.resource.nameBytes, nameBytes ?? appearance.resource.nameBytes));
  final ({Set<String> reads, Set<String> writes}) next = _nativeAppearanceStyleState(updated, changed);
  if (parts.any((change) => change.children != null)) {
    changedState.addAll(next.writes);
    final Map<String, AiNativeInstruction> before = _nativeAppearanceScalarState(appearance, state.reads);
    final Map<String, AiNativeInstruction> after = _nativeAppearanceScalarState(changed, next.reads);
    changedState.removeWhere((key) => before.containsKey(key) && after.containsKey(key) && _sameNativeArtworkState(before[key], after[key]));
  } else if (paints.isEmpty) {
    changedState.removeAll(_nativeAppearanceOrderState(appearance, parts, state.reads));
  }

  final Map<AiNativeArtworkResource?, List<AiNativeAppearanceReplacement>> contexts = {};
  for (final AiNativeAppearanceReplacement replacement in all) {
    (contexts[replacement.artwork.resource] ??= []).add(replacement);
  }

  /// Checks each local execution interval and restores resource boundary state.
  void following(Map<String, AiNativeInstruction> restored) {
    for (final MapEntry<AiNativeArtworkResource?, List<AiNativeAppearanceReplacement>> context in contexts.entries) {
      final AiNativeArtworkResource? resource = context.key;
      _sourceFollowingDependencies(
        resource?._drawing ?? drawing,
        {
          for (final AiNativeAppearanceReplacement replacement in context.value)
            (start: replacement.artwork.start, end: replacement.artwork.end): (
              commands: replacement.artwork._commands,
              styles: {
                ...replacement.artwork._styleReads,
                for (final AiNativeResourceUse use in replacement.uses.where(selected.contains)) use.instruction.end: {...state.reads, ...next.reads},
              },
              prefix: [],
              suffix: [],
              unresolved: {},
              printingUnresolved: {},
              discard: false,
            ),
        },
        retainedArtwork: resource == null ? retained : _nativeRetainedAppearanceArtwork(model, resource: resource),
        clipping: true,
        styleChanges: {
          for (final AiNativeResourceUse use in {...selected, ...affected.keys}) use.instruction.end: {...?affected[use], if (selected.contains(use)) ...changedState},
        },
        styleRestorations: {for (final AiNativeResourceUse use in selected) use.instruction.end: restored},
        document: layers,
        resource: resource,
        patterns: patterns,
      );
    }
  }

  try {
    following(const {});
    return updated;
  } on UnsupportedError {
    final Map<String, AiNativeInstruction> restored = _nativeAppearanceScalarState(appearance, state.reads, colors: true)..removeWhere((key, _) => !changedState.contains(key));
    if (restored.isEmpty) {
      rethrow;
    }
    following(restored);
    final List<int> suffix = latin1.encode('\n${restored.values.map((value) => _shapeStateText(value, private: true)).join()}');
    return _nativeAppearanceResult(model, [
      ...edits,
      for (final AiNativeResourceUse use in selected) AiSourceEdit(start: use.instruction.end, end: use.instruction.end, bytes: suffix),
    ], owners);
  }
}

/// Rebinds supplied owners after bounded serialization, including state replays.
AiNativeAppearances _nativeAppearanceResult(AiNativeAppearances model, List<AiSourceEdit> edits, List<AiNativeResourceUse> owners) {
  final AiNativeDrawing drawing = model.structure.drawing;
  if (drawing.records.program.bytes.length + edits.fold<int>(0, (size, edit) => size + edit.bytes.length - (edit.end - edit.start)) > drawing.records.program.limits.maxDecodedBytes) {
    throw const AiLimitException(message: 'Appearance transaction exceeds the native byte limit.');
  }
  final AiNativeDrawing result = AiNativeDrawing.decode(
    records: AiNativeRecords.decode(
      program: AiNativeEditor.apply(program: drawing.records.program, edits: edits),
    ),
  );
  if (result.liveShapes.length != drawing.liveShapes.length || result.liveShapes.indexed.any((entry) => drawing.liveShapes[entry.$1].isBound && !entry.$2.isBound)) {
    throw const FormatException('Appearance changes disrupted native authoring or printing ownership.');
  }
  final AiNativeAppearances updated = AiNativeAppearances.decode(structure: AiNativeStructure.decode(drawing: result));
  if (updated.uses.length != model.uses.length) {
    throw const FormatException('Appearance changes disrupted named source ownership.');
  }
  for (final AiNativeResourceUse use in owners) {
    updated.artworkFor(use: updated.uses[model.uses.indexOf(use)]);
  }
  return updated;
}

/// Discovers qualified ordinary pairs without requiring unrelated opaque users.
///
/// Unqualified owners remain in the intervening source: dependency inspection
/// rejects them if unresolved state reaches them, and shared scope always checks
/// them. They are never silently counted as covered or safe to edit.
List<AiNativeAppearanceArtwork> _nativeRetainedAppearanceArtwork(AiNativeAppearances model, {AiNativeArtworkResource? resource}) {
  final AiNativeDrawing drawing = resource?._drawing ?? model.structure.drawing;
  final Set<int> shapes = drawing.liveShapes.map((shape) => shape.end).toSet();
  final List<AiNativeAppearanceArtwork> result = [];
  for (final AiNativeResourceUse use in model.uses.where(
    (use) =>
        use.instruction.start >= (resource?.artworkStart ?? drawing.records.program.bodyStart) &&
        use.instruction.end <= (resource?.artworkEnd ?? drawing.records.program.bodyEnd) &&
        !shapes.contains(use.instruction.end),
  )) {
    try {
      result.add(model.artworkFor(use: use));
    } on UnsupportedError {
      // The source interval remains unqualified for the dependency/scope pass.
    }
  }
  return result;
}

/// Binds every change to an exact selected field before writing numeric tokens.
List<AiSourceEdit> _nativeAppearanceChanges(AiNativeAppearances model, AiNativeAppearance appearance, List<AiNativePaintChange> paints, List<AiNativeAppearancePartChange> parts) {
  final Set<AiNativePaintAssignment> owned = {
    for (final AiNativePaintStyle paint in [?appearance.simplePaint, for (final AiNativeAppearancePart part in appearance.parts) ...part.paints.map((paint) => paint.style)]) ...paint.assignments,
  };
  if (paints.map((change) => change.assignment).toSet().length != paints.length ||
      paints.any((change) => !owned.contains(change.assignment)) ||
      parts.map((change) => change.part).toSet().length != parts.length ||
      parts.any((change) => !appearance.parts.contains(change.part))) {
    throw ArgumentError('Appearance changes require distinct owned assignments and part handles.');
  }
  final List<AiSourceEdit> edits = [];
  int tokens = 0;
  for (final AiNativePaintChange change in paints) {
    tokens += change.values.length + (change.dashPhase == null ? 1 : 4);
    if (tokens > model.structure.drawing.records.program.limits.maxTokens) {
      throw const AiLimitException(message: 'The appearance change batch exceeds native token limits.');
    }
    edits.addAll(_nativeAppearancePaintEdits(change, model.structure.drawing.records));
  }
  for (final AiNativeAppearancePartChange change in parts) {
    final AiNativeAppearancePart part = change.part;

    /// Requires an explicit source flag instead of inserting an inherited value.
    void flag(AiNativeEntry? field, bool? current, bool value) {
      if (field == null || current == null || field.items.length != 1 || field.items.single is! AiNativeToken) {
        throw UnsupportedError('Appearance flag editing requires an explicitly saved qualified setting.');
      }
      edits.add(AiSourceEdit(start: field.items.single.start, end: field.items.single.end, bytes: [if (value) 49 else 48]));
    }

    if (change.visible case final bool value) {
      flag(part.record['Visible'], part.visible, value);
    }
    if (change.evenOdd case final bool value) {
      flag(part.parameters?['UseEvenOdd'], part.evenOdd, value);
    }
    if (change.adjustDashes case final bool value) {
      final AiNativeStrokeSettings? settings = part.strokeSettings;
      if (settings?.version != 1) {
        throw UnsupportedError('Dash adjustment requires an existing version-one stroke settings owner.');
      }
      flag(settings!.record['BSDashAdj'], settings.adjustDashes, value);
    }
    if (change.strokeAlignment case final AiNativeStrokeAlignment alignment) {
      if (part.kind != .strokeOffset || alignment == .center) {
        throw UnsupportedError('Alignment changes require an existing native inside/outside stroke descriptor.');
      }
      final AiNativeEntry? label = part.parameters?['DisplayString'];
      if ((label != null) != (change.alignmentLabelBytes != null)) {
        throw UnsupportedError('Alignment changes require a supplied label exactly when the source has a saved DisplayString.');
      }
      if (label != null) {
        if (label.items.length != 1 || label.stringBytes == null) {
          throw UnsupportedError('An alignment label requires one owned literal string.');
        }
        edits.add(
          AiSourceEdit(
            start: label.items.single.start,
            end: label.items.single.end,
            bytes: _nativeLiteralString(change.alignmentLabelBytes!, model.structure.drawing.records.program.limits.maxDecodedBytes),
          ),
        );
      }
      flag(part.parameters?['StrokeOffsetInside'], part.strokeAlignment == null ? null : part.strokeAlignment == .inside, alignment == .inside);
    }
  }
  if (parts.any((change) => change.children != null)) {
    return _NativeAppearanceGraphEditor(
      appearance: appearance,
      records: model.structure.drawing.records,
      changes: {for (final AiNativeAppearancePartChange change in parts) change.part: change},
      scalarEdits: edits,
    ).build();
  }
  return _nativeAppearanceOrderEdits(model, appearance, parts, edits);
}

/// Reuses the literal operand grammar and retains comments between source tokens.
List<AiSourceEdit> _nativeAppearancePaintEdits(AiNativePaintChange change, AiNativeRecords records) {
  final AiNativeLimits limits = records.program.limits;
  if (change.namedColor case final AiNativeNamedColor color) {
    final AiNativeInstruction source = change.assignment.instruction;
    return [
      for (final (int index, AiToken token) in source.operands.take(color.components.length).indexed)
        AiSourceEdit(start: token.start, end: token.end, bytes: latin1.encode('${color.components[index]}')),
      AiSourceEdit(start: source.operands[color.components.length + 1].start, end: source.operands[color.components.length + 1].end, bytes: latin1.encode('${color.tint}')),
    ];
  }
  if (change.gradientDefinition case final AiNativeGradientDefinition target) {
    return _nativeGradientApplicationEdits(records, change.assignment.gradient!, target);
  }
  if (change.values.length + 5 > limits.maxTokens || change.values.length > limits.maxDecodedBytes ~/ 2) {
    throw const AiLimitException(message: 'Replacement paint operands exceed native limits.');
  }
  final AiNativeInstruction instruction = change.assignment.instruction;
  final bool dash = change.assignment.parameter == .dash;
  final List<AiToken> values = [
    for (final double value in change.values) AiToken(kind: .number, start: 0, end: 0, lexeme: value.toString()),
  ];
  final AiNativeInstruction candidate = AiNativeInstruction._(
    token: instruction.token,
    operands: dash
        ? [instruction.operands.first, ...values, instruction.operands[instruction.operands.length - 2], AiToken(kind: .number, start: 0, end: 0, lexeme: change.dashPhase.toString())]
        : values,
    isPrivate: instruction.isPrivate,
  );
  _nativePaintAssignments([candidate]);
  final List<AiToken> original = dash ? instruction.operands.sublist(1, instruction.operands.length - 2) : instruction.operands;
  final List<AiSourceEdit> edits = [
    for (final (int, AiToken) operand in original.indexed)
      AiSourceEdit(start: operand.$2.start, end: operand.$2.end, bytes: operand.$1 < values.length ? latin1.encode(values[operand.$1].lexeme) : []),
  ];
  if (dash) {
    if (values.length > original.length) {
      final int insertion = instruction.operands[instruction.operands.length - 2].start;
      edits.add(AiSourceEdit(start: insertion, end: insertion, bytes: latin1.encode(' ${values.skip(original.length).map((value) => value.lexeme).join(' ')} ')));
    }
    edits.add(AiSourceEdit(start: instruction.operands.last.start, end: instruction.operands.last.end, bytes: latin1.encode(change.dashPhase.toString())));
  }
  return edits;
}
