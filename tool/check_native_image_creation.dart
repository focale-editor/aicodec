import 'dart:io';

import 'package:aicodec/aicodec.dart';

import '../test/ai_native_document_creation_test.dart';
import '../test/ai_native_image_creation_test.dart';

/// Emits newly authored images and two complete saves for independent readers.
Future<void> main() async {
  final Directory output = await Directory('test/corpus/output/image-creation').create(recursive: true);
  final AiNativeDrawing drawing = createdImageDocument();
  final PdfDocument host = createdImagePdf();
  final AiPdfDocument saved = newDocumentSave(drawing.records, host);
  await File('${output.path}/created.ps').writeAsBytes(drawing.records.program.bytes);
  await File('${output.path}/created.ai').writeAsBytes(const AiCodec().encode(saved));
  await File('${output.path}/host.pdf').writeAsBytes(const AiCodec().encode(AiPdfDocument(pdf: host)));
  final AiNativeSource source = AiNativeData.extract(saved).single;
  final AiNativePlacements links = AiNativePlacements.decode(
    records: AiNativeRecords.decode(program: AiProgram.decode(bytes: source.bytes)),
  );
  final AiNativeRasters embedded = links.embed(object: links.objects.single, samples: createdImageSamples());
  final AiPdfDocument second = AiNativeData.replace(source: source, program: embedded.records.program.bytes, synchronizedPdf: saved.pdf);
  await File('${output.path}/embedded.ps').writeAsBytes(embedded.records.program.bytes);
  await File('${output.path}/embedded.ai').writeAsBytes(const AiCodec().encode(second));
  stdout.writeln('Wrote two native image snapshots and matching AI/PDF saves to ${output.path}.');
}
