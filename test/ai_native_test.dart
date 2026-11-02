import 'dart:convert';
import 'dart:typed_data';

import 'package:aicodec/aicodec.dart';
import 'package:checks/checks.dart';
import 'package:test/test.dart';
import 'package:zcodec/zcodec.dart';

/// A CC-style layer header with an explicit editable native path.
const String programText =
    '%!PS-Adobe-3.0\n%%Creator: Adobe Illustrator(R) 24.0\n%%EndComments\n%%BeginSetup\n%%EndSetup\n'
    '%AI5_BeginLayer\n1 1 1 1 0 0 1 0 79 128 255 0 50 0 Lb\n(Layer 1) Ln\n0 AE\n0 A\n0 Xw\n'
    '1 Ap\n0 0 0 1 k\n0 0 m\n10 0 L\n10 10 20 10 20 0 C\nf\nLB\n%%PageTrailer\n%%EOF\n';

/// Builds private-data graphs independently of the native replacement writer.
AiPdfDocument nativePdf({
  required AiNativeCompression compression,
  bool alias = false,
  bool thumbnail = false,
  String prefix = 'AIPrivateData',
  int chunkBytes = 37,
  String nativeProgram = programText,
}) {
  final PdfDocument pdf = PdfDocument.fromPages(
    pages: [
      PdfPageSource(width: 100, height: 100, content: latin1.encode('q Q')),
      if (alias) PdfPageSource(width: 100, height: 100, content: latin1.encode('q Q')),
    ],
  );
  final Uint8List envelope = AiNativeData.encodeEnvelope(latin1.encode(nativeProgram), compression: compression);
  final Map<PdfReference, PdfValue> objects = {...pdf.objects};
  final Map<String, PdfValue> blocks = {};
  int number = 1;
  if (thumbnail) {
    final PdfReference reference = PdfReference(objectNumber: 100 + number);
    objects[reference] = PdfStream(dictionary: PdfDictionary(), data: latin1.encode('%%BoundingBox: 0 0 10 10\n%AI7_Thumbnail: 1 1 8\n'));
    blocks['$prefix${number++}'] = reference;
  }
  for (int offset = 0; offset < envelope.length; offset += chunkBytes) {
    final PdfReference reference = PdfReference(objectNumber: 100 + number);
    final int end = offset + chunkBytes < envelope.length ? offset + chunkBytes : envelope.length;
    objects[reference] = PdfStream(
      dictionary: PdfDictionary(values: {'Filter': PdfName(value: 'FlateDecode')}),
      data: const ZlibEncoder().convert(envelope.sublist(offset, end)),
    );
    blocks['$prefix${number++}'] = reference;
  }
  final PdfDictionary private = PdfDictionary(
    values: {
      ...blocks,
      'PrivateSentinel': PdfString.text(text: 'preserve me'),
    },
  );
  final PdfDictionary pieces = PdfDictionary(
    values: {
      'OtherProducer': PdfDictionary(values: {'Value': PdfNumber(value: 42)}),
      'Illustrator': PdfDictionary(values: {'Private': private, 'Unknown': PdfNumber(value: 17)}),
    },
  );
  for (final PdfPage page in pdf.pages) {
    objects[page.reference!] = page.dictionary.copyWith(values: {'PieceInfo': pieces});
  }
  return AiPdfDocument(pdf: pdf.copyWith(objects: objects));
}

