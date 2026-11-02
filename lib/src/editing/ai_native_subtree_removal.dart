part of 'package:aicodec/src/model/ai_native_records.dart';

/// Retains assignments and definite style scalars after a complete owner leaves.
({List<int> bytes, _NativeSourceReplacement replacement}) _retainedSubtreeState(
  List<AiNativeInstruction> ordinary,
  List<_NativeShapeBundle> pairs,
  Map<int, _NativeShapeInputs> states,
  int maxBytes,
) {
  final List<AiNativeInstruction> commands = [...ordinary, for (final _NativeShapeBundle pair in pairs) ...pair.commands]..sort((first, second) => first.start.compareTo(second.start));
  final Map<int, _NativeShapeBundle> styles = {for (final _NativeShapeBundle pair in pairs) pair.shape.end: pair};
  final List<_NativeShapeReplay> replay = [];
  final Set<String> unresolved = {};
  final StringBuffer bytes = StringBuffer('\n');

  /// Bounds retained scalar replay without retaining removed private geometry.
  void append(AiNativeInstruction value, {required bool private}) {
    final String text = _shapeStateText(value, private: private);
    if (bytes.length + text.length > maxBytes) {
      throw const AiLimitException(message: 'Retained subtree state exceeds the native byte limit.');
    }
    bytes.write(text);
    replay.add((value: value, private: private));
    unresolved.remove(_nativeArtworkStateKey(value));
  }

  for (final AiNativeInstruction command in commands) {
    if (_nativeArtworkStateKey(command) != null) {
      append(command, private: command.isPrivate);
    } else if (styles[command.end] case final _NativeShapeBundle pair when _marker(command, 1)) {
      final Map<String, AiNativeInstruction> restored = _restoredShapeStyle(pair, states[pair.shape.end]!);
      for (final AiNativeInstruction value in restored.values) {
        append(value, private: true);
      }
      unresolved.addAll(pair.styleWrites.difference(restored.keys.toSet()));
    }
  }
  return (
    bytes: latin1.encode(bytes.toString()),
    replacement: (commands: [], styles: {}, prefix: replay, suffix: [], unresolved: unresolved, printingUnresolved: {}, discard: true),
  );
}

/// Removes whole mixed subtrees while retaining both streams' persistent effects.
List<AiSourceEdit> _removedNativeSubtrees(
  AiNativeLayers model,
  List<_NativeSubtreeSpan> spans,
  List<_NativeShapeBundle> pairs, {
  bool groups = false,
  List<AiNativeAppearanceArtwork> appearanceArtwork = const [],
}) {
  final AiNativeDrawing drawing = model.drawing;
  final List<AiNativeObjectIdentifier> identifiers = [
    for (final AiNativeObjectIdentifier identifier in model.structure.identifiers)
      if (spans.any((span) => identifier.field.owner.start >= span.start && identifier.field.owner.end <= span.end)) identifier,
  ];
  _nativeRemovalReferences(
    model,
    identifiers,
    _layerHeaderItems(model),
    bodyDictionaries: identifiers.isEmpty || appearanceArtwork.isEmpty
        ? null
        : _nativeReferenceBody(
            model,
            _layerHeaderItems(model),
            inspect: _nativeAppearanceInterval,
            qualifyShapeNeighbors: false,
            clipping: true,
            appearanceArtwork: appearanceArtwork,
          ),
  );
  final Map<int, _NativeShapeInputs> states = _shapeCopyInputs(
    drawing,
    [
      ...pairs.map((pair) => pair.shape.end),
      ...spans.expand((span) => [span.start, span.end]),
    ],
    appearanceArtwork: appearanceArtwork,
    clipping: appearanceArtwork.isNotEmpty,
  );
  final List<AiSourceEdit> edits = [];
  final Map<_NativeSubtreeSpan, _NativeSourceReplacement> replacements = {};
  int remaining = drawing.records.program.limits.maxDecodedBytes;
  for (final _NativeSubtreeSpan span in spans) {
    final List<_NativeShapeBundle> selected = pairs.where((pair) => pair.start >= span.start && pair.shape.end <= span.end).toList();
    final List<AiNativeInstruction> ordinary = _subtreeOrdinaryCommands(model, span.start, span.end, selected, groups: groups, appearanceArtwork: appearanceArtwork);
    final List<AiNativeAppearanceArtwork> appearances = _subtreeAppearances(appearanceArtwork, span.start, span.end);
    final ({List<int> bytes, _NativeSourceReplacement replacement}) retained = appearances.isEmpty
        ? _retainedSubtreeState(ordinary, selected, states, remaining)
        : _removedAppearanceState(_subtreeCopyAccess(drawing, ordinary, selected, states, appearanceArtwork: appearances), states[span.start]!, states[span.end]!, remaining);
    edits.add(AiSourceEdit(start: span.start, end: span.end, bytes: retained.bytes));
    replacements[span] = retained.replacement;
    remaining -= retained.bytes.length;
  }
  _sourceFollowingDependencies(drawing, replacements, retainedArtwork: appearanceArtwork, clipping: appearanceArtwork.isNotEmpty);
  return edits;
}
