import 'dart:convert';

import 'package:aicodec/aicodec.dart';
import 'package:checks/checks.dart';
import 'package:test/test.dart';

import 'ai_native_artboard_references_test.dart' show artboardReferenceSource;
import 'ai_native_artboard_text_test.dart' show artboardTextEngineSource;
import 'ai_native_artboards_test.dart' show artboardModel;
import 'ai_native_artwork_movement_test.dart' show movementState;
import 'ai_native_contour_movement_test.dart' show contourMovementContour, contourMovementGroup, contourMovementPath;
import 'ai_native_group_creation_test.dart' show groupCreationDrawing;
import 'ai_native_objects_test.dart' show objectDictionary;
import 'ai_native_path_topology_test.dart' show topologyBounds, topologyGeometry;

/// Encodes an empty text namespace with independently retained typography data.
String contourTextEngine({int version = 11, String composer = '/4 << /0 7 /1 8 /2 1 /3 (Illustrator) >>', String extra = ''}) =>
    '/98 << /0 $version >> /0 << /1 << /0 [ << /0 << /97 (P10) >> >> ] /1 [ << /0 0 >> ] >> /8 << /0 [] /1 [] >> >> '
    '/1 << /1 [] /2 << /0 0 /1 12 >> /3 << /0 0 >> $composer $extra >>';

/// Provides identified ordinary branches beside unchanged independent text owners.
String contourTextSource({String? main, String? undo, bool withUndo = true}) => artboardReferenceSource(
  main: PsEngineDocument.decode(bytes: latin1.encode(main ?? contourTextEngine())).root,
  undo: PsEngineDocument.decode(bytes: latin1.encode(undo ?? contourTextEngine())).root,
  withUndo: withUndo,
  body:
      '''$movementState
0 1 0 0 0 Xy
u ${contourMovementPath(10)}U
${objectDictionary(identifier: 'Left')}
u ${contourMovementPath(20)}U
${objectDictionary(identifier: 'Right')}
''',
);

/// Compares exact binary owners instead of normalized engine re-encodings.
void _retained(AiNativeDrawing before, AiNativeDrawing after) {
  for (final AiNativeContainer owner in before.records.roots.where((record) => record.type == 'AI11TextDocument' || record.type == 'AI11UndoFreeTextDocument')) {
    final AiNativeContainer actual = after.records.roots.singleWhere((record) => record.type == owner.type);
    check(after.records.program.bytes.sublist(actual.start, actual.end)).deepEquals(before.records.program.bytes.sublist(owner.start, owner.end));
  }
  check(after.records.program.limits).identicalTo(before.records.program.limits);
}

