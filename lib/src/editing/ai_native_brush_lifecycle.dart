part of 'package:illustratorkit/src/model/ai_native_records.dart';

/// Serializes literal payload fragments without executing descriptor syntax.
Uint8List _nativeBrushBytes(String plugin, List<int> name, List<int> payload, int maximum) {
  if (name.length > maximum || payload.length > maximum) {
    throw const AiLimitException(message: 'Brush descriptor inputs exceed the native byte limit.');
  }
  if (name.isEmpty || name.any((byte) => byte < 0 || byte > 255) || payload.any((byte) => byte < 0 || byte > 255)) {
    throw ArgumentError('Brush descriptors require a nonempty byte name and byte payload.');
  }
  final _NativeDocumentBytes output = _NativeDocumentBytes(maximum: maximum);
  output.text('\n%AI8_BeginPluginObject\n');
  output.add(_nativeLiteralString(latin1.encode(plugin), maximum));
  output.text('\n');
  output.add(_nativeLiteralString(name, maximum));
  output.text('\n');
  // Fixed-size literal fragments bound escaping work and preserve arbitrary bytes.
  for (int start = 0; start < max(1, payload.length); start += 128) {
    final int end = min(start + 128, payload.length);
    output.add(_nativeLiteralString(payload.sublist(start, end), maximum));
    output.text(end == payload.length ? ' .\n' : ' -\n');
  }
  output.text('%AI8_EndPluginObject\n');
  return output.takeBytes();
}

/// Serializes explicit membership with the manager's delimiter-only grammar.
Uint8List _nativeBrushPanel(List<(String, List<int>)> entries, int maximum) {
  final _NativeDocumentBytes payload = _NativeDocumentBytes(maximum: maximum);
  for (final (String plugin, List<int> bytes) in entries) {
    final String name = latin1.decode(bytes);
    if (name.isEmpty || name != name.trim() || name.contains('/') || bytes.any((byte) => byte < 32 || byte == 127)) {
      throw UnsupportedError('Listed brush names must round-trip through the delimiter-separated native panel.');
    }
    payload.text(' $plugin/ $name/');
  }
  return _nativeBrushBytes('Adobe Brush Manager Order', latin1.encode('Adobe Brush Manager Order'), payload.takeBytes(), maximum);
}

/// Requires distinct current handles before any source mutation is prepared.
void _nativeBrushSelection(AiNativeBrushes model, List<AiNativeBrushDescriptor> selected, {bool empty = false}) {
  if (!empty && selected.isEmpty || selected.toSet().length != selected.length || selected.any((brush) => !model.brushes.contains(brush))) {
    throw ArgumentError('Brush operations require distinct current descriptor handles.');
  }
}

/// Rejects every owned style reference, including currently unused styles.
void _unusedNativeBrushes(AiNativeBrushes model, List<AiNativeBrushDescriptor> selected) {
  final Set<(String, String)> names = {for (final AiNativeBrushDescriptor brush in selected) (brush.plugin, latin1.decode(brush.nameBytes))};
  for (final AiNativeContainer record in model.structure.drawing.records.containers.where((record) => record.type == 'GObjRef')) {
    final List<AiNativeItem>? values = record['PluginObject']?.items;
    if (values != null && values.length == 2 && values.every((value) => value is AiNativeToken && _artboardPaletteName(value.token))) {
      final String name = latin1.decode(aiStringBytes((values.first as AiNativeToken).token));
      final String plugin = latin1.decode(aiStringBytes((values.last as AiNativeToken).token));
      if (names.contains((plugin, name))) {
        throw UnsupportedError('Referenced brush descriptors require their complete dependent appearance representations.');
      }
    }
  }
}

/// Reopens and qualifies the entire candidate before returning a new snapshot.
AiNativeBrushes _nativeBrushResult(AiNativeBrushes model, List<AiSourceEdit> edits, int count) {
  final AiNativeRecords records = AiNativeRecords.decode(
    program: AiNativeEditor.apply(program: model.structure.drawing.records.program, edits: edits),
  );
  _paintResourceScope(records);
  final AiNativeBrushes result = AiNativeBrushes.decode(
    structure: AiNativeStructure.decode(drawing: AiNativeDrawing.decode(records: records)),
  );
  if (result.brushes.length != count) {
    throw const FormatException('Brush editing changed an unexpected descriptor count.');
  }
  return result;
}

