import 'dart:collection';
import 'dart:convert';

import 'package:checks/checks.dart';
import 'package:illustratorkit/illustratorkit.dart';
import 'package:test/test.dart';
import 'package:zcodec/zcodec.dart';

import 'ai_native_artboards_test.dart' show artboardSource;
import 'ai_native_save_test.dart' show multipleNativePrograms;
import 'ai_native_test.dart' show nativePdf;

/// A header with distinct complete and font-filtered representations.
const String metadataHeader = '''%!PS-Adobe-3.0
%%Creator: Adobe Illustrator(R) 24.0
%%BoundingBox: 10 -20 30 -10
%%DocumentFonts: FirstFont
%%+ SecondFont
%%DocumentNeededFonts: ThirdFont
%%+ FourthFont
%%DocumentNeededResources: procset Adobe_Illustrator
%%+ procset Adobe_Other
%AI3_Cropmarks: 400 0 500 100
%FutureHeader: retain unknown fields
%%EndComments
''';

/// Explicit expected omission, independent of production header scanning.
String metadataWithoutFonts(String header) => header.replaceFirst('%%DocumentFonts: FirstFont\n%%+ SecondFont\n', '').replaceFirst('%%DocumentNeededFonts: ThirdFont\n%%+ FourthFont\n', '');

/// Resolves one saved owner without conflating catalog aliases and page indices.
PdfDictionary metadataPrivate(PdfDocument pdf, int? owner) {
  final PdfDictionary dictionary = owner == null ? pdf.catalog : pdf.pages[owner].dictionary;
  return pdf.dictionary(pdf.dictionary(pdf.dictionary(dictionary['PieceInfo']!)['Illustrator']!)['Private']!);
}

/// Adds source caches using independent PDF graph construction before extraction.
AiPdfDocument withMetadataHeaders(AiPdfDocument source, Map<int?, PdfValue> caches) {
  final PdfEditor editor = PdfEditor(document: source.pdf);
  final Map<PdfStream, PdfReference> streams = HashMap.identity();
  for (final MapEntry<int?, PdfValue> cache in caches.entries) {
    final PdfValue value = switch (cache.value) {
      final PdfStream stream => streams.putIfAbsent(stream, () => editor.addObject(value: stream)),
      final PdfValue value => value,
    };
    final PdfReference reference = (cache.key == null ? source.pdf.trailer['Root'] : source.pdf.pages[cache.key!].reference)! as PdfReference;
    final PdfDictionary owner = source.pdf.dictionary(reference);
    final PdfDictionary pieces = source.pdf.dictionary(owner['PieceInfo']!);
    final PdfDictionary illustrator = source.pdf.dictionary(pieces['Illustrator']!);
    final PdfDictionary private = source.pdf.dictionary(illustrator['Private']!);
    editor.replaceObject(
      reference: reference,
      value: owner.copyWith(
        values: {
          'PieceInfo': pieces.copyWith(
            values: {
              'Illustrator': illustrator.copyWith(
                values: {
                  'Private': private.copyWith(values: {'AIMetaData': value}),
                },
              ),
            },
          ),
        },
      ),
    );
  }
  return AiPdfDocument(pdf: editor.document);
}

/// Reads decoded cache bytes, regardless of original PDF stream filtering.
List<int> metadataBytes(PdfDocument pdf, int? owner) => PdfFilters.decode(pdf.resolve(metadataPrivate(pdf, owner)['AIMetaData']!) as PdfStream, resolve: pdf.resolve);

/// Keeps drawing opaque to the header synchronization path.
String metadataProgram(String header) => '$header%%BeginSetup\n%%EndSetup\n17 FuturePaint\n%%Trailer\n%%EOF\n';

