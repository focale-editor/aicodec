import 'dart:convert';

import 'package:aikit/aikit.dart';
import 'package:checks/checks.dart';
import 'package:test/test.dart';

import 'ai_native_artboard_lifecycle_test.dart' show newArtboard;
import 'ai_native_artboard_palette_test.dart' show artboardPaletteGradient;
import 'ai_native_artboards_test.dart' show artboardModel, artboardSource;
import 'ai_native_objects_test.dart' show objectDictionary;

/// Direct CC tile artwork with private groups, a clipping path and a gradient.
const String artboardPattern = '''%AI3_BeginPattern: (board-0)
(board-0) 0 0 10 10
%_0 A 0 Xw 0 Ae u
%_q
%_4 As 0 0 m 10 0 L 10 10 L 0 10 L 0 0 L h W n
%_/ArtDictionary : 1 /Bool (AIPattern_Editor_Backing_Tile_Rect) , ;
%_*u
%_4 As 1 0.5 0 0 0 Xy 0.3 g
%_0 0 m 10 0 L 10 10 L 0 10 L 0 0 L
%_Bb 1 (board-0) 0 0 0 1 1 0 0 1 0 0 1 Bg
%_1 0 0 1 0 0 Bm f 0 BB
%_/ArtDictionary : /Dictionary : /NotRecorded ,
%_1 0 0 1 0 0 /RealMatrix (CAIGradientTformMatrix) ,
%_; (Adobe_AI9_ArtStyle_Dictionary) , ;
%_*U Q
%_U
%_/ArtDictionary : (0.4) /String (BBAccumRotation) ,
%_1 /Bool (AIPattern_Editor_AutoGrow) ,
%_10 /Real (AIPattern_Editor_Tile_Width) ,
%_10 /Real (AIPattern_Editor_Tile_Height) ,
%_5 /Int (AIPattern_Editor_Preview_Rows) , ;
%_0 1 Xd 6 () XW 9 () XW
E
%AI3_EndPattern
''';

/// A literal fill reference with an independently recorded pattern transform.
const String artboardPatternPalette = '''%AI5_BeginPalette
0 0 Pb
(board-0) 3 -5 0.5 2 35 1 45 12 7 [1 0.2 0.3 1 40 70] p (Pattern cell) Pc
PB
%AI5_EndPalette
''';

/// Keeps one pattern, one gradient and three artboard names in separate namespaces.
String patternArtboardSource({String pattern = artboardPattern, String palette = artboardPatternPalette, String gradients = artboardPaletteGradient, String body = ''}) =>
    artboardSource(extra: '$gradients$pattern$palette', body: body);

/// Requires unchanged source outside the selected Document record.
void _retained(AiNativeArtboards before, AiNativeArtboards after) {
  check(after.records.program.bytes.sublist(0, after.document.start)).deepEquals(before.records.program.bytes.sublist(0, before.document.start));
  check(after.records.program.bytes.sublist(after.document.end)).deepEquals(before.records.program.bytes.sublist(before.document.end));
}

