part of 'package:aikit/src/model/ai_native_records.dart';

/// Resolves a complete source pair without treating an ordinary path as a shape.
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
    final _NativeShapeBundle bundle = _shapeBundle(drawing, shape, model.structure, qualifyNeighbors: false);
    _nativeAppearanceParents(model.structure, bundle.start, shape.end, shape.appearanceGroup!);
    return AiNativeAppearanceArtwork._(
      owner: model,
      use: use,
      path: shape.path!,
      printingGroup: shape.appearanceGroup!,
      dictionary: shape.dictionary,
      printingDictionary: shape.appearanceDictionary,
      liveShape: shape,
      start: bundle.start,
      commands: bundle.commands,
      styleReads: bundle.styleReads,
    );
  }
  final List<AiNativeItem> items = drawing.items;
  int index = _pathOffset(items, use.instruction.start, (item) => item.start) - 1;
  final AiNativeContainer? dictionary = index >= 0 && items[index] is AiNativeContainer ? items[index--] as AiNativeContainer : null;
  final AiNativePath? path = index < 0 ? null : drawing.paths.where((path) => identical(path.paint, items[index])).singleOrNull;
  if (path == null || !path.isPrivate || !const {'n', 'N'}.contains(path.paint.operator) || path.geometry.skip(1).any((command) => command.operator == 'm')) {
    throw UnsupportedError('Appearance artwork requires one authoritative private contour before its style use.');
  }
  index = _pathOffset(items, path.start, (item) => item.start) - 1;
  AiNativeInstruction? count;
  while (index >= 0 && items[index] is AiNativeInstruction && (items[index] as AiNativeInstruction).isPrivate) {
    final AiNativeInstruction item = items[index--] as AiNativeInstruction;
    if (item.operator == 'As' && count == null) {
      count = item;
    } else if (_nativeArtworkStateKey(item) == null) {
      throw UnsupportedError('Appearance authoring prefixes require qualified scalar state and one point count.');
    }
  }
  if (count != null) {
    final List<double> first = path.geometry.first.numbers!;
    final List<double> last = path.geometry.last.numbers!;
    if (count.numbers?.length != 1 || count.numbers!.single != path.geometry.length - (path.closed ? 1 : 0) || path.closed && (first[0] != last[last.length - 2] || first[1] != last.last)) {
      throw UnsupportedError('The authoring point count disagrees with its contour.');
    }
  }
  if (index < 0 ||
      items[index] is! AiNativeInstruction ||
      !_marker(items[index] as AiNativeInstruction, 6) ||
      (items[index] as AiNativeInstruction).isPrivate ||
      aiStringBytes((items[index] as AiNativeInstruction).operands.last).isNotEmpty) {
    throw UnsupportedError('Appearance artwork requires an empty printing-style boundary before its private contour.');
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
  _printingState(drawing, group);
  _printingPointCounts(drawing, group);
  final AiNativeStructureNode owner = model.structure.nodeFor(group);
  for (final AiNativeItem item in [path, use.instruction, ?dictionary, ?printingDictionary]) {
    if (!_sameNativeObjectOwner(owner, model.structure.nodeFor(item))) {
      throw UnsupportedError('Appearance artwork cannot cross lexical owners or version branches.');
    }
  }
  [?dictionary, ?printingDictionary].forEach(_nativeAppearanceDictionary);
  final AiNativeInstruction? panel = drawing._objects.forSource(group).expansion;
  if (panel != null && (panel.isPrivate || panel.numbers?.length != 1 || !const {0, 1}.contains(panel.numbers!.single) || !_sameNativeObjectOwner(owner, model.structure.nodeFor(panel)))) {
    throw UnsupportedError('Appearance artwork has an unqualified outer panel flag.');
  }
  final int start = panel?.start ?? group.start;
  _nativeAppearanceParents(model.structure, start, use.instruction.end, group);
  if (_nativeObjectMetadataComments(drawing, start, use.instruction.end)) {
    throw UnsupportedError('Appearance artwork contains unresolved structured comments or payloads.');
  }
  final List<AiNativeInstruction> commands = [];
  final Set<AiNativeInstruction> geometry = {...path.geometry, path.paint};
  for (final AiNativeItem item in _pathInterval(items, start, use.instruction.end, (item) => item.start)) {
    if (identical(item, dictionary) || identical(item, printingDictionary)) {
      continue;
    }
    if (item is! AiNativeInstruction || item.start >= path.start && item.end <= path.end && !geometry.contains(item)) {
      throw UnsupportedError('Appearance artwork contains an unresolved native owner or interleaved contour state.');
    }
    commands.add(item);
  }
  final ({Set<String> reads, Set<String> writes}) state = _nativeLiteralStyleState(drawing, style.resource.definition.source as AiNativeContainer);
  return AiNativeAppearanceArtwork._(
    owner: model,
    use: use,
    path: path,
    printingGroup: group,
    dictionary: dictionary,
    printingDictionary: printingDictionary,
    liveShape: null,
    start: start,
    commands: commands,
    styleReads: state.reads,
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
