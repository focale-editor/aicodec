part of 'package:aicodec/src/model/ai_native_records.dart';

/// Assigns only flags consumed by the opening group, preserving child state.
AiNativeDrawing _updateNativeGroupAttributes(AiNativeDrawing drawing, AiNativeGroup group, bool? hidden, bool? locked) {
  _nativeMixedArtworkGroup(AiNativeLayers.decode(drawing: drawing), group);
  if (hidden == null && locked == null) {
    return drawing;
  }
  final _NativeShapeInputs before = _shapeCopyInputs(drawing, [group.start], appearanceArtwork: _nativeCreationAppearances(drawing))[group.start]!;
  final Map<String, int> values = {if (hidden != null) 'Xw': hidden ? 1 : 0, if (locked != null) 'A': locked ? 1 : 0};
  final StringBuffer prefix = StringBuffer();
  final StringBuffer restore = StringBuffer();
  for (final MapEntry<String, int> entry in values.entries) {
    final AiNativeInstruction? native = before.native[entry.key];
    final AiNativeInstruction? printing = before.printing[entry.key];
    if (native == null || printing == null) {
      throw UnsupportedError('Group attributes cannot restore unknown ${entry.key} child state.');
    }
    if (native.numbers!.single == entry.value && printing.numbers!.single == entry.value) {
      continue;
    }
    prefix.writeln('${entry.value} ${entry.key}');
    restore.write(_shapeStateText(printing, private: false));
    if (!_sameNativeArtworkState(printing, native)) {
      restore.write(_shapeStateText(native, private: true));
    }
  }
  if (prefix.isEmpty) {
    return drawing;
  }
  return _groupLifecycleResult(
    drawing,
    [
      AiSourceEdit(start: group.start, end: group.start, bytes: latin1.encode(prefix.toString())),
      AiSourceEdit(start: group.opening.end, end: group.opening.end, bytes: latin1.encode('\n$restore')),
    ],
    paths: drawing.paths.length,
    groups: drawing.groups.length,
    liveShapes: drawing.liveShapes.length,
  );
}
