import 'dart:convert';
import 'dart:io';

import 'package:aikit/aikit.dart';

import '../test/ai_native_group_creation_test.dart' show groupCreationDrawing, groupCreationSource;
import '../test/ai_native_objects_test.dart' show objectSource;
import '../test/ai_native_path_group_movement_test.dart' show mixedPathGroupSource, pathGroupParent;
import 'check_native_shape_lifecycle.dart' show shapeLifecycleInventory;
import 'native_layer_support.dart' show nativeLayerInventory;

/// Retains independent layer and complete CC-pair ownership for every snapshot.
Map<String, Object?> _inventory(AiNativeDrawing drawing) => {
  'layers': nativeLayerInventory(AiNativeLayers.decode(drawing: drawing)),
  'pairs': shapeLifecycleInventory(drawing).where((shape) => shape['printing'] != null).toList(),
};

/// Emits fixed sibling-free group creation and explicit inheritance transactions.
Future<void> main() async {
  final Directory output = await Directory('test/corpus/output/group-creation').create(recursive: true);
  final List<Map<String, Object?>> rows = [];

  /// Saves the requested destination and exact immutable refusal when applicable.
  Future<void> record(String name, String variant, AiNativeDrawing source, {AiNativeGroup? parent, AiLayer? layer, String? anchorName, bool inherit = false, bool reject = false}) async {
    AiNativeDrawing result = source;
    String? issue;
    try {
      result = source.createGroup(parent: parent, layer: layer, identifierBytes: latin1.encode('AiKit_group'), nameBytes: latin1.encode('AiKit (group)'), inheritParentFlags: inherit);
    } on UnsupportedError catch (error) {
      if (!reject) {
        rethrow;
      }
      issue = error.message;
    }
    if (reject != (issue != null)) {
      throw StateError('Unexpected group creation qualification for $name/$variant.');
    }
    final String original = '$name.original.ps';
    final String target = '$name.$variant.ps';
    await File('${output.path}/$original').writeAsBytes(source.records.program.bytes);
    await File('${output.path}/$target').writeAsBytes(result.records.program.bytes);
    rows.add({
      'source': name,
      'variant': variant,
      'target': parent != null
          ? 'group'
          : layer != null
          ? 'layer'
          : 'root',
      'anchor': anchorName,
      'groupSpan': parent == null ? null : [parent.start, parent.end],
      'layer': layer == null ? null : source.records.program.layers.indexOf(layer),
      'position': parent?.closing.start ?? layer?.end.start ?? source.records.program.bodyEnd,
      'inheritParentFlags': inherit,
      'rejected': reject,
      'issue': issue,
      'original': original,
      'result': target,
      'before': _inventory(source),
      'after': _inventory(result),
    });
    stdout.writeln('$target passed');
  }

  for (final String name in ['simple_shapes.ai', 'simple_shapes_cc.ai', 'layers_and_sublayers.ai']) {
    final AiNativeDrawing source = AiNativeDrawing.decode(
      records: AiNativeRecords.decode(program: AiProgram.decode(bytes: AiNativeData.extract(const AiCodec().decode(await File('test/corpus/files/$name').readAsBytes())).single.bytes)),
    );
    await record(name, 'root', source, inherit: true);
    await record(name, 'layer', source, layer: source.records.program.layers.first, inherit: true);
    if (name == 'layers_and_sublayers.ai') {
      await record(name, 'group', source, parent: source.groups.single, inherit: true);
    }
  }
  await record('synthetic-empty', 'root', groupCreationDrawing(objectSource('', setup: '')));
  final AiNativeDrawing groups = groupCreationDrawing(groupCreationSource);
  for (final String name in ['Parent', 'Empty']) {
    await record('synthetic-groups', name.toLowerCase(), groups, parent: pathGroupParent(groups, name), anchorName: name);
  }
  final AiNativeDrawing mixed = groupCreationDrawing(mixedPathGroupSource());
  await record('synthetic-mixed', 'parent', mixed, parent: pathGroupParent(mixed, 'outer_0'), anchorName: 'outer_0', inherit: true);
  final AiNativeDrawing flagged = groupCreationDrawing(objectSource('1 A\n%_1 Xw\nu U', setup: ''));
  await record('synthetic-flags', 'inherited', flagged, inherit: true);
  await record('synthetic-flags', 'rejected', flagged, reject: true);
  await File('${output.path}/report.json').writeAsString('${const JsonEncoder.withIndent('  ').convert(rows)}\n');
}
