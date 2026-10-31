import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:aikit/aikit.dart';
import 'package:checks/checks.dart';
import 'package:test/test.dart';

/// Authors two independently specified RGB pixels and an optional object record.
Uint8List _raster({String metadata = '', bool private = false, bool setup = false}) {
  final String prefix = private ? '%_' : '';
  return (BytesBuilder()
        ..add(
          latin1.encode('''%!PS-Adobe-3.0
%%Creator: Adobe Illustrator
%%BoundingBox: 0 0 100 100
%%HiResBoundingBox: 0.0 0.0 100.0 100.0
%%PageBoundingBox: 0 0 100 100
%%BeginSetup
${setup ? '' : '%%EndSetup'}
$prefix%AI5_BeginRaster
$prefix(source.png) 0 XG
$prefix/DeviceRGB XN
$prefix[2e0 0 0 3.0 10 20] 2 1 0 Xh
$prefix[2e0 0 0 3.0 10 20] 0 0 2 1 2 1 8 3 0 1 1 0 4 4 0 0
$prefix%%BeginData: 9 Binary Bytes
XI
'''),
        )
        ..add([255, 0, 0, 0, 255, 0])
        ..add(
          latin1.encode('''
$prefix%%EndData
${prefix}XH
$prefix%AI5_EndRaster
${prefix}N
$metadata
${setup ? '%%EndSetup' : ''}
%%Trailer
%%EOF
'''),
        ))
      .takeBytes();
}

/// Adds independently encoded metadata, including stable image/object identities.
String _dictionary({String angle = '%_(0.000000) /String (BBAccumRotation) ,', String extras = '', bool private = true}) {
  final String source =
      '''%_/ArtDictionary :
$angle
%_(stable-object) /String (AI10_ArtUID) ,
%_(Picture) /String (AIArtName) ,
%_0.24 /Real (Raster Art Original Scale) ,
$extras
%_;''';
  return private ? source : source.replaceAll('%_', '');
}

/// Provides a linked rectangle whose local origin is not the image origin.
AiNativePlacements _linked({String? metadata}) => AiNativePlacements.decode(
  records: AiNativeRecords.decode(
    program: AiProgram.decode(
      bytes: latin1.encode('''%!PS-Adobe-3.0
%%Creator: Adobe Illustrator
%%BoundingBox: 0 0 100 100
%%DocumentFiles:picture.png
%%EndSetup
%AI5_BeginPlace
%%FileType: 1
[2e0 0 0 -3.0 -90 250] 50 60 70 80 4 4 0 (picture.png)`
%%IncludeFile:picture.png
~
%AI5_EndPlace
${metadata ?? _dictionary()}
9 () XW
%%Trailer
%%EOF
'''),
    ),
  ),
);

/// Reads source-owned embedded image handles under explicit output ceilings.
AiNativeRasters _decode(List<int> bytes, {AiNativeLimits limits = const AiNativeLimits()}) => AiNativeRasters.decode(
  records: AiNativeRecords.decode(
    program: AiProgram.decode(bytes: bytes, limits: limits),
  ),
);

/// Replaces one source image using an independently specified target matrix.
AiNativeRasters _set(AiNativeRasters source, List<double> matrix, {double? angle}) => source.setPlacement(image: source.images.single, matrix: matrix, rotationRadians: angle);

/// Recovers scalar frame rotation independently of its preserved source type.
double? _angle(AiNativeContainer? dictionary) {
  final AiNativeEntry? entry = dictionary?['BBAccumRotation'];
  return entry == null ? null : entry.number ?? double.parse(entry.text()!);
}

