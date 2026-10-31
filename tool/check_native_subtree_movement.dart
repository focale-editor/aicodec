import 'dart:convert';
import 'dart:io';

import 'package:aikit/aikit.dart';

import '../test/ai_native_subtree_movement_test.dart' show subtreeMovementSource;
import '../test/ai_native_subtree_reordering_test.dart' show subtreeBatchReorderingSource, subtreeReorderingSource;
import 'check_native_shape_lifecycle.dart' show shapeLifecycleInventory;
import 'native_layer_support.dart' show nativeLayerInventory;
import 'native_subtree_support.dart' show wrapNativeSubtrees;

/// Opens bounded immutable native source without producing host representations.
AiNativeDrawing _drawing(List<int> bytes) => AiNativeDrawing.decode(
  records: AiNativeRecords.decode(program: AiProgram.decode(bytes: bytes)),
);

/// Locates declared owner identities without relying on their mutable positions.
AiNativeItem _owner(AiNativeDrawing drawing, String name) {
  if (name == 'empty-group') {
    return drawing.groups.singleWhere((group) => group.paths.isEmpty);
  }
  final AiNativeObjects objects = AiNativeObjects.decode(drawing: drawing);
  final AiNativeGroup? group = drawing.groups.where((group) => latin1.decode(objects.forSource(group).identifier?.bytes ?? const []) == name).firstOrNull;
  return group ?? AiNativeLayers.decode(drawing: drawing).layers.singleWhere((layer) => latin1.decode(layer.nameBytes ?? const []) == name);
}

/// Captures each saved pair and complete layer ownership for independent decoding.
Map<String, Object?> _inventory(AiNativeDrawing drawing) => {
  'layers': nativeLayerInventory(AiNativeLayers.decode(drawing: drawing)),
  'pairs': shapeLifecycleInventory(drawing).where((shape) => shape['printing'] != null).toList(),
};

