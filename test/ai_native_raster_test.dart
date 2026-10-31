import 'dart:convert';
import 'dart:typed_data';

import 'package:aikit/aikit.dart';
import 'package:checks/checks.dart';
import 'package:test/test.dart';

/// Builds a binary native raster independently of the decoder and PDF writer.
Uint8List _bytes({
  int width = 2,
  int height = 2,
  int components = 3,
  int bits = 8,
  List<int>? colors,
  List<int>? alpha,
  bool private = false,
  int adjustment = 1,
  bool countAlpha = false,
  bool mask = false,
}) {
  final List<int> color = colors ?? List<int>.generate(((width * components * bits + 7) ~/ 8) * height, (index) => index * 17 % 256);
  final String prefix = private ? '%_' : '';
  final int flags =
      (components == 4
          ? 2
          : components == 3
          ? 1
          : 0) +
      (alpha == null ? 0 : 16);
  return (BytesBuilder()
        ..add(
          latin1.encode('''%!PS-Adobe-3.0
%%Creator: Adobe Illustrator
%%BoundingBox: 0 0 100 100
%%BeginSetup
%%EndSetup
$prefix%AI5_BeginRaster
$prefix() 1 XG
$prefix/Device${components == 4
              ? 'CMYK'
              : components == 3
              ? 'RGB'
              : 'Gray'} XN
$prefix[ 2 0 0 3 10 20 ] $width $height 0 Xh
$prefix[ 2 0 0 3 10 20 ] 0 0 $width $height $width $height $bits $components ${alpha == null ? 0 : 1} $flags 1 ${mask ? 1 : 0} 4 4 0 0
$prefix%%BeginData: ${color.length + (countAlpha ? alpha?.length ?? 0 : 0) + 3 + adjustment}
XI
'''),
        )
        ..add(color)
        ..add(alpha ?? [])
        ..add(latin1.encode('$prefix%%EndData\n${prefix}XH\n$prefix%AI5_EndRaster\n${prefix}N\n%%Trailer\n%%EOF\n')))
      .takeBytes();
}

/// Reads the public source-backed inventory with the same limits as its program.
AiNativeRasters _decode(List<int> bytes) => AiNativeRasters.decode(
  records: AiNativeRecords.decode(program: AiProgram.decode(bytes: bytes)),
);

/// Renders a fixture without introducing a second image encoder.
PdfDocument _render(List<int> bytes, {PdfLimits limits = const PdfLimits()}) => AiNativePdf.render(
  program: AiProgram.decode(bytes: bytes),
  bounds: AiBoundingBox(left: 0, bottom: 0, right: 100, top: 100),
  limits: limits,
);

