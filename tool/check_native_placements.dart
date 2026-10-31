import 'dart:convert';
import 'dart:io';

import 'package:aikit/aikit.dart';

/// Exercises a real CC placement with both its preview and host-resolved pixels.
Future<void> main() async {
  final Directory output = await Directory('test/corpus/output/native-placements').create(recursive: true);
  final AiPostScriptDocument document = const AiCodec().decode(await File('test/corpus/files/image_linked_original_cc.ai').readAsBytes()) as AiPostScriptDocument;
  if (document.dscIssue != null) {
    throw StateError('The intact placement must have complete DSC metadata.');
  }
  final AiProgram program = AiProgram.decode(bytes: document.postScriptBytes);
  final AiNativePlacements placements = AiNativePlacements.decode(records: AiNativeRecords.decode(program: program));
  final AiNativePlacedObject object = placements.objects.single;
  final AiNativePlacedPreview preview = object.preview!;
  final AiBoundingBox bounds = AiBoundingBox(left: 0, bottom: -792, right: 612, top: 0);
  await File('${output.path}/original.ps').writeAsBytes(program.bytes);
  await File('${output.path}/preview.argb').writeAsBytes(preview.bytes);
  final AiNativePlacements moved = placements.translate(objects: placements.objects, deltaX: 37, deltaY: -19);
  await File('${output.path}/translated.ps').writeAsBytes(moved.records.program.bytes);
  final AiDocument host = const AiCodec().decode(await File('test/corpus/files/raster_v2020.ai').readAsBytes());
  final AiNativeRasters hostImages = AiNativeRasters.decode(
    records: AiNativeRecords.decode(program: AiProgram.decode(bytes: AiNativeData.extract(host).single.bytes)),
  );
  final AiNativeRaster resolved = hostImages.images.singleWhere((image) => image.isPrintable(program: hostImages.records.program));
  final AiNativeRasterSamples full = AiNativeRasterSamples(
    width: resolved.width,
    height: resolved.height,
    bitsPerComponent: resolved.bitsPerComponent,
    components: resolved.components,
    colorSamples: resolved.colorSamples,
    alphaSamples: resolved.alphaSamples,
  );
  await File('${output.path}/host-source.ps').writeAsBytes(hostImages.records.program.bytes);
  final List<Map<String, Object?>> variants = [];
  for (final (String, AiNativePlacements, AiNativeRasterSamples) variant in [('preview', placements, preview.toSamples()), ('resolved', placements, full), ('translated', moved, full)]) {
    final AiNativeRasters embedded = variant.$2.embed(object: variant.$2.objects.single, samples: variant.$3);
    await File('${output.path}/${variant.$1}.embedded.ps').writeAsBytes(embedded.records.program.bytes);
    await File('${output.path}/${variant.$1}.pdf').writeAsBytes(const PdfEncoder().convert(AiNativePdf.render(program: embedded.records.program, bounds: bounds)));
    variants.add({'variant': variant.$1, 'width': variant.$3.width, 'height': variant.$3.height, 'components': variant.$3.components});
  }
  // A PDF carrier separately tests native envelope synchronization for this
  // source, whose original Illustrator container has no PDF compatibility page.
  final PdfDocument carrier = PdfDocument.fromPages(pages: [PdfPageSource(width: 612, height: 792, content: [])]);
  final PdfEditor editor = PdfEditor(document: carrier);
  final PdfReference native = editor.addObject(
    value: PdfStream(dictionary: PdfDictionary(), data: program.bytes),
  );
  final PdfDictionary catalog = editor.document.catalog.copyWith(
    values: {
      'PieceInfo': PdfDictionary(
        values: {
          'Illustrator': PdfDictionary(
            values: {
              'Private': PdfDictionary(values: {'AIPrivateData1': native}),
            },
          ),
        },
      ),
    },
  );
  final PdfReference root = editor.document.trailer['Root']! as PdfReference;
  final AiPdfDocument container = AiPdfDocument(pdf: editor.document.copyWith(objects: {...editor.document.objects, root: catalog}));
  final AiNativeSource source = AiNativeData.extract(container).single;
  final AiProgram editedProgram = AiProgram.decode(bytes: await File('${output.path}/resolved.embedded.ps').readAsBytes());
  final AiPdfDocument saved = AiNativePdf.save(source: source, program: editedProgram, pageBounds: [bounds]);
  await File('${output.path}/synchronized.ai').writeAsBytes(const AiCodec().encode(saved));
  await File('${output.path}/report.json').writeAsString(
    const JsonEncoder.withIndent('  ').convert({
      'pathBytes': object.pathBytes,
      'relativeDirectoryBytes': object.relativeDirectoryBytes,
      'matrix': object.matrix,
      'bounds': object.bounds,
      'preview': {'width': preview.width, 'height': preview.height, 'rowBytes': preview.rowBytes, 'bits': preview.bitsPerPixel, 'format': preview.format},
      'variants': variants,
    }),
  );
  stdout.writeln('CC placement: preview decoded, placement translated, three embedded variants and one synchronized PDF saved');
}
