part of 'package:illustratorkit/src/model/ai_native_records.dart';

/// Contour attributes restored by ordinary `q`/`Q`, unlike persistent paint data.
const Set<String> _nativeClipStateKeys = {'J', 'j', 'w', 'M', 'd'};

/// Serialized assignments and unresolved differences in both interpretations.
typedef _NativeClipReplay = ({List<int> bytes, _NativeContourDifferences assigned, _NativeContourDifferences unresolved});

/// Replays exact source values after changing a qualified clipping boundary.
_NativeClipReplay _nativeClipStateReplay(
  AiNativeDrawing drawing,
  _NativeShapeInputs current,
  _NativeShapeInputs target, {
  int? maxBytes,
  Set<String> keys = _nativeClipStateKeys,
  bool allowUnknown = false,
}) {
  final Map<String, AiNativeInstruction> printing = Map.of(current.printing);
  final Map<String, AiNativeInstruction> native = Map.of(current.native);
  final BytesBuilder result = BytesBuilder(copy: false);
  final int maximum = maxBytes ?? drawing.records.program.limits.maxDecodedBytes;
  final _NativeContourDifferences assigned = (printing: {}, native: {});
  final _NativeContourDifferences unresolved = (printing: {}, native: {});

  /// Serializes one assignment in its original native or printing interpretation.
  void append(String key, AiNativeInstruction value, {required bool private}) {
    final List<int> bytes = latin1.encode(_shapeStateText(value, private: private));
    if (result.length + bytes.length + 1 > maximum) {
      throw const AiLimitException(message: 'Clipping state output exceeds the source byte limit.');
    }
    if (result.isEmpty) {
      result.addByte(10);
    }
    result.add(bytes);
    assigned.native.add(key);
    if (!private) {
      assigned.printing.add(key);
    }
  }

  for (final String key in keys) {
    if (!_sameShapeAttribute(printing, current.printingOrigins, target.printing, target.printingOrigins, key)) {
      final AiNativeInstruction? value = target.printing[key];
      if (value == null) {
        unresolved.printing.add(key);
      } else {
        append(key, value, private: false);
        printing[key] = value;
        native[key] = value;
      }
    }
  }
  for (final String key in keys) {
    if (!_sameShapeAttribute(native, current.nativeOrigins, target.native, target.nativeOrigins, key)) {
      final AiNativeInstruction? value = target.native[key];
      if (value == null) {
        unresolved.native.add(key);
      } else {
        append(key, value, private: true);
      }
    }
  }
  if (!allowUnknown && (unresolved.printing.isNotEmpty || unresolved.native.isNotEmpty)) {
    throw UnsupportedError('Changing a clipping boundary cannot restore an unknown contour attribute.');
  }
  return (bytes: result.takeBytes(), assigned: assigned, unresolved: unresolved);
}

/// Preserves contour state when compound boundaries activate or suppress `q/Q`.
List<AiSourceEdit> _nativeCompoundClipState(AiNativeDrawing drawing, List<AiNativeGroup> groups, {required bool activate}) {
  if (groups.isEmpty) {
    return [];
  }
  final Map<int, _NativeShapeInputs> states = _nativeContourInputs(drawing, [
    for (final AiNativeGroup group in groups) ...[group.opening.end, group.closing.start, group.closing.end],
  ]);
  int remaining = drawing.records.program.limits.maxDecodedBytes;
  final List<AiSourceEdit> edits = [];
  for (final AiNativeGroup group in groups) {
    final List<int> bytes = _nativeClipStateReplay(drawing, states[activate ? group.opening.end : group.closing.start]!, states[group.closing.end]!, maxBytes: remaining).bytes;
    remaining -= bytes.length;
    if (bytes.isNotEmpty) {
      edits.add(AiSourceEdit(start: _nativeContourOwner(drawing, group).end, end: _nativeContourOwner(drawing, group).end, bytes: bytes));
    }
  }
  return edits;
}
