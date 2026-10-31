part of 'package:aikit/src/model/ai_native_records.dart';

/// Known persistent assignments and the last boundary invalidating unknown values.
final class _NativeArtworkState {
  /// Last explicit source assignment for each qualified state component.
  final Map<String, AiNativeInstruction> values;

  /// Opaque boundary identity; absent values across different barriers differ.
  final int barrier;

  /// Freezes a source state without guessing defaults after unknown instructions.
  _NativeArtworkState({required Map<String, AiNativeInstruction> values, required this.barrier}) : values = Map.unmodifiable(values);

  /// Requires matching known values or the same unchanged unknown provenance.
  bool matches(_NativeArtworkState other, String key) => values[key] == null && other.values[key] == null ? barrier == other.barrier : _sameGroupState(values[key], other.values[key]);
}

/// Captures state while retaining the provenance of unknown inherited values.
Map<int, _NativeArtworkState> _nativeArtworkStates(AiNativeDrawing drawing, Iterable<int> boundaries, {Set<int> structural = const {}}) {
  final List<int> positions = boundaries.toSet().toList()..sort();
  final Map<int, _NativeArtworkState> result = {};
  final Map<String, AiNativeInstruction> state = {};
  int index = 0;
  int barrier = -1;
  for (final int position in positions) {
    while (index < drawing.items.length && drawing.items[index].end <= position) {
      final AiNativeItem item = drawing.items[index++];
      if (structural.contains(item.start)) {
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
    result[position] = _NativeArtworkState(values: state, barrier: barrier);
  }
  return result;
}

/// Serializes only owned source spans under an aggregate output budget.
List<int> _nativeSourceSpans(AiProgram program, Iterable<({int start, int end})> spans, int maxBytes, {List<AiSourceEdit> edits = const []}) {
  final BytesBuilder result = BytesBuilder(copy: false);
  for (final ({int start, int end}) span in spans) {
    final List<AiSourceEdit> replacements = edits.where((edit) => edit.start >= span.start && edit.end <= span.end).toList();
    final int length = span.end - span.start + replacements.fold(0, (count, edit) => count + edit.bytes.length - (edit.end - edit.start));
    if (result.length + length + 1 > maxBytes) {
      throw const AiLimitException(message: 'Native artwork output exceeds the native byte limit.');
    }
    result.add(replacements.isEmpty ? Uint8List.sublistView(program.bytes, span.start, span.end) : AiNativeEditor.copyRange(program: program, start: span.start, end: span.end, edits: replacements));
    result.addByte(10);
  }
  return result.takeBytes();
}

/// Replays source values around owned artwork, retaining both boundary states.
List<int> _placedNativeArtwork(
  AiProgram program,
  Iterable<({int start, int end})> spans,
  List<AiNativeInstruction> commands,
  _NativeArtworkState source,
  _NativeArtworkState incoming,
  _NativeArtworkState outgoing, {
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
        throw UnsupportedError('The placed artwork requires an unknown inherited $key value.');
      }
      prefix.add(value);
      actual[key] = value;
    }
  }
  actual.addAll(writes);
  final List<AiNativeInstruction> suffix = [];
  final _NativeArtworkState resulting = _NativeArtworkState(values: actual, barrier: incoming.barrier);
  for (final String key in _groupStateKeys) {
    if (!resulting.matches(outgoing, key)) {
      final AiNativeInstruction? value = outgoing.values[key];
      if (value == null) {
        throw UnsupportedError('The placed artwork cannot restore an unknown outgoing $key value.');
      }
      suffix.add(value);
    }
  }
  return _nativeSourceSpans(
    program,
    [
      for (final AiNativeInstruction item in prefix) (start: item.start, end: item.end),
      ...spans,
      for (final AiNativeInstruction item in suffix) (start: item.start, end: item.end),
    ],
    maxBytes,
    edits: sourceEdits,
  );
}
