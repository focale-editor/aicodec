import 'dart:convert';

import 'package:aikit/aikit.dart';
import 'package:checks/checks.dart';
import 'package:test/test.dart';

import 'ai_native_artboard_lifecycle_test.dart' show newArtboard;
import 'ai_native_artboard_symbols_test.dart' show artboardSymbol, symbolArtboardSource;
import 'ai_native_artboards_test.dart' show artboardModel;

/// Emits exact gray samples inside a counted private raster section.
String artboardMaskRaster({List<int> pixels = const [0, 85, 170, 255], bool private = true}) {
  final String prefix = private ? '%_' : '';
  return '''$prefix%AI5_File:
$prefix%AI5_BeginRaster
$prefix() 1 XG
$prefix/DeviceGray XN
$prefix[1 0 0 1 30 -40] ${pixels.length} 1 0 Xh
$prefix[1 0 0 1 30 -40] 0 0 ${pixels.length} 1 ${pixels.length} 1 8 1 0 0 1 0 4 4 0 0
$prefix%%BeginData: ${pixels.length + 4}
XI
${latin1.decode(pixels)}$prefix%%EndData
${prefix}XH
$prefix%AI5_EndRaster
${prefix}N
$prefix/ArtDictionary : (board-0) /UnicodeString (AI24 ImageRawDataUUID) ,
$prefix(kept-alpha) /String (AI24 ImageAlphaRawDataUUID) ,
${prefix}1 /Real (Raster Art Original Scale) ,
${prefix}1 /Bool (AI9 Fuzzy Mask) , ;
''';
}

/// Defines explicit mask flags independently of the enclosing symbol drawing.
String artboardOpacityMask({String? art, bool private = true}) {
  final String prefix = private ? '%_' : '';
  return '''$prefix/Mask : 1 /Bool (Linked) ,
${prefix}X=
${prefix}0 Ae u 0 Ap
${art ?? artboardMaskRaster(private: private)}${prefix}U
${prefix}9 () XW
${prefix}X+ (Art) ,
${prefix}0 /Bool (Disabled) , 0 /Bool (Clipping) , 0 /Bool (Inverted) , ;
''';
}

/// Adds the mask to existing identified symbol metadata without changing names.
String maskArtboardSource({String? mask, String extra = ''}) => symbolArtboardSource(
  symbol: artboardSymbol.replaceFirst('%_(0.4) /String (BBAccumRotation)', '${mask ?? artboardOpacityMask()}%_(AI9_Mask) ,\n$extra%_(0.4) /String (BBAccumRotation)'),
);

/// Checks every unselected source byte, including image samples and mask flags.
void _retained(AiNativeArtboards before, AiNativeArtboards after) {
  check(after.records.program.bytes.take(after.document.start)).deepEquals(before.records.program.bytes.take(before.document.start));
  check(after.records.program.bytes.skip(after.document.end)).deepEquals(before.records.program.bytes.skip(before.document.end));
  check(AiNativeRasters.decode(records: after.records).images.map((image) => image.colorSamples)).deepEquals(AiNativeRasters.decode(records: before.records).images.map((image) => image.colorSamples));
}

