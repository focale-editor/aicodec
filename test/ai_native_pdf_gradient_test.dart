import 'dart:convert';
import 'dart:math' as math;

import 'package:aikit/aikit.dart';
import 'package:checks/checks.dart';
import 'package:test/test.dart';

/// Creates an independently specified native gradient and its printing geometry.
AiProgram _program({String stops = '0 0 50 100 %_Bs\n1 0 50 0 %_Bs', String? body, bool radial = false, bool cmyk = false}) => AiProgram.decode(
  bytes: latin1.encode('''%!PS-Adobe-3.0
%%Creator: Adobe Illustrator
%AI9_ColorModel: ${cmyk ? 2 : 1}
%%BeginSetup
%AI5_BeginGradient: (Ink)
(Ink) ${radial ? 1 : 0} 2 Bd
[
$stops
BD
%AI5_EndGradient
%%EndSetup
${body ?? '10 10 m 90 10 L 90 90 L 10 90 L Bb\n${radial ? '0 0 90 0.5 Bh' : ''}\n1 (Ink) 0 0 0 1 1 0 0 1 0 0 1 Bg\n80 0 0 -80 10 90 ${radial ? 'Bm' : 'Xm'}\nf 0 BB'}
%%Trailer
%%EOF
'''),
);

/// Renders into a fixed native/PDF frame without application dependencies.
PdfDocument _render(AiProgram program) => AiNativePdf.render(program: program, bounds: AiBoundingBox(left: 0, bottom: 0, right: 100, top: 100));

/// Reads generated shading dictionaries without relying on their resource names.
List<PdfDictionary> _shadings(PdfDocument document) => document.objects.values.whereType<PdfDictionary>().where((value) => value['ShadingType'] != null).toList();

/// Numeric PDF arrays for direct semantic expectations.
List<double> _numbers(PdfValue value) => (value as PdfArray).values.cast<PdfNumber>().map((number) => number.value.toDouble()).toList();

/// A CC gradient placed only around the final contour's paint instruction.
const String _compoundGradient = '''*u
0 g 30 30 m 30 70 L 70 70 L 70 30 L f
10 10 m 90 10 L 90 90 L 10 90 L
Bb 1 (Ink) 0 0 0 1 1 0 0 1 0 0 Bg
80 0 0 -80 10 90 Xm f 0 BB
*U''';

