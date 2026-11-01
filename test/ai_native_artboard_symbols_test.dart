import 'dart:convert';

import 'package:aikit/aikit.dart';
import 'package:checks/checks.dart';
import 'package:test/test.dart';

import 'ai_native_artboard_lifecycle_test.dart' show newArtboard;
import 'ai_native_artboard_palette_test.dart' show artboardPaletteGradient;
import 'ai_native_artboard_patterns_test.dart' show artboardPattern;
import 'ai_native_artboard_references_test.dart' show artboardSimpleStyle;
import 'ai_native_artboards_test.dart' show artboardModel, artboardSource;

/// A retained symbol with private counted geometry, a style and registration data.
const String artboardSymbol = '''%AI14_BeginSymbol
(board-0)
0 A 0 Xw 0 Ae u
%_4 As 9 0.85 1 2 1 Xy 0.3 g
%_0 0 m 10 0 L 10 10 L 0 10 L 0 0 L n
%_/ArtDictionary : /XMLUID : (board-0) ; (AI10_ArtUID) ,
%_(0.4) /String (BBAccumRotation) , ;
1 (board-0) XW
U
%_/ArtDictionary : 2 /Int (AI13PatternExportType) ,
%_0 /Bool (AI13PatternEnableGuides) ,
%_5 /Int (AI13PatternRegistrationType) ,
%_1 2 3 4 0 0 /RealMatrix (AI13Pattern9SliceScalingGridKey) ,
%_1 /Bool (AI15PixelPerfectSymbolEnablekey) , ;
9 () XW
%AI10_EndSymbol
''';

/// A panel inventory whose name is independent of the equal artboard UUID.
const String artboardSymbolList = '''%AI24_BeginSymbolList
(board-0)
%AI24_EndSymbolList
''';

/// Provides explicit symbol, style and optional resource ownership in setup.
String symbolArtboardSource({String symbol = artboardSymbol, String inventory = artboardSymbolList, String style = artboardSimpleStyle, String resources = '', String body = ''}) =>
    artboardSource(extra: '$resources$style$symbol$inventory', body: body);

/// Checks the entire retained program outside the selected Document dictionary.
void _retained(AiNativeArtboards before, AiNativeArtboards after) {
  check(after.records.program.bytes.take(after.document.start)).deepEquals(before.records.program.bytes.take(before.document.start));
  check(after.records.program.bytes.skip(after.document.end)).deepEquals(before.records.program.bytes.skip(before.document.end));
}

