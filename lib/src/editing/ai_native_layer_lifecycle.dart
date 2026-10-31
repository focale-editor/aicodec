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
    } else if (_groupStateKey(item) == null) {
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

/// Known persistent assignments and the last boundary invalidating unknown values.
final class _NativeLayerState {
  /// Last explicit source assignment for each qualified state component.
  final Map<String, AiNativeInstruction> values;

  /// Opaque boundary identity; absent values across different barriers differ.
  final int barrier;

  /// Freezes a source state without guessing defaults after unknown instructions.
  _NativeLayerState({required Map<String, AiNativeInstruction> values, required this.barrier}) : values = Map.unmodifiable(values);

  /// Requires matching known values or the same unchanged unknown provenance.
  bool matches(_NativeLayerState other, String key) => values[key] == null && other.values[key] == null ? barrier == other.barrier : _sameGroupState(values[key], other.values[key]);
}

/// Reads state across layer boundaries, which do not save or restore paint.
Map<int, _NativeLayerState> _layerStates(AiNativeLayers model, Iterable<int> boundaries, Map<int, AiNativeLayer> headers) {
  final List<int> positions = boundaries.toSet().toList()..sort();
  final Map<int, _NativeLayerState> result = {};
  final Map<String, AiNativeInstruction> state = {};
  int index = 0;
  int barrier = -1;
  for (final int position in positions) {
    while (index < model.drawing.items.length && model.drawing.items[index].end <= position) {
      final AiNativeItem item = model.drawing.items[index++];
      if (headers[item.start] case final AiNativeLayer owner when owner.bindingIssue == null) {
        continue;
      }
      if (item is AiNativeInstruction && !item.isPrivate) {
        try {
          final String? key = _groupStateKey(item);
          if (key != null) {
            state[key] = item;
            continue;
          }
          if (_nativeGeometry.contains(item.operator) || _nativePaint.contains(item.operator) || const {'u', 'U', 'As'}.contains(item.operator)) {
            continue;
          }
        } on FormatException {
          // Malformed unrelated state grants no inherited value to a later edit.
        }
      }
      state.clear();
      barrier = item.start;
    }
    result[position] = _NativeLayerState(values: state, barrier: barrier);
  }
  return result;
}

/// Serializes only owned source spans under an aggregate output budget.
List<int> _layerSourceSpans(AiProgram program, Iterable<({int start, int end})> spans, int maxBytes, {List<AiSourceEdit> edits = const []}) {
  final BytesBuilder result = BytesBuilder(copy: false);
  for (final ({int start, int end}) span in spans) {
    final List<AiSourceEdit> replacements = edits.where((edit) => edit.start >= span.start && edit.end <= span.end).toList();
    final int length = span.end - span.start + replacements.fold(0, (count, edit) => count + edit.bytes.length - (edit.end - edit.start));
    if (result.length + length + 1 > maxBytes) {
      throw const AiLimitException(message: 'Layer lifecycle output exceeds the native byte limit.');
    }
    result.add(replacements.isEmpty ? Uint8List.sublistView(program.bytes, span.start, span.end) : AiNativeEditor.copyRange(program: program, start: span.start, end: span.end, edits: replacements));
    result.addByte(10);
  }
  return result.takeBytes();
}

/// Replays source values around a moved subtree to retain both boundary states.
List<int> _placedLayer(
  AiNativeLayers model,
  AiNativeLayer layer,
  List<AiNativeInstruction> commands,
  _NativeLayerState source,
  _NativeLayerState incoming,
  _NativeLayerState outgoing, {
  required int maxBytes,
  List<AiSourceEdit> sourceEdits = const [],
}) {
  final Set<String> required = {};
  final Map<String, AiNativeInstruction> writes = {};
  for (final AiNativeInstruction command in commands) {
    final String? key = _groupStateKey(command);
    if (key != null) {
      writes[key] = command;
    } else if (command.operator == 'u' || command.operator == 'm') {
      required.addAll((command.operator == 'u' ? const {'A', 'Xw'} : _groupStateKeys).where((key) => !writes.containsKey(key)));
    }
  }
  final Map<String, AiNativeInstruction> actual = Map.of(incoming.values);
  final List<AiNativeInstruction> prefix = [];
  for (final String key in required) {
    if (!source.matches(incoming, key)) {
      final AiNativeInstruction? value = source.values[key];
      if (value == null) {
        throw UnsupportedError('The placed layer requires an unknown inherited $key value.');
      }
      prefix.add(value);
      actual[key] = value;
    }
  }
  actual.addAll(writes);
  final List<AiNativeInstruction> suffix = [];
  final _NativeLayerState resulting = _NativeLayerState(values: actual, barrier: incoming.barrier);
  for (final String key in _groupStateKeys) {
    if (!resulting.matches(outgoing, key)) {
      final AiNativeInstruction? value = outgoing.values[key];
      if (value == null) {
        throw UnsupportedError('The placed layer cannot restore an unknown outgoing $key value.');
      }
      suffix.add(value);
    }
  }
  return _layerSourceSpans(
    model.drawing.records.program,
    [
      for (final AiNativeInstruction item in prefix) (start: item.start, end: item.end),
      (start: layer.start, end: layer.end),
      for (final AiNativeInstruction item in suffix) (start: item.start, end: item.end),
    ],
    maxBytes,
    edits: sourceEdits,
  );
}

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
  final Map<int, _NativeLayerState> states = _layerStates(model, slots.expand((layer) => [layer.start, layer.end]), headers);
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
  final Map<int, _NativeLayerState> states = _layerStates(model, [layer.start, position], headers);
  final int maxBytes = model.drawing.records.program.limits.maxDecodedBytes;
  final List<int> retained = _layerSourceSpans(model.drawing.records.program, [
    for (final AiNativeInstruction item in commands)
      if (_groupStateKey(item) != null) (start: item.start, end: item.end),
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
  final Map<int, _NativeLayerState> states = _layerStates(model, selected.expand((layer) => [layer.start, layer.end]), headers);
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
    final List<int> state = _layerSourceSpans(model.drawing.records.program, [
      for (final AiNativeInstruction item in commands)
        if (_groupStateKey(item) != null) (start: item.start, end: item.end),
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