/// Exercises text-independent contour operations and unchanged global contracts.
void main() {
  test('retains empty ATE 11 snapshots across contour edits movement and deletion', () {
    final String source = contourTextSource();
    final AiNativeDrawing drawing = groupCreationDrawing(source);
    for (final AiNativeDrawing changed in [
      drawing.editPaths(
        edits: [AiNativePathEdit(path: drawing.paths.first, segments: topologyGeometry())],
        bounds: topologyBounds,
      ),
      drawing.moveContours(paths: [drawing.paths.first], group: contourMovementGroup(drawing, 'Right'), bounds: topologyBounds, inheritParentFlags: true),
      drawing.moveContourGroups(groups: [contourMovementGroup(drawing, 'Left')], parent: contourMovementGroup(drawing, 'Right'), bounds: topologyBounds, inheritParentFlags: true),
      drawing.removePaths(paths: [drawing.paths.first]),
    ]) {
      _retained(drawing, changed);
      final AiNativeTextDocument text = AiNativeTextDocument.decode(records: changed.records);
      check(text.frames).isEmpty();
      check(text.stories).isEmpty();
      check(text.fonts).length.equals(1);
    }
    check(latin1.decode(drawing.records.program.bytes)).equals(source);
  });

  test('qualifies each empty snapshot independently and keeps optional composer data', () {
    for (final int version in [7, 9, 11]) {
      for (final bool primary in [false, true]) {
        final String older = contourTextEngine(version: version, composer: '');
        final AiNativeDrawing drawing = groupCreationDrawing(contourTextSource(main: primary ? older : null, undo: primary ? null : older, withUndo: version != 7 || !primary));
        _retained(drawing, drawing.removePaths(paths: [drawing.paths.first]));
      }
    }
  });

  test('retains empty ATE 11 through artboard lifecycle without rewriting its origin', () {
    final AiNativeArtboards boards = artboardModel(contourTextSource());
    final AiNativeDrawing before = AiNativeDrawing.decode(records: boards.records);
    for (final AiNativeArtboards changed in [
      boards.reorder(artboards: boards.artboards.reversed.toList(), cropBounds: null),
      boards.remove(artboards: [boards.artboards.first], activeArtboard: null, cropBounds: null),
      boards.resize(artboard: boards.artboards.first, bounds: topologyBounds, cropBounds: null),
    ]) {
      _retained(before, AiNativeDrawing.decode(records: changed.records));
      check(changed.records.program.bytes.take(changed.document.start)).deepEquals(boards.records.program.bytes.take(boards.document.start));
      check(changed.records.program.bytes.skip(changed.document.end)).deepEquals(boards.records.program.bytes.skip(boards.document.end));
    }
  });

  test('does not qualify populated ATE 11 frames stories or drawing references', () {
    for (final String engine in [
      artboardTextEngineSource(version: 11),
      contourTextEngine().replaceFirst('/8 << /0 []', '/8 << /0 [ << /0 << /0 [12 34] >> >> ]'),
      contourTextEngine().replaceFirst('/1 << /1 []', '/1 << /1 [ << /0 << /0 (unused) >> /1 << /0 [] >> >> ]'),
    ]) {
      for (final bool primary in [false, true]) {
        final String source = contourTextSource(main: primary ? engine : null, undo: primary ? null : engine);
        final AiNativeDrawing drawing = groupCreationDrawing(source);
        check(() => drawing.pathTopology(path: drawing.paths.first)).throws<UnsupportedError>();
        check(() => drawing.removePaths(paths: [drawing.paths.first])).throws<UnsupportedError>();
        check(latin1.decode(drawing.records.program.bytes)).equals(source);
      }
    }
    final String source = contourTextSource().replaceFirst('u 2 As', '/AI11Text : 0 /FreeUndo , 0 /StoryIndex , 0 /FrameIndex , ;\nu 2 As');
    final AiNativeDrawing drawing = groupCreationDrawing(source);
    check(() => drawing.pathTopology(path: drawing.paths.first)).throws<FormatException>();
  });

  test('rejects unknown schemas and opaque tokens in either empty snapshot', () {
    for (final String engine in [
      contourTextEngine(version: 13),
      contourTextEngine(version: 9),
      contourTextEngine(extra: '/Future (P10)'),
      contourTextEngine().replaceFirst('/0 7 /1 8', '/Future (P10) /0 7 /1 8'),
      contourTextEngine().replaceFirst('/97 (P10)', '/97 future'),
      contourTextEngine().replaceFirst('/8 <<', '/Future << >> /8 <<'),
      contourTextEngine().replaceFirst('/98 <<', '/Future (P10) /98 <<'),
    ]) {
      for (final bool primary in [false, true]) {
        final String source = contourTextSource(main: primary ? engine : null, undo: primary ? null : engine);
        final AiNativeDrawing drawing = groupCreationDrawing(source);
        check(() => drawing.pathTopology(path: drawing.paths.first)).throws<UnsupportedError>();
        check(latin1.decode(drawing.records.program.bytes)).equals(source);
      }
    }
  });

  test('rejects malformed composer descriptors and unresolved resource displays', () {
    for (final String composer in [
      '/4 << /0 7 /1 8 /3 (Illustrator) >>',
      '/4 << /0 -1 /1 8 /2 1 /3 (Illustrator) >>',
      '/4 << /0 7 /1 8.5 /2 1 /3 (Illustrator) >>',
      '/4 << /0 7 /1 8 /2 9007199254740992 /3 (Illustrator) >>',
      '/4 << /0 7 /1 8 /2 1 /3 /Illustrator >>',
    ]) {
      final AiNativeDrawing drawing = groupCreationDrawing(contourTextSource(main: contourTextEngine(composer: composer)));
      check(() => drawing.pathTopology(path: drawing.paths.first)).throws<FormatException>();
    }
    final AiNativeDrawing dangling = groupCreationDrawing(contourTextSource(undo: contourTextEngine().replaceFirst('/1 [ << /0 0 >> ]', '/1 [ << /0 1 >> ]')));
    check(() => dangling.pathTopology(path: dangling.paths.first)).throws<FormatException>();
  });

  test('retains the aggregate node budget for empty ATE 11', () {
    final String engine = contourTextEngine().replaceFirst('/97 (P10)', '/97 (P10) /66 [${'false ' * 1000}]');
    final String source = contourTextSource(main: engine, undo: engine);
    final AiNativeDrawing limited = groupCreationDrawing(source, limits: const AiNativeLimits(maxTokens: 2000));
    check(() => limited.pathTopology(path: contourMovementContour(limited, 10))).throws<FormatException>();
    check(latin1.decode(limited.records.program.bytes)).equals(source);
    final AiNativeDrawing full = groupCreationDrawing(source);
    _retained(full, full.removePaths(paths: [full.paths.first]));
  });

  test('bounds the aggregate decoded bytes across both ATE 11 owners', () {
    final String engine = contourTextEngine().replaceFirst('/97 (P10)', '/97 (${'\u0000' * 12000})');
    final String source = contourTextSource(main: engine, undo: engine).replaceFirst('%%EndComments', '% ${'padding' * 800}\n%%EndComments');
    check(source.length).isGreaterThan(engine.length);
    check(source.length).isLessThan(2 * engine.length);
    final AiNativeDrawing limited = groupCreationDrawing(source, limits: AiNativeLimits(maxDecodedBytes: source.length));
    check(() => limited.pathTopology(path: limited.paths.first)).throws<FormatException>();
    check(latin1.decode(limited.records.program.bytes)).equals(source);
  });
}
