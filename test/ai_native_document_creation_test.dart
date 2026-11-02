import 'dart:convert';

import 'package:aicodec/aicodec.dart';
import 'package:checks/checks.dart';
import 'package:test/test.dart';

/// Supplies fresh deterministic native board identities and explicit ruler points.
AiNativeArtboardDefinition newDocumentBoard(int index) => AiNativeArtboardDefinition(
  nameBytes: [0, 66, 0, 48 + index],
  identifierBytes: latin1.encode('12345678-1234-4234-8234-${index.toString().padLeft(12, '0')}'),
  bounds: index == 0 ? AiBoundingBox(left: -10, bottom: -20, right: 90, top: 80) : AiBoundingBox(left: 200, bottom: -30, right: 320, top: 50),
  rulerOrigin: [8191.5, 8191.5],
  selected: index == 0,
);

/// Uses one explicit fourteen-operand CC layer layout with fresh XML identities.
AiNativeLayerDefinition newDocumentLayer(String id) => AiNativeLayerDefinition(
  attributes: [1, 1, 1, 1, 0, 0, 1, 0, 10, 20, 30, 0, 50, 0],
  nameBytes: latin1.encode('Layer $id'),
  identifierBytes: latin1.encode(id),
  expanded: true,
);

/// Defines independent native triangles and host-known ink bounds.
AiNativePathDefinition newDocumentPath(int index, {AiNativeDocumentColorMode mode = .rgb}) {
  final double x = index == 0 ? 10 : 210;
  return AiNativePathDefinition(
    artwork: AiArtworkPath(
      segments: [
        AiPathSegment(operator: 'm', coordinates: [x, 10]),
        AiPathSegment(operator: 'L', coordinates: [x + 20, 10]),
        AiPathSegment(operator: 'L', coordinates: [x + 20, 30]),
      ],
      fill: mode == .rgb ? AiColor(space: .rgb, channels: index == 0 ? [1, 0, 0] : [0, 0, 1]) : AiColor(space: .cmyk, channels: index == 0 ? [0, 1, 1, 0] : [1, 1, 0, 0]),
      closed: true,
    ),
    bounds: AiBoundingBox(left: x, bottom: 10, right: x + 20, top: 30),
    nameBytes: latin1.encode('Path $index'),
    identifierBytes: latin1.encode('path_$index'),
  );
}

/// Creates a complete new source without reading or embedding an existing AI.
AiNativeRecords newDocumentRecords({bool blank = false, AiNativeDocumentColorMode mode = .rgb, AiNativeLimits limits = const AiNativeLimits()}) => AiNativeDocument.create(
  artboards: [newDocumentBoard(0), if (!blank) newDocumentBoard(1)],
  layers: [
    AiNativeDocumentLayer(
      definition: newDocumentLayer('root'),
      paths: [if (!blank) newDocumentPath(0, mode: mode)],
      children: [
        if (!blank)
          AiNativeDocumentLayer(
            definition: newDocumentLayer('child'),
            paths: [newDocumentPath(1, mode: mode)],
          ),
      ],
    ),
  ],
  titleBytes: latin1.encode('New (Focale) document'),
  colorMode: mode,
  createdAt: DateTime.utc(2026, 11, 1, 12, 30, 15),
  limits: limits,
);

/// Explicit compatibility pages independently authored in the host coordinate basis.
PdfDocument newDocumentPdf({bool blank = false, AiNativeDocumentColorMode mode = .rgb}) => PdfDocument.fromPages(
  pages: [
    PdfPageSource(width: 100, height: 100, content: latin1.encode(blank ? '' : 'q 1 0 0 1 10 20 cm ${mode == .rgb ? '1 0 0 rg' : '0 1 1 0 k'} 10 10 m 30 10 l 30 30 l h f Q')),
    if (!blank) PdfPageSource(width: 120, height: 80, content: latin1.encode('q 1 0 0 1 -200 30 cm ${mode == .rgb ? '0 0 1 rg' : '1 1 0 0 k'} 210 10 m 230 10 l 230 30 l h f Q')),
  ],
);

/// Binds every board explicitly to the current PDF page in native order.
List<AiNativeDocumentPage> newDocumentBindings(AiNativeRecords records, PdfDocument pdf) => [
  for (final (int, AiNativeArtboard) item in AiNativeArtboards.decode(records: records).artboards.indexed) AiNativeDocumentPage(artboard: item.$2, page: pdf.pages[item.$1].reference!),
];

/// Packages a complete first save and forces both formats through encoding/decoding.
AiPdfDocument newDocumentSave(AiNativeRecords records, PdfDocument pdf, {int blockBytes = 71}) => const AiCodec().decode(
  const AiCodec().encode(
    AiNativeDocument.createPdf(
      records: records,
      compatibilityPdf: pdf,
      pages: newDocumentBindings(records, pdf),
      modifiedAt: DateTime.utc(2026, 11, 1, 13),
      blockBytes: blockBytes,
    ),
  ),
) as AiPdfDocument;

