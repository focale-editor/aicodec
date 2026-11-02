import 'dart:convert';
import 'dart:io';

import 'package:aicodec/aicodec.dart';

import '../test/ai_native_appearance_artwork_test.dart' show appearanceArtworkReplacement, appearanceArtworkSource;
import '../test/ai_native_appearance_editing_test.dart' show appearanceAssignment, appearanceEditingModel;
import '../test/ai_native_appearance_strokes_test.dart' show appearanceStrokeSource;
import 'check_native_appearances.dart' show appearanceInventory;

/// Emits complete settings transactions without claiming synthetic visual output.
Future<void> main() async {
  final Directory output = await Directory('test/corpus/output/appearance-strokes').create(recursive: true);
  final List<Map<String, Object?>> rows = [];
  for (final String variant in ['selected', 'shared', 'private']) {
    final String text = appearanceStrokeSource(source: appearanceArtworkSource(), private: variant == 'private');
    final AiNativeAppearances model = appearanceEditingModel(source: text);
    final AiNativeAppearance style = model.styles.single;
    final List<AiNativeAppearancePartChange> parts = [AiNativeAppearancePartChange(part: style.parts[6], adjustDashes: false)];
    final List<AiNativePaintChange> paints = [
      AiNativePaintChange(assignment: appearanceAssignment(style, 6, .dash), values: [4, 2], dashPhase: 3),
    ];
    final AiNativeAppearances changed = variant == 'shared'
        ? model.updateShared(appearance: style, parts: parts, paints: paints, artwork: [appearanceArtworkReplacement(model, 0), appearanceArtworkReplacement(model, 1)])
        : model.updateSelected(appearance: style, parts: parts, paints: paints, artwork: [appearanceArtworkReplacement(model, 1)], nameBytes: latin1.encode('Stroke settings'));
    for (final (String, AiNativeAppearances) item in [('before', model), ('after', changed)]) {
      final String name = '$variant.${item.$1}';
      await File('${output.path}/$name.ps').writeAsBytes(item.$2.structure.drawing.records.program.bytes);
      rows.add({'source': name, ...appearanceInventory(item.$2)});
    }
    stdout.writeln('$variant: dash adjustment, sequence and phase saved atomically');
  }
  await File('${output.path}/report.json').writeAsString('${const JsonEncoder.withIndent('  ').convert(rows)}\n');
}
