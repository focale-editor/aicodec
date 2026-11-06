part of 'package:illustratorkit/src/model/ai_native_records.dart';

/// Complete selected byte owners, including their attached metadata.
typedef _NativeSubtreeSpan = ({int start, int end});

/// Counts authoritative shapes once, including separate saved metadata branches.
int _subtreeLiveShapeCount(AiNativeDrawing drawing, List<_NativeSubtreeSpan> spans) =>
    drawing.liveShapes.where((shape) => spans.any((span) => shape.start >= span.start && shape.end <= span.end)).length;

/// Qualifies every intersecting nonordinary shape without cutting either view.
List<_NativeShapeBundle> _subtreeShapeBundles(AiNativeDrawing drawing, List<_NativeSubtreeSpan> spans, {List<AiNativeAppearanceArtwork> appearanceArtwork = const []}) {
  final List<_NativeShapeBundle> result = [];
  for (final AiLiveShape shape in drawing.liveShapes.where((shape) => _directNativeShapeIssue(shape) != null)) {
    if (appearanceArtwork.any((owner) => identical(owner.liveShape, shape)) || !spans.any((span) => shape.start < span.end && shape.end > span.start)) {
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

  final List<_NativeSubtreeSpan> owned = [
    for (final _NativeShapeBundle pair in pairs.where((pair) => pair.start >= start && pair.shape.end <= end)) (start: pair.start, end: pair.shape.end),
    for (final AiNativeAppearanceArtwork owner in _subtreeAppearances(appearanceArtwork, start, end)) (start: owner.start, end: owner.end),
  ]..sort((first, second) => first.start.compareTo(second.start));
  int position = start;
  for (final _NativeSubtreeSpan pair in owned) {
    if (pair.start < position) {
      throw UnsupportedError('Subtree appearance owners cannot overlap.');
    }
    interval(position, pair.start);
    position = pair.end;
  }
  interval(position, end);
  return commands;
}

/// Selects whole appearance pairs and rejects partial representation ownership.
List<AiNativeAppearanceArtwork> _subtreeAppearances(List<AiNativeAppearanceArtwork> artwork, int start, int end) {
  final List<AiNativeAppearanceArtwork> selected = [];
  for (final AiNativeAppearanceArtwork owner in artwork) {
    if (owner.start >= end || owner.end <= start) {
      continue;
    }
    if (owner.start < start || owner.end > end) {
      throw UnsupportedError('A subtree operation cannot split a complete appearance pair.');
    }
    selected.add(owner);
  }
  return selected;
}

/// Combines qualified commands without changing source bytes or private scopes.
List<AiNativeInstruction> _subtreeCommands(List<AiNativeInstruction> ordinary, List<_NativeShapeBundle> pairs, List<AiNativeAppearanceArtwork> artwork) => [
  ...ordinary,
  for (final _NativeShapeBundle pair in pairs) ...pair.commands,
  for (final AiNativeAppearanceArtwork owner in artwork) ...owner._commands,
]..sort((first, second) => first.start.compareTo(second.start));
