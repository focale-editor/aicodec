import 'dart:convert';
import 'dart:io';

import 'package:aikit/aikit.dart';

import '../test/ai_native_artboard_lifecycle_test.dart' show newArtboard;
import '../test/ai_native_page_save_test.dart' show mappedArtboardSource, mappedArtboards, nativeBoards;
import '../test/ai_native_save_test.dart' show multipleNativePrograms;
import 'check_native_artboards.dart' show artboardInventory;

/// Replaces one page identity using supplied original artwork and nonnative data.
PdfDocument replacedFirstPage(PdfDocument original) {
  final PdfPage page = original.pages.first;
  final PdfEditor host = PdfEditor(document: original)
    ..insertPage(page: PdfPageSource(width: 1, height: 1, content: []), index: 0)
    ..removePage(pageIndex: 1);
  host.setPageAttributes(
    pageIndex: 0,
    values: {
      ...page.inherited.values,
      for (final MapEntry<String, PdfValue> field in page.dictionary.values.entries)
        if (!const {'Type', 'Parent', 'PieceInfo'}.contains(field.key)) field.key: field.value,
      if (page.dictionary['PieceInfo'] case final PdfValue pieces) 'PieceInfo': original.dictionary(pieces).copyWith(remove: {'Illustrator'}),
    },
  );
  return host.document;
}