/// Checks native gradient geometry, exact process colors and alpha separation.
void main() {
  test('writes axial shading bounded by the native fill and retains the printing matrix', () {
    final PdfDocument pdf = _render(_program());
    final PdfDictionary shading = _shadings(pdf).single;
    check(shading.integer('ShadingType')).equals(2);
    check(shading.name('ColorSpace')).equals('DeviceGray');
    check(_numbers(shading['Coords']!)).deepEquals([0, 0, 1, 0]);
    final List<PdfOperation> operations = PdfProgram.fromPage(document: pdf, pageIndex: 0).operations;
    check(operations.map((operation) => operation.operator).toList()).containsEqualInOrder(['h', 'W', 'n', 'cm', 'sh', 'Q']);
    check(_numbers(PdfArray(values: operations.lastWhere((operation) => operation.operator == 'cm').operands))).deepEquals([80, 0, 0, -80, 10, 90]);
    final PdfDictionary function = pdf.dictionary(shading['Function']!);
    final PdfDictionary interval = (function['Functions']! as PdfArray).values.single as PdfDictionary;
    check(_numbers(interval['C0']!)).deepEquals([1]);
    check(_numbers(interval['C1']!)).deepEquals([0]);
  });

  test('writes mirrored midpoints below fifty and constant caps outside the stops', () {
    final PdfDocument pdf = _render(_program(stops: '0 0 50 80 %_Bs\n1 0 25 20 %_Bs'));
    final PdfDictionary function = pdf.dictionary(_shadings(pdf).single['Function']!);
    final List<PdfDictionary> intervals = (function['Functions']! as PdfArray).values.cast<PdfDictionary>().toList();
    check(_numbers(function['Bounds']!)).deepEquals([0.2, 0.8]);
    check(_numbers(function['Encode']!)).deepEquals([0, 1, 1, 0, 0, 1]);
    check(_numbers(intervals[1]['C0']!)).deepEquals([0]);
    check(_numbers(intervals[1]['C1']!)).deepEquals([1]);
    final double exponent = (intervals[1]['N']! as PdfNumber).value.toDouble();
    check((math.pow(0.75, exponent) - 0.5).abs()).isLessThan(1e-12);
    check(_numbers(intervals.first['C0']!)).deepEquals(_numbers(intervals.first['C1']!));
    check(_numbers(intervals.last['C0']!)).deepEquals(_numbers(intervals.last['C1']!));
  });

  test('uses focal radial circles and maps native gray to black ink in CMYK documents', () {
    final PdfDocument pdf = _render(_program(radial: true, cmyk: true));
    final PdfDictionary shading = _shadings(pdf).single;
    check(shading.integer('ShadingType')).equals(3);
    check(shading.name('ColorSpace')).equals('DeviceCMYK');
    final List<double> circles = _numbers(shading['Coords']!);
    check(circles[0].abs()).isLessThan(1e-12);
    check(circles.sublist(1)).deepEquals([-0.5, 0, 0, 0, 1]);
    final PdfDictionary function = pdf.dictionary(shading['Function']!);
    final PdfDictionary interval = (function['Functions']! as PdfArray).values.single as PdfDictionary;
    check(_numbers(interval['C0']!)).deepEquals([0, 0, 0, 0]);
    check(_numbers(interval['C1']!)).deepEquals([0, 0, 0, 1]);
  });

  test('keeps gradient stop opacity in a matching gray mask independent of its process colors', () {
    final PdfDocument pdf = _render(_program(stops: '%_0 0 0.2 6 50 100 Bs\n%_1 0 0.8 6 50 0 Bs', cmyk: true));
    final List<PdfDictionary> shadings = _shadings(pdf);
    check(shadings.map((shade) => shade.name('ColorSpace')).toList()).deepEquals(['DeviceCMYK', 'DeviceGray']);
    check(_numbers(shadings[0]['Coords']!)).deepEquals(_numbers(shadings[1]['Coords']!));
    final PdfDictionary maskFunction = pdf.dictionary(shadings[1]['Function']!);
    final PdfDictionary interval = (maskFunction['Functions']! as PdfArray).values.single as PdfDictionary;
    check(_numbers(interval['C0']!)).deepEquals([0.8]);
    check(_numbers(interval['C1']!)).deepEquals([0.2]);
    final PdfStream mask = pdf.objects.values.whereType<PdfStream>().singleWhere((stream) => stream.dictionary['Group'] != null);
    check(pdf.dictionary(mask.dictionary['Group']!).name('CS')).equals('DeviceGray');
    check(_numbers(mask.dictionary['BBox']!)).deepEquals([0, 0, 100, 100]);
    check(PdfContent.decode(pdf.decodeStream(mask)).map((operation) => operation.operator).toList()).deepEquals(['cm', 'sh']);
  });

  test('restores gradient clipping before stroking the same path', () {
    final PdfDocument pdf = _render(_program(body: '0 0 1 XA 10 w 10 10 m 90 10 L 90 90 L Bb 1 (Ink) 0 0 0 1 1 0 0 1 0 0 Bg 80 0 0 -80 10 90 Bm f 2 BB'));
    final List<PdfOperation> operations = PdfProgram.fromPage(document: pdf, pageIndex: 0).operations;
    check(operations.map((operation) => operation.operator).toList()).containsEqualInOrder(['W', 'n', 'sh', 'Q', 'm', 'l', 'l', 'h', 'S']);
    check(operations.where((operation) => operation.operator == 'S')).length.equals(1);
  });

  test('uses the last contour gradient for the whole compound and preserves its fill rule', () {
    for (final int rule in [0, 1]) {
      final PdfDocument pdf = _render(_program(body: '$rule XR $_compoundGradient'));
      final List<PdfOperation> operations = PdfProgram.fromPage(document: pdf, pageIndex: 0).operations;
      check(_shadings(pdf)).length.equals(1);
      check(operations.where((operation) => operation.operator == 'sh')).length.equals(1);
      check(operations.where((operation) => operation.operator == 'm')).length.equals(2);
      check(operations.where((operation) => operation.operator == 'h')).length.equals(2);
      check(operations.where((operation) => operation.operator == (rule == 1 ? 'W*' : 'W'))).length.equals(1);
      check(operations.any((operation) => const {'f', 'f*', 'B', 'B*'}.contains(operation.operator))).isFalse();
    }
  });

  test('collects grouped compound contours and snapshots the final paint before later state changes', () {
    final String body = _compoundGradient.replaceFirst('*u', '*u u u').replaceFirst('Bb', '0 0.4 0 0 0 Xy Bb').replaceFirst('*U', 'U U 9 () XW 0 0.9 0 0 0 Xy *U');
    final PdfDocument pdf = _render(_program(body: body));
    final List<PdfStream> forms = pdf.objects.values.whereType<PdfStream>().where((stream) => stream.dictionary.name('Subtype') == 'Form').toList();
    check(forms).length.equals(1);
    final List<PdfOperation> operations = PdfContent.decode(pdf.decodeStream(forms.single));
    check(operations.where((operation) => operation.operator == 'm')).length.equals(2);
    check(operations.where((operation) => operation.operator == 'sh')).length.equals(1);
    final PdfDictionary state = pdf.objects.values.whereType<PdfDictionary>().singleWhere((value) => value.name('Type') == 'ExtGState');
    check((state['ca']! as PdfNumber).value).equals(0.4);
  });

  test('does not retain an earlier contour gradient when the final contour uses solid paint', () {
    final String body = _compoundGradient.replaceFirst('*U', '1 0 0 Xa 15 15 m 20 15 L 20 20 L f *U');
    final PdfDocument pdf = _render(_program(body: body));
    final List<PdfOperation> operations = PdfProgram.fromPage(document: pdf, pageIndex: 0).operations;
    check(_shadings(pdf)).isEmpty();
    check(operations.where((operation) => operation.operator == 'f')).length.equals(1);
    check(operations.where((operation) => operation.operator == 'm')).length.equals(3);
    check(_numbers(PdfArray(values: operations.singleWhere((operation) => operation.operator == 'rg').operands))).deepEquals([1, 0, 0]);
  });

  test('composites compound gradient alpha and a solid stroke once for the complete object', () {
    final String body = '0 0.5 0 0 0 Xy 0 0 1 XA 10 w ${_compoundGradient.replaceFirst('0 BB', '2 BB')}';
    final PdfDocument pdf = _render(_program(body: body, stops: '%_0 0 0.2 6 50 100 Bs\n%_1 0 0.8 6 50 0 Bs'));
    check(_shadings(pdf)).length.equals(2);
    final List<PdfStream> forms = pdf.objects.values.whereType<PdfStream>().where((stream) => stream.dictionary.name('Subtype') == 'Form').toList();
    check(forms).length.equals(2);
    final List<PdfOperation> paint = forms.map((form) => PdfContent.decode(pdf.decodeStream(form))).singleWhere((operations) => operations.any((operation) => operation.operator == 'S'));
    check(paint.where((operation) => operation.operator == 'sh')).length.equals(1);
    check(paint.where((operation) => operation.operator == 'm')).length.equals(4);
    check(paint.where((operation) => operation.operator == 'S')).length.equals(1);
    check(paint.map((operation) => operation.operator).toList()).containsEqualInOrder(['W', 'n', 'sh', 'Q', 'm', 'm', 'S']);
    final PdfDictionary alpha = pdf.objects.values.whereType<PdfDictionary>().singleWhere((state) => state['ca'] != null);
    check((alpha['ca']! as PdfNumber).value).equals(0.5);
  });

  test('keeps gradient appearance notes from painting or leaking into the next object', () {
    for (final String selector in ['', '1 ']) {
      final PdfDocument pdf = _render(_program(body: '${selector}Bb 2 (Missing note) 0 0 0 1 1 0 0 1 0 0 Bg 0 BB 1 0 0 Xa 10 10 m 90 10 L 90 90 L f'));
      check(_shadings(pdf)).isEmpty();
      check(PdfProgram.fromPage(document: pdf, pageIndex: 0).operations.where((operation) => operation.operator == 'f')).length.equals(1);
    }
    check(() => _render(_program(body: '10 10 m Bb 2 (Ink) 0 0 0 1 1 0 0 1 0 0 Bg 0 BB'))).throws<FormatException>();
  });

  test('rejects independent paints inside one gradient and unsupported nested compound masks', () {
    const String gradient = 'Bb 1 (Ink) 0 0 0 1 1 0 0 1 0 0 Bg 80 0 0 -80 10 90 Xm';
    check(() => _render(_program(body: '$gradient 10 10 m 90 10 L 90 90 L f 20 20 m 30 20 L 30 30 L f 0 BB'))).throws<UnsupportedError>();
    check(() => _render(_program(body: _compoundGradient.replaceFirst('*u', '*u q').replaceFirst('*U', 'Q *U')))).throws<UnsupportedError>();
  });

  test('rejects missing resources, singular matrices, unsupported colors and ambiguous stops', () {
    const String body = '10 10 m 90 10 L 90 90 L Bb 1 (Ink) 0 0 0 1 1 0 0 1 0 0 Bg 80 0 0 -80 10 90 Xm f 0 BB';
    check(() => _render(_program(body: body.replaceFirst('(Ink)', '(Missing)')))).throws<FormatException>();
    check(() => _render(_program(body: body.replaceFirst('80 0 0 -80', '0 0 0 0')))).throws<FormatException>();
    check(() => _render(_program(body: body.replaceFirst('80 0 0 -80 10 90 Xm', '')))).throws<UnsupportedError>();
    check(() => _render(_program(body: body.replaceFirst('Bb', '1 Bb')))).throws<UnsupportedError>();
    check(() => _render(_program(stops: '0 0 50 50 %_Bs\n1 0 50 50 %_Bs'))).throws<UnsupportedError>();
    check(() => _render(_program(stops: '0 1 1 0 (Spot) 0 3 50 100 %_Bs\n0 1 1 0 (Spot) 1 3 50 0 %_Bs'))).throws<UnsupportedError>();
  });
}
