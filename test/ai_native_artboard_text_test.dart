import 'dart:convert';

import 'package:checks/checks.dart';
import 'package:illustratorkit/illustratorkit.dart';
import 'package:test/test.dart';

import 'ai_native_artboard_lifecycle_test.dart' show artboardText, newArtboard;
import 'ai_native_artboard_references_test.dart' show artboardReferenceSource;
import 'ai_native_artboards_test.dart' show artboardModel;
import 'ai_native_objects_test.dart' show objectDictionary;
import 'ai_native_page_save_test.dart' show mappedArtboardSource, mappedArtboards, nativeBoards, saveMapped;

/// Describes point, area and path frames, two stories and local composition data.
String artboardTextEngineSource({int version = 9}) {
  final String text = latin1.decode(PsEngineCodec.encode(value: PsEngineString.fromText(text: 'A 🖋\r')));
  return '''/98 << /0 $version >> /0 << /8 << /0 [
<< /0 << /97 (point) /0 [12 34] /2 << /2 [1 0 0 1 4 5] >> >> >>
<< /0 << /97 (area) /1 << /0 [0 0 1 2 3 4 10 20] >> /2 << /0 1 /2 [0 1 -1 0 50 60] /3 2 /4 3 /5 false /10 << /0 2 /1 4 >> >> >> >>
<< /0 << /97 (path) /1 << /0 [0 0 1 2 3 4 10 20] >> /2 << /0 2 /6 [0.25 0.75] /11 << /0 true /4 10 /6 false /7 true /18 10.0 >> >> >> >>
] /1 [ << /0 2 >> ] >> >> /1 << /1 [
<< /0 << /0 $text /10 << /0 2 >> >> /1 << /0 [ << /0 1 >> << /0 0 >> ]
/1 << /0 (local cache) >> /2 [ << /99 /F /10 1 /6 [ << /99 /G /5 [10 11 1] /24 (glyph cache) >> ] >> ] >> >>
<< /0 << /0 $text >> /1 << /0 [ << /0 2 >> ] /2 [ << /99 /F /10 2 >> ] >> >>
] >>''';
}

/// Keeps a complete unpainted source curve and its separate rotation metadata.
const String artboardTextConfinement = 'X= 1 Ap 2 As 0 0 m 1 2 3 4 10 20 c N /ArtDictionary : (0.4) /String (BBAccumRotation) , ; X+';

/// Declares explicit drawing-to-story slots with attached text-local identities.
String artboardTextDrawing({int snapshot = 0, String confinement = artboardTextConfinement}) =>
    '''0 A 0 Xw 0 0 Xd 1 (board-0) XW
/AI11Text : $snapshot /FreeUndo , 0 /StoryIndex , 0 /FrameIndex , /Art : $confinement ; /ConfiningPath , 2 /TextAntialiasing , ;
/ArtDictionary : (story-zero) /UnicodeString (AI24 TextStoryRawDataUUID) , ;
/AI11Text : $snapshot /FreeUndo , 0 /StoryIndex , 1 /FrameIndex , ;
${objectDictionary(identifier: 'point_text')}
/AI11Text : $snapshot /FreeUndo , 1 /StoryIndex , 0 /FrameIndex , /Art : $confinement ; /ConfiningPath , ;
6 () XW
''';

/// Builds independent main/undo-free snapshots, retaining source-encoded caches.
String populatedArtboardSource({String? main, String? undo, String? body, bool withUndo = true}) => artboardReferenceSource(
  main: PsEngineDocument.decode(bytes: latin1.encode(main ?? artboardTextEngineSource())).root,
  undo: undo == null ? null : PsEngineDocument.decode(bytes: latin1.encode(undo)).root,
  withUndo: withUndo,
  body: body ?? artboardTextDrawing(),
);

/// Requires every byte outside the selected native Document to remain identical.
void _retained(AiNativeArtboards before, AiNativeArtboards after) {
  check(after.records.program.bytes.take(after.document.start)).deepEquals(before.records.program.bytes.take(before.document.start));
  check(after.records.program.bytes.skip(after.document.end)).deepEquals(before.records.program.bytes.skip(before.document.end));
}

