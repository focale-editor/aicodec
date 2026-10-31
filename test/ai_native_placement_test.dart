import 'dart:convert';
import 'dart:typed_data';

import 'package:aikit/aikit.dart';
import 'package:checks/checks.dart';
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

/// Renders the resulting native artwork with explicit drawing bounds.
PdfDocument _render(AiProgram program) => AiNativePdf.render(program: program, bounds: AiBoundingBox(left: 0, bottom: 0, right: 100, top: 100));

/// Stores a linked program in shared native blocks across two PDF page owners.
AiPdfDocument _linkedDocument(AiProgram program) {
  final PdfDocument document = PdfDocument.fromPages(pages: [for (int index = 0; index < 2; index++) PdfPageSource(width: 100, height: 100, content: [])]);
  const PdfReference block = PdfReference(objectNumber: 90);
  final PdfDictionary pieces = PdfDictionary(
    values: {
      'Illustrator': PdfDictionary(
        values: {
          'Private': PdfDictionary(values: {'AIPrivateData1': block}),
        },
      ),
    },
  );
  return AiPdfDocument(
    pdf: document.copyWith(
      objects: {
        ...document.objects,
        block: PdfStream(
          dictionary: PdfDictionary(),
          data: AiNativeData.encodeEnvelope(program.bytes, compression: .zstandard),
        ),
        for (final PdfPage page in document.pages) page.reference!: page.dictionary.copyWith(values: {'PieceInfo': pieces}),
      },
    ),
  );
}

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
    check(() => _render(placements.records.program)).throws<UnsupportedError>();
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
    final PdfDocument pdf = _render(embedded.records.program);
    final PdfOperation matrix = PdfProgram.fromPage(document: pdf, pageIndex: 0).operations.lastWhere((operation) => operation.operator == 'cm');
    check(matrix.operands.cast<PdfNumber>().map((value) => value.value).toList()).deepEquals([40, 0, 0, 60, 10, 10]);
    final List<PdfStream> images = pdf.objects.values.whereType<PdfStream>().where((stream) => stream.dictionary.name('Subtype') == 'Image').toList();
    check(images).length.equals(2);
    check(pdf.decodeStream(images.first)).deepEquals([255, 128, 0, 255]);
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
    final PdfDocument pdf = _render(embedded.records.program);
    final List<num> matrix = PdfProgram.fromPage(
      document: pdf,
      pageIndex: 0,
    ).operations.lastWhere((operation) => operation.operator == 'cm').operands.cast<PdfNumber>().map((value) => value.value).toList();
    check(embedded.images.single.matrix[4]).equals(164);
    check(embedded.images.single.matrix[5]).equals(-253);
    check(matrix[3]).isCloseTo(280, 1e-10);
    check(matrix[4]).equals(164);
    check(matrix[5]).equals(-533);
    check(matrix[0]).isCloseTo(264.1509433962264, 1e-10);
  });

  test('renders explicit linked samples without changing source links or previews', () {
    final AiNativePlacements source = _decode(_bytes());
    final AiNativeRasterSamples samples = source.objects.single.preview!.toSamples();
    int calls = 0;
    final PdfDocument linked = AiNativePdf.render(
      program: source.records.program,
      bounds: AiBoundingBox(left: 0, bottom: 0, right: 100, top: 100),
      resolvePlacement: (object) {
        calls++;
        check(object.pathBytes).deepEquals(source.objects.single.pathBytes);
        check(object.relativeDirectoryBytes!).deepEquals(source.objects.single.relativeDirectoryBytes!);
        return samples;
      },
    );
    final AiNativeRasters embedded = source.embed(object: source.objects.single, samples: samples);
    check(const PdfEncoder().convert(linked)).deepEquals(const PdfEncoder().convert(_render(embedded.records.program)));
    check(calls).equals(1);
    check(source.records.program.bytes).deepEquals(_bytes());
  });

  test('requires explicit resolution and propagates host failures without preview fallback', () {
    final AiNativePlacements source = _decode(_bytes());
    final AiBoundingBox bounds = AiBoundingBox(left: 0, bottom: 0, right: 100, top: 100);
    check(() => AiNativePdf.render(program: source.records.program, bounds: bounds)).throws<UnsupportedError>();
    check(() => AiNativePdf.render(program: source.records.program, bounds: bounds, resolvePlacement: (object) => null)).throws<UnsupportedError>();
    final StateError failure = StateError('Host could not decode this file.');
    check(() => AiNativePdf.render(program: source.records.program, bounds: bounds, resolvePlacement: (object) => throw failure)).throws<StateError>().equals(failure);
    final AiNativePlacements unknownPreview = _decode(_bytes(format: 18));
    check(() => unknownPreview.objects.single.preview!.toSamples()).throws<UnsupportedError>();
    AiNativePdf.render(program: unknownPreview.records.program, bounds: bounds, resolvePlacement: (object) => source.objects.single.preview!.toSamples());
  });

  test('qualifies native semantics before asking the host for pixels', () {
    final String original = latin1.decode(_bytes());
    for (final String changed in [original.replaceFirst('%%FileType: 1', '%%FileType: 2'), original.replaceFirst('(AIArtName)', '(OpaqueAppearance)')]) {
      int calls = 0;
      final AiProgram program = AiProgram.decode(bytes: latin1.encode(changed));
      check(
        () => AiNativePdf.render(
          program: program,
          bounds: AiBoundingBox(left: 0, bottom: 0, right: 100, top: 100),
          resolvePlacement: (object) {
            calls++;
            return object.preview!.toSamples();
          },
        ),
      ).throws<UnsupportedError>();
      check(calls).equals(0);
    }
  });

  test('does not resolve private authoring placements or paint their previews', () {
    final AiNativePlacements source = _decode(latin1.encode(latin1.decode(_bytes(private: true)).replaceFirst('%%FileType: 1', '%%FileType: 2').replaceFirst('(AIArtName)', '(OpaquePrivateState)')));
    int calls = 0;
    final PdfDocument pdf = AiNativePdf.render(
      program: source.records.program,
      bounds: AiBoundingBox(left: 0, bottom: 0, right: 100, top: 100),
      resolvePlacement: (object) {
        calls++;
        return object.preview!.toSamples();
      },
    );
    check(calls).equals(0);
    check(pdf.objects.values.whereType<PdfStream>().where((stream) => stream.dictionary.name('Subtype') == 'Image')).isEmpty();
  });

  test('saves current linked appearances on every PDF page while preserving native bytes', () {
    final AiNativePlacements initial = _decode(_bytes());
    final AiNativePlacements moved = initial.translate(objects: initial.objects, deltaX: 3, deltaY: -7);
    final AiPdfDocument original = _linkedDocument(initial.records.program);
    final AiNativeSource source = AiNativeData.extract(original).single;
    int calls = 0;
    final AiPdfDocument saved = AiNativePdf.save(
      source: source,
      program: moved.records.program,
      pageBounds: [for (int index = 0; index < 2; index++) AiBoundingBox(left: 0, bottom: 0, right: 100, top: 100)],
      resolvePlacement: (object) {
        calls++;
        check(object.matrix).deepEquals(moved.objects.single.matrix);
        return object.preview!.toSamples();
      },
    );
    check(calls).equals(1);
    check(AiNativeData.extract(saved).single.bytes).deepEquals(moved.records.program.bytes);
    check(
      AiNativePlacements.decode(
        records: AiNativeRecords.decode(program: AiProgram.decode(bytes: AiNativeData.extract(saved).single.bytes)),
      ).objects.single.pathBytes,
    ).deepEquals(initial.objects.single.pathBytes);
    check(AiNativeData.extract(original).single.bytes).deepEquals(initial.records.program.bytes);
    for (int index = 0; index < 2; index++) {
      check(PdfProgram.fromPage(document: saved.pdf, pageIndex: index).operations.where((operation) => operation.operator == 'Do')).length.equals(1);
    }
  });

  test('charges all linked sample planes against the aggregate PDF byte limit', () {
    final String original = latin1.decode(_bytes());
    final String section = original.substring(original.indexOf('%AI5_BeginPlace'), original.indexOf('%%Trailer'));
    final AiProgram program = AiProgram.decode(bytes: latin1.encode(original.replaceFirst('%%Trailer', '$section%%Trailer')));
    final AiNativeRasterSamples samples = AiNativeRasterSamples(width: 8, height: 8, bitsPerComponent: 8, components: 3, colorSamples: List.filled(192, 0), alphaSamples: List.filled(64, 255));
    check(
      () => AiNativePdf.render(program: program, bounds: AiBoundingBox(left: 0, bottom: 0, right: 100, top: 100), resolvePlacement: (object) => samples, limits: const PdfLimits(maxDecodedBytes: 300)),
    ).throws<FormatException>();
  });

  test('preserves clipping and object opacity when a link uses explicit samples', () {
    final String original = latin1.decode(_bytes());
    final String changed = original.replaceFirst('%AI5_BeginPlace', 'q 10 10 m 45 10 L 45 80 L 10 80 L h W N 0 0.5 0 0 0 Xy\n%AI5_BeginPlace').replaceFirst('%%Trailer', 'Q\n%%Trailer');
    final AiNativePlacements source = _decode(latin1.encode(changed));
    final AiNativeRasterSamples samples = source.objects.single.preview!.toSamples();
    final PdfDocument linked = AiNativePdf.render(program: source.records.program, bounds: AiBoundingBox(left: 0, bottom: 0, right: 100, top: 100), resolvePlacement: (object) => samples);
    final AiNativeRasters embedded = source.embed(object: source.objects.single, samples: samples);
    check(const PdfEncoder().convert(linked)).deepEquals(const PdfEncoder().convert(_render(embedded.records.program)));
    final PdfDictionary opacity = linked.objects.values.whereType<PdfDictionary>().singleWhere((value) => value.name('Type') == 'ExtGState');
    check((opacity['ca']! as PdfNumber).value).equals(0.5);
  });

  test('checks hidden links without painting and rejects links interrupting paths', () {
    final String original = latin1.decode(_bytes());
    final AiNativeRasterSamples samples = _decode(_bytes()).objects.single.preview!.toSamples();
    final AiBoundingBox bounds = AiBoundingBox(left: 0, bottom: 0, right: 100, top: 100);
    final String hidden = original.replaceFirst('%AI5_BeginPlace', '0 1 1 1 0 0 0 0 0 0 Lb (Hidden) Ln\n%AI5_BeginPlace').replaceFirst('%%Trailer', 'LB\n%%Trailer');
    final AiProgram program = AiProgram.decode(bytes: latin1.encode(hidden));
    check(() => AiNativePdf.render(program: program, bounds: bounds)).throws<UnsupportedError>();
    int calls = 0;
    final PdfDocument pdf = AiNativePdf.render(
      program: program,
      bounds: bounds,
      resolvePlacement: (object) {
        calls++;
        return samples;
      },
    );
    check(calls).equals(1);
    check(pdf.objects.values.whereType<PdfStream>().where((stream) => stream.dictionary.name('Subtype') == 'Image')).isEmpty();
    for (final (String, String) scope in [('0 0 m', '1 1 L S'), ('*u', '0 0 m 1 1 L S *U')]) {
      final AiProgram interrupted = AiProgram.decode(
        bytes: latin1.encode(original.replaceFirst('%AI5_BeginPlace', '${scope.$1}\n%AI5_BeginPlace').replaceFirst('%%Trailer', '${scope.$2}\n%%Trailer')),
      );
      PdfDocument render() => AiNativePdf.render(
        program: interrupted,
        bounds: bounds,
        resolvePlacement: (object) {
          calls++;
          return samples;
        },
      );
      if (scope.$1 == '0 0 m') {
        check(render).throws<FormatException>();
      } else {
        check(render).throws<UnsupportedError>();
      }
    }
    check(calls).equals(1);
  });

  test('resolves each instance independently even when file paths are shared', () {
    final String original = latin1.decode(_bytes());
    final String section = original.substring(original.indexOf('%AI5_BeginPlace'), original.indexOf('%%Trailer')).replaceFirst('-90 250', '-50 250');
    final AiProgram program = AiProgram.decode(bytes: latin1.encode(original.replaceFirst('%%Trailer', '$section%%Trailer')));
    final List<double> positions = [];
    final PdfDocument pdf = AiNativePdf.render(
      program: program,
      bounds: AiBoundingBox(left: 0, bottom: 0, right: 100, top: 100),
      resolvePlacement: (object) {
        positions.add(object.matrix[4]);
        return AiNativeRasterSamples(width: 1, height: 1, bitsPerComponent: 8, components: 1, colorSamples: [if (positions.length == 1) 32 else 224]);
      },
    );
    check(positions).deepEquals([-90, -50]);
    final List<PdfStream> images = pdf.objects.values.whereType<PdfStream>().where((stream) => stream.dictionary.name('Subtype') == 'Image').toList();
    check(images.map(pdf.decodeStream).toList()).deepEquals([
      [32],
      [224],
    ]);
  });
}
