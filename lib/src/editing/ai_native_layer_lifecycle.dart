part of 'package:aikit/src/model/ai_native_records.dart';

/// Associates known structural instructions and identity records with their layer.
Map<int, AiNativeLayer> _layerHeaderItems(AiNativeLayers model) => {
  for (final AiNativeLayer layer in model.layers) ...{
    layer.source.begin.start: layer,
    layer.source.end.start: layer,
    if (layer.source.naming != null) layer.source.naming!.start: layer,
    if (layer.expansion != null) layer.expansion!.start: layer,
    if (layer.dictionary != null) layer.dictionary!.start: layer,
  },
};

/// Refuses unresolved metadata that precedes and may belong to a selected layer.
void _layerLifecyclePrefix(AiNativeLayers model, AiNativeLayer layer, Map<int, AiNativeLayer> headers) {
  int start = model.drawing.records.program.bodyStart;
  for (int index = _pathOffset(model.drawing.items, layer.start, (item) => item.start) - 1; index >= 0; index--) {
    final AiNativeItem item = model.drawing.items[index];
    if (item is AiNativeInstruction && (_nativePaint.contains(item.operator) || const {'u', 'U', 'Lb', 'LB'}.contains(item.operator))) {
      start = item.end;
      break;
    }
  }
  _layerInterval(model, start, layer.start, headers);
}

/// Validates an ordinary interval without interpreting opaque object families.
List<AiNativeInstruction> _layerInterval(AiNativeLayers model, int start, int end, Map<int, AiNativeLayer> headers) {
  final AiNativeDrawing drawing = model.drawing;
  final List<AiNativePath> paths = _pathInterval(drawing.paths, start, end, (path) => path.start).toList();
  final Map<AiNativePath, AiNativeInstruction?> counts = paths.isEmpty ? {} : _ordinaryPathCounts(drawing, paths, ownership: model.structure);
  final Set<AiNativeInstruction> geometry = {
    for (final AiNativePath path in paths) ...[...path.geometry, path.paint],
    ...counts.values.whereType<AiNativeInstruction>(),
  };
  final List<AiNativeInstruction> commands = [];
  for (final AiNativeItem item in _pathInterval(drawing.items, start, end, (item) => item.start)) {
    if (item.end > end) {
      throw UnsupportedError('The layer edit crosses an unfinished native object.');
    }
    if (headers[item.start] case final AiNativeLayer owner) {
      if (owner.bindingIssue case final String issue) {
        throw UnsupportedError(issue);
      }
      continue;
    }
    if (item is! AiNativeInstruction || item.isPrivate) {
      throw UnsupportedError('Layer lifecycle edits require ordinary artwork and qualified layer identities.');
    }
    if (const {'u', 'U'}.contains(item.operator)) {
      if (item.operands.isNotEmpty) {
        throw UnsupportedError('Layer artwork has an unqualified group boundary.');
      }
    } else if (geometry.contains(item)) {
      // Geometry and consumed counts were qualified against their native owners.
    } else if (_nativeArtworkStateKey(item) == null) {
      throw UnsupportedError('Layer lifecycle edits have no state contract for ${item.operator}.');
    }
    commands.add(item);
  }
  final Set<int> wrappers = {
    for (final AiNativeLayer layer in model.layers) ...[
      if (layer.openingComment != null) layer.openingComment!.start,
      if (layer.closingComment != null) layer.closingComment!.start,
    ],
  };
  if (_pathInterval(drawing.records._projection.tokens, start, end, (token) => token.start).any(
    (token) => token.kind == .data || token.kind == .comment && !wrappers.contains(token.start) && (token.lexeme.startsWith('%AI') || token.lexeme.startsWith('%%')),
  )) {
    throw UnsupportedError('Layer lifecycle edits require ownership of all attached native metadata.');
  }
  return commands;
}

/// Reads state across qualified layer headers without resetting persistent paint.
Map<int, _NativeArtworkState> _layerStates(AiNativeLayers model, Iterable<int> boundaries, Map<int, AiNativeLayer> headers) =>
    _nativeArtworkStates(model.drawing, boundaries, structural: headers.entries.where((entry) => entry.value.bindingIssue == null).map((entry) => entry.key).toSet());

/// Places a complete layer with optional identity edits and retained state.
List<int> _placedLayer(
  AiNativeLayers model,
  AiNativeLayer layer,
  List<AiNativeInstruction> commands,
  _NativeArtworkState source,
  _NativeArtworkState incoming,
  _NativeArtworkState outgoing, {
  required int maxBytes,
  List<AiSourceEdit> sourceEdits = const [],
}) => _placedNativeArtwork(
  model.drawing.records.program,
  [(start: layer.start, end: layer.end)],
  commands,
  source,
  incoming,
  outgoing,
  maxBytes: maxBytes,
  sourceEdits: sourceEdits,
);

