import 'dart:convert';
import 'dart:io';

import 'package:aicodec/aicodec.dart';

import '../test/ai_native_artwork_movement_test.dart' show movementLayer, movementPath;
import '../test/ai_native_layer_creation_test.dart' show createdLayerAttributes, layerCreationSource, layerDefinition;
import 'native_layer_support.dart' show nativeLayerInventory;

/// Opens source ownership without creating any derived artwork.
AiNativeLayers _layers(List<int> bytes) => AiNativeLayers.decode(
  drawing: AiNativeDrawing.decode(
    records: AiNativeRecords.decode(program: AiProgram.decode(bytes: bytes)),
  ),
);

/// Emits fixed first-layer, root and nested creation transactions.
Future<void> main() async {
  final Directory output = await Directory('test/corpus/output/layer-creation').create(recursive: true);
  final List<Map<String, Object?>> rows = [];

  /// Saves explicit definitions and source-owned insertion boundaries.
  Future<void> record(String name, String variant, AiNativeLayers source, {int? parent, List<double> attributes = createdLayerAttributes, bool expanded = false}) async {
    final AiNativeLayerDefinition definition = layerDefinition(name: 'AiCodec (new)', identifier: 'AiCodec_new', attributes: attributes, expanded: expanded);
    final AiNativeLayer? owner = parent == null ? null : source.layers[parent];
    final AiNativeLayers result = source.create(definition: definition, parent: owner, discardViewState: true);
    final String original = '$name.original.ps';
    final String target = '$name.$variant.ps';
    await File('${output.path}/$original').writeAsBytes(source.drawing.records.program.bytes);
    await File('${output.path}/$target').writeAsBytes(result.drawing.records.program.bytes);
    rows.add({
      'source': name,
      'variant': variant,
      'parent': parent,
      'position': owner?.source.end.start ?? source.drawing.records.program.bodyEnd,
      'attributes': definition.attributes,
      'name': definition.nameBytes,
      'identifier': definition.identifierBytes,
      'expanded': definition.expanded,
      'original': original,
      'result': target,
      'before': nativeLayerInventory(source),
      'after': nativeLayerInventory(result),
    });
    stdout.writeln('$target passed');
  }

  for (final String name in ['simple_shapes.ai', 'simple_shapes_cc.ai', 'layers_and_sublayers.ai']) {
    final AiNativeLayers source = _layers(AiNativeData.extract(const AiCodec().decode(await File('test/corpus/files/$name').readAsBytes())).single.bytes);
    await record(name, 'root', source);
    await record(name, 'nested', source, parent: 0, expanded: true);
  }
  final AiNativeLayers empty = _layers(latin1.encode(layerCreationSource()));
  await record('synthetic-empty', 'classic', empty, attributes: [0, 1, 0, 0, 1, 0, -1, 255, 0, 128]);
  await record('synthetic-empty', 'extended', empty, attributes: createdLayerAttributes.take(13).toList(), expanded: true);
  await record('synthetic-empty', 'cc', empty);
  final AiNativeLayers nine = _layers(latin1.encode(layerCreationSource(body: [for (int index = 0; index < 9; index++) movementLayer('Layer_$index', movementPath(index))].join('\n'), count: 9)));
  await record('synthetic-nine', 'root', nine);
  final AiNativeLayers nested = _layers(latin1.encode(layerCreationSource(body: movementLayer('Parent', '${movementLayer('Empty', '')}\n${movementPath(10)}'), count: 1)));
  await record('synthetic-parent', 'populated', nested, parent: 0);
  await record('synthetic-parent', 'empty', nested, parent: 1);
  await File('${output.path}/report.json').writeAsString('${const JsonEncoder.withIndent('  ').convert(rows)}\n');
}
