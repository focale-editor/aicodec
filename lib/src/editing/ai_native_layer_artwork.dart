part of 'package:illustratorkit/src/model/ai_native_records.dart';

/// Qualifies an ordinary group as a complete mixed owner or append destination.
AiNativeStructureNode _nativeMixedArtworkGroup(AiNativeLayers model, AiNativeGroup group) {
  if (!model.drawing.groups.contains(group)) {
    throw ArgumentError('The group belongs to another native drawing snapshot.');
  }
  final AiNativeStructureNode node = model.structure.nodeFor(group);
  _sourceMovementParents(model.drawing, _artworkParents(model.structure, node));
  if (model.layers.any((layer) => layer.start >= group.start && layer.end <= group.end)) {
    throw UnsupportedError('Ordinary group artwork cannot contain native layer declarations.');
  }
  return node;
}

/// Resolves exact handles to complete source spans without guessing ownership.
({_NativeSubtreeSpan span, AiNativeStructureNode node}) _nativeLayerArtworkOwner(
  AiNativeLayers model,
  AiNativeItem item, {
  List<AiNativeAppearanceArtwork> appearanceArtwork = const [],
}) {
  final AiNativeStructureNode node;
  final _NativeSubtreeSpan span;
  if (item is AiNativeLayer) {
    _qualifiedLayerHeader(model, item);
    _layerLifecyclePrefix(model, item, _layerHeaderItems(model), privateState: true, appearanceArtwork: appearanceArtwork);
    node = model.structure.nodeFor(item.source);
    span = (start: item.start, end: item.end);
  } else if (item is AiNativeGroup) {
    node = _nativeMixedArtworkGroup(model, item);
    final AiNativeObject object = _ordinaryObject(model.drawing, item);
    span = (start: object.start, end: object.end);
  } else if (item is AiNativeGradientArtwork) {
    if (!model.drawing.gradientArtwork.contains(item)) {
      throw ArgumentError('Gradient artwork belongs to another source snapshot.');
    }
    node = model.structure.nodeFor(item.path);
    span = (start: item.start, end: item.end);
  } else if (item is AiNativeMeshArtwork) {
    if (!model.drawing.meshArtwork.contains(item)) {
      throw ArgumentError('Mesh artwork belongs to another source snapshot.');
    }
    node = model.structure.nodeFor(item.opening);
    span = (start: item.start, end: item.end);
  } else if (item is AiNativePath) {
    final AiNativeInstruction? count = _ordinaryPathCounts(model.drawing, [item], ownership: model.structure, appearanceArtwork: appearanceArtwork)[item];
    node = model.structure.nodeFor(item);
    span = (start: count?.start ?? item.start, end: _ordinaryObject(model.drawing, item).end);
  } else if (item is AiNativeRaster) {
    model.rasters.validateSourceLayout(image: item);
    final int end = _nativeImageAttributeOwner(model.drawing, item, _imageCreationNeutralSpans(model.drawing));
    node = _nativeRasterNode(model.structure, item);
    span = (start: item.start, end: end);
  } else if (item is AiNativePlacedObject) {
    if (!model.placements.objects.contains(item)) {
      throw ArgumentError('The placed object belongs to another native snapshot.');
    }
    item.validateRasterLayout();
    final int end = _nativeImageAttributeOwner(model.drawing, item, _imageCreationNeutralSpans(model.drawing));
    node = model.structure.nodes.singleWhere((node) => node.kind == .instruction && node.start == item.instruction.start);
    span = (start: item.start, end: end);
  } else if (item is AiNativeContainer && item.type == 'AI11Text') {
    final _NativeTextArtwork? owner = model.drawing._textArtwork.where((owner) => identical(owner.record, item)).firstOrNull;
    if (owner == null) {
      throw UnsupportedError('Moving text requires an owned isolated native text reference.');
    }
    node = model.structure.nodeFor(item);
    span = owner.span;
  } else {
    throw ArgumentError('Mixed artwork requires owned paths, gradients, meshes, images, text references, groups or complete layers.');
  }
  final AiNativeStructureNode? parent = model.structure.parentOf(node);
  if (parent != null && parent.kind != .layer && parent.kind != .group || item is AiNativeLayer && parent?.kind == .group) {
    throw UnsupportedError('Mixed artwork requires ordinary ancestry; layers cannot be group children.');
  }
  _sourceMovementParents(model.drawing, _artworkParents(model.structure, parent));
  return (span: span, node: node);
}

