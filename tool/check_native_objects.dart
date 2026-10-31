import 'dart:convert';
import 'dart:io';

import 'package:aikit/aikit.dart';

import '../test/ai_native_objects_test.dart' show objectMetadataSource;
import 'native_object_support.dart';

/// Decodes native data without generating a compatibility representation.
AiNativeDrawing _drawing(List<int> bytes) => AiNativeDrawing.decode(
  records: AiNativeRecords.decode(program: AiProgram.decode(bytes: bytes)),
);

/// Writes complete metadata transactions on pinned artwork and observed schemas.
Future<void> main() async {
  final Directory output = await Directory('test/corpus/output/objects').create(recursive: true);
  final List<Map<String, Object?>> rows = [];

  /// Records an operation with exact source-owned metadata boundaries.
  Future<void> record(
    String source,
    String operation,
    AiNativeDrawing before,
    AiNativeDrawing after,
    List<AiNativeItem> selected, {
    Map<AiNativeItem, List<int>> identifiers = const {},
    AiNativeItem? anchor,
  }) async {
    final String original = '$source.original.ps';
    final String result = '$source.$operation.ps';
    final AiNativeObjects objects = AiNativeObjects.decode(drawing: before);
    await File('${output.path}/$original').writeAsBytes(before.records.program.bytes);
    await File('${output.path}/$result').writeAsBytes(after.records.program.bytes);
    rows.add({
      'source': source,
      'operation': operation,
      'original': original,
      'result': result,
      'selected': selected.map((source) => objects.objects.indexOf(objects.forSource(source))).toList(),
      'anchor': anchor == null ? null : objects.objects.indexOf(objects.forSource(anchor)),
      'identifiers': [
        for (final MapEntry<AiNativeItem, List<int>> entry in identifiers.entries) {'object': objects.objects.indexOf(objects.forSource(entry.key)), 'bytes': entry.value},
      ],
      'before': nativeObjectInventory(before),
      'after': nativeObjectInventory(after),
    });
    stdout.writeln('$result passed');
  }

  final AiNativeDrawing real = _drawing(AiNativeData.extract(const AiCodec().decode(await File('test/corpus/files/layers_and_sublayers.ai').readAsBytes())).single.bytes);
  final List<AiNativeObject> metadata = AiNativeObjects.decode(drawing: real).objects.where((object) => object.dictionary != null && object.bindingIssue == null).toList();
  final List<AiNativePath> paths = metadata.map((object) => object.source).whereType<AiNativePath>().where((path) => !path.isPrivate).toList();
  final AiNativeGroup group = metadata.map((object) => object.source).whereType<AiNativeGroup>().singleWhere((group) => !group.opening.isPrivate);
  if (paths.length != 2) {
    throw StateError('The pinned source no longer has its expected ordinary metadata.');
  }
  final Map<String, AiNativeDrawing Function()> rejected = {
    'duplicate-path': () => real.duplicatePaths(paths: [paths.first]),
    'remove-path': () => real.removePaths(paths: [paths.first]),
    'reorder-paths': () => real.reorderPaths(paths: paths.reversed.toList()),
    'duplicate-group': () => real.duplicateGroups(groups: [group]),
    'remove-group': () => real.removeGroups(groups: [group]),
    'ungroup': () => real.ungroup(groups: [group]),
  };
  for (final MapEntry<String, AiNativeDrawing Function()> entry in rejected.entries) {
    try {
      entry.value();
      throw StateError('The pinned XW group unexpectedly became editable.');
    } on UnsupportedError {
      await record('layers_and_sublayers.ai', 'reject-${entry.key}', real, real, [group, ...paths]);
    }
  }

  final AiNativeDrawing synthetic = _drawing(latin1.encode(objectMetadataSource));
  final Map<AiNativeItem, List<int>> pathIds = {synthetic.paths.first: latin1.encode('copied_path')};
  final Map<AiNativeItem, List<int>> groupIds = {
    synthetic.groups.single: latin1.encode('copied_group'),
    synthetic.paths[0]: latin1.encode('copied_a'),
    synthetic.paths[1]: latin1.encode('copied_b'),
  };
  await record('synthetic-identity', 'duplicate-path', synthetic, synthetic.duplicatePaths(paths: [synthetic.paths.first], identifiers: pathIds), [synthetic.paths.first], identifiers: pathIds);
  await record(
    'synthetic-identity',
    'duplicate-group',
    synthetic,
    synthetic.duplicateGroups(groups: synthetic.groups, identifiers: groupIds),
    synthetic.groups,
    identifiers: groupIds,
  );
  await record('synthetic-identity', 'remove-path', synthetic, synthetic.removePaths(paths: [synthetic.paths.last]), [synthetic.paths.last]);
  await record('synthetic-identity', 'reorder-paths', synthetic, synthetic.reorderPaths(paths: [synthetic.paths[1], synthetic.paths[0]]), [synthetic.paths[1], synthetic.paths[0]]);
  await record('synthetic-identity', 'move-path', synthetic, synthetic.movePathAfter(path: synthetic.paths.first, after: synthetic.paths.last, inheritParentFlags: true), [
    synthetic.paths.first,
  ], anchor: synthetic.paths.last);
  await File('${output.path}/report.json').writeAsString('${const JsonEncoder.withIndent('  ').convert(rows)}\n');
}
