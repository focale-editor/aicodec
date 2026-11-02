import 'dart:convert';
import 'dart:io';

import 'package:aicodec/aicodec.dart';

import '../test/ai_native_brush_lifecycle_test.dart';
import '../test/ai_native_document_creation_test.dart';

/// Produces actual consecutive saves for independent descriptor and panel inspection.
Future<void> main(List<String> arguments) async {
  final Directory output = await Directory(arguments.isEmpty ? 'test/corpus/output/brush-lifecycle' : arguments.single).create(recursive: true);
  final PdfDocument host = newDocumentPdf(blank: true);
  await File('${output.path}/host.pdf').writeAsBytes(const AiCodec().encode(AiPdfDocument(pdf: host)));
  for (final AiNativeBrushKind kind in AiNativeBrushKind.values) {
    AiNativeBrushes model = brushLifecycleCreate(brushLifecycleModel(), kind);
    AiNativeSource? previous;
    PdfDocument synchronized = host;
    for (final String phase in ['created', 'replaced', 'removed']) {
      if (phase == 'replaced') {
        model = model.replaceUnused(brush: model.brushes.single, payloadBytes: latin1.encode(brushLifecyclePayload(kind, revised: true)));
      } else if (phase == 'removed') {
        model = model.remove(brushes: model.brushes);
      }
      final AiProgram program = model.structure.drawing.records.program;
      final AiPdfDocument saved = previous == null
          ? newDocumentSave(model.structure.drawing.records, host)
          : AiNativeData.replace(source: previous, program: program.bytes, synchronizedPdf: synchronized);
      final String stem = '${kind.name}-$phase';
      await File('${output.path}/$stem.ps').writeAsBytes(program.bytes);
      await File('${output.path}/$stem.ai').writeAsBytes(const AiCodec().encode(saved));
      final AiPdfDocument reopened = const AiCodec().decode(await File('${output.path}/$stem.ai').readAsBytes()) as AiPdfDocument;
      previous = AiNativeData.extract(reopened).single;
      synchronized = reopened.pdf;
      model = AiNativeBrushes.decode(
        structure: AiNativeStructure.decode(
          drawing: AiNativeDrawing.decode(
            records: AiNativeRecords.decode(program: AiProgram.decode(bytes: previous.bytes)),
          ),
        ),
      );
    }
  }
  stdout.writeln('Wrote twelve complete brush descriptor saves to ${output.path}.');
}
