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
List<AiNativeInstruction> _subtreeOrdinaryCommands(
  AiNativeLayers model,
  int start,
  int end,
  List<_NativeShapeBundle> pairs, {
  bool groups = false,
  List<AiNativeAppearanceArtwork> appearanceArtwork = const [],
}) {
  final List<AiNativeInstruction> commands = [];
  final Map<int, AiNativeLayer> headers = _layerHeaderItems(model);

  /// Keeps private scalar replay separate from private geometry and opaque owners.
  void interval(int first, int last) {
    commands.addAll(
      groups
          ? _groupInterval(model.drawing, first, last, privateState: true, retainImages: true)
          : _layerInterval(model, first, last, headers, privateState: true, retainImages: true, appearanceArtwork: appearanceArtwork),
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
