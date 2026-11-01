import 'dart:convert';
import 'dart:io';

import 'package:aikit/aikit.dart';

import '../test/ai_native_contour_branch_movement_test.dart' show contourBranchSource, contourBranchTreeSource, moveContourBranch;
import '../test/ai_native_group_creation_test.dart' show groupCreationDrawing;
import '../test/ai_native_path_topology_test.dart' show topologyBounds;
import 'check_native_contour_group_movement.dart' show contourGroupInventory;

/// Emits branch movements with explicit predecessors and untouched producer setup.
Future<void> main() async {
  final Directory output = await Directory('test/corpus/output/contour-branch-movement').create(recursive: true);
  final List<Map<String, Object?>> rows = [];
  for (final String name in ['ordinary', 'mask', 'mask-tree', 'inkscape_minimized_ai_cc.ai', 'inkscape_minimized_ai_cc_current.ai']) {
    final bool producer = name.endsWith('.ai');
    final AiNativeDrawing original = producer
        ? AiNativeDrawing.decode(
            records: AiNativeRecords.decode(program: AiProgram.decode(bytes: AiNativeData.extract(const AiCodec().decode(await File('test/corpus/files/$name').readAsBytes())).single.bytes)),
          )
        : groupCreationDrawing(name == 'mask-tree' ? contourBranchTreeSource() : contourBranchSource(mask: name == 'mask'));
    await File('${output.path}/$name.original.ps').writeAsBytes(original.records.program.bytes);
    AiNativeDrawing prepared = original;
    if (producer) {
      final AiNativePathTopology topology = original.pathTopology(path: original.paths.first);
      final int start = topology.pointCount?.start ?? topology.path.start;
      final int end = AiNativeObjects.decode(drawing: original).forSource(topology.path).end;
      prepared = AiNativeDrawing.decode(
        records: AiNativeRecords.decode(
          program: AiNativeEditor.apply(
            program: original.records.program,
            edits: [
              AiSourceEdit(start: start, end: start, bytes: latin1.encode('\nu\n')),
              AiSourceEdit(start: end, end: end, bytes: latin1.encode('\nU\n')),
            ],
          ),
        ),
      );
      await File('${output.path}/$name.prepared.ps').writeAsBytes(prepared.records.program.bytes);
      await File('${output.path}/$name.preparation.json').writeAsString(jsonEncode({'before': contourGroupInventory(original), 'after': contourGroupInventory(prepared), 'start': start, 'end': end}));
    }
    final Map<String, AiNativeDrawing> snapshots = {producer ? 'prepared' : 'original': prepared};
    for (final String variant in [
      'extract',
      if (!producer && name != 'mask-tree') ...['reorder', 'adopt'],
      if (name == 'ordinary') ...['nest', 'enter'],
      'restore',
    ]) {
      final String predecessor = variant == 'restore'
          ? 'extract'
          : producer
          ? 'prepared'
          : 'original';
      final AiNativeDrawing before = snapshots[predecessor]!;
      final AiNativeDrawing after;
      if (producer) {
        final AiNativeGroup compound = before.groups.singleWhere((group) => group.compound);
        final AiNativeGroup branch = before.groups.singleWhere((group) => !group.compound && group.paths.length == 1);
        final AiNativeGroup parent = variant == 'extract' ? before.groups.last : compound;
        after = before.moveContourGroups(groups: [branch], parent: parent, bounds: topologyBounds, inheritParentFlags: true, inheritCompoundAppearance: variant == 'restore');
      } else {
        after = moveContourBranch(
          before,
          variant == 'enter'
              ? 'Destination'
              : name == 'mask-tree'
              ? 'Tree'
              : 'Branch',
          switch (variant) {
            'extract' => 'Destination',
            'reorder' || 'restore' => 'Source',
            'nest' => 'Sibling',
            _ => 'Target',
          },
          inheritCompoundAppearance: const {'adopt', 'enter', 'restore'}.contains(variant),
        );
      }
      snapshots[variant] = after;
      await File('${output.path}/$name.$variant.ps').writeAsBytes(after.records.program.bytes);
      rows.add({'source': name, 'variant': variant, 'predecessor': predecessor, 'before': contourGroupInventory(before), 'after': contourGroupInventory(after)});
      stdout.writeln('$name/$variant passed');
    }
  }
  await File('${output.path}/report.json').writeAsString('${const JsonEncoder.withIndent('  ').convert(rows)}\n');
}
