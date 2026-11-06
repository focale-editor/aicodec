part of 'package:illustratorkit/src/model/ai_native_records.dart';

/// Changes private contours together with each complete supplied printing owner.
AiNativeAppearances _editNativeAppearancePaths(
  AiNativeAppearances model,
  List<AiNativePathEdit> changes,
  List<AiNativeAppearanceReplacement> artwork,
  Map<AiNativeItem, double> frameAngles,
) {
  if (changes.isEmpty || changes.map((change) => change.path).toSet().length != changes.length || changes.any((change) => change.segments == null || change.mask != null)) {
    throw ArgumentError('Appearance geometry requires distinct complete contour changes without mask-role changes.');
  }
  final List<AiNativeAppearanceArtwork> owners = _selectedBodyAppearanceArtwork(model, artwork.map((replacement) => replacement.artwork).toList());
  if (artwork.any((replacement) => replacement.uses.length != 1 || !identical(replacement.uses.single, replacement.artwork.use)) || owners.any((owner) => owner.liveShape != null)) {
    throw UnsupportedError('Appearance geometry requires complete ordinary authoring owners; live shapes retain their parameter contract.');
  }
  final AiNativeDrawing drawing = model.structure.drawing;
  final Map<AiNativePath, AiNativeAppearanceArtwork> paths = {};
  final Map<AiNativePath, AiNativeInstruction?> counts = {};
  final Map<AiNativePath, bool> closed = {};
  final Set<AiNativeItem> frameTargets = {};
  for (final AiNativeAppearanceArtwork owner in owners) {
    frameTargets.addAll(drawing.groups.where((group) => group.start >= owner.authoring.start && group.end <= owner.authoring.end));
    if (owner.path case final AiNativePath path) {
      paths[path] = owner;
      counts[path] = owner._commands.where((command) => command.isPrivate && command.operator == 'As' && command.end < path.start).singleOrNull;
      closed[path] = path.closed;
    }
    for (final AiNativePathTopology contour in owner.groupContours) {
      paths[contour.path] = owner;
      counts[contour.path] = contour.pointCount;
      closed[contour.path] = contour.path.closed || contour.mask == .closed;
    }
    if (!changes.any((change) => identical(paths[change.path], owner))) {
      throw ArgumentError('Every supplied printing owner must cover a selected authoring contour.');
    }
  }
  frameTargets.addAll(paths.keys);
  if (frameAngles.keys.any((item) => !frameTargets.contains(item))) {
    throw ArgumentError('Frame changes require current authoring paths or groups inside supplied appearance owners.');
  }
  if (changes.any((change) => !change.path.isPrivate || !paths.containsKey(change.path))) {
    throw ArgumentError('Every changed path requires its current complete private appearance owner.');
  }
  final List<AiSourceEdit> edits = _nativeAppearancePrintingEdits(model, artwork);
  int remaining = drawing.records.program.limits.maxDecodedBytes - edits.fold(0, (sum, edit) => sum + edit.bytes.length);
  for (final AiNativePathEdit change in changes) {
    final AiNativePath path = change.path;
    final List<AiSourceEdit> geometry = _replaceShapeContour(drawing, path, counts[path], change.segments!, remaining, closed: closed[path]);
    remaining -= geometry.fold(0, (sum, edit) => sum + edit.bytes.length);
    edits.addAll(geometry);
    if (remaining < 0) {
      throw const AiLimitException(message: 'Appearance geometry exceeds the aggregate native output limit.');
    }
  }
  for (final MapEntry<AiNativeItem, double> frame in frameAngles.entries) {
    final double angle = frame.value;
    if (!angle.isFinite || angle.abs() > 2 * pi) {
      throw ArgumentError('Native frame angles must lie in -2π..2π.');
    }
    final List<AiSourceEdit> values = _nativeFrameRotationEdits(drawing.records, drawing._objects.forSource(frame.key).dictionary, frame.key.end, angle);
    remaining -= values.fold(0, (sum, edit) => sum + edit.bytes.length);
    if (remaining < 0) {
      throw const AiLimitException(message: 'Appearance frame changes exceed the aggregate native output limit.');
    }
    edits.addAll(values);
  }
  final AiNativeAppearances result = _nativeAppearanceResult(model, edits, owners.map((owner) => owner.use).toList());
  for (final AiNativeAppearanceArtwork owner in owners) {
    final AiNativeAppearanceArtwork after = result.artworkFor(use: result.uses[model.uses.indexOf(owner.use)]);
    if ((owner.path == null) != (after.path == null) || owner.groupContours.length != after.groupContours.length || owner.nestedUses.length != after.nestedUses.length) {
      throw const FormatException('Appearance geometry changed private authoring ownership.');
    }
  }
  return result;
}