/// Verifies source preservation without recomposing opacity masks.
void main() {
  test('retains mask flags raster samples placement and identities through every artboard edit', () {
    final AiNativeArtboards before = artboardModel(maskArtboardSource());
    for (final AiNativeArtboards after in [
      before.create(definition: newArtboard(), index: 1, lastArtboardId: 68, cropBounds: null),
      before.resize(artboard: before.artboards.first, bounds: AiBoundingBox(left: -20, bottom: -30, right: 120, top: 250), cropBounds: null),
      before.reorder(artboards: before.artboards.reversed.toList(), cropBounds: null),
      before.remove(artboards: [before.artboards.first], activeArtboard: null, cropBounds: null),
    ]) {
      _retained(before, after);
    }
  });

  test('retains ordinary vector empty and independently nested opacity masks', () {
    final String nested = '%_/ArtDictionary :\n${artboardOpacityMask(art: '')}%_(AI9_Mask) , ;\n';
    for (final String mask in [
      artboardOpacityMask(private: false),
      artboardOpacityMask(art: ''),
      artboardOpacityMask(art: '%_4 As 0.3 g 0 0 m 10 0 L 10 10 L 0 10 L 0 0 L f\n'),
      artboardOpacityMask(art: nested),
    ]) {
      final AiNativeArtboards before = artboardModel(maskArtboardSource(mask: mask));
      _retained(before, before.reorder(artboards: before.artboards.reversed.toList(), cropBounds: null));
    }
  });

  test('retains each mask flag combination without interpreting the pixels', () {
    for (int flags = 0; flags < 16; flags++) {
      String mask = artboardOpacityMask();
      for (final (int, String) flag in ['Linked', 'Disabled', 'Clipping', 'Inverted'].indexed) {
        mask = mask.replaceFirst(RegExp('[01] /Bool \\(${flag.$2}\\)'), '${(flags >> flag.$1) & 1} /Bool (${flag.$2})');
      }
      final AiNativeArtboards before = artboardModel(maskArtboardSource(mask: mask));
      _retained(before, before.remove(artboards: [before.artboards.first], activeArtboard: null, cropBounds: null));
    }
  });

  test('retains hostile binary bytes and a known raster observer without parsing samples', () {
    final String raster = artboardMaskRaster(pixels: latin1.encode('%%EndData\n%AI10_EndSymbol\n%_/Mask : 0 /Bool (Art) , ; X+'));
    final AiNativeArtboards before = artboardModel(
      maskArtboardSource(
        mask: artboardOpacityMask(art: raster),
        extra: '%_/Array : (AI Auto Rasterize) /String , ; (Adobe_AI9_Observed_Key_Strings) ,\n',
      ),
    );
    _retained(before, before.reorder(artboards: before.artboards.reversed.toList(), cropBounds: null));
  });

  test('rejects unknown incomplete duplicate or executable mask dependencies atomically', () {
    for (final String mask in [
      artboardOpacityMask().replaceFirst('(Linked)', '(FutureArtboard)'),
      artboardOpacityMask().replaceFirst('1 /Bool (Linked) ,', ''),
      artboardOpacityMask().replaceFirst('1 /Bool (Linked) ,', '1 /Bool (Linked) , 0 /Bool (Linked) ,'),
      artboardOpacityMask(art: '%_(board-0) load\n'),
      artboardOpacityMask(art: '%_/ArtDictionary : (board-0) /String (FutureReference) , ;\n'),
      artboardOpacityMask(art: artboardMaskRaster().replaceFirst('XG\n', 'XG\n%_%AI24_Unknown: board-0\n')),
      artboardOpacityMask(art: artboardMaskRaster().replaceFirst('%AI5_File:', '%AI5_File: opaque')),
      artboardOpacityMask(art: '%_%AI24_Unknown: board-0\n'),
    ]) {
      final String source = maskArtboardSource(mask: mask);
      final AiNativeArtboards before = artboardModel(source);
      check(() => before.reorder(artboards: before.artboards.reversed.toList(), cropBounds: null)).throws<UnsupportedError>();
      check(latin1.decode(before.records.program.bytes)).equals(source);
    }
  });

  test('rejects malformed mask fields boundaries and point counts', () {
    for (final String mask in [
      artboardOpacityMask().replaceFirst('1 /Bool (Linked)', '2 /Bool (Linked)'),
      artboardOpacityMask().replaceFirst('X=', '1 X='),
      artboardOpacityMask().replaceFirst('X+', 'X='),
      artboardOpacityMask().replaceFirst('%_X+', 'X+'),
      artboardOpacityMask(art: '%_4 As\n${artboardMaskRaster()}'),
      artboardOpacityMask(art: artboardMaskRaster().replaceFirst('%_N\n', '%_1 N\n')),
      artboardOpacityMask(art: artboardMaskRaster().replaceFirst('XH\n', 'XH\n%_0 FutureImage\n')),
    ]) {
      check(() {
        final AiNativeArtboards before = artboardModel(maskArtboardSource(mask: mask));
        return before.reorder(artboards: before.artboards.reversed.toList(), cropBounds: null);
      }).throws<FormatException>();
    }
  });

  test('rejects inconsistent raster placement unknown metadata and unowned image fields', () {
    for (final String raster in [
      artboardMaskRaster().replaceFirst('[1 0 0 1 30 -40] 4 1 0 Xh', '[1 0 0 1 40 -40] 4 1 0 Xh'),
      artboardMaskRaster().replaceFirst('/DeviceGray', '/ProfileSpace'),
      artboardMaskRaster().replaceFirst('XH\n', '0 FutureImage\n%_XH\n'),
      artboardMaskRaster().replaceFirst('AI9 Fuzzy Mask', 'FutureImageReference'),
    ]) {
      final AiNativeArtboards before = artboardModel(maskArtboardSource(mask: artboardOpacityMask(art: raster)));
      check(() => before.reorder(artboards: before.artboards.reversed.toList(), cropBounds: null)).throws<UnsupportedError>();
    }
    final AiNativeArtboards outside = artboardModel(maskArtboardSource(extra: '%_(board-0) /String (AI24 ImageRawDataUUID) ,\n'));
    check(() => outside.reorder(artboards: outside.artboards.reversed.toList(), cropBounds: null)).throws<UnsupportedError>();
  });

  test('retains original nesting and output bounds for recursive mask inspection', () {
    final String mask = artboardOpacityMask(art: '%_${List.filled(9, 'u').join(' ')}\n%_${List.filled(9, 'U').join(' ')}\n');
    final AiNativeArtboards before = artboardModel(maskArtboardSource(mask: mask), limits: const AiNativeLimits(maxDepth: 8));
    check(() => before.reorder(artboards: before.artboards.reversed.toList(), cropBounds: null)).throws<FormatException>();
  });
}
