part of 'package:aikit/src/model/ai_native_records.dart';

/// Copies mutable scalar maps before simulating one relocated contour branch.
_NativeShapeInputs _nativeContourSnapshot(_NativeShapeInputs state) => (
  printing: Map.of(state.printing),
  native: Map.of(state.native),
  printingOrigins: Map.of(state.printingOrigins),
  nativeOrigins: Map.of(state.nativeOrigins),
);

/// Places branches while accounting for deferred paint and newly active clips.
List<int> _nativeContourBranchPlacement(
  AiNativeDrawing drawing,
  AiNativeObject owner,
  List<AiNativeInstruction> commands,
  Map<int, _NativeShapeInputs> states,
  _NativeShapeInputs destination,
  _NativeContourDifferences changed, {
  required AiNativeGroup? sourceCompound,
  required AiNativeGroup? targetCompound,
  required int maxBytes,
}) {
  final _NativeShapeInputs current = _nativeContourSnapshot(destination);
  // Earlier placed owners may leave an unrestorable value. Its original unknown
  // provenance is no longer valid, even if both inputs were originally unknown.
  for (final String key in changed.printing) {
    current.printing.remove(key);
    current.printingOrigins[key] = -2;
  }
  for (final String key in changed.native) {
    current.native.remove(key);
    current.nativeOrigins[key] = -2;
  }
  final Map<int, AiNativePath> paths = {for (final AiNativePath path in drawing.paths) path.start: path};
  final Map<int, AiNativeGroup> endings = {for (final AiNativeGroup group in drawing.groups) group.closing.start: group};
  final BytesBuilder bytes = BytesBuilder(copy: false);
  final List<_NativeShapeInputs?> clips = [];
  int compoundDepth = targetCompound == null ? 0 : 1;
  int position = owner.start;

  /// Bounds original bytes and scalar replay under the same output ceiling.
  void append(List<int> value) {
    if (bytes.length + value.length > maxBytes) {
      throw const AiLimitException(message: 'Moved contour branches exceed the source byte limit.');
    }
    bytes.add(value);
  }

  /// Replays required values and records their actual effects in both streams.
  _NativeClipReplay replay(_NativeShapeInputs target, Set<String> keys, {bool allowUnknown = false}) {
    final _NativeClipReplay result = _nativeClipStateReplay(drawing, current, target, keys: keys, maxBytes: maxBytes - bytes.length, allowUnknown: allowUnknown);
    append(result.bytes);
    for (final String key in result.assigned.printing) {
      current.printing[key] = target.printing[key]!;
      current.native[key] = target.printing[key]!;
    }
    for (final String key in result.assigned.native) {
      if (target.native[key] case final AiNativeInstruction value) {
        current.native[key] = value;
      }
    }
    return result;
  }

  /// Restores only attributes actually scoped by the Illustrator clip operators.
  void restore(_NativeShapeInputs saved) {
    for (final String key in _nativeClipStateKeys) {
      current.printing.remove(key);
      current.native.remove(key);
      if (saved.printing[key] case final AiNativeInstruction value) {
        current.printing[key] = value;
      }
      if (saved.native[key] case final AiNativeInstruction value) {
        current.native[key] = value;
      }
      current.printingOrigins[key] = saved.printingOrigins[key]!;
      current.nativeOrigins[key] = saved.nativeOrigins[key]!;
    }
  }

  append([10]);
  for (final AiNativeInstruction command in commands) {
    append(Uint8List.sublistView(drawing.records.program.bytes, position, command.start));
    if (const {'u', '*u', 'q'}.contains(command.operator)) {
      replay(states[command.start]!, {'A', 'Xw'});
    }
    if (paths[command.start] case final AiNativePath path) {
      final _NativeShapeInputs local = states[path.start]!;
      final _NativeShapeInputs wanted = sourceCompound != null && compoundDepth == 0 ? _nativeContourAppearance(local, states[sourceCompound.closing.start]!) : local;
      replay(wanted, compoundDepth == 0 ? _shapeCopyReads(drawing, path) : _nativeContourFlags);
    }
    if (command.operator == '*U') {
      replay(states[command.start]!, _shapeCopyReads(drawing, endings[command.start]!.paths.last)..removeAll(_nativeContourFlags));
    }
    if (targetCompound != null && !identical(sourceCompound, targetCompound) && _nativePaint.contains(command.operator)) {
      final String paint = targetCompound.paths.last.paint.operator.toUpperCase();
      append(latin1.encode(command.operator == command.operator.toLowerCase() ? paint.toLowerCase() : paint));
    } else {
      append(Uint8List.sublistView(drawing.records.program.bytes, command.start, command.end));
    }
    position = command.end;
    if (_nativeContourStateKey(command) case final String key) {
      current.native[key] = command;
      if (!command.isPrivate) {
        current.printing[key] = command;
      }
    }
    switch (command.operator) {
      case '*u':
        compoundDepth++;
      case '*U':
        compoundDepth--;
      case 'q':
        clips.add(compoundDepth == 0 ? _nativeContourSnapshot(current) : null);
      case 'Q':
        if (clips.removeLast() case final _NativeShapeInputs saved) {
          restore(saved);
        }
    }
  }
  append(Uint8List.sublistView(drawing.records.program.bytes, position, owner.end));
  append([10]);
  final _NativeClipReplay output = replay(destination, _nativeArtworkStateKeys, allowUnknown: true);
  changed.printing
    ..clear()
    ..addAll(output.unresolved.printing);
  changed.native
    ..clear()
    ..addAll(output.unresolved.native);
  return bytes.takeBytes();
}
