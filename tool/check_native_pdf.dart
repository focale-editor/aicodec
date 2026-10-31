import 'dart:convert';
import 'dart:io';

import 'package:aikit/aikit.dart';

/// Rebuilds PDF compatibility artwork from original and edited native drawings.
Future<void> main() async {
  final Directory output = await Directory('test/corpus/output/native-pdf').create(recursive: true);
  final List<Map<String, Object?>> report = [];
  int failures = 0;
  for (final String name in ['cmyk_rectangle.ai', 'rgb_rectangle.ai', 'circle.ai', 'simple_shapes.ai', 'simple_shapes_cc.ai', 'opacity.ai', 'gradient_linear.ai', 'gradient_radial.ai']) {
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
      if (name == 'circle.ai') {
        await _checkMidpoints(output, program);
      }
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
        if (name.startsWith('gradient_')) {
          final AiProgram colors = _replaceGradient(program);
          final AiPdfDocument recolored = AiNativePdf.save(source: source, program: colors, pageBounds: [bounds]);
          await File('${output.path}/$name.colors.ps').writeAsBytes(colors.bytes);
          await File('${output.path}/$name.colors.ai').writeAsBytes(const AiCodec().encode(recolored));
          await File('${output.path}/$name.colors.pdf').writeAsBytes(const PdfEncoder().convert(recolored.pdf));
        }
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

/// Exposes two real nonlinear swatches as PDF fields for cached-ramp comparison.
Future<void> _checkMidpoints(Directory output, AiProgram source) async {
  for (final int number in [14, 54]) {
    final bool radial = number == 14;
    final AiProgram program = AiNativeEditor.apply(
      program: source,
      edits: [
        AiSourceEdit(
          start: source.bodyStart,
          end: source.bodyEnd,
          bytes: latin1.encode('''

0 0 m 200 0 L 200 200 L 0 200 L Bb
${radial ? '0 0 0 0 Bh' : ''}
1 (Unnamed gradient $number) 0 0 0 1 1 0 0 1 0 0 1 Bg
${radial ? '100 0 0 -100 100 100 Bm' : '200 0 0 -200 0 200 Xm'}
f 0 BB
'''),
        ),
      ],
    );
    final PdfDocument pdf = AiNativePdf.render(program: program, bounds: AiBoundingBox(left: 0, bottom: 0, right: 200, top: 200));
    await File('${output.path}/midpoint-$number.pdf').writeAsBytes(const PdfEncoder().convert(pdf));
  }
}

/// Changes the shared CC resource to three explicit process colors and opacity.
AiProgram _replaceGradient(AiProgram program) {
  final AiNativeGradientResources resources = AiNativeGradientResources.decode(records: AiNativeRecords.decode(program: program));
  final List<List<double>> channels = [
    [0, 1, 1, 0, 1, 0, 0],
    [1, 0, 1, 0, 0, 1, 0],
    [1, 1, 0, 0, 0, 0, 1],
  ];
  final List<AiNativeGradientStop> stops = [
    for (int index = 0; index < 3; index++)
      AiNativeGradientStop(
        color: AiNativeGradientColor(kind: .rgb, components: channels[index]),
        position: const [0.0, 40.0, 100.0][index],
        opacity: index == 1 ? 0.4 : 1,
      ),
  ];
  final List<AiNativeGradientRamp> ramps = [
    for (int interval = 0; interval < 2; interval++)
      AiNativeGradientRamp(
        kind: .rgb,
        channels: [
          for (int channel = 0; channel < 7; channel++)
            AiNativeGradientChannel.samples(values: [for (int sample = 0; sample < 256; sample++) (channels[interval][channel] * (255 - sample) + channels[interval + 1][channel] * sample).round()]),
        ],
      ),
  ];
  return resources.replaceStops(definition: resources.definitions.first, stops: stops, ramps: ramps).records.program;
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
