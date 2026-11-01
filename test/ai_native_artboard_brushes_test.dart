import 'dart:convert';

import 'package:aikit/aikit.dart';
import 'package:checks/checks.dart';
import 'package:test/test.dart';

import 'ai_native_artboard_lifecycle_test.dart' show newArtboard;
import 'ai_native_artboard_palette_test.dart' show artboardPaletteGradient;
import 'ai_native_artboard_patterns_test.dart' show artboardPattern;
import 'ai_native_artboard_references_test.dart' show artboardSimpleStyle;
import 'ai_native_artboard_symbols_test.dart' show artboardSymbol, artboardSymbolList;
import 'ai_native_artboards_test.dart' show artboardModel, artboardSource;

/// Emits process samples and a separate alpha plane in one bounded source image.
String artboardBrushRaster({int components = 4, bool alpha = true, bool private = false, bool colorCount = false, List<int>? colors, List<int>? alphaSamples}) {
  final String prefix = private ? '%_' : '';
  final List<int> samples = colors ?? List.generate(components * 2, (index) => (index * 37) % 256);
  final int width = samples.length ~/ components;
  final List<int> pixels = [...samples, if (alpha) ...alphaSamples ?? List.generate(width, (index) => (index * 127) % 256)];
  final String space = components == 1
      ? 'Gray'
      : components == 3
      ? 'RGB'
      : 'CMYK';
  final int flags =
      (components == 1
          ? 0
          : components == 3
          ? 1
          : 2) +
      (alpha ? 16 : 0);
  return '''$prefix%AI5_File:
$prefix%AI5_BeginRaster
$prefix() 1 XG
$prefix/Device$space XN
$prefix[0.24 0 0 -0.24 30 -40] $width 1 0 Xh
$prefix[0.24 0 0 -0.24 30 -40] 0 0 $width 1 $width 1 8 $components ${alpha ? 1 : 0} $flags 1 0 4 4 0 0
$prefix%%BeginData: ${(colorCount ? samples.length : pixels.length) + 3}
XI
${latin1.decode(pixels)}$prefix%%EndData
${prefix}XH
$prefix%AI5_EndRaster
${prefix}N
$prefix/ArtDictionary : /XMLUID : (board-0) ; (AI10_ArtUID) ,
$prefix(board-0) /UnicodeString (AI24 ImageRawDataUUID) ,
$prefix(retained-alpha) /UnicodeString (AI24 ImageAlphaRawDataUUID) ,
${prefix}0.24 /Real (Raster Art Original Scale) , ;
''';
}

/// A resource with ordinary compound/clip topology and image-owned metadata.
String artboardBrush({String? art, String name = 'board-0'}) =>
    '''%AI8_BeginBrushPattern
($name)
0 A 0 Xw 0 Ae u
${art ?? 'q\n${artboardBrushRaster()}4 As 0 0 m 20 0 L 20 20 L 0 20 L 0 0 L h W n Q'}
U
9 () XW
%AI8_EndBrushPattern
''';

/// Checks complete retained resources, including both original sample planes.
void _retained(AiNativeArtboards before, AiNativeArtboards after) {
  check(after.records.program.bytes.take(after.document.start)).deepEquals(before.records.program.bytes.take(before.document.start));
  check(after.records.program.bytes.skip(after.document.end)).deepEquals(before.records.program.bytes.skip(before.document.end));
  final List<AiNativeRaster> original = AiNativeRasters.decode(records: before.records).images;
  final List<AiNativeRaster> result = AiNativeRasters.decode(records: after.records).images;
  check(result.map((image) => image.colorSamples)).deepEquals(original.map((image) => image.colorSamples));
  check(result.map((image) => image.alphaSamples)).deepEquals(original.map((image) => image.alphaSamples));
}

