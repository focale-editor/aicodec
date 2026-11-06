part of 'package:illustratorkit/src/model/ai_native_records.dart';

/// Attaches named paints to private children without replacing their identities.
AiNativeAppearances _applyNativeAppearanceChildStyle(
  AiNativeAppearances model,
  AiNativeAppearance appearance,
  List<AiNativePath> paths,
  List<AiNativeAppearanceReplacement> artwork,
) {
  if (!model.styles.contains(appearance) || paths.isEmpty || paths.toSet().length != paths.length) {
    throw ArgumentError('Child styles require a current definition and distinct current contours.');
  }
  final List<AiNativeAppearanceArtwork> owners = _selectedBodyAppearanceArtwork(model, artwork.map((replacement) => replacement.artwork).toList());
  if (appearance.resource.versions.isNotEmpty ||
      model.styles.where((style) => _sameNativeBytes(style.resource.nameBytes, appearance.resource.nameBytes)).length != 1 ||
      owners.any((owner) => owner.group == null || owner.liveShape != null) ||
      artwork.any((replacement) => replacement.uses.length != 1 || !identical(replacement.uses.single, replacement.artwork.use))) {
    throw UnsupportedError('Child style attachment requires unique unconditional styles and complete ordinary group owners.');
  }
  final Map<AiNativePath, AiNativeAppearanceArtwork> selected = {};
  for (final AiNativeAppearanceArtwork owner in owners) {
    final List<AiNativePathTopology> contours = owner.groupContours.where((contour) => paths.contains(contour.path)).toList();
    if (contours.isEmpty) {
      throw ArgumentError('Every supplied printing owner must cover a selected private contour.');
    }
    for (final AiNativePathTopology contour in contours) {
      if (contour.compound != null || contour.mask != .none || owner.nestedUses.any((use) => identical(owner.authoringFor(use: use), contour.path))) {
        throw UnsupportedError('Compound, clipping and already styled contours require their own appearance transaction.');
      }
      selected[contour.path] = owner;
    }
  }
  if (paths.any((path) => !path.isPrivate || !selected.containsKey(path))) {
    throw ArgumentError('Every styled contour must belong to a supplied current private group.');
  }
  final AiNativeDrawing drawing = model.structure.drawing;
  final List<AiNativeAppearanceArtwork> retained = _nativeBodyAppearanceArtwork(model);
  final ({Set<String> reads, Set<String> writes}) style = _nativeAppearanceStyleState(model, appearance);
  final Map<int, _NativeShapeInputs> states = _shapeCopyInputs(drawing, paths.map((path) => path.end), clipping: true, appearanceArtwork: retained);
  final Map<AiNativePath, _NativePrivatePathStateChange> changes = {};
  final Map<AiNativePath, int> positions = {};
  final List<AiSourceEdit> edits = _nativeAppearancePrintingEdits(model, artwork);
  int remaining = drawing.records.program.limits.maxDecodedBytes - edits.fold(0, (sum, edit) => sum + edit.bytes.length);
  final List<int> name = _nativeLiteralString(appearance.resource.nameBytes, drawing.records.program.limits.maxDecodedBytes);
  for (final AiNativePath path in paths) {
    final Map<String, AiNativeInstruction> original = states[path.end]!.native;
    if (!original.keys.toSet().containsAll(style.reads)) {
      throw UnsupportedError('The child style requires unresolved inherited native inputs.');
    }
    final int position = drawing._objects.forSource(path).dictionary?.end ?? path.end;
    positions[path] = position;
    final _NativeDocumentBytes bytes = _NativeDocumentBytes(maximum: remaining);
    bytes.text('\n%_0 ');
    bytes.add(name);
    bytes.text(' XW\n');
    for (final String key in style.writes.where(original.containsKey)) {
      bytes.text(_shapeStateText(original[key]!, private: true));
    }
    // The final private prefix also protects commands sharing the source line.
    bytes.text('%_');
    final Uint8List inserted = bytes.takeBytes();
    remaining -= inserted.length + 1;
    if (remaining < 0) {
      throw const AiLimitException(message: 'Child style attachment exceeds aggregate output limits.');
    }
    edits.add(AiSourceEdit(start: path.paint.start, end: path.paint.end, bytes: ascii.encode(path.closed ? 'n' : 'N')));
    edits.add(AiSourceEdit(start: position, end: position, bytes: inserted));
    changes[path] = (writes: {}, reads: {..._nativeContourFlags, ...style.reads}, unresolved: style.writes.difference(original.keys.toSet()));
  }
  _sourceFollowingDependencies(
    drawing,
    {
      for (final AiNativeAppearanceArtwork owner in owners)
        (start: owner.start, end: owner.end): (commands: owner._commands, styles: owner._styleReads, prefix: [], suffix: [], unresolved: {}, printingUnresolved: {}, discard: false),
    },
    retainedArtwork: retained,
    clipping: true,
    pathChanges: changes,
    patterns: _nativeAppearancePatterns(model, appearance),
  );
  final AiNativeDrawing result = AiNativeDrawing.decode(
    records: AiNativeRecords.decode(
      program: AiNativeEditor.apply(program: drawing.records.program, edits: edits),
    ),
  );
  final AiNativeAppearances updated = AiNativeAppearances.decode(structure: AiNativeStructure.decode(drawing: result));
  if (updated.uses.length != model.uses.length + paths.length ||
      updated.styles.length != model.styles.length ||
      updated.structure.identifiers.length != model.structure.identifiers.length ||
      result.liveShapes.length != drawing.liveShapes.length) {
    throw const FormatException('Child style attachment changed unrelated native ownership.');
  }

  /// Rebinds old applications after newly inserted private uses enter source order.
  AiNativeResourceUse retainedUse(AiNativeResourceUse use) => updated.uses[model.uses.indexOf(use) + positions.values.where((position) => position <= use.instruction.start).length];

  for (final AiNativeResourceUse use in model.uses) {
    final AiNativeResourceUse after = retainedUse(use);
    if (!_sameNativeBytes(use.nameBytes, after.nameBytes) ||
        use.instruction.isPrivate != after.instruction.isPrivate ||
        use.instruction.operands.first.number != after.instruction.operands.first.number) {
      throw const FormatException('Child style attachment changed a retained application.');
    }
  }
  for (final AiNativeAppearanceArtwork owner in owners) {
    final AiNativeAppearanceArtwork after = updated.artworkFor(use: retainedUse(owner.use));
    final List<AiNativePath> children = paths.where((path) => identical(selected[path], owner)).toList();
    if (after.groupContours.length != owner.groupContours.length || after.nestedUses.length != owner.nestedUses.length + children.length || after.opacityMasks.length != owner.opacityMasks.length) {
      throw const FormatException('Child style attachment changed private contour or mask ownership.');
    }
    for (final AiNativePath path in children) {
      final AiNativePath child = after.groupContours[owner.groupContours.indexWhere((contour) => identical(contour.path, path))].path;
      final AiNativeResourceUse use = after.nestedUses.singleWhere((use) => identical(after.authoringFor(use: use), child));
      if (!const {'n', 'N'}.contains(child.paint.operator) || !_sameNativeBytes(use.nameBytes, appearance.resource.nameBytes)) {
        throw const FormatException('The named child lost its authoritative unpainted contour.');
      }
    }
  }
  return updated;
}
