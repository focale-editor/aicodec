part of 'package:aikit/src/model/ai_native_records.dart';

/// Changes selected native fields and their supplied expansions in one snapshot.
AiNativeAppearances _editNativeAppearance(
  AiNativeAppearances model,
  AiNativeAppearance appearance,
  List<AiNativePaintChange> paints,
  List<AiNativeAppearancePartChange> parts,
  List<AiNativePrintingGroupReplacement> printing,
  List<AiNativeAppearanceReplacement> artwork,
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
  _artboardRetainedStyle(layers, declaration, {for (final AiNativeResourceUse use in model.structure.resourceUses) use.instruction.start: use}, {}, {});
  final ({Set<String> reads, Set<String> writes}) state = _nativeLiteralStyleState(drawing, declaration);
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
  final List<AiNativeResourceUse> selected = replacements.map((replacement) => replacement.artwork.use).toList();
  if (selected.toSet().length != selected.length || replacements.any((replacement) => !identical(replacement.artwork._owner, model))) {
    throw ArgumentError('Appearance expansions require distinct current artwork handles.');
  }
  if (selected.any((use) => !appearance.uses.contains(use) || !identical(model.resolve(use: use), appearance))) {
    throw UnsupportedError('Each supplied expansion must belong to a uniquely bound user of the selected style.');
  }
  final List<AiNativeAppearanceArtwork> retained = _nativeRetainedAppearanceArtwork(model);
  final List<AiSourceEdit> edits = [
    if (replacements.isNotEmpty)
      ..._nativePrintingSourceEdits(drawing, [
        for (final AiNativeAppearanceReplacement replacement in replacements) (group: replacement.artwork.printingGroup, bytes: replacement.bytes, bounds: replacement.bounds),
      ]),
  ];
  if (nameBytes == null) {
    if (appearance.uses.length != selected.length || appearance.uses.any((use) => !selected.contains(use))) {
      throw UnsupportedError('A shared appearance change must cover every source use and its printing owner.');
    }
    // The known-use inventory cannot establish that opaque owners have no links.
    final _ArtboardResourceScope resources = _artboardResourceScope(layers);
    final _ArtboardBrushScope brushes = _artboardBrushScope(layers, resources.brushes);
    _nativeReferenceScope(layers, _layerHeaderItems(layers), retainedResources: resources, retainedBrushes: brushes, appearanceArtwork: retained);
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
      if (_nativeArtworkStateKey(change.assignment.instruction) case final String key) key else ...state.writes,
    if (parts.isNotEmpty) ...{...state.writes, 'XR'},
  };
  final AiNativeDrawing result = AiNativeDrawing.decode(
    records: AiNativeRecords.decode(
      program: AiNativeEditor.apply(program: program, edits: edits),
    ),
  );
  if (result.liveShapes.length != drawing.liveShapes.length || result.liveShapes.indexed.any((entry) => drawing.liveShapes[entry.$1].isBound && !entry.$2.isBound)) {
    throw const FormatException('Appearance changes disrupted native authoring or printing ownership.');
  }
  final AiNativeAppearances updated = AiNativeAppearances.decode(structure: AiNativeStructure.decode(drawing: result));
  if (parts.any((change) => change.children != null)) {
    final AiNativeAppearance changed = updated.styles.singleWhere((style) => _sameNativeBytes(style.resource.nameBytes, nameBytes ?? appearance.resource.nameBytes));
    final ({Set<String> reads, Set<String> writes}) next = _nativeLiteralStyleState(result, changed.resource.definition.source as AiNativeContainer);
    changedState.addAll(next.writes);
    final Map<String, AiNativeInstruction> before = _nativeAppearanceScalarState(appearance, state.reads);
    final Map<String, AiNativeInstruction> after = _nativeAppearanceScalarState(changed, next.reads);
    changedState.removeWhere((key) => before.containsKey(key) && after.containsKey(key) && _sameNativeArtworkState(before[key], after[key]));
  } else if (paints.isEmpty) {
    changedState.removeAll(_nativeAppearanceOrderState(appearance, parts, state.reads));
  }
  if (updated.uses.length != model.uses.length) {
    throw const FormatException('Appearance changes disrupted named source ownership.');
  }
  for (final AiNativeResourceUse use in selected) {
    updated.artworkFor(use: updated.uses[model.uses.indexOf(use)]);
  }
  _sourceFollowingDependencies(drawing, {
    for (final AiNativeAppearanceReplacement replacement in replacements)
      (start: replacement.artwork.start, end: replacement.artwork.end): (
        commands: replacement.artwork._commands,
        styles: {replacement.artwork.end: replacement.artwork._styleReads},
        prefix: [],
        suffix: [],
        unresolved: changedState,
        printingUnresolved: {},
        discard: false,
      ),
  }, retainedArtwork: retained);
  return updated;
}

/// Discovers qualified ordinary pairs without requiring unrelated opaque users.
///
/// Unqualified owners remain in the intervening source: dependency inspection
/// rejects them if unresolved state reaches them, and shared scope always checks
/// them. They are never silently counted as covered or safe to edit.
List<AiNativeAppearanceArtwork> _nativeRetainedAppearanceArtwork(AiNativeAppearances model) {
  final AiNativeDrawing drawing = model.structure.drawing;
  final Set<int> shapes = drawing.liveShapes.map((shape) => shape.end).toSet();
  final List<AiNativeAppearanceArtwork> result = [];
  for (final AiNativeResourceUse use in model.uses.where(
    (use) => use.instruction.start >= drawing.records.program.bodyStart && use.instruction.end <= drawing.records.program.bodyEnd && !shapes.contains(use.instruction.end),
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
    edits.addAll(_nativeAppearancePaintEdits(change, model.structure.drawing.records.program.limits));
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
List<AiSourceEdit> _nativeAppearancePaintEdits(AiNativePaintChange change, AiNativeLimits limits) {
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
