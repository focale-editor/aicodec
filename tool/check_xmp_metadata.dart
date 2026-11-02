import 'dart:convert';
import 'dart:io';

import 'package:aicodec/aicodec.dart';

/// Generates preserved and edited packets for independent XML/PDF inspection.
Future<void> main() async {
  final Directory output = await Directory('test/corpus/output/xmp').create(recursive: true);
  final AiPdfDocument original = const AiCodec().decode(await File('test/corpus/files/xmp/BlueSquare.ai').readAsBytes()) as AiPdfDocument;
  final AiXmpMetadata adobe = AiXmpMetadata.fromPdf(document: original)!;
  if (adobe.resources.isNotEmpty) {
    throw StateError('The pinned Adobe packet should have no dependency manifest.');
  }
  await File('${output.path}/adobe.xmp').writeAsString(adobe.source);
  await File('${output.path}/preserved.ai').writeAsBytes(const AiCodec().encode(adobe.writeTo(document: original)));
  final AiXmpMetadata source = AiXmpMetadata.parse(source: await File('test/corpus/files/xmp/XMP3.xmp').readAsString());
  if (source.resources.length != 1 || source.resources.single.filePath != r'C:\some path\file.ext') {
    throw StateError('The pinned ExifTool packet should have one known manifest resource.');
  }
  const String path = '/assets/Été & <soir> 😀.png';
  final AiXmpMetadata changed = source.relink(resources: source.resources, filePath: path, documentId: 'xmp.did:aicodec-corpus-resource', instanceId: null);
  await File('${output.path}/relinked.xmp').writeAsString(changed.source);
  // This is an explicit synthetic catalog carrier, not a relink of BlueSquare art.
  await File('${output.path}/metadata-carrier.ai').writeAsBytes(const AiCodec().encode(changed.writeTo(document: original)));
  await File('${output.path}/report.json').writeAsString(const JsonEncoder.withIndent('  ').convert({'path': path, 'documentId': 'xmp.did:aicodec-corpus-resource', 'instanceId': null}));
  stdout.writeln('XMP: Adobe packet retained; one dependency relinked; two PDF catalog carriers saved.');
}
