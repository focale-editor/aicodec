import 'dart:convert';

import 'package:checks/checks.dart';
import 'package:illustratorkit/illustratorkit.dart';
import 'package:test/test.dart';

import 'ai_native_artboard_lifecycle_test.dart' show artboardText, newArtboard;
import 'ai_native_artboards_test.dart' show artboardModel, artboardSource, mixedArtboardSource;
import 'ai_native_page_save_test.dart' show mappedArtboardSource, mappedArtboards, nativeBoards, saveMapped;

/// Adds distinct all flags, ranges and unrelated print choices to a native source.
String printJobSource({String artboards = '(1,3)', String pages = '()', int allArtboards = 0, int allPages = 1, String? source}) => (source ?? artboardSource()).replaceFirst(
  '%_67 /Int (LastArtboardID) ,',
  '''%_67 /Int (LastArtboardID) ,
%_/Dictionary : /NotRecorded ,
%_$allArtboards /Int (/attributes/job.printallartboards) ,
%_$artboards /UnicodeString (/attributes/job.artboardrange) ,
%_$allPages /Int (/attributes/job.printall) ,
%_$pages /String (/attributes/job.pagerange) ,
%_1 /Int (/attributes/job.collate) ,
%_0 /Int (/attributes/job.reverseorder) ,
%_; (AI11 Print JobInfo Dict) ,''',
);

/// Decodes native ASCII or BOM-marked range bytes for exact string assertions.
String printRange(AiNativeArtboards model, {bool pages = false}) => latin1.decode(pages ? model.printJob!.pageRangeBytes! : model.printJob!.artboardRangeBytes!);