/// Exercises source ownership without expanding or rendering symbol instances.
void main() {
  test('retains symbols identities styles and independent panel names through all artboard edits', () {
    final AiNativeArtboards before = artboardModel(symbolArtboardSource());
    for (final AiNativeArtboards after in [
      before.create(definition: newArtboard(), index: 1, lastArtboardId: 68, cropBounds: null),
      before.resize(artboard: before.artboards.first, bounds: AiBoundingBox(left: -20, bottom: -40, right: 100, top: 200), cropBounds: null),
      before.reorder(artboards: before.artboards.reversed.toList(), cropBounds: null),
      before.remove(artboards: [before.artboards.first], activeArtboard: null, cropBounds: null),
    ]) {
      _retained(before, after);
    }
  });

  test('retains ordinary and empty symbols and legacy NUL-terminated panel wrappers', () {
    for (final String symbol in [artboardSymbol.replaceAll('%_', ''), '%AI14_BeginSymbol\n(board-0)\n%AI10_EndSymbol\n']) {
      for (final String inventory in ['', artboardSymbolList, artboardSymbolList.replaceAll('AI24', 'AI10').replaceFirst('BeginSymbolList', 'BeginSymbolList\u0000')]) {
        final AiNativeArtboards before = artboardModel(symbolArtboardSource(symbol: symbol, inventory: inventory));
        _retained(before, before.reorder(artboards: before.artboards.reversed.toList(), cropBounds: null));
      }
    }
  });

  test('resolves gradient and pattern resources inside symbols without conflating names', () {
    final String symbol = artboardSymbol.replaceFirst(
      '%_0 0 m 10 0 L 10 10 L 0 10 L 0 0 L n',
      '%_0 0 m 10 0 L 10 10 L 0 10 L 0 0 L\n%_Bb 1 (board-0) 0 0 0 1 1 0 0 1 0 0 1 Bg f 0 BB\n%_(board-0) 3 -5 0.5 2 35 1 45 12 7 [1 0.2 0.3 1 40 70] p',
    );
    final AiNativeArtboards before = artboardModel(symbolArtboardSource(symbol: symbol, resources: '$artboardPaletteGradient$artboardPattern'));
    _retained(before, before.remove(artboards: [before.artboards.first], activeArtboard: null, cropBounds: null));
    for (final String resources in ['', artboardPaletteGradient]) {
      final AiNativeArtboards missing = artboardModel(symbolArtboardSource(symbol: symbol, resources: resources));
      check(() => missing.reorder(artboards: missing.artboards.reversed.toList(), cropBounds: null)).throws<UnsupportedError>();
    }
  });

  test('keeps literal blending flags and named fill and stroke alternatives', () {
    for (int mode = 0; mode < 16; mode++) {
      final String symbol = artboardSymbol
          .replaceFirst('9 0.85 1 2 1 Xy', '$mode 0.5 1 2 1 Xy')
          .replaceFirst(
            '0.3 g',
            '0.1 0.2 0.3 0.4 (Ink) 0.5 Xs\n%_0.1 0.2 0.3 0.4 (Ink) 0.5 XS\n%_0 0 0 1 0 0 0 (Ink) 1 1 Xz\n%_0 0 0 1 0 0 0 (Ink) 1 1 XZ',
          );
      final AiNativeArtboards before = artboardModel(symbolArtboardSource(symbol: symbol));
      _retained(before, before.reorder(artboards: before.artboards.reversed.toList(), cropBounds: null));
    }
  });

  test('rejects missing ambiguous conditional and privately listed symbols and styles atomically', () {
    for (final String source in [
      symbolArtboardSource(symbol: ''),
      symbolArtboardSource(symbol: '$artboardSymbol$artboardSymbol'),
      symbolArtboardSource(style: ''),
      symbolArtboardSource(style: '$artboardSimpleStyle$artboardSimpleStyle'),
      symbolArtboardSource(inventory: artboardSymbolList.replaceFirst('(board-0)', '(missing)')),
      symbolArtboardSource(inventory: artboardSymbolList.replaceFirst('(board-0)', '(board-0) (board-0)')),
      symbolArtboardSource(inventory: artboardSymbolList.replaceFirst('(board-0)', '%_(board-0)')),
      symbolArtboardSource(symbol: '%AI17_Begin_Content_if_version_gt:24 4\n$artboardSymbol%AI17_End_Versioned_Content\n'),
    ]) {
      final AiNativeArtboards before = artboardModel(source);
      check(() => before.reorder(artboards: before.artboards.reversed.toList(), cropBounds: null)).throws<UnsupportedError>();
      check(latin1.decode(before.records.program.bytes)).equals(source);
    }
  });

  test('rejects unsupported symbol metadata execution and nested declarations', () {
    for (final String symbol in [
      artboardSymbol.replaceFirst('0 Ae', '(board-0) load'),
      artboardSymbol.replaceFirst('0 Ae', '{ 0 Ae } exec'),
      artboardSymbol.replaceFirst('0 Ae', '%AI24_Unknown: board-0\n0 Ae'),
      artboardSymbol.replaceFirst('9 () XW', artboardPattern),
      artboardSymbol.replaceFirst('AI13PatternRegistrationType', 'FutureArtboardIndex'),
      artboardSymbol.replaceFirst('(0.4) /String (BBAccumRotation)', '/Mask : ; (AI9_Mask)'),
    ]) {
      final AiNativeArtboards before = artboardModel(symbolArtboardSource(symbol: symbol));
      check(() => before.reorder(artboards: before.artboards.reversed.toList(), cropBounds: null)).throws<UnsupportedError>();
    }
    final AiNativeArtboards outside = artboardModel(symbolArtboardSource(resources: '%_/ArtDictionary : 5 /Int (AI13PatternRegistrationType) , ;\n'));
    check(() => outside.reorder(artboards: outside.artboards.reversed.toList(), cropBounds: null)).throws<UnsupportedError>();
  });

  test('rejects malformed symbol names topology counts identities and scalar state', () {
    for (final String symbol in [
      artboardSymbol.replaceFirst('(board-0)', '()'),
      artboardSymbol.replaceFirst('(board-0)', '%_(board-0)'),
      artboardSymbol.replaceFirst('4 As', '5 As'),
      artboardSymbol.replaceFirst('U\n', 'Q\n'),
      artboardSymbol.replaceFirst('(0.4)', '(not numeric)'),
      artboardSymbol.replaceFirst('/XMLUID : (board-0)', '/XMLUID : ()'),
      artboardSymbol.replaceFirst('9 0.85 1 2 1 Xy', '9 0.85 1 2 Xy'),
    ]) {
      check(() {
        final AiNativeArtboards before = artboardModel(symbolArtboardSource(symbol: symbol));
        return before.reorder(artboards: before.artboards.reversed.toList(), cropBounds: null);
      }).throws<FormatException>();
    }
    for (final String values in ['16 0.5 0 0 0', '0 -0.1 0 0 0', '0 0.5 2 0 0', '0 0.5 0 3 0', '0 0.5 0 0 2']) {
      final AiNativeArtboards before = artboardModel(symbolArtboardSource(symbol: artboardSymbol.replaceFirst('9 0.85 1 2 1', values)));
      check(() => before.reorder(artboards: before.artboards.reversed.toList(), cropBounds: null)).throws<UnsupportedError>();
    }
  });

  test('bounds retained symbol group depth with the original program policy', () {
    final String symbol = artboardSymbol.replaceFirst('0 Ae u', '0 Ae ${List.filled(9, 'u').join(' ')} u').replaceFirst('U\n', "U ${List.filled(9, 'U').join(' ')}\n");
    final AiNativeArtboards before = artboardModel(symbolArtboardSource(symbol: symbol), limits: const AiNativeLimits(maxDepth: 8));
    check(() => before.reorder(artboards: before.artboards.reversed.toList(), cropBounds: null)).throws<FormatException>();
  });
}