/// Emits complete native and PDF mappings for independent round-trip validation.
Future<void> main() async {
  final Directory output = await Directory('test/corpus/output/page-saves').create(recursive: true);
  final List<Map<String, Object?>> rows = [];

  /// Retains source programs, explicit metadata templates and host appearances.
  Future<void> record(
    String name,
    AiPdfDocument original,
    PdfDocument host,
    List<AiNativePageReplacement> replacements,
    List<int?> appearances, {
    String? fixture,
    AiNativeArtboards? before,
    AiNativeArtboards? after,
    String operation = 'none',
  }) async {
    if (fixture == null) {
      await File('${output.path}/$name.original.ai').writeAsBytes(const AiCodec().encode(original));
    }
    await File('${output.path}/$name.host.pdf').writeAsBytes(const PdfCodec().encode(host));
    final List<AiNativeSource> sources = AiNativeData.extract(original);
    final List<Map<String, Object?>> programs = [];
    for (final (int, AiNativeSource) source in sources.indexed) {
      final AiNativePageReplacement? replacement = replacements.where((entry) {
        final List<int?> owners = entry.replacement.source.owners;
        return owners.length == source.$2.owners.length && owners.indexed.every((owner) => owner.$2 == source.$2.owners[owner.$1]);
      }).firstOrNull;
      await File('${output.path}/$name.${source.$1}.before.ps').writeAsBytes(source.$2.bytes);
      await File('${output.path}/$name.${source.$1}.after.ps').writeAsBytes(replacement?.replacement.program ?? source.$2.bytes);
      programs.add({
        'owners': source.$2.owners,
        'selected': replacement != null,
        'pages': [
          for (final AiNativePageBinding binding in replacement?.pages ?? []) {'index': host.pages.indexWhere((page) => page.reference == binding.page), 'metadataOwner': binding.metadataOwner},
        ],
      });
    }
    final AiPdfDocument saved = AiNativeData.replaceMapped(replacements: replacements, synchronizedPdf: host);
    await File('${output.path}/$name.saved.ai').writeAsBytes(const AiCodec().encode(saved));
    rows.add({
      'name': name,
      'fixture': fixture,
      'operation': operation,
      'appearances': appearances,
      'programs': programs,
      if (before != null) 'before': artboardInventory(before),
      if (after != null) 'after': artboardInventory(after),
    });
    stdout.writeln('$name passed');
  }

  for (final String name in ['simple_cc_legacy.ai', 'simple_v2020_no_pdf_data.ai', 'reuters-preview-dev.ai']) {
    final AiPdfDocument original = const AiCodec().decode(await File('test/corpus/files/$name').readAsBytes()) as AiPdfDocument;
    final AiNativeSource source = AiNativeData.extract(original).single;
    final AiNativeArtboards boards = nativeBoards(source);
    final PdfDocument host = replacedFirstPage(original.pdf);
    await record(
      name,
      original,
      host,
      [mappedArtboards(source, boards, host, List.generate(host.pages.length, (index) => index))],
      List.generate(host.pages.length, (index) => index),
      fixture: name,
      before: boards,
      after: boards,
    );
  }
  for (final String operation in ['create', 'remove', 'reorder', 'resize']) {
    final AiPdfDocument original = mappedArtboardSource();
    final AiNativeSource source = AiNativeData.extract(original).single;
    final AiNativeArtboards boards = nativeBoards(source);
    final PdfEditor host = PdfEditor(document: original.pdf);
    final AiNativeArtboards changed;
    final List<int?> owners;
    final List<int?> appearances;
    switch (operation) {
      case 'create':
        changed = boards.create(definition: newArtboard(), index: 1, lastArtboardId: 68, cropBounds: AiBoundingBox(left: -10, bottom: -20, right: 30, top: 40));
        host.insertPage(page: PdfPageSource(width: 504, height: 804, content: latin1.encode('0.5 g 0 0 30 40 re f')), index: 1);
        owners = [0, null, 1, 2];
        appearances = [0, null, 1, 2];
      case 'remove':
        changed = boards.remove(artboards: [boards.artboards[2]], activeArtboard: boards.artboards[1], cropBounds: null);
        host.removePage(pageIndex: 2);
        owners = [0, 1];
        appearances = [0, 1];
      case 'reorder':
        changed = boards.reorder(artboards: [boards.artboards[2], boards.artboards[0], boards.artboards[1]], cropBounds: null);
        host.movePage(from: 2, to: 0);
        owners = [2, 0, 1];
        appearances = [2, 0, 1];
      case 'resize':
        changed = boards.resize(artboard: boards.artboards.first, bounds: AiBoundingBox(left: -10, bottom: -20, right: 500, top: 800), cropBounds: null);
        host.setPageAttributes(
          pageIndex: 0,
          values: {
            'MediaBox': PdfArray(values: [0, 0, 540, 840].map((value) => PdfNumber(value: value))),
          },
        );
        owners = [0, 1, 2];
        appearances = [0, 1, 2];
      default:
        throw StateError('Unknown artboard transaction.');
    }
    await record('synthetic-$operation', original, host.document, [mappedArtboards(source, changed, host.document, owners)], appearances, before: boards, after: changed, operation: operation);
  }
  for (final bool batch in [false, true]) {
    final AiPdfDocument original = multipleNativePrograms();
    final List<AiNativeSource> sources = AiNativeData.extract(original);
    final AiNativeArtboards boards = nativeBoards(sources.first);
    final PdfEditor host = PdfEditor(document: original.pdf)..insertPage(page: PdfPageSource(width: 220, height: 140, content: latin1.encode('q Q')));
    final List<AiNativePageReplacement> replacements = [
      boards.pageReplacement(
        source: sources.first,
        pages: [
          AiNativeArtboardPage(artboard: boards.artboards.first, page: host.document.pages.first.reference!, metadataOwner: 0),
          AiNativeArtboardPage(artboard: boards.artboards.last, page: host.document.pages.last.reference!, metadataOwner: null),
        ],
      ),
      if (batch)
        AiNativePageReplacement(
          replacement: AiNativeReplacement(source: sources.last, program: sources.last.bytes),
          pages: [AiNativePageBinding(page: host.document.pages[1].reference!, metadataOwner: 1)],
        ),
    ];
    await record(batch ? 'synthetic-batch' : 'synthetic-selected', original, host.document, replacements, [0, 1, null]);
  }
  await File('${output.path}/report.json').writeAsString('${const JsonEncoder.withIndent('  ').convert(rows)}\n');
}
