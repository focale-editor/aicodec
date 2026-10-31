import 'dart:convert';
import 'dart:io';

import 'package:aikit/aikit.dart';

/// Isolates selected real CC appearances before exercising global gradient APIs.
Future<void> main() async {
  final Directory output = await Directory('test/corpus/output/gradient-isolation').create(recursive: true);
  final List<Map<String, Object?>> report = [];
  for (final String name in ['gradient_linear.ai', 'gradient_radial.ai']) {
    final AiDocument document = const AiCodec().decode(await File('test/corpus/files/$name').readAsBytes());
    final AiNativeSource source = AiNativeData.extract(document).single;
    final AiProgram program = AiProgram.decode(bytes: source.bytes);
    final AiNativeDrawing drawing = AiNativeDrawing.decode(records: AiNativeRecords.decode(program: program));
    final List<int> sourceName = drawing.gradients.first.geometry.nameBytes;
    final List<AiLiveShape> eligible = drawing.liveShapes
        .where(
          (shape) => drawing.gradients.any(
            (gradient) => latin1.decode(gradient.geometry.nameBytes) == latin1.decode(sourceName) && gradient.paths.isNotEmpty && gradient.paths.every(shape.appearancePaths.contains),
          ),
        )
        .toList();
    final List<AiLiveShape> selection = {eligible.first, eligible[eligible.length ~/ 2], eligible.last}.toList();
    final List<int> selected = selection.map(drawing.liveShapes.indexOf).toList();
    final AiNativeDrawing isolated = drawing.isolateLiveShapeGradient(shapes: selection, sourceNameBytes: sourceName, nameBytes: latin1.encode('AiKit Selected Gradient'));
    final AiBoundingBox bounds = AiBoundingBox.parse(value: RegExp(r'%AI3_Cropmarks:\s*([^\r\n]+)').firstMatch(latin1.decode(program.bytes))![1]!);
    await File('${output.path}/$name.original.ps').writeAsBytes(program.bytes);
    await File('${output.path}/$name.original.pdf').writeAsBytes(const AiCodec().encode(document));
    await File('${output.path}/$name.isolated.ps').writeAsBytes(isolated.records.program.bytes);
    final bool radial = name == 'gradient_radial.ai';
    for (final String variant in ['isolated', 'colors', if (radial) 'focus']) {
      AiNativeGradientResources resources = AiNativeGradientResources.decode(records: isolated.records);
      final AiNativeGradientDefinition definition = resources.definitions.firstWhere((definition) => latin1.decode(definition.nameBytes) == 'AiKit Selected Gradient');
      if (variant == 'colors') {
        resources = resources.replaceStops(
          definition: definition,
          stops: [
            AiNativeGradientStop(
              color: AiNativeGradientColor(kind: .gray, components: [0.2]),
              position: 0,
            ),
            AiNativeGradientStop(
              color: AiNativeGradientColor(kind: .gray, components: [0.8]),
              position: 100,
            ),
          ],
          ramps: [
            AiNativeGradientRamp(
              kind: .gray,
              channels: [AiNativeGradientChannel.samples(values: List.generate(256, (index) => (51 + 153 * index / 255).round()))],
            ),
          ],
        );
      } else if (variant == 'focus') {
        resources = resources.setRadialFocus(definition: definition, angle: 37, length: 0.375);
      }
      final String stem = '${output.path}/$name.$variant';
      final AiPdfDocument saved = AiNativePdf.save(source: source, program: resources.records.program, pageBounds: [bounds]);
      await File('$stem.ps').writeAsBytes(resources.records.program.bytes);
      await File('$stem.ai').writeAsBytes(const AiCodec().encode(saved));
      await File('$stem.pdf').writeAsBytes(const PdfEncoder().convert(saved.pdf));
      report.add({
        'file': name,
        'variant': variant,
        'sourceName': latin1.decode(sourceName),
        'name': 'AiKit Selected Gradient',
        'selected': selected,
        'shapes': drawing.liveShapes.length,
        'paths': drawing.paths.length,
        'bounds': [bounds.left, bounds.bottom, bounds.right, bounds.top],
      });
      stdout.writeln('$name $variant: selected $selected of ${drawing.liveShapes.length}');
    }
  }
  await File('${output.path}/report.json').writeAsString(const JsonEncoder.withIndent('  ').convert(report));
}
