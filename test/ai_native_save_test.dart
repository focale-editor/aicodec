import 'dart:convert';

import 'package:aikit/aikit.dart';
import 'package:checks/checks.dart';
import 'package:test/test.dart';

import 'ai_native_test.dart' as fixtures;

/// Synthetic multiple artboards do not imply a one-to-one PDF owner mapping.
const String _artboards = '''%_/Document : /Dictionary : /Array :
%_/Dictionary : (First) /UnicodeString (Name) ,
%_0 100 /RealPointRelToROrigin (PositionPoint1) ,
%_100 0 /RealPointRelToROrigin (PositionPoint2) , ; ,
%_/Dictionary : (Second) /UnicodeString (Name) ,
%_200 100 /RealPointRelToROrigin (PositionPoint1) ,
%_300 0 /RealPointRelToROrigin (PositionPoint2) , ; ,
%_; (ArtboardArray) , ; /Recorded , ;
''';

/// Builds distinct native programs, a catalog alias and opaque reference chains.
AiPdfDocument multipleNativePrograms() {
  final AiPdfDocument original = fixtures.nativePdf(
    compression: .zstandard,
    alias: true,
    nativeProgram: fixtures.programText.replaceFirst('%%EndSetup', '$_artboards\n%%EndSetup').replaceFirst('1 Ap', '17 FuturePaint\n1 Ap'),
  );
  final PdfReference root = original.pdf.trailer['Root']! as PdfReference;
  final PdfPage independent = original.pdf.pages.last;
  final PdfDictionary second = PdfDictionary(
    values: {
      'Illustrator': PdfDictionary(
        values: {
          'Private': PdfDictionary(
            values: {
              'AIPrivateData1': const PdfReference(objectNumber: 902),
              'Opaque': const PdfReference(objectNumber: 900),
            },
          ),
        },
      ),
    },
  );
  return AiPdfDocument(
    pdf: original.pdf.copyWith(
      objects: {
        ...original.pdf.objects,
        root: original.pdf.catalog.copyWith(values: {'PieceInfo': original.pdf.pages.first.dictionary['PieceInfo']!}),
        independent.reference!: independent.dictionary.copyWith(values: {'PieceInfo': second}),
        const PdfReference(objectNumber: 900): PdfArray(values: [const PdfReference(objectNumber: 901)]),
        const PdfReference(objectNumber: 901): PdfStream(dictionary: PdfDictionary(), data: [0, 255, 42]),
        const PdfReference(objectNumber: 902): PdfStream(dictionary: PdfDictionary(), data: latin1.encode(fixtures.programText.replaceFirst('Layer 1', 'Independent'))),
      },
    ),
  );
}

/// Supplies a nonvisual layer edit while keeping all other native bytes.
AiNativeReplacement _replacement(AiNativeSource source) {
  final AiProgram program = AiProgram.decode(bytes: source.bytes);
  return AiNativeReplacement(
    source: source,
    program: AiNativeEditor.updateLayer(program: program, layer: program.layers.first, name: 'Saved ${source.owners}').bytes,
  );
}

