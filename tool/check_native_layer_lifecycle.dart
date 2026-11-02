import 'dart:convert';
import 'dart:io';

import 'package:aicodec/aicodec.dart';

import 'native_layer_support.dart';

/// Supplies explicit process paint and object flags before any synthetic art.
const String _state = '0 A 0 Xw 0.1 g 0 G 2 w [] 0 d 0 O 0 R 0 XR 0 D 0 Ap 0 J 0 j 10 M';

/// Writes representative identified CC layers without borrowed artwork.
String _layer(String name, String body, {bool hidden = false}) =>
    '''%AI5_BeginLayer
${hidden ? '0 1 0 1 0 0 0' : '1 1 1 1 0 0 1'} 0 79 128 255 0 50 0 Lb
($name) Ln
1 AE
%_/ArtDictionary :
%_/XMLUID : ($name) ; (AI10_ArtUID) ,
%_;
$body
LB
%AI5_EndLayer--''';

/// Creates a counted open path at a distinct native position.
String _path(int position) => '2 As $position 0 m ${position + 1} 1 L S';

/// Decodes one native source without generating a compatibility representation.
AiNativeLayers _decode(List<int> bytes) => AiNativeLayers.decode(
  drawing: AiNativeDrawing.decode(
    records: AiNativeRecords.decode(program: AiProgram.decode(bytes: bytes)),
  ),
);