/// Requires distinct immutable handles with disjoint complete source subtrees.
List<AiNativeLayer> _selectedLayers(AiNativeLayers model, List<AiNativeLayer> layers) {
  if (layers.isEmpty || layers.toSet().length != layers.length) {
    throw ArgumentError('Layer lifecycle edits require distinct owned layers.');
  }
  for (final AiNativeLayer layer in layers) {
    _qualifiedLayerHeader(model, layer);
  }
  final List<AiNativeLayer> ordered = [...layers]..sort((a, b) => a.start.compareTo(b.start));
  if (ordered.indexed.any((entry) => entry.$1 > 0 && ordered[entry.$1 - 1].end > entry.$2.start)) {
    throw ArgumentError('Selected layers cannot contain each other.');
  }
  return ordered;
}

/// Checks expected artwork counts and root declarations after atomic edits.
AiNativeLayers _layerLifecycleResult(AiNativeLayers model, List<AiSourceEdit> edits, {required int roots, int? layers, int? paths, int? groups}) {
  final AiNativeDrawing drawing = _pathLifecycleResult(model.drawing, edits, paths ?? model.drawing.paths.length);
  final AiNativeLayers result = AiNativeLayers.decode(drawing: drawing);
  if (result.layers.length != (layers ?? model.layers.length) || drawing.groups.length != (groups ?? model.drawing.groups.length) || result.rootCount != roots || !result.rootCountMatches) {
    throw const FormatException('Layer lifecycle edits changed unrelated artwork or root counts.');
  }
  return result;
}

/// Reorders sibling slots while keeping every slot's outgoing persistent state.
AiNativeLayers _reorderNativeLayers(AiNativeLayers model, List<AiNativeLayer> layers, bool discardViewState) {
  final List<AiNativeLayer> slots = _selectedLayers(model, layers);
  if (slots.any((layer) => layer.parentIndex != slots.first.parentIndex)) {
    throw ArgumentError('Reordering requires layers with the same immediate parent.');
  }
  if (slots.indexed.every((entry) => identical(entry.$2, layers[entry.$1]))) {
    return model;
  }
  final Map<int, AiNativeLayer> headers = _layerHeaderItems(model);
  for (final AiNativeLayer layer in layers) {
    _layerLifecyclePrefix(model, layer, headers);
  }
  _layerInterval(model, slots.first.start, slots.last.end, headers);
  final Map<int, _NativeArtworkState> states = _layerStates(model, slots.expand((layer) => [layer.start, layer.end]), headers);
  final List<AiSourceEdit> edits = _layerDeclarations(model, model.rootCount, discardViewState);
  int remaining = model.drawing.records.program.limits.maxDecodedBytes;
  for (final (int, AiNativeLayer) entry in slots.indexed) {
    final AiNativeLayer source = layers[entry.$1];
    final AiNativeLayer slot = entry.$2;
    if (identical(source, slot)) {
      continue;
    }
    final List<int> bytes = _placedLayer(
      model,
      source,
      _layerInterval(model, source.start, source.end, headers),
      states[source.start]!,
      states[slot.start]!,
      states[slot.end]!,
      maxBytes: remaining - 1,
    );
    edits.add(AiSourceEdit(start: slot.start, end: slot.end, bytes: [10, ...bytes]));
    remaining -= bytes.length + 1;
  }
  return _layerLifecycleResult(model, edits, roots: model.rootCount);
}

/// Moves a complete layer while preserving state at its old and new positions.
AiNativeLayers _moveNativeLayer(AiNativeLayers model, AiNativeLayer layer, AiNativeLayer anchor, {required bool inside, required bool inheritParentFlags, required bool discardViewState}) {
  _qualifiedLayerHeader(model, layer);
  _qualifiedLayerHeader(model, anchor);
  if (layer.start <= anchor.start && layer.end >= anchor.end) {
    throw ArgumentError('A layer cannot move into or after its own subtree.');
  }
  final int? parent = inside ? anchor.index : anchor.parentIndex;
  if (layer.parentIndex != parent && !inheritParentFlags) {
    throw UnsupportedError('Changing a layer parent requires explicit inheritParentFlags.');
  }
  final int position = inside ? anchor.source.end.start : anchor.end;
  final int roots = model.rootCount + (parent == null ? 1 : 0) - (layer.parentIndex == null ? 1 : 0);
  final List<AiSourceEdit> edits = _layerDeclarations(model, roots, discardViewState);
  final Map<int, AiNativeLayer> headers = _layerHeaderItems(model);
  _layerLifecyclePrefix(model, layer, headers);
  _layerInterval(model, min(layer.start, position), max(layer.end, position), headers);
  final List<AiNativeInstruction> commands = _layerInterval(model, layer.start, layer.end, headers);
  final Map<int, _NativeArtworkState> states = _layerStates(model, [layer.start, position], headers);
  final int maxBytes = model.drawing.records.program.limits.maxDecodedBytes;
  final List<int> retained = _nativeSourceSpans(model.drawing.records.program, [
    for (final AiNativeInstruction item in commands)
      if (_nativeArtworkStateKey(item) != null) (start: item.start, end: item.end),
  ], maxBytes);
  final List<int> moved = _placedLayer(model, layer, commands, states[layer.start]!, states[position]!, states[position]!, maxBytes: maxBytes - retained.length - 2);
  edits.addAll([
    AiSourceEdit(start: layer.start, end: layer.end, bytes: [10, ...retained]),
    AiSourceEdit(start: position, end: position, bytes: [10, ...moved]),
  ]);
  return _layerLifecycleResult(model, edits, roots: roots);
}

