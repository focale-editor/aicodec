import 'dart:convert';
import 'dart:io';

import 'package:aicodec/aicodec.dart';

import '../test/ai_native_artboards_test.dart' show mixedArtboardSource;
import '../test/ai_native_clipping_lifecycle_test.dart' show clippingLifecycleSource, createClippingFixture;
import '../test/ai_native_group_creation_test.dart' show groupCreationDrawing;
import '../test/ai_native_objects_test.dart' show objectDictionary, objectSource;
import '../test/ai_native_path_topology_test.dart' show topologyBounds, topologyRectangle;
import 'check_native_path_topology.dart' show pathTopologyInventory;

/// Records independently bindable group boundaries and direct owned attachments.
List<Map<String, Object?>> _groups(AiNativeDrawing drawing) {
  final AiNativeObjects objects = AiNativeObjects.decode(drawing: drawing);
  return [
    for (final AiNativeGroup group in drawing.groups)
      {
        'start': group.start,
        'end': group.end,
        'opening': [group.opening.start, group.opening.end],
        'closing': [group.closing.start, group.closing.end],
        'owner': [objects.forSource(group).start, objects.forSource(group).end],
        'paths': group.paths.map(drawing.paths.indexOf).toList(),
      },
  ];
}

/// Emits prescribed clipping and compound-state transactions without rendering.
Future<void> main() async {
  final Directory output = await Directory('test/corpus/output/clipping-lifecycle').create(recursive: true);
  final Map<String, String> sources = {
    'state': clippingLifecycleSource(),
    'nested': objectSource('q 4 As $topologyRectangle h W n q 4 As $topologyRectangle H W f 8 w 4 As $topologyRectangle f Q 5 w 4 As $topologyRectangle f Q 4 As $topologyRectangle f'),
    'compound': objectSource('*u u 4 As $topologyRectangle f U\n${objectDictionary(identifier: 'Leaf')}\n4 As $topologyRectangle f *U'),
    'compound-state': objectSource('%_4 w\nq u q 7 w\n%_9 w\n4 As $topologyRectangle h W n Q q 11 w\n%_13 w\n4 As $topologyRectangle h W n Q U 4 As $topologyRectangle f Q 4 As $topologyRectangle f'),
    'metadata': objectSource(
      '1 Ae q 4 As $topologyRectangle h W n\n${objectDictionary(identifier: 'Child')}\n7 w Q\n${objectDictionary(identifier: 'Parent')}\n9 () XW\n4 As $topologyRectangle f',
      setup: '',
    ),
    'cc-pairs': mixedArtboardSource().replaceFirst('%%Trailer', '0 A 0 Xw 4 As $topologyRectangle f 4 As $topologyRectangle f\n%%Trailer'),
    'batch': objectSource(List.filled(200, 'q 7 w 4 As $topologyRectangle h W n Q').join('\n')),
  };
  final List<Map<String, Object?>> rows = [];
  for (final MapEntry<String, String> source in sources.entries) {
    final AiNativeDrawing original = groupCreationDrawing(source.value);
    final Map<String, AiNativeDrawing> snapshots = {'original': original};
    if (source.key == 'state') {
      snapshots['create'] = createClippingFixture(original);
    } else if (source.key == 'compound') {
      snapshots['create'] = original.clipArtwork(
        groups: [original.groups.last],
        masks: [for (final AiNativePath path in original.paths) AiNativePathEdit(path: path, mask: .closed)],
        bounds: topologyBounds,
      );
    } else if (source.key == 'cc-pairs') {
      snapshots['create'] = original.clipArtwork(
        paths: original.paths.skip(original.paths.length - 2).toList(),
        masks: [AiNativePathEdit(path: original.paths[original.paths.length - 2], mask: .open)],
        bounds: topologyBounds,
      );
    } else if (source.key == 'compound-state') {
      snapshots['create'] = original.compoundArtwork(groups: [original.groups.firstWhere((group) => group.opening.operator == 'u')], bounds: topologyBounds);
    }
    final AiNativeDrawing previous = snapshots['create'] ?? original;
    snapshots['release'] = source.key == 'compound-state'
        ? previous.releaseCompounds(groups: previous.groups.where((group) => group.compound).toList(), bounds: topologyBounds)
        : previous.releaseClippingGroups(
            groups: source.key == 'batch' ? previous.groups : [previous.groups.last],
            bounds: topologyBounds,
            discardMetadata: true,
          );
    for (final MapEntry<String, AiNativeDrawing> snapshot in snapshots.entries) {
      await File('${output.path}/${source.key}.${snapshot.key}.ps').writeAsBytes(snapshot.value.records.program.bytes);
      if (snapshot.key == 'original') {
        continue;
      }
      final String predecessor = snapshot.key == 'release' && snapshots.containsKey('create') ? 'create' : 'original';
      final AiNativeDrawing before = snapshots[predecessor]!;
      rows.add({
        'source': source.key,
        'variant': snapshot.key,
        'predecessor': predecessor,
        'before': pathTopologyInventory(before),
        'after': pathTopologyInventory(snapshot.value),
        'beforeGroups': _groups(before),
        'afterGroups': _groups(snapshot.value),
      });
      stdout.writeln('${source.key}/${snapshot.key} passed');
    }
  }
  await File('${output.path}/report.json').writeAsString('${const JsonEncoder.withIndent('  ').convert(rows)}\n');
}