/// Exercises source geometry, frame metadata and atomic edit rejection.
void main() {
  test('changes both raster matrices while retaining samples and stable identities', () {
    final AiNativeRasters original = _decode(_raster(metadata: _dictionary(extras: '%_(11111111-1111-4111-8111-111111111111) /String (AI24 ImageRawDataUUID) ,')));
    const List<double> matrix = [0, 5, -7, 0, -12, 108];
    final AiNativeRasters changed = _set(original, matrix, angle: pi / 2);
    final AiNativeRaster image = changed.images.single;
    check(image.matrix).deepEquals(matrix);
    check(image.commands.singleWhere((command) => command.operator == 'Xh').operands.skip(1).take(6).map((token) => token.number).toList()).deepEquals(matrix);
    check(image.colorSamples).deepEquals(original.images.single.colorSamples);
    check(image.declaration.lexeme).equals(original.images.single.declaration.lexeme);
    check(image.dictionary!['AI24 ImageRawDataUUID']!.text()).equals('11111111-1111-4111-8111-111111111111');
    check(image.dictionary!['AI10_ArtUID']!.text()).equals('stable-object');
    check(image.dictionary!['Raster Art Original Scale']!.number).equals(0.24);
    check(image.commands.first.operands.map((token) => token.lexeme).toList()).deepEquals(['(source.png)', '0']);
    check(_angle(image.dictionary)).equals(1.570796);
    check(image.frameRotationRadians).equals(1.570796);
    final String bytes = latin1.decode(changed.records.program.bytes);
    check(bytes).contains('%%BoundingBox: -12 0 100 118');
    final AiBoundingBox precise = AiBoundingBox.parse(value: RegExp(r'%%HiResBoundingBox:\s*([^\r\n]+)').firstMatch(bytes)![1]!);
    check([precise.left, precise.bottom, precise.right, precise.top]).deepEquals([-12, 0, 100, 118]);
    check(bytes).contains('%%PageBoundingBox: -12 0 100 118');
    check(original.images.single.matrix).deepEquals([2, 0, 0, 3, 10, 20]);
  });

  test('sets linked geometry independently of resource paths and local coordinates', () {
    final AiNativePlacements original = _linked();
    final AiNativePlacedObject object = original.objects.single;
    const List<double> matrix = [-2, 1, 0.5, -3, 7, 11];
    final AiNativePlacements changed = original.setPlacement(object: object, matrix: matrix, rotationRadians: -0.25);
    final AiNativePlacedObject edited = changed.objects.single;
    check(edited.matrix).deepEquals(matrix);
    check(edited.bounds).deepEquals(object.bounds);
    check(edited.pathBytes).deepEquals(object.pathBytes);
    check(_angle(edited.dictionary)).equals(-0.25);
    check(edited.frameRotationRadians).equals(-0.25);
    check(latin1.decode(changed.records.program.bytes)).contains('%%BoundingBox: -103 -179 100 100');
    check(latin1.decode(changed.records.program.bytes)).contains('%%DocumentFiles:picture.png');
    check(edited.rasterMatrix(width: 2, height: 2)).deepEquals([-20, 10, -5, 30, -63, -119]);
  });

  test('supports reflection, shear, nonuniform scaling and reversed image rows', () {
    final AiNativeRasters original = _decode(_raster());
    for (final List<double> matrix in <List<double>>[
      [-2, 0, 0, 3, 30, 40],
      [2, 0.5, 1, 3, 10, 20],
      [4, 0, 0, 1.5, 10, 20],
      [2, 0, 0, -3, 10, 20],
    ]) {
      final AiNativeRasters changed = _set(original, matrix);
      check(changed.images.single.matrix).deepEquals(matrix);
      check(changed.images.single.colorSamples).deepEquals(original.images.single.colorSamples);
      check(changed.images.single.dictionary).isNull();
      check(changed.images.single.frameRotationRadians).isNull();
      final PdfDocument pdf = AiNativePdf.render(program: changed.records.program, bounds: AiBoundingBox(left: 0, bottom: 0, right: 100, top: 100));
      check(pdf.objects.values.whereType<PdfStream>().where((stream) => stream.dictionary.name('Subtype') == 'Image').length).equals(1);
    }
  });

  test('adds frame metadata without changing private/public representation or N boundaries', () {
    for (final bool private in [false, true]) {
      for (final String dictionary in ['', _dictionary(angle: '', private: private)]) {
        final AiNativeRasters original = _decode(_raster(metadata: dictionary, private: private));
        final AiNativeRasters changed = _set(original, [3, 0, 0, 4, 15, 25], angle: -pi);
        check(_angle(changed.images.single.dictionary)).equals(-3.141593);
        check(changed.images.single.instruction.isPrivate).equals(private);
        check(changed.images.single.colorSamples).deepEquals(original.images.single.colorSamples);
        check(latin1.decode(changed.records.program.bytes)).contains(private ? '%_N' : '\nN');
      }
    }
  });

  test('preserves no-op syntax and supports split strings, UnicodeString and Real angles', () {
    for (final String angle in [
      '%_(0.) (000000) /String (BBAccumRotation) ,',
      '%_<302E303030303030> /UnicodeString (BBAccumRotation) ,',
      '%_0e0 /Real (BBAccumRotation) ,',
    ]) {
      final AiNativeRasters original = _decode(_raster(metadata: _dictionary(angle: angle)));
      check(_set(original, original.images.single.matrix, angle: 0)).identicalTo(original);
      final AiNativeRasters changed = _set(original, original.images.single.matrix, angle: 0.12345678);
      check(_angle(changed.images.single.dictionary)).equals(0.123457);
      check(changed.images.single.dictionary!['BBAccumRotation']!.type).equals(original.images.single.dictionary!['BBAccumRotation']!.type);
      check(changed.images.single.matrix).deepEquals(original.images.single.matrix);
      check(latin1.decode(changed.records.program.bytes)).contains('[2e0 0 0 3.0 10 20]');
    }
    final AiNativeRasters absent = _decode(_raster());
    check(_set(absent, absent.images.single.matrix)).identicalTo(absent);
    final AiNativeRasters precise = _decode(_raster(metadata: _dictionary(angle: '%_(0.12345678) /String (BBAccumRotation) ,')));
    check(_set(precise, precise.images.single.matrix, angle: precise.images.single.frameRotationRadians)).identicalTo(precise);
  });

  test('does not expand drawing bounds for setup resources or private authoring images', () {
    for (final AiNativeRasters original in [_decode(_raster(setup: true)), _decode(_raster(private: true))]) {
      final AiNativeRasters changed = _set(original, [2, 0, 0, 3, 1000, 2000]);
      check(latin1.decode(changed.records.program.bytes)).contains('%%BoundingBox: 0 0 100 100');
    }
  });

  test('rejects foreign handles and invalid, singular or overflowing placement before mutation', () {
    final AiNativeRasters original = _decode(_raster());
    final AiNativeRasters foreign = _decode(_raster());
    check(() => original.setPlacement(image: foreign.images.single, matrix: [1, 0, 0, 1, 0, 0], rotationRadians: null)).throws<ArgumentError>();
    for (final List<double> matrix in <List<double>>[
      [1, 0, 0, 1, 0],
      [1, 2, 2, 4, 0, 0],
      [double.nan, 0, 0, 1, 0, 0],
      [1, 0, 0, 1, double.infinity, 0],
      [1e-200, 0, 0, 1e-200, 0, 0],
      [9007199254740991, 0, 0, 1, 0, 0],
      [1e-100, 0, 0, 1e-100, 10, 20],
    ]) {
      check(() => _set(original, matrix)).throws<ArgumentError>();
    }
    for (final double angle in [double.nan, double.infinity, 7]) {
      check(() => _set(original, original.images.single.matrix, angle: angle)).throws<ArgumentError>();
    }
    check(original.records.program.bytes).deepEquals(_raster());
  });

  test('requires explicit frame-angle policy and rejects unknown or duplicate metadata', () {
    final AiNativeRasters known = _decode(_raster(metadata: _dictionary()));
    check(() => _set(known, [3, 0, 0, 4, 0, 0])).throws<ArgumentError>();
    for (final String metadata in [
      _dictionary(extras: '%_1 /Bool (AI9 Fuzzy Mask) ,'),
      _dictionary(extras: '%_1 /Real (BBAccumShear) ,'),
      _dictionary(angle: '%_(unknown) /String (BBAccumRotation) ,'),
      _dictionary(angle: '%_1 2 /RealPoint (BBAccumRotation) ,'),
      _dictionary().replaceFirst('0.24 /Real', '-1 /Real'),
    ]) {
      final AiNativeRasters original = _decode(_raster(metadata: metadata));
      check(() => _set(original, [3, 0, 0, 4, 0, 0], angle: 0)).throws<UnsupportedError>();
    }
    check(() => _decode(_raster(metadata: _dictionary(extras: '%_1 /Real (BBAccumRotation) ,')))).throws<FormatException>();
    final AiNativePlacements linked = _linked(metadata: _dictionary(extras: '%_1 /Real (unknown-cache) ,'));
    check(() => linked.setPlacement(object: linked.objects.single, matrix: [1, 0, 0, 1, 0, 0], rotationRadians: 0)).throws<UnsupportedError>();
  });

  test('bounds the final program and updates deferred DSC without nested document changes', () {
    final Uint8List bytes = _raster();
    final AiNativeRasters limited = _decode(bytes, limits: AiNativeLimits(maxDecodedBytes: bytes.length));
    check(() => _set(limited, [3, 0, 0, 4, 15, 25], angle: 0.5)).throws<FormatException>();
    final String source = latin1.decode(bytes).replaceFirst('%%BoundingBox: 0 0 100 100', '%%BoundingBox: (atend)').replaceFirst('%%Trailer', '''%%BeginDocument: nested.eps
%%BoundingBox: 1 2 3 4
%%EndDocument
{ % nested procedure
%%BoundingBox: 5 6 7 8
} pop
%%Trailer
%%BoundingBox: 0 0 100 100''');
    final AiNativeRasters changed = _set(_decode(latin1.encode(source)), [2, 0, 0, 3, -0.5, 102.25]);
    final String result = latin1.decode(changed.records.program.bytes);
    check(result).contains('%%BoundingBox: (atend)');
    check(result).contains('%%BoundingBox: -1 0 100 103');
    check(result).contains('%%BoundingBox: 1 2 3 4');
    check(result).contains('%%BoundingBox: 5 6 7 8');
  });
}
