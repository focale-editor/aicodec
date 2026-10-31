import 'dart:convert';
import 'dart:io';

import 'package:aikit/aikit.dart';

/// Retains source boundaries and exact metadata for independent native decoding.
Map<String, Object?> _inventory(AiNativeLayers model) => {
  'rootCount': model.rootCount,
  'declaredRootCount': model.declaredRootCount,
  'rootCountSpan': model.rootCountHeader == null ? null : [model.rootCountHeader!.token.start, model.rootCountHeader!.token.end],
  'viewSpans': [
    for (final AiToken token in model.viewComments) [token.start, token.end],
  ],
  'layers': [
    for (final AiNativeLayer layer in model.layers)
      {
        'start': layer.start,
        'end': layer.end,
        'opening': [layer.source.begin.start, layer.source.begin.end],
        'closing': [layer.source.end.start, layer.source.end.end],
        'openingComment': layer.openingComment?.lexeme,
        'closingComment': layer.closingComment?.lexeme,
        'bodyStart': layer.bodyStart,
        'parent': layer.parentIndex,
        'children': layer.childIndices,
        'name': layer.nameBytes?.toList(),
        'attributes': layer.source.begin.numbers,
        'expanded': layer.expanded,
        'identifier': layer.identifier?.bytes.toList(),
        'issue': layer.bindingIssue,
      },
  ],
};

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
            variants.add({'selected': layer.index, 'name': label, 'identifier': identifier, 'result': file, 'after': _inventory(changed)});
          } on UnsupportedError catch (error) {
            variants.add({'selected': layer.index, 'unsupported': error.message});
          }
        }
        rows.add({'file': name, 'manifest': manifestName, 'sourceIndex': source.$1, 'native': native, 'before': _inventory(model), 'variants': variants});
        stdout.writeln('$name: ${model.layers.length} layers, ${variants.where((variant) => variant.containsKey('result')).length} insertions');
      }
    }
  }
  await File('${output.path}/report.json').writeAsString(const JsonEncoder.withIndent('  ').convert(rows));
}
