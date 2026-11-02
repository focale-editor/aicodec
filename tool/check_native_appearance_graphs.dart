import 'dart:convert';
import 'dart:io';

import 'package:aicodec/aicodec.dart';

import '../test/ai_native_appearance_editing_test.dart' show appearanceAssignment, appearanceEditingModel, appearancePrinting;
import '../test/ai_native_appearance_graph_test.dart' show newAppearanceFill, retainAppearanceParts;
import '../test/ai_native_appearance_order_test.dart' show appearanceOrderSource, reverseAppearanceChildren;
import 'check_native_appearances.dart' show appearanceInventory;

/// Exercises all authored part kinds and process stroke spaces independently.
AiNativeAppearancePartDefinition _typedParts({bool strokeSettings = false}) => AiNativeAppearancePartDefinition(
  kind: .chain,
  children: [
    AiNativeAppearanceChild.create(
      definition: AiNativeAppearancePartDefinition(
        kind: .stack,
        children: [
          AiNativeAppearanceChild.create(definition: newAppearanceFill()),
          for (final (AiColorSpace, List<double>, AiNativeStrokeAlignment) entry in <(AiColorSpace, List<double>, AiNativeStrokeAlignment)>[
            (.gray, [0.25], .center),
            (.rgb, [0.2, 0.4, 0.6], .inside),
            (.cmyk, [0.1, 0.2, 0.3, 0.4], .outside),
          ])
            AiNativeAppearanceChild.create(
              definition: AiNativeAppearancePartDefinition(
                kind: .stroke,
                colors: [AiColor(space: entry.$1, channels: entry.$2)],
                overprint: true,
                opacity: 0.5,
                evenOdd: true,
                strokeWidth: 3.5,
                lineCap: 1,
                lineJoin: 2,
                miterLimit: 8,
                dash: [2.5, 1.5],
                dashPhase: -1.5,
                adjustDashes: strokeSettings ? entry.$3 != .outside : null,
                strokeAlignment: entry.$3,
                alignmentLabelBytes: entry.$3 == .center ? null : latin1.encode(entry.$3.name),
              ),
            ),
        ],
      ),
    ),
    AiNativeAppearanceChild.create(definition: AiNativeAppearancePartDefinition(kind: .conduit)),
  ],
);

/// Saves complete graph transactions for independent tree and byte verification.
Future<void> main() async {
  final Directory output = await Directory('test/corpus/output/appearance-graphs').create(recursive: true);
  final List<Map<String, Object?>> rows = [];
  for (final String variant in ['create', 'remove', 'copy', 'move', 'shared', 'private', 'typed', 'typed-strokes']) {
    String text = appearanceOrderSource();
    if (variant == 'private') {
      final AiNativeContainer owner = appearanceEditingModel(source: text).styles.single.resource.definition.source as AiNativeContainer;
      final String fragment = text.substring(owner.start, owner.end);
      text = text.replaceFirst(fragment, fragment.split('\n').map((line) => '%_$line').join('\n'));
    }
    final AiNativeAppearances source = appearanceEditingModel(source: text);
    final AiNativeAppearance style = source.styles.single;
    final List<AiNativeAppearanceChild> children = switch (variant) {
      'remove' => retainAppearanceParts(style, [2, 6, 7]),
      'move' => retainAppearanceParts(style, [1, 7]),
      'copy' => [
        ...retainAppearanceParts(style, [1, 6, 7]),
        AiNativeAppearanceChild.copy(part: style.parts[2]),
      ],
      _ => [
        ...retainAppearanceParts(style, [1, 6, 7]),
        AiNativeAppearanceChild.create(definition: variant.startsWith('typed') ? _typedParts(strokeSettings: variant == 'typed-strokes') : newAppearanceFill()),
      ],
    };
    final List<AiNativeAppearancePartChange> parts = [
      AiNativeAppearancePartChange(part: style.parts.first, children: children),
      if (variant == 'move') AiNativeAppearancePartChange(part: style.parts[1], children: retainAppearanceParts(style, [6, 2, 3, 4, 5])),
      if (variant == 'shared') ...[reverseAppearanceChildren(style, 1), AiNativeAppearancePartChange(part: style.parts[2], visible: true)],
    ];
    final List<AiNativePaintChange> paints = [
      if (variant == 'copy') AiNativePaintChange(assignment: appearanceAssignment(style, 2, .fillColor), values: [0.7, 0.6, 0.5]),
    ];
    final AiNativeAppearances changed = variant == 'shared'
        ? source.updateShared(appearance: style, parts: parts, paints: paints, printing: [appearancePrinting(source, 0), appearancePrinting(source, 1)])
        : source.updateSelected(appearance: style, parts: parts, paints: paints, printing: [appearancePrinting(source, 1)], nameBytes: latin1.encode('Graph'));
    for (final (String, AiNativeAppearances) item in [('before', source), ('after', changed)]) {
      final String name = '$variant.${item.$1}';
      await File('${output.path}/$name.ps').writeAsBytes(item.$2.structure.drawing.records.program.bytes);
      rows.add({'source': name, ...appearanceInventory(item.$2)});
    }
    stdout.writeln('$variant: ${changed.styles.length} styles, ${changed.styles.last.parts.length} selected parts');
  }
  await File('${output.path}/report.json').writeAsString('${const JsonEncoder.withIndent('  ').convert(rows)}\n');
}
