import 'dart:convert';

import 'package:aikit/aikit.dart';
import 'package:checks/checks.dart';
import 'package:test/test.dart';

/// Native programs with explicit setup boundaries and an untouched authoring key.
AiProgram _program(String body) => AiProgram.decode(
  bytes: latin1.encode('''%!PS-Adobe-3.0
%%Creator: Adobe Illustrator
%%BeginSetup
/Dictionary : 7 /Integer (Sentinel) , ;
%%EndSetup
$body
%%Trailer
%%EOF
'''),
);

/// A closed rectangle with predictable native winding and paint.
const String _rectangle = '10 10 m 60 10 L 60 60 L 10 60 L f';

/// A fixed drawing/page frame for focused compilation tests.
AiBoundingBox _bounds() => AiBoundingBox(left: 0, bottom: 0, right: 100, top: 100);

/// Embeds independent native data in aliased pages, retaining unrelated metadata.
AiPdfDocument _document(AiProgram program, {int pages = 1}) {
  final PdfDocument pdf = PdfDocument.fromPages(pages: [for (int index = 0; index < pages; index++) PdfPageSource(width: 100, height: 100, content: latin1.encode('q Q'))]);
  const PdfReference block = PdfReference(objectNumber: 90);
  final Map<PdfReference, PdfValue> objects = {
    ...pdf.objects,
    block: PdfStream(
      dictionary: PdfDictionary(),
      data: AiNativeData.encodeEnvelope(program.bytes, compression: .zstandard),
    ),
  };
  for (final PdfPage page in pdf.pages) {
    objects[page.reference!] = page.dictionary.copyWith(
      values: {
        'PieceInfo': PdfDictionary(
          values: {
            'Illustrator': PdfDictionary(
              values: {
                'Private': PdfDictionary(values: {'AIPrivateData1': block, 'Keep': PdfNumber(value: 42)}),
              },
            ),
            'OtherProducer': PdfDictionary(values: {'Keep': PdfNumber(value: 17)}),
          },
        ),
      },
    );
  }
  return AiPdfDocument(pdf: pdf.copyWith(objects: objects));
}

/// All newly generated transparency forms in a standalone PDF graph.
List<PdfStream> _forms(PdfDocument document) => document.objects.values.whereType<PdfStream>().where((stream) => stream.dictionary.name('Subtype') == 'Form').toList();

