import 'dart:convert';

import 'package:aicodec/aicodec.dart';
import 'package:checks/checks.dart';
import 'package:test/test.dart';

import 'ai_native_artboard_lifecycle_test.dart' show newArtboard;
import 'ai_native_artboard_palette_test.dart' show artboardPaletteGradient;
import 'ai_native_artboard_patterns_test.dart' show artboardPattern;
import 'ai_native_artboard_symbols_test.dart' show artboardSymbol, symbolArtboardSource;
import 'ai_native_artboards_test.dart' show artboardModel;

/// Builds an explicit effect whose parameters stay in their original basis.
String artboardEffect({String name = 'Adobe Fuzzy Mask', String plugin = 'Illustrator.exe', String parameters = '2 /Real (Radius) ,'}) =>
    '/BasicFilter : ($name) 1 0 /Filter , 1 /Visible , ($plugin) /PluginFileName , (board-0) /Title , /Dictionary : /NotRecorded , $parameters ; /Dict ;';

/// A nested ordered appearance, including a hidden paint and one native effect.
String artboardActiveStyle({String? effect, String paint = '0.2 0.3 0.4 Xa 9 0.8 1 2 1 Xy 0 1 Xd'}) =>
    '''/KnownStyle : (board-0) /Name ,
/ActiveStyle : /CompoundFilter : (Chain Style Filter) 0 0 /Filter , 1 /Visible ,
/CompoundFilter : (Stack Style Filter) 0 0 /Filter , 1 /Visible ,
/BasicFilter : (Fill Style Filter) 0 0 /Filter , 0 /Visible ,
/Dictionary : /NotRecorded , 1 /Bool (UseEvenOdd) , /FillStyle : $paint /Def ; (FillStyle) , ; /Dict ; /Part ,
/BasicFilter : (Conduit Filter) 0 0 /Filter , 1 /Visible ; /Part ,
/BasicFilter : (Stroke Style Filter) 0 0 /Filter , 1 /Visible , 2 /FillOrStroke ,
/Dictionary : /NotRecorded , /StrokeStyle : 0 0 0 1 K 0 R 2 w 10 M [] 0 d 0 0 Xd /Def ; (StrokeStyle) , ; /Dict ; /Part ,
; /Part ,
${effect ?? artboardEffect()} /Part ,
/BasicFilter : (Blend Style Filter) 0 0 /Filter , 1 /Visible ,
/Dictionary : /NotRecorded , /BlendStyle : 15 0.5 0 0 0 Xy /Def ; (BlendStyle) , ; /Dict ; /Part ,
; /Execution ; /Def ;
''';

/// Checks that every appearance and drawing byte outside Document is unchanged.
void _retained(AiNativeArtboards before, AiNativeArtboards after) {
  check(after.records.program.bytes.take(after.document.start)).deepEquals(before.records.program.bytes.take(before.document.start));
  check(after.records.program.bytes.skip(after.document.end)).deepEquals(before.records.program.bytes.skip(before.document.end));
}

