import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:aikit/aikit.dart';

/// Exercises relative CC placement and synchronized saves on original/transformed art.
Future<void> main() async {
  final Directory output = await Directory('test/corpus/output/gradient-placement').create(recursive: true);
  final List<Map<String, Object?>> report = [];
  for (final String name in ['gradient_linear.ai', 'gradient_radial.ai']) {
    final AiDocument document = const AiCodec().decode(await File('test/corpus/files/$name').readAsBytes());
    final AiNativeSource source = AiNativeData.extract(document).single;
    final AiNativeDrawing original = AiNativeDrawing.decode(
      records: AiNativeRecords.decode(program: AiProgram.decode(bytes: source.bytes)),
    );
    final bool radial = name == 'gradient_radial.ai';
    final List<double> parameters = [0.15, if (radial) -0.2 else 0, 37, 0.75, if (radial) 0.6 else 1];
    await File('${output.path}/$name.original.ps').writeAsBytes(source.bytes);
    for (final String variant in ['all', 'selected', 'transformed']) {
      AiNativeDrawing drawing = original;
      if (variant == 'transformed') {
        drawing = drawing.rotateLiveShapes(shapes: drawing.liveShapes, radians: pi / 7, pivotX: 960, pivotY: -540);
        drawing = drawing.scaleLiveShapes(shapes: drawing.liveShapes, factor: 0.8, pivotX: 960, pivotY: -540);
      }
      final List<int> selected = variant == 'all' ? List.generate(drawing.liveShapes.length, (index) => index) : [0, drawing.liveShapes.length ~/ 2, drawing.liveShapes.length - 1];
      final AiNativeDrawing changed = drawing.setLiveShapeGradientPlacement(
        shapes: selected.map((index) => drawing.liveShapes[index]).toList(),
        nameBytes: drawing.gradients.first.geometry.nameBytes,
        originX: parameters[0],
        originY: parameters[1],
        angle: parameters[2],
        length: parameters[3],
        aspectRatio: parameters[4],
      );
      final String stem = '${output.path}/$name.$variant';
      final AiBoundingBox bounds = AiBoundingBox(left: 0, bottom: -1080, right: 1920, top: 0);
      final AiPdfDocument saved = AiNativePdf.save(source: source, program: changed.records.program, pageBounds: [bounds]);
      await File('$stem.before.ps').writeAsBytes(drawing.records.program.bytes);
      await File('$stem.ps').writeAsBytes(changed.records.program.bytes);
      await File('$stem.ai').writeAsBytes(const AiCodec().encode(saved));
      await File('$stem.pdf').writeAsBytes(const PdfEncoder().convert(saved.pdf));
      report.add({'file': name, 'variant': variant, 'selected': selected, 'shapes': drawing.liveShapes.length, 'parameters': parameters});
      stdout.writeln('$name $variant: ${selected.length} selected shapes');
    }
  }
  await File('${output.path}/report.json').writeAsString(const JsonEncoder.withIndent('  ').convert(report));
}