/// Changes independently styled contours while retaining masks and boundary state.
AiNativeAppearances _replaceNativeAppearanceContours(
  AiNativeAppearances model,
  List<AiNativeAppearanceContourChange> changes,
  List<AiNativeAppearanceReplacement> artwork,
) {
  if (changes.isEmpty || changes.map((change) => change.path).toSet().length != changes.length) {
    throw ArgumentError('Standalone contour changes require distinct current paths.');
  }
  final List<AiNativeAppearanceArtwork> owners = _selectedBodyAppearanceArtwork(model, artwork.map((replacement) => replacement.artwork).toList());
  if (owners.any((owner) => owner.liveShape != null) || artwork.any((replacement) => replacement.uses.length != 1 || !identical(replacement.uses.single, replacement.artwork.use))) {
    throw ArgumentError('Styled contours require complete current body owners.');
  }
  final Map<AiNativePath, AiNativeAppearanceArtwork> targets = {};
  final Map<AiNativePath, AiNativeResourceUse> uses = {};
  final Map<AiNativePath, AiNativeInstruction?> counts = {};
  for (final AiNativeAppearanceArtwork owner in owners) {
    if (owner.path case final AiNativePath path) {
      targets[path] = owner;
      uses[path] = owner.use;
      counts[path] = owner._commands.where((command) => command.isPrivate && command.operator == 'As' && command.end < path.start).singleOrNull;
    }
    for (final AiNativePathTopology contour in owner.groupContours) {
      final List<AiNativeResourceUse> styles = owner.nestedUses.where((use) => identical(owner.authoringFor(use: use), contour.path)).toList();
      if (contour.compound == null && contour.mask == .none && styles.length == 1 && const {'n', 'N'}.contains(contour.path.paint.operator)) {
        targets[contour.path] = owner;
        uses[contour.path] = styles.single;
        counts[contour.path] = contour.pointCount;
      }
    }
    if (!changes.any((change) => identical(targets[change.path], owner))) {
      throw ArgumentError('Every printing owner must cover a selected styled contour.');
    }
  }
  if (changes.any((change) => !targets.containsKey(change.path))) {
    throw ArgumentError('Contour changes require independently styled current private paths.');
  }
  final AiNativeDrawing drawing = model.structure.drawing;
  final List<AiNativeAppearanceArtwork> retained = _nativeBodyAppearanceArtwork(model);
  final Map<int, _NativeShapeInputs> states = _shapeCopyInputs(
    drawing,
    [
      ...owners.expand((owner) => [owner.printingGroup.end, owner.end]),
      ...uses.values.map((use) => use.instruction.end),
    ],
    clipping: true,
    appearanceArtwork: retained,
  );
  final List<AiSourceEdit> edits = _nativeAppearancePrintingEdits(model, artwork);
  int remaining = drawing.records.program.limits.maxDecodedBytes - edits.fold(0, (sum, edit) => sum + edit.bytes.length);

  /// Charges geometry and flag fragments before publishing an immutable result.
  void add(AiSourceEdit edit) {
    remaining -= edit.bytes.length;
    if (remaining < 0) {
      throw const AiLimitException(message: 'Standalone contour replacement exceeds aggregate output limits.');
    }
    edits.add(edit);
  }

  for (final AiNativeAppearanceContourChange change in changes) {
    final AiNativeAppearanceArtwork owner = targets[change.path]!;
    final AiNativeResourceUse use = uses[change.path]!;
    final ({Set<String> reads, Set<String> writes}) style = _nativeAppearanceStyleState(model, model.resolve(use: use)!);
    const Set<String> flags = {'A', 'Xw'};
    if (style.reads.intersection(flags).isNotEmpty || style.writes.intersection(flags).isNotEmpty) {
      throw UnsupportedError('Standalone contour flags require a style independent of visibility and locking state.');
    }
    final Map<String, AiNativeInstruction> native = states[use.instruction.end]!.native;
    final Map<String, AiNativeInstruction> printing = states[owner.printingGroup.end]!.printing;
    if (!native.keys.toSet().containsAll(flags) || owner.path != null && !printing.keys.toSet().containsAll(flags)) {
      throw UnsupportedError('Standalone contour flags require proven native and printing restoration values.');
    }
    final String prefix = '${change.locked ? 1 : 0} A ${change.hidden ? 1 : 0} Xw ';
    final AiNativeInstruction? count = counts[change.path];
    for (final AiSourceEdit edit in _replaceShapeContour(drawing, change.path, count, change.segments, remaining, closed: change.closed)) {
      add(edit.start == change.path.geometry.first.start ? AiSourceEdit(start: edit.start, end: edit.end, bytes: [...latin1.encode(prefix), ...edit.bytes]) : edit);
    }
    add(AiSourceEdit(start: change.path.paint.start, end: change.path.paint.end, bytes: ascii.encode(change.closed ? 'n' : 'N')));

    if (owner.path == null) {
      // The host printing belongs to the entire group. Only this child's native
      // flags change; restore them after its style and before the next sibling.
      add(AiSourceEdit(start: use.instruction.end, end: use.instruction.end, bytes: latin1.encode('\n${flags.map((key) => _shapeStateText(native[key]!, private: true)).join()}%_')));
      continue;
    }

    // Keep the printing dictionary adjacent to its group and the authoring
    // dictionary adjacent to its contour. Restorations live past those owners.
    final int printingIndex = edits.indexWhere((edit) => edit.start == owner.printingGroup.start && edit.end == owner.printingGroup.end);
    if (printingIndex < 0) {
      throw StateError('A complete contour transaction lost its printing replacement.');
    }
    final AiSourceEdit previous = edits[printingIndex];
    final String printingRestore = '\n${flags.map((key) => _shapeStateText(printing[key]!, private: false)).join()}';
    final List<int> printingPrefix = latin1.encode('$prefix\n');
    final bool expansion = owner.start < owner.printingGroup.start;
    if (expansion) {
      add(AiSourceEdit(start: owner.start, end: owner.start, bytes: printingPrefix));
    } else {
      remaining -= printingPrefix.length;
    }
    edits[printingIndex] = AiSourceEdit(
      start: previous.start,
      end: previous.end,
      bytes: [
        if (!expansion) ...printingPrefix,
        ...previous.bytes,
        if (owner.printingDictionary == null) ...latin1.encode(printingRestore),
      ],
    );
    if (owner.printingDictionary == null) {
      remaining -= printingRestore.length;
    } else {
      add(AiSourceEdit(start: owner.printingDictionary!.end, end: owner.printingDictionary!.end, bytes: latin1.encode(printingRestore)));
    }
    add(AiSourceEdit(start: owner.end, end: owner.end, bytes: latin1.encode('\n${flags.map((key) => _shapeStateText(native[key]!, private: true)).join()}')));
  }
  final AiNativeAppearances result = _nativeAppearanceResult(model, edits, owners.map((owner) => owner.use).toList());
  for (final AiNativeAppearanceArtwork owner in owners) {
    final AiNativeAppearanceArtwork after = result.artworkFor(use: result.uses[model.uses.indexOf(owner.use)]);
    if ((after.path == null) != (owner.path == null) ||
        after.liveShape != null ||
        after.groupContours.length != owner.groupContours.length ||
        after.nestedUses.length != owner.nestedUses.length ||
        after.opacityMasks.length != owner.opacityMasks.length ||
        !_sameNativeBytes(after.use.nameBytes, owner.use.nameBytes)) {
      throw const FormatException('Standalone contour replacement changed its style or mask ownership.');
    }
  }
  return result;
}
