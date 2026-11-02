import 'dart:convert';

import 'package:aicodec/aicodec.dart';
import 'package:checks/checks.dart';
import 'package:test/test.dart';

import 'ai_native_artboard_lifecycle_test.dart' show newArtboard;
import 'ai_native_artboards_test.dart' show artboardModel, artboardSource;
import 'ai_native_objects_test.dart' show objectDictionary;

/// A counted gradient whose name belongs to a separate namespace from boards.
const String artboardPaletteGradient = '''1 Bn
%AI5_BeginGradient: (board-0)
(board-0) 1 2 Bd
[
0 0 50 0 Bs
1 0 50 100 Bs
BD
%AI5_EndGradient
''';

/// Local named colors, groups and a resolved gradient without pattern artwork.
const String artboardPalette = '''%AI5_BeginPalette
2 4 Pb
Pn (None) Pc
0 0 0 1 0 0 0 ([Passermarken]) 0 1 Xz ([Passermarken]) Pc
0.2 0.3 0.4 0.5 (board-0) 0.6 Xs (Custom) Pc
0.2 0.3 0.4 0.5 0.6 0.7 0.8 (board-0) 0.9 1 Xz (RGB ink) Pc
1 (board-0) 0 Pg
0.5 g (Process gray) Pc
0 (Other colors) 1 Pg
Bb 0 0 0 0 Bh 2 (board-0) 0 0 0 1 1 0 0 1 0 0 1 Bg 0 BB
(Gradient) Pc
PB
%AI5_EndPalette
''';

/// Combines a palette with three independent native artboard identities.
String paletteArtboardSource({String palette = artboardPalette, String gradients = artboardPaletteGradient, String body = ''}) => artboardSource(extra: '$gradients$palette', body: body);

/// Requires exact retained setup, headers, body and unselected record bytes.
void _retained(AiNativeArtboards before, AiNativeArtboards after) {
  check(after.records.program.bytes.sublist(0, after.document.start)).deepEquals(before.records.program.bytes.sublist(0, before.document.start));
  check(after.records.program.bytes.sublist(after.document.end)).deepEquals(before.records.program.bytes.sublist(before.document.end));
}

