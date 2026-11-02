import 'dart:convert';
import 'dart:io';

import 'package:aikit/aikit.dart';

import '../test/ai_native_test.dart' as fixtures;
import '../test/ai_native_text_lifecycle_test.dart' show addLifecycleStory, lifecycleDocument;
import '../test/ai_native_text_save_test.dart' show composedTextView;

/// Produces structural save evidence; synthetic glyphs are not font acceptance.
Future<void> main() async {
  final Directory output = await Directory('test/corpus/output/text-lifecycle').create(recursive: true);
  final List<Map<String, Object>> report = [];
  for (final bool named in [false, true]) {
    final String prefix = named ? 'named' : 'compact';
    final AiNativeTextDocument originalText = addLifecycleStory(lifecycleDocument(named: named), 'Old', named: named);
    final AiPdfDocument original = fixtures.nativePdf(compression: .zstandard, alias: true, thumbnail: true, nativeProgram: latin1.decode(originalText.records.program.bytes));
    final AiNativeSource source = AiNativeData.extract(original).single;
    AiNativeTextDocument text = AiNativeTextDocument.decode(
      records: AiNativeRecords.decode(program: AiProgram.decode(bytes: source.bytes)),
    );

    /// Stores complete native and engine payloads for independent comparison.
    Future<void> save(String stage) async {
      final String name = '$prefix.$stage';
      await File('${output.path}/$name.ps').writeAsBytes(text.records.program.bytes);
      await File('${output.path}/$name.ate').writeAsBytes(text.engine.bytes);
      report.add({'name': name, 'texts': text.stories.map((story) => story.text).toList(), 'frames': text.stories.map((story) => story.frameIndices).toList()});
    }

    await save('original');
    text = text.replaceText(story: text.stories.single, start: 0, end: 3, text: 'New');
    text = text.createStory(
      text: 'Temporary',
      frames: [AiNativeTextFrameDefinition.point(x: 30, y: 40, named: named)],
      layer: text.records.program.layers.single,
    );
    await save('created');
    text = text.duplicateStory(story: text.stories.first);
    await save('copied');
    text = text.duplicateFrame(frame: text.frames.last);
    await save('linked');
    text = text.removeFrame(frame: text.frames.last);
    text = text.removeStory(story: text.stories.first);
    text = text.removeStory(story: text.stories.first);
    await save('removed');
    text = text.withComposedText(
      story: text.stories.single,
      view: composedTextView(text.stories.single, named: named),
      bounds: AiBoundingBox(left: 0, bottom: 0, right: 100, top: 100),
    );
    text.validateTextForSave();
    await save('composed');
    final PdfEditor host = PdfEditor(document: original.pdf);
    for (int index = 0; index < host.document.pages.length; index++) {
      final String font = host.setPageResource(
        pageIndex: index,
        category: 'Font',
        prefix: 'Text',
        value: PdfDictionary(
          values: {
            'Type': PdfName(value: 'Font'),
            'Subtype': PdfName(value: 'Type1'),
            'BaseFont': PdfName(value: 'Helvetica'),
          },
        ),
      );
      host.setPageContent(pageIndex: index, bytes: latin1.encode('BT /$font 12 Tf 10 80 Td (New) Tj ET'));
    }
    final AiPdfDocument saved = AiNativeData.replace(source: source, program: text.records.program.bytes, synchronizedPdf: host.document);
    await File('${output.path}/$prefix.ai').writeAsBytes(const AiCodec().encode(saved));
  }
  await File('${output.path}/report.json').writeAsString(const JsonEncoder.withIndent('  ').convert(report));
  stdout.writeln('Wrote 12 text lifecycle snapshots and 2 complete AI saves to ${output.path}.');
}
