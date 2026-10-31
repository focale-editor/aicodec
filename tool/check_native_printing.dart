import 'dart:convert';
import 'dart:io';

import 'package:aikit/aikit.dart';

/// Midpoint used only by the host-side fixture to compose equivalent curves.
List<double> _midpoint(List<double> first, List<double> second) => [(first[0] + second[0]) / 2, (first[1] + second[1]) / 2];

/// Supplies mathematically equivalent subdivided paths without a kit compositor.
List<AiPathSegment> _subdivide(List<AiPathSegment> source) {
  final List<AiPathSegment> result = [source.first];
  List<double> current = source.first.coordinates;
  for (final AiPathSegment segment in source.skip(1)) {
    final List<double> values = segment.coordinates;
    final List<double> end = values.sublist(values.length - 2);
    if (segment.operator == 'l' || segment.operator == 'L') {
      result.add(AiPathSegment(operator: 'l', coordinates: _midpoint(current, end)));
      result.add(segment);
    } else {
      final List<double> first = segment.operator == 'v' || segment.operator == 'V' ? current : values.sublist(0, 2);
      final List<double> second = segment.operator == 'y' || segment.operator == 'Y' ? end : values.sublist(values.length - 4, values.length - 2);
      final List<double> firstHalf = _midpoint(current, first);
      final List<double> center = _midpoint(first, second);
      final List<double> lastHalf = _midpoint(second, end);
      final List<double> left = _midpoint(firstHalf, center);
      final List<double> right = _midpoint(center, lastHalf);
      final List<double> split = _midpoint(left, right);
      result.add(AiPathSegment(operator: 'c', coordinates: [...firstHalf, ...left, ...split]));
      result.add(AiPathSegment(operator: segment.operator == segment.operator.toUpperCase() ? 'C' : 'c', coordinates: [...right, ...lastHalf, ...end]));
    }
    current = end;
  }
  return result;
}

/// Refreshes existing CC printing contours while retaining all authoring data.
Future<void> main() async {
  final Directory output = await Directory('test/corpus/output/native-printing').create(recursive: true);
  final List<Map<String, Object?>> rows = [];
  for (final String name in ['simple_shapes.ai', 'simple_shapes_cc.ai', 'opacity.ai', 'gradient_linear.ai', 'gradient_radial.ai']) {
    final AiDocument document = const AiCodec().decode(await File('test/corpus/files/$name').readAsBytes());
    final AiNativeSource source = AiNativeData.extract(document).single;
    final AiNativeDrawing drawing = AiNativeDrawing.decode(
      records: AiNativeRecords.decode(program: AiProgram.decode(bytes: source.bytes)),
    );
    final List<AiLiveShape> shapes = drawing.liveShapes.where((shape) => shape.isBound && shape.appearanceGroup != null && shape.path?.isPrivate == true).toList();
    if (shapes.isEmpty) {
      throw StateError('The required fixture has no separate printing groups: $name.');
    }
    await File('${output.path}/$name.original.ps').writeAsBytes(source.bytes);
    for (final bool all in [false, true]) {
      final List<AiLiveShape> selected = all ? shapes : [shapes.first];
      final List<AiNativePrintingReplacement> replacements = [
        for (final AiLiveShape shape in selected)
          AiNativePrintingReplacement(
            shape: shape,
            paths: [
              for (final AiNativePath path in shape.appearancePaths) AiNativePrintingContours(path: path, contours: [_subdivide(path.segments)]),
            ],
            bounds: source.asPostScript().boundingBox!,
          ),
      ];
      final AiNativeDrawing changed = drawing.withPrintingContours(replacements: replacements);
      final String variant = all ? 'all' : 'first';
      await File('${output.path}/$name.$variant.ps').writeAsBytes(changed.records.program.bytes);
      rows.add({
        'file': name,
        'variant': variant,
        'shapes': selected.length,
        'paths': drawing.paths.length,
        'selectedPaths': [for (final AiLiveShape shape in selected) ...shape.appearancePaths.map(drawing.paths.indexOf)],
        'groups': [
          for (final AiLiveShape shape in selected)
            {
              'before': [shape.appearanceGroup!.start, shape.appearanceGroup!.end],
              'after': [changed.liveShapes[drawing.liveShapes.indexOf(shape)].appearanceGroup!.start, changed.liveShapes[drawing.liveShapes.indexOf(shape)].appearanceGroup!.end],
            },
        ],
      });
      stdout.writeln('$name/$variant: ${selected.length} host-supplied expansions');
    }
  }
  await File('${output.path}/report.json').writeAsString(const JsonEncoder.withIndent('  ').convert(rows));
}
