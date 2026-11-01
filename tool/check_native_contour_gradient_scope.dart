import 'dart:convert';
import 'dart:io';

import 'package:aikit/aikit.dart';

import '../test/ai_native_contour_gradient_scope_test.dart' show contourGradientSource;
import '../test/ai_native_contour_movement_test.dart' show contourMovementContour, contourMovementGroup;
import '../test/ai_native_group_creation_test.dart' show groupCreationDrawing;
import '../test/ai_native_path_topology_test.dart' show topologyBounds, topologyGeometry;
import 'check_native_contour_group_movement.dart' show contourGroupInventory;
import 'check_native_contour_movement.dart' show contourMovementPaths;

/// Keeps a shared gradient bank and its two bounded instances under their own names.
String _shared() {
  final String source = contourGradientSource();
  final int start = source.indexOf('Bb\n');
  final int end = source.indexOf('0 BB') + 4;
  return source.replaceRange(start, end, '${source.substring(start, end)}\n${source.substring(start, end)}').replaceFirst('(P10)', '(path_target)');
}

/// Emits isolated edits and precise original-producer refusals for independent checks.
Future<void> main() async {
  final Directory output = await Directory('test/corpus/output/contour-gradient-scope').create(recursive: true);
  final List<Map<String, Object?>> rows = [];
  final Map<String, String> sources = {
    'legacy': contourGradientSource(),
    'relative': contourGradientSource(relative: true),
    'preceding': contourGradientSource(precedingGeometry: true),
    'shared': _shared(),
    'unknown': contourGradientSource(reset: false),
  };
  for (final String name in ['gradient_linear.ai', 'gradient_radial.ai']) {
    sources[name] = latin1.decode(AiNativeData.extract(const AiCodec().decode(await File('test/corpus/files/$name').readAsBytes())).single.bytes);
  }
  for (final MapEntry<String, String> entry in sources.entries) {
    final AiNativeDrawing before = groupCreationDrawing(entry.value);
    await File('${output.path}/${entry.key}.original.ps').writeAsBytes(before.records.program.bytes);
    for (final String variant in entry.key.endsWith('.ai') ? ['geometry'] : ['geometry', 'move', 'group']) {
      AiNativeDrawing result = before;
      String? error;
      try {
        result = switch (variant) {
          'geometry' => before.editPaths(
            edits: [AiNativePathEdit(path: before.paths.first, segments: topologyGeometry())],
            bounds: topologyBounds,
          ),
          'move' => before.moveContours(paths: [contourMovementContour(before, 10)], group: contourMovementGroup(before, 'Right'), bounds: topologyBounds, inheritParentFlags: true),
          _ => before.moveContourGroups(groups: [contourMovementGroup(before, 'Left')], parent: contourMovementGroup(before, 'Right'), bounds: topologyBounds, inheritParentFlags: true),
        };
      } on UnsupportedError catch (failure) {
        error = failure.message;
      }
      final bool rejected = entry.key.endsWith('.ai') || entry.key == 'unknown' && variant != 'geometry';
      if (rejected != (error != null)) {
        throw StateError('Unexpected contour gradient outcome for ${entry.key}/$variant: $error');
      }
      await File('${output.path}/${entry.key}.$variant.ps').writeAsBytes(result.records.program.bytes);
      rows.add({
        'source': entry.key,
        'variant': variant,
        'error': error,
        'before': {...contourGroupInventory(before), 'paths': contourMovementPaths(before)},
        'after': {...contourGroupInventory(result), 'paths': contourMovementPaths(result)},
      });
      stdout.writeln('${entry.key}/$variant: ${error ?? 'passed'}');
    }
  }
  await File('${output.path}/report.json').writeAsString('${const JsonEncoder.withIndent('  ').convert(rows)}\n');
}