/// Checks native-to-PDF rendering transactions and retained graph semantics.
void main() {
  test('maps process colors, curve shorthand, stroke attributes and nonzero origins', () {
    final AiProgram program = _program('0 1 1 0 1 0 0 Xa 0 0 1 XA 3 w 1 J 2 j 5 M [3 2] 1 d 1 XR 10 20 m 12 22 20 20 V 25 20 30 25 Y b');
    final PdfDocument pdf = AiNativePdf.render(program: program, bounds: AiBoundingBox(left: 10, bottom: 20, right: 110, top: 120));
    final List<PdfOperation> operations = PdfProgram.fromPage(document: pdf, pageIndex: 0).operations;
    check(operations.firstWhere((operation) => operation.operator == 'rg').operands.cast<PdfNumber>().map((value) => value.value).toList()).deepEquals([1, 0, 0]);
    check(operations.firstWhere((operation) => operation.operator == 'cm').operands.cast<PdfNumber>().map((value) => value.value).toList()).deepEquals([1, 0, 0, 1, -10, -20]);
    check(operations.map((operation) => operation.operator).toList()).containsEqualInOrder(['v', 'y', 'h', 'B*']);
    final PdfArray dash = operations.singleWhere((operation) => operation.operator == 'd').operands.first as PdfArray;
    check(dash.values.cast<PdfNumber>().map((value) => value.value).toList()).deepEquals([3, 2]);
    final String encoded = latin1.decode(PdfContent.encode(operations));
    check(encoded).contains('1 J');
    check(encoded).contains('2 j');
  });

  test('paints compounds once with the final style and keeps clipping in its group', () {
    final PdfDocument pdf = AiNativePdf.render(program: _program('q 0 0 m 80 0 L 80 80 L h W N 1 XR *u 1 0 0 Xa $_rectangle 0 1 0 Xa 20 20 m 40 20 L 40 40 L f *U Q'), bounds: _bounds());
    final List<PdfOperation> operations = PdfProgram.fromPage(document: pdf, pageIndex: 0).operations;
    check(operations.where((operation) => operation.operator == 'W')).length.equals(1);
    check(operations.where((operation) => operation.operator == 'f*')).length.equals(1);
    check(operations.where((operation) => operation.operator == 'rg')).length.equals(1);
    check(operations.singleWhere((operation) => operation.operator == 'rg').operands.cast<PdfNumber>().map((value) => value.value).toList()).deepEquals([0, 1, 0]);
    check(operations.last.operator).equals('Q');
  });

  test('applies opacity to the complete fill and stroke without double compositing', () {
    final PdfDocument pdf = AiNativePdf.render(program: _program('0 0.5 0 0 0 Xy 1 0 0 Xa 0 0 1 XA 10 w 10 10 m 60 10 L 60 60 L b'), bounds: _bounds());
    final PdfStream form = _forms(pdf).single;
    final List<PdfOperation> paint = PdfContent.decode(pdf.decodeStream(form));
    check(paint.where((operation) => operation.operator == 'B')).length.equals(1);
    check(paint.any((operation) => operation.operator == 'gs')).isFalse();
    final PdfDictionary alpha = pdf.objects.values.whereType<PdfDictionary>().singleWhere((dictionary) => dictionary.name('Type') == 'ExtGState');
    check((alpha['ca']! as PdfNumber).value).equals(0.5);
    check((alpha['CA']! as PdfNumber).value).equals(0.5);
  });

  test('keeps native style state across groups and uses the state at the group marker', () {
    final PdfDocument pdf = AiNativePdf.render(program: _program('u 1 0.29 1 1 0 Xy 1 0 0 Xa $_rectangle U 0 0 Xd 6 () XW $_rectangle'), bounds: _bounds());
    final List<PdfStream> forms = _forms(pdf);
    check(forms).length.equals(3);
    final List<PdfDictionary> states = pdf.objects.values.whereType<PdfDictionary>().where((value) => value.name('Type') == 'ExtGState').toList();
    check(states).length.equals(1);
    check(states.single.name('BM')).equals('Multiply');
    check((states.single['ca']! as PdfNumber).value).equals(0.29);
    check((pdf.dictionary(forms[1].dictionary['Group']!)['K']! as PdfBoolean).value).isTrue();
    check((pdf.dictionary(forms[1].dictionary['Group']!)['I']! as PdfBoolean).value).isTrue();
  });

  test('retains style changes after a compound for the next object', () {
    final PdfDocument pdf = AiNativePdf.render(program: _program('*u 0 0.25 0 0 0 Xy $_rectangle *U 0 1 0 0 0 Xy $_rectangle'), bounds: _bounds());
    check(_forms(pdf)).length.equals(1);
    check(PdfProgram.fromPage(document: pdf, pageIndex: 0).operations.where((operation) => operation.operator == 'f')).length.equals(1);
  });

  test('captures appearance state at Xd and applies it to a preceding path exactly once', () {
    final PdfDocument pdf = AiNativePdf.render(program: _program('0 0.8 0 0 0 Xy $_rectangle 0 1 Xd 0 0.3 0 0 0 Xy 6 () XW $_rectangle'), bounds: _bounds());
    final List<PdfDictionary> states = pdf.objects.values.whereType<PdfDictionary>().where((value) => value['ca'] != null).toList();
    check(states.map((state) => (state['ca']! as PdfNumber).value).toList()).deepEquals([0.8, 0.3]);
    check(_forms(pdf)).length.equals(2);
    for (final PdfStream form in _forms(pdf)) {
      check(PdfContent.decode(pdf.decodeStream(form)).where((operation) => operation.operator == 'f')).length.equals(1);
    }
    check(() => AiNativePdf.render(program: _program('$_rectangle 0 1 Xd $_rectangle 6 () XW'), bounds: _bounds())).throws<FormatException>();
    check(() => AiNativePdf.render(program: _program('$_rectangle 0 2 Xd 6 () XW'), bounds: _bounds())).throws<UnsupportedError>();
  });

  test('accepts plain group markers without inventing independent group opacity', () {
    final PdfDocument pdf = AiNativePdf.render(program: _program('u 0 0.5 0 0 0 Xy $_rectangle U 9 () XW'), bounds: _bounds());
    check(_forms(pdf)).length.equals(1);
    check(() => AiNativePdf.render(program: _program('$_rectangle 9 () XW'), bounds: _bounds())).throws<UnsupportedError>();
  });

  test('omits hidden and nonprinting layers while still rejecting unsupported content', () {
    const String hidden = '0 1 1 1 0 0 0 0 0 0 Lb (Hidden) Ln $_rectangle LB';
    const String nonprinting = '1 1 1 0 0 0 0 0 0 0 Lb (Nonprinting) Ln $_rectangle LB';
    final PdfDocument pdf = AiNativePdf.render(program: _program('$hidden $nonprinting $_rectangle'), bounds: _bounds());
    check(PdfProgram.fromPage(document: pdf, pageIndex: 0).operations.where((operation) => operation.operator == 'f')).length.equals(1);
    check(() => AiNativePdf.render(program: _program(hidden.replaceFirst(_rectangle, '42 UnknownPaint')), bounds: _bounds())).throws<UnsupportedError>();
    check(() => AiNativePdf.render(program: _program('$hidden 0 0 Xd 6 () XW'), bounds: _bounds())).throws<FormatException>();
  });

  test('saves edited paths and aliased native owners without changing source metadata', () {
    final AiProgram original = _program('1 0 0 Xa $_rectangle');
    final AiPdfDocument document = _document(original, pages: 2);
    final AiNativeSource source = AiNativeData.extract(document).single;
    final AiProgram changed = _program('0 1 0 Xa 20 20 m 70 20 L 70 70 L f');
    final AiPdfDocument saved = AiNativePdf.save(source: source, program: changed, pageBounds: [_bounds(), _bounds()]);
    final AiPdfDocument reopened = const AiCodec().decode(const AiCodec().encode(saved)) as AiPdfDocument;
    check(AiNativeData.extract(reopened).single.bytes).deepEquals(changed.bytes);
    check(AiNativeData.extract(reopened).single.owners).deepEquals([0, 1]);
    for (final PdfPage page in reopened.pdf.pages) {
      final PdfDictionary pieces = reopened.pdf.dictionary(page.dictionary['PieceInfo']!);
      check(reopened.pdf.dictionary(pieces['OtherProducer']!).integer('Keep')).equals(17);
      final PdfDictionary illustrator = reopened.pdf.dictionary(pieces['Illustrator']!);
      check(reopened.pdf.dictionary(illustrator['Private']!).integer('Keep')).equals(42);
    }
    check(document.pdf.pageContent(document.pdf.pages.first)).deepEquals(latin1.encode('q Q'));
    check(AiNativeData.extract(document).single.bytes).deepEquals(original.bytes);
  });

  test('uses PdfCore allocation and retains original resource bindings and dangling references', () {
    final AiProgram program = _program('0 0.5 0 0 0 Xy $_rectangle');
    final AiPdfDocument source = _document(program);
    final PdfDocument pdf = source.pdf;
    const PdfReference dangling = PdfReference(objectNumber: 5);
    final PdfReference page = pdf.pages.single.reference!;
    final Map<PdfReference, PdfValue> objects = {
      ...pdf.objects,
      page: pdf.pages.single.dictionary.copyWith(
        values: {
          'Sentinel': dangling,
          'Thumb': dangling,
          'Resources': PdfDictionary(
            values: {
              'ExtGState': PdfDictionary(
                values: {
                  'OldState': PdfDictionary(values: {'Keep': PdfNumber(value: 7)}),
                },
              ),
            },
          ),
        },
      ),
    };
    final AiNativeSource native = AiNativeData.extract(AiPdfDocument(pdf: pdf.copyWith(objects: objects))).single;
    final PdfDocument saved = AiNativePdf.save(source: native, program: program, pageBounds: [_bounds()]).pdf;
    check(saved.objects.containsKey(dangling)).isFalse();
    check(saved.pages.single.dictionary['Thumb']).isNull();
    check(PdfEditor(document: saved).pageResource(pageIndex: 0, category: 'ExtGState', name: 'OldState')).isA<PdfDictionary>().has((value) => value.integer('Keep'), 'Keep').equals(7);
  });

  test('rejects unrendered operations, malformed state and incomplete clips', () {
    for (final String body in ['1 0 0 1 2 3 cm', '0 1 0 0 1 Xy $_rectangle', '16 1 0 0 0 Xy $_rectangle', '1 O $_rectangle', '1 (Missing) XW', '0 0 XI', '42 FuturePaint']) {
      check(() => AiNativePdf.render(program: _program(body), bounds: _bounds())).throws<UnsupportedError>();
    }
    for (final String body in ['-1 w $_rectangle', '4 J $_rectangle', '[0 0] 0 d $_rectangle', '0 0 m 1 0 L h W N', '0 0 Xd 6 () XW']) {
      check(() => AiNativePdf.render(program: _program(body), bounds: _bounds())).throws<FormatException>();
    }
    check(() => AiNativePdf.render(program: _program('%%BeginDocument: other\n$_rectangle\n%%EndDocument'), bounds: _bounds())).throws<UnsupportedError>();
  });

  test('bounds PDF operations and rejects invalid page mappings before publishing changes', () {
    final AiProgram program = _program('0 0.5 0 0 0 Xy $_rectangle');
    check(() => AiNativePdf.render(program: program, bounds: _bounds(), limits: const PdfLimits(maxObjects: 6))).throws<FormatException>();
    check(() => AiNativePdf.render(program: program, bounds: _bounds(), limits: const PdfLimits(maxDecodedBytes: 2))).throws<FormatException>();
    final AiPdfDocument document = _document(program);
    final AiNativeSource source = AiNativeData.extract(document).single;
    check(() => AiNativePdf.save(source: source, program: program, pageBounds: [])).throws<ArgumentError>();
    check(() => AiNativePdf.save(source: source, program: program, pageBounds: [AiBoundingBox(left: 0, bottom: 0, right: 200, top: 100)])).throws<ArgumentError>();
    check(document.pdf.pageContent(document.pdf.pages.single)).deepEquals(latin1.encode('q Q'));
  });
}
