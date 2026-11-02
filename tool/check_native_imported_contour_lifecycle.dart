import 'dart:convert';
import 'dart:io';

import 'package:aicodec/aicodec.dart';

import '../test/ai_native_path_topology_test.dart' show topologyBounds;
import 'check_native_path_topology.dart' show pathTopologyInventory;

/// Exposes complete contour/group ownership for independent source binding.
Map<String, Object?> _inventory(AiNativeDrawing drawing) {
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

/// Emits complete producer transactions without replacing setup or body data.
Future<void> main() async {
  final Directory output = await Directory('test/corpus/output/imported-contour-lifecycle').create(recursive: true);
  final List<Map<String, Object?>> rows = [];
  for (final String name in ['inkscape_minimized_ai_cc.ai', 'inkscape_minimized_ai_cc_current.ai']) {
    final AiNativeSource source = AiNativeData.extract(const AiCodec().decode(await File('test/corpus/files/$name').readAsBytes())).single;
    final AiNativeDrawing original = AiNativeDrawing.decode(
      records: AiNativeRecords.decode(program: AiProgram.decode(bytes: source.bytes)),
    );
    final Map<String, AiNativeDrawing> snapshots = {'original': original};
    await File('${output.path}/$name.original.ps').writeAsBytes(source.bytes);
    for (final String variant in ['release', 'recompound', 'clip', 'unclip']) {
      final String predecessor = variant == 'recompound'
          ? 'release'
          : variant == 'unclip'
          ? 'clip'
          : 'original';
      final AiNativeDrawing before = snapshots[predecessor]!;
      final AiNativeDrawing result = switch (variant) {
        'release' => before.releaseCompounds(groups: before.groups.where((group) => group.compound).toList(), bounds: topologyBounds, discardMetadata: true),
        'recompound' => before.compoundArtwork(paths: before.paths, bounds: topologyBounds),
        'clip' => before.clipArtwork(
          groups: before.groups.where((group) => group.compound).toList(),
          masks: [for (final AiNativePath path in before.paths) AiNativePathEdit(path: path, mask: .closed)],
          bounds: topologyBounds,
        ),
        _ => before.releaseClippingGroups(groups: before.groups.where((group) => group.opening.operator == 'q').toList(), bounds: topologyBounds),
      };
      snapshots[variant] = result;
      await File('${output.path}/$name.$variant.ps').writeAsBytes(result.records.program.bytes);
      rows.add({'source': name, 'variant': variant, 'predecessor': predecessor, 'before': _inventory(before), 'after': _inventory(result)});
      stdout.writeln('$name/$variant passed');
    }
  }
  await File('${output.path}/report.json').writeAsString('${const JsonEncoder.withIndent('  ').convert(rows)}\n');
}
