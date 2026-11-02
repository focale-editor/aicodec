part of 'package:aicodec/src/model/ai_native_records.dart';

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

/// Qualifies every possible reference owner before deleting saved pair identities.
void _shapeRemovalReferences(AiNativeDrawing drawing, List<_NativeShapeBundle> selected) {
  final AiNativeStructure structure = drawing._objects.structure;
  final List<AiNativeObjectIdentifier> identifiers = structure.identifiers
      .where((identifier) => selected.any((bundle) => identifier.field.owner.start >= bundle.start && identifier.field.owner.end <= bundle.shape.end))
      .toList();
  if (identifiers.isEmpty) {
    return;
  }
  final AiNativeLayers layers = AiNativeLayers.decode(drawing: drawing);
  _nativeRemovalReferences(layers, identifiers, _layerHeaderItems(layers));
}

/// Selects definite outgoing style scalars without synthesizing unknown effects.
Map<String, AiNativeInstruction> _restoredShapeStyle(_NativeShapeBundle bundle, _NativeShapeInputs state) => {
  for (final String key in bundle.styleWrites)
    if (state.native[key] case final AiNativeInstruction value) key: value,
};

/// Describes retained assignments after removing an object's complete source span.
_NativeShapeReplacement _removedShapeReplacement(_NativeShapeBundle bundle, Map<String, AiNativeInstruction> restored) => (
  bundle: bundle,
  prefix: [],
  suffix: [for (final AiNativeInstruction value in restored.values) (value: value, private: true)],
  unresolved: bundle.styleWrites.difference(restored.keys.toSet()),
  printingUnresolved: {},
  discard: true,
);

/// Removes disjoint complete pairs while preserving observable native state.
AiNativeDrawing _removeNativeShapes(AiNativeDrawing drawing, List<AiLiveShape> shapes) {
  final List<_NativeShapeBundle> selected = _selectedShapeBundles(drawing, shapes);
  _shapeRemovalReferences(drawing, selected);
  final Map<int, _NativeShapeInputs> states = _shapeCopyInputs(drawing, selected.map((bundle) => bundle.shape.end));
  final Map<AiLiveShape, Map<String, AiNativeInstruction>> restored = {
    for (final _NativeShapeBundle bundle in selected) bundle.shape: _restoredShapeStyle(bundle, states[bundle.shape.end]!),
  };
  _shapeFollowingDependencies(drawing, selected, {
    for (final _NativeShapeBundle bundle in selected) bundle.shape: _removedShapeReplacement(bundle, restored[bundle.shape]!),
  });
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