/// Exercises saved selection remapping independently of printed-page composition.
void main() {
  test('reads stored ranges separately from all flags and preserves dormant choices', () {
    final AiNativeArtboards model = artboardModel(printJobSource(artboards: '( 3, 1-2,2 )', pages: '(2-)', allArtboards: 1, allPages: 0));
    final AiNativePrintJob job = model.printJob!;
    check(job.document).identicalTo(model.document);
    check(job.records).identicalTo(model.records);
    check(job.allArtboards).equals(true);
    check(job.allPages).equals(false);
    check(job.artboardIndices!).deepEquals([0, 1, 2]);
    check(job.pageIndices(pageCount: 5)!).deepEquals([1, 2, 3, 4]);
    check(printRange(model)).equals(' 3, 1-2,2 ');
    check(job.artboardIndices!.clear).throws<UnsupportedError>();
    check(() => job.artboardRangeBytes![0] = 0).throws<UnsupportedError>();
    check(artboardModel(artboardSource()).printJob).isNull();
  });

  test('remaps identities through insertion reordering and removal without selecting new boards', () {
    final AiNativeArtboards original = artboardModel(printJobSource());
    final AiNativeArtboards inserted = original.create(definition: newArtboard(), index: 0, lastArtboardId: 68, cropBounds: null);
    check(printRange(inserted)).equals('2,4');
    final AiNativeArtboards reordered = inserted.reorder(artboards: [inserted.artboards[3], inserted.artboards[2], inserted.artboards[0], inserted.artboards[1]], cropBounds: null);
    check(printRange(reordered)).equals('1,4');
    final AiNativeArtboards removed = reordered.remove(artboards: [reordered.artboards.first], activeArtboard: reordered.artboards.last, cropBounds: null);
    check(printRange(removed)).equals('3');
    check(removed.printJob!.allArtboards).equals(false);
    check(removed.artboards[removed.printJob!.artboardIndices!.single].identifier).equals('board-0');
    check(printRange(original)).equals('1,3');
  });

  test('requires an explicit choice when removal exhausts an active print selection', () {
    final AiNativeArtboards model = artboardModel(printJobSource(artboards: '(1)'));
    check(() => model.remove(artboards: [model.artboards.first], activeArtboard: null, cropBounds: null)).throws<UnsupportedError>();
    final AiNativeArtboards all = model.remove(artboards: [model.artboards.first], activeArtboard: null, cropBounds: null, artboardPrinting: AiNativePrintSelection(count: 2, indices: null));
    check(all.printJob!.allArtboards).equals(true);
    check(printRange(all)).equals('');
    final AiNativeArtboards selected = model.remove(
      artboards: [model.artboards.first],
      activeArtboard: null,
      cropBounds: null,
      artboardPrinting: AiNativePrintSelection(count: 2, indices: [1]),
    );
    check(printRange(selected)).equals('2');
    final AiNativeArtboards dormant = artboardModel(printJobSource(artboards: '(1)', allArtboards: 1));
    check(printRange(dormant.remove(artboards: [dormant.artboards.first], activeArtboard: null, cropBounds: null))).equals('');
  });

  test('preserves exact unchanged ranges flags and unrelated print settings', () {
    final String source = printJobSource(artboards: '( 1, 3 )', pages: '(2-4)', allPages: 0);
    final AiNativeArtboards model = artboardModel(source);
    check(model.reorder(artboards: model.artboards, cropBounds: null)).identicalTo(model);
    check(model.resize(artboard: model.artboards.first, bounds: model.artboards.first.bounds, cropBounds: null)).identicalTo(model);
    final AiNativeArtboards explicit = model.reorder(
      artboards: model.artboards,
      cropBounds: null,
      artboardPrinting: AiNativePrintSelection(count: 3, indices: [2, 0]),
      pagePrinting: AiNativePrintSelection(count: 7, indices: [1, 2, 3]),
    );
    check(artboardText(explicit)).equals(source.replaceFirst('( 1, 3 )', r'(\061\054\063)'));
    check(explicit.printJob!.record['/attributes/job.collate']!.number).equals(1);
    check(explicit.printJob!.record['/attributes/job.reverseorder']!.number).equals(0);
  });

  test('requires host physical-page choices after geometry or ordinal edits', () {
    final AiNativeArtboards model = artboardModel(printJobSource(pages: '(1-2)', allPages: 0));
    final AiBoundingBox bounds = AiBoundingBox(left: -10, bottom: -10, right: 200, top: 120);
    check(() => model.resize(artboard: model.artboards.first, bounds: bounds, cropBounds: null)).throws<UnsupportedError>();
    check(() => model.reorder(artboards: model.artboards.reversed.toList(), cropBounds: null)).throws<UnsupportedError>();
    check(() => model.create(definition: newArtboard(), index: 1, lastArtboardId: 68, cropBounds: null)).throws<UnsupportedError>();
    check(() => model.remove(artboards: [model.artboards[1]], activeArtboard: null, cropBounds: null)).throws<UnsupportedError>();
    check(
      () => model.reorder(
        artboards: model.artboards,
        cropBounds: null,
        artboardPrinting: AiNativePrintSelection(count: 3, indices: [1]),
      ),
    ).throws<UnsupportedError>();
    final AiNativeArtboards resized = model.resize(
      artboard: model.artboards.first,
      bounds: bounds,
      cropBounds: null,
      pagePrinting: AiNativePrintSelection(count: 12, indices: [0, 1, 4, 10, 11]),
    );
    check(printRange(resized, pages: true)).equals('1-2,5,11-12');
    check(resized.printJob!.pageIndices(pageCount: 12)!).deepEquals([0, 1, 4, 10, 11]);
    check(resized.artboards).length.equals(3);
    final AiNativeArtboards all = resized.resize(artboard: resized.artboards.first, bounds: bounds, cropBounds: null, pagePrinting: AiNativePrintSelection(count: 12, indices: null));
    check(all.printJob!.allPages).equals(true);
    check(printRange(all, pages: true)).equals('');
  });

  test('supports bounded open ranges fragmented strings and explicit UTF16 byte order', () {
    for (final String literal in ['(2-)', '(2)(-3)', '(2)% keep range trivia\n%_(-3)', '<322d33>', '<feff0032002d0033>', '<fffe32002d003300>']) {
      final AiNativeArtboards model = artboardModel(printJobSource(artboards: literal));
      check(model.printJob!.artboardIndices!).deepEquals([1, 2]);
      final AiNativeArtboards changed = model.reorder(artboards: [model.artboards[1], model.artboards[0], model.artboards[2]], cropBounds: null);
      check(changed.printJob!.artboardIndices!).deepEquals([0, 2]);
      final List<int> bytes = changed.printJob!.artboardRangeBytes!;
      if (literal.startsWith('<feff')) {
        check(bytes).deepEquals([254, 255, 0, 49, 0, 44, 0, 51]);
      } else if (literal.startsWith('<fffe')) {
        check(bytes).deepEquals([255, 254, 49, 0, 44, 0, 51, 0]);
      } else {
        check(bytes).deepEquals(latin1.encode('1,3'));
      }
      if (literal.contains('% keep')) {
        check(artboardText(changed)).contains('% keep range trivia');
      }
    }
  });

  test('writes empty operand fields and freezes host selections with exact counts', () {
    final AiNativeArtboards model = artboardModel(printJobSource(artboards: '', pages: '', allArtboards: 1));
    final List<int> indices = [2, 0];
    final AiNativePrintSelection selection = AiNativePrintSelection(count: 3, indices: indices);
    indices.clear();
    check(selection.indices!).deepEquals([0, 2]);
    check(selection.indices!.clear).throws<UnsupportedError>();
    final AiNativeArtboards changed = model.reorder(
      artboards: model.artboards,
      cropBounds: null,
      artboardPrinting: selection,
      pagePrinting: AiNativePrintSelection(count: 8, indices: [7]),
    );
    check(printRange(changed)).equals('1,3');
    check(printRange(changed, pages: true)).equals('8');
    check(changed.printJob!.allPages).equals(false);
    check(() => model.create(definition: newArtboard(), index: 0, lastArtboardId: 68, cropBounds: null, artboardPrinting: selection)).throws<ArgumentError>();
    for (final int count in [0, -1, 9007199254740992]) {
      check(() => AiNativePrintSelection(count: count, indices: null)).throws<ArgumentError>();
      check(() => model.printJob!.pageIndices(pageCount: count)).throws<ArgumentError>();
    }
    for (final List<int> invalid in [
      [],
      [-1],
      [3],
      [1, 1],
    ]) {
      check(() => AiNativePrintSelection(count: 3, indices: invalid)).throws<ArgumentError>();
    }
  });

  test('rejects malformed endpoints encodings flags and unknown range grammars atomically', () {
    for (final String range in ['(0)', '(4)', '(3-2)', '(1-4)', '(99999999999999999999)', '<feff00>']) {
      final AiNativeArtboards model = artboardModel(printJobSource(artboards: range));
      check(() => model.printJob!.artboardIndices).throws<FormatException>();
      check(() => model.reorder(artboards: model.artboards.reversed.toList(), cropBounds: null)).throws<FormatException>();
    }
    for (final String range in ['(odd)', '(1,)', '(-2)', '(1;2)', '<0031>', '<feff1234>']) {
      final AiNativeArtboards model = artboardModel(printJobSource(artboards: range));
      check(() => model.printJob!.artboardIndices).throws<UnsupportedError>();
    }
    for (final int flag in [-1, 2]) {
      final AiNativeArtboards model = artboardModel(printJobSource(allArtboards: flag));
      check(() => model.printJob!.allArtboards).throws<FormatException>();
      check(() => model.create(definition: newArtboard(), index: 0, lastArtboardId: 68, cropBounds: null)).throws<FormatException>();
    }
    check(
      () => artboardModel(
        printJobSource().replaceFirst('%_0 /Int (/attributes/job.printallartboards) ,', '%_0 /Int (/attributes/job.printallartboards) ,\n%_1 /Int (/attributes/job.printallartboards) ,'),
      ),
    ).throws<FormatException>();
  });

  test('keeps absent fields distinct and requires complete existing supplied choices', () {
    final AiNativePrintSelection selection = AiNativePrintSelection(count: 3, indices: null);
    final AiNativeArtboards absent = artboardModel(artboardSource());
    check(() => absent.reorder(artboards: absent.artboards, cropBounds: null, artboardPrinting: selection)).throws<UnsupportedError>();
    final String source = printJobSource().replaceFirst('%_(1,3) /UnicodeString (/attributes/job.artboardrange) ,', '');
    final AiNativeArtboards missing = artboardModel(source);
    check(missing.printJob!.artboardIndices).isNull();
    check(() => missing.reorder(artboards: missing.artboards, cropBounds: null, artboardPrinting: selection)).throws<UnsupportedError>();
    final AiNativeArtboards unknown = artboardModel(printJobSource().replaceFirst('%_0 /Int (/attributes/job.printallartboards) ,', ''));
    check(unknown.printJob!.allArtboards).isNull();
    check(printRange(unknown.create(definition: newArtboard(), index: 0, lastArtboardId: 68, cropBounds: null))).equals('2,4');
  });

  test('preserves CC pairs resources byte limits and bounded range expansion', () {
    final String source = printJobSource(source: mixedArtboardSource());
    final AiNativeArtboards model = artboardModel(source);
    final AiNativeArtboards changed = model.create(definition: newArtboard(), index: 1, lastArtboardId: 68, cropBounds: null);
    check(changed.records.program.bytes.sublist(changed.records.program.bodyStart)).deepEquals(model.records.program.bytes.sublist(model.records.program.bodyStart));
    check(AiNativeDrawing.decode(records: changed.records).liveShapes).length.equals(2);
    final AiNativeArtboards limited = artboardModel(source, limits: AiNativeLimits(maxDecodedBytes: source.length));
    check(
      () => limited.reorder(
        artboards: limited.artboards,
        cropBounds: null,
        pagePrinting: AiNativePrintSelection(count: 1000, indices: [999]),
      ),
    ).throws<FormatException>();
    final AiNativeArtboards pages = artboardModel(printJobSource(pages: '(1-)'), limits: const AiNativeLimits(maxTokens: 10000));
    check(() => pages.printJob!.pageIndices(pageCount: 10001)).throws<AiLimitException>();
    check(artboardText(limited)).equals(source);
  });

  test('serializes remapped print choices with explicit host PDF pages and shared owners', () {
    final AiPdfDocument base = mappedArtboardSource();
    final AiNativeSource originalSource = AiNativeData.extract(base).single;
    final AiPdfDocument original = AiNativeData.replace(
      source: originalSource,
      program: latin1.encode(printJobSource(source: latin1.decode(originalSource.bytes))),
      synchronizedPdf: base.pdf,
    );
    final AiNativeSource source = AiNativeData.extract(original).single;
    final AiNativeArtboards model = nativeBoards(source);
    final AiNativeArtboards changed = model.reorder(artboards: [model.artboards[2], model.artboards[0], model.artboards[1]], cropBounds: null);
    final PdfEditor host = PdfEditor(document: original.pdf)..movePage(from: 2, to: 0);
    final AiPdfDocument saved = saveMapped(mappedArtboards(source, changed, host.document, [2, 0, 1]), host.document);
    final AiNativeSource recovered = AiNativeData.extract(saved).single;
    check(recovered.owners).deepEquals([null, 0, 1, 2]);
    check(recovered.bytes).deepEquals(changed.records.program.bytes);
    check(printRange(nativeBoards(recovered))).equals('1-2');
    check(saved.pdf.pages).length.equals(3);
  });
}