/// Checks reference ownership without regenerating any local paint appearance.
void main() {
  test('retains named colors localized registration groups and gradients through all edits', () {
    final AiNativeArtboards before = artboardModel(paletteArtboardSource());
    for (final AiNativeArtboards after in [
      before.create(definition: newArtboard(), index: 1, lastArtboardId: 68, cropBounds: null),
      before.resize(artboard: before.artboards.first, bounds: AiBoundingBox(left: -10, bottom: -20, right: 500, top: 800), cropBounds: null),
      before.reorder(artboards: before.artboards.reversed.toList(), cropBounds: null),
      before.remove(artboards: [before.artboards.first], activeArtboard: null, cropBounds: null),
    ]) {
      _retained(before, after);
    }
  });

  test('retains unnamed legacy cells and absolute palette gradient coordinates', () {
    const String palette = '''%AI5_BeginPalette
0 3 Pb Pn Pc 0.7 g Pc 0 0 0 1 k Pc
Bb 2 (board-0) -4014 4716 0 0 1 0 0 1 0 0 Bg 0 BB Pc
PB
%AI5_EndPalette
''';
    final AiNativeArtboards before = artboardModel(paletteArtboardSource(palette: palette));
    _retained(before, before.resize(artboard: before.artboards.first, bounds: AiBoundingBox(left: -1, bottom: -2, right: 3, top: 4), cropBounds: null));
  });

  test('preserves byte-valued color group and cell names without decoding localization', () {
    final String palette = artboardPalette.replaceAll('(board-0) 0.6 Xs', '<00626f617264ff> 0.6 Xs').replaceFirst('(Custom)', '<00ff>').replaceFirst('(Other colors)', '<00ff01>');
    final AiNativeArtboards before = artboardModel(paletteArtboardSource(palette: palette));
    _retained(before, before.reorder(artboards: before.artboards.reversed.toList(), cropBounds: null));
  });

  test('refuses missing ambiguous or conditional gradient resources', () {
    for (final String source in [
      paletteArtboardSource(gradients: ''),
      paletteArtboardSource(gradients: artboardPaletteGradient.replaceFirst('1 Bn', '2 Bn') + artboardPaletteGradient.substring('1 Bn\n'.length)),
      paletteArtboardSource(gradients: '%AI17_Begin_Content_if_version_gt:24 4\n$artboardPaletteGradient%AI17_End_Versioned_Content\n'),
      paletteArtboardSource(palette: artboardPalette.replaceFirst('2 (board-0)', '2 (missing)')),
    ]) {
      final AiNativeArtboards before = artboardModel(source);
      check(() => before.reorder(artboards: before.artboards.reversed.toList(), cropBounds: null)).throws<UnsupportedError>();
      check(latin1.decode(before.records.program.bytes)).equals(source);
    }
  });

  test('rejects malformed palette indices names color components tints and groups', () {
    for (final String palette in [
      artboardPalette.replaceFirst('2 4 Pb', '-1 4 Pb'),
      artboardPalette.replaceFirst('2 4 Pb', '0.5 4 Pb'),
      artboardPalette.replaceFirst('2 4 Pb', '9007199254740992 4 Pb'),
      artboardPalette.replaceFirst('0.2 0.3 0.4 0.5', '1.2 0.3 0.4 0.5'),
      artboardPalette.replaceFirst('(board-0) 0.6 Xs', '(board-0) 1.6 Xs'),
      artboardPalette.replaceFirst('([Passermarken]) 0 1 Xz', '() 0 1 Xz'),
      artboardPalette.replaceFirst('([Passermarken]) 0 1 Xz', '([Passermarken]) 0 2 Xz'),
      artboardPalette.replaceFirst('1 (board-0) 0 Pg', '2 (board-0) 0 Pg'),
      artboardPalette.replaceFirst('1 (board-0) 0 Pg', '1 (board-0) 0 1 Pg'),
      artboardPalette.replaceFirst('(None) Pc', '() Pc'),
    ]) {
      final AiNativeArtboards before = artboardModel(paletteArtboardSource(palette: palette));
      check(() => before.reorder(artboards: before.artboards.reversed.toList(), cropBounds: null)).throws<FormatException>();
    }
  });

  test('rejects unfinished cells overlapping paints and misplaced groups', () {
    for (final String palette in [
      artboardPalette.replaceFirst('Pn (None) Pc', 'Pn 0.5 g (None) Pc'),
      artboardPalette.replaceFirst('(None) Pc', '1 (Group) 1 Pg (None) Pc'),
      artboardPalette.replaceFirst('(Gradient) Pc', ''),
      artboardPalette.replaceFirst('PB', 'PB 0.2 g'),
      artboardPalette.replaceFirst('Pn (None) Pc', '(None) Pc'),
      artboardPalette.replaceFirst('Pn', '1 Pn'),
    ]) {
      final AiNativeArtboards before = artboardModel(paletteArtboardSource(palette: palette));
      check(() => before.reorder(artboards: before.artboards.reversed.toList(), cropBounds: null)).throws<FormatException>();
    }
  });

  test('refuses opaque annotations private colors pattern dependencies and executable paints', () {
    for (final String palette in [
      artboardPalette.replaceFirst('Pn (None) Pc', '%_Pn (None) Pc\n'),
      artboardPalette.replaceFirst('Pn', '%AI24_Unknown: board-0\nPn'),
      artboardPalette.replaceFirst('Pn', '(board-0) load'),
      artboardPalette.replaceFirst('Pn', '(Pattern) 0 0 1 1 0 0 0 0 0 [1 0 0 1 0 0] p'),
      artboardPalette.replaceFirst('Bb 0', 'Bb (board-0) load 0'),
      artboardPalette.replaceFirst('2 (board-0) 0 0 0 1', '1 (board-0) 0 0 0 1'),
    ]) {
      final String source = paletteArtboardSource(palette: palette);
      final AiNativeArtboards before = artboardModel(source);
      check(() => before.reorder(artboards: before.artboards.reversed.toList(), cropBounds: null)).throws<UnsupportedError>();
      check(latin1.decode(before.records.program.bytes)).equals(source);
    }
  });

  test('keeps palette names separate from removed artwork identities', () {
    final String source = paletteArtboardSource(body: '0 A 0 Xw 0.3 g 10 -10 m 30 -20 L f\n${objectDictionary(identifier: 'board-0')}');
    final AiNativeArtboards before = artboardModel(source);
    _retained(before, before.remove(artboards: [before.artboards.first], activeArtboard: null, cropBounds: null));
    final AiNativeDrawing drawing = AiNativeDrawing.decode(records: before.records);
    final AiNativeDrawing removed = drawing.removePaths(paths: drawing.paths);
    check(removed.paths).isEmpty();
    check(removed.records.program.bytes.take(removed.records.program.bodyStart)).deepEquals(drawing.records.program.bytes.take(drawing.records.program.bodyStart));
    final AiNativeDrawing unknown = AiNativeDrawing.decode(records: artboardModel(source.replaceFirst('PB\n', '(board-0) load PB\n')).records);
    check(() => unknown.removePaths(paths: unknown.paths)).throws<UnsupportedError>();
  });
}
