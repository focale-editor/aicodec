import 'dart:convert';
import 'dart:io';

import 'package:aicodec/aicodec.dart';

import '../test/ai_native_text_paints_test.dart' show textPaintChanges, textPaintDocument;

/// Exercises every populated producer story and both native field spellings.
Future<void> main() async {
  final Directory output = await Directory('test/corpus/output/text-paints').create(recursive: true);
  final Map<String, AiNativeTextDocument> sources = {
    'compact': textPaintDocument(),
    'named': textPaintDocument(named: true),
  };
  for (final String name in [
    'flowtext.ai',
    'text_transforms.ai',
    'simple_v2020.ai',
    'simple_cc_legacy.ai',
    'simple_v2020_no_pdf_data.ai',
    'simple_cs.ai',
    'simple_cs2.ai',
    'simple_cs3.ai',
    'simple_cs4.ai',
    'simple_cs5.ai',
    'simple_cs6.ai',
  ]) {
    final AiNativeSource source = AiNativeData.extract(const AiCodec().decode(await File('test/corpus/files/$name').readAsBytes())).single;
    sources[name] = AiNativeTextDocument.decode(
      records: AiNativeRecords.decode(program: AiProgram.decode(bytes: source.bytes)),
    );
  }
  final List<Map<String, Object?>> rows = [];

  /// Keeps complete native programs beside their separately decoded engine data.
  Future<void> save(String prefix, AiNativeTextDocument document) async {
    await File('${output.path}/$prefix.ps').writeAsBytes(document.records.program.bytes);
    await File('${output.path}/$prefix.ate').writeAsBytes(document.engine.bytes);
  }

  for (final MapEntry<String, AiNativeTextDocument> entry in sources.entries) {
    final String name = entry.key;
    final AiNativeTextDocument before = entry.value;
    final bool synthetic = !name.endsWith('.ai');
    final String original = '$name.original';
    await save(original, before);
    for (final AiNativeTextStory story in synthetic ? before.stories.take(1) : before.stories) {
      final int index = before.stories.indexOf(story);
      final int start = synthetic ? 1 : 0;
      final int first = story.modelText.codeUnitAt(start);
      final int end = start + (first >= 0xd800 && first <= 0xdbff ? 2 : 1);
      final AiNativeTextDocument edited = before.setCharacterFeatures(story: story, start: start, end: end, changes: textPaintChanges());
      final AiNativeTextDocument inherited = edited.setCharacterFeatures(
        story: edited.stories[index],
        start: start,
        end: end,
        changes: AiNativeCharacterChanges(inherit: {.fillColor, .strokeColor, .backgroundColor, .dashArray, .lineWidth}),
      );
      for (final (String, AiNativeTextDocument) operation in [('edit', edited), ('inherit', inherited)]) {
        final String prefix = '$name.$index.${operation.$1}';
        await save(prefix, operation.$2);
        rows.add({'file': name, 'story': index, 'start': start, 'end': end, 'operation': operation.$1, 'before': operation.$1 == 'edit' ? original : '$name.$index.edit', 'after': prefix});
      }
      if (synthetic) {
        final AiNativeTextDocument lab = before.setCharacterFeatures(
          story: story,
          start: start,
          end: end,
          changes: AiNativeCharacterChanges(
            fillColor: AiNativeTextProcessColor(space: .lab, components: [50, -128, 127]),
          ),
        );
        final String prefix = '$name.$index.lab';
        await save(prefix, lab);
        rows.add({'file': name, 'story': index, 'start': start, 'end': end, 'operation': 'lab', 'before': original, 'after': prefix});
      }
      stdout.writeln('$name/$index: process paint edits and inheritance saved');
    }
  }
  await File('${output.path}/report.json').writeAsString('${const JsonEncoder.withIndent('  ').convert(rows)}\n');
}
