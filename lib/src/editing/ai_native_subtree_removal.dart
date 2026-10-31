part of 'package:aikit/src/model/ai_native_records.dart';

/// Complete selected byte owners, including their attached metadata.
typedef _NativeSubtreeSpan = ({int start, int end});

/// Counts authoritative shapes once, including separate saved metadata branches.
int _subtreeLiveShapeCount(AiNativeDrawing drawing, List<_NativeSubtreeSpan> spans) =>
    drawing.liveShapes.where((shape) => spans.any((span) => shape.start >= span.start && shape.end <= span.end)).length;

/// Qualifies every intersecting nonordinary shape without cutting either view.
List<_NativeShapeBundle> _subtreeShapeBundles(AiNativeDrawing drawing, List<_NativeSubtreeSpan> spans) {
  final List<_NativeShapeBundle> result = [];
  for (final AiLiveShape shape in drawing.liveShapes.where((shape) => _directNativeShapeIssue(shape) != null)) {
    if (!spans.any((span) => shape.start < span.end && shape.end > span.start)) {
      continue;
    }
    final _NativeShapeBundle bundle = _shapeBundle(drawing, shape, drawing._objects.structure);
    if (!spans.any((span) => bundle.start >= span.start && shape.end <= span.end)) {
      throw UnsupportedError('A subtree operation cannot split a complete authoring/printing pair.');
    }
    result.add(bundle);
  }
  return result;
}

/// Visits ordinary intervals around complete pairs without flattening their data.
List<AiNativeInstruction> _subtreeOrdinaryCommands(AiNativeLayers model, int start, int end, List<_NativeShapeBundle> pairs, {bool groups = false}) {
  final List<AiNativeInstruction> commands = [];
  final Map<int, AiNativeLayer> headers = _layerHeaderItems(model);

  /// Keeps private scalar replay separate from private geometry and opaque owners.
  void interval(int first, int last) {
    commands.addAll(
      groups ? _groupInterval(model.drawing, first, last, privateState: true) : _layerInterval(model, first, last, headers, privateState: true),
    );
  }

  int position = start;
  for (final _NativeShapeBundle pair in pairs.where((pair) => pair.start >= start && pair.shape.end <= end)) {
    interval(position, pair.start);
    position = pair.shape.end;
  }
  interval(position, end);
  return commands;
}

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
