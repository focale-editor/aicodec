import 'dart:convert';
import 'dart:typed_data';

import 'package:aicodec/aicodec.dart';
import 'package:checks/checks.dart';
import 'package:test/test.dart';

/// Builds a binary native raster independently of the decoder.
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

/// Adds native sample UUIDs alongside unrelated object metadata.
Uint8List _metadata(List<int> bytes) => Uint8List.fromList(
  latin1.encode(
    latin1.decode(bytes).replaceFirst('%%Trailer', '''%_/ArtDictionary :
%_(11111111-1111-4111-8111-111111111111) /UnicodeString (AI24 ImageRawDataUUID) ,
%_(22222222-2222-4222-8222-222222222222) /String (AI24 ImageAlphaRawDataUUID) ,
%_(kept) /String (Object name) ,
%_0.24 /Real (Raster Art Original Scale) ,
%_;
%%Trailer'''),
  ),
);

/// Copies a source image into explicitly owned replacement sample planes.
AiNativeRasterSamples _samples(AiNativeRaster image, {List<int>? colors, List<int>? alpha, bool opaque = false}) => AiNativeRasterSamples(
  width: image.width,
  height: image.height,
  bitsPerComponent: image.bitsPerComponent,
  components: image.components,
  colorSamples: colors ?? image.colorSamples,
  alphaSamples: opaque ? null : alpha ?? image.alphaSamples,
  imageMask: image.imageMask,
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
  });

  test('retains packed rows and sixteen-bit samples without truncating padding', () {
    for (final (int, int, List<int>) fixture in [
      (9, 1, [0x80, 0x80, 0x40, 0]),
      (2, 16, [0x12, 0x34, 0xab, 0xcd, 0, 0, 0xff, 0xff]),
    ]) {
      final Uint8List bytes = _bytes(width: fixture.$1, height: 2, components: 1, bits: fixture.$2, colors: fixture.$3);
      final AiNativeRaster image = _decode(bytes).images.single;
      check(image.colorSamples).deepEquals(fixture.$3);
      check(image.bitsPerComponent).equals(fixture.$2);
    }
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
    final String unqualified = latin1.decode(valid).replaceFirst('%%BeginData: 16\nXI\n', 'XI\n%%BeginData: 12\n');
    check(() => _decode(latin1.encode(unqualified))).throws<UnsupportedError>();
  });

  test('owns validated replacement bytes including packed and sixteen-bit rows', () {
    final List<int> color = [0x80, 0, 0x40, 0];
    final List<int> alpha = [0, 0, 0x80, 0];
    final AiNativeRasterSamples samples = AiNativeRasterSamples(width: 9, height: 2, bitsPerComponent: 1, components: 1, colorSamples: color, alphaSamples: alpha);
    color[0] = 0;
    alpha[0] = 255;
    check(samples.colorSamples).deepEquals([0x80, 0, 0x40, 0]);
    check(samples.alphaSamples!).deepEquals([0, 0, 0x80, 0]);
    check(() => samples.colorSamples[0] = 0).throws<UnsupportedError>();
    check(() => samples.alphaSamples![0] = 0).throws<UnsupportedError>();
    for (final List<int> invalid in [
      [0],
      [0, 256],
      [0, -1],
      [0, 0, 0],
    ]) {
      check(() => AiNativeRasterSamples(width: 1, height: 1, bitsPerComponent: 16, components: 1, colorSamples: invalid)).throws<ArgumentError>();
    }
    check(() => AiNativeRasterSamples(width: 1, height: 1, bitsPerComponent: 8, components: 1, colorSamples: [0], alphaSamples: [])).throws<ArgumentError>();
    check(() => AiNativeRasterSamples(width: 0, height: 1, bitsPerComponent: 8, components: 1, colorSamples: [0])).throws<ArgumentError>();
    check(() => AiNativeRasterSamples(width: 1, height: 1, bitsPerComponent: 3, components: 1, colorSamples: [0])).throws<ArgumentError>();
    check(() => AiNativeRasterSamples(width: 1, height: 1, bitsPerComponent: 8, components: 1, colorSamples: [0], imageMask: true)).throws<ArgumentError>();
  });

  test('changes only the modified plane identity and retains object metadata', () {
    final Uint8List bytes = _metadata(_bytes(alpha: [0, 85, 170, 255]));
    final AiNativeRasters before = _decode(bytes);
    final AiNativeRaster first = before.images.single;
    final List<int> colors = first.colorSamples.map((byte) => 255 - byte).toList();
    final AiNativeRasters after = before.replacePixels(
      image: first,
      samples: _samples(first, colors: colors),
    );
    final AiNativeRaster second = after.images.single;
    check(second.colorSamples).deepEquals(colors);
    check(second.alphaSamples!).deepEquals(first.alphaSamples!);
    check(second.dictionary!['AI24 ImageRawDataUUID']!.text() == first.dictionary!['AI24 ImageRawDataUUID']!.text()).isFalse();
    check(second.dictionary!['AI24 ImageAlphaRawDataUUID']!.text()).equals(first.dictionary!['AI24 ImageAlphaRawDataUUID']!.text());
    check(second.dictionary!['Object name']!.text()).equals('kept');
    check(second.dictionary!['Raster Art Original Scale']!.number).equals(0.24);
    check(second.declaration.lexeme).equals('%%BeginData: 19 Binary Bytes');
    check(before.records.program.bytes).deepEquals(bytes);
    check(identical(after.replacePixels(image: second, samples: _samples(second)), after)).isTrue();
    check(() => before.replacePixels(image: second, samples: _samples(second))).throws<ArgumentError>();
  });

  test('adds edits and removes alpha without reusing either previous alpha identity', () {
    AiNativeRasters source = _decode(_metadata(_bytes()));
    final String colorIdentity = source.images.single.dictionary!['AI24 ImageRawDataUUID']!.text()!;
    final Set<String> alphaIdentities = {source.images.single.dictionary!['AI24 ImageAlphaRawDataUUID']!.text()!};
    for (final List<int>? alpha in [
      [0, 85, 170, 255],
      [255, 170, 85, 0],
      null,
    ]) {
      final AiNativeRaster image = source.images.single;
      source = source.replacePixels(
        image: image,
        samples: _samples(image, alpha: alpha, opaque: alpha == null),
      );
      final AiNativeRaster edited = source.images.single;
      check(edited.hasAlpha).equals(alpha != null);
      check(edited.flags).equals(alpha == null ? 1 : 17);
      check(edited.dictionary!['AI24 ImageRawDataUUID']!.text()).equals(colorIdentity);
      check(alphaIdentities.add(edited.dictionary!['AI24 ImageAlphaRawDataUUID']!.text()!)).isTrue();
      if (alpha == null) {
        check(edited.alphaSamples).isNull();
      } else {
        check(edited.alphaSamples!).deepEquals(alpha);
      }
    }
  });

  test('changes resolution depth and color space while preserving the placed extent', () {
    final AiNativeRasters before = _decode(_metadata(_bytes()));
    final AiNativeRasters after = before.replacePixels(
      image: before.images.single,
      samples: AiNativeRasterSamples(
        width: 4,
        height: 3,
        bitsPerComponent: 16,
        components: 1,
        colorSamples: List.generate(24, (index) => index * 10),
        alphaSamples: List.filled(24, 255),
      ),
    );
    final AiNativeRaster image = after.images.single;
    check(image.matrix).deepEquals([1, 0, 0, 2, 10, 20]);
    check(image.bounds).deepEquals([0, 0, 4, 3]);
    check(image.width).equals(4);
    check(image.height).equals(3);
    check(image.bitsPerComponent).equals(16);
    check(image.components).equals(1);
    check(image.commands.singleWhere((command) => command.operator == 'XN').operands.single.lexeme).equals('/DeviceGray');
  });

  test('preserves reflection and shear when changing sample dimensions', () {
    final AiNativeRasters source = _decode(latin1.encode(latin1.decode(_bytes()).replaceAll('[ 2 0 0 3 10 20 ]', '[ -2 1 4 3 10 20 ]')));
    final AiNativeRasters edited = source.replacePixels(
      image: source.images.single,
      samples: AiNativeRasterSamples(width: 4, height: 1, bitsPerComponent: 8, components: 4, colorSamples: List.filled(16, 128)),
    );
    check(edited.images.single.matrix).deepEquals([-1, 0.5, 8, 6, 10, 20]);
  });

  test('supports wide packed rows whose column count exceeds the source byte count', () {
    final AiNativeRasters source = _decode(_bytes(width: 10000, height: 1, bits: 1, components: 1, colors: List.filled(1250, 0)));
    final AiNativeRasters edited = source.replacePixels(
      image: source.images.single,
      samples: _samples(source.images.single, colors: List.filled(1250, 255)),
    );
    check(edited.images.single.width).equals(10000);
    check(edited.images.single.colorSamples).deepEquals(List.filled(1250, 255));
  });

  test('keeps replacement bytes opaque in private native records', () {
    final AiNativeRasters source = _decode(_metadata(_bytes(private: true)));
    final List<int> colors = latin1.encode('%_%%EndData\n(fake) { /ArtDictionary :\n');
    final AiNativeRasters edited = source.replacePixels(
      image: source.images.single,
      samples: AiNativeRasterSamples(width: colors.length, height: 1, bitsPerComponent: 8, components: 1, colorSamples: colors),
    );
    check(edited.images.single.colorSamples).deepEquals(colors);
    check(edited.images.single.instruction.isPrivate).isTrue();
    check(edited.images.single.dictionary!['Object name']!.text()).equals('kept');
  });

  test('marks retained source links as modified and rejects unqualified metadata', () {
    final String original = latin1.decode(_metadata(_bytes())).replaceFirst('() 1 XG', '(source.tif) 0 XG');
    final AiNativeRasters source = _decode(latin1.encode(original));
    final AiNativeRaster first = source.images.single;
    final AiNativeRasters edited = source.replacePixels(
      image: first,
      samples: _samples(first, colors: List.filled(12, 99)),
    );
    check(latin1.decode(edited.records.program.bytes)).contains('(source.tif) 1 XG');
    for (final String invalid in [
      original.replaceFirst('/DeviceRGB', '/CustomSpace'),
      original.replaceFirst('4 4 0 0\n%%BeginData', '4 4 1 0\n%%BeginData'),
      original.replaceFirst('10 20 ] 2 2 0 Xh', '99 20 ] 2 2 0 Xh'),
      original.replaceFirst('11111111-1111-4111-8111-111111111111', 'unqualified'),
      original.replaceFirst('/UnicodeString (AI24 ImageRawDataUUID)', '/FutureType (AI24 ImageRawDataUUID)'),
    ]) {
      final AiNativeRasters unknown = _decode(latin1.encode(invalid));
      check(
        () => unknown.replacePixels(
          image: unknown.images.single,
          samples: _samples(first, colors: List.filled(12, 99)),
        ),
      ).throws<UnsupportedError>();
    }
  });

  test('bounds replacements before allocating a larger edited program', () {
    final Uint8List bytes = _bytes();
    final AiNativeRasters source = AiNativeRasters.decode(
      records: AiNativeRecords.decode(
        program: AiProgram.decode(
          bytes: bytes,
          limits: AiNativeLimits(maxDecodedBytes: bytes.length),
        ),
      ),
    );
    final AiNativeRasterSamples samples = AiNativeRasterSamples(width: 100, height: 100, bitsPerComponent: 8, components: 3, colorSamples: List.filled(30000, 0));
    check(() => source.replacePixels(image: source.images.single, samples: samples)).throws<FormatException>();
    check(source.records.program.bytes).deepEquals(bytes);
  });

  test('isolates shared sample UUIDs and does not attach metadata across drawing commands', () {
    final String one = latin1.decode(_metadata(_bytes()));
    final String raster = one.substring(one.indexOf('%AI5_BeginRaster'), one.indexOf('%%Trailer'));
    final AiNativeRasters source = _decode(latin1.encode(one.replaceFirst('%%Trailer', '$raster%%Trailer')));
    final AiNativeRasters edited = source.replacePixels(
      image: source.images.first,
      samples: _samples(source.images.first, colors: List.filled(12, 99)),
    );
    check(edited.images.last.dictionary!['AI24 ImageRawDataUUID']!.text()).equals(source.images.last.dictionary!['AI24 ImageRawDataUUID']!.text());
    check(edited.images.last.colorSamples).deepEquals(source.images.last.colorSamples);
    final AiNativeRasters unrelated = _decode(latin1.encode(one.replaceFirst('%_/ArtDictionary', '0 0 m 1 1 L S\n%_/ArtDictionary')));
    check(unrelated.images.single.dictionary).isNull();
  });

  test('edits a body-only inventory without confusing setup image indices', () {
    final String one = latin1.decode(_metadata(_bytes()));
    final String raster = one.substring(one.indexOf('%AI5_BeginRaster'), one.indexOf('%%Trailer'));
    final AiNativeRecords records = _decode(latin1.encode(one.replaceFirst('%%EndSetup', '$raster%%EndSetup'))).records;
    final AiNativeRasters body = AiNativeRasters.decode(records: records, bodyOnly: true);
    check(body.images).length.equals(1);
    final AiNativeRasters edited = body.replacePixels(
      image: body.images.single,
      samples: _samples(body.images.single, colors: List.filled(12, 99)),
    );
    check(edited.images).length.equals(2);
    check(edited.images.first.colorSamples).deepEquals(body.images.single.colorSamples);
    check(edited.images.last.colorSamples).deepEquals(List.filled(12, 99));
  });

  test('edits legacy stencil pixels without inventing alpha operands', () {
    final String original = latin1.decode(_bytes(width: 2, height: 1, components: 1, bits: 1, colors: [0x40], mask: true)).replaceFirst(' 4 4 0 0\n%%BeginData', '\n%%BeginData');
    final AiNativeRasters source = _decode(latin1.encode(original));
    final AiNativeRasters edited = source.replacePixels(
      image: source.images.single,
      samples: _samples(source.images.single, colors: [0x80]),
    );
    final AiNativeRaster image = edited.images.single;
    check(image.extensions).isEmpty();
    check(image.imageMask).isTrue();
    check(image.colorSamples).deepEquals([0x80]);
    check(
      () => source.replacePixels(
        image: source.images.single,
        samples: AiNativeRasterSamples(width: 2, height: 1, bitsPerComponent: 1, components: 1, colorSamples: [0x80], alphaSamples: [0xc0]),
      ),
    ).throws<UnsupportedError>();
    final AiNativeRasters opaque = source.replacePixels(
      image: source.images.single,
      samples: AiNativeRasterSamples(width: 2, height: 1, bitsPerComponent: 1, components: 1, colorSamples: [0x40]),
    );
    check(opaque.images.single.imageMask).isFalse();
  });

  test('renews split identity strings without altering other native entry bytes', () {
    final String original = latin1.decode(_metadata(_bytes())).replaceFirst('(11111111-1111-4111-8111-111111111111)', '(11111111-1111-)\n%_(4111-8111-111111111111)');
    final AiNativeRasters source = _decode(latin1.encode(original));
    final AiNativeRasters edited = source.replacePixels(
      image: source.images.single,
      samples: _samples(source.images.single, colors: List.filled(12, 255)),
    );
    check(edited.images.single.dictionary!['AI24 ImageRawDataUUID']!.text()).isNotNull();
    check(edited.images.single.dictionary!['AI24 ImageRawDataUUID']!.items).length.equals(1);
    check(edited.images.single.dictionary!['AI24 ImageAlphaRawDataUUID']!.text()).equals(source.images.single.dictionary!['AI24 ImageAlphaRawDataUUID']!.text());
  });
}
