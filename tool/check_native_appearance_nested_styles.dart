import 'dart:convert';
import 'dart:io';

import 'package:aicodec/aicodec.dart';

import '../test/ai_native_appearance_editing_test.dart' show appearanceEditingModel;
import '../test/ai_native_appearance_nested_styles_test.dart' show nestedAppearanceEdit, nestedAppearanceSource;
import 'check_native_appearance_groups.dart' show appearanceGroupInventory;
import 'check_native_appearances.dart' show appearanceInventory;

/// Emits outer appearance edits with exact retained private style applications.
Future<void> main() async {
  final Directory output = await Directory('test/corpus/output/appearance-nested-styles').create(recursive: true);
  final List<Map<String, Object?>> rows = [];
  for (final String variant in ['selected', 'shared', 'simple-selected', 'simple-shared', 'compound-selected', 'compound-shared']) {
    final AiNativeAppearances before = appearanceEditingModel(
      source: nestedAppearanceSource(compound: variant.startsWith('compound'), simple: variant.startsWith('simple')),
    );
    final AiNativeAppearances after = nestedAppearanceEdit(before, shared: variant.endsWith('shared'));
    for (final (String, AiNativeAppearances) item in [('before', before), ('after', after)]) {
      final String name = '$variant.${item.$1}';
      await File('${output.path}/$name.ps').writeAsBytes(item.$2.structure.drawing.records.program.bytes);
      rows.add({'source': name, ...appearanceInventory(item.$2), ...appearanceGroupInventory(item.$2)});
    }
    stdout.writeln('$variant: complete outer edit with exact retained nested style uses');
  }
  await File('${output.path}/report.json').writeAsString('${const JsonEncoder.withIndent('  ').convert(rows)}\n');
}
