import 'dart:convert';
import 'dart:io';

import 'package:aikit/aikit.dart';

import 'check_native_appearances.dart' show appearanceInventory;

/// Host-authored white and cyan alternatives, without kit-side color conversion.
const List<double> _white = [0, 0, 0, 0, 1, 1, 1];

/// Both saved process alternatives for the replacement cyan fill.
const List<double> _cyan = [1, 0, 0, 0, 0, 1, 1];

/// Checks exact fixture values before selecting a printing paint occurrence.
bool _same(List<double>? first, List<double> second) => first != null && first.length == second.length && first.indexed.every((entry) => entry.$2 == second[entry.$1]);

/// Authors a group by changing only its existing white foreground assignment.
AiNativePrintingGroupReplacement _printing(AiNativeSource source, AiNativeDrawing drawing, AiLiveShape shape) {
  final AiNativeGroup group = shape.appearanceGroup!;
  final List<AiNativeInstruction> fills = drawing.items
      .whereType<AiNativeInstruction>()
      .where((item) => item.start > group.start && item.end < group.paths.first.start && item.operator == 'Xa')
      .toList();
  if (fills.length != 1 || !_same(fills.single.numbers, _white)) {
    throw StateError('The source printing group must have exactly one explicit white foreground.');
  }
  return AiNativePrintingGroupReplacement(
    shape: shape,
    bytes: AiNativeEditor.copyRange(
      program: drawing.records.program,
      start: group.start,
      end: group.end,
      edits: [for (final (int, AiToken) entry in fills.single.operands.indexed) AiSourceEdit(start: entry.$2.start, end: entry.$2.end, bytes: latin1.encode(_cyan[entry.$1].toString()))],
    ),
    bounds: source.asPostScript().boundingBox!,
  );
}

/// Changes real complete producer programs without removing setup or neighbors.
Future<void> main() async {
  final Directory output = await Directory('test/corpus/output/appearance-producers').create(recursive: true);
  final List<Map<String, Object?>> rows = [];
  for (final String name in ['simple_shapes.ai', 'simple_shapes_cc.ai']) {
    final AiNativeSource source = AiNativeData.extract(const AiCodec().decode(await File('test/corpus/files/$name').readAsBytes())).single;
    final AiNativeDrawing drawing = AiNativeDrawing.decode(
      records: AiNativeRecords.decode(program: AiProgram.decode(bytes: source.bytes)),
    );
    final AiNativeAppearances model = AiNativeAppearances.decode(structure: AiNativeStructure.decode(drawing: drawing));
    if (drawing.liveShapes.length != 5) {
      throw StateError('Unexpected producer paint or shape inventory.');
    }
    await File('${output.path}/$name.before.ps').writeAsBytes(source.bytes);
    final AiLiveShape shape = drawing.liveShapes.first;
    final AiNativeAppearance style = model.styles.singleWhere((style) => identical(style.resource.definition.source, shape.style));
    final AiNativeAppearancePart part = style.parts.singleWhere((part) => part.kind == .fill);
    final AiNativePaintAssignment paint = part.paints.single.style.assignments.singleWhere((assignment) => assignment.parameter == .fillColor);
    if (!_same(paint.numbers, _white)) {
      throw StateError('Unexpected producer foreground color.');
    }
    final List<AiLiveShape> selected = [shape];
    final List<AiNativePrintingGroupReplacement> groups = selected.map((shape) => _printing(source, drawing, shape)).toList();
    String? sharedRejection;
    try {
      model.updateShared(
        appearance: style,
        paints: [AiNativePaintChange(assignment: paint, values: _cyan)],
        printing: groups,
      );
    } on UnsupportedError catch (error) {
      sharedRejection = error.message;
    }
    if (sharedRejection != 'Artboard setup inventories require unconditional ownership.') {
      throw StateError('The shared producer appearance boundary changed: $sharedRejection');
    }
    final AiNativeAppearances changed = model.updateSelected(
      appearance: style,
      paints: [AiNativePaintChange(assignment: paint, values: _cyan)],
      printing: groups,
      nameBytes: latin1.encode('Selected cyan'),
    );
    await File('${output.path}/$name.selected.ps').writeAsBytes(changed.structure.drawing.records.program.bytes);
    rows.add({
      'file': name,
      'selectedShapes': selected.map(drawing.liveShapes.indexOf).toList(),
      'style': model.styles.indexOf(style),
      'part': part.index,
      'sharedRejection': sharedRejection,
      'before': {'source': '$name.before', ...appearanceInventory(model)},
      'after': {'source': '$name.selected', ...appearanceInventory(changed)},
    });
    stdout.writeln('$name: ${selected.length} users, ${model.styles.length}/${changed.styles.length} styles');
  }
  await File('${output.path}/report.json').writeAsString('${const JsonEncoder.withIndent('  ').convert(rows)}\n');
}
