part of 'package:aikit/src/model/ai_native_records.dart';

/// Replaces independent private path paints with complete host printing coverage.
AiNativeAppearances _replaceNativeAppearancePaths(
  AiNativeAppearances model,
  List<AiNativeAppearancePathChange> changes,
  List<AiNativeAppearanceReplacement> artwork,
) {
  if (changes.isEmpty || changes.map((change) => change.path).toSet().length != changes.length) {
    throw ArgumentError('Private paint changes require distinct current contours.');
  }
  final List<AiNativeAppearanceArtwork> owners = _selectedBodyAppearanceArtwork(model, artwork.map((replacement) => replacement.artwork).toList());
  if (artwork.any((replacement) => replacement.uses.length != 1 || !identical(replacement.uses.single, replacement.artwork.use)) ||
      owners.any((owner) => owner.group == null || owner.liveShape != null)) {
    throw UnsupportedError('Private paints require complete ordinary group owners.');
  }
  final Map<AiNativePath, AiNativePathTopology> contours = {};
  for (final AiNativeAppearanceArtwork owner in owners) {
    final Set<AiNativePath> selected = changes.map((change) => change.path).toSet().intersection(owner.groupContours.map((contour) => contour.path).toSet());
    if (selected.isEmpty) {
      throw ArgumentError('Every printing owner must cover a changed private contour.');
    }
    for (final AiNativePathTopology contour in owner.groupContours.where((contour) => selected.contains(contour.path))) {
      if (contour.compound != null || contour.mask != .none || owner.nestedUses.any((use) => identical(owner.authoringFor(use: use), contour.path))) {
        throw UnsupportedError('Compound, mask and named-style children require their own complete appearance contract.');
      }
      contours[contour.path] = contour;
    }
  }
  if (changes.any((change) => !change.path.isPrivate || !contours.containsKey(change.path))) {
    throw ArgumentError('Every changed path requires its current private group owner.');
  }
  final AiNativeDrawing drawing = model.structure.drawing;
  final List<AiNativeAppearanceArtwork> retained = _nativeBodyAppearanceArtwork(model);
  final Map<int, _NativeShapeInputs> states = _shapeCopyInputs(drawing, changes.map((change) => change.path.end), clipping: true, appearanceArtwork: retained);
  final List<AiSourceEdit> edits = _nativeAppearancePrintingEdits(model, artwork);
  final Map<AiNativePath, _NativePrivatePathStateChange> stateChanges = {};
  int remaining = drawing.records.program.limits.maxDecodedBytes - edits.fold(0, (sum, edit) => sum + edit.bytes.length);

  /// Charges all emitted fragments, including restorations, before publication.
  void add(AiSourceEdit edit) {
    remaining -= edit.bytes.length;
    if (remaining < 0) {
      throw const AiLimitException(message: 'Private path paints exceed the aggregate native output limit.');
    }
    edits.add(edit);
  }

  for (final AiNativeAppearancePathChange change in changes) {
    final AiNativePath path = change.path;
    final AiArtworkPath paint = change.artwork;
    final AiNativeAppearanceReplacement owner = artwork.singleWhere((replacement) => replacement.artwork.groupContours.any((contour) => identical(contour.path, path)));
    final AiNativePathDefinition definition = AiNativePathDefinition(
      artwork: paint,
      namedFill: change.namedFill,
      namedStroke: change.namedStroke,
      bounds: owner.bounds,
      opacity: change.opacity,
      transparency: change.transparency,
      hidden: change.hidden,
      fillOverprint: change.fillOverprint,
      strokeOverprint: change.strokeOverprint,
    );
    final Set<String> writes = {'A', 'Xw', 'XR', 'Xy', 'O', 'R', 'w', 'J', 'j', 'M', 'd', if (definition.filled) 'fill', if (definition.stroked) 'stroke'};
    final Set<String> reads = {
      'A',
      'Xw',
      'Ap',
      'D',
      'XR',
      if (definition.filled || definition.stroked) 'Xy',
      if (definition.filled) ...{'O', 'fill'},
      if (definition.stroked) ...{'stroke', 'R', 'w', 'J', 'j', 'M', 'd'},
    };
    final Map<String, AiNativeInstruction> original = states[path.end]!.native;
    stateChanges[path] = (writes: writes, reads: reads, unresolved: writes.difference(original.keys.toSet()));
    final String prefix = ['${paint.locked ? 1 : 0} A', '${change.hidden ? 1 : 0} Xw', ..._nativePathPaintCommands(definition, maximum: drawing.records.program.limits.maxDecodedBytes)].join(' ');
    final List<AiSourceEdit> geometry = _replaceShapeContour(drawing, path, contours[path]!.pointCount, paint.segments, remaining, closed: paint.closed);
    for (final AiSourceEdit edit in geometry) {
      add(edit.start == path.geometry.first.start ? AiSourceEdit(start: edit.start, end: edit.end, bytes: [...latin1.encode('$prefix '), ...edit.bytes]) : edit);
    }
    final String operator = !definition.filled ? (!definition.stroked ? 'N' : 'S') : (!definition.stroked ? 'F' : 'B');
    add(AiSourceEdit(start: path.paint.start, end: path.paint.end, bytes: ascii.encode(paint.closed ? operator.toLowerCase() : operator)));
    final String restoration = writes.where(original.containsKey).map((key) => _shapeStateText(original[key]!, private: true)).join();
    if (restoration.isNotEmpty) {
      // Keep the original dictionary directly attached to its path. The final
      // private prefix also protects commands sharing the original source line.
      final int position = drawing._objects.forSource(path).dictionary?.end ?? path.end;
      add(AiSourceEdit(start: position, end: position, bytes: latin1.encode('\n$restoration%_')));
    }
  }
  _sourceFollowingDependencies(
    drawing,
    {
      for (final AiNativeAppearanceArtwork owner in owners)
        (start: owner.start, end: owner.end): (
          commands: owner._commands,
          styles: owner._styleReads,
          prefix: [],
          suffix: [],
          unresolved: {},
          printingUnresolved: {},
          discard: false,
        ),
    },
    retainedArtwork: retained,
    clipping: true,
    pathChanges: stateChanges,
  );
  final AiNativeAppearances result = _nativeAppearanceResult(model, edits, owners.map((owner) => owner.use).toList());
  for (final AiNativeAppearanceArtwork owner in owners) {
    final AiNativeAppearanceArtwork after = result.artworkFor(use: result.uses[model.uses.indexOf(owner.use)]);
    if (after.group == null || after.groupContours.length != owner.groupContours.length || after.nestedUses.length != owner.nestedUses.length) {
      throw const FormatException('Private paint replacement changed authoring ownership.');
    }
  }
  return result;
}