/// Permutes mixed sibling slots with independent restoration at every boundary.
AiNativeLayers _reorderNativeLayerArtwork(AiNativeLayers model, List<AiNativeItem> artwork, bool discardViewState) {
  if (artwork.isEmpty || artwork.toSet().length != artwork.length) {
    throw ArgumentError('Mixed artwork ordering requires distinct owned handles.');
  }
  final List<AiNativeAppearanceArtwork> retained = _nativeBodyAppearanceArtwork(AiNativeAppearances.decode(structure: model.structure));
  final List<({_NativeSubtreeSpan span, AiNativeStructureNode node})> owners = artwork.map((item) => _nativeLayerArtworkOwner(model, item, appearanceArtwork: retained)).toList();
  final int? parent = owners.first.node.parentIndex;
  if (owners.any((owner) => owner.node.parentIndex != parent)) {
    throw ArgumentError('Mixed artwork ordering requires one immediate parent.');
  }
  final List<_NativeSubtreeSpan> spans = owners.map((owner) => owner.span).toList();
  final List<_NativeSubtreeSpan> sorted = [...spans]..sort((first, second) => first.start.compareTo(second.start));
  if (sorted.indexed.any((entry) => entry.$1 > 0 && sorted[entry.$1 - 1].end > entry.$2.start)) {
    throw ArgumentError('Selected native artwork owners cannot overlap.');
  }
  if (spans.indexed.every((entry) => entry.$2 == sorted[entry.$1])) {
    return model;
  }
  final List<_NativeShapeBundle> pairs = _subtreeShapeBundles(model.drawing, spans, appearanceArtwork: retained);
  return _layerLifecycleResult(model, [
    if (artwork.any((item) => item is AiNativeLayer)) ..._layerDeclarations(model, model.rootCount, discardViewState),
    ..._reorderedNativeSubtrees(model, spans, pairs, appearanceArtwork: retained),
  ], roots: model.rootCount);
}

/// Relocates one complete mixed owner to a root, layer or ordinary group boundary.
AiNativeLayers _moveNativeLayerArtwork(AiNativeLayers model, AiNativeItem artwork, AiNativeLayer? parent, AiNativeGroup? group, bool inheritParentFlags, bool discardViewState) {
  if (parent != null && group != null) {
    throw ArgumentError('Moving artwork requires at most one group or layer destination.');
  }
  final List<AiNativeAppearanceArtwork> retained = _nativeBodyAppearanceArtwork(AiNativeAppearances.decode(structure: model.structure));
  final ({_NativeSubtreeSpan span, AiNativeStructureNode node}) owner = _nativeLayerArtworkOwner(model, artwork, appearanceArtwork: retained);
  if (parent != null) {
    _qualifiedLayerHeader(model, parent);
    if (parent.start >= owner.span.start && parent.end <= owner.span.end) {
      throw ArgumentError('Native artwork cannot move into its own subtree.');
    }
  }
  if (group != null) {
    _nativeMixedArtworkGroup(model, group);
    if (artwork is AiNativeLayer) {
      throw UnsupportedError('Native layers cannot move inside an ordinary group.');
    }
    if (group.start >= owner.span.start && group.end <= owner.span.end) {
      throw ArgumentError('Native artwork cannot move into its own subtree.');
    }
  }
  final AiNativeStructureNode? destination = group != null
      ? model.structure.nodeFor(group)
      : parent == null
      ? null
      : model.structure.nodeFor(parent.source);
  final int position = group?.closing.start ?? parent?.source.end.start ?? model.drawing.records.program.bodyEnd;
  if (position >= owner.span.start && position <= owner.span.end) {
    return model;
  }
  final int roots = model.rootCount + (artwork is AiNativeLayer ? (parent == null ? 1 : 0) - (artwork.parentIndex == null ? 1 : 0) : 0);
  return _layerLifecycleResult(model, [
    if (artwork is AiNativeLayer) ..._layerDeclarations(model, roots, discardViewState),
    ..._relocatedNativeSubtree(
      model,
      owner.node,
      owner.span,
      _subtreeShapeBundles(model.drawing, [owner.span], appearanceArtwork: retained),
      position,
      destination,
      inheritParentFlags,
      appearanceArtwork: retained,
    ),
  ], roots: roots);
}

