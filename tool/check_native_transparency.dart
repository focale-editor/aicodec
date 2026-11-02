import 'dart:convert';
import 'dart:io';

import 'package:aicodec/aicodec.dart';

import '../test/ai_native_appearance_editing_test.dart' show appearanceEditingModel;
import '../test/ai_native_transparency_test.dart' show editTransparency, transparencySource;
import 'check_native_appearances.dart' show appearanceInventory;

/// Records complete source transactions for independent byte and tree checks.
Future<void> main() async {
  final Directory output = await Directory('test/corpus/output/transparency').create(recursive: true);
  final List<Map<String, Object?>> rows = [];

  /// Saves both full programs and their exact style and printing owner handles.
  Future<void> save(String name, AiNativeAppearances before, AiNativeAppearances after, int style, int part, List<int> uses) async {
    for (final (String, AiNativeAppearances) item in [('before', before), ('after', after)]) {
      await File('${output.path}/$name.${item.$1}.ps').writeAsBytes(item.$2.structure.drawing.records.program.bytes);
    }
    rows.add({
      'name': name,
      'style': style,
      'part': part,
      'uses': uses,
      'groups': [
        for (final int index in uses) [before.artworkFor(use: before.uses[index]).printingGroup.start, before.artworkFor(use: before.uses[index]).printingGroup.end],
      ],
      'before': {'source': '$name.before', ...appearanceInventory(before)},
      'after': {'source': '$name.after', ...appearanceInventory(after)},
    });
  }

  for (final bool grouped in [false, true]) {
    for (final bool shared in [false, true]) {
      final AiNativeAppearances source = appearanceEditingModel(source: transparencySource(grouped: grouped));
      await save('${grouped ? 'group' : 'path'}-${shared ? 'shared' : 'selected'}', source, editTransparency(source, shared: shared), 0, 7, shared ? [0, 1] : [0]);
    }
  }

  final AiNativeSource native = AiNativeData.extract(const AiCodec().decode(await File('test/corpus/files/stroke_styles.ai').readAsBytes())).single;
  final AiNativeAppearances source = appearanceEditingModel(source: latin1.decode(native.bytes));
  final AiNativeDrawing drawing = source.structure.drawing;
  final AiNativeResourceUse use = source.uses.firstWhere((use) => use.instruction.start >= drawing.records.program.bodyStart && !drawing.liveShapes.any((shape) => shape.end == use.instruction.end));
  final AiNativeAppearance style = source.resolve(use: use)!;
  final AiNativeAppearancePart part = style.parts.singleWhere((part) => part.kind == .stroke);
  final AiNativePaintAssignment assignment = part.paints.single.style.assignments.singleWhere((assignment) => assignment.parameter == .transparency);
  final AiNativeAppearanceArtwork artwork = source.artworkFor(use: use);
  final AiNativeGroup group = artwork.printingGroup;
  final AiNativeInstruction color = drawing.items.whereType<AiNativeInstruction>().singleWhere((item) => item.start > group.start && item.end < group.end && item.operator == 'XA');
  final AiNativeAppearances changed = source.updateSelected(
    appearance: style,
    paints: [
      AiNativePaintChange.transparency(
        assignment: assignment,
        value: AiNativeTransparency(blendMode: .multiply, opacity: 0.25, isolated: false, knockout: .off, alphaIsShape: false),
      ),
    ],
    artwork: [
      AiNativeAppearanceReplacement(
        artwork: artwork,
        bytes: AiNativeEditor.copyRange(
          program: drawing.records.program,
          start: group.start,
          end: group.end,
          edits: [
            AiSourceEdit(start: color.end, end: color.end, bytes: latin1.encode('\n1 0.25 0 0 0 Xy\n')),
            AiSourceEdit(start: group.end - 1, end: group.end - 1, bytes: latin1.encode('0 1 0 0 0 Xy\n')),
          ],
        ),
        bounds: native.asPostScript().boundingBox!,
      ),
    ],
    nameBytes: latin1.encode('Transparent selection'),
  );
  await save('stroke_styles.ai', source, changed, source.styles.indexOf(style), part.index, [source.uses.indexOf(use)]);
  await File('${output.path}/report.json').writeAsString('${const JsonEncoder.withIndent('  ').convert(rows)}\n');
  stdout.writeln('${rows.length} native transparency transactions written.');
}
