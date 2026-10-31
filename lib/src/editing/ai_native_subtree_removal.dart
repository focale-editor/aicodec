part of 'package:aikit/src/model/ai_native_records.dart';

/// Removes whole mixed subtrees while retaining both streams' persistent effects.
List<AiSourceEdit> _removedNativeSubtrees(AiNativeLayers model, List<_NativeSubtreeSpan> spans, List<_NativeShapeBundle> pairs, {bool groups = false}) {
  final AiNativeDrawing drawing = model.drawing;
  final Map<_NativeSubtreeSpan, List<AiNativeInstruction>> ordinary = {
    for (final _NativeSubtreeSpan span in spans) span: _subtreeOrdinaryCommands(model, span.start, span.end, pairs, groups: groups),
  };
  _nativeRemovalReferences(model, [
    for (final AiNativeObjectIdentifier identifier in model.structure.identifiers)
      if (spans.any((span) => identifier.field.owner.start >= span.start && identifier.field.owner.end <= span.end)) identifier,
  ], _layerHeaderItems(model));
  final Map<int, _NativeShapeInputs> states = _shapeCopyInputs(drawing, pairs.map((pair) => pair.shape.end));
  final Map<AiLiveShape, Map<String, AiNativeInstruction>> restored = {
    for (final _NativeShapeBundle pair in pairs) pair.shape: _restoredShapeStyle(pair, states[pair.shape.end]!),
  };
  _shapeFollowingDependencies(drawing, pairs, {
    for (final _NativeShapeBundle pair in pairs) pair.shape: _removedShapeReplacement(pair, restored[pair.shape]!),
  }, discarded: spans);
  final List<AiSourceEdit> edits = [];
  int remaining = drawing.records.program.limits.maxDecodedBytes;
  for (final _NativeSubtreeSpan span in spans) {
    final BytesBuilder bytes = BytesBuilder(copy: false);

    /// Bounds state replay under the same aggregate limit as the source editor.
    void append(List<int> value) {
      if (bytes.length + value.length > remaining) {
        throw const AiLimitException(message: 'Removed subtree state exceeds the native byte limit.');
      }
      bytes.add(value);
    }

    append([10]);
    final List<AiNativeInstruction> commands = ordinary[span]!;
    int index = 0;

    /// Replays assignments in source order without retaining deleted geometry.
    void through(int boundary) {
      while (index < commands.length && commands[index].start < boundary) {
        final AiNativeInstruction item = commands[index++];
        if (_nativeArtworkStateKey(item) != null) {
          append(latin1.encode(_shapeStateText(item, private: item.isPrivate)));
        }
      }
    }

    for (final _NativeShapeBundle pair in pairs.where((pair) => pair.start >= span.start && pair.shape.end <= span.end)) {
      through(pair.start);
      append(_removedShapeState(pair, restored[pair.shape]!, remaining - bytes.length));
    }
    through(span.end);
    edits.add(AiSourceEdit(start: span.start, end: span.end, bytes: bytes.takeBytes()));
    remaining -= edits.last.bytes.length;
  }
  return edits;
}
