part of 'package:aikit/src/model/ai_native_records.dart';

/// Retains explicit public/private assignments without applying an orphaned style.
List<int> _removedShapeState(_NativeShapeBundle bundle, Map<String, AiNativeInstruction> restored, int maxBytes) {
  final StringBuffer output = StringBuffer('\n');

  /// Bounds each retained or restored literal before appending its source text.
  void append(AiNativeInstruction value, {required bool private}) {
    final String text = _shapeStateText(value, private: private);
    if (output.length + text.length > maxBytes) {
      throw const AiLimitException(message: 'Removed shape state exceeds the native byte limit.');
    }
    output.write(text);
  }

  for (final AiNativeInstruction command in bundle.commands) {
    if (_nativeArtworkStateKey(command) == null) {
      continue;
    }
    append(command, private: command.isPrivate);
  }
  for (final AiNativeInstruction value in restored.values) {
    append(value, private: true);
  }
  return latin1.encode(output.toString());
}

/// Proves that retained objects never consume unresolved removed-style effects.
void _shapeRemovalDependencies(AiNativeDrawing drawing, List<_NativeShapeBundle> selected, Map<AiLiveShape, Map<String, AiNativeInstruction>> restored) {
  final Set<String> unresolved = {};
  final AiNativeLayers layers = AiNativeLayers.decode(drawing: drawing);
  final Map<int, AiNativeLayer> headers = _layerHeaderItems(layers);
  final Map<AiLiveShape, _NativeShapeBundle> removed = {for (final _NativeShapeBundle bundle in selected) bundle.shape: bundle};
  final Map<int, AiNativePath> paths = {for (final AiNativePath path in drawing.paths) path.start: path};

  /// Requires identical incoming attributes wherever retained artwork reads them.
  void read(Set<String> keys) {
    final Set<String> missing = unresolved.intersection(keys);
    if (missing.isNotEmpty) {
      throw UnsupportedError('Following artwork depends on removed native style state: ${missing.join(', ')}.');
    }
  }

  /// Accounts for retained assignments before each path or group observes state.
  void command(AiNativeInstruction item, {bool discard = false, _NativeShapeBundle? bundle}) {
    final String? key = _nativeArtworkStateKey(item);
    if (key != null) {
      unresolved.remove(key);
      return;
    }
    if (discard) {
      if (_marker(item, 1)) {
        unresolved.addAll(bundle!.styleWrites);
        unresolved.removeAll(restored[bundle.shape]!.keys);
      }
      return;
    }
    if (paths[item.start] case final AiNativePath path) {
      read(_shapeCopyReads(drawing, path));
    } else if (const {'u', '*u'}.contains(item.operator)) {
      read({'A', 'Xw'});
    } else if (_marker(item, 6)) {
      read({'Xy'});
    } else if (_marker(item, 1)) {
      read(bundle!.styleReads);
      // Potential writes are not definite writes: hidden filter parts may not
      // execute. Keep unresolved keys until an explicit assignment replaces them.
    }
  }

  /// Qualifies ordinary intervening artwork only while state may still differ.
  void interval(int start, int end) {
    if (unresolved.isEmpty || start == end) {
      return;
    }
    _layerInterval(layers, start, end, headers).forEach(command);
  }

  int position = selected.first.start;
  for (final AiLiveShape shape in drawing.liveShapes.where((shape) => shape.isBound && shape.appearanceGroup != null && shape.path?.isPrivate == true && shape.end > position)) {
    final int start = drawing._objects.forSource(shape.appearanceGroup!).expansion?.start ?? shape.start;
    interval(position, start);
    if (removed.containsKey(shape) || unresolved.isNotEmpty) {
      final _NativeShapeBundle bundle = removed[shape] ?? _shapeBundle(drawing, shape, layers.structure);
      for (final AiNativeInstruction item in bundle.commands) {
        command(item, discard: removed.containsKey(shape), bundle: bundle);
      }
    }
    position = shape.end;
  }
  interval(position, drawing.records.program.bodyEnd);
}

/// Qualifies every possible reference owner before deleting saved pair identities.
void _shapeRemovalReferences(AiNativeDrawing drawing, List<_NativeShapeBundle> selected) {
  final AiNativeStructure structure = drawing._objects.structure;
  final List<AiNativeObjectIdentifier> identifiers = structure.identifiers
      .where((identifier) => selected.any((bundle) => identifier.field.owner.start >= bundle.start && identifier.field.owner.end <= bundle.shape.end))
      .toList();
  if (identifiers.isEmpty) {
    return;
  }
  final List<_NativeShapeBundle> bundles = _selectedShapeBundles(
    drawing,
    drawing.liveShapes.where((shape) => shape.appearanceGroup != null || shape.path?.isPrivate == true).toList(),
  );
  final AiNativeLayers layers = AiNativeLayers.decode(drawing: drawing);
  _nativeRemovalReferences(layers, identifiers, _layerHeaderItems(layers), shapes: bundles);
}

/// Removes disjoint complete pairs while preserving observable native state.
AiNativeDrawing _removeNativeShapes(AiNativeDrawing drawing, List<AiLiveShape> shapes) {
  final List<_NativeShapeBundle> selected = _selectedShapeBundles(drawing, shapes);
  _shapeRemovalReferences(drawing, selected);
  final Map<int, _NativeShapeInputs> states = _shapeCopyInputs(drawing, selected.map((bundle) => bundle.shape.end));
  final Map<AiLiveShape, Map<String, AiNativeInstruction>> restored = {
    for (final _NativeShapeBundle bundle in selected)
      bundle.shape: {
        for (final String key in bundle.styleWrites)
          if (states[bundle.shape.end]!.native[key] case final AiNativeInstruction value) key: value,
      },
  };
  _shapeRemovalDependencies(drawing, selected, restored);
  final List<AiSourceEdit> edits = [];
  int remaining = drawing.records.program.limits.maxDecodedBytes;
  for (final _NativeShapeBundle bundle in selected) {
    final List<int> state = _removedShapeState(bundle, restored[bundle.shape]!, remaining);
    edits.add(AiSourceEdit(start: bundle.start, end: bundle.shape.end, bytes: state));
    remaining -= state.length;
  }
  return _groupLifecycleResult(
    drawing,
    edits,
    paths: drawing.paths.length - shapes.fold(0, (count, shape) => count + shape.appearancePaths.length + 1),
    groups: drawing.groups.length - selected.fold(0, (count, bundle) => count + drawing.groups.where((group) => group.start >= bundle.start && group.end <= bundle.shape.end).length),
    liveShapes: drawing.liveShapes.length - shapes.length,
  );
}
