import 'dart:convert';
import 'dart:io';

import 'package:aicodec/aicodec.dart';

import '../test/ai_native_path_group_movement_test.dart' show countedPathGroupSource, mixedPathGroupSource, pathGroupParent, pathGroupPath, pathGroupSource;
import 'check_native_shape_lifecycle.dart' show shapeLifecycleInventory;
import 'native_layer_support.dart' show nativeLayerInventory;

/// Opens immutable native owners without producing compatibility artwork.
AiNativeDrawing _drawing(List<int> bytes) => AiNativeDrawing.decode(
  records: AiNativeRecords.decode(program: AiProgram.decode(bytes: bytes)),
);

/// Retains exact independent pair and layer boundaries.
Map<String, Object?> _inventory(AiNativeDrawing drawing) => {
  'pairs': shapeLifecycleInventory(drawing).where((shape) => shape['printing'] != null).toList(),
  'layers': nativeLayerInventory(AiNativeLayers.decode(drawing: drawing)),
};

/// Emits fixed path moves into empty and populated source-owned groups.
Future<void> main() async {
  final Directory output = await Directory('test/corpus/output/path-group-movement').create(recursive: true);
  final List<Map<String, Object?>> rows = [];

  /// Saves source selections and exact recipes independently of changed output.
  Future<void> record(
    String name,
    String variant,
    AiNativeDrawing source,
    AiNativePath path,
    AiNativeGroup parent,
    String parentName, {
    bool inherit = false,
    bool reject = false,
    Map<String, Object?>? recipe,
  }) async {
    final AiNativeObjects objects = AiNativeObjects.decode(drawing: source);
    final AiNativeObject object = objects.forSource(path);
    final AiNativeObject anchor = objects.forSource(parent);
    final int previousEnd = source.paths.where((candidate) => candidate.end <= path.start).lastOrNull?.end ?? source.records.program.bodyStart;
    final AiNativeInstruction? count = source.items.whereType<AiNativeInstruction>().where((item) => previousEnd <= item.start && item.end <= path.start && item.operator == 'As').lastOrNull;
    final int start = count?.start ?? object.start;
    AiNativeDrawing result = source;
    String? issue;
    try {
      result = source.movePathToGroup(path: path, group: parent, inheritParentFlags: inherit);
    } on UnsupportedError catch (error) {
      if (!reject) {
        rethrow;
      }
      issue = error.message;
    }
    if (reject != (issue != null)) {
      throw StateError('Unexpected path movement qualification for $name/$variant.');
    }
    final String original = '$name.$variant.original.ps';
    final String target = '$name.$variant.ps';
    await File('${output.path}/$original').writeAsBytes(source.records.program.bytes);
    await File('${output.path}/$target').writeAsBytes(result.records.program.bytes);
    rows.add({
      'source': name,
      'variant': variant,
      'operation': 'path',
      'selected': source.paths.indexOf(path),
      'anchor': parentName,
      'span': [start, object.end],
      'geometry': [path.start, path.end],
      'anchorSpan': [anchor.start, anchor.end],
      'position': parent.closing.start,
      'inheritParentFlags': inherit,
      'rejected': reject,
      'issue': issue,
      'recipe': recipe,
      'original': original,
      'result': target,
      'before': _inventory(source),
      'after': _inventory(result),
    });
    stdout.writeln('$target passed');
  }

  for (final String name in ['simple_shapes.ai', 'simple_shapes_cc.ai', 'circle.ai']) {
    final AiNativeDrawing base = _drawing(AiNativeData.extract(const AiCodec().decode(await File('test/corpus/files/$name').readAsBytes())).single.bytes);
    final AiNativeLayer layer = AiNativeLayers.decode(drawing: base).layers.last;
    for (final bool backward in [false, true]) {
      final int position = backward ? layer.bodyStart : layer.source.end.start;
      const String insertion = '\nu U\n';
      final AiProgram program = AiNativeEditor.apply(
        program: base.records.program,
        edits: [AiSourceEdit(start: position, end: position, bytes: latin1.encode(insertion))],
      );
      final AiNativeDrawing source = _drawing(program.bytes);
      await record(
        name,
        backward ? 'backward' : 'forward',
        source,
        source.paths[name == 'circle.ai' ? 0 : 18],
        source.groups.singleWhere((group) => group.paths.isEmpty),
        'empty-group',
        inherit: true,
        reject: backward && name != 'circle.ai',
        recipe: {'position': position, 'insertion': insertion},
      );
    }
  }
  final AiNativeDrawing ordinary = _drawing(latin1.encode(pathGroupSource()));
  for (final String parent in ['destination', 'empty', 'source']) {
    await record('synthetic-ordinary', parent, ordinary, pathGroupPath(ordinary, 10), pathGroupParent(ordinary, parent), parent);
  }
  await record('synthetic-ordinary', 'backward', ordinary, pathGroupPath(ordinary, 20), pathGroupParent(ordinary, 'source'), 'source');
  final AiNativeDrawing counted = _drawing(latin1.encode(countedPathGroupSource()));
  await record('synthetic-counted', 'empty', counted, pathGroupPath(counted, 10), pathGroupParent(counted, 'empty'), 'empty');
  final AiNativeDrawing layered = _drawing(latin1.encode(pathGroupSource(layers: true)));
  for (final bool inherit in [false, true]) {
    await record('synthetic-layers', inherit ? 'cross' : 'reject-parent', layered, pathGroupPath(layered, 10), pathGroupParent(layered, 'empty'), 'empty', inherit: inherit, reject: !inherit);
  }
  final AiNativeDrawing mixed = _drawing(latin1.encode(mixedPathGroupSource()));
  await record('synthetic-mixed', 'forward', mixed, pathGroupPath(mixed, 70), mixed.groups.singleWhere((group) => group.paths.isEmpty), 'empty-group', inherit: true);
  await record('synthetic-mixed', 'backward', mixed, pathGroupPath(mixed, 72), pathGroupParent(mixed, 'outer_0'), 'outer_0', inherit: true);
  await File('${output.path}/report.json').writeAsString('${const JsonEncoder.withIndent('  ').convert(rows)}\n');
}
