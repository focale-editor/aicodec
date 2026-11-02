import 'dart:convert';
import 'dart:io';

import 'package:aicodec/aicodec.dart';

import '../test/ai_native_artboards_test.dart' show mixedArtboardSource;
import '../test/ai_native_compound_lifecycle_test.dart' show compoundLifecycleSource;
import '../test/ai_native_group_creation_test.dart' show groupCreationDrawing;
import '../test/ai_native_objects_test.dart' show objectDictionary, objectSource;
import '../test/ai_native_path_topology_test.dart' show topologyBounds, topologyRectangle;

/// Emits complete compound transactions for independent grammar and byte checks.
Future<void> main() async {
  final Directory output = await Directory('test/corpus/output/compound-lifecycle').create(recursive: true);
  final Map<String, String> sources = {
    'nested': compoundLifecycleSource(),
    'mask': objectSource('q 4 As $topologyRectangle h W n 4 As $topologyRectangle h W n Q'),
    'mask-tree': objectSource('q u q 4 As $topologyRectangle h W n Q q 4 As $topologyRectangle h W n Q U Q'),
    'cc-pairs': mixedArtboardSource().replaceFirst('%%Trailer', '0 A 0 Xw 4 As $topologyRectangle f 4 As $topologyRectangle f\n%%Trailer'),
    'metadata': objectSource('''1 Ae *u
4 As $topologyRectangle f
${objectDictionary(identifier: 'Child')}
*U
${objectDictionary(identifier: 'Parent', name: 'Compound')}
9 () XW
4 As $topologyRectangle f
''', setup: ''),
    'batch': objectSource(List.filled(200, '*u 4 As $topologyRectangle f 4 As $topologyRectangle f *U').join('\n')),
  };
  final List<Map<String, Object?>> rows = [];
  for (final MapEntry<String, String> source in sources.entries) {
    final AiNativeDrawing drawing = groupCreationDrawing(source.value);
    await File('${output.path}/${source.key}.original.ps').writeAsBytes(drawing.records.program.bytes);
    AiNativeDrawing compounded = drawing;
    if (source.key != 'metadata' && source.key != 'batch') {
      compounded = drawing.compoundArtwork(
        paths: switch (source.key) {
          'nested' => [drawing.paths.first],
          'mask' => drawing.paths,
          'cc-pairs' => drawing.paths.skip(drawing.paths.length - 2).toList(),
          _ => [],
        },
        groups: const {'nested', 'mask-tree'}.contains(source.key) ? [drawing.groups.lastWhere((group) => group.opening.operator == 'u')] : [],
        bounds: topologyBounds,
        inheritParentFlags: true,
      );
      await File('${output.path}/${source.key}.compound.ps').writeAsBytes(compounded.records.program.bytes);
      rows.add({'source': source.key, 'variant': 'compound', 'predecessor': 'original'});
    }
    final AiNativeDrawing released = compounded.releaseCompounds(
      groups: source.key == 'cc-pairs' ? [compounded.groups.last] : compounded.groups.where((group) => group.compound).toList(),
      bounds: topologyBounds,
      discardMetadata: true,
      inheritParentFlags: true,
    );
    await File('${output.path}/${source.key}.release.ps').writeAsBytes(released.records.program.bytes);
    rows.add({'source': source.key, 'variant': 'release', 'predecessor': identical(compounded, drawing) ? 'original' : 'compound'});
    stdout.writeln('${source.key} passed');
  }
  await File('${output.path}/report.json').writeAsString('${const JsonEncoder.withIndent('  ').convert(rows)}\n');
}
