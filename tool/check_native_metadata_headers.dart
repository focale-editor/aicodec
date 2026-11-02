import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:aicodec/aicodec.dart';

import '../test/ai_native_metadata_header_test.dart' show withMetadataHeaders;
import '../test/ai_native_save_test.dart' show multipleNativePrograms;

/// Old cache profiles with independently observed resource or canvas differences.
const Set<String> _unqualified = {
  'inkscape_minimized_ai9.ai',
  'inkscape_minimized_ai10.ai',
  'inkscape_minimized_ai_cs.ai',
  'inkscape_minimized_ai_cs2.ai',
  'inkscape_minimized_ai_cs3.ai',
  'empty_cs.ai',
  'empty_cs2.ai',
  'simple_cs.ai',
  'simple_cs2.ai',
  'simple_cs3.ai',
};

/// Replaces only the Creator declaration in these bounded pinned source headers.
List<int> changedMetadataCreator(AiNativeSource source) {
  final String header = latin1.decode(source.bytes.take(65536).toList());
  final RegExpMatch? creator = RegExp(r'(?:^|(?<=[\r\n]))%%Creator:[^\r\n]*', multiLine: true).firstMatch(header);
  if (creator == null || creator.end > header.indexOf('%%EndComments')) {
    throw StateError('The pinned fixture has no initial Creator declaration.');
  }
  final BytesBuilder result = BytesBuilder(copy: false)
    ..add(Uint8List.sublistView(source.bytes, 0, creator.start))
    ..add(latin1.encode('%%Creator: AiCodec cache validation'))
    ..add(Uint8List.sublistView(source.bytes, creator.end));
  return result.takeBytes();
}

/// Saves changed headers without interpreting or regenerating native drawing.
Future<void> main() async {
  final Directory output = await Directory('test/corpus/output/metadata-headers').create(recursive: true);
  final List<Map<String, Object?>> rows = [];

  /// Records complete source programs, cache updates and unchanged native owners.
  Future<void> save(String name, AiPdfDocument document, {bool synthetic = false, bool firstOnly = false}) async {
    if (synthetic) {
      await File('${output.path}/$name.original.ai').writeAsBytes(const AiCodec().encode(document));
    }
    final List<AiNativeSource> sources = AiNativeData.extract(document);
    final List<AiNativeReplacement> replacements = [];
    for (final (int, AiNativeSource) source in sources.indexed) {
      final bool selected = !firstOnly || source.$1 == 0;
      final List<int> changed = selected ? changedMetadataCreator(source.$2) : source.$2.bytes;
      if (selected) {
        replacements.add(AiNativeReplacement(source: source.$2, program: changed));
      }
      await File('${output.path}/$name.${source.$1}.before.ps').writeAsBytes(source.$2.bytes);
      await File('${output.path}/$name.${source.$1}.after.ps').writeAsBytes(changed);
    }
    AiPdfDocument? saved;
    String? issue;
    try {
      saved = AiNativeData.replaceAll(replacements: replacements, synchronizedPdf: document.pdf);
    } on UnsupportedError catch (error) {
      if (!_unqualified.contains(name)) {
        rethrow;
      }
      issue = error.message;
    }
    if (_unqualified.contains(name) != (saved == null)) {
      throw StateError('Unexpected metadata-header qualification for $name.');
    }
    if (saved != null) {
      await File('${output.path}/$name.saved.ai').writeAsBytes(const AiCodec().encode(saved));
    }
    rows.add({
      'file': name,
      'synthetic': synthetic,
      'firstOnly': firstOnly,
      'rejected': saved == null,
      'issue': issue,
      'owners': sources.map((source) => source.owners).toList(),
    });
    stdout.writeln('$name: ${saved == null ? 'unchanged refusal' : 'saved'}');
  }

  final Map<String, Object?> manifest = (jsonDecode(await File('test/corpus/manifest.json').readAsString()) as Map).cast<String, Object?>();
  for (final Object? entry in manifest['files']! as List) {
    final String name = (entry! as Map)['file'] as String;
    final AiDocument document = const AiCodec().decode(await File('test/corpus/files/$name').readAsBytes());
    if (document is AiPdfDocument) {
      await save(name, document);
    }
  }
  await save('reuters-preview-dev.ai', const AiCodec().decode(await File('test/corpus/files/reuters-preview-dev.ai').readAsBytes()) as AiPdfDocument);
  final AiPdfDocument base = multipleNativePrograms();
  final String header = latin1.decode(AiNativeData.extract(base).first.bytes).split('%%BeginSetup').first;
  final PdfStream cache = PdfStream(
    dictionary: PdfDictionary(values: {'Sentinel': PdfNumber(value: 17)}),
    data: latin1.encode(header),
  );
  final AiPdfDocument synthetic = withMetadataHeaders(base, {null: cache, 0: cache, 1: cache});
  await save('synthetic-batch', synthetic, synthetic: true);
  await save('synthetic-selected', synthetic, synthetic: true, firstOnly: true);
  await File('${output.path}/report.json').writeAsString('${const JsonEncoder.withIndent('  ').convert(rows)}\n');
}
