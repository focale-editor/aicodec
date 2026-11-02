import 'dart:convert';
import 'dart:io';

import 'package:aicodec/aicodec.dart';

import '../test/ai_native_save_test.dart' show multipleNativePrograms;

/// Qualifies native saving using nonvisual edits and host-supplied PDF resources.
Future<void> main() async {
  final Map<String, Object?> manifest = (jsonDecode(await File('test/corpus/manifest.json').readAsString()) as Map).cast<String, Object?>();
  final Directory output = await Directory('test/corpus/output/native-saves').create(recursive: true);
  final List<Map<String, Object?>> rows = [];

  /// Saves a source snapshot without inferring any native-to-page correspondence.
  Future<void> save(String name, AiPdfDocument document, {bool firstOnly = false, bool synthetic = false}) async {
    if (synthetic) {
      await File('${output.path}/$name.original.ai').writeAsBytes(const AiCodec().encode(document));
    }
    final List<AiNativeSource> sources = AiNativeData.extract(document);
    final List<AiNativeReplacement> replacements = [];
    final List<Map<String, Object?>> programs = [];
    for (final (int, AiNativeSource) entry in sources.indexed) {
      final AiNativeSource source = entry.$2;
      final AiProgram before = AiProgram.decode(bytes: source.bytes);
      final bool selected = !firstOnly || entry.$1 == 0;
      final AiProgram after = selected && before.layers.isNotEmpty ? AiNativeEditor.updateLayer(program: before, layer: before.layers.first, name: 'Saved layer') : before;
      if (selected) {
        replacements.add(AiNativeReplacement(source: source, program: after.bytes));
      }
      final String prefix = '$name.${entry.$1}';
      await File('${output.path}/$prefix.before.ps').writeAsBytes(before.bytes);
      await File('${output.path}/$prefix.after.ps').writeAsBytes(after.bytes);
      programs.add({
        'prefix': prefix,
        'owners': source.owners,
        'selected': selected,
        'renamed': selected && before.layers.isNotEmpty,
        'oldNameStart': before.layers.firstOrNull?.naming?.start,
        'oldNameEnd': before.layers.firstOrNull?.naming?.end,
        'newNameStart': after.layers.firstOrNull?.naming?.start,
        'newNameEnd': after.layers.firstOrNull?.naming?.end,
      });
    }
    final PdfEditor host = PdfEditor(document: document.pdf);
    final String resource = host.setPageResource(
      pageIndex: 0,
      category: 'XObject',
      prefix: 'Host',
      value: PdfStream(
        dictionary: PdfDictionary(
          values: {
            'Type': PdfName(value: 'XObject'),
            'Subtype': PdfName(value: 'Form'),
            'BBox': PdfArray(values: [0, 0, 10, 10].map((value) => PdfNumber(value: value))),
          },
        ),
        data: latin1.encode('q Q'),
      ),
    );
    // An unused resource tests packaging without changing existing page artwork.
    final AiPdfDocument saved = AiNativeData.replaceAll(replacements: replacements, synchronizedPdf: host.document);
    await File('${output.path}/$name.saved.ai').writeAsBytes(const AiCodec().encode(saved));
    rows.add({'file': name, 'synthetic': synthetic, 'resource': resource, 'programs': programs});
    stdout.writeln('$name: ${replacements.length} replacements, ${document.pdf.pages.length} pages');
  }

  for (final Object? entry in manifest['files']! as List) {
    final String name = (entry! as Map)['file'] as String;
    final AiDocument document = const AiCodec().decode(await File('test/corpus/files/$name').readAsBytes());
    if (document is AiPdfDocument) {
      await save(name, document);
    }
  }
  await save('synthetic-batch', multipleNativePrograms(thumbnails: true), synthetic: true);
  await save('synthetic-selected', multipleNativePrograms(thumbnails: true), firstOnly: true, synthetic: true);
  await File('${output.path}/report.json').writeAsString(const JsonEncoder.withIndent('  ').convert(rows));
}