/// Enumerates complete disjoint subtrees in source order, including their roots.
List<AiNativeLayer> _layerDescendants(AiNativeLayers model, List<AiNativeLayer> selected) => [
  for (final AiNativeLayer layer in selected) ..._pathInterval(model.layers, layer.start, layer.end, (child) => child.start),
];

/// Counts selected geometry/topology without treating layer headers as artwork.
({int paths, int groups}) _layerArtworkCounts(AiNativeLayers model, List<AiNativeLayer> selected) => (
  paths: selected.fold(0, (count, layer) => count + _pathInterval(model.drawing.paths, layer.start, layer.end, (path) => path.start).length),
  groups: selected.fold(0, (count, layer) => count + model.drawing.groups.where((group) => group.start >= layer.start && group.end <= layer.end).length),
);

/// Plans independent new identities and optional names for every copied owner.
List<AiSourceEdit> _layerCopyEdits(AiNativeLayers model, List<AiNativeLayer> descendants, Map<AiNativeLayer, List<int>> identifiers, Map<AiNativeLayer, List<int>> names) {
  final Set<AiNativeLayer> expected = descendants.where((layer) => layer.identifier != null).toSet();
  final Set<AiNativeLayer> named = descendants.where((layer) => layer.source.naming != null).toSet();
  if (identifiers.length != expected.length || identifiers.keys.any((layer) => !expected.contains(layer)) || names.keys.any((layer) => !named.contains(layer))) {
    throw ArgumentError('Copies require exactly their identified descendants and only owned existing display names.');
  }
  final Set<String> reserved = _layerIdentityNames(model);
  final List<AiSourceEdit> edits = [];
  int remaining = model.drawing.records.program.limits.maxDecodedBytes;
  for (final AiNativeLayer layer in descendants) {
    if (identifiers[layer] case final List<int> value) {
      final AiSourceEdit edit = _layerIdentityEdit(layer, value, reserved, remaining);
      edits.add(edit);
      remaining -= edit.bytes.length;
    }
    if (names[layer] case final List<int> value) {
      final AiToken token = layer.source.naming!.operands.single;
      final List<int> encoded = _layerString(value, remaining);
      edits.add(AiSourceEdit(start: token.start, end: token.end, bytes: encoded));
      remaining -= encoded.length;
    }
  }
  return edits;
}

/// Copies complete ordinary subtrees with new identities and retained paint state.
AiNativeLayers _duplicateNativeLayers(AiNativeLayers model, List<AiNativeLayer> layers, Map<AiNativeLayer, List<int>> identifiers, Map<AiNativeLayer, List<int>> names, bool discardViewState) {
  final List<AiNativeLayer> selected = _selectedLayers(model, layers);
  final List<AiNativeLayer> descendants = _layerDescendants(model, selected);
  final List<AiSourceEdit> replacements = _layerCopyEdits(model, descendants, identifiers, names);
  final int roots = model.rootCount + selected.where((layer) => layer.parentIndex == null).length;
  final List<AiSourceEdit> edits = _layerDeclarations(model, roots, discardViewState);
  final Map<int, AiNativeLayer> headers = _layerHeaderItems(model);
  final Map<int, _NativeArtworkState> states = _layerStates(model, selected.expand((layer) => [layer.start, layer.end]), headers);
  int remaining = model.drawing.records.program.limits.maxDecodedBytes;
  for (final AiNativeLayer layer in selected) {
    _layerLifecyclePrefix(model, layer, headers);
    final List<int> bytes = _placedLayer(
      model,
      layer,
      _layerInterval(model, layer.start, layer.end, headers),
      states[layer.start]!,
      states[layer.end]!,
      states[layer.end]!,
      maxBytes: remaining - 1,
      sourceEdits: replacements,
    );
    edits.add(AiSourceEdit(start: layer.end, end: layer.end, bytes: [10, ...bytes]));
    remaining -= bytes.length + 1;
  }
  final ({int paths, int groups}) count = _layerArtworkCounts(model, selected);
  return _layerLifecycleResult(
    model,
    edits,
    roots: roots,
    layers: model.layers.length + descendants.length,
    paths: model.drawing.paths.length + count.paths,
    groups: model.drawing.groups.length + count.groups,
  );
}