/// Verifies immutable brush-resource retention independently of brush execution.
void main() {
  test('retains brush paths clips raster planes and identities through every artboard operation', () {
    final AiNativeArtboards before = artboardModel(artboardSource(extra: artboardBrush()));
    for (final AiNativeArtboards after in [
      before.create(definition: newArtboard(), index: 1, lastArtboardId: 68, cropBounds: null),
      before.resize(artboard: before.artboards.first, bounds: AiBoundingBox(left: -20, bottom: -40, right: 100, top: 200), cropBounds: null),
      before.reorder(artboards: before.artboards.reversed.toList(), cropBounds: null),
      before.remove(artboards: [before.artboards.first], activeArtboard: null, cropBounds: null),
    ]) {
      _retained(before, after);
    }
  });

  test('retains process colors alpha variants and both producer byte counts', () {
    for (final int components in [1, 3, 4]) {
      for (final bool alpha in [false, true]) {
        for (final bool private in [false, true]) {
          for (final bool colorCount in [false, true]) {
            final String raster = artboardBrushRaster(components: components, alpha: alpha, private: private, colorCount: colorCount);
            final AiNativeArtboards before = artboardModel(artboardSource(extra: artboardBrush(art: raster)));
            _retained(before, before.reorder(artboards: before.artboards.reversed.toList(), cropBounds: null));
          }
        }
      }
    }
  });

  test('shares image ownership with direct pattern and symbol resources without merging names', () {
    final String image = artboardBrushRaster();
    final String symbol = artboardSymbol.replaceFirst('0 Ae u', '0 Ae u\n$image');
    final String pattern = '%AI3_BeginPattern: (board-0)\n(board-0) 0 0 100 100\n$image\nE\n%AI3_EndPattern\n';
    final AiNativeArtboards before = artboardModel(artboardSource(extra: '${artboardBrush()}$symbol$artboardSymbolList$pattern$artboardSimpleStyle'));
    check(AiNativeRasters.decode(records: before.records).images).length.equals(3);
    _retained(before, before.remove(artboards: [before.artboards.first], activeArtboard: null, cropBounds: null));
  });

  test('resolves brush styles patterns and gradients while retaining empty and vector resources', () {
    for (final String art in [
      '',
      '*u 4 As 0.3 g 0 0 m 10 0 L 10 10 L 0 10 L 0 0 L f *U',
      '0 (board-0) XW\n%_1 (board-0) XW\n(board-0) 0 0 1 1 0 0 0 0 0 [1 0 0 1 0 0] p\nBb 1 (board-0) 0 0 0 1 1 0 0 1 0 0 1 Bg 0 BB',
    ]) {
      final AiNativeArtboards before = artboardModel(artboardSource(extra: '${artboardBrush(art: art)}$artboardSimpleStyle$artboardPattern$artboardPaletteGradient'));
      _retained(before, before.reorder(artboards: before.artboards.reversed.toList(), cropBounds: null));
    }
    for (final String resources in ['', '$artboardSimpleStyle$artboardSimpleStyle']) {
      final AiNativeArtboards before = artboardModel(artboardSource(extra: '${artboardBrush(art: '0 (board-0) XW')}$resources'));
      check(() => before.reorder(artboards: before.artboards.reversed.toList(), cropBounds: null)).throws<UnsupportedError>();
    }
  });

  test('keeps hostile color and alpha bytes opaque across resource boundaries', () {
    final List<int> pixels = latin1.encode('%AI8_EndBrushPattern\n%AI14_BeginSymbol\n(fake)\n%%EndData\n/ArtDictionary : ;');
    final String image = artboardBrushRaster(components: 1, colors: pixels, alphaSamples: pixels);
    final String source = artboardSource(
      extra: '${artboardBrush(art: image)}${artboardBrush(art: '', name: 'after')}',
    );
    final AiNativeArtboards before = artboardModel(source);
    _retained(before, before.reorder(artboards: before.artboards.reversed.toList(), cropBounds: null));
    check(AiNativeRasters.decode(records: before.records).images.single.colorSamples).deepEquals(pixels);
    check(AiNativeRasters.decode(records: before.records).images.single.alphaSamples).isNotNull().deepEquals(pixels);
  });

  test('rejects unrelated annotations metadata embedded programs and resource ambiguity atomically', () {
    final String brush = artboardBrush();
    for (final String resource in [
      '$brush$brush',
      brush.replaceFirst('0 Ae u', '0 Ae u\n$artboardPattern'),
      brush.replaceFirst('%AI5_File:', '%AI5_File: external.tif'),
      brush.replaceFirst('%AI5_File:', '%AI24_ArtboardRef: board-0\n%AI5_File:'),
      brush.replaceFirst('XH', 'XH\n%AI24_ArtboardRef: board-0'),
      brush.replaceFirst('Raster Art Original Scale', 'ArtboardIndex'),
      brush.replaceFirst('q\n', 'q\n(board-0) load\n'),
      brush.replaceFirst('q\n', 'q\n%%BeginData: 4\nABCD\n%%EndData\n'),
      brush.replaceFirst('q\n', 'q\n%%BeginDocument: embedded.eps\n0 0 m N\n%%EndDocument\n'),
      brush.replaceFirst('0 A', '%_/ArtDictionary : (board-0) /String (AI24 ImageRawDataUUID) , ;\n0 A'),
      '%AI17_Begin_Content_if_version_gt:24 4\n$brush%AI17_End_Versioned_Content\n',
    ]) {
      final String source = artboardSource(extra: resource);
      final AiNativeArtboards before = artboardModel(source);
      check(() => before.reorder(artboards: before.artboards.reversed.toList(), cropBounds: null)).throws<UnsupportedError>();
      check(latin1.decode(before.records.program.bytes)).equals(source);
    }
  });

  test('rejects malformed image framing geometry ownership and portable placement', () {
    final String brush = artboardBrush();
    for (final String changed in [
      brush.replaceFirst('4 As', '5 As'),
      brush.replaceFirst('Q\n', 'U\n'),
      brush.replaceFirst('N\n/ArtDictionary', '1 N\n/ArtDictionary'),
      brush.replaceFirst('%%BeginData: 13', '%%BeginData: 999'),
      brush.replaceAll('[0.24 0 0 -0.24 30 -40]', '[9007199254740992 0 0 -0.24 30 -40]'),
    ]) {
      check(() {
        final AiNativeArtboards before = artboardModel(artboardSource(extra: changed));
        before.reorder(artboards: before.artboards.reversed.toList(), cropBounds: null);
      }).throws<FormatException>();
    }
    for (final String changed in [
      brush.replaceFirst('/DeviceCMYK', '/UnknownProfile'),
      brush.replaceFirst('%AI5_EndRaster', '%_ %AI5_EndRaster'),
      brush.replaceFirst('[0.24 0 0 -0.24 30 -40]', '[1 0 0 1 30 -40]'),
    ]) {
      final AiNativeArtboards unsupported = artboardModel(artboardSource(extra: changed));
      check(() => unsupported.reorder(artboards: unsupported.artboards.reversed.toList(), cropBounds: null)).throws<UnsupportedError>();
    }
  });

  test('retains original parser depth and output byte limits for brush collections', () {
    final String source = artboardSource(extra: artboardBrush(art: '${List.filled(12, 'u').join(' ')} ${List.filled(12, 'U').join(' ')}'));
    final AiNativeArtboards limited = artboardModel(source, limits: const AiNativeLimits(maxDepth: 8));
    check(() => limited.reorder(artboards: limited.artboards.reversed.toList(), cropBounds: null)).throws<FormatException>();
    final String bytes = artboardSource(extra: artboardBrush());
    final AiNativeArtboards bounded = artboardModel(bytes, limits: AiNativeLimits(maxDecodedBytes: bytes.length));
    check(() => bounded.create(definition: newArtboard(), index: 1, lastArtboardId: 68, cropBounds: null)).throws<FormatException>();
  });
}
