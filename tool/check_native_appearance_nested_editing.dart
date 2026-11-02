import 'dart:convert';
import 'dart:io';

import 'package:aicodec/aicodec.dart';

import '../test/ai_native_appearance_editing_test.dart' show appearanceEditingModel;
import '../test/ai_native_appearance_nested_editing_test.dart' show nestedStyleEdit, nestedStylePaints, nestedStyleReplacement, nestedStyleSource;
import '../test/ai_native_appearance_nested_styles_test.dart' show nestedAppearanceOwners;
import 'check_native_appearance_groups.dart' show appearanceGroupInventory;
import 'check_native_appearances.dart' show appearanceInventory;

/// Emits complete nested selections with one supplied group per enclosing owner.
Future<void> main() async {
  final Directory output = await Directory('test/corpus/output/appearance-nested-editing').create(recursive: true);
  final List<Map<String, Object?>> rows = [];
  for (final String variant in [
    'path',
    'group',
    'both',
    'shared',
    'simple-selected',
    'simple-shared',
    'compound-selected',
    'compound-shared',
    'restored-selected',
    'restored-shared',
    'outer-shared',
    'create',
  ]) {
    String source = nestedStyleSource(
      compound: variant.startsWith('compound'),
      simple: variant.startsWith('simple'),
      localConsumer: variant.startsWith('restored'),
      reset: variant == 'outer-shared' || variant == 'create',
    );
    if (variant == 'outer-shared') {
      source = source.replaceAll('%_0 (Child) XW', '%_0 (Shared) XW');
    }
    final AiNativeAppearances before = appearanceEditingModel(source: source);
    final AiNativeAppearances after;
    if (variant == 'outer-shared') {
      after = before.updateShared(
        appearance: before.styles.first,
        paints: nestedStylePaints(before.styles.first),
        artwork: [
          for (final int index in [0, 1]) nestedStyleReplacement(before, index, outer: true),
        ],
      );
    } else if (variant == 'create') {
      final AiNativeAppearance style = before.styles[1];
      final AiNativeAppearancePart stack = style.parts[1];
      after = before.updateSelected(
        appearance: style,
        parts: [
          AiNativeAppearancePartChange(
            part: stack,
            children: [
              AiNativeAppearanceChild.create(
                definition: AiNativeAppearancePartDefinition(
                  kind: .fill,
                  colors: [
                    AiColor(space: .rgb, channels: [0, 1, 1]),
                  ],
                ),
              ),
              for (final int index in stack.childIndices) AiNativeAppearanceChild.retain(part: style.parts[index]),
            ],
          ),
        ],
        artwork: [nestedStyleReplacement(before, 0)],
        nameBytes: latin1.encode('Child with added fill'),
      );
    } else {
      after = nestedStyleEdit(before, shared: variant.endsWith('shared'), both: variant == 'both', child: variant == 'group' ? 1 : 0);
    }
    for (final (String, AiNativeAppearances) item in [('before', before), ('after', after)]) {
      final String name = '$variant.${item.$1}';
      await File('${output.path}/$name.ps').writeAsBytes(item.$2.structure.drawing.records.program.bytes);
      rows.add({
        'source': name,
        ...appearanceInventory(item.$2),
        ...appearanceGroupInventory(item.$2),
        'nestedOwners': [
          for (final AiNativeResourceUse use in nestedAppearanceOwners(item.$2))
            for (final AiNativeAppearanceArtwork artwork in [item.$2.artworkFor(use: use)])
              for (final AiNativeResourceUse child in artwork.nestedUses)
                {
                  'use': item.$2.uses.indexOf(child),
                  'span': [artwork.authoringFor(use: child).start, artwork.authoringFor(use: child).end],
                },
        ],
      });
    }
    stdout.writeln('$variant: native child selection and complete supplied printing owners');
  }
  await File('${output.path}/report.json').writeAsString('${const JsonEncoder.withIndent('  ').convert(rows)}\n');
}
