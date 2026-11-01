import 'dart:convert';
import 'dart:io';

import 'package:aikit/aikit.dart';

import '../test/ai_native_appearance_editing_test.dart' show appearanceAssignment, appearanceEditingModel, appearanceEditingSource, appearancePrinting;
import 'check_native_appearances.dart' show appearanceInventory;

/// Saves source-owned inventories for independent scalar and byte comparisons.
Future<void> main() async {
  final Directory output = await Directory('test/corpus/output/appearance-edits').create(recursive: true);
  final List<Map<String, Object?>> rows = [];
  for (final String variant in ['selected', 'shared', 'settings']) {
    final AiNativeAppearances source = appearanceEditingModel(
      source: variant == 'settings'
          ? appearanceEditingSource().replaceFirst('1 /Bool (StrokeOffsetInside)', '(Inside) /String (DisplayString) , 1 /Bool (StrokeOffsetInside)')
          : appearanceEditingSource(),
    );
    final AiNativeAppearance style = source.styles.single;
    final List<AiNativePaintChange> paints = variant == 'settings'
        ? [
            AiNativePaintChange(assignment: appearanceAssignment(style, 6, .dash), values: [5, 2, 3, 4], dashPhase: -2),
            AiNativePaintChange(assignment: appearanceAssignment(style, 6, .strokeWidth), values: [8]),
            AiNativePaintChange(assignment: appearanceAssignment(style, 6, .strokeColor), values: [0, 0.1, 0.2, 0.3, 0.4, 0.5, 0.6]),
          ]
        : [
            AiNativePaintChange(assignment: appearanceAssignment(style, 2, .fillColor), values: [0.7, 0.6, 0.5]),
          ];
    final AiNativeAppearances changed = variant == 'shared'
        ? source.updateShared(appearance: style, paints: paints, printing: [appearancePrinting(source, 0), appearancePrinting(source, 1)])
        : source.updateSelected(
            appearance: style,
            paints: paints,
            parts: [
              if (variant == 'settings') ...[
                AiNativeAppearancePartChange(part: style.parts[2], visible: true, evenOdd: false),
                AiNativeAppearancePartChange(part: style.parts[6], strokeAlignment: .outside, alignmentLabelBytes: latin1.encode('Outside')),
              ],
            ],
            printing: [appearancePrinting(source, variant == 'settings' ? 1 : 0)],
            nameBytes: latin1.encode('Selected'),
          );
    for (final (String, AiNativeAppearances) item in [('before', source), ('after', changed)]) {
      final String name = '$variant.${item.$1}';
      await File('${output.path}/$name.ps').writeAsBytes(item.$2.structure.drawing.records.program.bytes);
      rows.add({'source': name, ...appearanceInventory(item.$2)});
    }
    stdout.writeln('$variant: ${changed.styles.length} styles, ${changed.uses.length} users');
  }
  await File('${output.path}/report.json').writeAsString('${const JsonEncoder.withIndent('  ').convert(rows)}\n');
}
