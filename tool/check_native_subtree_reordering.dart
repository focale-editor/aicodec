import 'dart:convert';
import 'dart:io';

import 'package:aikit/aikit.dart';

import '../test/ai_native_artwork_movement_test.dart' show movementLayer;
import '../test/ai_native_objects_test.dart' show objectDictionary;
import '../test/ai_native_subtree_reordering_test.dart' show subtreeBatchReorderingSource, subtreeReorderingGroups, subtreeReorderingSource;
import 'check_native_shape_lifecycle.dart' show shapeLifecycleInventory;
import 'native_layer_support.dart' show nativeLayerInventory;

/// Opens immutable native source without deriving host appearances.
AiNativeDrawing _drawing(List<int> bytes) => AiNativeDrawing.decode(
  records: AiNativeRecords.decode(program: AiProgram.decode(bytes: bytes)),
);

/// Records all layer headers and both saved representations of complete pairs.
Map<String, Object?> _inventory(AiNativeDrawing drawing) => {
  'layers': nativeLayerInventory(AiNativeLayers.decode(drawing: drawing)),
  'pairs': shapeLifecycleInventory(drawing).where((shape) => shape['printing'] != null).toList(),
};

/// Declares wrappers around unchanged pinned real pairs, without source templates.
({AiNativeDrawing drawing, List<Map<String, Object?>> recipe}) _wrapped(AiNativeDrawing original, {required bool layers}) {
  final AiNativeObjects objects = AiNativeObjects.decode(drawing: original);
  final List<Map<String, Object?>> recipe = [];
  final List<AiSourceEdit> edits = [];
  for (final (int, AiLiveShape) entry in original.liveShapes.indexed) {
    final int start = objects.forSource(entry.$2.appearanceGroup!).start;
    final int end = entry.$2.end;
    final String body = latin1.decode(original.records.program.bytes.sublist(start, end));
    const String opening = '0 Ae\nu\nu\n';
    final String closing = '\nU\n${objectDictionary(identifier: 'inner_${entry.$1}')}\nU\n${objectDictionary(identifier: 'outer_${entry.$1}')}';
    final String group = '$opening$body$closing';
    final String wrapper = layers ? movementLayer('Wrapped_${entry.$1}', group) : group;
    final int offset = wrapper.indexOf(body);
    recipe.add({'start': start, 'end': end, 'opening': wrapper.substring(0, offset), 'closing': wrapper.substring(offset + body.length)});
    edits.add(AiSourceEdit(start: start, end: end, bytes: latin1.encode(wrapper)));
  }
  final AiProgram program = AiNativeEditor.apply(program: original.records.program, edits: edits);
  final AiNativeDrawing wrapped = _drawing(program.bytes);
  if (!AiNativeLayers.decode(drawing: wrapped).rootCountMatches) {
    throw StateError('The declared wrappers changed the original root-layer count.');
  }
  return (drawing: wrapped, recipe: recipe);
}

/// Emits complete-owner permutations, exact preservation checks and refusals.
Future<void> main() async {
  final Directory output = await Directory('test/corpus/output/subtree-reordering').create(recursive: true);
  final List<Map<String, Object?>> rows = [];

  /// Retains all original owners so independent checks can bind the permutation.
  Future<void> record(String name, String operation, String variant, AiNativeDrawing source, List<int> order, {List<Map<String, Object?>>? recipe, bool reject = false}) async {
    final AiNativeLayers model = AiNativeLayers.decode(drawing: source);
    final AiNativeObjects objects = AiNativeObjects.decode(drawing: source);
    final List<AiNativeGroup> groups = subtreeReorderingGroups(source, prefix: name == 'synthetic-batch' ? 'batch_' : 'outer_');
    final List<AiNativeLayer> layers = model.layers.where((layer) => latin1.decode(layer.nameBytes ?? const []).startsWith(name.startsWith('synthetic') ? 'Layer_' : 'Wrapped_')).toList();
    final List<AiNativeItem> owners = operation == 'group' ? groups.map(objects.forSource).toList() : layers;
    AiNativeDrawing result = source;
    String? issue;
    try {
      result = operation == 'group'
          ? source.reorderGroups(groups: order.map((index) => groups[index]).toList())
          : model.reorder(layers: order.map((index) => layers[index]).toList(), discardViewState: true).drawing;
    } on UnsupportedError catch (error) {
      if (!reject) {
        rethrow;
      }
      issue = error.message;
    }
    if (reject != (issue != null)) {
      throw StateError('Unexpected subtree reordering qualification for $name/$operation/$variant.');
    }
    final String original = '$name.$operation.original.ps';
    final String target = '$name.$operation.$variant.ps';
    await File('${output.path}/$original').writeAsBytes(source.records.program.bytes);
    await File('${output.path}/$target').writeAsBytes(result.records.program.bytes);
    rows.add({
      'source': name,
      'operation': operation,
      'variant': variant,
      'order': order,
      'original': original,
      'result': target,
      'recipe': recipe,
      'rejected': reject,
      'issue': issue,
      'spans': [
        for (final AiNativeItem owner in owners) [owner.start, owner.end],
      ],
      'before': _inventory(source),
      'after': _inventory(result),
    });
    stdout.writeln('$target passed');
  }

  for (final String name in ['simple_shapes.ai', 'simple_shapes_cc.ai', 'gradient_linear.ai', 'gradient_radial.ai']) {
    final AiNativeDrawing original = _drawing(AiNativeData.extract(const AiCodec().decode(await File('test/corpus/files/$name').readAsBytes())).single.bytes);
    for (final String operation in ['group', 'layer']) {
      final ({AiNativeDrawing drawing, List<Map<String, Object?>> recipe}) fixture = _wrapped(original, layers: operation == 'layer');
      final int first = name == 'gradient_linear.ai' ? 0 : 1;
      await record(name, operation, 'adjacent', fixture.drawing, [first + 1, first], recipe: fixture.recipe);
      await record(name, operation, 'ends', fixture.drawing, [original.liveShapes.length - 1, first], recipe: fixture.recipe);
      await record(name, operation, 'reverse', fixture.drawing, [for (int index = original.liveShapes.length - 1; index >= first; index--) index], recipe: fixture.recipe);
      await record(name, operation, first == 0 ? 'unchanged' : 'reject-first', fixture.drawing, first == 0 ? [0, 1] : [1, 0], recipe: fixture.recipe, reject: first != 0);
    }
  }
  for (final String operation in ['group', 'layer']) {
    final bool layers = operation == 'layer';
    final AiNativeDrawing source = _drawing(latin1.encode(subtreeReorderingSource(layers: layers)));
    await record('synthetic', operation, 'rotate', source, [2, 0, 1]);
    await record('synthetic', operation, 'ends', source, [2, 0]);
    await record('synthetic', operation, 'unchanged', source, [0, 1, 2]);
    await record('synthetic-following', operation, 'reverse', _drawing(latin1.encode(subtreeReorderingSource(layers: layers, following: true))), [2, 1, 0], reject: true);
    await record('synthetic-reset', operation, 'reverse', _drawing(latin1.encode(subtreeReorderingSource(layers: layers, following: true, reset: true))), [2, 1, 0]);
  }
  await record('synthetic-batch', 'group', 'reverse', _drawing(latin1.encode(subtreeBatchReorderingSource())), [1, 0]);
  await File('${output.path}/report.json').writeAsString('${const JsonEncoder.withIndent('  ').convert(rows)}\n');
}
