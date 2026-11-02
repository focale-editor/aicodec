import 'dart:io';

import 'package:aikit/aikit.dart';

import '../test/ai_native_document_creation_test.dart';
import '../test/ai_native_text_creation_test.dart';

/// Emits new typography namespaces and lifecycle edits without a source template.
Future<void> main() async {
  final Directory output = await Directory('test/corpus/output/text-creation').create(recursive: true);
  final AiNativeTextDocument initial = newDocumentText();
  final AiNativeTextDocument created = initial.createStory(text: 'Bonjour 🖋\rSuite', frames: [AiNativeTextFrameDefinition.point(x: 10, y: 20)], layer: initial.records.program.layers.single);
  final AiNativeTextDocument copied = created.duplicateStory(story: created.stories.single);
  final AiNativeTextDocument removed = copied.removeStory(story: copied.stories.first);
  final AiNativeTextDocument empty = removed.removeStory(story: removed.stories.single);
  for (final (String, AiNativeTextDocument) row in [('initial', initial), ('created', created), ('copied', copied), ('removed', removed), ('empty', empty)]) {
    await File('${output.path}/${row.$1}.ps').writeAsBytes(row.$2.records.program.bytes);
    await File('${output.path}/${row.$1}.ate').writeAsBytes(row.$2.engine.bytes);
    await File('${output.path}/${row.$1}.undo.ate').writeAsBytes(row.$2.records.containers.singleWhere((record) => record.type == 'AI11UndoFreeTextDocument').decodeBinary());
  }
  final AiPdfDocument first = newDocumentSave(initial.records, newDocumentPdf(blank: true));
  await File('${output.path}/initial.ai').writeAsBytes(const AiCodec().encode(first));
  final AiPdfDocument saved = AiNativeData.replace(source: AiNativeData.extract(first).single, program: empty.records.program.bytes, synchronizedPdf: first.pdf);
  await File('${output.path}/empty.ai').writeAsBytes(const AiCodec().encode(saved));
  stdout.writeln('Wrote five new ATE snapshots and two matching empty PDF-backed AI files to ${output.path}.');
}