/// Checks binary boundaries, immutable image models and synchronized placement.
void main() {
  test('reads color and separate alpha planes for every observed DSC count variant', () {
    for (final int adjustment in [0, 1]) {
      for (final bool countAlpha in [false, true]) {
        final Uint8List bytes = _bytes(alpha: [0, 85, 170, 255], adjustment: adjustment, countAlpha: countAlpha);
        final AiNativeRasters rasters = _decode(bytes);
        final AiNativeRaster image = rasters.images.single;
        check(image.width).equals(2);
        check(image.height).equals(2);
        check(image.matrix).deepEquals([2, 0, 0, 3, 10, 20]);
        check(image.colorSamples).deepEquals(List<int>.generate(12, (index) => index * 17));
        check(image.alphaSamples!).deepEquals([0, 85, 170, 255]);
        check(image.isPrintable(program: rasters.records.program)).isTrue();
        check(() => image.colorSamples[0] = 1).throws<UnsupportedError>();
        check(rasters.records.program.bytes).deepEquals(bytes);
      }
    }
  });

  test('uses geometry rather than delimiter searching inside hostile binary samples', () {
    final List<int> samples = latin1.encode('%%EndData\n%AI5_EndRaster\n%_/Dictionary : 1 /Int (Injected) , ;\n< } [ XI');
    final Uint8List bytes = _bytes(width: samples.length, height: 1, components: 1, colors: samples);
    final AiNativeRasters rasters = _decode(bytes);
    check(rasters.images.single.colorSamples).deepEquals(samples);
    check(rasters.records.roots).isEmpty();
    check(rasters.records.program.instructions.where((instruction) => instruction.operator == 'XI')).length.equals(1);
  });

  test('accepts exact DSC byte counts including a final CRLF separator', () {
    final Uint8List bytes = _bytes(adjustment: 2);
    final AiNativeRasters rasters = _decode(latin1.encode(latin1.decode(bytes).replaceFirst('%%EndData', '\r\n%%EndData')));
    check(rasters.images.single.colorSamples).length.equals(12);
  });

  test('keeps comment-prefixed raster bodies opaque and excludes them from printing', () {
    final List<int> samples = latin1.encode('> %_%%BeginData: 9\n(fake) { /Dictionary :');
    final Uint8List bytes = _bytes(width: samples.length, height: 1, components: 1, colors: samples, private: true);
    final AiNativeRasters rasters = _decode(bytes);
    check(rasters.images.single.instruction.isPrivate).isTrue();
    check(rasters.images.single.colorSamples).deepEquals(samples);
    check(rasters.records.program.instructions.where((instruction) => instruction.operator == 'XI')).isEmpty();
    check(_render(bytes).objects.values.whereType<PdfStream>().where((stream) => stream.dictionary.name('Subtype') == 'Image')).isEmpty();
  });

  test('retains packed rows and sixteen-bit samples without truncating padding', () {
    for (final (int, int, List<int>) fixture in [
      (9, 1, [0x80, 0x80, 0x40, 0]),
      (2, 16, [0x12, 0x34, 0xab, 0xcd, 0, 0, 0xff, 0xff]),
    ]) {
      final Uint8List bytes = _bytes(width: fixture.$1, height: 2, components: 1, bits: fixture.$2, colors: fixture.$3);
      final AiNativeRaster image = _decode(bytes).images.single;
      check(image.colorSamples).deepEquals(fixture.$3);
      final PdfDocument pdf = _render(bytes);
      final PdfStream stream = pdf.objects.values.whereType<PdfStream>().singleWhere((stream) => stream.dictionary.name('Subtype') == 'Image');
      check(stream.dictionary.integer('BitsPerComponent')).equals(fixture.$2);
      check(pdf.decodeStream(stream)).deepEquals(fixture.$3);
    }
  });

  test('writes process images with separate soft masks and the native upper-left origin', () {
    final Uint8List bytes = _bytes(alpha: [0, 85, 170, 255]);
    final PdfDocument pdf = _render(bytes);
    final List<PdfStream> images = pdf.objects.values.whereType<PdfStream>().where((stream) => stream.dictionary.name('Subtype') == 'Image').toList();
    check(images).length.equals(2);
    check(images.map((image) => image.dictionary.name('ColorSpace')).toList()).deepEquals(['DeviceGray', 'DeviceRGB']);
    check(pdf.decodeStream(images.first)).deepEquals([0, 85, 170, 255]);
    check(pdf.resolve(images.last.dictionary['SMask']!)).equals(images.first);
    final PdfOperation matrix = PdfProgram.fromPage(document: pdf, pageIndex: 0).operations.lastWhere((operation) => operation.operator == 'cm');
    check(matrix.operands.cast<PdfNumber>().map((number) => number.value).toList()).deepEquals([4, 0, 0, 6, 10, 14]);
    check(() => _render(bytes, limits: const PdfLimits(maxDecodedBytes: 8))).throws<FormatException>();
  });

  test('retains current fill paint for a one-bit stencil without a color space', () {
    final String source = latin1.decode(_bytes(width: 2, height: 1, components: 1, bits: 1, colors: [0x40], mask: true)).replaceFirst('%%EndSetup', '%%EndSetup\n1 0 0 Xa');
    final PdfDocument pdf = _render(latin1.encode(source));
    final PdfStream image = pdf.objects.values.whereType<PdfStream>().singleWhere((stream) => stream.dictionary.name('Subtype') == 'Image');
    check((image.dictionary['ImageMask']! as PdfBoolean).value).isTrue();
    check(image.dictionary['ColorSpace']).isNull();
    check(pdf.decodeStream(image)).deepEquals([0x40]);
    final PdfOperation paint = PdfProgram.fromPage(document: pdf, pageIndex: 0).operations.singleWhere((operation) => operation.operator == 'rg');
    check(paint.operands.cast<PdfNumber>().map((number) => number.value).toList()).deepEquals([1, 0, 0]);
  });

  test('translates both native matrices while retaining samples and independent metadata', () {
    final Uint8List bytes = _bytes(alpha: [0, 85, 170, 255]);
    final AiNativeRasters before = _decode(bytes);
    final AiNativeRasters after = before.translate(images: before.images, deltaX: 37, deltaY: -19);
    final AiNativeRaster image = after.images.single;
    check(image.matrix).deepEquals([2, 0, 0, 3, 47, 1]);
    check(image.commands.singleWhere((command) => command.operator == 'Xh').operands.skip(1).take(6).map((token) => token.number).toList()).deepEquals([2, 0, 0, 3, 47, 1]);
    check(image.colorSamples).deepEquals(before.images.single.colorSamples);
    check(image.alphaSamples!).deepEquals(before.images.single.alphaSamples!);
    check(latin1.decode(after.records.program.bytes)).contains('%%BoundingBox: 0 -19 137 100');
    check(before.records.program.bytes).deepEquals(bytes);
    check(() => before.translate(images: after.images, deltaX: 1, deltaY: 0)).throws<ArgumentError>();
    check(() => before.translate(images: before.images, deltaX: double.infinity, deltaY: 0)).throws<ArgumentError>();
    final AiNativeRasters inconsistent = _decode(latin1.encode(latin1.decode(bytes).replaceFirst('10 20 ] 2 2 0 Xh', '99 20 ] 2 2 0 Xh')));
    check(() => inconsistent.translate(images: inconsistent.images, deltaX: 1, deltaY: 0)).throws<UnsupportedError>();
  });

  test('rejects bad lengths and byte boundaries even when a later marker looks valid', () {
    final Uint8List valid = _bytes();
    check(() => _decode(_bytes(adjustment: 2))).throws<FormatException>();
    check(() => _decode(_bytes(colors: [1, 2]))).throws<FormatException>();
    check(() => _decode(latin1.encode(latin1.decode(valid).replaceFirst('%%EndData', 'junk\n%%EndData')))).throws<FormatException>();
    check(() => _decode(latin1.encode(latin1.decode(valid).replaceFirst('2 2 8 3', '999999999 2 8 3')))).throws<FormatException>();
    check(() => _decode(_bytes(bits: 3))).throws<UnsupportedError>();
    check(() => _decode(_bytes(mask: true))).throws<FormatException>();
  });

  test('rejects unknown color or placement semantics and unrelated opaque drawing data', () {
    final String valid = latin1.decode(_bytes());
    for (final String body in [
      valid.replaceFirst('/DeviceRGB', '/CustomSpace'),
      valid.replaceFirst('4 4 0 0\n%%BeginData', '4 4 1 0\n%%BeginData'),
      valid.replaceFirst('10 20 ] 2 2 0 Xh', '99 20 ] 2 2 0 Xh'),
      valid.replaceFirst('0 0 2 2 2 2 8', '0 0 3 2 2 2 8'),
      valid.replaceFirst('XH\n', 'FutureImagePaint\nXH\n'),
    ]) {
      check(() => _render(latin1.encode(body))).throws<UnsupportedError>();
    }
    check(() => _render(latin1.encode(valid.replaceFirst('%%EndSetup', '%%EndSetup\n%%BeginData: 3\nabc\n%%EndData')))).throws<UnsupportedError>();
  });
}
