import 'dart:convert';
import 'dart:io';

import 'package:aikit/aikit.dart';

import '../test/ai_native_appearance_graph_test.dart' show newAppearanceFill;
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

/// Authors this fixture's white rectangle above its retained inside-stroke ink.
AiNativePrintingGroupReplacement _orderedPrinting(AiNativeSource source, AiNativeDrawing drawing, AiLiveShape shape) {
  final AiNativeGroup group = shape.appearanceGroup!;
  final AiNativeGroup stroke = drawing.groups.singleWhere((candidate) => candidate.compound && candidate.start > group.start && candidate.end < group.end);
  final AiNativeInstruction black = drawing.items.whereType<AiNativeInstruction>().singleWhere((item) => item.operator == 'Xa' && item.start > stroke.start && item.end < stroke.end);
  final bool counted = drawing.items.whereType<AiNativeInstruction>().any((item) => item.operator == 'As' && item.start > group.start && item.end < group.end);
  final AiProgram program = drawing.records.program;
  final String outline = latin1.decode(program.bytes.sublist(stroke.start, stroke.end));
  final String outgoing = latin1.decode(program.bytes.sublist(black.start, black.end));
  final String geometry = shape.path!.geometry.map((command) => '${command.operands.map((operand) => operand.lexeme).join(' ')} ${command.operator}').join('\n');
  return AiNativePrintingGroupReplacement(
    shape: shape,
    bytes: latin1.encode('u\n0 O\n0 1 0 0 0 Xy\n0 J 0 j 1 w 10 M []0 d\n0 XR\n0 Ae\n$outline\n${counted ? '4 As\n' : ''}0 D\n0 0 0 0 1 1 1 Xa\n$geometry\nf\n$outgoing\n1 D\nU'),
    bounds: source.asPostScript().boundingBox!,
  );
}

/// Composes a new cyan fill above all existing ink without changing old paths.
AiNativePrintingGroupReplacement _addedPrinting(AiNativeSource source, AiNativeDrawing drawing, AiLiveShape shape) {
  final AiNativeGroup group = shape.appearanceGroup!;
  final AiNativeGroup stroke = drawing.groups.singleWhere((candidate) => candidate.compound && candidate.start > group.start && candidate.end < group.end);
  final AiNativeInstruction black = drawing.items.whereType<AiNativeInstruction>().singleWhere((item) => item.operator == 'Xa' && item.start > stroke.start && item.end < stroke.end);
  final bool counted = drawing.items.whereType<AiNativeInstruction>().any((item) => item.operator == 'As' && item.start > group.start && item.end < group.end);
  final AiProgram program = drawing.records.program;
  final String outgoing = latin1.decode(program.bytes.sublist(black.start, black.end));
  final String geometry = shape.path!.geometry.map((command) => '${command.operands.map((operand) => operand.lexeme).join(' ')} ${command.operator}').join('\n');
  if (program.bytes[group.end - 1] != 85) {
    throw StateError('The source printing group must end in its closing U operator.');
  }
  return AiNativePrintingGroupReplacement(
    shape: shape,
    bytes: AiNativeEditor.copyRange(
      program: program,
      start: group.start,
      end: group.end,
      edits: [
        AiSourceEdit(
          start: group.end - 1,
          end: group.end - 1,
          bytes: latin1.encode('0 O\n0 1 0 0 0 Xy\n0 XR\n${counted ? '4 As\n' : ''}0 D\n${_cyan.join(' ')} Xa\n$geometry\nf\n$outgoing\n1 D\n'),
        ),
      ],
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
    final AiNativeAppearances shared = model.updateShared(
      appearance: style,
      paints: [AiNativePaintChange(assignment: paint, values: _cyan)],
      printing: groups,
    );
    final AiNativeAppearances changed = model.updateSelected(
      appearance: style,
      paints: [AiNativePaintChange(assignment: paint, values: _cyan)],
      printing: groups,
      nameBytes: latin1.encode('Selected cyan'),
    );
    final AiNativeAppearancePart stack = style.parts.singleWhere((part) => part.kind == .stack);
    final AiNativeAppearances ordered = model.updateSelected(
      appearance: style,
      parts: [AiNativeAppearancePartChange(part: stack, childOrder: stack.childIndices.reversed.map((index) => style.parts[index]).toList())],
      printing: [_orderedPrinting(source, drawing, shape)],
      nameBytes: latin1.encode('Fill above stroke'),
    );
    final AiNativeAppearances added = model.updateSelected(
      appearance: style,
      parts: [
        AiNativeAppearancePartChange(
          part: stack,
          children: [
            AiNativeAppearanceChild.create(definition: newAppearanceFill()),
            for (final int index in stack.childIndices) AiNativeAppearanceChild.retain(part: style.parts[index]),
          ],
        ),
      ],
      printing: [_addedPrinting(source, drawing, shape)],
      nameBytes: latin1.encode('Added cyan fill'),
    );
    final AiNativeAppearances sharedOrder = model.updateShared(
      appearance: style,
      parts: [AiNativeAppearancePartChange(part: stack, childOrder: stack.childIndices.reversed.map((index) => style.parts[index]).toList())],
      printing: [_orderedPrinting(source, drawing, shape)],
    );
    final AiNativeAppearances sharedAdded = model.updateShared(
      appearance: style,
      parts: [
        AiNativeAppearancePartChange(
          part: stack,
          children: [
            AiNativeAppearanceChild.create(definition: newAppearanceFill()),
            for (final int index in stack.childIndices) AiNativeAppearanceChild.retain(part: style.parts[index]),
          ],
        ),
      ],
      printing: [_addedPrinting(source, drawing, shape)],
    );
    await File('${output.path}/$name.selected.ps').writeAsBytes(changed.structure.drawing.records.program.bytes);
    await File('${output.path}/$name.ordered.ps').writeAsBytes(ordered.structure.drawing.records.program.bytes);
    await File('${output.path}/$name.added.ps').writeAsBytes(added.structure.drawing.records.program.bytes);
    await File('${output.path}/$name.shared.ps').writeAsBytes(shared.structure.drawing.records.program.bytes);
    await File('${output.path}/$name.shared-order.ps').writeAsBytes(sharedOrder.structure.drawing.records.program.bytes);
    await File('${output.path}/$name.shared-added.ps').writeAsBytes(sharedAdded.structure.drawing.records.program.bytes);
    rows.add({
      'file': name,
      'selectedShapes': selected.map(drawing.liveShapes.indexOf).toList(),
      'style': model.styles.indexOf(style),
      'part': part.index,
      'before': {'source': '$name.before', ...appearanceInventory(model)},
      'after': {'source': '$name.selected', ...appearanceInventory(changed)},
      'ordered': {'source': '$name.ordered', ...appearanceInventory(ordered)},
      'added': {'source': '$name.added', ...appearanceInventory(added)},
      'shared': {'source': '$name.shared', ...appearanceInventory(shared)},
      'sharedOrder': {'source': '$name.shared-order', ...appearanceInventory(sharedOrder)},
      'sharedAdded': {'source': '$name.shared-added', ...appearanceInventory(sharedAdded)},
    });
    stdout.writeln('$name: selected/shared fill, order and creation edits, ${selected.length} users, ${model.styles.length}/${changed.styles.length} styles');
  }
  await File('${output.path}/report.json').writeAsString('${const JsonEncoder.withIndent('  ').convert(rows)}\n');
}
