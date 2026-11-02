import 'dart:convert';
import 'dart:io';

import 'package:aicodec/aicodec.dart';

import '../test/ai_native_appearance_editing_test.dart' show appearanceEditingModel;
import '../test/ai_native_appearance_groups_test.dart' show appearanceGroupEdit, appearanceGroupsSource;
import 'check_native_appearances.dart' show appearanceInventory;

/// Records native group ownership independently of its host-supplied expansion.
Map<String, Object?> appearanceGroupInventory(AiNativeAppearances model) => {
  'artwork': [
    for (final AiNativeAppearanceArtwork artwork in model.uses.where((use) => !use.instruction.isPrivate).map((use) => model.artworkFor(use: use)))
      {
        'authoring': [artwork.authoring.start, artwork.authoring.end],
        'printing': [artwork.printingGroup.start, artwork.printingGroup.end],
        'group': artwork.group != null,
        'compound': artwork.group?.compound,
        'paths': artwork.group?.paths.length ?? 1,
        'nestedUses': [for (final AiNativeResourceUse use in artwork.nestedUses) model.uses.indexOf(use)],
        'metadata': [
          for (final AiNativeContainer record in artwork.metadata) [record.start, record.end],
        ],
      },
  ],
};

/// Emits complete selected/shared transactions without claiming visual composition.
Future<void> main() async {
  final Directory output = await Directory('test/corpus/output/appearance-groups').create(recursive: true);
  final List<Map<String, Object?>> rows = [];
  for (final String variant in ['selected', 'shared', 'compound-selected', 'compound-shared', 'uncounted', 'mixed']) {
    final AiNativeAppearances before = appearanceEditingModel(
      source: appearanceGroupsSource(compound: variant.startsWith('compound'), counted: variant != 'uncounted', mixed: variant == 'mixed'),
    );
    final AiNativeAppearances after = appearanceGroupEdit(before, shared: variant.endsWith('shared') || variant == 'mixed');
    for (final (String, AiNativeAppearances) item in [('before', before), ('after', after)]) {
      final String name = '$variant.${item.$1}';
      await File('${output.path}/$name.ps').writeAsBytes(item.$2.structure.drawing.records.program.bytes);
      rows.add({'source': name, ...appearanceInventory(item.$2), ...appearanceGroupInventory(item.$2)});
    }
    stdout.writeln('$variant: qualified group appearance owners and retained native subtrees');
  }
  await File('${output.path}/report.json').writeAsString('${const JsonEncoder.withIndent('  ').convert(rows)}\n');
}
