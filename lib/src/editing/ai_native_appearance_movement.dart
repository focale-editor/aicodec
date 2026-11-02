part of 'package:aicodec/src/model/ai_native_records.dart';

/// Rebinds inventory wrappers only through their exact immutable source handles.
({_NativeSubtreeSpan span, AiNativeStructureNode node}) _appearanceMovementAnchor(
  AiNativeDrawing drawing,
  AiNativeItem anchor,
  List<AiNativeAppearanceArtwork> retained,
) {
  final AiNativeLayers layers = AiNativeLayers.decode(drawing: drawing);
  final AiNativeItem? current = switch (anchor) {
    AiNativeLayer() => layers.layerFor(anchor.source),
    AiNativeRaster() => layers.rasters.images.where((image) => identical(image.instruction, anchor.instruction)).singleOrNull,
    AiNativePlacedObject() => layers.placements.objects.where((image) => identical(image.instruction, anchor.instruction)).singleOrNull,
    _ => anchor,
  };
  if (current == null) {
    throw ArgumentError('An ordinary movement anchor must belong to the current native source.');
  }
  return _nativeLayerArtworkOwner(layers, current, appearanceArtwork: retained);
}

/// Qualifies public ancestry without allowing a pair's printing group as a parent.
void _appearanceMovementParents(AiNativeAppearances model, Iterable<AiNativeStructureNode> parents, List<AiNativeAppearanceArtwork> retained) {
  final AiNativeDrawing drawing = model.structure.drawing;
  final AiNativeLayers layers = AiNativeLayers.decode(drawing: drawing);
  final List<_NativeSubtreeSpan> neutral = _nativeNeutralArtwork(drawing);
  for (final AiNativeStructureNode parent in parents) {
    if (parent.versions.isNotEmpty || !const {AiNativeStructureKind.layer, AiNativeStructureKind.group, AiNativeStructureKind.clip}.contains(parent.kind)) {
      throw UnsupportedError('Appearance movement requires unconditional ordinary or clipping ancestors.');
    }
    if (parent.source case final AiNativeGroup group) {
      if (group.opening.isPrivate ||
          group.closing.isPrivate ||
          group.opening.operands.isNotEmpty ||
          group.closing.operands.isNotEmpty ||
          retained.any((owner) => group.start >= owner.start && group.end <= owner.end) ||
          neutral.any((span) => group.start >= span.start && group.end <= span.end)) {
        throw UnsupportedError('Private or derived groups cannot receive independent appearance owners.');
      }
      _ordinaryObjectFollowing(drawing, group, clipping: true);
    } else if (parent.source case final AiLayer layer) {
      _qualifiedLayerHeader(layers, layers.layerFor(layer));
    }
  }
}

