import 'dart:convert';
import 'dart:io';

import 'package:aicodec/aicodec.dart';

import '../test/ai_native_appearance_ancestors_test.dart' show appearanceAncestorsEdit, appearanceAncestorsSource;
import '../test/ai_native_appearance_editing_test.dart' show appearanceEditingModel;
import 'check_native_appearance_groups.dart' show appearanceGroupInventory;
import 'check_native_appearances.dart' show appearanceInventory;
import 'check_native_path_topology.dart' show pathTopologyInventory;

/// Emits selected/shared edits under exact retained ordinary clipping ancestors.
Future<void> main() async {
  final Directory output = await Directory('test/corpus/output/appearance-ancestors').create(recursive: true);
  final List<Map<String, Object?>> rows = [];
  for (final String kind in ['ordinary', 'live', 'private', 'nested', 'compound']) {
    for (final bool shared in [false, true]) {
      final String variant = '$kind-${shared ? 'shared' : 'selected'}';
      final AiNativeAppearances before = appearanceEditingModel(
        source: appearanceAncestorsSource(variant: kind, tail: '50 0 m 60 0 L 60 10 L s\n'),
      );
      final AiNativeAppearances after = appearanceAncestorsEdit(before, shared: shared);
      for (final (String, AiNativeAppearances) item in [('before', before), ('after', after)]) {
        final String name = '$variant.${item.$1}';
        final AiNativeDrawing drawing = item.$2.structure.drawing;
        await File('${output.path}/$name.ps').writeAsBytes(drawing.records.program.bytes);
        rows.add({
          'source': name,
          ...appearanceInventory(item.$2),
          ...appearanceGroupInventory(item.$2),
          'paths': pathTopologyInventory(drawing),
          'groups': [
            for (final AiNativeGroup group in drawing.groups)
              {
                'span': [group.start, group.end],
                'private': group.opening.isPrivate,
                'paths': group.paths.map(drawing.paths.indexOf).toList(),
              },
          ],
        });
      }
      stdout.writeln('$variant: retained enclosing masks and native state');
    }
  }
  await File('${output.path}/report.json').writeAsString('${const JsonEncoder.withIndent('  ').convert(rows)}\n');
}
