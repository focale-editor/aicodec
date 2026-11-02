import 'dart:convert';
import 'dart:io';

import 'package:aicodec/aicodec.dart';

import '../test/ai_native_shape_lifecycle_test.dart' show identifiedShapeLifecycleSource;
import '../test/ai_native_shape_movement_test.dart' show shapeMovementSource;
import '../test/ai_native_shape_reordering_test.dart' show shapeReorderingSource;
import 'check_native_shape_lifecycle.dart' show shapeLifecycleInventory;

/// Opens exact native programs without synthesizing host representations.
AiNativeDrawing _drawing(List<int> bytes) => AiNativeDrawing.decode(
  records: AiNativeRecords.decode(program: AiProgram.decode(bytes: bytes)),
);

/// Resolves the ordinary enclosing group by a stable original pair index.
AiNativeGroup _parent(AiNativeDrawing drawing, int index) {
  final AiNativeStructure structure = AiNativeStructure.decode(drawing: drawing);
  return structure.parentOf(structure.nodeFor(drawing.liveShapes[index].appearanceGroup!))!.source as AiNativeGroup;
}

/// Records complete moves, exact source spans and explicit inheritance refusals.
Future<void> main() async {
  final Directory output = await Directory('test/corpus/output/shape-movement').create(recursive: true);
  final List<Map<String, Object?>> rows = [];

  /// Saves fixed requests for independent owner, representation and state checks.
  Future<void> record(String name, String variant, AiNativeDrawing source, int shape, String destination, {bool inheritParentFlags = false, bool reject = false}) async {
    AiNativeDrawing result = source;
    String? issue;
    final int position = switch (destination) {
      'empty-group' => source.groups.singleWhere((group) => group.paths.isEmpty).closing.start,
      'first-group' => _parent(source, 0).closing.start,
      'last-group' => _parent(source, source.liveShapes.length - 1).closing.start,
      'first-layer' => source.records.program.layers.first.end.start,
      'empty-layer' => source.records.program.layers.last.end.start,
      _ => source.liveShapes[int.parse(destination)].end,
    };
    try {
      final AiLiveShape selected = source.liveShapes[shape];
      result = switch (destination) {
        'empty-group' => source.moveLiveShapeToGroup(shape: selected, group: source.groups.singleWhere((group) => group.paths.isEmpty), inheritParentFlags: inheritParentFlags),
        'first-group' => source.moveLiveShapeToGroup(shape: selected, group: _parent(source, 0), inheritParentFlags: inheritParentFlags),
        'last-group' => source.moveLiveShapeToGroup(shape: selected, group: _parent(source, source.liveShapes.length - 1), inheritParentFlags: inheritParentFlags),
        'first-layer' => source.moveLiveShapeToLayer(shape: selected, layer: source.records.program.layers.first, inheritParentFlags: inheritParentFlags),
        'empty-layer' => source.moveLiveShapeToLayer(shape: selected, layer: source.records.program.layers.last, inheritParentFlags: inheritParentFlags),
        _ => source.moveLiveShapeAfter(shape: selected, after: source.liveShapes[int.parse(destination)], inheritParentFlags: inheritParentFlags),
      };
    } on UnsupportedError catch (error) {
      if (!reject) {
        rethrow;
      }
      issue = error.message;
    }
    if (reject != (issue != null)) {
      throw StateError('Unexpected movement qualification for $name/$variant.');
    }
    final String original = '$name.original.ps';
    final String target = '$name.$variant.ps';
    await File('${output.path}/$original').writeAsBytes(source.records.program.bytes);
    await File('${output.path}/$target').writeAsBytes(result.records.program.bytes);
    rows.add({
      'source': name,
      'variant': variant,
      'original': original,
      'result': target,
      'shape': shape,
      'destination': destination,
      'position': position,
      'inheritParentFlags': inheritParentFlags,
      'rejected': reject,
      'issue': issue,
      'before': shapeLifecycleInventory(source),
      'after': shapeLifecycleInventory(result),
    });
    stdout.writeln('$target passed');
  }

  for (final String name in ['simple_shapes.ai', 'simple_shapes_cc.ai', 'gradient_linear.ai', 'gradient_radial.ai']) {
    final AiNativeDrawing source = _drawing(AiNativeData.extract(const AiCodec().decode(await File('test/corpus/files/$name').readAsBytes())).single.bytes);
    final int first = name == 'gradient_linear.ai' ? 0 : 1;
    await record(name, 'forward', source, first, '${source.liveShapes.length - 1}');
    await record(name, 'backward', source, source.liveShapes.length - 1, '$first');
    await record(name, 'adjacent', source, first, '${first + 1}');
    if (first != 0) {
      await record(name, 'reject-first', source, 0, '${source.liveShapes.length - 1}', reject: true);
    }
  }
  final AiNativeDrawing plain = _drawing(latin1.encode(shapeReorderingSource()));
  await record('synthetic', 'forward', plain, 0, '2');
  await record('synthetic', 'backward', plain, 2, '0');
  final AiNativeDrawing groups = _drawing(latin1.encode(shapeMovementSource(layers: false)));
  await record('synthetic-groups', 'empty', groups, 0, 'empty-group');
  await record('synthetic-groups', 'backward', groups, 2, 'first-group');
  final AiNativeDrawing layers = _drawing(latin1.encode(shapeMovementSource()));
  await record('synthetic-layers', 'cross', layers, 0, '2', inheritParentFlags: true);
  await record('synthetic-layers', 'empty', layers, 0, 'empty-layer', inheritParentFlags: true);
  await record('synthetic-layers', 'lift', layers, 0, 'first-layer', inheritParentFlags: true);
  await record('synthetic-layers', 'reject-cross', layers, 0, '2', reject: true);
  for (final bool private in [false, true]) {
    final String name = 'synthetic-${private ? 'native' : 'printing'}-flags';
    final AiNativeDrawing source = _drawing(latin1.encode(shapeMovementSource(layers: false, targetFlags: private ? '%_1 A\n%_1 Xw' : '1 A 1 Xw')));
    await record(name, 'inherit', source, 0, 'last-group', inheritParentFlags: true);
    await record(name, 'reject-flags', source, 0, 'last-group', reject: true);
  }
  await record('synthetic-unknown', 'forward', _drawing(latin1.encode(identifiedShapeLifecycleSource().replaceFirst('0 A 0 Xw ', ''))), 0, '1');
  await record('synthetic-panel', 'forward', _drawing(latin1.encode(shapeReorderingSource().replaceFirst('\nu\n', '\n0 Ae\nu\n'))), 0, '2');
  await record(
    'synthetic-reference',
    'forward',
    _drawing(latin1.encode(shapeReorderingSource().replaceFirst('%%EndSetup', '/Dictionary : /XMLUID : (author_0) ; (Reference) , ;\n%%EndSetup'))),
    0,
    '2',
  );
  final AiNativeDrawing following = _drawing(latin1.encode(shapeReorderingSource().replaceFirst('%%Trailer', '70 70 m 80 80 L f\n%%Trailer')));
  await record('synthetic-following', 'reject-forward', following, 0, '2', reject: true);
  await record('synthetic-following', 'reject-backward', following, 2, '0', reject: true);
  await File('${output.path}/report.json').writeAsString('${const JsonEncoder.withIndent('  ').convert(rows)}\n');
}