/// Writes transactions for an independent reader and exact-source comparisons.
Future<void> main() async {
  final Directory output = await Directory('test/corpus/output/layer-lifecycle').create(recursive: true);
  final List<Map<String, Object?>> rows = [];

  /// Saves the selected source handles and the complete before/after inventory.
  Future<void> record(
    String source,
    String original,
    String operation,
    AiNativeLayers before,
    AiNativeLayers after,
    List<int> selected, {
    int? anchor,
    String? label,
    Map<AiNativeLayer, List<int>> identifiers = const {},
    Map<AiNativeLayer, List<int>> names = const {},
  }) async {
    final String file = '$source.${label ?? operation}.ps';
    await File('${output.path}/$file').writeAsBytes(after.drawing.records.program.bytes);
    rows.add({
      'source': source,
      'original': original,
      'result': file,
      'operation': operation,
      'selected': selected,
      'anchor': ?anchor,
      'identifiers': [
        for (final MapEntry<AiNativeLayer, List<int>> entry in identifiers.entries) {'layer': entry.key.index, 'bytes': entry.value},
      ],
      'names': [
        for (final MapEntry<AiNativeLayer, List<int>> entry in names.entries) {'layer': entry.key.index, 'bytes': entry.value},
      ],
      'before': nativeLayerInventory(before),
      'after': nativeLayerInventory(after),
    });
    stdout.writeln('$file: ${before.rootCount} -> ${after.rootCount} roots');
  }

  /// Copies a complete selection with explicit fresh names and nested identities.
  Future<void> duplicate(String name, AiNativeLayers model, List<int> selected, String label) async {
    final List<AiNativeLayer> descendants = [for (final int index in selected) ...model.layers.where((layer) => layer.start >= model.layers[index].start && layer.end <= model.layers[index].end)];
    final Map<AiNativeLayer, List<int>> identifiers = {
      for (final AiNativeLayer layer in descendants)
        if (layer.identifier != null) layer: latin1.encode('AiCodec_copy_${layer.index}'),
    };
    final Map<AiNativeLayer, List<int>> names = {
      for (final AiNativeLayer layer in descendants)
        if (layer.source.naming != null) layer: latin1.encode('Copy ${layer.index}'),
    };
    final AiNativeLayers result = model.duplicate(layers: selected.map((index) => model.layers[index]).toList(), identifiers: identifiers, names: names, discardViewState: true);
    await record(name, '$name.original.ps', 'duplicate', model, result, selected, label: label, identifiers: identifiers, names: names);
  }

  const String name = 'layers_and_sublayers.ai';
  final AiNativeLayers layers = _decode(AiNativeData.extract(const AiCodec().decode(await File('test/corpus/files/$name').readAsBytes())).single.bytes);
  await File('${output.path}/$name.original.ps').writeAsBytes(layers.drawing.records.program.bytes);
  await duplicate(name, layers, [1], 'copy-child');
  await duplicate(name, layers, [3], 'copy-subtree');
  await record(name, '$name.original.ps', 'reorder', layers, layers.reorder(layers: [layers.layers[2], layers.layers[1]], discardViewState: true), [2, 1]);
  await record(
    name,
    '$name.original.ps',
    'after',
    layers,
    layers.moveAfter(layer: layers.layers[1], after: layers.layers[2], discardViewState: true),
    [1],
    anchor: 2,
    label: 'sibling',
  );
  await record(
    name,
    '$name.original.ps',
    'after',
    layers,
    layers.moveAfter(layer: layers.layers[4], after: layers.layers[3], inheritParentFlags: true, discardViewState: true),
    [4],
    anchor: 3,
    label: 'lift-subtree',
  );
  await record(
    name,
    '$name.original.ps',
    'after',
    layers,
    layers.moveAfter(layer: layers.layers[5], after: layers.layers[3], inheritParentFlags: true, discardViewState: true),
    [5],
    anchor: 3,
    label: 'lift-child',
  );
  await record(name, '$name.original.ps', 'inside', layers, layers.moveInto(layer: layers.layers[5], parent: layers.layers[3], inheritParentFlags: true, discardViewState: true), [5], anchor: 3);

  for (final String name in ['simple_shapes.ai', 'simple_shapes_cc.ai']) {
    final AiNativeLayers before = _decode(AiNativeData.extract(const AiCodec().decode(await File('test/corpus/files/$name').readAsBytes())).single.bytes);
    await File('${output.path}/$name.original.ps').writeAsBytes(before.drawing.records.program.bytes);
    final AiNativeLayers inserted = before.insertAfter(after: before.layers.single, nameBytes: latin1.encode('Inserted'), identifierBytes: latin1.encode('AiCodec_inserted'), discardViewState: true);
    await record(name, '$name.original.ps', 'insert', before, inserted, [0]);
    final AiNativeLayers moved = inserted.moveInto(layer: inserted.layers.last, parent: inserted.layers.first, inheritParentFlags: true);
    await record(name, '$name.insert.ps', 'inside', inserted, moved, [1], anchor: 0);
  }

  const String anonymousName = 'inkscape_minimized_ai7.ai';
  final AiNativeLayers anonymous = _decode(AiNativeData.extract(const AiCodec().decode(await File('test/corpus/files/$anonymousName').readAsBytes())).single.bytes);
  await File('${output.path}/$anonymousName.original.ps').writeAsBytes(anonymous.drawing.records.program.bytes);
  final AiNativeLayers inserted = anonymous.insertAfter(after: anonymous.layers.single, nameBytes: latin1.encode('Inserted'), discardViewState: true);
  await record(anonymousName, '$anonymousName.original.ps', 'insert', anonymous, inserted, [0]);
  await record(anonymousName, '$anonymousName.insert.ps', 'remove', inserted, inserted.remove(layers: [inserted.layers.last]), [1]);

  final String body = [
    _layer('A', '0.2 g ${_path(10)}\n${_layer('A1', '1 A 1 Xw 5 w u ${_path(20)} U', hidden: true)}'),
    _layer('B', '0 A 0 Xw 0.7 g 4 w ${_path(30)}\n${_layer('B1', 'u ${_path(40)} 0.4 g ${_path(50)} U')}', hidden: true),
    _layer('C', '0.9 g'),
  ].join('\n');
  final AiNativeLayers synthetic = _decode(
    latin1.encode('''%!PS-Adobe-3.0
%%Creator: Adobe Illustrator
%%BoundingBox: 0 0 100 100
%AI5_NumLayers: 3
%AI5_OpenViewLayers: 37
%%EndComments
%%BeginProlog
%%EndProlog
%%BeginSetup
%%EndSetup
$_state
$body
%%PageTrailer
%%Trailer
%%EOF
'''),
  );
  await File('${output.path}/synthetic-state.original.ps').writeAsBytes(synthetic.drawing.records.program.bytes);
  await duplicate('synthetic-state', synthetic, [0, 4], 'copy-batch');
  await record('synthetic-state', 'synthetic-state.original.ps', 'remove', synthetic, synthetic.remove(layers: [synthetic.layers[0]], discardViewState: true), [0]);
  await record('synthetic-state', 'synthetic-state.original.ps', 'remove', synthetic, synthetic.remove(layers: [synthetic.layers[1]], discardViewState: true), [1], label: 'remove-child');
  await record(
    'synthetic-state',
    'synthetic-state.original.ps',
    'remove',
    synthetic,
    synthetic.remove(layers: [synthetic.layers[0], synthetic.layers[2], synthetic.layers[4]], discardViewState: true),
    [0, 2, 4],
    label: 'remove-all',
  );
  await record('synthetic-state', 'synthetic-state.original.ps', 'reorder', synthetic, synthetic.reorder(layers: [synthetic.layers[4], synthetic.layers[0]], discardViewState: true), [4, 0]);
  await record('synthetic-state', 'synthetic-state.original.ps', 'after', synthetic, synthetic.moveAfter(layer: synthetic.layers[0], after: synthetic.layers[2], discardViewState: true), [
    0,
  ], anchor: 2);
  await record(
    'synthetic-state',
    'synthetic-state.original.ps',
    'inside',
    synthetic,
    synthetic.moveInto(layer: synthetic.layers[0], parent: synthetic.layers[2], inheritParentFlags: true, discardViewState: true),
    [0],
    anchor: 2,
  );
  await record(
    'synthetic-state',
    'synthetic-state.original.ps',
    'inside',
    synthetic,
    synthetic.moveInto(layer: synthetic.layers[0], parent: synthetic.layers[4], inheritParentFlags: true, discardViewState: true),
    [0],
    anchor: 4,
    label: 'empty-parent',
  );
  await record(
    'synthetic-state',
    'synthetic-state.original.ps',
    'inside',
    synthetic,
    synthetic.moveInto(layer: synthetic.layers[3], parent: synthetic.layers[1], inheritParentFlags: true, discardViewState: true),
    [3],
    anchor: 1,
    label: 'backwards',
  );
  await File('${output.path}/report.json').writeAsString(const JsonEncoder.withIndent('  ').convert(rows));
}