/// Checks retained text namespaces, geometry, caches and atomic failure behavior.
void main() {
  for (final int version in [7, 9]) {
    test('retains populated compact ATE $version across all artboard operations', () {
      final AiNativeArtboards before = artboardModel(populatedArtboardSource(main: artboardTextEngineSource(version: version)));
      final AiNativeArtboards resized = before.resize(artboard: before.artboards.first, bounds: AiBoundingBox(left: -30, bottom: -200, right: 400, top: 500), cropBounds: null);
      final AiNativeArtboards added = resized.create(definition: newArtboard(), index: 0, lastArtboardId: 68, cropBounds: null);
      final AiNativeArtboards reversed = added.reorder(artboards: added.artboards.reversed.toList(), cropBounds: null);
      final AiNativeArtboards removed = reversed.remove(artboards: [reversed.artboards.first], activeArtboard: reversed.artboards.last, cropBounds: null);
      for (final AiNativeArtboards after in [resized, added, reversed, removed]) {
        _retained(before, after);
        final AiNativeTextDocument text = AiNativeTextDocument.decode(records: after.records);
        check(text.frames.map((frame) => frame.kind)).deepEquals([AiNativeTextFrameKind.point, AiNativeTextFrameKind.area, AiNativeTextFrameKind.path]);
        check(text.stories.first.frameIndices).deepEquals([1, 0]);
        check(text.stories.last.frameIndices).deepEquals([2]);
        check(text.stories.first.strikes.single.children.single.glyphIds).deepEquals([10, 11, 1]);
      }
    });
  }

  test('resolves undo-free drawing references in their own independent namespace', () {
    final String main = artboardTextEngineSource().replaceFirst('/0 [12 34]', '/0 [120 340]');
    final String undo = artboardTextEngineSource().replaceFirst('/0 [12 34]', '/0 [-12 -34]');
    final AiNativeArtboards before = artboardModel(populatedArtboardSource(main: main, undo: undo, body: artboardTextDrawing(snapshot: 1)));
    _retained(before, before.reorder(artboards: before.artboards.reversed.toList(), cropBounds: null));
    for (final bool withUndo in [false, true]) {
      final AiNativeArtboards missing = artboardModel(populatedArtboardSource(body: artboardTextDrawing(snapshot: 1), withUndo: withUndo));
      check(() => missing.reorder(artboards: missing.artboards.reversed.toList(), cropBounds: null)).throws<FormatException>();
    }
  });

  test('retains populated text after mapped serialization and a further native edit', () {
    final AiPdfDocument original = mappedArtboardSource(nativeProgram: populatedArtboardSource());
    final AiNativeSource source = AiNativeData.extract(original).single;
    final AiNativeArtboards before = nativeBoards(source);
    final AiNativeArtboards changed = before.reorder(artboards: before.artboards.reversed.toList(), cropBounds: null);
    final PdfEditor host = PdfEditor(document: original.pdf)
      ..movePage(from: 1, to: 0)
      ..movePage(from: 2, to: 0);
    final AiPdfDocument saved = saveMapped(mappedArtboards(source, changed, host.document, [2, 1, 0]), host.document);
    final AiNativeArtboards after = nativeBoards(AiNativeData.extract(saved).single);
    _retained(before, after);
    _retained(before, after.remove(artboards: [after.artboards.first], activeArtboard: after.artboards.last, cropBounds: null));
  });

  test('rejects unresolved story frame and cached-frame references atomically', () {
    final String source = populatedArtboardSource();
    for (final String changed in [
      source.replaceFirst('0 /StoryIndex', '9 /StoryIndex'),
      source.replaceFirst('0 /FrameIndex', '9 /FrameIndex'),
      source.replaceFirst('0 /FrameIndex', '-1 /FrameIndex'),
      populatedArtboardSource(main: artboardTextEngineSource().replaceFirst('/0 [ << /0 1 >> << /0 0 >> ]', '/0 [ << /0 1 >> << /0 1 >> ]')),
      populatedArtboardSource(main: artboardTextEngineSource().replaceFirst('/0 [ << /0 2 >> ]', '/0 [ << /0 42 >> ]')),
      populatedArtboardSource(main: artboardTextEngineSource().replaceFirst('/99 /F /10 1', '/99 /F /10 2')),
    ]) {
      final AiNativeArtboards model = artboardModel(changed);
      check(() => model.reorder(artboards: model.artboards.reversed.toList(), cropBounds: null)).throws<FormatException>();
      check(artboardText(model)).equals(changed);
    }
  });

  test('rejects unqualified text schemas without treating unknown owners as artboard independent', () {
    final String engine = artboardTextEngineSource();
    for (final String changed in [
      engine.replaceFirst('/0 [12 34]', '/Artboard 0 /0 [12 34]'),
      engine.replaceFirst('/0 1 /2 [0 1', '/0 8 /2 [0 1'),
      engine.replaceFirst('/1 << /0 [ << /0 1', '/1 << /Future (board-0) /0 [ << /0 1'),
      engine.replaceFirst('/99 /G', '/99 /FutureGlyphs'),
      engine.replaceFirst('/24 (glyph cache)', '/Artboard 0 /24 (glyph cache)'),
    ]) {
      for (final bool undo in [false, true]) {
        final AiNativeArtboards model = artboardModel(populatedArtboardSource(main: undo ? null : changed, undo: undo ? changed : null));
        check(() => model.reorder(artboards: model.artboards.reversed.toList(), cropBounds: null)).throws<UnsupportedError>();
      }
    }
  });

  test('rejects missing confining paths and malformed text-local geometry', () {
    for (final String source in [
      populatedArtboardSource(body: artboardTextDrawing().replaceFirst('/Art : $artboardTextConfinement ; /ConfiningPath ,', '')),
      populatedArtboardSource(main: artboardTextEngineSource().replaceFirst('/0 [12 34]', '/0 [12]')),
      populatedArtboardSource(main: artboardTextEngineSource().replaceFirst('/2 [1 0 0 1 4 5]', '/2 [1 0 0 1 4]')),
      populatedArtboardSource(body: artboardTextDrawing(confinement: artboardTextConfinement.replaceFirst('2 As', '7 As'))),
      populatedArtboardSource(body: artboardTextDrawing().replaceFirst('/Art : X=', '/Art : /ASCII85Decode ,\n%z~>\nX=')),
    ]) {
      final AiNativeArtboards model = artboardModel(source);
      check(() => model.reorder(artboards: model.artboards.reversed.toList(), cropBounds: null)).throws<FormatException>();
    }
  });

  test('rejects conditional private extended and executable drawing text', () {
    final String body = artboardTextDrawing();
    for (final String changed in [
      body.replaceFirst('/AI11Text :', '%_/AI11Text :'),
      body.replaceFirst('0 /FreeUndo', '2 /FreeUndo'),
      body.replaceFirst('0 /FreeUndo', '0 /FreeUndo , (board-0) /Artboard'),
      body.replaceFirst('6 () XW', '1 (missing) XW'),
      body.replaceFirst('6 () XW', '6 (unknown) XW'),
      body.replaceFirst('0 0 Xd', '0 2 Xd'),
      body.replaceFirst('N /ArtDictionary', 'f /ArtDictionary'),
      body.replaceFirst('X= 1 Ap', 'X= 1 0 0 1 0 0 cm 1 Ap'),
      body.replaceFirst('X= 1 Ap', 'X= /Binary : /ASCII85Decode ,\n%z~>\n; 1 Ap'),
      body.replaceFirst('(story-zero)', '(board-0) /String (FutureReference) , (story-zero)'),
      '%AI17_Begin_Content_if_version_gt:24 4\n$body\n%AI17_End_Versioned_Content',
    ]) {
      final AiNativeArtboards model = artboardModel(populatedArtboardSource(body: changed));
      check(() => model.reorder(artboards: model.artboards.reversed.toList(), cropBounds: null)).throws<UnsupportedError>();
    }
  });

  test('bounds populated frame and layout inspection by the original native limits', () {
    final String engine = artboardTextEngineSource();
    final String deep = engine.replaceFirst('/24 (glyph cache)', '/24 [${'[' * 24}0${']' * 24}]');
    final String wide = engine.replaceFirst('[10 11 1]', '[${List.filled(1000, '1').join(' ')}]');
    for (final (String, AiNativeLimits) fixture in [(deep, const AiNativeLimits(maxDepth: 12)), (wide, const AiNativeLimits(maxTokens: 600))]) {
      final String source = populatedArtboardSource(main: fixture.$1);
      final AiNativeArtboards model = artboardModel(source, limits: fixture.$2);
      check(() => model.reorder(artboards: model.artboards.reversed.toList(), cropBounds: null)).throws<FormatException>();
      check(artboardText(model)).equals(source);
    }
  });
}