/// Checks batch ownership, graph preservation and atomic rejection.
void main() {
  test('saves independent programs, catalog aliases, artboards and host resources together', () {
    final AiPdfDocument original = multipleNativePrograms();
    final List<AiNativeReplacement> replacements = AiNativeData.extract(original).map(_replacement).toList();
    final PdfEditor host = PdfEditor(document: original.pdf);
    final String name = host.setPageResource(
      pageIndex: 1,
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
        data: latin1.encode('0 1 0 rg 0 0 10 10 re f'),
      ),
    );
    host.setPageContent(pageIndex: 1, bytes: latin1.encode('/$name Do'));
    final List<int> before = const AiCodec().encode(original);
    final AiPdfDocument saved = AiNativeData.replaceAll(replacements: replacements, synchronizedPdf: host.document, blockBytes: 43);
    final AiPdfDocument reopened = const AiCodec().decode(const AiCodec().encode(saved)) as AiPdfDocument;
    final List<AiNativeSource> sources = AiNativeData.extract(reopened);
    check(sources).length.equals(2);
    check(sources.first.owners).deepEquals([null, 0]);
    check(sources.last.owners).deepEquals([1]);
    for (int index = 0; index < sources.length; index++) {
      check(sources[index].bytes).deepEquals(replacements[index].program);
      check(sources[index].compression).equals(replacements[index].source.compression);
    }
    final AiNativeRecords records = AiNativeRecords.decode(program: AiProgram.decode(bytes: sources.first.bytes));
    check(records.artboards.map((artboard) => latin1.decode(artboard.nameBytes))).deepEquals(['First', 'Second']);
    check(latin1.decode(sources.first.bytes)).contains('17 FuturePaint');
    final PdfEditor recovered = PdfEditor(document: reopened.pdf);
    check((recovered.pageResource(pageIndex: 1, category: 'XObject', name: name) as PdfStream).data).deepEquals(latin1.encode('0 1 0 rg 0 0 10 10 re f'));
    check(recovered.pageOperations(pageIndex: 1).single.operator).equals('Do');
    check((reopened.pdf.resolve(const PdfReference(objectNumber: 901)) as PdfStream).data).deepEquals([0, 255, 42]);
    check(const AiCodec().encode(original)).deepEquals(before);
  });

  test('preserves unselected programs and requires fresh handles after saving', () {
    final AiPdfDocument original = multipleNativePrograms();
    final List<AiNativeSource> sources = AiNativeData.extract(original);
    final AiPdfDocument saved = AiNativeData.replace(source: sources.first, program: _replacement(sources.first).program, synchronizedPdf: original.pdf);
    check(AiNativeData.extract(saved).last.bytes).deepEquals(sources.last.bytes);
    check(saved.pdf.pages.last.dictionary['PieceInfo']).identicalTo(original.pdf.pages.last.dictionary['PieceInfo']);
    check(() => AiNativeData.replace(source: sources.last, program: sources.last.bytes, synchronizedPdf: saved.pdf)).throws<ArgumentError>();
    final AiNativeSource fresh = AiNativeData.extract(saved).last;
    final AiPdfDocument secondSave = AiNativeData.replace(source: fresh, program: _replacement(fresh).program, synchronizedPdf: saved.pdf);
    check(AiNativeData.extract(secondSave).first.bytes).deepEquals(AiNativeData.extract(saved).first.bytes);
  });

  test('rejects foreign graphs and reordered, inserted or removed owner pages', () {
    final AiPdfDocument original = multipleNativePrograms();
    final AiNativeSource source = AiNativeData.extract(original).first;
    final PdfReference tree = original.pdf.catalog['Pages']! as PdfReference;
    final PdfDictionary pages = original.pdf.dictionary(tree);
    final PdfEditor inserted = PdfEditor(document: original.pdf)..insertPage(page: PdfPageSource(width: 100, height: 100, content: []));
    final PdfEditor removed = PdfEditor(document: original.pdf)..removePage(pageIndex: 1);
    final List<PdfDocument> invalid = [
      (const AiCodec().decode(const AiCodec().encode(original)) as AiPdfDocument).pdf,
      original.pdf.copyWith(
        objects: {
          ...original.pdf.objects,
          tree: pages.copyWith(values: {'Kids': PdfArray(values: (pages['Kids']! as PdfArray).values.reversed)}),
        },
      ),
      inserted.document,
      removed.document,
    ];
    for (final PdfDocument graph in invalid) {
      final List<int> before = const AiCodec().encode(AiPdfDocument(pdf: graph));
      check(() => AiNativeData.replace(source: source, program: source.bytes, synchronizedPdf: graph)).throws<ArgumentError>();
      check(const AiCodec().encode(AiPdfDocument(pdf: graph))).deepEquals(before);
    }
  });

  test('rejects changed native dependencies even in an unselected program', () {
    final AiPdfDocument original = multipleNativePrograms();
    final AiNativeSource selected = AiNativeData.extract(original).first;
    for (final PdfReference reference in [const PdfReference(objectNumber: 900), const PdfReference(objectNumber: 901)]) {
      final PdfDocument changed = original.pdf.copyWith(
        objects: {
          ...original.pdf.objects,
          reference: PdfString.text(text: 'changed'),
        },
      );
      check(() => AiNativeData.replace(source: selected, program: selected.bytes, synchronizedPdf: changed)).throws<ArgumentError>();
    }
  });

  test('rejects changed alias membership and a new catalog identity', () {
    final AiPdfDocument original = multipleNativePrograms();
    final AiNativeSource selected = AiNativeData.extract(original).first;
    final PdfPage page = original.pdf.pages.last;
    for (final PdfDocument graph in [
      original.pdf.copyWith(
        objects: {
          ...original.pdf.objects,
          page.reference!: page.dictionary.copyWith(values: {'PieceInfo': original.pdf.pages.first.dictionary['PieceInfo']!}),
        },
      ),
      original.pdf.copyWith(
        objects: {
          ...original.pdf.objects,
          page.reference!: page.dictionary.copyWith(remove: {'PieceInfo'}),
        },
      ),
      original.pdf.copyWith(
        objects: {...original.pdf.objects, const PdfReference(objectNumber: 1000): original.pdf.catalog},
        trailer: original.pdf.trailer.copyWith(values: {'Root': const PdfReference(objectNumber: 1000)}),
      ),
    ]) {
      check(() => AiNativeData.replace(source: selected, program: selected.bytes, synchronizedPdf: graph)).throws<ArgumentError>();
    }
  });

  test('retains host changes to unrelated producer metadata', () {
    final AiPdfDocument original = multipleNativePrograms();
    final AiNativeSource source = AiNativeData.extract(original).first;
    final PdfPage page = original.pdf.pages.first;
    final PdfDictionary pieces = original.pdf.dictionary(page.dictionary['PieceInfo']!);
    final PdfDocument host = original.pdf.copyWith(
      objects: {
        ...original.pdf.objects,
        page.reference!: page.dictionary.copyWith(
          values: {
            'PieceInfo': pieces.copyWith(values: {'Host': PdfString.text(text: 'kept')}),
          },
        ),
      },
    );
    final AiPdfDocument saved = AiNativeData.replace(source: source, program: source.bytes, synchronizedPdf: host);
    final PdfDictionary after = saved.pdf.dictionary(saved.pdf.pages.first.dictionary['PieceInfo']!);
    check((after['Host']! as PdfString).text).equals('kept');
    check(after['OtherProducer']).identicalTo(pieces['OtherProducer']);
  });

  test('rejects overlapping, foreign and invalid batch entries atomically', () {
    final AiPdfDocument original = multipleNativePrograms();
    final List<AiNativeSource> sources = AiNativeData.extract(original);
    final AiNativeReplacement first = _replacement(sources.first);
    final List<int> before = const AiCodec().encode(original);
    for (final List<AiNativeReplacement> batch in [
      <AiNativeReplacement>[],
      [first, _replacement(AiNativeData.extract(original).first)],
      [first, _replacement(AiNativeData.extract(multipleNativePrograms()).last)],
    ]) {
      check(() => AiNativeData.replaceAll(replacements: batch, synchronizedPdf: original.pdf)).throws<ArgumentError>();
    }
    check(
      () => AiNativeData.replaceAll(
        replacements: [
          first,
          AiNativeReplacement(source: sources.last, program: [0]),
        ],
        synchronizedPdf: original.pdf,
      ),
    ).throws<FormatException>();
    check(const AiCodec().encode(original)).deepEquals(before);
  });

  test('owns supplied bytes and bounds aggregate output and metadata traversal', () {
    final AiPdfDocument original = multipleNativePrograms();
    final List<AiNativeSource> sources = AiNativeData.extract(original);
    final List<int> bytes = sources.first.bytes.toList();
    final AiNativeReplacement copied = AiNativeReplacement(source: sources.first, program: bytes);
    bytes[0] = 0;
    check(copied.program.first).equals(37);
    check(() => copied.program[0] = 0).throws<UnsupportedError>();
    check(() => AiNativeReplacement(source: sources.first, program: [256])).throws<FormatException>();
    final int encodedTotal = sources.fold(0, (total, source) => total + AiNativeData.encodeEnvelope(source.bytes, compression: source.compression).length);
    for (final AiNativeLimits limits in [
      AiNativeLimits(maxDecodedBytes: sources.first.bytes.length),
      AiNativeLimits(maxEncodedBytes: encodedTotal - 1),
      const AiNativeLimits(maxTokens: 1),
      const AiNativeLimits(maxDepth: 1),
    ]) {
      check(
        () => AiNativeData.replaceAll(
          replacements: [
            copied,
            AiNativeReplacement(source: sources.last, program: sources.last.bytes),
          ],
          synchronizedPdf: original.pdf,
          limits: limits,
          blockBytes: 1,
        ),
      ).throws<FormatException>();
    }
  });
}
