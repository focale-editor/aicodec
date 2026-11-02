import 'dart:convert';
import 'dart:io';

import 'package:aicodec/aicodec.dart';

import 'check_native_printing.dart' show nativePrintingFixtures, subdividePrintingPath;

/// Supplies equivalent groups with new nesting and a zero-area unstroked path.
Future<void> main() async {
  final Directory output = await Directory('test/corpus/output/native-printing-groups').create(recursive: true);
  final List<Map<String, Object?>> rows = [];
  for (final String name in nativePrintingFixtures) {
    final AiNativeSource source = AiNativeData.extract(const AiCodec().decode(await File('test/corpus/files/$name').readAsBytes())).single;
    final AiNativeDrawing drawing = AiNativeDrawing.decode(
      records: AiNativeRecords.decode(program: AiProgram.decode(bytes: source.bytes)),
    );
    final List<AiLiveShape> shapes = drawing.liveShapes.where((shape) => shape.isBound && shape.appearanceGroup != null && shape.path?.isPrivate == true).toList();
    if (shapes.isEmpty) {
      throw StateError('No separate groups in required fixture $name.');
    }
    await File('${output.path}/$name.original.ps').writeAsBytes(source.bytes);
    for (final bool all in [false, true]) {
      final List<AiLiveShape> selected = all ? shapes : [shapes.first];
      final String variant = all ? 'all' : 'first';
      final AiNativeDrawing prepared = drawing.withPrintingContours(
        replacements: [
          for (final AiLiveShape shape in selected)
            AiNativePrintingReplacement(
              shape: shape,
              paths: [
                for (final AiNativePath path in shape.appearancePaths) AiNativePrintingContours(path: path, contours: [subdividePrintingPath(path.segments)]),
              ],
              bounds: source.asPostScript().boundingBox!,
            ),
        ],
      );
      final List<AiNativePrintingGroupReplacement> replacements = [];
      final List<String> payloads = [];
      for (final AiLiveShape shape in selected) {
        final int index = drawing.liveShapes.indexOf(shape);
        final AiNativeGroup group = prepared.liveShapes[index].appearanceGroup!;
        final AiNativePath first = group.paths.first;
        final bool explicitStroke = prepared.items.whereType<AiNativeInstruction>().any(
          (item) => item.start >= group.start && item.end <= first.start && const {'G', 'K', 'XA'}.contains(item.operator),
        );
        if (!const {'f', 'F'}.contains(first.paint.operator) && !explicitStroke) {
          throw StateError('The independent comparison requires retained fill or an explicit stroke in $name.');
        }
        final bool counted = prepared.items.whereType<AiNativeInstruction>().any((item) => item.start >= group.start && item.end <= group.end && item.operator == 'As');
        final List<int> bytes = [
          // The pinned SVG reader clears inherited colors after N. Use the
          // original filled paths' color; stroked fixtures set their own paint.
          ...latin1.encode('u\n${counted ? '1 As\n' : ''}0 0 m F\n'),
          ...prepared.records.program.bytes.sublist(group.start, group.end),
          ...latin1.encode('\nU'),
        ];
        final String payload = '$name.$variant.shape-$index.ps';
        await File('${output.path}/$payload').writeAsBytes(bytes);
        payloads.add(payload);
        replacements.add(AiNativePrintingGroupReplacement(shape: shape, bytes: bytes, bounds: source.asPostScript().boundingBox!));
      }
      final AiNativeDrawing changed = drawing.withPrintingGroups(replacements: replacements);
      await File('${output.path}/$name.$variant.ps').writeAsBytes(changed.records.program.bytes);
      rows.add({
        'file': name,
        'variant': variant,
        'shapes': selected.length,
        'paths': drawing.paths.length,
        'selectedPaths': [for (final AiLiveShape shape in selected) ...shape.appearancePaths.map(drawing.paths.indexOf)],
        'addedPaths': [for (final AiLiveShape shape in selected) changed.paths.indexOf(changed.liveShapes[drawing.liveShapes.indexOf(shape)].appearancePaths.first)],
        'groups': [
          for (final (int, AiLiveShape) entry in selected.indexed)
            {
              'before': [entry.$2.appearanceGroup!.start, entry.$2.appearanceGroup!.end],
              'after': [changed.liveShapes[drawing.liveShapes.indexOf(entry.$2)].appearanceGroup!.start, changed.liveShapes[drawing.liveShapes.indexOf(entry.$2)].appearanceGroup!.end],
              'payload': payloads[entry.$1],
            },
        ],
      });
      stdout.writeln('$name/$variant: ${selected.length} complete host-supplied groups');
    }
  }
  await File('${output.path}/report.json').writeAsString(const JsonEncoder.withIndent('  ').convert(rows));
}
