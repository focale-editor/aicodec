import 'dart:convert';
import 'dart:io';

import 'package:aicodec/aicodec.dart';

import '../test/ai_native_reference_scope_test.dart' show referenceScopeSource;
import 'native_layer_support.dart';
import 'native_object_support.dart';

/// Retains metadata owners separately from all artwork and layer identities.
Map<String, Object?> _inventory(AiNativeLayers model) => {
  'layers': nativeLayerInventory(model),
  'objects': nativeObjectInventory(model.drawing),
  'documents': [
    for (final AiNativeContainer record in model.drawing.records.roots.where((record) => record.type == 'Document')) [record.start, record.end],
  ],
};

/// Opens an immutable source without producing a host compatibility appearance.
AiNativeLayers _model(List<int> bytes) => AiNativeLayers.decode(
  drawing: AiNativeDrawing.decode(
    records: AiNativeRecords.decode(program: AiProgram.decode(bytes: bytes)),
  ),
);

/// Exercises real CC identified-layer removal and synthetic artwork references.
Future<void> main() async {
  final Directory output = await Directory('test/corpus/output/reference-scope').create(recursive: true);
  final List<Map<String, Object?>> rows = [];

  /// Records fixed requests and both source inventories for independent checks.
  Future<void> record(String source, String operation, AiNativeLayers before, AiNativeLayers after, {List<int> layers = const [], List<int> objects = const []}) async {
    final String original = '$source.original.ps';
    final String result = '$source.$operation.ps';
    await File('${output.path}/$original').writeAsBytes(before.drawing.records.program.bytes);
    await File('${output.path}/$result').writeAsBytes(after.drawing.records.program.bytes);
    rows.add({
      'source': source,
      'operation': operation,
      'original': original,
      'result': result,
      'layers': layers,
      'objects': objects,
      'layerIdentifiers': [],
      'artworkIdentifiers': [],
      'before': _inventory(before),
      'after': _inventory(after),
    });
    stdout.writeln('$result passed');
  }

  final Map<String, Object?> manifest = (jsonDecode(await File('test/corpus/document_manifest.json').readAsString()) as Map).cast<String, Object?>();
  for (final Object? entry in manifest['files']! as List) {
    final String name = (entry! as Map)['file'] as String;
    final AiNativeLayers model = _model(AiNativeData.extract(const AiCodec().decode(await File('test/corpus/files/$name').readAsBytes())).single.bytes);
    if (model.layers.length != 1 || model.layers.single.identifier == null || model.drawing.paths.length != 1) {
      throw StateError('The pinned document no longer has one identified layer and ordinary path.');
    }
    await record(name, 'remove-layers', model, model.remove(layers: model.layers, discardViewState: true), layers: [0]);
    if (name == 'units-20x40mm_origin_topleft_CC.ai') {
      final AiNativeContainer document = model.drawing.records.roots.singleWhere((record) => record.type == 'Document');
      final AiNativeContainer recorded = document['Recorded']!.container!;
      final AiNativeContainer assets = recorded['DocumentDict/ExportableAssetsKey']!.container!;
      for (final ({String name, int position, String value}) mutation in [
        (name: 'unknown-reference', position: recorded.end - 1, value: '/XMLUID : (Layer_1) ; (FutureReference) ,\n'),
        (name: 'asset-reference', position: assets.end - 1, value: '/XMLUID : (Layer_1) ; (ExportedObject) ,\n'),
      ]) {
        final List<int> bytes = model.drawing.records.program.bytes;
        final AiNativeLayers rejected = _model([...bytes.take(mutation.position), ...latin1.encode(mutation.value), ...bytes.skip(mutation.position)]);
        try {
          rejected.remove(layers: rejected.layers, discardViewState: true);
          throw StateError('The injected reference unexpectedly permitted identity deletion.');
        } on UnsupportedError {
          await record('$name.${mutation.name}', 'reject-remove', rejected, rejected, layers: [0]);
        }
      }
    }
  }
  final AiNativeLayers synthetic = _model(latin1.encode(referenceScopeSource));
  await record('synthetic', 'remove-layers', synthetic, synthetic.remove(layers: [synthetic.layers.first], discardViewState: true), layers: [0]);
  await record(
    'synthetic',
    'remove-paths',
    synthetic,
    AiNativeLayers.decode(drawing: synthetic.drawing.removePaths(paths: [synthetic.drawing.paths.first])),
    objects: [0],
  );
  await record(
    'synthetic',
    'remove-groups',
    synthetic,
    AiNativeLayers.decode(drawing: synthetic.drawing.removeGroups(groups: synthetic.drawing.groups)),
    objects: [1],
  );
  await File('${output.path}/report.json').writeAsString('${const JsonEncoder.withIndent('  ').convert(rows)}\n');
}