/// Verifies native decompression, byte preservation and coherent source edits.
void main() {
  for (final AiNativeCompression compression in AiNativeCompression.values) {
    test('saves host-supplied pages with $compression native data and opaque appearances', () {
      final String nativeProgram = programText.replaceFirst('1 Ap\n', '1 Ap\n0 1 0 2 1 Xy\n');
      final AiPdfDocument original = nativePdf(compression: compression, alias: true, thumbnail: true, nativeProgram: nativeProgram);
      final AiNativeSource source = AiNativeData.extract(original).single;
      final AiProgram program = AiProgram.decode(bytes: source.bytes);
      final AiProgram changed = AiNativeEditor.updateLayer(program: program, layer: program.layers.single, name: 'Host-edited layer');
      // The host supplies each page's appearance; AiCodec never interprets Xy.
      final List<List<int>> appearances = [
        latin1.encode('0 0 0 1 k 0 0 m 10 0 l 10 10 20 10 20 0 c f'),
        latin1.encode('q 1 0 0 1 30 40 cm 0 0 0 1 k 0 0 m 10 0 l 10 10 20 10 20 0 c f Q'),
      ];
      final PdfEditor host = PdfEditor(document: original.pdf);
      for (final (int, List<int>) page in appearances.indexed) {
        host.setPageProgram(
          pageIndex: page.$1,
          program: PdfProgram(operations: PdfContent.decode(page.$2), resources: PdfDictionary(), document: host.document),
        );
      }

      final AiPdfDocument saved = AiNativeData.replace(source: source, program: changed.bytes, synchronizedPdf: host.document);
      final AiPdfDocument reopened = const AiCodec().decode(const AiCodec().encode(saved)) as AiPdfDocument;

      final AiNativeSource recovered = AiNativeData.extract(reopened).single;
      check(recovered.compression).equals(compression);
      check(recovered.owners).deepEquals([0, 1]);
      check(recovered.bytes).deepEquals(changed.bytes);
      check(latin1.decode(recovered.bytes)).contains('0 1 0 2 1 Xy');
      check(AiProgram.decode(bytes: recovered.bytes).layers.single.name).equals('Host-edited layer');
      for (int index = 0; index < appearances.length; index++) {
        check(PdfContent.encode(PdfProgram.fromPage(document: reopened.pdf, pageIndex: index).operations)).deepEquals(PdfContent.encode(PdfContent.decode(appearances[index])));
        final PdfDictionary pieces = reopened.pdf.dictionary(reopened.pdf.pages[index].dictionary['PieceInfo']!);
        check(reopened.pdf.dictionary(pieces['OtherProducer']!).integer('Value')).equals(42);
        final PdfDictionary illustrator = reopened.pdf.dictionary(pieces['Illustrator']!);
        check(illustrator.integer('Unknown')).equals(17);
        check((reopened.pdf.dictionary(illustrator['Private']!)['PrivateSentinel']! as PdfString).text).equals('preserve me');
        check(PdfProgram.fromPage(document: original.pdf, pageIndex: index).operations.map((operation) => operation.operator)).deepEquals(['q', 'Q']);
      }
      check(source.bytes).deepEquals(latin1.encode(nativeProgram));
    });

    test('extracts $compression after PDF filtering, split markers and thumbnails', () {
      final AiPdfDocument document = nativePdf(compression: compression, thumbnail: true, chunkBytes: 7);
      final AiNativeSource source = AiNativeData.extract(document).single;
      check(source.compression).equals(compression);
      check(source.bytes).deepEquals(latin1.encode(programText));
      check(source.asPostScript().creator).equals('Adobe Illustrator(R) 24.0');
      check(() => source.bytes[0] = 0).throws<UnsupportedError>();
    });

    test('rewrites $compression native data and all aliased owners', () {
      final AiPdfDocument document = nativePdf(compression: compression, alias: true);
      final AiNativeSource source = AiNativeData.extract(document).single;
      check(source.owners).deepEquals([0, 1]);
      final AiProgram program = AiProgram.decode(bytes: source.bytes);
      final AiProgram changed = AiNativeEditor.updateLayer(program: program, layer: program.layers.single, name: 'Renamed (layer)', visible: false, locked: true);
      final PdfDocument synchronized = document.pdf.copyWith(objects: {...document.pdf.objects});
      final AiPdfDocument updated = AiNativeData.replace(source: source, program: changed.bytes, synchronizedPdf: synchronized, blockBytes: 41);
      final AiPdfDocument reopened = const AiCodec().decode(const AiCodec().encode(updated)) as AiPdfDocument;
      final AiNativeSource rewritten = AiNativeData.extract(reopened).single;
      check(rewritten.bytes).deepEquals(changed.bytes);
      check(rewritten.owners).deepEquals([0, 1]);
      final PdfDictionary pieces = reopened.pdf.dictionary(reopened.pdf.pages.first.dictionary['PieceInfo']!);
      check(pieces['OtherProducer']).isNotNull();
      final PdfDictionary illustrator = reopened.pdf.dictionary(pieces['Illustrator']!);
      check(illustrator.integer('Unknown')).equals(17);
      check((reopened.pdf.dictionary(illustrator['Private']!)['PrivateSentinel']! as PdfString).text).equals('preserve me');
      check(AiProgram.decode(bytes: source.bytes).layers.single.name).equals('Layer 1');
    });
  }

  test('reserves dangling references when allocating rewritten native blocks', () {
    final AiPdfDocument original = nativePdf(compression: .plain);
    final int maximum = original.pdf.objects.keys.map((reference) => reference.objectNumber).reduce((first, second) => first > second ? first : second);
    final PdfReference dangling = PdfReference(objectNumber: maximum + 1);
    final PdfPage page = original.pdf.pages.single;
    final AiPdfDocument document = AiPdfDocument(
      pdf: original.pdf.copyWith(
        objects: {
          ...original.pdf.objects,
          page.reference!: page.dictionary.copyWith(values: {'Sentinel': dangling}),
        },
      ),
    );
    final AiNativeSource source = AiNativeData.extract(document).single;
    final AiPdfDocument saved = AiNativeData.replace(source: source, program: source.bytes, synchronizedPdf: document.pdf, blockBytes: 41);
    check(saved.pdf.objects.containsKey(dangling)).isFalse();
    check(saved.pdf.pages.single.dictionary['Sentinel']).equals(dangling);
    check(AiNativeData.extract(saved).single.bytes).deepEquals(source.bytes);
  });

  test('detects AIPDF private streams without Creator metadata', () {
    final AiPdfDocument original = nativePdf(compression: .zstandard, prefix: 'AIPDFPrivateData');
    final AiPdfDocument decoded = const AiCodec().decode(const AiCodec().encode(original)) as AiPdfDocument;
    check(AiNativeData.extract(decoded).single.bytes).deepEquals(latin1.encode(programText));
  });

  test('rejects compressed corruption, unknown envelopes and resource exhaustion', () {
    final Uint8List encoded = AiNativeData.encodeEnvelope(latin1.encode(programText), compression: .zstandard);
    encoded[encoded.length - 1] ^= 1;
    check(() => AiNativeData.decodeEnvelope(encoded)).throws<FormatException>();
    check(() => AiNativeData.decodeEnvelope(latin1.encode('%Unknown123'))).throws<FormatException>();
    final AiPdfDocument document = nativePdf(compression: .zlib);
    check(() => AiNativeData.extract(document, limits: const AiNativeLimits(maxDecodedBytes: 20))).throws<FormatException>();
    check(() => AiNativeData.extract(document, limits: const AiNativeLimits(maxEncodedBytes: 20))).throws<FormatException>();
    check(() => AiNativeData.extract(document, limits: const AiNativeLimits(maxTokens: 0))).throws<ArgumentError>();
  });

  test('keeps independent page programs separate', () {
    final AiPdfDocument document = nativePdf(compression: .plain, alias: true);
    final Map<PdfReference, PdfValue> objects = {...document.pdf.objects};
    final PdfPage page = document.pdf.pages[1];
    objects[page.reference!] = page.dictionary.copyWith(
      values: {
        'PieceInfo': PdfDictionary(
          values: {
            'Illustrator': PdfDictionary(
              values: {
                'Private': PdfDictionary(
                  values: {
                    'AIPrivateData1': PdfStream(dictionary: PdfDictionary(), data: latin1.encode(programText.replaceFirst('Layer 1', 'Independent'))),
                  },
                ),
              },
            ),
          },
        ),
      },
    );
    final List<AiNativeSource> sources = AiNativeData.extract(AiPdfDocument(pdf: document.pdf.copyWith(objects: objects)));
    check(sources.length).equals(2);
    check(AiProgram.decode(bytes: sources[1].bytes).layers.single.name).equals('Independent');
  });

  test('updating layer flags preserves a first child with private metadata', () {
    final AiProgram program = AiProgram.decode(bytes: latin1.encode(programText.replaceFirst('0 A\n0 Xw', '%_/ArtDictionary : (Group) /String (AIArtName) , ;\n1 Xw\n1 A')));
    final AiProgram changed = AiNativeEditor.updateLayer(program: program, layer: program.layers.single, visible: true, locked: false);
    check(changed.layers.single.visible).isTrue();
    check(changed.layers.single.locked).isFalse();
    check(latin1.decode(changed.bytes)).contains('1 Xw\n1 A');
  });

  test('parses nested and hidden layers with original extended attributes', () {
    final String nested = programText.replaceFirst('1 Ap', '0 1 0 1 0 0 1 5 79 255 255 0 50 0 Lb\n(Child) Ln\n1 A\n1 Xw\nLB\n1 Ap');
    final AiProgram program = AiProgram.decode(bytes: latin1.encode(nested));
    check(program.layers.length).equals(2);
    check(program.layers[1].parentStart).equals(program.layers[0].begin.start);
    check(program.layers[1].visible).isFalse();
    check(program.layers[1].locked).isTrue();
    final AiProgram changed = AiNativeEditor.updateLayer(program: program, layer: program.layers[1], name: 'Visible child', visible: true, locked: false, printing: false);
    check(changed.layers[1].visible).isTrue();
    check(changed.layers[1].locked).isFalse();
    check(changed.layers[1].printing).isFalse();
    check(changed.layers[0].name).equals('Layer 1');
    check(changed.layers[1].begin.numbers!.skip(4)).deepEquals(program.layers[1].begin.numbers!.skip(4));
  });

  test('edits plain native paths and preserves corner operators and unknown comments', () {
    final AiProgram program = AiProgram.decode(bytes: latin1.encode(programText.replaceFirst('1 Ap', '% untouched metadata\n1 Ap')));
    final AiProgram edited = AiNativeEditor.replacePath(
      program: program,
      path: program.paths.single,
      segments: [
        AiPathSegment(operator: 'm', coordinates: [1, 2]),
        AiPathSegment(operator: 'L', coordinates: [20, 30]),
      ],
    );
    check(edited.paths.single.segments.last.operator).equals('L');
    check(edited.paths.single.segments.last.coordinates).deepEquals([20.0, 30.0]);
    check(edited.paths.single.closed).isTrue();
    check(latin1.decode(edited.bytes).contains('% untouched metadata')).isTrue();
    check(program.paths.single.geometry.length).equals(3);
  });

  test('refuses stale handles, overlapping patches and unsynchronized appearances', () {
    final AiProgram original = AiProgram.decode(bytes: latin1.encode(programText));
    final AiProgram copy = AiProgram.decode(bytes: original.bytes);
    check(() => AiNativeEditor.updateLayer(program: copy, layer: original.layers.single, visible: false)).throws<ArgumentError>();
    check(
      () => AiNativeEditor.apply(
        program: original,
        edits: [
          AiSourceEdit(start: 0, end: 5, bytes: []),
          AiSourceEdit(start: 4, end: 6, bytes: []),
        ],
      ),
    ).throws<ArgumentError>();
    final AiProgram liveShape = AiProgram.decode(bytes: latin1.encode(programText.replaceFirst('f\nLB', 'f\n%_(ai::Rectangle) /UnicodeString (ai::LiveShape::HandlerName) ,\nLB')));
    check(liveShape.paths.single.hasDependentAppearance).isTrue();
    check(() => AiNativeEditor.replacePath(program: liveShape, path: liveShape.paths.single, segments: original.paths.single.segments)).throws<UnsupportedError>();
  });

  test('synchronizes plain CC point counts and preserves unselected source', () {
    final String counted = programText.replaceFirst('0 0 m', '3 As\n0 0 m').replaceFirst('20 0 C\nf', '20 0 C\n0 0 L\nf');
    final AiProgram source = AiProgram.decode(bytes: latin1.encode(counted));
    final List<AiPathSegment> geometry = [
      AiPathSegment(operator: 'm', coordinates: [1, 1]),
      AiPathSegment(operator: 'L', coordinates: [2, 3]),
    ];
    final AiProgram changed = AiNativeEditor.replacePath(program: source, path: source.paths.single, segments: geometry);
    check(changed.instructions.singleWhere((item) => item.operator == 'As').numbers).isNotNull().deepEquals([2]);
    check(changed.paths.single.segments.last.coordinates).deepEquals([1, 1]);
    check(changed.bytes.sublist(changed.paths.single.paint.start)).deepEquals(source.bytes.sublist(source.paths.single.paint.start));
    check(source.bytes).deepEquals(latin1.encode(counted));
    final AiProgram open = AiProgram.decode(bytes: latin1.encode(counted.replaceFirst('0 0 L\nf', 'F')));
    final AiProgram openChanged = AiNativeEditor.replacePath(program: open, path: open.paths.single, segments: geometry);
    check(openChanged.paths.single.segments).length.equals(2);
    check(openChanged.instructions.singleWhere((item) => item.operator == 'As').numbers).isNotNull().deepEquals([2]);
    final AiProgram point = AiNativeEditor.replacePath(program: source, path: source.paths.single, segments: [geometry.first]);
    check(point.instructions.singleWhere((item) => item.operator == 'As').numbers).isNotNull().deepEquals([1]);
    check(point.paths.single.segments).length.equals(2);
    for (final String body in [
      counted.replaceFirst('3 As', '4 As'),
      counted.replaceFirst('3 As', '3 As\n3 As'),
      counted.replaceFirst('3 As', '3 As\nu').replaceFirst('f\nLB', 'f\nU\nLB'),
      counted.replaceFirst('3 As\n', '').replaceFirst('0 0 L\nf', '0 0 L\n3 As\nf'),
    ]) {
      final AiProgram invalid = AiProgram.decode(bytes: latin1.encode(body));
      check(() => AiNativeEditor.replacePath(program: invalid, path: invalid.paths.single, segments: geometry)).throws<UnsupportedError>();
    }
  });

  test('rejects malformed structures and nested allocation attacks', () {
    check(() => AiProgram.decode(bytes: latin1.encode(programText.replaceFirst('LB\n', '')))).throws<FormatException>();
    check(() => AiProgram.decode(bytes: latin1.encode(programText.replaceFirst('0 0 m', 'q q q\n0 0 m')), limits: const AiNativeLimits(maxDepth: 2))).throws<FormatException>();
    check(() => AiProgram.decode(bytes: latin1.encode(programText), limits: const AiNativeLimits(maxTokens: 5))).throws<FormatException>();
  });
}
