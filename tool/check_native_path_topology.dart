import 'dart:convert';
import 'dart:io';

import 'package:aikit/aikit.dart';

import '../test/ai_native_artboards_test.dart' show mixedArtboardSource;
import '../test/ai_native_group_creation_test.dart' show groupCreationDrawing;
import '../test/ai_native_objects_test.dart' show objectSource;
import '../test/ai_native_path_topology_test.dart' show topologyBounds, topologyGeometry, topologyRectangle, topologySource;

/// Locates source commands independently of whether their paths are editable.
List<Map<String, Object?>> pathTopologyInventory(AiNativeDrawing drawing) {
  int previous = drawing.records.program.bodyStart;
  return [
    for (final AiNativePath path in drawing.paths)
      () {
        final AiNativeInstruction? count = drawing.items.whereType<AiNativeInstruction>().where((item) => item.start >= previous && item.end <= path.start && item.operator == 'As').singleOrNull;
        previous = path.end;
        return {
          'geometry': [
            for (final AiNativeInstruction item in path.geometry) [item.start, item.end],
          ],
          'controls': [
            for (final AiNativeItem item in drawing.items.where((item) => item.start >= path.geometry.last.end && item.end <= path.paint.start)) [item.start, item.end],
          ],
          'paint': [path.paint.start, path.paint.end],
          'count': count == null ? null : [count.start, count.end],
          'countOperand': count == null ? null : [count.operands.single.start, count.operands.single.end],
        };
      }(),
  ];
}

/// Emits prescribed independent geometry/mask transactions and producer refusals.
Future<void> main() async {
  final Directory output = await Directory('test/corpus/output/path-topology').create(recursive: true);
  final List<Map<String, Object?>> rows = [];
  final Map<String, String> synthetic = {
    'synthetic-nested': topologySource(),
    'synthetic-open-mask': objectSource('q u 3 As 0 0 m 20 0 L 20 20 L N U 4 As $topologyRectangle f Q'),
    'synthetic-cc-pairs': mixedArtboardSource().replaceFirst('%%Trailer', '*u 4 As $topologyRectangle f 4 As $topologyRectangle f *U\n%%Trailer'),
  };
  for (final MapEntry<String, String> source in synthetic.entries) {
    final AiNativeDrawing before = groupCreationDrawing(source.value);
    final Map<String, AiNativeDrawing> snapshots = {'original': before};
    final bool nested = source.key == 'synthetic-nested';
    final bool pairs = source.key == 'synthetic-cc-pairs';
    final int selected = pairs ? before.paths.length - 2 : 0;
    final Map<String, ({String predecessor, List<int> geometry, List<int> masks, AiNativePathMask? mask})> requests = {
      'geometry': (predecessor: 'original', geometry: [selected], masks: [], mask: null),
      if (nested || pairs) 'inner': (predecessor: 'original', geometry: [selected + 1], masks: [], mask: null),
      if (!pairs) ...{
        'closed': (predecessor: 'original', geometry: [], masks: nested ? [0, 1] : [0], mask: .closed),
        'open': (predecessor: 'closed', geometry: [], masks: nested ? [0, 1] : [0], mask: .open),
        'clear': (predecessor: 'open', geometry: [], masks: nested ? [0, 1] : [0], mask: .none),
      },
      if (nested) 'combined': (predecessor: 'original', geometry: [0], masks: [0, 1], mask: .closed),
    };
    for (final MapEntry<String, ({String predecessor, List<int> geometry, List<int> masks, AiNativePathMask? mask})> request in requests.entries) {
      final AiNativeDrawing original = snapshots[request.value.predecessor]!;
      final Set<int> selected = {...request.value.geometry, ...request.value.masks};
      final AiNativeDrawing result = original.editPaths(
        edits: [
          for (final int index in selected)
            AiNativePathEdit(
              path: original.paths[index],
              segments: request.value.geometry.contains(index) ? topologyGeometry() : null,
              mask: request.value.masks.contains(index) ? request.value.mask : null,
            ),
        ],
        bounds: topologyBounds,
      );
      snapshots[request.key] = result;
      final String input = '${source.key}.${request.value.predecessor}.ps';
      final String target = '${source.key}.${request.key}.ps';
      await File('${output.path}/$input').writeAsBytes(original.records.program.bytes);
      await File('${output.path}/$target').writeAsBytes(result.records.program.bytes);
      rows.add({
        'source': source.key,
        'variant': request.key,
        'original': input,
        'result': target,
        'before': pathTopologyInventory(original),
        'after': pathTopologyInventory(result),
        'rejected': false,
      });
      stdout.writeln('${source.key}/${request.key} passed');
    }
  }
  for (final String name in ['simple_shapes_cc.ai', 'inkscape_minimized_ai_cc.ai', 'inkscape_minimized_ai_cc_current.ai']) {
    final AiNativeSource source = AiNativeData.extract(const AiCodec().decode(await File('test/corpus/files/$name').readAsBytes())).single;
    final AiNativeDrawing drawing = AiNativeDrawing.decode(
      records: AiNativeRecords.decode(program: AiProgram.decode(bytes: source.bytes)),
    );
    final AiNativePath path = drawing.groups.firstWhere((group) => group.compound).paths.first;
    String? issue;
    try {
      drawing.editPaths(
        edits: [AiNativePathEdit(path: path, segments: topologyGeometry())],
        bounds: topologyBounds,
      );
    } on UnsupportedError catch (error) {
      issue = error.message;
    }
    if (issue == null) {
      throw StateError('Unexpected qualification of $name.');
    }
    final String original = '$name.original.ps';
    await File('${output.path}/$original').writeAsBytes(drawing.records.program.bytes);
    rows.add({'source': name, 'variant': 'rejected', 'original': original, 'result': original, 'rejected': true, 'issue': issue});
    stdout.writeln('$name/rejected passed');
  }
  await File('${output.path}/report.json').writeAsString('${const JsonEncoder.withIndent('  ').convert(rows)}\n');
}
