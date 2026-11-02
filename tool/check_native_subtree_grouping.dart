import 'dart:convert';
import 'dart:io';

import 'package:aicodec/aicodec.dart';

import '../test/ai_native_shape_reordering_test.dart' show shapeReorderingSource;
import '../test/ai_native_subtree_grouping_test.dart' show subtreeGroupingSource;
import '../test/ai_native_subtree_reordering_test.dart' show subtreeReorderingGroups, subtreeReorderingSource;
import 'native_subtree_support.dart' show wrapNativeSubtrees;

/// Opens an immutable native program without constructing host representations.
AiNativeDrawing _drawing(List<int> bytes) => AiNativeDrawing.decode(
  records: AiNativeRecords.decode(program: AiProgram.decode(bytes: bytes)),
);

/// Declares complete source owners for an independent reader to bind again.
Map<String, Object> _selection(AiNativeDrawing drawing, Object source) {
  if (source is AiLiveShape) {
    return {'kind': 'pair', 'index': drawing.liveShapes.indexOf(source), 'start': AiNativeObjects.decode(drawing: drawing).forSource(source.appearanceGroup!).start, 'end': source.end};
  }
  final AiNativeObject object = AiNativeObjects.decode(drawing: drawing).forSource(source as AiNativeItem);
  final AiNativeInstruction? preceding = drawing.items.whereType<AiNativeInstruction>().where((item) => item.end <= object.start).lastOrNull;
  return {
    'kind': source is AiNativeGroup ? 'group' : 'path',
    'name': object.identifier == null ? '' : latin1.decode(object.identifier!.bytes),
    'start': source is AiNativePath && preceding?.operator == 'As' ? preceding!.start : object.start,
    'end': object.end,
    if (source is AiNativeGroup) 'openingEnd': source.opening.end,
    if (source is AiNativeGroup) 'closingStart': source.closing.start,
  };
}

/// Generates fixed mixed-owner transactions and atomic refusals for verification.
Future<void> main() async {
  final Directory output = await Directory('test/corpus/output/subtree-grouping').create(recursive: true);
  final List<Map<String, Object?>> rows = [];

  /// Saves exact immutable input/output and the requested policy, including refusals.
  Future<AiNativeDrawing> record(
    String name,
    String variant,
    AiNativeDrawing before,
    List<Object> selected, {
    bool dissolve = false,
    bool discardMetadata = false,
    bool inheritParentFlags = true,
    Object? recipe,
  }) async {
    AiNativeDrawing after = before;
    String? issue;
    try {
      after = dissolve
          ? before.ungroup(groups: selected.cast<AiNativeGroup>(), discardMetadata: discardMetadata, inheritParentFlags: inheritParentFlags)
          : before.groupArtwork(
              paths: selected.whereType<AiNativePath>().toList(),
              groups: selected.whereType<AiNativeGroup>().toList(),
              liveShapes: selected.whereType<AiLiveShape>().toList(),
              inheritParentFlags: inheritParentFlags,
            );
    } on UnsupportedError catch (error) {
      issue = error.toString();
    }
    final String original = '$name.$variant.original.ps';
    final String result = '$name.$variant.ps';
    await File('${output.path}/$original').writeAsBytes(before.records.program.bytes);
    await File('${output.path}/$result').writeAsBytes(after.records.program.bytes);
    rows.add({
      'source': name,
      'variant': variant,
      'operation': dissolve ? 'dissolve' : 'group',
      'original': original,
      'result': result,
      'selected': selected.map((source) => _selection(before, source)).toList(),
      'discardMetadata': discardMetadata,
      'inheritParentFlags': inheritParentFlags,
      'recipe': recipe,
      'issue': issue,
    });
    stdout.writeln('$result: ${issue ?? 'saved'}');
    return after;
  }

  for (final String name in ['simple_shapes.ai', 'simple_shapes_cc.ai', 'gradient_linear.ai', 'gradient_radial.ai']) {
    final AiNativeDrawing original = _drawing(AiNativeData.extract(const AiCodec().decode(await File('test/corpus/files/$name').readAsBytes())).single.bytes);
    final AiNativeDrawing grouped = await record(name, 'pairs', original, original.liveShapes.take(2).toList());
    final AiNativeGroup parent = grouped.groups.where((group) => group.paths.contains(grouped.liveShapes.first.path) && group.paths.contains(grouped.liveShapes[1].path)).single;
    await record(name, 'dissolve', grouped, [parent], dissolve: true);
    final ({AiNativeDrawing drawing, List<Map<String, Object?>> recipe}) wrapped = wrapNativeSubtrees(original, layers: false);
    await record(name, 'subtrees', wrapped.drawing, subtreeReorderingGroups(wrapped.drawing).take(2).toList(), recipe: wrapped.recipe);
  }
  final AiNativeDrawing mixed = _drawing(latin1.encode(subtreeGroupingSource()));
  await record('synthetic', 'mixed', mixed, [
    subtreeReorderingGroups(mixed, prefix: 'parent').single,
    mixed.paths.singleWhere((path) => path.geometry.first.numbers!.first == 70),
    mixed.liveShapes[1],
  ]);
  final AiNativeDrawing identified = _drawing(latin1.encode(subtreeReorderingSource()));
  await record('synthetic', 'identified', identified, subtreeReorderingGroups(identified), dissolve: true, discardMetadata: true, inheritParentFlags: false);
  for (final (String, String) entry in [
    ('flags', shapeReorderingSource().replaceFirst('0 A 0 Xw ', '0 A 0 Xw\n%_1 A\n')),
    ('gap', shapeReorderingSource()),
    ('opaque', subtreeReorderingSource().replaceFirst('%%EndSetup', '/Dictionary : /XMLUID : (outer_0) ; (Reference) , ;\n%%EndSetup')),
    ('alias', subtreeReorderingSource().replaceFirst('(outer_1)', '(outer_0)')),
  ]) {
    final AiNativeDrawing source = _drawing(latin1.encode(entry.$2));
    final bool dissolve = const {'opaque', 'alias'}.contains(entry.$1);
    await record(
      'synthetic',
      entry.$1,
      source,
      dissolve
          ? [subtreeReorderingGroups(source).first]
          : entry.$1 == 'gap'
          ? [source.liveShapes.first, source.liveShapes.last]
          : source.liveShapes.take(2).toList(),
      dissolve: dissolve,
      discardMetadata: dissolve,
      inheritParentFlags: entry.$1 != 'flags',
    );
  }
  await File('${output.path}/report.json').writeAsString('${const JsonEncoder.withIndent('  ').convert(rows)}\n');
}
