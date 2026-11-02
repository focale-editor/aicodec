import 'dart:io';

import 'package:aikit/aikit.dart';

import '../test/ai_native_document_creation_test.dart';

/// Emits entirely new native/PDF documents for independent reader checks.
Future<void> main() async {
  final Directory output = await Directory('test/corpus/output/documents').create(recursive: true);
  for (final AiNativeDocumentColorMode mode in AiNativeDocumentColorMode.values) {
    for (final bool blank in [false, true]) {
      final String name = '${mode.name}-${blank ? 'blank' : 'artwork'}';
      final AiNativeRecords records = newDocumentRecords(blank: blank, mode: mode);
      final PdfDocument host = newDocumentPdf(blank: blank, mode: mode);
      final AiPdfDocument saved = newDocumentSave(records, host);
      await File('${output.path}/$name.ps').writeAsBytes(records.program.bytes);
      await File('${output.path}/$name.ai').writeAsBytes(const AiCodec().encode(saved));
      await File('${output.path}/$name.pdf').writeAsBytes(const AiCodec().encode(AiPdfDocument(pdf: host)));
      final AiNativeSource source = AiNativeData.extract(saved).single;
      final AiNativeLayers layers = AiNativeLayers.decode(
        drawing: AiNativeDrawing.decode(
          records: AiNativeRecords.decode(program: AiProgram.decode(bytes: source.bytes)),
        ),
      );
      final AiNativeRecords changed = layers.create(definition: newDocumentLayer('later')).drawing.records;
      final AiPdfDocument edited = AiNativeData.replace(source: source, program: changed.program.bytes, synchronizedPdf: saved.pdf);
      await File('${output.path}/$name-edited.ps').writeAsBytes(changed.program.bytes);
      await File('${output.path}/$name-edited.ai').writeAsBytes(const AiCodec().encode(edited));
    }
  }
  stdout.writeln('Wrote four new documents and four ordinary subsequent saves to ${output.path}.');
}
