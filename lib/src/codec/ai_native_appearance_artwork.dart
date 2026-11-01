part of 'package:aikit/src/model/ai_native_records.dart';

/// Resolves a complete source pair without inventing live-shape parameters.
AiNativeAppearanceArtwork _nativeAppearanceArtwork(AiNativeAppearances model, AiNativeResourceUse use) {
  final AiNativeAppearance? style = model.resolve(use: use);
  final AiNativeDrawing drawing = model.structure.drawing;
  final AiProgram program = drawing.records.program;
  if (!_marker(use.instruction, 1) ||
      style == null ||
      use.versions.isNotEmpty ||
      style.resource.versions.isNotEmpty ||
      use.instruction.isPrivate ||
      use.instruction.start < program.bodyStart ||
      use.instruction.end > program.bodyEnd) {
    throw UnsupportedError('Appearance artwork requires a uniquely resolved unconditional body use.');
  }
  final AiLiveShape? shape = drawing.liveShapes.where((shape) => shape.end == use.instruction.end).singleOrNull;
  if (shape != null) {
    final _NativeShapeBundle bundle = _shapeBundle(drawing, shape, model.structure, qualifyNeighbors: false, clipping: true);
    _nativeAppearanceParents(model.structure, bundle.start, shape.end, shape.appearanceGroup!);
    return AiNativeAppearanceArtwork._(
      owner: model,
      use: use,
      authoring: shape.path!,
      printingGroup: shape.appearanceGroup!,
      dictionary: shape.dictionary,
      printingDictionary: shape.appearanceDictionary,
      liveShape: shape,
      start: bundle.start,
      metadata: shape.alternativeDictionaries,
      commands: bundle.commands,
      styleReads: {shape.end: bundle.styleReads},
    );
  }
  final List<AiNativeItem> items = drawing.items;
  int index = _pathOffset(items, use.instruction.start, (item) => item.start) - 1;
  final AiNativeContainer? dictionary = index >= 0 && items[index] is AiNativeContainer ? items[index--] as AiNativeContainer : null;
  final AiNativePath? path = index < 0 ? null : drawing.paths.where((path) => identical(path.paint, items[index])).singleOrNull;
  final AiNativeGroup? authoringGroup = index < 0 || path != null ? null : drawing.groups.where((group) => identical(group.closing, items[index])).singleOrNull;
  final List<AiNativeContainer> metadata = [];
  final Map<AiNativeResourceUse, AiNativeItem> nestedOwners = {};
  final List<AiNativePathTopology> contours = [];
  if (path != null) {
    if (!path.isPrivate || !const {'n', 'N'}.contains(path.paint.operator) || path.geometry.skip(1).any((command) => command.operator == 'm')) {
      throw UnsupportedError('Appearance artwork requires one authoritative private contour before its style use.');
    }
  } else if (authoringGroup != null) {
    final ({List<AiNativeContainer> metadata, Map<AiNativeResourceUse, AiNativeItem> owners, List<AiNativePathTopology> contours}) retained = _nativeAppearanceGroup(model, authoringGroup);
    metadata.addAll(retained.metadata);
    nestedOwners.addAll(retained.owners);
    contours.addAll(retained.contours);
  } else {
    throw UnsupportedError('Appearance artwork requires an authoritative private contour or group before its style use.');
  }
  final AiNativeItem authoring = path ?? authoringGroup!;
  index = _pathOffset(items, authoring.start, (item) => item.start) - 1;
  AiNativeInstruction? count;
  bool panel = false;
  while (index >= 0 && items[index] is AiNativeInstruction && (items[index] as AiNativeInstruction).isPrivate) {
    final AiNativeInstruction item = items[index--] as AiNativeInstruction;
    if (item.operator == 'As' && count == null && path != null) {
      count = item;
    } else if (item.operator == 'Ae' &&
        authoringGroup != null &&
        identical(items[index + 2], authoringGroup.opening) &&
        !panel &&
        item.numbers?.length == 1 &&
        const {0, 1}.contains(item.numbers!.single)) {
      panel = true;
    } else if (_nativeArtworkStateKey(item) == null) {
      throw UnsupportedError('Appearance authoring prefixes require qualified scalar state and path or group flags.');
    }
  }
  if (count != null) {
    _nativeAppearanceCount(path!, count);
  }
  if (index < 0 ||
      items[index] is! AiNativeInstruction ||
      !_marker(items[index] as AiNativeInstruction, 6) ||
      (items[index] as AiNativeInstruction).isPrivate ||
      aiStringBytes((items[index] as AiNativeInstruction).operands.last).isNotEmpty) {
    throw UnsupportedError('Appearance artwork requires an empty printing-style boundary before its private artwork.');
  }
  index--;
  while (index >= 0 && items[index] is AiNativeInstruction) {
    final AiNativeInstruction item = items[index] as AiNativeInstruction;
    if (item.isPrivate || !(_nativeArtworkStateKey(item) != null || item.operator == 'Xd' && item.numbers?.length == 2 && item.numbers!.every((value) => value == 0))) {
      break;
    }
    index--;
  }
  final AiNativeContainer? printingDictionary = index >= 0 && items[index] is AiNativeContainer ? items[index--] as AiNativeContainer : null;
  final AiNativeGroup? group = index < 0 ? null : drawing.groups.where((group) => group.end == items[index].end).singleOrNull;
  if (group == null || group.opening.isPrivate || group.compound || drawing.liveShapes.any((shape) => shape.start < use.instruction.end && shape.end > group.start)) {
    throw UnsupportedError('Appearance artwork requires a distinct ordinary printing group.');
  }
  _printingState(drawing, group, clipping: true);
  _printingPointCounts(drawing, group);
  final AiNativeStructureNode owner = model.structure.nodeFor(group);
  for (final AiNativeItem item in [authoring, use.instruction, ?dictionary, ?printingDictionary]) {
    if (!_sameNativeObjectOwner(owner, model.structure.nodeFor(item))) {
      throw UnsupportedError('Appearance artwork cannot cross lexical owners or version branches.');
    }
  }
  [?dictionary, ?printingDictionary].forEach(_nativeAppearanceDictionary);
  final AiNativeInstruction? expansion = drawing._objects.forSource(group).expansion;
  if (expansion != null &&
      (expansion.isPrivate || expansion.numbers?.length != 1 || !const {0, 1}.contains(expansion.numbers!.single) || !_sameNativeObjectOwner(owner, model.structure.nodeFor(expansion)))) {
    throw UnsupportedError('Appearance artwork has an unqualified outer panel flag.');
  }
  final int start = expansion?.start ?? group.start;
  _nativeAppearanceParents(model.structure, start, use.instruction.end, group);
  if (_nativeObjectMetadataComments(drawing, start, use.instruction.end)) {
    throw UnsupportedError('Appearance artwork contains unresolved structured comments or payloads.');
  }
  final List<AiNativeInstruction> commands = [];
  final Set<AiNativeInstruction> geometry = {
    if (path != null) ...[...path.geometry, path.paint],
  };
  for (final AiNativeItem item in _pathInterval(items, start, use.instruction.end, (item) => item.start)) {
    if (identical(item, dictionary) || identical(item, printingDictionary) || metadata.contains(item)) {
      continue;
    }
    if (item is! AiNativeInstruction || path != null && item.start >= path.start && item.end <= path.end && !geometry.contains(item)) {
      throw UnsupportedError('Appearance artwork contains an unresolved native owner or interleaved contour state.');
    }
    commands.add(item);
  }
  final ({Set<String> reads, Set<String> writes}) state = _nativeLiteralStyleState(drawing, style.resource.definition.source as AiNativeContainer);
  return AiNativeAppearanceArtwork._(
    owner: model,
    use: use,
    authoring: authoring,
    printingGroup: group,
    dictionary: dictionary,
    printingDictionary: printingDictionary,
    liveShape: null,
    start: start,
    metadata: metadata,
    nestedOwners: nestedOwners,
    groupContours: contours,
    commands: commands,
    styleReads: {
      use.instruction.end: state.reads,
      for (final AiNativeResourceUse nested in nestedOwners.keys)
        nested.instruction.end: _nativeLiteralStyleState(drawing, model.resolve(use: nested)!.resource.definition.source as AiNativeContainer).reads,
    },
  );
}

