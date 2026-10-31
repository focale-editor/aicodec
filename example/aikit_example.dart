import 'dart:convert';
import 'dart:typed_data';

import 'package:aikit/aikit.dart';

/// Inspects, authors and edits native AI artwork, then creates PDF interchange.
void main() {
  final Uint8List source = latin1.encode('%!PS-Adobe-3.0\n%%Creator: Adobe Illustrator\n%%BoundingBox: 0 0 100 80\n%%EndComments\n0 0 m 100 80 l S\n%%EOF\n');
  final AiPostScriptDocument legacy = const AiCodec().decode(source) as AiPostScriptDocument;
  final List<AiToken> tokens = AiPostScript.tokenize(legacy.postScriptBytes);
  print('${legacy.creator}; ${tokens.length} PostScript tokens');

  final AiArtwork artwork = AiArtwork(
    bounds: AiBoundingBox(left: 0, bottom: 0, right: 100, top: 80),
    children: [
      AiArtworkLayer(
        name: 'Drawing',
        children: [
          AiArtworkPath(
            segments: [
              AiPathSegment(operator: 'm', coordinates: [10, 10]),
              AiPathSegment(operator: 'L', coordinates: [90, 10]),
              AiPathSegment(operator: 'L', coordinates: [50, 70]),
            ],
            closed: true,
            fill: AiColor(space: .rgb, channels: [1, 0.3, 0]),
          ),
        ],
      ),
    ],
  );
  final AiNativeSource native = AiNativeData.extract(artwork.toPostScript()).single;
  final AiProgram program = AiProgram.decode(bytes: native.bytes);
  final AiProgram edited = AiNativeEditor.updateLayer(program: program, layer: program.layers.single, name: 'Triangle');
  print('${edited.layers.single.name}: ${edited.paths.length} editable AI7 path');

  final PdfDocument pdf = AiNativePdf.render(program: edited, bounds: artwork.bounds);
  final AiPdfDocument interchange = AiPdfDocument.forPdfInterchange(pdf: pdf);
  final Uint8List bytes = const AiCodec().encode(interchange);
  final AiPdfDocument reopened = const AiCodec(allowGeneric: true).decode(bytes) as AiPdfDocument;
  print('${reopened.pdf.pages.length} PDF interchange page; native Illustrator data is not synthesized');
}