/// Checks pattern ownership without generating tiles or changing native objects.
void main() {
  test('retains private tile groups clips geometry metadata and palette transforms through all edits', () {
    final AiNativeArtboards before = artboardModel(patternArtboardSource());
    for (final AiNativeArtboards after in [
      before.create(definition: newArtboard(), index: 1, lastArtboardId: 68, cropBounds: null),
      before.resize(artboard: before.artboards.first, bounds: AiBoundingBox(left: -10, bottom: -20, right: 500, top: 800), cropBounds: null),
      before.reorder(artboards: before.artboards.reversed.toList(), cropBounds: null),
      before.remove(artboards: [before.artboards.first], activeArtboard: null, cropBounds: null),
    ]) {
      _retained(before, after);
    }
  });

  test('retains ordinary declarations empty tiles and multiple independent pattern users', () {
    for (final String pattern in [artboardPattern.replaceAll('%_', ''), '%AI3_BeginPattern: (board-0)\n(board-0) 0 0 10 10 E\n%AI3_EndPattern\n']) {
      final String palette = artboardPatternPalette.replaceFirst('PB', '(board-0) 0 0 1 1 0 0 0 0 0 [1 0 0 1 0 0] P (Stroke cell) Pc\nPB');
      final AiNativeArtboards before = artboardModel(patternArtboardSource(pattern: pattern, palette: palette));
      _retained(before, before.remove(artboards: [before.artboards.first], activeArtboard: null, cropBounds: null));
    }
  });

  test('rejects unresolved duplicated and conditional pattern or gradient resources', () {
    for (final String source in [
      patternArtboardSource(pattern: ''),
      patternArtboardSource(pattern: '$artboardPattern$artboardPattern'),
      patternArtboardSource(gradients: ''),
      patternArtboardSource(pattern: '%AI17_Begin_Content_if_version_gt:24 4\n$artboardPattern%AI17_End_Versioned_Content\n'),
      patternArtboardSource(palette: artboardPatternPalette.replaceFirst('(board-0)', '(missing)')),
    ]) {
      final AiNativeArtboards before = artboardModel(source);
      check(() => before.reorder(artboards: before.artboards.reversed.toList(), cropBounds: null)).throws<UnsupportedError>();
      check(latin1.decode(before.records.program.bytes)).equals(source);
    }
  });

  test('rejects malformed tile declarations and pattern paint operands', () {
    for (final String source in [
      patternArtboardSource(pattern: artboardPattern.replaceFirst('BeginPattern: (board-0)', 'BeginPattern: (other)')),
      patternArtboardSource(pattern: artboardPattern.replaceFirst('(board-0) 0 0 10 10', '(board-0) 0 0 0 10')),
      patternArtboardSource(pattern: artboardPattern.replaceFirst('(board-0) 0 0 10 10', '(board-0) 0 0 1e100 10')),
      patternArtboardSource(pattern: artboardPattern.replaceFirst('\nE\n', '\n%_E\n')),
      patternArtboardSource(pattern: artboardPattern.replaceFirst('\nE\n', '\n')),
      patternArtboardSource(palette: artboardPatternPalette.replaceFirst('35 1 45', '35 2 45')),
      patternArtboardSource(palette: artboardPatternPalette.replaceFirst('[1 0.2 0.3 1 40 70]', '[1 0.2 0.3 1 40]')),
    ]) {
      final AiNativeArtboards before = artboardModel(source);
      check(() => before.reorder(artboards: before.artboards.reversed.toList(), cropBounds: null)).throws<FormatException>();
    }
  });

  test('rejects malformed topology counts rotations and metadata values', () {
    for (final String pattern in [
      artboardPattern.replaceFirst('4 As', '5 As'),
      artboardPattern.replaceFirst('%_*U Q', '%_U Q'),
      artboardPattern.replaceFirst('(0.4)', '(invalid)'),
      artboardPattern.replaceFirst('10 /Real (AIPattern_Editor_Tile_Width)', '1e100 /Real (AIPattern_Editor_Tile_Width)'),
      artboardPattern.replaceFirst('1 0 0 1 0 0 Bm', '1e100 0 0 1 0 0 Bm'),
      artboardPattern.replaceFirst('9 () XW', '9 () XW 3 As'),
    ]) {
      check(() {
        final AiNativeArtboards before = artboardModel(patternArtboardSource(pattern: pattern));
        return before.reorder(artboards: before.artboards.reversed.toList(), cropBounds: null);
      }).throws<FormatException>();
    }
  });

  test('refuses executable state unknown metadata and gradient ownership crossing groups', () {
    for (final String pattern in [
      artboardPattern.replaceFirst('0 Ae', '(board-0) load'),
      artboardPattern.replaceFirst('0 Ae', '1 Ae'),
      artboardPattern.replaceFirst('0 Ae', '[1 0 0 1 0 0] concat'),
      artboardPattern.replaceFirst('0 Ae', '{ 0 Ae } exec'),
      artboardPattern.replaceFirst('%_0 A 0 Xw 0 Ae u', '%%BeginDocument: Nested\n0 Ae\n%%EndDocument\n%_0 A 0 Xw 0 Ae u'),
      artboardPattern.replaceFirst('6 () XW', '1 (board-0) XW'),
      artboardPattern.replaceFirst('1 /Bool (AIPattern_Editor_AutoGrow)', '(board-0) /String (FutureReference)'),
      artboardPattern.replaceFirst('/RealMatrix (CAIGradientTformMatrix)', '/RealMatrix (UnknownMatrix)'),
      artboardPattern.replaceFirst('0 1 Xd', 'Bb u U 2 (board-0) 0 0 0 1 1 0 0 1 0 0 1 Bg 0 BB 0 1 Xd'),
      artboardPattern.replaceFirst('0 Ae', '%AI24_Unknown: board-0\n%_0 Ae'),
    ]) {
      final AiNativeArtboards before = artboardModel(patternArtboardSource(pattern: pattern));
      check(() => before.reorder(artboards: before.artboards.reversed.toList(), cropBounds: null)).throws<UnsupportedError>();
    }
  });

  test('does not qualify metadata outside the pattern or lower artwork deletion guards', () {
    const String outside = '/ArtDictionary : 1 /Bool (AIPattern_Editor_AutoGrow) , ;\n';
    for (final String pattern in ['$outside$artboardPattern', '$artboardPattern$outside']) {
      final AiNativeArtboards before = artboardModel(patternArtboardSource(pattern: pattern));
      check(() => before.reorder(artboards: before.artboards.reversed.toList(), cropBounds: null)).throws<UnsupportedError>();
    }
    final AiNativeArtboards before = artboardModel(patternArtboardSource(body: '0 A 0 Xw 0.3 g 10 -10 m 30 -20 L f\n${objectDictionary(identifier: 'target')}'));
    _retained(before, before.reorder(artboards: before.artboards.reversed.toList(), cropBounds: null));
    final AiNativeDrawing drawing = AiNativeDrawing.decode(records: before.records);
    check(() => drawing.removePaths(paths: drawing.paths)).throws<UnsupportedError>();
  });

  test('bounds tile group nesting using the original program inspection policy', () {
    final String pattern = artboardPattern.replaceFirst('0 Ae u', '0 Ae ${List.filled(9, 'u').join(' ')} u').replaceFirst('\nE\n', '\n%_${List.filled(9, 'U').join(' ')}\nE\n');
    final AiNativeArtboards before = artboardModel(patternArtboardSource(pattern: pattern), limits: const AiNativeLimits(maxDepth: 8));
    check(() => before.reorder(artboards: before.artboards.reversed.toList(), cropBounds: null)).throws<FormatException>();
  });
}
