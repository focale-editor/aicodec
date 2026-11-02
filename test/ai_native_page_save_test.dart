import 'dart:convert';

import 'package:aicodec/aicodec.dart';
import 'package:checks/checks.dart';
import 'package:test/test.dart';

import 'ai_native_artboard_lifecycle_test.dart' show newArtboard;
import 'ai_native_artboard_topology_test.dart' show artboardTopologySource;
import 'ai_native_artboards_test.dart' show artboardSource, mixedArtboardSource;
import 'ai_native_metadata_header_test.dart' show metadataBytes, metadataPrivate, withMetadataHeaders;
import 'ai_native_save_test.dart' show multipleNativePrograms;
import 'ai_native_test.dart' show nativePdf;

/// Builds three native boards, three PDF owners and an independent catalog alias.
AiPdfDocument mappedArtboardSource({bool opaqueDrawing = false, String? nativeProgram}) {
  final String program = nativeProgram ?? artboardSource(body: opaqueDrawing ? '17 FuturePaint' : '0 A 0 Xw 0.3 g 10 -10 m 30 -20 L f');
  final AiPdfDocument base = nativePdf(compression: .zstandard, alias: true, nativeProgram: program);
  final PdfEditor editor = PdfEditor(document: base.pdf)..insertPage(page: PdfPageSource(width: 120, height: 140, content: latin1.encode('q Q')));
  final PdfValue pieces = base.pdf.pages.first.dictionary['PieceInfo']!;
  editor.setPageAttributes(pageIndex: 2, values: {'PieceInfo': pieces});
  final PdfReference root = editor.document.trailer['Root']! as PdfReference;
  editor.replaceObject(
    reference: root,
    value: editor.document.catalog.copyWith(values: {'PieceInfo': pieces}),
  );
  final String header = program.substring(0, program.indexOf('%%EndComments') + '%%EndComments\n'.length);
  final PdfStream cache = PdfStream(
    dictionary: PdfDictionary(values: {'Sentinel': PdfNumber(value: 41)}),
    data: latin1.encode(header),
  );
  final AiPdfDocument cached = withMetadataHeaders(AiPdfDocument(pdf: editor.document), {null: cache, 0: cache, 1: cache, 2: cache});
  final PdfEditor distinct = PdfEditor(document: cached.pdf);
  for (final int? index in [null, 0, 1, 2]) {
    final PdfReference reference = (index == null ? cached.pdf.trailer['Root'] : cached.pdf.pages[index].reference)! as PdfReference;
    final PdfDictionary owner = cached.pdf.dictionary(reference);
    final PdfDictionary pieces = cached.pdf.dictionary(owner['PieceInfo']!);
    final PdfDictionary illustrator = cached.pdf.dictionary(pieces['Illustrator']!);
    distinct.replaceObject(
      reference: reference,
      value: owner.copyWith(
        values: {
          'PieceInfo': pieces.copyWith(
            values: {
              'Illustrator': illustrator.copyWith(
                values: {
                  'Private': metadataPrivate(cached.pdf, index).copyWith(values: {'OwnerSentinel': PdfNumber(value: index ?? -1)}),
                },
              ),
            },
          ),
        },
      ),
    );
  }
  return AiPdfDocument(pdf: distinct.document);
}

/// Binds a current model to host pages and explicit original metadata owners.
AiNativePageReplacement mappedArtboards(AiNativeSource source, AiNativeArtboards model, PdfDocument host, List<int?> metadataOwners) => model.pageReplacement(
  source: source,
  pages: [
    for (final (int, AiNativeArtboard) board in model.artboards.indexed) AiNativeArtboardPage(artboard: board.$2, page: host.pages[board.$1].reference!, metadataOwner: metadataOwners[board.$1]),
  ],
);

/// Decodes native artboard ownership without interpreting drawing operators.
AiNativeArtboards nativeBoards(AiNativeSource source) => AiNativeArtboards.decode(
  records: AiNativeRecords.decode(program: AiProgram.decode(bytes: source.bytes)),
);

/// Supplies a complete mapped save and reopens its serialized container.
AiPdfDocument saveMapped(AiNativePageReplacement replacement, PdfDocument host, {AiNativePageLabelsPolicy pageLabels = .requireUpdated}) {
  final AiPdfDocument saved = AiNativeData.replaceMapped(replacements: [replacement], synchronizedPdf: host, pageLabels: pageLabels);
  return const AiCodec().decode(const AiCodec().encode(saved)) as AiPdfDocument;
}