/// Deletes complete mixed owners after validating every affected reference.
AiNativeLayers _removeNativeLayerArtwork(AiNativeLayers model, List<AiNativeItem> artwork, bool discardViewState) {
  if (artwork.isEmpty || artwork.toSet().length != artwork.length) {
    throw ArgumentError('Mixed removal requires distinct owned artwork.');
  }
  final List<AiNativeAppearanceArtwork> retained = _nativeBodyAppearanceArtwork(AiNativeAppearances.decode(structure: model.structure));
  final List<_NativeSubtreeSpan> spans = artwork.map((item) => _nativeLayerArtworkOwner(model, item, appearanceArtwork: retained).span).toList()
    ..sort((first, second) => first.start.compareTo(second.start));
  if (model.drawing.records.containers.any((record) => record.type == 'AI11Text' && spans.any((span) => record.start >= span.start && record.end <= span.end))) {
    throw UnsupportedError('Remove text stories or frames before deleting their containing artwork.');
  }
  if (spans.indexed.any((entry) => entry.$1 > 0 && spans[entry.$1 - 1].end > entry.$2.start)) {
    throw ArgumentError('Removed artwork owners cannot contain or overlap one another.');
  }

  /// Tests complete ownership without allowing partial image or group deletion.
  bool removed(AiNativeItem item) => spans.any((span) => item.start >= span.start && item.end <= span.end);

  final List<AiNativeLayer> layers = model.layers.where(removed).toList();
  final int roots = model.rootCount - layers.where((layer) => layer.parentIndex == null).length;
  final List<_NativeShapeBundle> pairs = _subtreeShapeBundles(model.drawing, spans, appearanceArtwork: retained);
  final AiNativeLayers result = _layerLifecycleResult(
    model,
    [
      if (layers.isNotEmpty) ..._layerDeclarations(model, roots, discardViewState),
      ..._removedNativeSubtrees(model, spans, pairs, appearanceArtwork: retained),
    ],
    roots: roots,
    layers: model.layers.length - layers.length,
    paths: model.drawing.paths.length - model.drawing.paths.where(removed).length,
    groups: model.drawing.groups.length - model.drawing.groups.where(removed).length,
    liveShapes: model.drawing.liveShapes.length - _subtreeLiveShapeCount(model.drawing, spans),
  );
  if (result.rasters.images.length != model.rasters.images.length - model.rasters.images.where(removed).length) {
    throw const FormatException('Mixed removal changed an unexpected raster count.');
  }
  if (result.placements.objects.length != model.placements.objects.length - model.placements.objects.where(removed).length) {
    throw const FormatException('Mixed removal changed an unexpected linked image count.');
  }
  if (result.drawing.gradientArtwork.length != model.drawing.gradientArtwork.length - model.drawing.gradientArtwork.where(removed).length) {
    throw const FormatException('Mixed removal changed an unexpected gradient owner count.');
  }
  if (result.drawing.meshArtwork.length != model.drawing.meshArtwork.length - model.drawing.meshArtwork.where(removed).length) {
    throw const FormatException('Mixed removal changed an unexpected mesh owner count.');
  }
  AiNativeRecords records = result.drawing.records;
  final Set<String> paths = {
    for (final AiNativeRaster image in model.rasters.images.where(removed)) latin1.decode(aiStringBytes(image.commands.singleWhere((command) => command.operator == 'XG').operands.first)),
    for (final AiNativePlacedObject image in model.placements.objects.where(removed)) latin1.decode(image.pathBytes),
  }..remove('');
  for (final String path in paths) {
    final List<AiSourceEdit> edits = _placedFilePathEdits(AiNativePlacements.decode(records: records), path);
    if (edits.isNotEmpty) {
      records = AiNativeRecords.decode(
        program: AiNativeEditor.apply(program: records.program, edits: edits),
      );
    }
  }
  return identical(records, result.drawing.records) ? result : AiNativeLayers.decode(drawing: AiNativeDrawing.decode(records: records));
}
