import 'dart:convert';
import 'dart:io';

import 'package:aikit/aikit.dart';

/// Rebuilds PDF compatibility artwork from original and edited native drawings.
Future<void> main() async {
  final Directory output = await Directory('test/corpus/output/native-pdf').create(recursive: true);
  final List<Map<String, Object?>> report = [];
  int failures = 0;
  for (final String name in ['cmyk_rectangle.ai', 'rgb_rectangle.ai', 'circle.ai', 'simple_shapes.ai', 'simple_shapes_cc.ai', 'opacity.ai']) {
    try {
      final AiDocument document = const AiCodec().decode(await File('test/corpus/files/$name').readAsBytes());
      final AiNativeSource source = AiNativeData.extract(document).single;
      final AiProgram program = AiProgram.decode(bytes: source.bytes);
      final RegExpMatch crop = RegExp(r'%AI3_Cropmarks:\s*([^\r\n]+)').firstMatch(latin1.decode(program.bytes))!;
      final AiBoundingBox cropBounds = AiBoundingBox.parse(value: crop[1]!);
      final List<double>? media = document is AiPdfDocument
          ? (document.pdf.resolve(document.pdf.pages.single.inherited['MediaBox']!) as PdfArray).values.cast<PdfNumber>().map((value) => value.value.toDouble()).toList()
          : null;
      final AiBoundingBox bounds = media == null
          ? cropBounds
          : AiBoundingBox(left: cropBounds.left, bottom: cropBounds.bottom, right: cropBounds.left + media[2] - media[0], top: cropBounds.bottom + media[3] - media[1]);
      final AiNativeDrawing drawing = AiNativeDrawing.decode(records: AiNativeRecords.decode(program: program));
      final AiNativeDrawing moved = drawing.translateLiveShapes(shapes: drawing.liveShapes, deltaX: 37, deltaY: -19);
      PdfDocument rebuilt;
      PdfDocument translated;
      if (document is AiPdfDocument) {
        rebuilt = AiNativePdf.save(source: source, program: program, pageBounds: [bounds]).pdf;
        final AiPdfDocument saved = AiNativePdf.save(source: source, program: moved.records.program, pageBounds: [bounds]);
        translated = saved.pdf;
        final AiPdfDocument reopened = const AiCodec().decode(const AiCodec().encode(saved)) as AiPdfDocument;
        if (latin1.decode(AiNativeData.extract(reopened).single.bytes) != latin1.decode(moved.records.program.bytes)) {
          throw StateError('Saved native data differs from the PDF rendering source.');
        }
        await File('${output.path}/$name.original.pdf').writeAsBytes(const AiCodec().encode(document));
        await File('${output.path}/$name.saved.ai').writeAsBytes(const AiCodec().encode(saved));
      } else {
        rebuilt = AiNativePdf.render(program: program, bounds: bounds);
        translated = AiNativePdf.render(program: moved.records.program, bounds: bounds);
      }
      await File('${output.path}/$name.rebuilt.pdf').writeAsBytes(const PdfEncoder().convert(rebuilt));
      await File('${output.path}/$name.translated.pdf').writeAsBytes(const PdfEncoder().convert(translated));
      await File('${output.path}/$name.native.ps').writeAsBytes(program.bytes);
      await File('${output.path}/$name.translated.ps').writeAsBytes(moved.records.program.bytes);
      report.add({
        'file': name,
        'shapes': drawing.liveShapes.length,
        'pdfBacked': document is AiPdfDocument,
        'bounds': [bounds.left, bounds.bottom, bounds.right, bounds.top],
        'status': 'passed',
      });
      stdout.writeln('$name: native and PDF saved together');
    } on Object catch (error, stack) {
      failures++;
      report.add({'file': name, 'status': 'failed', 'error': '$error'});
      stderr.writeln('$name: $error\n$stack');
    }
  }
  await File('${output.path}/report.json').writeAsString(const JsonEncoder.withIndent('  ').convert(report));
  await _checkComposition(output);
  if (failures > 0) {
    exitCode = 1;
  }
}

/// Writes independent pixel probes for opacity, blend groups and clipping scope.
Future<void> _checkComposition(Directory output) async {
  final AiProgram program = AiProgram.decode(
    bytes: latin1.encode('''%!PS-Adobe-3.0
%%Creator: Adobe Illustrator
%%BeginSetup
%%EndSetup
0 0.5 0 0 0 Xy 1 0 0 Xa 0 0 1 XA 10 w
10 90 m 70 90 L 70 150 L 10 150 L b
0 1 0 0 0 Xy 0 1 0 Xa
100 90 m 170 90 L 170 150 L 100 150 L f
u 1 0 0 Xa 110 100 m 160 100 L 160 140 L 110 140 L f U
1 0.5 0 0 0 Xy 0 0 Xd 6 () XW
0 1 0 0 0 Xy
q 10 10 m 70 10 L 70 70 L 10 70 L h W N
0 0 1 Xa 0 0 m 90 0 L 90 80 L 0 80 L f Q
1 0 0 Xa 90 10 m 110 10 L 110 70 L 90 70 L f
0 1 1 1 0 0 0 0 0 0 Lb (Hidden) Ln
120 10 m 140 10 L 140 70 L 120 70 L f LB
1 1 1 0 0 0 0 0 0 0 Lb (Nonprinting) Ln
150 10 m 170 10 L 170 70 L 150 70 L f LB
%%Trailer
%%EOF
'''),
  );
  final PdfDocument pdf = AiNativePdf.render(program: program, bounds: AiBoundingBox(left: 0, bottom: 0, right: 200, top: 160));
  await File('${output.path}/composition.pdf').writeAsBytes(const PdfEncoder().convert(pdf));
}