/// Resolves current private metadata without assuming direct dictionary storage.
PdfDictionary newDocumentPrivate(PdfDocument pdf, int index) => pdf.dictionary(pdf.dictionary(pdf.dictionary(pdf.pages[index].dictionary['PieceInfo']!)['Illustrator']!)['Private']!);

/// Exercises new native authoring, first saves and reuse of ordinary editing APIs.
void main() {
  test('creates blank RGB and populated CMYK native documents without a template', () {
    for (final AiNativeDocumentColorMode mode in AiNativeDocumentColorMode.values) {
      for (final bool blank in [false, true]) {
        final AiNativeRecords records = newDocumentRecords(blank: blank, mode: mode);
        final AiNativeArtboards boards = AiNativeArtboards.decode(records: records);
        final AiNativeLayers layers = AiNativeLayers.decode(drawing: AiNativeDrawing.decode(records: records));
        check(boards.artboards).length.equals(blank ? 1 : 2);
        check(boards.activeIndex).equals(0);
        check(boards.lastArtboardId).equals(blank ? 1 : 2);
        check(boards.artboards.first.record['Name']!.stringBytes!).deepEquals([0, 66, 0, 48]);
        check(layers.rootCountMatches).isTrue();
        check(layers.rootCount).equals(1);
        check(layers.layers).length.equals(blank ? 1 : 2);
        check(layers.drawing.paths).length.equals(blank ? 0 : 2);
        check(layers.layers.every((layer) => layer.bindingIssue == null)).isTrue();
        check(latin1.decode(records.program.bytes)).contains('%AI9_ColorModel: ${mode.index}');
        check(AiNativeDocumentSettings.decode(records: records).rulerUnit).equals(AiNativeRulerUnit.points);
        check(() => records.program.bytes[0] = 0).throws<UnsupportedError>();
      }
    }
  });

  test('first saves share complete blocks and header caches while retaining host pages', () {
    for (final bool blank in [false, true]) {
      final AiNativeRecords records = newDocumentRecords(blank: blank);
      final PdfDocument pdf = newDocumentPdf(blank: blank);
      final AiPdfDocument saved = newDocumentSave(records, pdf);
      final AiNativeSource native = AiNativeData.extract(saved).single;
      check(native.compression).equals(AiNativeCompression.zstandard);
      check(native.owners).deepEquals(blank ? [0] : [0, 1]);
      check(native.bytes).deepEquals(records.program.bytes);
      for (final (int, PdfPage) page in saved.pdf.pages.indexed) {
        check(saved.pdf.pageContent(page.$2)).deepEquals(pdf.pageContent(pdf.pages[page.$1]));
        final PdfDictionary metadata = newDocumentPrivate(saved.pdf, page.$1);
        check(metadata.integer('ContainerVersion')).equals(12);
        check(metadata.integer('CreatorVersion')).equals(24);
        check(metadata.integer('RoundtripStreamType')).equals(2);
        check(metadata.integer('RoundtripVersion')).equals(24);
        check(metadata.integer('NumBlock')!).isGreaterThan(1);
        final PdfDictionary illustrator = saved.pdf.dictionary(saved.pdf.dictionary(page.$2.dictionary['PieceInfo']!)['Illustrator']!);
        check((illustrator['LastModified']! as PdfString).bytes).deepEquals(latin1.encode('D:20261101130000Z'));
        final List<int> header = saved.pdf.decodeStream(saved.pdf.resolve(metadata['AIMetaData']!) as PdfStream);
        check(latin1.decode(header)).endsWith('%%EndComments\n');
        check(records.program.bytes.take(header.length)).deepEquals(header);
      }
      check(AiNativeData.extract(AiPdfDocument(pdf: pdf))).isEmpty();
      if (!blank) {
        check(newDocumentPrivate(saved.pdf, 0)['AIPrivateData1']).equals(newDocumentPrivate(saved.pdf, 1)['AIPrivateData1']);
        check(newDocumentPrivate(saved.pdf, 0)['AIMetaData']).equals(newDocumentPrivate(saved.pdf, 1)['AIMetaData']);
      }
    }
  });

  test('new documents support path layer and artboard editing followed by ordinary saving', () {
    final AiPdfDocument first = newDocumentSave(newDocumentRecords(blank: true), newDocumentPdf(blank: true));
    final AiNativeSource source = AiNativeData.extract(first).single;
    final AiNativeDrawing drawing = AiNativeDrawing.decode(
      records: AiNativeRecords.decode(program: AiProgram.decode(bytes: source.bytes)),
    );
    final AiNativeDrawing changed = drawing.createPath(definition: newDocumentPath(0), layer: drawing.records.program.layers.single);
    final AiNativeLayers next = AiNativeLayers.decode(drawing: changed).create(definition: newDocumentLayer('added'));
    final AiNativeArtboards boards = AiNativeArtboards.decode(records: next.drawing.records);
    final AiNativeArtboards resized = boards.resize(artboard: boards.artboards.single, bounds: AiBoundingBox(left: -10, bottom: -20, right: 90, top: 80), cropBounds: boards.artboards.single.bounds);
    final PdfDocument appearance = newDocumentPdf();
    final PdfEditor host = PdfEditor(document: first.pdf)..setPageContent(pageIndex: 0, bytes: appearance.pageContent(appearance.pages.first));
    final AiPdfDocument saved =
        const AiCodec().decode(const AiCodec().encode(AiNativeData.replace(source: source, program: resized.records.program.bytes, synchronizedPdf: host.document))) as AiPdfDocument;
    final AiNativeSource reopened = AiNativeData.extract(saved).single;
    check(
      AiNativeDrawing.decode(
        records: AiNativeRecords.decode(program: AiProgram.decode(bytes: reopened.bytes)),
      ).paths,
    ).length.equals(1);
    check(AiProgram.decode(bytes: reopened.bytes).layers).length.equals(2);
    check(latin1.decode(saved.pdf.decodeStream(saved.pdf.resolve(newDocumentPrivate(saved.pdf, 0)['AIMetaData']!) as PdfStream))).contains('%AI5_NumLayers: 2');
  });

  test('escapes header names and preserves explicit timestamps and large ruler units', () {
    final AiNativeRecords records = AiNativeDocument.create(
      artboards: [newDocumentBoard(0)],
      layers: [AiNativeDocumentLayer(definition: newDocumentLayer('a'))],
      titleBytes: [0, 255, 10, ...latin1.encode('%%EndComments\n()\\')],
      colorMode: .rgb,
      createdAt: DateTime.parse('2026-11-01T15:00:00+02:00'),
      rulerUnit: .meters,
      pageOrigin: [-3, 4],
    );
    check(latin1.decode(records.program.bytes)).contains('%%CreationDate: 2026-11-01T13:00:00.000Z');
    check(AiNativeDocumentSettings.decode(records: records).rulerUnit).equals(AiNativeRulerUnit.meters);
    check(AiNativeDocumentSettings.decode(records: records).pageOrigin!).deepEquals([-3.0, 4.0]);
    check(latin1.decode(records.program.bytes).split('%%EndComments')).length.equals(2);
  });

  test('populates new resource banks through existing APIs before the first save', () {
    final AiNativeGradientResources created = AiNativeGradientResources.decode(records: newDocumentRecords(blank: true)).create(
      nameBytes: latin1.encode('New gradient'),
      radial: true,
      stops: [
        AiNativeGradientStop(
          color: AiNativeGradientColor(kind: .gray, components: [0]),
          position: 0,
        ),
        AiNativeGradientStop(
          color: AiNativeGradientColor(kind: .gray, components: [1]),
          position: 100,
        ),
      ],
      ramps: [
        AiNativeGradientRamp(kind: .gray, channels: [AiNativeGradientChannel.constant(value: 1)]),
      ],
    );
    final AiPdfDocument saved = newDocumentSave(created.records, newDocumentPdf(blank: true));
    final AiNativeRecords reopened = AiNativeRecords.decode(program: AiProgram.decode(bytes: AiNativeData.extract(saved).single.bytes));
    check(AiNativeGradientResources.decode(records: reopened).definitions.single.nameBytes).deepEquals(latin1.encode('New gradient'));
  });

  test('fontless declarations remain editable but mixed and deferred font headers reject', () {
    final String source = latin1.decode(newDocumentRecords(blank: true).program.bytes);
    for (final String declaration in ['(none) Other', '(atend)', '(Other)']) {
      final AiNativeArtboards boards = AiNativeArtboards.decode(
        records: AiNativeRecords.decode(program: AiProgram.decode(bytes: latin1.encode(source.replaceFirst('%%DocumentFonts: (none)', '%%DocumentFonts: $declaration')))),
      );
      check(() => boards.resize(artboard: boards.artboards.single, bounds: boards.artboards.single.bounds, cropBounds: boards.artboards.single.bounds)).throws<UnsupportedError>();
    }
  });

  test('rejects duplicate native identities missing owners and exceeded budgets', () {
    final AiNativeDocumentLayer layer = AiNativeDocumentLayer(definition: newDocumentLayer('a'));
    for (final List<AiNativeDocumentLayer> layers in [
      <AiNativeDocumentLayer>[],
      [layer, layer],
      [
        AiNativeDocumentLayer(definition: newDocumentLayer('path_0'), paths: [newDocumentPath(0)]),
      ],
    ]) {
      check(() => AiNativeDocument.create(artboards: [newDocumentBoard(0)], layers: layers, titleBytes: [], colorMode: .rgb, createdAt: DateTime.utc(2026))).throws<ArgumentError>();
    }
    check(() => AiNativeDocument.create(artboards: [newDocumentBoard(0), newDocumentBoard(0)], layers: [layer], titleBytes: [], colorMode: .rgb, createdAt: DateTime.utc(2026)))
        .throws<ArgumentError>();
    expect(() => newDocumentRecords(limits: const AiNativeLimits(maxDecodedBytes: 200)), throwsA(anyOf(isA<AiLimitException>(), isA<FormatException>())));
    expect(() => newDocumentRecords(limits: const AiNativeLimits(maxDepth: 2)), throwsA(anyOf(isA<AiLimitException>(), isA<FormatException>())));
  });
}
