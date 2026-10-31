import 'dart:convert';
import 'dart:io';

import 'package:aikit/aikit.dart';

/// Writes a linked-image probe with separate alpha, object opacity and clipping.
Future<void> _writeLinkedProbe(Directory output) async {
  final AiProgram program = AiProgram.decode(
    bytes: latin1.encode('''%!PS-Adobe-3.0
%%Creator: Adobe Illustrator
%%EndComments
%%EndSetup
0 0 1 Xa 0 0 m 100 0 L 100 100 L 0 100 L f
q 10 30 m 40 30 L 40 70 L 10 70 L h W N
0 0.5 0 0 0 Xy
%AI5_BeginPlace
%%FileType: 1
[20 0 0 -20 10 70] 0 0 2 2 4 4 0 (probe.png)`
%%IncludeFile:probe.png
~
%AI5_EndPlace
Q
%%Trailer
%%EOF
'''),
  );
  final AiNativeRasterSamples samples = AiNativeRasterSamples(
    width: 2,
    height: 2,
    bitsPerComponent: 8,
    components: 3,
    colorSamples: [255, 0, 0, 0, 255, 0, 0, 0, 255, 255, 255, 255],
    alphaSamples: [128, 255, 0, 255],
  );
  final PdfDocument pdf = AiNativePdf.render(program: program, bounds: AiBoundingBox(left: 0, bottom: 0, right: 100, top: 100), resolvePlacement: (object) => samples);
  await File('${output.path}/linked-alpha-probes.pdf').writeAsBytes(const PdfEncoder().convert(pdf));
}

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
  final List<(String, AiNativePlacements, AiNativeRasterSamples)> cases = [('preview', placements, preview.toSamples()), ('resolved', placements, full), ('translated', moved, full)];
  for (final (String, AiNativePlacements, AiNativeRasterSamples) variant in cases) {
    final AiNativeRasters embedded = variant.$2.embed(object: variant.$2.objects.single, samples: variant.$3);
    await File('${output.path}/${variant.$1}.embedded.ps').writeAsBytes(embedded.records.program.bytes);
    await File('${output.path}/${variant.$1}.pdf').writeAsBytes(const PdfEncoder().convert(AiNativePdf.render(program: embedded.records.program, bounds: bounds)));
    await File('${output.path}/${variant.$1}.linked.pdf')
        .writeAsBytes(const PdfEncoder().convert(AiNativePdf.render(program: variant.$2.records.program, bounds: bounds, resolvePlacement: (object) => variant.$3)));
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
  for (final (String, AiNativePlacements, AiNativeRasterSamples) variant in cases) {
    final AiPdfDocument linked = AiNativePdf.save(source: source, program: variant.$2.records.program, pageBounds: [bounds], resolvePlacement: (object) => variant.$3);
    await File('${output.path}/${variant.$1}.linked.ai').writeAsBytes(const AiCodec().encode(linked));
  }
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
  await _writeLinkedProbe(output);
  stdout.writeln('CC placement: three embedded and three linked variants rendered; four synchronized PDFs saved');
}
