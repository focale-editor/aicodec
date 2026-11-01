import 'dart:convert';
import 'dart:io';

import 'package:aikit/aikit.dart';

import '../test/ai_native_appearance_editing_test.dart' show appearanceEditingModel;
import '../test/ai_native_appearance_state_test.dart' show appearanceStateEdit, appearanceStateSource;
import 'check_native_appearances.dart' show appearanceInventory;

/// Saves isolated fills before retained text without composing text in the kit.
Future<void> main() async {
  final Directory output = await Directory('test/corpus/output/appearance-state').create(recursive: true);
  final List<Map<String, Object?>> rows = [];

  /// Records both complete snapshots for independently bound byte/tree checks.
  Future<void> save(String name, AiNativeAppearances before, AiNativeAppearances after) async {
    for (final (String, AiNativeAppearances) item in [('before', before), ('after', after)]) {
      final String source = '$name.${item.$1}';
      await File('${output.path}/$source.ps').writeAsBytes(item.$2.structure.drawing.records.program.bytes);
      rows.add({'source': source, ...appearanceInventory(item.$2)});
    }
    stdout.writeln('$name: isolated fill and exact native outgoing state');
  }

  for (final String name in ['live', 'ordinary']) {
    final AiNativeAppearances before = appearanceEditingModel(source: appearanceStateSource(ordinary: name == 'ordinary'));
    await save(name, before, appearanceStateEdit(before));
  }
  for (final String name in ['simple_cc_legacy.ai', 'simple_v2020.ai']) {
    final AiNativeSource source = AiNativeData.extract(const AiCodec().decode(await File('test/corpus/files/$name').readAsBytes())).single;
    final AiNativeAppearances before = appearanceEditingModel(source: latin1.decode(source.bytes));
    final AiNativeDrawing drawing = before.structure.drawing;
    final AiLiveShape shape = drawing.liveShapes.single;
    final AiNativeAppearance style = before.styles.singleWhere((style) => identical(style.resource.definition.source, shape.style));
    final AiNativePaintAssignment paint = style.parts.singleWhere((part) => part.kind == .fill).paints.single.style.assignments.singleWhere((paint) => paint.parameter == .fillColor);
    final AiNativeGroup group = shape.appearanceGroup!;
    final AiNativeInstruction fill = drawing.items.whereType<AiNativeInstruction>().singleWhere(
      (item) => item.start > group.start && item.end < group.end && item.operator == 'Xa' && item.numbers!.join(' ') == '0.0 0.0 0.0 0.0 1.0 1.0 1.0',
    );
    final AiNativeAppearances after = before.updateSelected(
      appearance: style,
      paints: [
        AiNativePaintChange(assignment: paint, values: [1, 0, 0, 0, 0, 1, 1]),
      ],
      printing: [
        AiNativePrintingGroupReplacement(
          shape: shape,
          bytes: AiNativeEditor.copyRange(
            program: drawing.records.program,
            start: group.start,
            end: group.end,
            edits: [AiSourceEdit(start: fill.start, end: fill.end, bytes: latin1.encode('1.0 0.0 0.0 0.0 0.0 1.0 1.0 Xa'))],
          ),
          bounds: source.asPostScript().boundingBox!,
        ),
      ],
      nameBytes: latin1.encode('Selected state'),
    );
    await save(name, before, after);
  }
  await File('${output.path}/report.json').writeAsString('${const JsonEncoder.withIndent('  ').convert(rows)}\n');
}
