import 'dart:convert';
import 'dart:io';

import 'package:aicodec/aicodec.dart';

import '../test/ai_native_contour_group_movement_test.dart' show contourGroupMovementSource;
import '../test/ai_native_contour_movement_test.dart' show contourMovementPath;
import '../test/ai_native_group_creation_test.dart' show groupCreationDrawing;
import '../test/ai_native_objects_test.dart' show objectSource;
import '../test/ai_native_path_topology_test.dart' show topologyBounds;
import 'check_native_path_topology.dart' show pathTopologyInventory;

/// Exposes complete native owners for independent structural and byte binding.
Map<String, Object?> contourGroupInventory(AiNativeDrawing drawing) {
  final AiNativeObjects objects = AiNativeObjects.decode(drawing: drawing);
  return {
    'paths': pathTopologyInventory(drawing),
    'groups': [
      for (final AiNativeGroup group in drawing.groups)
        {
          'start': group.start,
          'end': group.end,
          'owner': [objects.forSource(group).start, objects.forSource(group).end],
          'opening': [group.opening.start, group.opening.end],
          'closing': [group.closing.start, group.closing.end],
          'paths': group.paths.map(drawing.paths.indexOf).toList(),
        },
    ],
  };
}

/// Generates complete-owner edits against original synthetic and CC programs.
Future<void> main() async {
  final Directory output = await Directory('test/corpus/output/contour-group-movement').create(recursive: true);
  final Map<String, AiNativeDrawing> sources = {
    'synthetic': groupCreationDrawing(contourGroupMovementSource()),
    'scope-saved': groupCreationDrawing(objectSource('u U\nq 2 w ${contourMovementPath(20)}Q\nu 8 w ${contourMovementPath(10)}U', setup: '').replaceFirst('2 w', '')),
    'scope-enclosing': groupCreationDrawing(objectSource('q u U Q\n${contourMovementPath(20)}u 8 w ${contourMovementPath(10)}U', setup: '').replaceFirst('2 w', '')),
  };
  for (final String name in ['inkscape_minimized_ai_cc.ai', 'inkscape_minimized_ai_cc_current.ai']) {
    final AiNativeSource source = AiNativeData.extract(const AiCodec().decode(await File('test/corpus/files/$name').readAsBytes())).single;
    sources[name] = AiNativeDrawing.decode(
      records: AiNativeRecords.decode(program: AiProgram.decode(bytes: source.bytes)),
    );
  }
  final List<Map<String, Object?>> rows = [];
  for (final MapEntry<String, AiNativeDrawing> entry in sources.entries) {
    final AiNativeDrawing before = entry.value;
    await File('${output.path}/${entry.key}.original.ps').writeAsBytes(before.records.program.bytes);
    final Map<String, ({List<int> groups, int? parent, int? after})> requests = entry.key == 'synthetic'
        ? {
            'compound': (groups: [0], parent: 4, after: null),
            'clip': (groups: [2], parent: 4, after: null),
            'batch': (groups: [4, 2], parent: 5, after: null),
            'anchor': (groups: [0], parent: 2, after: 1),
            'root': (groups: [0], parent: null, after: null),
            'mask-root': (groups: [3], parent: null, after: null),
          }
        : entry.key.startsWith('scope-')
        ? {
            'move': (groups: [2], parent: 0, after: null),
          }
        : {
            'view': (groups: [2], parent: 0, after: null),
          };
    for (final MapEntry<String, ({List<int> groups, int? parent, int? after})> request in requests.entries) {
      final AiNativeDrawing result = before.moveContourGroups(
        groups: request.value.groups.map((index) => before.groups[index]).toList(),
        parent: request.value.parent == null ? null : before.groups[request.value.parent!],
        after: request.value.after == null ? null : before.groups[request.value.after!],
        bounds: topologyBounds,
        inheritParentFlags: true,
      );
      await File('${output.path}/${entry.key}.${request.key}.ps').writeAsBytes(result.records.program.bytes);
      rows.add({'source': entry.key, 'variant': request.key, 'before': contourGroupInventory(before), 'after': contourGroupInventory(result)});
      stdout.writeln('${entry.key}/${request.key} passed');
      if (entry.key.endsWith('.ai')) {
        final AiNativeDrawing restored = result.moveContourGroups(
          groups: [result.groups[1]],
          layer: AiNativeLayers.decode(drawing: result).layers.single.source,
          after: result.groups[2],
          bounds: topologyBounds,
          inheritParentFlags: true,
        );
        await File('${output.path}/${entry.key}.restore.ps').writeAsBytes(restored.records.program.bytes);
        rows.add({'source': entry.key, 'variant': 'restore', 'before': contourGroupInventory(result), 'after': contourGroupInventory(restored)});
        stdout.writeln('${entry.key}/restore passed');
      }
    }
  }
  await File('${output.path}/report.json').writeAsString('${const JsonEncoder.withIndent('  ').convert(rows)}\n');
}