/// Creates a fresh plug-in/name pair and updates only its panel membership.
AiNativeBrushes _createNativeBrush(AiNativeBrushes model, AiNativeBrushKind kind, List<int> name, List<int> payload, bool listed) {
  if (model.brushes.any((brush) => brush.kind == kind && _sameNativeBytes(brush.nameBytes, name))) {
    throw ArgumentError('A new brush requires a fresh name in its plug-in namespace.');
  }
  final AiNativeRecords records = model.structure.drawing.records;
  _paintResourceScope(records);
  final int maximum = records.program.limits.maxDecodedBytes;
  final List<int> bytes = [..._nativeBrushBytes(kind.plugin, name, payload, maximum)];
  final List<AiSourceEdit> edits = [];
  if (listed) {
    final List<int> panel = _nativeBrushPanel([...model.order.map((brush) => (brush.plugin, brush.nameBytes)), (kind.plugin, name)], maximum);
    if (model._panel case final AiNativeBrushDescriptor existing) {
      edits.add(AiSourceEdit(start: existing.start, end: existing.end, bytes: panel));
    } else {
      bytes.addAll(panel);
    }
  }
  final int position = _nativeAppearanceSetupEnd(records);
  edits.add(AiSourceEdit(start: position, end: position, bytes: bytes));
  return _nativeBrushResult(model, edits, model.brushes.length + 1);
}

/// Replaces a qualified unused payload, retaining namespace and saved order.
AiNativeBrushes _replaceUnusedNativeBrush(AiNativeBrushes model, AiNativeBrushDescriptor brush, List<int> payload) {
  _nativeBrushSelection(model, [brush]);
  final AiNativeRecords records = model.structure.drawing.records;
  _paintResourceScope(records);
  _unusedNativeBrushes(model, [brush]);
  return _nativeBrushResult(model, [
    AiSourceEdit(start: brush.start, end: brush.end, bytes: _nativeBrushBytes(brush.plugin, brush.nameBytes, payload, records.program.limits.maxDecodedBytes)),
  ], model.brushes.length);
}

/// Removes complete unused declarations and retains the other panel positions.
AiNativeBrushes _removeNativeBrushes(AiNativeBrushes model, List<AiNativeBrushDescriptor> selected) {
  _nativeBrushSelection(model, selected);
  final AiNativeRecords records = model.structure.drawing.records;
  _paintResourceScope(records);
  _unusedNativeBrushes(model, selected);
  return _nativeBrushResult(model, [
    for (final AiNativeBrushDescriptor brush in selected) AiSourceEdit(start: brush.start, end: brush.end, bytes: []),
    if (model._panel case final AiNativeBrushDescriptor panel)
      AiSourceEdit(
        start: panel.start,
        end: panel.end,
        bytes: _nativeBrushPanel([
          for (final AiNativeBrushDescriptor brush in model.order)
            if (!selected.contains(brush)) (brush.plugin, brush.nameBytes),
        ], records.program.limits.maxDecodedBytes),
      ),
  ], model.brushes.length - selected.length);
}

/// Rewrites only the inventory, preserving all descriptor and body source bytes.
AiNativeBrushes _orderNativeBrushes(AiNativeBrushes model, List<AiNativeBrushDescriptor> selected) {
  _nativeBrushSelection(model, selected, empty: true);
  final AiNativeRecords records = model.structure.drawing.records;
  _paintResourceScope(records);
  final int position = model._panel?.start ?? _nativeAppearanceSetupEnd(records);
  return _nativeBrushResult(model, [
    AiSourceEdit(
      start: position,
      end: model._panel?.end ?? position,
      bytes: _nativeBrushPanel([for (final AiNativeBrushDescriptor brush in selected) (brush.plugin, brush.nameBytes)], records.program.limits.maxDecodedBytes),
    ),
  ], model.brushes.length);
}