/// Preserves source bytes while restoring observable state at both movement slots.
AiNativeAppearances _moveNativeAppearanceArtwork(
  AiNativeAppearances model,
  AiNativeAppearanceArtwork artwork,
  AiBoundingBox bounds,
  AiNativeAppearanceArtwork? before,
  AiNativeAppearanceArtwork? after,
  AiNativeItem? beforeObject,
  AiNativeItem? afterObject,
  AiNativeGroup? parent,
  AiLayer? layer,
  bool inheritParentAppearance,
) {
  _nativeTopologyBounds(bounds);
  _selectedBodyAppearanceArtwork(model, [artwork]);
  if ([before, after, beforeObject, afterObject, parent, layer].where((value) => value != null).length > 1) {
    throw ArgumentError('Appearance movement accepts at most one destination selector.');
  }
  final AiNativeAppearanceArtwork? anchor = before ?? after;
  if (anchor != null) {
    _selectedBodyAppearanceArtwork(model, [artwork, anchor]);
  }
  final AiNativeDrawing drawing = model.structure.drawing;
  final AiNativeStructure structure = model.structure;
  final List<AiNativeAppearanceArtwork> retained = _nativeBodyAppearanceArtwork(model);
  final AiNativeItem? ordinaryAnchor = beforeObject ?? afterObject;
  final ({_NativeSubtreeSpan span, AiNativeStructureNode node})? ordinary = ordinaryAnchor == null ? null : _appearanceMovementAnchor(drawing, ordinaryAnchor, retained);
  if (ordinary != null &&
      retained.any(
        (owner) => ordinary.span.start >= owner.start && ordinary.span.start < owner.end || ordinary.span.end > owner.start && ordinary.span.end <= owner.end,
      )) {
    throw UnsupportedError('Appearance movement anchors must own complete independent artwork, not private or printing descendants.');
  }
  final AiNativeStructureNode? destination = anchor != null
      ? structure.parentOf(structure.nodeFor(anchor.printingGroup))
      : ordinary != null
      ? structure.parentOf(structure.nodeFor(ordinary.node.source))
      : parent != null
      ? structure.nodeFor(parent)
      : layer != null
      ? structure.nodeFor(layer)
      : null;
  final int position =
      before?.start ??
      after?.end ??
      (beforeObject != null
          ? ordinary!.span.start
          : afterObject != null
          ? ordinary!.span.end
          : null) ??
      parent?.closing.start ??
      layer?.end.start ??
      drawing.records.program.bodyEnd;
  if (position > artwork.start && position < artwork.end) {
    throw ArgumentError('An appearance owner cannot move inside its own source span.');
  }
  final List<AiNativeStructureNode> sourceParents = _artworkParents(structure, structure.parentOf(structure.nodeFor(artwork.printingGroup)));
  final List<AiNativeStructureNode> targetParents = _artworkParents(structure, destination);
  _appearanceMovementParents(model, {...sourceParents, ...targetParents}, retained);
  final Map<int, _NativeShapeInputs> states = _shapeCopyInputs(
    drawing,
    [
      artwork.start,
      artwork.end,
      position,
      ...sourceParents.where((node) => node.source is AiNativeGroup).map((node) => node.start),
      ...targetParents.where((node) => node.source is AiNativeGroup).map((node) => node.start),
    ],
    clipping: true,
    appearanceArtwork: retained,
  );
  _nativeContourInheritance([sourceParents], targetParents, states, inheritParentAppearance, inheritanceOption: 'inheritParentAppearance');
  if (!inheritParentAppearance) {
    final List<AiNativeStructureNode> sourceClips = sourceParents.where((node) => node.kind == .clip).toList();
    final List<AiNativeStructureNode> targetClips = targetParents.where((node) => node.kind == .clip).toList();
    if (sourceClips.length != targetClips.length || sourceClips.indexed.any((entry) => !identical(entry.$2, targetClips[entry.$1]))) {
      throw UnsupportedError('Changing clipping ancestry requires explicit inheritParentAppearance.');
    }
  }
  final bool unchanged = position == artwork.start || position == artwork.end;
  if (unchanged) {
    final List<AiSourceEdit> edits = AiNativeEditor.includeBoundsEdits(program: drawing.records.program, bounds: bounds);
    if (edits.isEmpty) {
      return model;
    }
    return AiNativeAppearances.decode(
      structure: AiNativeStructure.decode(
        drawing: _groupLifecycleResult(drawing, edits, appearanceLeaves: true, paths: drawing.paths.length, groups: drawing.groups.length, liveShapes: drawing.liveShapes.length),
      ),
    );
  }
  final _NativeShapeAccess access = _nativeAppearanceArtworkAccess(drawing, artwork, artwork._commands);
  final ({List<int> bytes, _NativeSourceReplacement replacement}) removed = _removedAppearanceState(
    access,
    states[artwork.start]!,
    states[artwork.end]!,
    drawing.records.program.limits.maxDecodedBytes,
  );
  final int remaining = drawing.records.program.limits.maxDecodedBytes - drawing.records.program.bytes.length + artwork.end - artwork.start - removed.bytes.length;
  final ({List<int> bytes, _NativeSourceReplacement replacement}) placed = _placedNativeSource(
    drawing,
    (start: artwork.start, end: artwork.end),
    artwork._commands,
    const {},
    access,
    states[artwork.start]!,
    states[artwork.end]!,
    states[position]!,
    states[position]!,
    maxBytes: remaining,
  );
  _sourceFollowingDependencies(
    drawing,
    {(start: artwork.start, end: artwork.end): removed.replacement},
    insertions: {
      position: (
        commands: artwork._commands,
        styles: artwork._styleReads,
        prefix: placed.replacement.prefix,
        suffix: placed.replacement.suffix,
        unresolved: placed.replacement.unresolved,
        printingUnresolved: placed.replacement.printingUnresolved,
        discard: false,
      ),
    },
    retainedArtwork: retained,
    clipping: true,
    patterns: model._patternNames,
  );
  final AiNativeDrawing result = _groupLifecycleResult(
    drawing,
    [
      AiSourceEdit(start: artwork.start, end: artwork.end, bytes: removed.bytes),
      AiSourceEdit(start: position, end: position, bytes: placed.bytes),
      ...AiNativeEditor.includeBoundsEdits(program: drawing.records.program, bounds: bounds),
    ],
    appearanceLeaves: true,
    paths: drawing.paths.length,
    groups: drawing.groups.length,
    liveShapes: drawing.liveShapes.length,
  );
  final AiNativeAppearances updated = AiNativeAppearances.decode(structure: AiNativeStructure.decode(drawing: result));
  final List<AiNativeResourceUse> moving = model.uses.where((use) => use.instruction.start >= artwork.start && use.instruction.end <= artwork.end).toList();
  final List<AiNativeResourceUse> uses = model.uses.where((use) => !moving.contains(use)).toList();
  final int insertion = uses.indexWhere((use) => use.instruction.start >= position);
  uses.insertAll(insertion < 0 ? uses.length : insertion, moving);
  if (updated.styles.length != model.styles.length || updated.uses.length != uses.length || updated.structure.identifiers.length != model.structure.identifiers.length) {
    throw const FormatException('Moving appearance artwork disrupted native resources or identities.');
  }
  for (final (int, AiNativeResourceUse) entry in uses.indexed) {
    final AiNativeResourceUse use = updated.uses[entry.$1];
    if (!_sameNativeBytes(use.nameBytes, entry.$2.nameBytes) || use.instruction.isPrivate != entry.$2.instruction.isPrivate) {
      throw const FormatException('Moving appearance artwork changed a retained style application.');
    }
    final AiNativeAppearanceArtwork? original = retained.where((owner) => identical(owner.use, entry.$2)).singleOrNull;
    if (original != null) {
      final AiNativeAppearanceArtwork owner = updated.artworkFor(use: use);
      if (!_sameNativeBytes(Uint8List.sublistView(result.records.program.bytes, owner.start, owner.end), Uint8List.sublistView(drawing.records.program.bytes, original.start, original.end))) {
        throw const FormatException('Moving appearance artwork changed an owned source representation.');
      }
    }
  }
  return updated;
}
