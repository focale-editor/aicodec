import 'dart:convert';
import 'dart:io';

import 'package:aikit/aikit.dart';

import 'native_layer_support.dart';

/// Checks header-only insertion without changing any original artwork bytes.
Future<void> main() async {
  final Directory output = await Directory('test/corpus/output/layers').create(recursive: true);
  final List<Map<String, Object?>> rows = [];
  for (final String manifestName in ['manifest.json', 'document_manifest.json']) {
    final Map<String, Object?> manifest = (jsonDecode(await File('test/corpus/$manifestName').readAsString()) as Map).cast<String, Object?>();
    for (final Object? entry in manifest['files']! as List) {
      final String name = (entry! as Map)['file'] as String;
      final List<AiNativeSource> sources = AiNativeData.extract(const AiCodec().decode(await File('test/corpus/files/$name').readAsBytes()));
      for (final (int, AiNativeSource) source in sources.indexed) {
        final AiNativeLayers model = AiNativeLayers.decode(
          drawing: AiNativeDrawing.decode(
            records: AiNativeRecords.decode(program: AiProgram.decode(bytes: source.$2.bytes)),
          ),
        );
        final String native = '$name.${source.$1}.ps';
        await File('${output.path}/$native').writeAsBytes(source.$2.bytes);
        final List<Map<String, Object?>> variants = [];
        for (final AiNativeLayer layer in model.layers) {
          final List<int> label = latin1.encode('AiKit inserted layer');
          final List<int>? identifier = layer.identifier == null ? null : latin1.encode('AiKit_inserted_${layer.index}');
          try {
            final AiNativeLayers changed = model.insertAfter(after: layer, nameBytes: label, identifierBytes: identifier, discardViewState: true);
            final String file = '$name.${source.$1}.insert-${layer.index}.ps';
            await File('${output.path}/$file').writeAsBytes(changed.drawing.records.program.bytes);
            variants.add({'selected': layer.index, 'name': label, 'identifier': identifier, 'result': file, 'after': nativeLayerInventory(changed)});
          } on UnsupportedError catch (error) {
            variants.add({'selected': layer.index, 'unsupported': error.message});
          }
        }
        rows.add({'file': name, 'manifest': manifestName, 'sourceIndex': source.$1, 'native': native, 'before': nativeLayerInventory(model), 'variants': variants});
        stdout.writeln('$name: ${model.layers.length} layers, ${variants.where((variant) => variant.containsKey('result')).length} insertions');
      }
    }
  }
  await File('${output.path}/report.json').writeAsString(const JsonEncoder.withIndent('  ').convert(rows));
}
