import 'dart:convert';
import 'dart:io';

import 'package:aicodec/aicodec.dart';

import '../test/ai_native_artwork_movement_test.dart' show movementState;
import '../test/ai_native_group_creation_test.dart' show groupCreationDrawing;
import '../test/ai_native_objects_test.dart' show objectSource;
import '../test/ai_native_path_creation_test.dart' show createdPath, pathCreationDefinition, pathCreationSource;
import '../test/ai_native_path_group_movement_test.dart' show mixedPathGroupSource, pathGroupParent;
import 'check_native_shape_lifecycle.dart' show shapeLifecycleInventory;
import 'native_layer_support.dart' show nativeLayerInventory;

/// Retains independent source ownership for existing layers and complete CC pairs.
Map<String, Object?> _inventory(AiNativeDrawing drawing) => {
  'layers': nativeLayerInventory(AiNativeLayers.decode(drawing: drawing)),
  'pairs': shapeLifecycleInventory(drawing).where((shape) => shape['printing'] != null).toList(),
};

/// Emits fixed explicit-path definitions without generating host representations.
Future<void> main() async {
  final Directory output = await Directory('test/corpus/output/path-creation').create(recursive: true);
  final List<Map<String, Object?>> rows = [];

  /// Saves requested geometry, original append boundary and exact native results.
  Future<void> record(
    String name,
    String variant,
    AiNativeDrawing source, {
    AiNativeGroup? parent,
    AiLayer? layer,
    String? anchor,
    AiColorSpace space = .rgb,
    bool closed = true,
    bool counted = true,
    bool filled = true,
    bool stroked = true,
    bool reject = false,
  }) async {
    final AiNativePathDefinition definition = pathCreationDefinition(space: space, closed: closed, counted: counted, filled: filled, stroked: stroked);
    final int position = parent?.closing.start ?? layer?.end.start ?? source.records.program.bodyEnd;
    AiNativeDrawing result = source;
    String? issue;
    try {
      result = source.createPath(definition: definition, parent: parent, layer: layer);
    } on UnsupportedError catch (error) {
      if (!reject) {
        rethrow;
      }
      issue = error.message;
    }
    if (reject != (issue != null)) {
      throw StateError('Unexpected path creation qualification for $name/$variant.');
    }
    final List<AiSourceEdit> bounds = reject ? [] : AiNativeEditor.includeBoundsEdits(program: source.records.program, bounds: definition.bounds);
    final int start = position + bounds.fold<int>(0, (offset, edit) => offset + (edit.end <= position ? edit.bytes.length - (edit.end - edit.start) : 0));
    final int length = result.records.program.bytes.length - source.records.program.bytes.length - bounds.fold<int>(0, (offset, edit) => offset + edit.bytes.length - (edit.end - edit.start));
    final AiNativePath? path = reject ? null : createdPath(result);
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
      'anchor': anchor,
      'groupSpan': parent == null ? null : [parent.start, parent.end],
      'layer': layer == null ? null : source.records.program.layers.indexOf(layer),
      'position': position,
      'inserted': [start, start + length],
      'geometry': path == null ? null : [path.start, path.end],
      'space': space.name,
      'closed': closed,
      'counted': counted,
      'filled': filled,
      'stroked': stroked,
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
    await record(name, 'root', source);
    await record(name, 'layer', source, layer: source.records.program.layers.first);
    if (name == 'layers_and_sublayers.ai') {
      await record(name, 'group', source, parent: source.groups.single);
    }
  }
  final AiNativeDrawing empty = groupCreationDrawing(objectSource('', setup: '').replaceFirst(movementState, ''));
  for (final AiColorSpace space in AiColorSpace.values) {
    await record('synthetic-empty', space.name, empty, space: space);
  }
  await record('synthetic-empty', 'unpainted', empty, filled: false, stroked: false);
  await record('synthetic-empty', 'fill', empty, stroked: false);
  await record('synthetic-empty', 'stroke', empty, filled: false);
  await record('synthetic-empty', 'uncounted-open', empty, counted: false, closed: false);
  final AiNativeDrawing groups = groupCreationDrawing(pathCreationSource);
  for (final String name in ['Parent', 'Empty']) {
    await record('synthetic-groups', name.toLowerCase(), groups, parent: pathGroupParent(groups, name), anchor: name);
  }
  final AiNativeDrawing mixed = groupCreationDrawing(mixedPathGroupSource());
  await record('synthetic-mixed', 'parent', mixed, parent: pathGroupParent(mixed, 'outer_0'), anchor: 'outer_0');
  final AiNativeDrawing unknown = groupCreationDrawing(objectSource('0 0.9 0 0 0 Xy\nu U\n20 -20 m 30 -30 L 20 -30 L f', setup: '').replaceFirst('0.1 g', ''));
  await record('synthetic-unknown', 'rejected', unknown, parent: unknown.groups.single, reject: true);
  await File('${output.path}/report.json').writeAsString('${const JsonEncoder.withIndent('  ').convert(rows)}\n');
}
