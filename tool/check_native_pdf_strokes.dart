import 'dart:convert';
import 'dart:io';

import 'package:aikit/aikit.dart';

/// Writes gradient-stroke probes with nonzero native and PDF page origins.
Future<void> main() async {
  final Directory output = await Directory('test/corpus/output/native-pdf-strokes').create(recursive: true);

  /// Offsets probe geometry without altering the independently chosen shapes.
  String point(int x, int y) => '${x + 37} ${y - 240}';

  /// A page-aligned gradient, bounded by the native stroked path itself.
  String stroke(int left, {String name = 'Opaque', String end = 'S 1 BB'}) => '1 Bb 1 ($name) 0 0 0 1 1 0 0 1 0 0 Bg 80 0 0 -80 ${point(left, 90)} Xm $end';

  final AiProgram program = AiProgram.decode(
    bytes: latin1.encode('''%!PS-Adobe-3.0
%%Creator: Adobe Illustrator
%%BeginSetup
%AI5_BeginGradient: (Opaque)
(Opaque) 0 2 Bd [ 0 0 50 100 %_Bs
1 0 50 0 %_Bs
BD
%AI5_EndGradient
%AI5_BeginGradient: (Alpha)
(Alpha) 0 2 Bd [
%_0 0 0.5 6 50 100 Bs
%_1 0 0.5 6 50 0 Bs
BD
%AI5_EndGradient
%AI5_BeginGradient: (Radial)
(Radial) 1 2 Bd [ 1 0 50 0 %_Bs
0 0 50 100 %_Bs
BD
%AI5_EndGradient
%%EndSetup
10 w 0 J 0 j [] 0 d
${point(10, 40)} m ${point(90, 40)} L ${stroke(10)}
[10 10] 0 d
${point(110, 40)} m ${point(190, 40)} L ${stroke(110)}
[] 0 d 1 J
${point(210, 40)} m ${point(290, 40)} L ${stroke(210)}
${point(310, 40)} m ${point(310, 120)} ${point(390, 120)} ${point(390, 40)} C ${stroke(310)}
0 J 0 0.5 0 0 0 Xy
${point(10, 150)} m ${point(90, 150)} L ${stroke(10, name: 'Alpha')}
u 0 1 0 0 0 Xy
${point(110, 150)} m ${point(190, 150)} L ${stroke(110)}
U 0 0.5 0 0 0 Xy 0 0 Xd 6 () XW
0 1 0 0 0 Xy 8 w
${point(210, 130)} m ${point(290, 130)} L ${point(290, 210)} L ${stroke(210, end: 'S 2 BB')}
10 w
${point(310, 150)} m ${point(390, 150)} L
1 Bb 1 (Radial) 0 0 0 1 1 0 0 1 0 0 Bg
40 0 0 -30 ${point(350, 150)} Bm S 1 BB
%%Trailer
%%EOF
'''),
  );
  final AiBoundingBox bounds = AiBoundingBox(left: 37, bottom: -240, right: 437, top: 0);
  final PdfDocument single = AiNativePdf.render(program: program, bounds: bounds);
  await File('${output.path}/probes.pdf').writeAsBytes(const PdfEncoder().convert(single));

  final PdfEditor editor = PdfEditor(
    document: PdfDocument.fromPages(pages: [for (int index = 0; index < 2; index++) PdfPageSource(width: 400, height: 240, content: [])]),
  );
  final PdfReference block = editor.addObject(
    value: PdfStream(
      dictionary: PdfDictionary(),
      data: AiNativeData.encodeEnvelope(program.bytes, compression: .zstandard),
    ),
  );
  editor.setPageAttributes(
    pageIndex: 0,
    values: {
      'MediaBox': PdfArray(values: [20, -30, 420, 210].map((value) => PdfNumber(value: value))),
      'PieceInfo': PdfDictionary(
        values: {
          'Illustrator': PdfDictionary(
            values: {
              'Private': PdfDictionary(values: {'AIPrivateData1': block}),
            },
          ),
        },
      ),
    },
  );
  editor.setPageAttributes(
    pageIndex: 1,
    values: {
      'MediaBox': PdfArray(values: [-15, 40, 385, 280].map((value) => PdfNumber(value: value))),
    },
  );
  final AiNativeSource source = AiNativeData.extract(AiPdfDocument(pdf: editor.document)).single;
  final AiPdfDocument multiple = AiNativePdf.save(
    source: source,
    program: program,
    pageBounds: [bounds, AiBoundingBox(left: 137, bottom: -240, right: 537, top: 0)],
  );
  await File('${output.path}/probes.multi.ai').writeAsBytes(const AiCodec().encode(multiple));
  await File('${output.path}/probes.native.ps').writeAsBytes(program.bytes);
  stdout.writeln('Gradient stroke probes saved with nonzero native coordinates and two different PDF page origins.');
}
