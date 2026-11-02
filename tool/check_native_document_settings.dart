import 'dart:convert';
import 'dart:io';

import 'package:aicodec/aicodec.dart';

/// Records settings and exact native ownership from both baseline and CC units.
Future<void> main() async {
  final Directory output = await Directory('test/corpus/output/document-settings').create(recursive: true);
  final List<Map<String, Object?>> rows = [];
  for (final String manifestName in ['manifest.json', 'document_manifest.json']) {
    final Map<String, Object?> manifest = (jsonDecode(await File('test/corpus/$manifestName').readAsString()) as Map).cast<String, Object?>();
    for (final Object? entry in manifest['files']! as List) {
      final String name = (entry! as Map)['file'] as String;
      final List<AiNativeSource> sources = AiNativeData.extract(const AiCodec().decode(await File('test/corpus/files/$name').readAsBytes()));
      for (final (int, AiNativeSource) source in sources.indexed) {
        final AiNativeDocumentSettings settings = AiNativeDocumentSettings.decode(
          records: AiNativeRecords.decode(program: AiProgram.decode(bytes: source.$2.bytes)),
        );
        final String native = '$name.${source.$1}.ps';
        await File('${output.path}/$native').writeAsBytes(source.$2.bytes);
        rows.add({
          'file': name,
          'manifest': manifestName,
          'sourceIndex': source.$1,
          'native': native,
          'header': {for (final MapEntry<String, AiNativeHeaderField> entry in settings.header.entries) entry.key: entry.value.values},
          'rulerUnit': settings.rulerUnit?.name,
          'documents': settings.documents.length,
          'artboards': [
            for (final AiNativeArtboard board in settings.artboards)
              {
                'document': settings.documents.indexOf(board.document),
                'index': board.index,
                'name': latin1.decode(board.nameBytes),
                'identifier': board.identifier,
                'selected': board.selected,
                'bounds': [board.bounds.left, board.bounds.bottom, board.bounds.right, board.bounds.top],
                'rulerOrigin': board.rulerOrigin,
              },
          ],
          'textRulerOrigins': settings.textRulerOrigins.map((origin) => origin.coordinates).toList(),
        });
        stdout.writeln('$name: ${settings.header.length} settings, ${settings.artboards.length} artboards, ${settings.textRulerOrigins.length} text origins');
      }
    }
  }
  await File('${output.path}/report.json').writeAsString(const JsonEncoder.withIndent('  ').convert(rows));
}
