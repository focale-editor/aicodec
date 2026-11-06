import 'dart:convert';
import 'dart:typed_data';

import 'package:checks/checks.dart';
import 'package:illustratorkit/illustratorkit.dart';
import 'package:test/test.dart';

/// Authors independent CC placement syntax with optional private preview rows.
Uint8List _bytes({bool private = false, bool preview = true, List<int>? rows, int width = 2, int height = 2, int rowBytes = 8, int bits = 32, int format = 17, bool prefixHeader = false}) {
  final String prefix = private ? '%_' : '';
  return (BytesBuilder(copy: false)
        ..add(
          latin1.encode('''%!PS-Adobe-3.0
%%Creator: Adobe Illustrator
%%Title: Header
%%BoundingBox: 0 0 100 100
%%DocumentFiles:folder/image.png
%%EndComments
%%EndSetup
$prefix%AI5_BeginPlace
$prefix%%FileType: 1
$prefix[ 2 0 0 -3 -90 250 ] 50 60 70 80 4 4 0
$prefix(folder/image.png)`
$prefix%%IncludeFile:folder/image.png
$prefix%AI17_Begin_Content_if_version_gt:24 12
$prefix%AI28_BeginPlacedRelativePath
$prefix(../Links/)
$prefix%AI28_EndPlacedRelativePath
$prefix%AI17_Alternate_Content
$prefix%AI17_End_Versioned_Content
'''),
        )
        ..add(preview ? latin1.encode('$prefix%AI17_Begin_Content_if_version_gt:24 5\n$prefix%AI26_BeginPlacedObjectPreview\n${prefixHeader ? '%_' : ''}$width $height $rowBytes $bits $format ') : [])
        ..add(preview ? rows ?? [255, 255, 0, 0, 128, 0, 255, 0, 0, 0, 0, 255, 255, 255, 255, 255] : [])
        ..add(preview ? latin1.encode('\r\n$prefix%AI26_EndPlacedObjectPreview\n$prefix%AI17_End_Versioned_Content\n') : [])
        ..add(
          latin1.encode('''$prefix~
$prefix%AI5_EndPlace
%_/ArtDictionary :
%_(Picture) /UnicodeString (AIArtName) ,
%_0 /Real (BBAccumRotation) ,
%_1 /Real (Raster Art Original Scale) ,
%_;
${prefix}9 () XW
%%Trailer
%%EOF
'''),
        ))
      .takeBytes();
}

/// Reads native placement snapshots under the caller's resource limits.
AiNativePlacements _decode(List<int> bytes, {AiNativeLimits limits = const AiNativeLimits()}) => AiNativePlacements.decode(
  records: AiNativeRecords.decode(
    program: AiProgram.decode(bytes: bytes, limits: limits),
  ),
);

