import 'dart:convert';
import 'dart:io';

import 'package:aicodec/aicodec.dart';

/// Creates editable native CC artwork and packages an independently supplied PDF.
///
/// Run `dart run example/create_document.dart output.ai`. No input AI is required.
/// Production hosts supply fresh identities and compose their own matching PDF.
Future<void> main(List<String> arguments) async {
  if (arguments.length != 1) {
    throw ArgumentError('Usage: dart run example/create_document.dart output.ai');
  }
  final DateTime timestamp = DateTime.now().toUtc();
  final AiNativeRecords records = AiNativeDocument.create(
    titleBytes: latin1.encode('New document'),
    colorMode: .rgb,
    createdAt: timestamp,
    artboards: [
      AiNativeArtboardDefinition(
        nameBytes: [0, 65, 0, 49],
        identifierBytes: latin1.encode('13ed8bb7-1799-4fb2-971f-9b1d1e72a725'),
        bounds: AiBoundingBox(left: 0, bottom: 0, right: 200, top: 100),
        rulerOrigin: [8191.5, 8191.5],
        selected: true,
      ),
    ],
    layers: [
      AiNativeDocumentLayer(
        definition: AiNativeLayerDefinition(
          attributes: [1, 1, 1, 1, 0, 0, 1, 0, 10, 20, 30, 0, 50, 0],
          nameBytes: latin1.encode('Artwork'),
          identifierBytes: latin1.encode('layer_1'),
        ),
        paths: [
          AiNativePathDefinition(
            artwork: AiArtworkPath(
              segments: [
                AiPathSegment(operator: 'm', coordinates: [20, 20]),
                AiPathSegment(operator: 'L', coordinates: [80, 20]),
                AiPathSegment(operator: 'L', coordinates: [80, 80]),
              ],
              closed: true,
              fill: AiColor(space: .rgb, channels: [1, 0, 0]),
            ),
            bounds: AiBoundingBox(left: 20, bottom: 20, right: 80, top: 80),
            identifierBytes: latin1.encode('path_1'),
          ),
        ],
      ),
    ],
  );
  // This example authors both representations. AiCodec does not render the native
  // triangle or check visual equivalence with this explicit host PDF content.
  final PdfDocument pdf = PdfDocument.fromPages(
    pages: [PdfPageSource(width: 200, height: 100, content: latin1.encode('1 0 0 rg 20 20 m 80 20 l 80 80 l h f'))],
  );
  final AiPdfDocument document = AiNativeDocument.createPdf(
    records: records,
    compatibilityPdf: pdf,
    pages: [
      AiNativeDocumentPage(
        artboard: AiNativeArtboards.decode(records: records).artboards.single,
        page: pdf.pages.single.reference!,
      ),
    ],
    modifiedAt: timestamp,
  );
  await File(arguments.single).writeAsBytes(const AiCodec().encode(document), flush: true);
  stdout.writeln('Created ${arguments.single} with editable native artwork and a host-supplied PDF.');
}
