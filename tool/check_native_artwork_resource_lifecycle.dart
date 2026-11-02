import 'dart:convert';
import 'dart:io';

import 'package:aicodec/aicodec.dart';

import '../test/ai_native_artwork_resource_lifecycle_test.dart';
import '../test/ai_native_document_creation_test.dart';

/// Emits complete resource creation, revision and removal saves for external readers.
Future<void> main(List<String> arguments) async {
  final Directory output = await Directory(arguments.isEmpty ? 'test/corpus/output/artwork-resource-lifecycle' : arguments.single).create(recursive: true);
  final PdfDocument host = newDocumentPdf(blank: true);
  await File('${output.path}/host.pdf').writeAsBytes(const AiCodec().encode(AiPdfDocument(pdf: host)));
  for (final AiNativeArtworkResourceKind kind in AiNativeArtworkResourceKind.values) {
    AiNativeArtworkResources model = resourceLifecycleCreate(resourceLifecycleModel(), kind, name: 'Resource (é)\\');
    AiNativeSource? previous;
    PdfDocument synchronized = host;
    for (final String phase in ['created', 'replaced', 'removed']) {
      if (phase == 'replaced') {
        model = model.replaceUnused(
          resource: model.resources.single,
          artworkBytes: latin1.encode(resourceLifecycleArtwork(gray: .75)),
          bounds: kind == .pattern ? AiBoundingBox(left: 0, bottom: 0, right: 30, top: 40) : null,
        );
      } else if (phase == 'removed') {
        model = model.remove(resources: model.resources);
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
      model = resourceLifecycleModel(
        records: AiNativeRecords.decode(program: AiProgram.decode(bytes: previous.bytes)),
      );
    }
  }
  stdout.writeln('Wrote nine complete resource lifecycle saves to ${output.path}.');
}
