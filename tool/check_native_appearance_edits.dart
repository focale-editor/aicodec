import 'dart:convert';
import 'dart:io';

import 'package:aicodec/aicodec.dart';

import '../test/ai_native_appearance_editing_test.dart' show appearanceAssignment, appearanceEditingModel, appearanceEditingSource, appearancePrinting;
import '../test/ai_native_appearance_order_test.dart' show appearanceOrderSource, reverseAppearanceChildren;
import '../test/ai_native_appearance_scope_test.dart' show appearanceScopeSource;
import '../test/ai_native_simple_style_editing_test.dart' show simpleAppearanceSource;
import 'check_native_appearances.dart' show appearanceInventory;

/// Saves source-owned inventories for independent scalar and byte comparisons.
Future<void> main() async {
  final Directory output = await Directory('test/corpus/output/appearance-edits').create(recursive: true);
  final List<Map<String, Object?>> rows = [];
  for (final String variant in ['selected', 'shared', 'settings', 'simple-selected', 'simple-shared', 'order-selected', 'order-shared', 'order-nested', 'scope-shared']) {
    final bool simple = variant.startsWith('simple-');
    final bool ordered = variant.startsWith('order-');
    final bool nested = variant == 'order-nested';
    final bool shared = variant == 'shared' || variant.endsWith('-shared');
    final AiNativeAppearances source = appearanceEditingModel(
      source: variant == 'scope-shared'
          ? appearanceScopeSource()
          : simple
          ? simpleAppearanceSource()
          : ordered
          ? appearanceOrderSource()
          : variant == 'settings'
          ? appearanceEditingSource().replaceFirst('1 /Bool (StrokeOffsetInside)', '(Inside) /String (DisplayString) , 1 /Bool (StrokeOffsetInside)')
          : appearanceEditingSource(),
    );
    final AiNativeAppearance style = source.styles.single;
    final List<AiNativePaintChange> paints = simple
        ? [
            AiNativePaintChange(assignment: style.simplePaint!.assignments.singleWhere((assignment) => assignment.parameter == .fillColor), values: [1, 0, 0, 0]),
          ]
        : variant == 'settings'
        ? [
            AiNativePaintChange(assignment: appearanceAssignment(style, 6, .dash), values: [5, 2, 3, 4], dashPhase: -2),
            AiNativePaintChange(assignment: appearanceAssignment(style, 6, .strokeWidth), values: [8]),
            AiNativePaintChange(assignment: appearanceAssignment(style, 6, .strokeColor), values: [0, 0.1, 0.2, 0.3, 0.4, 0.5, 0.6]),
          ]
        : [
            if (!ordered || nested) AiNativePaintChange(assignment: appearanceAssignment(style, 2, .fillColor), values: [0.7, 0.6, 0.5]),
          ];
    final List<AiNativeAppearancePartChange> parts = [
      if (ordered) reverseAppearanceChildren(style, 1),
      if (nested) reverseAppearanceChildren(style, 0),
      if (variant == 'settings' || nested) ...[
        AiNativeAppearancePartChange(part: style.parts[2], visible: true, evenOdd: false),
        AiNativeAppearancePartChange(part: style.parts[6], strokeAlignment: .outside, alignmentLabelBytes: nested ? null : latin1.encode('Outside')),
      ],
    ];
    final List<AiNativePrintingGroupReplacement> printing = [
      for (final int index in shared ? [0, 1] : [if (variant == 'settings' || nested) 1 else 0])
        if (simple) appearancePrinting(source, index, bytes: 'u\n1 0 0 0 k\n0 0 m 10 0 L 10 10 L f\n0 0 0 1 k\nU') else appearancePrinting(source, index),
    ];
    final AiNativeAppearances changed = shared
        ? source.updateShared(appearance: style, paints: paints, parts: parts, printing: printing)
        : source.updateSelected(
            appearance: style,
            paints: paints,
            parts: parts,
            printing: printing,
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