/// Emits fixed complete-owner moves with explicit source and destination semantics.
Future<void> main() async {
  final Directory output = await Directory('test/corpus/output/subtree-movement').create(recursive: true);
  final List<Map<String, Object?>> rows = [];

  /// Saves owned intervals and immutable refusals without silently changing requests.
  Future<void> record(
    String name,
    String operation,
    String variant,
    AiNativeDrawing source,
    String selected,
    String destination,
    String anchorName, {
    bool inherit = false,
    bool reject = false,
    List<Map<String, Object?>>? recipe,
  }) async {
    final AiNativeLayers model = AiNativeLayers.decode(drawing: source);
    final AiNativeObjects objects = AiNativeObjects.decode(drawing: source);
    final AiNativeItem owner = _owner(source, selected);
    final AiNativeItem anchor = _owner(source, anchorName);
    final AiNativeItem sourceSpan = owner is AiNativeGroup ? objects.forSource(owner) : owner;
    final AiNativeItem anchorSpan = anchor is AiNativeGroup ? objects.forSource(anchor) : anchor;
    final int position = destination == 'after'
        ? anchorSpan.end
        : anchor is AiNativeGroup
        ? anchor.closing.start
        : (anchor as AiNativeLayer).source.end.start;
    AiNativeDrawing result = source;
    String? issue;
    try {
      result = switch ((owner, destination, anchor)) {
        (final AiNativeGroup group, 'after', final AiNativeGroup target) => source.moveGroupAfter(group: group, after: target, inheritParentFlags: inherit),
        (final AiNativeGroup group, 'inside', final AiNativeGroup target) => source.moveGroupToGroup(group: group, parent: target, inheritParentFlags: inherit),
        (final AiNativeGroup group, 'inside', final AiNativeLayer target) => source.moveGroupToLayer(group: group, layer: target.source, inheritParentFlags: inherit),
        (final AiNativeLayer layer, 'after', final AiNativeLayer target) =>
          model.moveAfter(layer: model.layerFor(layer.source), after: model.layerFor(target.source), inheritParentFlags: inherit, discardViewState: true).drawing,
        (final AiNativeLayer layer, 'inside', final AiNativeLayer target) =>
          model.moveInto(layer: model.layerFor(layer.source), parent: model.layerFor(target.source), inheritParentFlags: inherit, discardViewState: true).drawing,
        _ => throw StateError('Unsupported declared fixture movement.'),
      };
    } on UnsupportedError catch (error) {
      if (!reject) {
        rethrow;
      }
      issue = error.message;
    }
    if (reject != (issue != null)) {
      throw StateError('Unexpected subtree movement qualification for $name/$operation/$variant.');
    }
    final String original = '$name.$operation.original.ps';
    final String target = '$name.$operation.$variant.ps';
    await File('${output.path}/$original').writeAsBytes(source.records.program.bytes);
    await File('${output.path}/$target').writeAsBytes(result.records.program.bytes);
    rows.add({
      'source': name,
      'operation': operation,
      'variant': variant,
      'selected': selected,
      'destination': destination,
      'anchor': anchorName,
      'inheritParentFlags': inherit,
      'span': [sourceSpan.start, sourceSpan.end],
      'anchorSpan': [anchorSpan.start, anchorSpan.end],
      'position': position,
      'original': original,
      'result': target,
      'recipe': recipe,
      'rejected': reject,
      'issue': issue,
      'before': _inventory(source),
      'after': _inventory(result),
    });
    stdout.writeln('$target passed');
  }

  for (final String name in ['simple_shapes.ai', 'simple_shapes_cc.ai', 'gradient_linear.ai', 'gradient_radial.ai']) {
    final AiNativeDrawing original = _drawing(AiNativeData.extract(const AiCodec().decode(await File('test/corpus/files/$name').readAsBytes())).single.bytes);
    for (final String operation in ['group', 'layer']) {
      final ({AiNativeDrawing drawing, List<Map<String, Object?>> recipe}) fixture = wrapNativeSubtrees(original, layers: operation == 'layer');
      final String prefix = operation == 'group' ? 'outer_' : 'Wrapped_';
      final String first = '$prefix${name == 'gradient_linear.ai' ? 0 : 1}';
      final String last = '$prefix${original.liveShapes.length - 1}';
      await record(name, operation, 'forward', fixture.drawing, first, 'after', last, recipe: fixture.recipe);
      await record(name, operation, 'backward', fixture.drawing, last, 'after', first, recipe: fixture.recipe);
      await record(name, operation, 'inside', fixture.drawing, first, 'inside', last, inherit: true, recipe: fixture.recipe);
      if (name != 'gradient_linear.ai') {
        await record(name, operation, 'reject-first', fixture.drawing, '${prefix}0', 'after', last, reject: true, recipe: fixture.recipe);
      }
    }
  }
  final AiNativeDrawing groups = _drawing(latin1.encode(subtreeMovementSource()));
  await record('synthetic-groups', 'group', 'forward', groups, 'outer_0', 'after', 'outer_2');
  await record('synthetic-groups', 'group', 'backward', groups, 'outer_2', 'after', 'outer_0');
  await record('synthetic-groups', 'group', 'inside', groups, 'outer_0', 'inside', 'outer_2', inherit: true);
  await record('synthetic-groups', 'group', 'empty', groups, 'outer_0', 'inside', 'empty-group', inherit: true);
  await record('synthetic-groups', 'group', 'reject-parent', groups, 'outer_0', 'inside', 'outer_2', reject: true);
  final AiNativeDrawing layers = _drawing(latin1.encode(subtreeMovementSource(layers: true)));
  await record('synthetic-layers', 'group', 'cross', layers, 'outer_0', 'after', 'outer_2', inherit: true);
  await record('synthetic-layers', 'group', 'lift', layers, 'outer_0', 'inside', 'Layer_0', inherit: true);
  await record('synthetic-layers', 'group', 'empty', layers, 'outer_0', 'inside', 'Empty', inherit: true);
  await record('synthetic-layers', 'group', 'reject-cross', layers, 'outer_0', 'after', 'outer_2', reject: true);
  await record('synthetic-layers', 'layer', 'forward', layers, 'Layer_0', 'after', 'Layer_2');
  await record('synthetic-layers', 'layer', 'backward', layers, 'Layer_2', 'after', 'Layer_0');
  await record('synthetic-layers', 'layer', 'inside', layers, 'Layer_0', 'inside', 'Layer_2', inherit: true);
  await record('synthetic-layers', 'layer', 'empty', layers, 'Layer_0', 'inside', 'Empty', inherit: true);
  await record('synthetic-layers', 'layer', 'lift', layers, 'Child_0', 'after', 'Layer_2', inherit: true);
  await record('synthetic-layers', 'layer', 'ancestor', layers, 'Child_0', 'after', 'Layer_0', inherit: true);
  await record('synthetic-layers', 'layer', 'reject-parent', layers, 'Layer_0', 'inside', 'Layer_2', reject: true);
  await record('synthetic-batch', 'group', 'forward', _drawing(latin1.encode(subtreeBatchReorderingSource())), 'batch_a', 'after', 'batch_b');
  for (final bool reset in [false, true]) {
    final AiNativeDrawing source = _drawing(latin1.encode(subtreeReorderingSource(following: true, reset: reset)));
    final String name = reset ? 'synthetic-reset' : 'synthetic-following';
    await record(name, 'group', 'forward', source, 'outer_0', 'after', 'outer_2', reject: !reset);
    await record(name, 'group', 'backward', source, 'outer_2', 'after', 'outer_0', reject: !reset);
  }
  await File('${output.path}/report.json').writeAsString('${const JsonEncoder.withIndent('  ').convert(rows)}\n');
}
