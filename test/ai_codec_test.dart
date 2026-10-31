import 'dart:convert';
import 'dart:typed_data';

import 'package:aikit/aikit.dart';
import 'package:checks/checks.dart';
import 'package:test/test.dart';

/// Creates a PDF graph with native authoring blocks on two different pages.
PdfDocument illustratorPdf() {
  final PdfDocument document = PdfDocument.fromPages(
    pages: [
      PdfPageSource(width: 10, height: 10, content: latin1.encode('q Q')),
      PdfPageSource(width: 20, height: 10, content: latin1.encode('q Q')),
    ],
  );
  final Map<PdfReference, PdfValue> objects = {...document.objects};
  for (int index = 0; index < 2; index++) {
    final PdfReference reference = PdfReference(objectNumber: 3 + index * 2);
    final PdfDictionary page = objects[reference]! as PdfDictionary;
    final PdfReference block = PdfReference(objectNumber: 10 + index);
    final PdfReference secondBlock = PdfReference(objectNumber: 20 + index);
    objects[secondBlock] = PdfStream(dictionary: PdfDictionary(), data: [42 + index]);
    objects[block] = PdfStream(dictionary: PdfDictionary(), data: [index, 255, 0, 10]);
    objects[reference] = page.copyWith(
      values: {
        'PieceInfo': PdfDictionary(
          values: {
            'OtherProducer': PdfDictionary(values: {'Version': PdfNumber(value: 1)}),
            'Illustrator': PdfDictionary(
              values: {
                'Private': PdfDictionary(
                  values: {
                    'AIPrivateData10': block,
                    'AIPrivateData2': secondBlock,
                  },
                ),
              },
            ),
          },
        ),
      },
    );
  }
  return document.copyWith(objects: objects);
}