/// Checks native references, preview boundaries and conversion into embedded art.
void main() {
  test('reads native references and straight ARGB preview pixels without encoding guesses', () {
    final Uint8List bytes = _bytes();
    final AiNativePlacements placements = _decode(bytes);
    final AiNativePlacedObject object = placements.objects.single;
    check(object.pathBytes).deepEquals(latin1.encode('folder/image.png'));
    check(object.relativeDirectoryBytes!).deepEquals(latin1.encode('../Links/'));
    check(object.matrix).deepEquals([2, 0, 0, -3, -90, 250]);
    check(object.bounds).deepEquals([50, 60, 70, 80]);
    check(object.extensions).deepEquals([4, 4, 0]);
    check(object.fileType).equals(1);
    check(object.isPrintable(program: placements.records.program)).isTrue();
    final AiNativeRasterSamples samples = object.preview!.toSamples();
    check(samples.colorSamples).deepEquals([255, 0, 0, 0, 255, 0, 0, 0, 255, 255, 255, 255]);
    check(samples.alphaSamples!).deepEquals([255, 128, 0, 255]);
    check(() => object.preview!.bytes[0] = 0).throws<UnsupportedError>();
    check(() => object.matrix[0] = 0).throws<UnsupportedError>();
    check(placements.records.program.bytes).deepEquals(bytes);
    check((const AiCodec().decode(bytes) as AiPostScriptDocument).dscIssue).isNull();
  });

  test('retains row padding and does not premultiply straight preview colors', () {
    final AiNativePlacedPreview preview = _decode(_bytes(rowBytes: 12, rows: [128, 255, 250, 240, 255, 0, 0, 0, 1, 2, 3, 4, 0, 255, 0, 0, 255, 0, 255, 0, 5, 6, 7, 8])).objects.single.preview!;
    check(preview.rowBytes).equals(12);
    check(preview.toSamples().colorSamples).deepEquals([255, 250, 240, 0, 0, 0, 255, 0, 0, 0, 255, 0]);
    check(preview.toSamples().alphaSamples!).deepEquals([128, 255, 0, 255]);
  });

  test('keeps fake comments and native tokens inside preview rows opaque', () {
    final List<int> rows = latin1.encode('\n%%Title: Forged\n%AI26_EndPlacedObjectPreview\n%_/Dictionary :\n{ ( [ ');
    while (rows.length % 4 != 0) {
      rows.add(0);
    }
    final Uint8List bytes = _bytes(width: rows.length ~/ 4, height: 1, rowBytes: rows.length, rows: rows);
    final AiPostScriptDocument document = const AiCodec().decode(bytes) as AiPostScriptDocument;
    check(document.title).equals('Header');
    check(document.dscIssue).isNull();
    check(_decode(bytes).objects.single.preview!.bytes).deepEquals(rows);
    check(AiPostScript.tokenize(bytes).where((token) => token.kind == .data)).length.equals(1);
  });

  test('preserves private previews before and after native comment projection', () {
    for (final bool prefixHeader in [false, true]) {
      final AiNativePlacements placements = _decode(_bytes(private: true, prefixHeader: prefixHeader));
      final AiNativePlacedObject object = placements.objects.single;
      check(object.instruction.isPrivate).isTrue();
      check(object.isPrintable(program: placements.records.program)).isFalse();
      check(object.preview!.toSamples().alphaSamples!).deepEquals([255, 128, 0, 255]);
      final AiNativeRasters embedded = placements.embed(object: object, samples: object.preview!.toSamples());
      check(embedded.images.single.instruction.isPrivate).isTrue();
      check(embedded.images.single.colorSamples).deepEquals(object.preview!.toSamples().colorSamples);
    }
  });

  test('preserves unknown preview layouts while rejecting guessed color conversion', () {
    for (final Uint8List bytes in [_bytes(bits: 24), _bytes(format: 18), _bytes(rowBytes: 7, rows: List.filled(14, 0))]) {
      final AiNativePlacedPreview preview = _decode(bytes).objects.single.preview!;
      check(preview.toSamples).throws<UnsupportedError>();
      check((const AiCodec().decode(bytes) as AiPostScriptDocument).dscIssue).isNull();
    }
  });

  test('rejects damaged preview counts rather than finding a later closing marker', () {
    final String valid = latin1.decode(_bytes());
    for (final String source in [
      valid.replaceFirst('2 2 8 32 17 ', '2 3 8 32 17 '),
      valid.replaceFirst('2 2 8 32 17 ', '999999999999 2 8 32 17 '),
      valid.replaceFirst('%AI26_EndPlacedObjectPreview', 'junk\n%AI26_EndPlacedObjectPreview'),
    ]) {
      check(() => _decode(latin1.encode(source))).throws<FormatException>();
      final AiPostScriptDocument document = const AiCodec().decode(latin1.encode(source)) as AiPostScriptDocument;
      check(document.dscIssue).isNotNull();
      check(document.title).equals('Header');
      check(const AiCodec().encode(document)).deepEquals(latin1.encode(source));
    }
  });

  test('translates placement only and retains cached rows and all link references', () {
    final AiNativePlacements source = _decode(_bytes());
    final AiNativePlacements moved = source.translate(objects: source.objects, deltaX: 7, deltaY: -9);
    final AiNativePlacedObject object = moved.objects.single;
    check(object.matrix).deepEquals([2, 0, 0, -3, -83, 241]);
    check(object.preview!.bytes).deepEquals(source.objects.single.preview!.bytes);
    check(object.pathBytes).deepEquals(source.objects.single.pathBytes);
    check(object.relativeDirectoryBytes!).deepEquals(source.objects.single.relativeDirectoryBytes!);
    check(latin1.decode(moved.records.program.bytes)).contains('%%BoundingBox: 0 -9 107 100');
    check(identical(source.translate(objects: source.objects, deltaX: 0, deltaY: 0), source)).isTrue();
    check(() => source.translate(objects: moved.objects, deltaX: 1, deltaY: 1)).throws<ArgumentError>();
    check(() => source.translate(objects: source.objects, deltaX: double.infinity, deltaY: 1)).throws<ArgumentError>();
  });

  test('embeds host samples with fixed extent and synchronized native metadata', () {
    final Uint8List bytes = _bytes();
    final AiNativePlacements source = _decode(bytes);
    final AiNativePlacedObject object = source.objects.single;
    final AiNativeRasters embedded = source.embed(object: object, samples: object.preview!.toSamples());
    final AiNativeRaster image = embedded.images.single;
    check(image.matrix).deepEquals([20, 0, 0, 30, 10, 70]);
    check(image.dictionary!['AIArtName']!.text()).equals('Picture');
    check(AiNativePlacements.decode(records: embedded.records).objects).isEmpty();
    check(latin1.decode(embedded.records.program.bytes).contains('DocumentFiles')).isFalse();
    check(latin1.decode(embedded.records.program.bytes).contains('folder/image.png')).isFalse();
    check(latin1.decode(embedded.records.program.bytes).contains('PlacedObjectPreview')).isFalse();
    check(source.records.program.bytes).deepEquals(bytes);
    check(() => source.embed(object: _decode(bytes).objects.single, samples: object.preview!.toSamples())).throws<ArgumentError>();
  });

  test('embeds a reflected and sheared placement at a different sample resolution', () {
    final AiNativePlacements source = _decode(latin1.encode(latin1.decode(_bytes(preview: false)).replaceFirst('[ 2 0 0 -3 -90 250 ]', '[ -2 1 0.5 -3 150 250 ]')));
    final AiNativeRasterSamples samples = AiNativeRasterSamples(width: 4, height: 1, bitsPerComponent: 8, components: 4, colorSamples: List.filled(16, 128));
    final AiNativeRasters embedded = source.embed(object: source.objects.single, samples: samples);
    check(embedded.images.single.matrix).deepEquals([-10, 5, -10, 60, 80, 120]);
    check(embedded.images.single.colorSamples).deepEquals(List.filled(16, 128));
    final List<double> matrix = source.objects.single.rasterMatrix(width: 4, height: 1);
    check(matrix).deepEquals(embedded.images.single.matrix);
    check(() => matrix[0] = 0).throws<UnsupportedError>();
    check(() => source.objects.single.rasterMatrix(width: 0, height: 1)).throws<ArgumentError>();
  });

  test('retains shared file dependencies and removes only the last owned reference', () {
    final String original = latin1.decode(_bytes());
    final String section = original.substring(original.indexOf('%AI5_BeginPlace'), original.indexOf('%%Trailer'));
    final AiNativePlacements source = _decode(latin1.encode(original.replaceFirst('%%Trailer', '$section%%Trailer')));
    final AiNativeRasters first = source.embed(object: source.objects.first, samples: source.objects.first.preview!.toSamples());
    check(latin1.decode(first.records.program.bytes)).contains('%%DocumentFiles:folder/image.png');
    final AiNativePlacements remaining = AiNativePlacements.decode(records: first.records);
    final AiNativeRasters last = remaining.embed(object: remaining.objects.single, samples: remaining.objects.single.preview!.toSamples());
    check(latin1.decode(last.records.program.bytes).contains('DocumentFiles')).isFalse();
    check(last.images).length.equals(2);
    final AiNativePlacements multiple = _decode(latin1.encode(original.replaceFirst('%%DocumentFiles:folder/image.png', '%%DocumentFiles:folder/image.png\n%%+another picture.png')));
    final AiNativeRasters removed = multiple.embed(object: multiple.objects.single, samples: multiple.objects.single.preview!.toSamples());
    check(latin1.decode(removed.records.program.bytes)).contains('%%DocumentFiles:another picture.png');
    for (final bool other in [false, true]) {
      final String trailer = original
          .replaceFirst('%%DocumentFiles:folder/image.png', '%%DocumentFiles: (atend)')
          .replaceFirst('%%Trailer', '%%Trailer\n%%DocumentFiles:folder/image.png${other ? '\n%%+another picture.png' : ''}');
      final AiNativePlacements deferred = _decode(latin1.encode(trailer));
      final AiNativeRasters result = deferred.embed(object: deferred.objects.single, samples: deferred.objects.single.preview!.toSamples());
      check(latin1.decode(result.records.program.bytes).contains('DocumentFiles')).equals(other);
      check(latin1.decode(result.records.program.bytes).contains('(atend)')).equals(other);
    }
  });

  test('rejects unresolved placed types flags links dictionaries and degenerate matrices', () {
    final String original = latin1.decode(_bytes());
    final AiNativeRasterSamples samples = _decode(_bytes()).objects.single.preview!.toSamples();
    for (final String source in [
      original.replaceFirst('%%FileType: 1', '%%FileType: 2'),
      original.replaceFirst('80 4 4 0', '80 4 4 1'),
      original.replaceFirst('%%IncludeFile:folder/image.png', '%%IncludeFile:other.png'),
      original.replaceFirst('(AIArtName)', '(UnknownLinkCache)'),
      original.replaceFirst('%AI28_BeginPlacedRelativePath', '%FuturePlacementState\n%AI28_BeginPlacedRelativePath'),
    ]) {
      final AiNativePlacements unknown = _decode(latin1.encode(source));
      check(() => unknown.embed(object: unknown.objects.single, samples: samples)).throws<UnsupportedError>();
    }
    final AiNativePlacements collapsed = _decode(latin1.encode(original.replaceFirst('[ 2 0 0 -3 -90 250 ]', '[ 0 0 0 -3 -90 250 ]')));
    check(() => collapsed.embed(object: collapsed.objects.single, samples: samples)).throws<FormatException>();
  });

  test('bounds embedded output under the owning native program limit', () {
    final Uint8List bytes = _bytes();
    final AiNativePlacements source = _decode(bytes, limits: AiNativeLimits(maxDecodedBytes: bytes.length));
    final AiNativeRasterSamples samples = AiNativeRasterSamples(width: 100, height: 100, bitsPerComponent: 8, components: 1, colorSamples: List.filled(10000, 0));
    check(() => source.embed(object: source.objects.single, samples: samples)).throws<FormatException>();
    check(source.records.program.bytes).deepEquals(bytes);
  });

  test('rejects mixed private sections and misplaced preview commands', () {
    final String original = latin1.decode(_bytes());
    check(() => _decode(latin1.encode(original.replaceFirst('%AI5_BeginPlace', '%_%AI5_BeginPlace')))).throws<UnsupportedError>();
    check(() => _decode(latin1.encode(original.replaceFirst('%AI26_BeginPlacedObjectPreview', '~\n%AI26_BeginPlacedObjectPreview').replaceFirst('\n~\n%AI5_EndPlace', '\n%AI5_EndPlace'))))
        .throws<FormatException>();
  });

  test('preserves unresolved conditional metadata but rejects its conversion', () {
    final String original = latin1.decode(_bytes());
    for (final String changed in [
      original.replaceFirst('%AI17_Alternate_Content', '%AI17_Alternate_Content\n%AI17_Alternate_Content'),
      original.replaceFirst('%AI17_End_Versioned_Content\n', ''),
      original.replaceFirst('%%FileType: 1\n', '').replaceFirst('\n~', '\n%%FileType: 1\n~'),
    ]) {
      final AiNativePlacements source = _decode(latin1.encode(changed));
      check(() => source.embed(object: source.objects.single, samples: source.objects.single.preview!.toSamples())).throws<UnsupportedError>();
      check(source.records.program.bytes).deepEquals(latin1.encode(changed));
    }
  });

  test('stabilizes the new raster origin after cancelling a nonzero ruler origin', () {
    final String original = latin1.decode(_bytes());
    final String changed = original.replaceFirst('[ 2 0 0 -3 -90 250 ] 50 60 70 80', '[ 0.330188679245283 0 0 -0.330188679245283 -2439.53773584906 2320.82075471698 ] 7885 7795 8685 8643');
    final AiNativePlacements source = _decode(latin1.encode(changed));
    final AiNativeRasters embedded = source.embed(object: source.objects.single, samples: source.objects.single.preview!.toSamples());
    check(embedded.images.single.matrix[4]).equals(164);
    check(embedded.images.single.matrix[5]).equals(-253);
  });
}
