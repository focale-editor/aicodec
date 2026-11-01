part of 'package:aikit/src/model/ai_native_records.dart';

/// Contour attributes restored by ordinary `q`/`Q`, unlike persistent paint data.
const Set<String> _nativeClipStateKeys = {'J', 'j', 'w', 'M', 'd'};

/// Replays exact source values after changing a qualified clipping boundary.
List<int> _nativeClipStateReplay(AiNativeDrawing drawing, _NativeShapeInputs current, _NativeShapeInputs target, {int? maxBytes, Set<String> keys = _nativeClipStateKeys}) {
  final Map<String, AiNativeInstruction> printing = Map.of(current.printing);
  final Map<String, AiNativeInstruction> native = Map.of(current.native);
  final BytesBuilder result = BytesBuilder(copy: false);
  final int maximum = maxBytes ?? drawing.records.program.limits.maxDecodedBytes;

  /// Serializes one assignment in its original native or printing interpretation.
  void append(AiNativeInstruction? value, {required bool private}) {
    if (value == null) {
      throw UnsupportedError('Changing a clipping boundary cannot restore an unknown contour attribute.');
    }
    final List<int> bytes = latin1.encode(_shapeStateText(value, private: private));
    if (result.length + bytes.length + 1 > maximum) {
      throw const AiLimitException(message: 'Clipping state output exceeds the source byte limit.');
    }
    if (result.isEmpty) {
      result.addByte(10);
    }
    result.add(bytes);
  }

  for (final String key in keys) {
    if (!_sameShapeAttribute(printing, current.printingOrigins, target.printing, target.printingOrigins, key)) {
      append(target.printing[key], private: false);
      printing[key] = target.printing[key]!;
      native[key] = target.printing[key]!;
    }
  }
  for (final String key in keys) {
    if (!_sameShapeAttribute(native, current.nativeOrigins, target.native, target.nativeOrigins, key)) {
      append(target.native[key], private: true);
    }
  }
  return result.takeBytes();
}

/// Preserves contour state when compound boundaries activate or suppress `q/Q`.
List<AiSourceEdit> _nativeCompoundClipState(AiNativeDrawing drawing, List<AiNativeGroup> groups, {required bool activate}) {
  if (groups.isEmpty) {
    return [];
  }
  for (final AiNativeGroup group in groups) {
    if (_pathInterval(drawing.items, group.start, group.end, (item) => item.start).whereType<AiNativeInstruction>().any((item) => item.operator == 'Xy')) {
      throw UnsupportedError('Compound clipping-state changes require a separate opacity/blend appearance contract.');
    }
  }
  final Map<int, _NativeShapeInputs> states = _shapeCopyInputs(drawing, [
    for (final AiNativeGroup group in groups) ...[group.opening.end, group.closing.start, group.closing.end],
  ], clipping: true);
  int remaining = drawing.records.program.limits.maxDecodedBytes;
  final List<AiSourceEdit> edits = [];
  for (final AiNativeGroup group in groups) {
    final List<int> bytes = _nativeClipStateReplay(drawing, states[activate ? group.opening.end : group.closing.start]!, states[group.closing.end]!, maxBytes: remaining);
    remaining -= bytes.length;
    if (bytes.isNotEmpty) {
      edits.add(AiSourceEdit(start: _ordinaryObject(drawing, group).end, end: _ordinaryObject(drawing, group).end, bytes: bytes));
    }
  }
  return edits;
}