/// Refuses identity deletion unless all possible native reference owners qualify.
void _layerRemovalReferences(AiNativeLayers model, List<AiNativeLayer> descendants, Map<int, AiNativeLayer> headers) {
  final List<AiNativeLayer> identified = descendants.where((layer) => layer.identifier != null).toList();
  if (identified.isEmpty) {
    return;
  }
  final Set<AiNativeContainer> dictionaries = {
    for (final AiNativeLayer layer in model.layers)
      if (layer.dictionary != null && layer.bindingIssue == null) layer.dictionary!,
  };
  if (model.drawing.records.roots.any((record) => !dictionaries.contains(record))) {
    throw UnsupportedError('Deleting identified layers requires qualification of native document, resource and opaque reference owners.');
  }
  final Map<String, int> occurrences = {};
  for (final AiNativeObjectIdentifier identifier in model.structure.identifiers.where((identifier) => identifier.kind == .xmlArt)) {
    occurrences.update(latin1.decode(identifier.bytes), (count) => count + 1, ifAbsent: () => 1);
  }
  if (identified.any((layer) => occurrences[latin1.decode(layer.identifier!.bytes)] != 1)) {
    throw UnsupportedError('Deleting a layer requires an unambiguous native identity.');
  }
  final AiProgram program = model.drawing.records.program;
  _layerInterval(model, program.bodyStart, program.bodyEnd, headers);
  final Set<int> declarations = {if (model.rootCountHeader != null) model.rootCountHeader!.token.start, ...model.viewComments.map((token) => token.start)};
  const Set<String> markers = {'%%EndComments', '%%BeginProlog', '%%EndProlog', '%%BeginSetup', '%%EndSetup', '%%PageTrailer', '%%Trailer', '%%EOF'};
  const Set<String> fields = {'%%Creator', '%%Title', '%%For', '%%CreationDate', '%%BoundingBox', '%%HiResBoundingBox', '%%Pages', '%%Orientation', '%%PageOrder', '%%DocumentData', '%%LanguageLevel'};
  final RegExp native = RegExp(r'^%{1,2}AI');
  for (final AiToken token in model.drawing.records._projection.tokens) {
    if (token.start >= program.bodyStart && token.start < program.bodyEnd) {
      continue;
    }
    final bool unknown = native.hasMatch(token.lexeme) || token.lexeme.startsWith('%%') && !markers.contains(token.lexeme) && !fields.contains(token.lexeme.split(':').first);
    if (token.kind != .comment || !declarations.contains(token.start) && unknown) {
      throw UnsupportedError('Deleting identified layers requires a declarative source without unqualified external reference sections.');
    }
  }
}

/// Deletes complete subtrees and retains only their persistent state assignments.
AiNativeLayers _removeNativeLayers(AiNativeLayers model, List<AiNativeLayer> layers, bool discardViewState) {
  final List<AiNativeLayer> selected = _selectedLayers(model, layers);
  final List<AiNativeLayer> descendants = _layerDescendants(model, selected);
  final Map<int, AiNativeLayer> headers = _layerHeaderItems(model);
  _layerRemovalReferences(model, descendants, headers);
  final int roots = model.rootCount - selected.where((layer) => layer.parentIndex == null).length;
  final List<AiSourceEdit> edits = _layerDeclarations(model, roots, discardViewState);
  int remaining = model.drawing.records.program.limits.maxDecodedBytes;
  for (final AiNativeLayer layer in selected) {
    _layerLifecyclePrefix(model, layer, headers);
    final List<AiNativeInstruction> commands = _layerInterval(model, layer.start, layer.end, headers);
    final List<int> state = _nativeSourceSpans(model.drawing.records.program, [
      for (final AiNativeInstruction item in commands)
        if (_nativeArtworkStateKey(item) != null) (start: item.start, end: item.end),
    ], remaining - 1);
    edits.add(AiSourceEdit(start: layer.start, end: layer.end, bytes: [10, ...state]));
    remaining -= state.length + 1;
  }
  final ({int paths, int groups}) count = _layerArtworkCounts(model, selected);
  return _layerLifecycleResult(
    model,
    edits,
    roots: roots,
    layers: model.layers.length - descendants.length,
    paths: model.drawing.paths.length - count.paths,
    groups: model.drawing.groups.length - count.groups,
  );
}