/// Tests both AI families, provenance, private blocks and DSC boundaries.
void main() {
  const String legacy =
      '%!PS-Adobe-3.0\r\n%%Creator: Adobe Illustrator(TM) 8.0\r\n%%Title: (Drawing)\r\n%%BoundingBox: (atend)\r\n%AI5_FileFormat: 3\r\n%%EndComments\r\n0 0 m 10 10 l S\r\n%%Trailer\r\n%%BoundingBox: -10 -20 200 100\r\n%%EOF\r\n';

  test('preserves legacy bytes and reads metadata from a trailer', () {
    final Uint8List bytes = latin1.encode(legacy);
    final AiPostScriptDocument document = const AiCodec().decode(bytes) as AiPostScriptDocument;
    check(document.kind).equals(AiContainerKind.postscript);
    check(document.title).equals('(Drawing)');
    check(document.boundingBox!.left).equals(-10);
    check(document.boundingBox!.top).equals(100);
    check(const AiCodec().encode(document)).deepEquals(bytes);
    check(() => document.bytes[0] = 0).throws<UnsupportedError>();
  });

  test('preserves PDF artwork and private blocks on every page', () {
    final PdfDocument pdf = illustratorPdf();
    final AiPdfDocument document = const AiCodec().decode(const PdfCodec().encode(pdf)) as AiPdfDocument;
    check(document.privateBlocks.map((block) => block.number)).deepEquals([2, 10, 2, 10]);
    check(document.privateBlocks.map((block) => block.pageIndex)).deepEquals([0, 0, 1, 1]);
    final AiPdfDocument reopened = const AiCodec().decode(const AiCodec().encode(document)) as AiPdfDocument;
    check(reopened.pdf.pages.length).equals(2);
    check(reopened.privateBlocks.last.stream.data).deepEquals([1, 255, 0, 10]);
  });

  test('PDF interchange removes stale native data and keeps other producers', () {
    final AiPdfDocument document = AiPdfDocument.forPdfInterchange(pdf: illustratorPdf());
    check(document.privateBlocks).isEmpty();
    final PdfDictionary pieces = document.pdf.dictionary(document.pdf.pages.first.dictionary['PieceInfo']!);
    check(pieces['OtherProducer']).isNotNull();
    check(pieces['Illustrator']).isNull();
    check((const AiCodec(allowGeneric: true).decode(const AiCodec().encode(document)) as AiPdfDocument).pdf.pages.length).equals(2);
  });

  test('generic PDF needs an explicit opt-in', () {
    final Uint8List bytes = const PdfCodec().encode(PdfDocument.fromPages(pages: []));
    check(() => const AiCodec().decode(bytes)).throws<FormatException>();
    check(const AiCodec(allowGeneric: true).decode(bytes).kind).equals(AiContainerKind.pdf);
  });

  test('recognizes Illustrator Creator metadata without private blocks', () {
    final PdfDocument pdf = PdfDocument.fromPages(pages: []);
    final PdfDocument marked = pdf.copyWith(
      trailer: pdf.trailer.copyWith(
        values: {
          'Info': PdfDictionary(values: {'Creator': PdfString.text(text: 'Adobe Illustrator 27')}),
        },
      ),
    );
    check(const AiCodec().decode(const PdfCodec().encode(marked)).kind).equals(AiContainerKind.pdf);
  });

  test('skips nested EPS metadata and reads DSC continuations', () {
    final String program = legacy.replaceFirst(
      '%%EndComments',
      '%%DocumentNeededResources: font Helvetica\n%%+ font Courier\n%%BeginDocument: child.eps\n%%Title: Child\n%%BoundingBox: 0 0 1 1\n%%EndDocument\n%%EndComments',
    );
    final AiPostScriptDocument document = const AiCodec().decode(latin1.encode(program)) as AiPostScriptDocument;
    check(document.title).equals('(Drawing)');
    check(document.comments['DocumentNeededResources']!.single).equals('font Helvetica\nfont Courier');
  });

  test('skips binary blocks containing counterfeit DSC comments', () {
    const String binary = '%%Title: Fake\n%%BeginDocument: x\n\x00\xff';
    final String program = legacy.replaceFirst('%%EndComments', '%%BeginBinary: ${binary.length}\n$binary\n%%EndBinary\n%%EndComments');
    final AiPostScriptDocument document = const AiCodec().decode(latin1.encode(program)) as AiPostScriptDocument;
    check(document.title).equals('(Drawing)');
  });

  test('skips BeginData line counts and rejects truncated data blocks', () {
    final String program = legacy.replaceFirst('%%EndComments', '%%BeginData: 2 ASCII Lines\n%%Title: Fake\n%%Title: Fake2\n%%EndData\n%%EndComments');
    check((const AiCodec().decode(latin1.encode(program)) as AiPostScriptDocument).title).equals('(Drawing)');
    check(() => const AiCodec().decode(latin1.encode('$legacy%%BeginBinary: 999\nx'))).throws<FormatException>();
  });

  test('reads DOS EPS envelopes and retains preview bytes', () {
    final Uint8List program = latin1.encode(legacy);
    final Uint8List bytes = Uint8List(30 + program.length + 4);
    final ByteData header = ByteData.sublistView(bytes);
    bytes.setRange(0, 4, [0xc5, 0xd0, 0xd3, 0xc6]);
    header.setUint32(4, 30, Endian.little);
    header.setUint32(8, program.length, Endian.little);
    header.setUint32(20, 30 + program.length, Endian.little);
    header.setUint32(24, 4, Endian.little);
    bytes.setRange(30, 30 + program.length, program);
    bytes.setRange(30 + program.length, bytes.length, [1, 2, 3, 4]);
    final AiPostScriptDocument document = const AiCodec().decode(bytes) as AiPostScriptDocument;
    check(document.postScriptBytes).deepEquals(program);
    check(const AiCodec().encode(document)).deepEquals(bytes);
    header.setUint32(8, 0xffffffff, Endian.little);
    check(() => const AiCodec().decode(bytes)).throws<FormatException>();
  });

  test('rejects other formats, unmarked EPS and invalid limits', () {
    check(() => const AiCodec().decode(latin1.encode('<svg></svg>'))).throws<FormatException>();
    check(() => const AiCodec().decode(latin1.encode('%!PS-Adobe-3.0\n%%Creator: Other\n%%EOF'))).throws<FormatException>();
    check(() => const AiCodec(limits: AiLimits(maxCommentBytes: 3)).decode(latin1.encode(legacy))).throws<FormatException>();
    check(() => const AiCodec(limits: AiLimits(maxComments: 0)).decode(latin1.encode(legacy))).throws<ArgumentError>();
  });

  test('rejects unmatched or excessive embedded documents', () {
    check(() => const AiCodec().decode(latin1.encode('$legacy%%EndDocument\n'))).throws<FormatException>();
    check(() => const AiCodec().decode(latin1.encode('$legacy%%BeginDocument: missing\n'))).throws<FormatException>();
  });

  test('validates bounding boxes and supports high-resolution coordinates', () {
    check(AiBoundingBox.parse(value: '-1.5 0 2.5 4').left).equals(-1.5);
    check(() => AiBoundingBox.parse(value: '3 0 2 4')).throws<FormatException>();
    check(() => AiBoundingBox.parse(value: '0 0 NaN 4')).throws<FormatException>();
  });

  test('composes with base64 without filesystem dependencies', () {
    final Codec<AiDocument, String> codec = const AiCodec().fuse(base64);
    final AiDocument document = const AiCodec().decode(latin1.encode(legacy));
    check(codec.decode(codec.encode(document)).kind).equals(AiContainerKind.postscript);
  });
}