/// Supplies position-based PDF labels independently of native board names.
PdfDictionary pageLabels(List<int> starts) => PdfDictionary(
  values: {
    'Nums': PdfArray(
      values: [
        for (final int index in starts) ...[
          PdfNumber(value: index),
          PdfDictionary(
            values: {
              'S': PdfName(value: 'D'),
              'P': PdfString.text(text: 'Page '),
            },
          ),
        ],
      ],
    ),
  },
);

/// Keeps the catalog identity while supplying host-owned dependent PDF structure.
PdfDocument hostCatalog(PdfDocument pdf, Map<String, PdfValue> values, {Set<String> remove = const {}}) {
  final PdfEditor host = PdfEditor(document: pdf)
    ..replaceObject(
      reference: pdf.trailer['Root']! as PdfReference,
      value: pdf.catalog.copyWith(values: values, remove: remove),
    );
  return host.document;
}

/// Checks page graph lifecycle, explicit artboard association and native ownership.
void main() {
  test('requires explicit catalog page ownership for removal and freezes declarations', () {
    final AiPdfDocument fixture = mappedArtboardSource();
    final PdfEditor originalEditor = PdfEditor(document: fixture.pdf);
    for (int index = 0; index < fixture.pdf.pages.length; index++) {
      originalEditor.setPageAttributes(pageIndex: index, remove: {'PieceInfo'});
    }
    final AiPdfDocument original = AiPdfDocument(pdf: originalEditor.document);
    final AiNativeSource source = AiNativeData.extract(original).single;
    final AiNativeArtboards before = nativeBoards(source);
    final AiNativeArtboards changed = before.remove(artboards: [before.artboards.first], activeArtboard: null, cropBounds: null);
    final PdfEditor host = PdfEditor(document: original.pdf)..removePage(pageIndex: 0);
    final List<PdfReference> declarations = original.pdf.pages.map((page) => page.reference!).toList();
    final AiNativePageReplacement mapping = changed.pageReplacement(
      source: source,
      pages: [
        for (int index = 0; index < changed.artboards.length; index++) AiNativeArtboardPage(artboard: changed.artboards[index], page: host.document.pages[index].reference!, metadataOwner: null),
      ],
      catalogPages: declarations,
    );
    declarations.clear();
    check(mapping.catalogPages).length.equals(3);
    check(mapping.catalogPages.clear).throws<UnsupportedError>();
    check(() => saveMapped(AiNativePageReplacement(replacement: mapping.replacement, pages: mapping.pages), host.document)).throws<ArgumentError>();
    final AiPdfDocument saved = saveMapped(mapping, host.document);
    check(AiNativeData.extract(saved).single.owners).deepEquals([null, 0, 1]);
    check(nativeBoards(AiNativeData.extract(saved).single).artboards).length.equals(2);
    for (final List<PdfReference> invalid in [
      [mapping.catalogPages.first, mapping.catalogPages.first],
      [const PdfReference(objectNumber: 999999)],
    ]) {
      check(() => saveMapped(AiNativePageReplacement(replacement: mapping.replacement, pages: mapping.pages, catalogPages: invalid), host.document)).throws<ArgumentError>();
    }
    check(() => saveMapped(AiNativePageReplacement(replacement: mapping.replacement, pages: [mapping.pages.first], catalogPages: mapping.catalogPages), host.document)).throws<ArgumentError>();
    final PdfReference removed = original.pdf.pages.first.reference!;
    final PdfEditor altered = PdfEditor(document: host.document)
      ..replaceObject(
        reference: removed,
        value: host.document.dictionary(removed).copyWith(values: {'PieceInfo': PdfDictionary(values: {})}),
      );
    check(() => saveMapped(mapping, altered.document)).throws<ArgumentError>();
    check(AiNativeData.extract(original).single.owners).deepEquals([null]);
  });

  test('cannot claim a separately owned native page through catalog declarations', () {
    final AiPdfDocument original = mappedArtboardSource();
    final AiNativeSource source = AiNativeData.extract(original).single;
    final AiNativePageReplacement mapping = mappedArtboards(source, nativeBoards(source), original.pdf, [0, 1, 2]);
    check(() => saveMapped(AiNativePageReplacement(replacement: mapping.replacement, pages: mapping.pages, catalogPages: [original.pdf.pages.first.reference!]), original.pdf)).throws<ArgumentError>();
    final PdfEditor pagesOnly = PdfEditor(document: original.pdf)
      ..replaceObject(
        reference: original.pdf.trailer['Root']! as PdfReference,
        value: original.pdf.catalog.copyWith(remove: {'PieceInfo'}),
      )
      ..setPageAttributes(pageIndex: 0, remove: {'PieceInfo'});
    final AiPdfDocument withoutCatalog = AiPdfDocument(pdf: pagesOnly.document);
    final AiNativeSource pageSource = AiNativeData.extract(withoutCatalog).single;
    final AiNativePageReplacement pageMapping = mappedArtboards(pageSource, nativeBoards(pageSource), withoutCatalog.pdf, [1, 1, 2]);
    check(() => saveMapped(AiNativePageReplacement(replacement: pageMapping.replacement, pages: pageMapping.pages, catalogPages: [withoutCatalog.pdf.pages.first.reference!]), withoutCatalog.pdf))
        .throws<ArgumentError>();
  });

  test('reorders native boards and host pages with exact per-owner metadata', () {
    final AiPdfDocument original = mappedArtboardSource();
    final AiNativeSource source = AiNativeData.extract(original).single;
    final AiNativeArtboards before = nativeBoards(source);
    final AiNativeArtboards changed = before.reorder(artboards: [before.artboards[2], before.artboards[0], before.artboards[1]], cropBounds: null);
    final PdfEditor host = PdfEditor(document: original.pdf)..movePage(from: 2, to: 0);
    final AiPdfDocument saved = saveMapped(mappedArtboards(source, changed, host.document, [2, 0, 1]), host.document);
    final AiNativeSource recovered = AiNativeData.extract(saved).single;
    check(recovered.owners).deepEquals([null, 0, 1, 2]);
    check(recovered.bytes).deepEquals(changed.records.program.bytes);
    check(saved.pdf.pages.map((page) => page.reference)).deepEquals(host.document.pages.map((page) => page.reference));
    check([
      for (final int index in [0, 1, 2]) metadataPrivate(saved.pdf, index).integer('OwnerSentinel'),
    ]).deepEquals([2, 0, 1]);
    check(metadataPrivate(saved.pdf, null).integer('OwnerSentinel')).equals(-1);
    check(nativeBoards(recovered).activeIndex).equals(0);
    check(() => AiNativeData.replace(source: source, program: changed.records.program.bytes, synchronizedPdf: host.document)).throws<ArgumentError>();
  });

  test('creates a mapped page using explicit metadata and supplied content boxes and resources', () {
    final AiPdfDocument original = mappedArtboardSource();
    final AiNativeSource source = AiNativeData.extract(original).single;
    final AiNativeArtboards changed = nativeBoards(source).create(definition: newArtboard(), index: 1, lastArtboardId: 68, cropBounds: AiBoundingBox(left: -10, bottom: -20, right: 30, top: 40));
    final PdfEditor host = PdfEditor(document: original.pdf)..insertPage(page: PdfPageSource(width: 504, height: 804, content: latin1.encode('0.5 g 0 0 30 40 re f')), index: 1);
    final String resource = host.setPageResource(
      pageIndex: 1,
      category: 'ExtGState',
      prefix: 'Host',
      value: PdfDictionary(values: {'ca': PdfNumber(value: 0.5)}),
    );
    host.setPageAttributes(
      pageIndex: 1,
      values: {
        'PieceInfo': PdfDictionary(values: {'HostProducer': PdfString.text(text: 'retained')}),
      },
    );
    final AiPdfDocument saved = saveMapped(mappedArtboards(source, changed, host.document, [0, null, 1, 2]), host.document);
    check(saved.pdf.pages).length.equals(4);
    check((saved.pdf.pages[1].dictionary['MediaBox']! as PdfArray).values.map((value) => (value as PdfNumber).value)).deepEquals([0, 0, 504, 804]);
    check(PdfProgram.fromPage(document: saved.pdf, pageIndex: 1).operations.last.operator).equals('f');
    final PdfDictionary state = PdfEditor(document: saved.pdf).pageResource(pageIndex: 1, category: 'ExtGState', name: resource) as PdfDictionary;
    check((state['ca']! as PdfNumber).value).equals(0.5);
    check((saved.pdf.dictionary(saved.pdf.pages[1].dictionary['PieceInfo']!)['HostProducer']! as PdfString).text).equals('retained');
    check(metadataPrivate(saved.pdf, 1).integer('OwnerSentinel')).equals(-1);
    check(AiNativeData.extract(saved).single.owners).deepEquals([null, 0, 1, 2, 3]);
    for (final int? owner in [null, 0, 1, 2, 3]) {
      check(latin1.decode(metadataBytes(saved.pdf, owner))).contains('%AI3_Cropmarks: ${-10.0} ${-20.0} ${30.0} ${40.0}');
    }
  });

  test('removes the active board and PDF page while retaining original unreachable objects', () {
    final AiPdfDocument original = mappedArtboardSource();
    final AiNativeSource source = AiNativeData.extract(original).single;
    final AiNativeArtboards before = nativeBoards(source);
    final AiNativeArtboards changed = before.remove(artboards: [before.artboards[2]], activeArtboard: before.artboards[1], cropBounds: null);
    final PdfEditor host = PdfEditor(document: original.pdf)..removePage(pageIndex: 2);
    final AiPdfDocument saved = AiNativeData.replaceMapped(
      replacements: [
        mappedArtboards(source, changed, host.document, [0, 1]),
      ],
      synchronizedPdf: host.document,
    );
    check(saved.pdf.pages).length.equals(2);
    check(saved.pdf.objects[original.pdf.pages[2].reference]).identicalTo(original.pdf.objects[original.pdf.pages[2].reference]);
    final AiNativeSource recovered = AiNativeData.extract(const AiCodec().decode(const AiCodec().encode(saved))).single;
    check(recovered.bytes).deepEquals(changed.records.program.bytes);
    check(nativeBoards(recovered).activeIndex).equals(1);
    check(
      () => AiNativeData.replaceMapped(
        replacements: [
          mappedArtboards(source, changed, saved.pdf, [0, 1]),
        ],
        synchronizedPdf: saved.pdf,
      ),
    ).throws<ArgumentError>();
  });

  for (final MapEntry<String, String> fixture in {'compound clips': artboardTopologySource(), 'shared live shapes': mixedArtboardSource()}.entries) {
    test('reopens every chained artboard save with retained ${fixture.key}', () {
      final AiPdfDocument original = mappedArtboardSource(nativeProgram: fixture.value);
      final AiNativeArtboards initial = nativeBoards(AiNativeData.extract(original).single);
      AiPdfDocument current = original;
      List<int> sentinels = [0, 1, 2];
      for (final String operation in ['create', 'resize', 'reverse', 'remove']) {
        final AiNativeSource source = AiNativeData.extract(current).single;
        final AiNativeArtboards before = nativeBoards(source);
        final PdfEditor host = PdfEditor(document: current.pdf);
        final AiNativeArtboards changed;
        final List<int?> owners;
        switch (operation) {
          case 'create':
            changed = before.create(definition: newArtboard(selected: true), index: 0, lastArtboardId: 68, cropBounds: null);
            host.insertPage(page: PdfPageSource(width: 240, height: 320, content: latin1.encode('0.5 g 2 3 20 30 re f')), index: 0);
            owners = [null, 0, 1, 2];
          case 'resize':
            changed = before.resize(artboard: before.artboards.first, bounds: AiBoundingBox(left: -25, bottom: -950, right: 2000, top: 40), cropBounds: null);
            host.setPageAttributes(
              pageIndex: 0,
              values: {
                'MediaBox': PdfArray(values: [0, 0, 540, 840].map((value) => PdfNumber(value: value))),
              },
            );
            owners = [0, 1, 2, 3];
          case 'reverse':
            changed = before.reorder(artboards: before.artboards.reversed.toList(), cropBounds: null);
            for (int index = 1; index < 4; index++) {
              host.movePage(from: index, to: 0);
            }
            owners = [3, 2, 1, 0];
          case 'remove':
            check(before.activeArtboard).identicalTo(before.artboards.first);
            changed = before.remove(artboards: [before.artboards.first], activeArtboard: before.artboards.last, cropBounds: null);
            host.removePage(pageIndex: 0);
            owners = [1, 2, 3];
          default:
            throw StateError('Unknown artboard operation.');
        }
        final AiPdfDocument saved = saveMapped(mappedArtboards(source, changed, host.document, owners), host.document);
        final AiNativeSource recovered = AiNativeData.extract(saved).single;
        final AiNativeArtboards after = nativeBoards(recovered);
        sentinels = [
          for (final int? owner in owners)
            if (owner == null) -1 else sentinels[owner],
        ];
        check([for (final int index in Iterable.generate(sentinels.length)) metadataPrivate(saved.pdf, index).integer('OwnerSentinel')]).deepEquals(sentinels);
        check(metadataPrivate(saved.pdf, null).integer('OwnerSentinel')).equals(-1);
        check(recovered.owners).deepEquals([null, ...Iterable.generate(sentinels.length)]);
        check(recovered.bytes).deepEquals(changed.records.program.bytes);
        check(after.records.program.bytes.take(after.document.start)).deepEquals(initial.records.program.bytes.take(initial.document.start));
        check(after.records.program.bytes.skip(after.document.end)).deepEquals(initial.records.program.bytes.skip(initial.document.end));
        check(AiNativeData.extract(current).single.bytes).deepEquals(before.records.program.bytes);
        check(saved.pdf.pages.map((page) => page.reference)).deepEquals(host.document.pages.map((page) => page.reference));
        current = saved;
      }
      final AiNativeArtboards finalBoards = nativeBoards(AiNativeData.extract(current).single);
      check(finalBoards.activeArtboard!.identifier).equals('b9ef2db5-64d8-49a5-b02e-b455c61a1f27');
      check(finalBoards.activeArtboard!.bounds.left).equals(-25);
      check(finalBoards.lastArtboardId).equals(68);
      check(sentinels).deepEquals([1, 0, -1]);
      check(AiNativeData.extract(original).single.bytes).deepEquals(latin1.encode(fixture.value));
    });
  }

  test('preserves unselected programs and supports independent mapped batches', () {
    final AiPdfDocument original = multipleNativePrograms();
    final List<AiNativeSource> sources = AiNativeData.extract(original);
    final AiNativeArtboards boards = nativeBoards(sources.first);
    final PdfEditor host = PdfEditor(document: original.pdf)..insertPage(page: PdfPageSource(width: 220, height: 140, content: latin1.encode('q Q')));
    final AiNativePageReplacement first = boards.pageReplacement(
      source: sources.first,
      pages: [
        AiNativeArtboardPage(artboard: boards.artboards.first, page: host.document.pages.first.reference!, metadataOwner: 0),
        AiNativeArtboardPage(artboard: boards.artboards.last, page: host.document.pages.last.reference!, metadataOwner: null),
      ],
    );
    final AiPdfDocument saved = saveMapped(first, host.document);
    final List<AiNativeSource> recovered = AiNativeData.extract(saved);
    check(recovered.first.owners).deepEquals([null, 0, 2]);
    check(recovered.last.owners).deepEquals([1]);
    check(recovered.last.bytes).deepEquals(sources.last.bytes);
    check((saved.pdf.resolve(const PdfReference(objectNumber: 901)) as PdfStream).data).deepEquals([0, 255, 42]);
    check(latin1.decode(recovered.first.bytes)).contains('17 FuturePaint');
    final AiNativePageReplacement second = AiNativePageReplacement(
      replacement: AiNativeReplacement(source: sources.last, program: sources.last.bytes),
      pages: [AiNativePageBinding(page: host.document.pages[1].reference!, metadataOwner: 1)],
    );
    final AiPdfDocument batch = AiNativeData.replaceMapped(replacements: [first, second], synchronizedPdf: host.document);
    check(AiNativeData.extract(batch).map((source) => source.bytes.length)).deepEquals(sources.map((source) => source.bytes.length));
  });

  test('requires every current board exactly once and freezes native page bindings', () {
    final AiPdfDocument original = mappedArtboardSource(opaqueDrawing: true);
    final AiNativeSource source = AiNativeData.extract(original).single;
    final AiNativeArtboards model = nativeBoards(source);
    final AiNativeArtboard foreign = nativeBoards(source).artboards.first;
    final List<AiNativeArtboardPage> pages = [
      for (final (int, AiNativeArtboard) board in model.artboards.indexed) AiNativeArtboardPage(artboard: board.$2, page: original.pdf.pages[board.$1].reference!, metadataOwner: board.$1),
    ];
    check(() => model.pageReplacement(source: source, pages: pages.take(2).toList())).throws<ArgumentError>();
    check(() => model.pageReplacement(source: source, pages: [pages.first, pages.first, pages.last])).throws<ArgumentError>();
    check(
      () => model.pageReplacement(
        source: source,
        pages: [
          AiNativeArtboardPage(artboard: foreign, page: pages.first.page, metadataOwner: 0),
          ...pages.skip(1),
        ],
      ),
    ).throws<ArgumentError>();
    final AiNativePageReplacement bound = model.pageReplacement(source: source, pages: pages.reversed.toList());
    pages.clear();
    check(bound.pages).length.equals(3);
    check(bound.pages.clear).throws<UnsupportedError>();
    check(saveMapped(bound, original.pdf).pdf.pages).length.equals(3);
    final PdfEditor replaced = PdfEditor(document: original.pdf)
      ..insertPage(page: PdfPageSource(width: 100, height: 100, content: []), index: 0)
      ..removePage(pageIndex: 1);
    check(saveMapped(mappedArtboards(source, model, replaced.document, [0, 1, 2]), replaced.document).pdf.pages).length.equals(3);
  });

  test('rejects incomplete reversed foreign duplicate or incorrectly sourced page mappings', () {
    final AiPdfDocument original = mappedArtboardSource();
    final AiNativeSource source = AiNativeData.extract(original).single;
    final AiNativePageReplacement valid = mappedArtboards(source, nativeBoards(source), original.pdf, [0, 1, 2]);
    for (final List<AiNativePageBinding> pages in [
      valid.pages.take(2).toList(),
      valid.pages.reversed.toList(),
      [valid.pages.first, valid.pages.first, valid.pages.last],
      [AiNativePageBinding(page: original.pdf.pages.first.reference!, metadataOwner: 1), ...valid.pages.skip(1)],
      [const AiNativePageBinding(page: PdfReference(objectNumber: 90000), metadataOwner: 0), ...valid.pages.skip(1)],
      [AiNativePageBinding(page: original.pdf.pages.first.reference!, metadataOwner: 99), ...valid.pages.skip(1)],
    ]) {
      final AiNativePageReplacement invalid = AiNativePageReplacement(replacement: valid.replacement, pages: pages);
      check(() => AiNativeData.replaceMapped(replacements: [invalid], synchronizedPdf: original.pdf)).throws<ArgumentError>();
    }
    check(() => AiNativeData.replaceMapped(replacements: [valid, valid], synchronizedPdf: original.pdf)).throws<ArgumentError>();
    final PdfDocument foreign = (const AiCodec().decode(const AiCodec().encode(original)) as AiPdfDocument).pdf;
    check(() => AiNativeData.replaceMapped(replacements: [valid], synchronizedPdf: foreign)).throws<ArgumentError>();
  });

  test('refuses unbound new pages and removal of an unselected native program', () {
    final AiPdfDocument original = multipleNativePrograms();
    final AiNativeSource source = AiNativeData.extract(original).first;
    final AiNativePageReplacement selected = AiNativePageReplacement(
      replacement: AiNativeReplacement(source: source, program: source.bytes),
      pages: [AiNativePageBinding(page: original.pdf.pages.first.reference!, metadataOwner: 0)],
    );
    final PdfEditor added = PdfEditor(document: original.pdf)..insertPage(page: PdfPageSource(width: 10, height: 10, content: []));
    check(() => AiNativeData.replaceMapped(replacements: [selected], synchronizedPdf: added.document)).throws<ArgumentError>();
    final PdfEditor removed = PdfEditor(document: original.pdf)..removePage(pageIndex: 1);
    check(() => AiNativeData.replaceMapped(replacements: [selected], synchronizedPdf: removed.document)).throws<ArgumentError>();
    final PdfEditor moved = PdfEditor(document: original.pdf)..insertPage(page: PdfPageSource(width: 10, height: 10, content: []));
    moved.setPageAttributes(
      pageIndex: 2,
      values: {
        'PieceInfo': PdfDictionary(
          values: {
            'Illustrator': PdfDictionary(values: {'Future': PdfNumber(value: 1)}),
          },
        ),
      },
    );
    final AiNativePageReplacement overwrite = AiNativePageReplacement(
      replacement: selected.replacement,
      pages: [
        ...selected.pages,
        AiNativePageBinding(page: moved.document.pages.last.reference!, metadataOwner: 0),
      ],
    );
    check(() => AiNativeData.replaceMapped(replacements: [overwrite], synchronizedPdf: moved.document)).throws<ArgumentError>();
  });

  test('rejects reachable destinations to removed pages and accepts host-updated destinations', () {
    final AiPdfDocument base = mappedArtboardSource();
    final AiPdfDocument original = AiPdfDocument(
      pdf: hostCatalog(base.pdf, {
        'OpenAction': PdfArray(
          values: [
            base.pdf.pages[2].reference!,
            PdfName(value: 'Fit'),
          ],
        ),
      }),
    );
    final AiNativeSource source = AiNativeData.extract(original).single;
    final AiNativeArtboards boards = nativeBoards(source);
    final AiNativeArtboards changed = boards.remove(artboards: [boards.artboards.last], activeArtboard: boards.artboards.first, cropBounds: null);
    final PdfEditor host = PdfEditor(document: original.pdf)..removePage(pageIndex: 2);
    final AiNativePageReplacement replacement = mappedArtboards(source, changed, host.document, [0, 1]);
    check(() => AiNativeData.replaceMapped(replacements: [replacement], synchronizedPdf: host.document)).throws<UnsupportedError>();
    final PdfDocument fixed = hostCatalog(host.document, {
      'OpenAction': PdfArray(
        values: [
          host.document.pages.first.reference!,
          PdfName(value: 'Fit'),
        ],
      ),
    });
    check(saveMapped(replacement, fixed).pdf.pages).length.equals(2);
  });

  test('requires explicit position-based label policy and validates replacement label starts', () {
    final AiPdfDocument base = mappedArtboardSource();
    final AiPdfDocument original = AiPdfDocument(
      pdf: hostCatalog(base.pdf, {
        'PageLabels': pageLabels([0, 2]),
      }),
    );
    final AiNativeSource source = AiNativeData.extract(original).single;
    final AiNativeArtboards boards = nativeBoards(source);
    final AiNativeArtboards changed = boards.reorder(artboards: boards.artboards.reversed.toList(), cropBounds: null);
    final PdfEditor host = PdfEditor(document: original.pdf)
      ..movePage(from: 2, to: 0)
      ..movePage(from: 2, to: 1);
    final AiNativePageReplacement replacement = mappedArtboards(source, changed, host.document, [2, 1, 0]);
    check(() => AiNativeData.replaceMapped(replacements: [replacement], synchronizedPdf: host.document)).throws<UnsupportedError>();
    check(saveMapped(replacement, host.document, pageLabels: .retainPositions).pdf.pages).length.equals(3);
    check(
      saveMapped(
        replacement,
        hostCatalog(host.document, {
          'PageLabels': pageLabels([0, 1]),
        }),
      ).pdf.pages,
    ).length.equals(3);
    check(saveMapped(replacement, hostCatalog(host.document, {}, remove: {'PageLabels'})).pdf.pages).length.equals(3);
    for (final List<int> starts in [
      [1],
      [0, 0],
      [0, -1],
      [0, 3],
    ]) {
      check(() => AiNativeData.replaceMapped(replacements: [replacement], synchronizedPdf: hostCatalog(host.document, {'PageLabels': pageLabels(starts)}))).throws<FormatException>();
    }
  });

  test('rejects captured dangling page identities and newly dangling references', () {
    final AiPdfDocument base = mappedArtboardSource();
    const PdfReference dangling = PdfReference(objectNumber: 90000);
    final AiPdfDocument original = AiPdfDocument(pdf: hostCatalog(base.pdf, {'Witness': dangling}));
    final AiNativeSource source = AiNativeData.extract(original).single;
    final AiNativeArtboards boards = nativeBoards(source).create(definition: newArtboard(), index: 3, lastArtboardId: 68, cropBounds: null);
    final PdfEditor host = PdfEditor(document: original.pdf)..insertPage(page: PdfPageSource(width: 10, height: 10, content: []));
    final PdfReference tree = host.document.catalog['Pages']! as PdfReference;
    final PdfDocument captured = host.document.copyWith(
      objects: {
        ...host.document.objects,
        dangling: host.document.pages.last.dictionary,
        tree: host.document
            .dictionary(tree)
            .copyWith(
              values: {
                'Kids': PdfArray(values: [...host.document.pages.take(3).map((page) => page.reference!), dangling]),
              },
            ),
      },
    );
    check(
      () => AiNativeData.replaceMapped(
        replacements: [
          mappedArtboards(source, boards, captured, [0, 1, 2, 0]),
        ],
        synchronizedPdf: captured,
      ),
    ).throws<ArgumentError>();
    final PdfDocument broken = hostCatalog(host.document, {'NewWitness': const PdfReference(objectNumber: 90001)});
    check(
      () => AiNativeData.replaceMapped(
        replacements: [
          mappedArtboards(source, boards, broken, [0, 1, 2, 0]),
        ],
        synchronizedPdf: broken,
      ),
    ).throws<FormatException>();
    check(saveMapped(mappedArtboards(source, boards, host.document, [0, 1, 2, 0]), host.document).pdf.pages).length.equals(4);
  });

  test('retains immutable source graphs and rejects metadata mutations and inspection excesses', () {
    final AiPdfDocument original = mappedArtboardSource();
    final AiNativeSource source = AiNativeData.extract(original).single;
    final AiNativePageReplacement mapping = mappedArtboards(source, nativeBoards(source), original.pdf, [0, 1, 2]);
    final List<int> before = const AiCodec().encode(original);
    for (final AiNativeLimits limits in [const AiNativeLimits(maxTokens: 1), const AiNativeLimits(maxDepth: 1), const AiNativeLimits(maxDecodedBytes: 1)]) {
      check(() => AiNativeData.replaceMapped(replacements: [mapping], synchronizedPdf: original.pdf, limits: limits)).throws<FormatException>();
    }
    final PdfReference cache = metadataPrivate(original.pdf, 0)['AIMetaData']! as PdfReference;
    final PdfEditor changed = PdfEditor(document: original.pdf)
      ..replaceObject(
        reference: cache,
        value: PdfString.text(text: 'changed'),
      );
    check(() => AiNativeData.replaceMapped(replacements: [mapping], synchronizedPdf: changed.document)).throws<ArgumentError>();
    final PdfReference content = original.pdf.pages.first.dictionary['Contents']! as PdfReference;
    final Map<PdfReference, PdfValue> missingContent = {...original.pdf.objects}..remove(content);
    check(
      () => AiNativeData.replaceMapped(
        replacements: [mapping],
        synchronizedPdf: original.pdf.copyWith(objects: missingContent),
      ),
    ).throws<FormatException>();
    check(const AiCodec().encode(original)).deepEquals(before);
  });

  test('checks removed-page references only in metadata retained by the resulting graph', () {
    for (final int ownerIndex in [0, 2]) {
      final AiPdfDocument base = mappedArtboardSource();
      final PdfPage page = base.pdf.pages[ownerIndex];
      final PdfDictionary pieces = base.pdf.dictionary(page.dictionary['PieceInfo']!);
      final PdfDictionary illustrator = base.pdf.dictionary(pieces['Illustrator']!);
      final PdfEditor prepared = PdfEditor(document: base.pdf)
        ..replaceObject(
          reference: page.reference!,
          value: page.dictionary.copyWith(
            values: {
              'PieceInfo': pieces.copyWith(
                values: {
                  'Illustrator': illustrator.copyWith(
                    values: {
                      'Private': metadataPrivate(base.pdf, ownerIndex).copyWith(values: {'PageReference': base.pdf.pages.last.reference!}),
                    },
                  ),
                },
              ),
            },
          ),
        );
      final AiPdfDocument original = AiPdfDocument(pdf: prepared.document);
      final AiNativeSource source = AiNativeData.extract(original).single;
      final AiNativeArtboards boards = nativeBoards(source);
      final AiNativeArtboards changed = boards.remove(artboards: [boards.artboards.last], activeArtboard: boards.artboards.first, cropBounds: null);
      final PdfEditor host = PdfEditor(document: original.pdf)..removePage(pageIndex: 2);
      final AiNativePageReplacement replacement = mappedArtboards(source, changed, host.document, [0, 1]);
      if (ownerIndex == 0) {
        check(() => AiNativeData.replaceMapped(replacements: [replacement], synchronizedPdf: host.document)).throws<UnsupportedError>();
      } else {
        check(saveMapped(replacement, host.document).pdf.pages).length.equals(2);
      }
    }
  });

  test('validates nested label ranges styles counters and cycles', () {
    final AiPdfDocument original = mappedArtboardSource();
    final AiNativeSource source = AiNativeData.extract(original).single;
    final AiNativePageReplacement replacement = mappedArtboards(source, nativeBoards(source), original.pdf, [0, 1, 2]);
    final PdfEditor host = PdfEditor(document: original.pdf);
    final PdfReference first = host.addObject(
      value: pageLabels([0]).copyWith(
        values: {
          'Limits': PdfArray(values: [PdfNumber(value: 0), PdfNumber(value: 0)]),
        },
      ),
    );
    final PdfReference second = host.addObject(
      value: pageLabels([2]).copyWith(
        values: {
          'Limits': PdfArray(values: [PdfNumber(value: 2), PdfNumber(value: 2)]),
        },
      ),
    );
    final PdfDictionary tree = PdfDictionary(
      values: {
        'Kids': PdfArray(values: [first, second]),
      },
    );
    check(saveMapped(replacement, hostCatalog(host.document, {'PageLabels': tree})).pdf.pages).length.equals(3);
    final PdfDictionary invalidLimits = pageLabels([0]).copyWith(
      values: {
        'Limits': PdfArray(values: [PdfNumber(value: 0), PdfNumber(value: 2)]),
      },
    );
    for (final PdfDictionary labels in [
      invalidLimits,
      PdfDictionary(
        values: {
          'Nums': PdfArray(values: [PdfNumber(value: 0)]),
        },
      ),
      for (final Map<String, PdfValue> fields in [
        {'S': PdfName(value: 'Unknown')},
        {'St': PdfNumber(value: 0)},
        {'P': PdfNumber(value: 1)},
      ])
        PdfDictionary(
          values: {
            'Nums': PdfArray(
              values: [
                PdfNumber(value: 0),
                PdfDictionary(values: fields),
              ],
            ),
          },
        ),
    ]) {
      check(() => AiNativeData.replaceMapped(replacements: [replacement], synchronizedPdf: hostCatalog(original.pdf, {'PageLabels': labels}))).throws<FormatException>();
    }
    final PdfReference cycle = host.addObject(value: PdfDictionary());
    host.replaceObject(
      reference: cycle,
      value: PdfDictionary(
        values: {
          'Kids': PdfArray(values: [cycle]),
        },
      ),
    );
    check(() => AiNativeData.replaceMapped(replacements: [replacement], synchronizedPdf: hostCatalog(host.document, {'PageLabels': cycle}))).throws<FormatException>();
  });
}