/// Retains inert object labels and identities without accepting appearance caches.
void _nativeAppearanceDictionary(AiNativeContainer dictionary) {
  if (dictionary.type != 'ArtDictionary' || dictionary.notRecorded || dictionary.entries.map((field) => field.key).toSet().length != dictionary.entries.length) {
    throw UnsupportedError('Appearance metadata requires one recorded dictionary with distinct fields.');
  }
  for (final AiNativeEntry field in dictionary.entries) {
    final double? angle = field.key == 'BBAccumRotation' ? double.tryParse(field.text() ?? '') : null;
    final bool valid = switch (field.key) {
      'AIArtName' || 'Object name' => const {'String', 'UnicodeString'}.contains(field.type) && (field.items.isEmpty || field.stringBytes != null),
      'BBAccumRotation' => field.type == 'String' && angle != null && angle.isFinite && angle.abs() <= 9007199254740991,
      'AI10_ArtUID' =>
        field.container?.type == 'XMLUID' &&
            field.container!.entries.length == 1 &&
            field.container!.entries.single.key == null &&
            field.container!.entries.single.type == null &&
            field.container!.entries.single.items.length == 1 &&
            field.container!.entries.single.stringBytes != null,
      _ => false,
    };
    if (!valid) {
      throw UnsupportedError('Appearance metadata contains an unqualified field or value.');
    }
  }
}

/// Requires an unconditional pair whose enclosing effects need no new expansion.
void _nativeAppearanceParents(AiNativeStructure structure, int start, int end, AiNativeGroup group) {
  if (structure.versions.memberships(start: start, end: end).isNotEmpty) {
    throw UnsupportedError('Appearance artwork requires an unconditional source owner.');
  }
  for (final AiNativeStructureNode parent in _artworkParents(structure, structure.parentOf(structure.nodeFor(group)))) {
    if (parent.versions.isNotEmpty || !const {AiNativeStructureKind.layer, AiNativeStructureKind.group}.contains(parent.kind)) {
      throw UnsupportedError('Appearance artwork has an unresolved enclosing owner.');
    }
    if (parent.source case final AiNativeGroup enclosing) {
      if (enclosing.opening.isPrivate) {
        throw UnsupportedError('Appearance artwork cannot inherit a private group.');
      }
      _ordinaryObjectFollowing(structure.drawing, enclosing);
    } else if (parent.source case final AiLayer layer) {
      final AiNativeLayers layers = AiNativeLayers.decode(drawing: structure.drawing);
      _qualifiedLayerHeader(layers, layers.layerFor(layer));
    }
  }
}
