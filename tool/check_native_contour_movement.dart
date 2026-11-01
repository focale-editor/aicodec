import 'dart:convert';
import 'dart:io';

import 'package:aikit/aikit.dart';

import '../test/ai_native_contour_movement_test.dart' show contourMovementPath, contourMovementSource;
import '../test/ai_native_group_creation_test.dart' show groupCreationDrawing;
import '../test/ai_native_objects_test.dart' show objectSource;
import '../test/ai_native_path_topology_test.dart' show topologyBounds;
import 'check_native_path_topology.dart' show pathTopologyInventory;

/// Exposes independently bindable path metadata without interpreting it.
List<Map<String, Object?>> _paths(AiNativeDrawing drawing) {
  final AiNativeObjects objects = AiNativeObjects.decode(drawing: drawing);
  final List<Map<String, Object?>> paths = pathTopologyInventory(drawing).map(Map<String, Object?>.from).toList();
  for (final (int, AiNativePath) entry in drawing.paths.indexed) {
    final AiNativeObject owner = objects.forSource(entry.$2);
    paths[entry.$1].addAll({
      'owner': [owner.start, owner.end],
      'dictionary': owner.dictionary == null ? null : [owner.dictionary!.start, owner.dictionary!.end],
    });
  }
  return paths;
}

/// Binds every retained group to its commands and complete descendant inventory.
List<Map<String, Object?>> _groups(AiNativeDrawing drawing) => [
  for (final AiNativeGroup group in drawing.groups)
    {
      'start': group.start,
      'end': group.end,
      'opening': [group.opening.start, group.opening.end],
      'closing': [group.closing.start, group.closing.end],
      'paths': group.paths.map(drawing.paths.indexOf).toList(),
    },
];

/// Generates complete-source movement transactions without constructing a renderer.
Future<void> main() async {
  final Directory output = await Directory('test/corpus/output/contour-movement').create(recursive: true);
  final Map<String, AiNativeDrawing> sources = {
    'synthetic': groupCreationDrawing(contourMovementSource()),
    'batch': groupCreationDrawing(objectSource('u ${[for (int index = 0; index < 200; index++) contourMovementPath(index)].join()}U\nu U', setup: '')),
  };
  for (final String name in ['inkscape_minimized_ai_cc.ai', 'inkscape_minimized_ai_cc_current.ai']) {
    final AiNativeSource source = AiNativeData.extract(const AiCodec().decode(await File('test/corpus/files/$name').readAsBytes())).single;
    sources[name] = AiNativeDrawing.decode(
      records: AiNativeRecords.decode(program: AiProgram.decode(bytes: source.bytes)),
    );
  }
  final List<Map<String, Object?>> rows = [];
  for (final MapEntry<String, AiNativeDrawing> source in sources.entries) {
    final AiNativeDrawing before = source.value;
    await File('${output.path}/${source.key}.original.ps').writeAsBytes(before.records.program.bytes);
    final Map<String, ({List<int> selected, int group, int? after, AiNativePathMask? mask, bool inherit})> requests = source.key == 'synthetic'
        ? {
            'leave': (selected: [0], group: 3, after: null, mask: null, inherit: false),
            'enter': (selected: [0], group: 2, after: null, mask: null, inherit: true),
            'reorder': (selected: [1, 0], group: 0, after: null, mask: null, inherit: false),
            'anchor': (selected: [6], group: 3, after: 4, mask: null, inherit: false),
            'mask': (selected: [0], group: 4, after: null, mask: .closed, inherit: false),
            'clear': (selected: [5, 0], group: 3, after: null, mask: .none, inherit: false),
          }
        : source.key == 'batch'
        ? {
            'reverse': (selected: [for (int index = 199; index >= 0; index--) index], group: 1, after: null, mask: null, inherit: false),
          }
        : {
            'reorder': (selected: [4, 3, 2, 1, 0], group: 1, after: null, mask: null, inherit: false),
            'leave': (selected: [1], group: 2, after: null, mask: null, inherit: false),
          };
    for (final MapEntry<String, ({List<int> selected, int group, int? after, AiNativePathMask? mask, bool inherit})> request in requests.entries) {
      final AiNativeDrawing result = before.moveContours(
        paths: [for (final int index in request.value.selected) before.paths[index]],
        group: before.groups[request.value.group],
        after: request.value.after == null ? null : before.paths[request.value.after!],
        mask: request.value.mask,
        inheritCompoundAppearance: request.value.inherit,
        inheritParentFlags: true,
        bounds: topologyBounds,
      );
      await File('${output.path}/${source.key}.${request.key}.ps').writeAsBytes(result.records.program.bytes);
      rows.add({'source': source.key, 'variant': request.key, 'before': _paths(before), 'after': _paths(result), 'beforeGroups': _groups(before), 'afterGroups': _groups(result)});
      stdout.writeln('${source.key}/${request.key} passed');
    }
  }
  await File('${output.path}/report.json').writeAsString('${const JsonEncoder.withIndent('  ').convert(rows)}\n');
}