/// Verifies bounded automatic synchronization without a native drawing parser.
void main() {
  test('synchronizes complete and font-filtered caches through every native envelope', () {
    for (final AiNativeCompression compression in AiNativeCompression.values) {
      final PdfStream full = PdfStream(
        dictionary: PdfDictionary(values: {'Sentinel': PdfNumber(value: 17)}),
        data: latin1.encode(metadataHeader),
      );
      final PdfStream filtered = PdfStream(
        dictionary: PdfDictionary(
          values: {
            'Filter': PdfName(value: 'FlateDecode'),
            'Sentinel': PdfNumber(value: 18),
          },
        ),
        data: const ZlibEncoder().convert(latin1.encode(metadataWithoutFonts(metadataHeader))),
      );
      final AiPdfDocument original = withMetadataHeaders(nativePdf(compression: compression, alias: true, nativeProgram: metadataProgram(metadataHeader)), {0: full, 1: filtered});
      final AiNativeSource source = AiNativeData.extract(original).single;
      final String changed = metadataHeader.replaceFirst('400 0 500 100', '-10 -20 30 40').replaceFirst('FirstFont', 'NewFont');
      final AiPdfDocument saved = AiNativeData.replace(source: source, program: latin1.encode(metadataProgram(changed)), synchronizedPdf: original.pdf);
      final AiPdfDocument reopened = const AiCodec().decode(const AiCodec().encode(saved)) as AiPdfDocument;
      check(metadataBytes(reopened.pdf, 0)).deepEquals(latin1.encode(changed));
      check(metadataBytes(reopened.pdf, 1)).deepEquals(latin1.encode(metadataWithoutFonts(metadataHeader).replaceFirst('400 0 500 100', '-10 -20 30 40')));
      check(AiNativeData.extract(reopened).single.bytes).deepEquals(latin1.encode(metadataProgram(changed)));
      for (final int owner in [0, 1]) {
        final PdfStream cache = reopened.pdf.resolve(metadataPrivate(reopened.pdf, owner)['AIMetaData']!) as PdfStream;
        check(cache.dictionary.integer('Sentinel')).equals(17 + owner);
        check(cache.dictionary['Filter']).isNull();
      }
      check(metadataBytes(original.pdf, 0)).deepEquals(latin1.encode(metadataHeader));
      check(metadataBytes(original.pdf, 1)).deepEquals(latin1.encode(metadataWithoutFonts(metadataHeader)));
    }
  });

  test('updates crop caches after supplied native edits while retaining host PDF content', () {
    final String program = artboardSource(body: '17 FuturePaint');
    final String header = program.substring(0, program.indexOf('%%EndComments') + '%%EndComments\n'.length);
    final AiPdfDocument original = withMetadataHeaders(nativePdf(compression: .zstandard, nativeProgram: program), {0: PdfStream(dictionary: PdfDictionary(), data: latin1.encode(header))});
    final AiNativeSource source = AiNativeData.extract(original).single;
    // Directly supplied native changes keep the unknown drawing operator intact.
    final String changed = program.replaceFirst('%AI3_Cropmarks: 400 0 500 100', '%AI3_Cropmarks: -10 -20 30 40');
    final PdfEditor host = PdfEditor(document: original.pdf)..setPageContent(pageIndex: 0, bytes: latin1.encode('0.5 g 0 0 50 50 re f'));
    final AiPdfDocument saved = AiNativeData.replace(source: source, program: latin1.encode(changed), synchronizedPdf: host.document);
    check(latin1.decode(metadataBytes(saved.pdf, 0))).equals(header.replaceFirst('400 0 500 100', '-10 -20 30 40'));
    check(PdfProgram.fromPage(document: saved.pdf, pageIndex: 0).operations.last.operator).equals('f');
    check(latin1.decode(AiNativeData.extract(saved).single.bytes)).contains('17 FuturePaint');
  });

  test('keeps opaque caches when only the body changes and never invents missing caches', () {
    for (final PdfValue cache in [
      PdfString.text(text: 'opaque'),
      PdfStream(dictionary: PdfDictionary(), data: [0, 255, 17]),
    ]) {
      final AiPdfDocument original = withMetadataHeaders(nativePdf(compression: .plain, nativeProgram: metadataProgram(metadataHeader)), {0: cache});
      final AiNativeSource source = AiNativeData.extract(original).single;
      final AiPdfDocument saved = AiNativeData.replace(
        source: source,
        program: latin1.encode(metadataProgram(metadataHeader).replaceFirst('17 FuturePaint', '18 FuturePaint')),
        synchronizedPdf: original.pdf,
      );
      check(saved.pdf.resolve(metadataPrivate(saved.pdf, 0)['AIMetaData']!)).identicalTo(cache);
    }
    for (final bool explicitNull in [false, true]) {
      final AiPdfDocument base = nativePdf(compression: .plain, nativeProgram: metadataProgram(metadataHeader));
      final AiPdfDocument original = explicitNull ? withMetadataHeaders(base, {0: const PdfNull()}) : base;
      final AiNativeSource source = AiNativeData.extract(original).single;
      final AiPdfDocument saved = AiNativeData.replace(source: source, program: latin1.encode(metadataProgram(metadataHeader.replaceFirst('400 0', '-10 0'))), synchronizedPdf: original.pdf);
      check(metadataPrivate(saved.pdf, 0)['AIMetaData']).identicalTo(metadataPrivate(original.pdf, 0)['AIMetaData']);
    }
  });

  test('refuses divergent cache profiles and non-stream caches before changing any owners', () {
    for (final PdfValue cache in [PdfString.text(text: 'opaque'), PdfStream(dictionary: PdfDictionary(), data: latin1.encode(metadataHeader.replaceFirst('400 0', '500 0')))]) {
      final AiPdfDocument original = withMetadataHeaders(nativePdf(compression: .plain, alias: true, nativeProgram: metadataProgram(metadataHeader)), {
        0: PdfStream(dictionary: PdfDictionary(), data: latin1.encode(metadataHeader)),
        1: cache,
      });
      final AiNativeSource source = AiNativeData.extract(original).single;
      final List<int> before = const AiCodec().encode(original);
      check(() => AiNativeData.replace(source: source, program: latin1.encode(metadataProgram(metadataHeader.replaceFirst('400 0', '-10 0'))), synchronizedPdf: original.pdf))
          .throws<UnsupportedError>();
      check(const AiCodec().encode(original)).deepEquals(before);
    }
  });

  test('shares updated cache objects and preserves references outside selected owners', () {
    final AiPdfDocument base = multipleNativePrograms();
    final PdfEditor prepared = PdfEditor(document: base.pdf);
    final String header = latin1.decode(AiNativeData.extract(base).first.bytes).split('%%BeginSetup').first;
    final PdfReference cache = prepared.addObject(
      value: PdfStream(dictionary: PdfDictionary(), data: latin1.encode(header)),
    );
    final PdfReference witness = prepared.addObject(value: PdfArray(values: [cache]));
    final AiPdfDocument original = withMetadataHeaders(AiPdfDocument(pdf: prepared.document), {null: cache, 0: cache, 1: cache});
    final List<AiNativeSource> sources = AiNativeData.extract(original);
    final List<int> program = latin1.encode(latin1.decode(sources.first.bytes).replaceFirst('%%EndComments', '%HostHeader: revised\n%%EndComments'));
    final AiPdfDocument saved = AiNativeData.replace(source: sources.first, program: program, synchronizedPdf: original.pdf);
    check(metadataPrivate(saved.pdf, null)['AIMetaData']).equals(metadataPrivate(saved.pdf, 0)['AIMetaData']);
    check(metadataPrivate(saved.pdf, 1)['AIMetaData']).equals(cache);
    check(saved.pdf.objects[cache]).identicalTo(original.pdf.objects[cache]);
    check(saved.pdf.objects[witness]).identicalTo(original.pdf.objects[witness]);
    check(AiNativeData.extract(saved).last.bytes).deepEquals(sources.last.bytes);
    final AiPdfDocument batch = AiNativeData.replaceAll(
      replacements: [
        for (final (int, AiNativeSource) item in sources.indexed)
          AiNativeReplacement(source: item.$2, program: latin1.encode(latin1.decode(item.$2.bytes).replaceFirst('%%EndComments', '%HostHeader: ${item.$1}\n%%EndComments'))),
      ],
      synchronizedPdf: original.pdf,
    );
    check(latin1.decode(metadataBytes(batch.pdf, null))).contains('%HostHeader: 0');
    check(latin1.decode(metadataBytes(batch.pdf, 1))).contains('%HostHeader: 1');
  });

  test('retains a font-filtered cache after font-only changes and rejects ambiguous new font policy', () {
    final PdfStream filtered = PdfStream(dictionary: PdfDictionary(), data: latin1.encode(metadataWithoutFonts(metadataHeader)));
    final AiPdfDocument original = withMetadataHeaders(nativePdf(compression: .plain, alias: true, nativeProgram: metadataProgram(metadataHeader)), {0: filtered, 1: filtered});
    final AiNativeSource source = AiNativeData.extract(original).single;
    final AiPdfDocument saved = AiNativeData.replace(source: source, program: latin1.encode(metadataProgram(metadataHeader.replaceFirst('FirstFont', 'DifferentFont'))), synchronizedPdf: original.pdf);
    check(saved.pdf.resolve(metadataPrivate(saved.pdf, 0)['AIMetaData']!)).identicalTo(filtered);
    check(saved.pdf.resolve(metadataPrivate(saved.pdf, 1)['AIMetaData']!)).identicalTo(filtered);
    final String absent = metadataWithoutFonts(metadataHeader);
    final AiPdfDocument ambiguous = withMetadataHeaders(nativePdf(compression: .plain, nativeProgram: metadataProgram(absent)), {0: filtered});
    check(() => AiNativeData.replace(source: AiNativeData.extract(ambiguous).single, program: latin1.encode(metadataProgram(metadataHeader)), synchronizedPdf: ambiguous.pdf))
        .throws<UnsupportedError>();
  });

  test('preserves complete CR LF and CRLF headers without normalizing unknown comments', () {
    for (final String newline in ['\n', '\r', '\r\n']) {
      final String header = metadataHeader.replaceAll('\n', newline);
      final AiPdfDocument original = withMetadataHeaders(nativePdf(compression: .plain, nativeProgram: metadataProgram(header)), {
        0: PdfStream(dictionary: PdfDictionary(), data: latin1.encode(header)),
      });
      final String changed = header.replaceFirst('retain unknown fields', 'supplied unknown fields');
      final AiPdfDocument saved = AiNativeData.replace(source: AiNativeData.extract(original).single, program: latin1.encode(metadataProgram(changed)), synchronizedPdf: original.pdf);
      check(metadataBytes(saved.pdf, 0)).deepEquals(latin1.encode(changed));
    }
  });

  test('rejects incomplete or executable headers without consulting a drawing whitelist', () {
    final AiPdfDocument original = withMetadataHeaders(nativePdf(compression: .plain, nativeProgram: metadataProgram(metadataHeader)), {
      0: PdfStream(dictionary: PdfDictionary(), data: latin1.encode(metadataHeader)),
    });
    for (final String changed in [
      metadataProgram(metadataHeader).replaceFirst('%%EndComments', '%End'),
      metadataProgram(metadataHeader).replaceFirst('%%EndComments', '17 FuturePaint\n%%EndComments'),
    ]) {
      check(() => AiNativeData.replace(source: AiNativeData.extract(original).single, program: latin1.encode(changed), synchronizedPdf: original.pdf)).throws<UnsupportedError>();
    }
  });

  test('bounds cache input output and header line inspection before graph allocation', () {
    final String sourceHeader = metadataWithoutFonts(metadataHeader);
    final AiPdfDocument base = nativePdf(compression: .plain, alias: true, nativeProgram: metadataProgram(sourceHeader));
    final PdfStream full = PdfStream(dictionary: PdfDictionary(), data: latin1.encode(sourceHeader));
    final AiPdfDocument original = withMetadataHeaders(base, {0: full, 1: PdfStream(dictionary: PdfDictionary(), data: latin1.encode(sourceHeader))});
    final AiNativeSource source = AiNativeData.extract(original).single;
    final String changed = metadataProgram(sourceHeader.replaceFirst('400 0', '-10 0'));
    final List<int> before = const AiCodec().encode(original);
    for (final AiNativeLimits limits in [AiNativeLimits(maxDecodedBytes: changed.length + 1), AiNativeLimits(maxEncodedBytes: changed.length + 1)]) {
      check(() => AiNativeData.replace(source: source, program: latin1.encode(changed), synchronizedPdf: original.pdf, limits: limits, blockBytes: 1)).throws<FormatException>();
    }
    final AiPdfDocument shared = withMetadataHeaders(base, {0: full, 1: full});
    check(
      AiNativeData.replace(
        source: AiNativeData.extract(shared).single,
        program: latin1.encode(changed),
        synchronizedPdf: shared.pdf,
        limits: AiNativeLimits(maxDecodedBytes: changed.length + 1),
      ).pdf.pages,
    ).length.equals(2);
    final AiPdfDocument compressed = withMetadataHeaders(base, {
      0: PdfStream(
        dictionary: PdfDictionary(values: {'Filter': PdfName(value: 'FlateDecode')}),
        data: const ZlibEncoder().convert(List.filled(100000, 37)),
      ),
    });
    check(
      () =>
          AiNativeData.replace(source: AiNativeData.extract(compressed).single, program: latin1.encode(changed), synchronizedPdf: compressed.pdf, limits: const AiNativeLimits(maxDecodedBytes: 1000)),
    ).throws<FormatException>();
    final String manyLines = sourceHeader.replaceFirst('%%EndComments', '${List.filled(200, '%\n').join()}%%EndComments');
    check(() => AiNativeData.replace(source: source, program: latin1.encode(metadataProgram(manyLines)), synchronizedPdf: original.pdf, limits: const AiNativeLimits(maxTokens: 150)))
        .throws<FormatException>();
    final String longHeader = sourceHeader.replaceFirst('%%EndComments', '%${List.filled(2000, 'x').join()}\n%%EndComments');
    final AiPdfDocument longSource = withMetadataHeaders(nativePdf(compression: .plain, nativeProgram: metadataProgram(longHeader)), {
      0: PdfStream(dictionary: PdfDictionary(), data: latin1.encode(longHeader)),
    });
    check(
      () =>
          AiNativeData.replace(source: AiNativeData.extract(longSource).single, program: latin1.encode(changed), synchronizedPdf: longSource.pdf, limits: const AiNativeLimits(maxDecodedBytes: 1000)),
    ).throws<FormatException>();
    check(const AiCodec().encode(original)).deepEquals(before);
  });
}
