import 'dart:convert';
import 'dart:io';

import 'package:aicodec/aicodec.dart';

import '../test/ai_native_identity_lifecycle_test.dart' show artworkCopyIdentifiers, identityLifecycleSource, layerCopyIdentifiers;
import '../test/ai_native_identity_reservation_test.dart' show identityReservationSource;
import 'native_layer_support.dart';
import 'native_object_support.dart';

/// Captures both identity namespaces and exact complete-object boundaries.
Map<String, Object?> _inventory(AiNativeLayers model) => {'layers': nativeLayerInventory(model), 'objects': nativeObjectInventory(model.drawing)};

/// Exercises complete identified subtrees and qualified identity removal.
Future<void> main() async {
  final Directory output = await Directory('test/corpus/output/identity-lifecycle').create(recursive: true);
  final AiNativeLayers before = AiNativeLayers.decode(
    drawing: AiNativeDrawing.decode(
      records: AiNativeRecords.decode(program: AiProgram.decode(bytes: latin1.encode(identityLifecycleSource))),
    ),
  );
  await File('${output.path}/original.ps').writeAsBytes(before.drawing.records.program.bytes);
  final List<Map<String, Object?>> rows = [];

  /// Records one exact request without deriving expected results from edited data.
  Future<void> record(
    String label,
    String operation,
    AiNativeLayers after, {
    List<AiNativeLayer> selectedLayers = const [],
    List<AiNativeItem> selectedObjects = const [],
    Map<AiNativeLayer, List<int>> layerIdentifiers = const {},
    Map<AiNativeItem, List<int>> artworkIdentifiers = const {},
    AiNativeLayers? input,
    String source = 'synthetic',
  }) async {
    final AiNativeLayers original = input ?? before;
    final AiNativeObjects objects = AiNativeObjects.decode(drawing: original.drawing);
    final String originalFile = input == null ? 'original.ps' : '$label.original.ps';
    final String result = '$label.ps';
    await File('${output.path}/$originalFile').writeAsBytes(original.drawing.records.program.bytes);
    await File('${output.path}/$result').writeAsBytes(after.drawing.records.program.bytes);
    rows.add({
      'source': source,
      'original': originalFile,
      'result': result,
      'operation': operation,
      'layers': selectedLayers.map((layer) => layer.index).toList(),
      'objects': selectedObjects.map((source) => objects.objects.indexOf(objects.forSource(source))).toList(),
      'layerIdentifiers': [
        for (final MapEntry<AiNativeLayer, List<int>> entry in layerIdentifiers.entries) {'layer': entry.key.index, 'bytes': entry.value},
      ],
      'artworkIdentifiers': [
        for (final MapEntry<AiNativeItem, List<int>> entry in artworkIdentifiers.entries) {'object': objects.objects.indexOf(objects.forSource(entry.key)), 'bytes': entry.value},
      ],
      'before': _inventory(original),
      'after': _inventory(after),
    });
    stdout.writeln('$result passed');
  }

  final List<AiNativeLayer> root = [before.layers.first];
  final Map<AiNativeLayer, List<int>> layerIds = layerCopyIdentifiers(before);
  final Map<AiNativeItem, List<int>> artworkIds = artworkCopyIdentifiers(before);
  await record(
    'copy-root',
    'copy',
    before.duplicate(layers: root, identifiers: layerIds, artworkIdentifiers: artworkIds, discardViewState: true),
    selectedLayers: root,
    layerIdentifiers: layerIds,
    artworkIdentifiers: artworkIds,
  );
  final List<AiNativeLayer> batch = [before.layers[2], before.layers[1]];
  final Map<AiNativeLayer, List<int>> batchLayerIds = {before.layers[1]: latin1.encode('Nested_A1'), before.layers[2]: latin1.encode('Other_B')};
  final Map<AiNativeItem, List<int>> batchArtworkIds = {
    before.drawing.paths[1]: latin1.encode('Nested_path'),
    before.drawing.groups.single: latin1.encode('Nested_group'),
    before.drawing.paths[2]: latin1.encode('Other_path'),
  };
  await record(
    'copy-batch',
    'copy',
    before.duplicate(layers: batch, identifiers: batchLayerIds, artworkIdentifiers: batchArtworkIds, discardViewState: true),
    selectedLayers: batch,
    layerIdentifiers: batchLayerIds,
    artworkIdentifiers: batchArtworkIds,
  );
  await record('remove-root', 'remove-layers', before.remove(layers: root, discardViewState: true), selectedLayers: root);
  final List<AiNativeLayer> roots = before.layers.where((layer) => layer.parentIndex == null).toList();
  await record('remove-all', 'remove-layers', before.remove(layers: roots, discardViewState: true), selectedLayers: roots);
  final List<AiNativePath> paths = [before.drawing.paths[0], before.drawing.paths[1]];
  await record(
    'remove-paths',
    'remove-paths',
    AiNativeLayers.decode(drawing: before.drawing.removePaths(paths: paths)),
    selectedObjects: paths,
  );
  await record(
    'remove-group',
    'remove-groups',
    AiNativeLayers.decode(drawing: before.drawing.removeGroups(groups: before.drawing.groups)),
    selectedObjects: before.drawing.groups,
  );
  const String payload = '/XMLUID : (reserved) ; (UnknownIdentity) ,\n';
  const String file = 'units-20x40mm_origin_topleft_CC.ai';
  final AiProgram real = AiProgram.decode(bytes: AiNativeData.extract(const AiCodec().decode(await File('test/corpus/files/$file').readAsBytes())).single.bytes);
  final AiNativeContainer document = AiNativeRecords.decode(program: real).roots.singleWhere((record) => record.type == 'Document');
  final int position = document['Recorded']!.container!.end - 1;
  final Map<String, List<int>> inputs = {
    'reserved': latin1.encode(identityReservationSource('/Dictionary : $payload ;')),
    file: [...real.bytes.take(position), ...latin1.encode(payload), ...real.bytes.skip(position)],
  };
  for (final MapEntry<String, List<int>> entry in inputs.entries) {
    final AiNativeLayers original = AiNativeLayers.decode(
      drawing: AiNativeDrawing.decode(
        records: AiNativeRecords.decode(program: AiProgram.decode(bytes: entry.value)),
      ),
    );
    final Map<AiNativeLayer, List<int>> layerIdentifiers = entry.key == 'reserved' ? layerCopyIdentifiers(original) : {original.layers.single: latin1.encode('Copy_CC')};
    final Map<AiNativeItem, List<int>> artworkIdentifiers = entry.key == 'reserved' ? artworkCopyIdentifiers(original) : {};
    await record(
      '${entry.key}.copy',
      'copy',
      original.duplicate(layers: [original.layers.first], identifiers: layerIdentifiers, artworkIdentifiers: artworkIdentifiers, discardViewState: true),
      input: original,
      source: entry.key,
      selectedLayers: [original.layers.first],
      layerIdentifiers: layerIdentifiers,
      artworkIdentifiers: artworkIdentifiers,
    );
    layerIdentifiers[original.layers.first] = latin1.encode('reserved');
    try {
      original.duplicate(layers: [original.layers.first], identifiers: layerIdentifiers, artworkIdentifiers: artworkIdentifiers, discardViewState: true);
      throw StateError('The existing non-artwork XMLUID allowed an identity collision.');
    } on ArgumentError {
      await record(
        '${entry.key}.reject-copy',
        'reject-copy',
        original,
        input: original,
        source: entry.key,
        selectedLayers: [original.layers.first],
        layerIdentifiers: layerIdentifiers,
        artworkIdentifiers: artworkIdentifiers,
      );
    }
  }
  await File('${output.path}/report.json').writeAsString('${const JsonEncoder.withIndent('  ').convert(rows)}\n');
}