/// Exercises appearance dependency isolation without producing rendered pixels.
void main() {
  test('retains ordered paints effects visibility and both named style application modes', () {
    for (final int mode in [0, 1]) {
      final AiNativeArtboards before = artboardModel(symbolArtboardSource(style: artboardActiveStyle(), symbol: artboardSymbol.replaceFirst('1 (board-0)', '$mode (board-0)')));
      for (final AiNativeArtboards after in [
        before.create(definition: newArtboard(), index: 1, lastArtboardId: 68, cropBounds: null),
        before.resize(artboard: before.artboards.first, bounds: AiBoundingBox(left: -20, bottom: -40, right: 100, top: 200), cropBounds: null),
        before.reorder(artboards: before.artboards.reversed.toList(), cropBounds: null),
        before.remove(artboards: [before.artboards.first], activeArtboard: null, cropBounds: null),
      ]) {
        _retained(before, after);
      }
    }
  });

  test('retains qualified local effect dictionaries and older module names', () {
    const Map<String, (String, String)> effects = {
      'Adobe Fuzzy Mask': ('FuzzyEffect.aip', '2 /Real (Radius) ,'),
      'Adobe Round Corners': ('Round.aip', '3 /Real (radius) ,'),
      'Adobe Offset Path': ('OffsetPath.aip', '-4 /Real (ofst) , 10 /Real (mlim) , 2 /Int (jntp) ,'),
      'Adobe Stroke Offset': ('StrokeOffset.aip', '(board-0) /String (DisplayString) , 1 /Bool (StrokeOffsetInside) , /StrokeStyle : 1 G 2 w /Def ; (StrokeStyle) ,'),
      'Adobe Drop Shadow': (
        'DropShadow.aip',
        '3 /Real (horz) , 4 /Real (vert) , 2 /Real (blur) , 0.5 /Real (opac) , 80 /Real (dark) , 1 /Bool (pair) , 1 /Bool (usePSLBlur) , 1 /Int (blnd) , 0 /Int (csrc) , 16 /Int (Adobe Effect Expand Before Version) , /FillStyle : 0.3 g /Def ; (sclr) ,',
      ),
      'Adobe Outer Glow': (
        'OuterGlow.aip',
        '2 /Real (blur) , 0.4 /Real (opac) , 1 /Bool (usePSLBlur) , 2 /Int (blnd) , 16 /Int (Adobe Effect Expand Before Version) , /FillStyle : 0.8 g /Def ; (sclr) ,',
      ),
      'Adobe Transform': (
        'Transform.aip',
        '2 /Int (numCopies) , 4 /Int (pinPoint) , 1 /Bool (reflectX) , 0 /Bool (reflectY) , 1 /Bool (scaleLines) , 1 /Bool (transformPatterns) , 0 /Bool (randomize) , 90 /Real (rotate_Degrees) , 1.570796 /Real (rotate_Radians) , -20 /Real (moveH_Pts) , 10 /Real (moveV_Pts) , 0.5 /Real (scaleH_Factor) , 2 /Real (scaleV_Factor) , 50 /Real (scaleH_Percent) , 200 /Real (scaleV_Percent) ,',
      ),
    };
    for (final MapEntry<String, (String, String)> effect in effects.entries) {
      for (final String plugin in ['Illustrator.exe', effect.value.$1]) {
        final String source = symbolArtboardSource(
          style: artboardActiveStyle(
            effect: artboardEffect(name: effect.key, plugin: plugin, parameters: effect.value.$2),
          ),
        );
        final AiNativeArtboards before = artboardModel(source);
        _retained(before, before.remove(artboards: [before.artboards.first], activeArtboard: null, cropBounds: null));
      }
    }
  });

  test('retains gradient pattern and named-color paints with exact resource ownership', () {
    const String paint = '0.1 0.2 0.3 0.4 (board-0) 0.5 Xs\nBb 1 (board-0) 0 0 0 1 1 0 0 1 0 0 1 Bg 0 BB\n(board-0) 3 -5 0.5 2 35 1 45 12 7 [1 0.2 0.3 1 40 70] p';
    final String style = artboardActiveStyle(paint: paint);
    final AiNativeArtboards before = artboardModel(symbolArtboardSource(style: style, resources: '$artboardPaletteGradient$artboardPattern'));
    _retained(before, before.reorder(artboards: before.artboards.reversed.toList(), cropBounds: null));
    for (final String resources in ['', artboardPaletteGradient, artboardPattern, '$artboardPaletteGradient$artboardPaletteGradient$artboardPattern']) {
      final AiNativeArtboards missing = artboardModel(symbolArtboardSource(style: style, resources: resources));
      check(() => missing.reorder(artboards: missing.artboards.reversed.toList(), cropBounds: null)).throws<UnsupportedError>();
    }
  });

  test('retains a direct filter and absent visibility without inventing defaults', () {
    final String style = '/KnownStyle : (board-0) /Name , /ActiveStyle : ${artboardEffect().replaceFirst('1 /Visible ,', '')} /Execution ; /Def ;';
    final AiNativeArtboards before = artboardModel(symbolArtboardSource(style: style));
    _retained(before, before.reorder(artboards: before.artboards.reversed.toList(), cropBounds: null));
    final AiNativeArtboards invalid = artboardModel(symbolArtboardSource(style: style.replaceFirst('/Filter ,', '/Filter , 2 /Visible ,')));
    check(() => invalid.reorder(artboards: invalid.artboards.reversed.toList(), cropBounds: null)).throws<UnsupportedError>();
  });

  test('keeps unnamed applications separate from named dependency resolution', () {
    for (final int mode in [0, 1, 6, 9]) {
      for (final bool private in [false, true]) {
        final AiNativeArtboards before = artboardModel(symbolArtboardSource(symbol: artboardSymbol.replaceFirst('1 (board-0) XW', '${private ? '%_' : ''}$mode () XW'), style: ''));
        final AiNativeStructure structure = AiNativeStructure.decode(drawing: AiNativeDrawing.decode(records: before.records));
        check(structure.resourceUses).isEmpty();
        _retained(before, before.reorder(artboards: before.artboards.reversed.toList(), cropBounds: null));
      }
    }
    for (final int mode in [0, 1]) {
      final AiNativeArtboards before = artboardModel(symbolArtboardSource(symbol: artboardSymbol.replaceFirst('1 (board-0)', '$mode (missing)')));
      final AiNativeStructure structure = AiNativeStructure.decode(drawing: AiNativeDrawing.decode(records: before.records));
      check(structure.resourceUses.single.resolution).equals(AiNativeResourceResolution.missing);
      check(() => before.reorder(artboards: before.artboards.reversed.toList(), cropBounds: null)).throws<UnsupportedError>();
    }
  });

  test('rejects unknown or misplaced fields plugins and executable graph owners atomically', () {
    final String style = artboardActiveStyle();
    for (final String changed in [
      style.replaceFirst('(Radius)', '(ArtboardIndex)'),
      style.replaceFirst('2 /Real (Radius)', '2 /Int (Radius)'),
      style.replaceFirst('2 /Real (Radius)', '/GObjRef : (board-0) /PluginObject ; (Radius)'),
      style.replaceFirst('Adobe Fuzzy Mask', 'Unknown Effect'),
      style.replaceFirst('Illustrator.exe', 'External.aip'),
      style.replaceFirst('(Adobe Fuzzy Mask) 1 0', '(Adobe Fuzzy Mask) 0 0'),
      style.replaceFirst('/Title ,', '/Title , (again) /Title ,'),
      style.replaceFirst('2 /Real (Radius) ,', '2 /Real (Radius) ,\n%AI24_ArtboardRef: board-0\n'),
      style.replaceFirst('(Chain Style Filter) 0 0', '(Future Chain) 0 0'),
      style.replaceFirst('/Execution', '/OtherExecution'),
      style.replaceFirst('0.2 0.3 0.4 Xa', '(board-0) load'),
      style.replaceFirst('0.2 0.3 0.4 Xa', '0 0 m 10 10 L f'),
    ]) {
      final String source = symbolArtboardSource(style: changed);
      final AiNativeArtboards before = artboardModel(source);
      check(() => before.reorder(artboards: before.artboards.reversed.toList(), cropBounds: null)).throws<UnsupportedError>();
      check(latin1.decode(before.records.program.bytes)).equals(source);
    }
  });

  test('rejects malformed numeric fields paint commands and mixed representations', () {
    final String style = artboardActiveStyle();
    for (final String changed in [
      style.replaceFirst('2 /Real (Radius) ,', '2 /Real (Radius) , 3 /Real (Radius) ,'),
      style.replaceFirst('2 /Real (Radius)', '(bad) /Real (Radius)'),
      style.replaceFirst('2 /Real (Radius)', '9007199254740992 /Real (Radius)'),
      style.replaceFirst('2 w', '-2 w'),
      style.replaceFirst('0.2 0.3 0.4 Xa', '0.2 0.3 Xa'),
      style.replaceFirst('0.2 0.3 0.4 Xa', '0.2\n%_0.3 0.4 Xa'),
    ]) {
      check(() {
        final AiNativeArtboards before = artboardModel(symbolArtboardSource(style: changed));
        before.reorder(artboards: before.artboards.reversed.toList(), cropBounds: null);
      }).throws<FormatException>();
    }
  });
}
