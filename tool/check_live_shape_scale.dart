import 'dart:convert';
import 'dart:io';

import 'package:aicodec/aicodec.dart';

/// Uniformly scales all live shapes while preserving unselected artwork in real CC files.
Future<void> main() async {
  final Directory output = await Directory('test/corpus/output/live-shape-scale').create(recursive: true);
  final List<Map<String, Object?>> report = [];
  for (final String name in [
    'cmyk_rectangle.ai',
    'rgb_rectangle.ai',
    'circle.ai',
    'simple_shapes.ai',
    'simple_shapes_cc.ai',
    'opacity.ai',
    'gradient_linear.ai',
    'gradient_radial.ai',
    'rectangle_with_rounded_corners.ai',
    'rectangle-rounded-corners-all-different.ai',
    'page_moved_to_1000_2000_rect200_300.ai',
  ]) {
    final AiDocument document = const AiCodec().decode(await File('test/corpus/files/$name').readAsBytes());
    final AiNativeSource source = AiNativeData.extract(document).single;
    final AiProgram program = AiProgram.decode(bytes: source.bytes);
    final AiNativeDrawing drawing = AiNativeDrawing.decode(records: AiNativeRecords.decode(program: program));
    final AiBoundingBox crop = AiBoundingBox.parse(value: RegExp(r'%AI3_Cropmarks:\s*([^\r\n]+)').firstMatch(latin1.decode(program.bytes))![1]!);
    final List<double>? media = document is AiPdfDocument
        ? (document.pdf.resolve(document.pdf.pages.single.inherited['MediaBox']!) as PdfArray).values.cast<PdfNumber>().map((value) => value.value.toDouble()).toList()
        : null;
    final AiBoundingBox bounds = media == null ? crop : AiBoundingBox(left: crop.left, bottom: crop.bottom, right: crop.left + media[2] - media[0], top: crop.bottom + media[3] - media[1]);
    final bool movedPage = name == 'page_moved_to_1000_2000_rect200_300.ai';
    final double pivotX = movedPage ? 1400 : (bounds.left + bounds.right) / 2;
    final double pivotY = movedPage ? -2400 : (bounds.bottom + bounds.top) / 2;
    await File('${output.path}/$name.original.ps').writeAsBytes(program.bytes);
    for (final (String, double) variant in [('smaller', 0.5), ('larger', 1.5)]) {
      final AiNativeDrawing changed = drawing.scaleLiveShapes(shapes: drawing.liveShapes, factor: variant.$2, pivotX: pivotX, pivotY: pivotY);
      final String stem = '${output.path}/$name.${variant.$1}';
      await File('$stem.ps').writeAsBytes(changed.records.program.bytes);
      report.add({
        'file': name,
        'variant': variant.$1,
        'factor': variant.$2,
        'pivot': [pivotX, pivotY],
        'bounds': [bounds.left, bounds.bottom, bounds.right, bounds.top],
        'shapes': drawing.liveShapes.length,
        'paths': drawing.paths.length,
      });
      stdout.writeln('$name ${variant.$1}: ${drawing.liveShapes.length} live shapes');
    }
  }
  await File('${output.path}/report.json').writeAsString(const JsonEncoder.withIndent('  ').convert(report));
}
