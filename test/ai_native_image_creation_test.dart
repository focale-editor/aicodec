import 'dart:convert';

import 'package:checks/checks.dart';
import 'package:illustratorkit/illustratorkit.dart';
import 'package:test/test.dart';

import 'ai_native_document_creation_test.dart';

/// Supplies distinct straight-alpha RGB pixels without image decoding.
AiNativeRasterSamples createdImageSamples() => AiNativeRasterSamples(
  width: 2,
  height: 1,
  bitsPerComponent: 8,
  components: 3,
  colorSamples: [255, 0, 0, 0, 255, 0],
  alphaSamples: [255, 128],
);

/// Creates an identified embedded image with a nontrivial affine placement.
AiNativeRasterDefinition createdImageDefinition({String id = 'image_1', double opacity = 0.5}) => AiNativeRasterDefinition(
  samples: createdImageSamples(),
  matrix: [10, 2, 3, 20, 5, 60],
  attributes: AiNativeImageAttributes(opacity: opacity, nameBytes: latin1.encode('Picture (red)'), identifierBytes: latin1.encode(id)),
);

/// Creates a portable native link with explicit preview and relative directory.
AiNativePlacementDefinition createdLinkDefinition({String path = 'Links/picture (1).png'}) => AiNativePlacementDefinition(
  pathBytes: latin1.encode(path),
  relativeDirectoryBytes: latin1.encode('../Links/'),
  matrix: [2, 0, 0, -3, 10, 60],
  bounds: [0, 0, 20, 10],
  preview: createdImageSamples(),
);

/// Decodes one drawing from a complete new source or explicitly replaced bytes.
AiNativeDrawing _drawing({bool blank = true, List<int>? bytes, AiNativeLimits limits = const AiNativeLimits()}) => AiNativeDrawing.decode(
  records: bytes == null
      ? newDocumentRecords(blank: blank, limits: limits)
      : AiNativeRecords.decode(
          program: AiProgram.decode(bytes: bytes, limits: limits),
        ),
);

/// Extracts one byte-exact source-backed owner for preservation assertions.
List<int> _slice(AiNativeRecords records, AiNativeItem item) => records.program.bytes.sublist(item.start, item.end);

/// Authors matching host PDF images independently of native serialization.
PdfDocument createdImagePdf() {
  final PdfEditor host = PdfEditor(document: newDocumentPdf(blank: true));
  final AiNativeRasterSamples samples = createdImageSamples();
  final PdfReference alpha = host.addObject(
    value: PdfStream(
      dictionary: PdfDictionary(
        values: {
          'Type': PdfName(value: 'XObject'),
          'Subtype': PdfName(value: 'Image'),
          'Width': PdfNumber(value: 2),
          'Height': PdfNumber(value: 1),
          'BitsPerComponent': PdfNumber(value: 8),
          'ColorSpace': PdfName(value: 'DeviceGray'),
        },
      ),
      data: samples.alphaSamples!,
    ),
  );
  final PdfReference image = host.addObject(
    value: PdfStream(
      dictionary: PdfDictionary(
        values: {
          'Type': PdfName(value: 'XObject'),
          'Subtype': PdfName(value: 'Image'),
          'Width': PdfNumber(value: 2),
          'Height': PdfNumber(value: 1),
          'BitsPerComponent': PdfNumber(value: 8),
          'ColorSpace': PdfName(value: 'DeviceRGB'),
          'SMask': alpha,
        },
      ),
      data: samples.colorSamples,
    ),
  );
  final String name = host.setPageResource(pageIndex: 0, category: 'XObject', prefix: 'Image', value: image);
  host.setPageContent(pageIndex: 0, bytes: latin1.encode('q 20 0 0 20 10 60 cm /$name Do Q\nq 20 0 0 20 40 60 cm /$name Do Q'));
  return host.document;
}

/// Creates two matching native owners, one embedded and one externally linked.
AiNativeDrawing createdImageDocument() {
  AiNativeDrawing drawing = _drawing();
  drawing = drawing.createRaster(
    definition: AiNativeRasterDefinition(
      samples: createdImageSamples(),
      matrix: [10, 0, 0, 20, 0, 60],
      attributes: AiNativeImageAttributes(identifierBytes: latin1.encode('embedded')),
    ),
    layer: drawing.records.program.layers.single,
  );
  return drawing.createPlacement(
    definition: AiNativePlacementDefinition(
      pathBytes: latin1.encode('Links/picture (1).png'),
      relativeDirectoryBytes: latin1.encode('../Links/'),
      matrix: [10, 0, 0, -20, 30, 60],
      bounds: [0, 0, 2, 1],
      preview: createdImageSamples(),
      attributes: AiNativeImageAttributes(identifierBytes: latin1.encode('linked')),
    ),
    layer: drawing.records.program.layers.single,
  );
}

/// Checks creation, state isolation, dependency maintenance and bounded rejection.
void main() {
  test('validates owned image framing and metadata without mutating samples', () {
    final AiNativeDrawing original = _drawing();
    final AiNativeDrawing drawing = original.createRaster(definition: createdImageDefinition(), layer: original.records.program.layers.single);
    final AiNativeRasters rasters = AiNativeRasters.decode(records: drawing.records);
    rasters.validateSourceLayout(image: rasters.images.single);
    check(() => rasters.validateSourceLayout(image: AiNativeRasters.decode(records: drawing.records).images.single)).throws<ArgumentError>();
    final String source = latin1.decode(drawing.records.program.bytes);
    final AiNativeEntry name = rasters.images.single.dictionary!['AIArtName']!;
    for (final String changed in [
      source.replaceFirst('%AI5_BeginRaster', '%AI5_BeginRaster\n%AI99_UnknownRasterCache'),
      source.replaceFirst('(AI24 ImageRawDataUUID)', '(UnknownSampleCache)'),
      source.replaceRange(name.items.first.start, name.typeToken!.end, '1 /Real'),
    ]) {
      check(changed).not((value) => value.equals(source));
      final AiNativeRasters unsupported = AiNativeRasters.decode(
        records: AiNativeRecords.decode(program: AiProgram.decode(bytes: latin1.encode(changed))),
      );
      check(() => unsupported.validateSourceLayout(image: unsupported.images.single)).throws<UnsupportedError>();
    }
    check(latin1.decode(rasters.records.program.bytes)).equals(source);
  });

  test('edits ordinary contours while retaining complete qualified image neighbors', () {
    AiNativeDrawing drawing = _drawing(blank: false);
    drawing = drawing.createRaster(definition: createdImageDefinition(), layer: drawing.records.program.layers.first);
    drawing = drawing.createPath(definition: newDocumentPath(2), layer: drawing.records.program.layers.first);
    final AiNativeRaster image = AiNativeRasters.decode(records: drawing.records).images.single;
    final List<int> retained = drawing.records.program.bytes.sublist(image.start, image.dictionary!.end);
    final AiNativePath selected = drawing.paths.last;
    final AiNativeDrawing changed = drawing.editPaths(
      edits: [
        AiNativePathEdit(
          path: selected,
          segments: [
            for (final AiPathSegment segment in selected.segments)
              AiPathSegment(operator: segment.operator, coordinates: [for (final (int index, double value) in segment.coordinates.indexed) value + (index.isEven ? 5 : 0)]),
          ],
        ),
      ],
      bounds: AiBoundingBox(left: 0, bottom: -100, right: 300, top: 100),
    );
    final AiNativeRaster after = AiNativeRasters.decode(records: changed.records).images.single;
    check(changed.records.program.bytes.sublist(after.start, after.dictionary!.end)).deepEquals(retained);
    final String bad = latin1.decode(drawing.records.program.bytes).replaceFirst('%AI5_BeginRaster', '%AI5_BeginRaster\n%AI99_UnknownRasterCache');
    final AiNativeDrawing unsupported = AiNativeDrawing.decode(
      records: AiNativeRecords.decode(program: AiProgram.decode(bytes: latin1.encode(bad))),
    );
    check(() => unsupported.pathTopology(path: unsupported.paths.last)).throws<UnsupportedError>();
  });

  test('creates editable embedded pixels in a blank layer with fresh identities', () {
    final AiNativeDrawing original = _drawing();
    final AiNativeDrawing changed = original.createRaster(definition: createdImageDefinition(), layer: original.records.program.layers.single);
    final AiNativeRaster image = AiNativeRasters.decode(records: changed.records).images.single;
    image.validateProcessLayout();
    check(image.colorSamples).deepEquals(createdImageSamples().colorSamples);
    check(image.alphaSamples!).deepEquals([255, 128]);
    check(image.matrix).deepEquals([10, 2, 3, 20, 5, 60]);
    check(image.dictionary!['AIArtName']!.text()).equals('Picture (red)');
    check(image.dictionary!['AI10_ArtUID']!.container!.entries.single.text()).equals('image_1');
    check(image.dictionary!['AI24 ImageRawDataUUID']!.text()).isNotNull();
    check(image.dictionary!['AI24 ImageAlphaRawDataUUID']!.text()).not((value) => value.equals(image.dictionary!['AI24 ImageRawDataUUID']!.text()));
    check(AiNativeRasters.decode(records: original.records).images).isEmpty();
    final AiNativeRasters edited = AiNativeRasters.decode(records: changed.records);
    final AiNativeRasters moved = edited.setPlacement(image: edited.images.single, matrix: [1, 0, 0, 1, 40, 50], rotationRadians: 0);
    check(moved.images.single.colorSamples).deepEquals(image.colorSamples);
    check(moved.images.single.dictionary!['AI24 ImageRawDataUUID']!.text()).equals(image.dictionary!['AI24 ImageRawDataUUID']!.text());
  });

  test('inserts repeated images and links while retaining existing path bytes', () {
    AiNativeDrawing drawing = _drawing(blank: false);
    final List<List<int>> paths = drawing.paths.map((path) => _slice(drawing.records, path)).toList();
    drawing = drawing.createRaster(definition: createdImageDefinition(), layer: drawing.records.program.layers.first);
    drawing = drawing.createPlacement(definition: createdLinkDefinition(), layer: drawing.records.program.layers.first);
    drawing = drawing.createRaster(
      definition: createdImageDefinition(id: 'image_2'),
      layer: drawing.records.program.layers.first,
    );
    check(drawing.paths.map((path) => _slice(drawing.records, path)).toList()).deepEquals(paths);
    final List<AiNativeRaster> images = AiNativeRasters.decode(records: drawing.records).images;
    final AiNativePlacedObject link = AiNativePlacements.decode(records: drawing.records).objects.single;
    check(images.length).equals(2);
    check(images.first.end < link.start && link.end < images.last.start).isTrue();
    check(images.first.dictionary!['AI24 ImageRawDataUUID']!.text()).not((value) => value.equals(images.last.dictionary!['AI24 ImageRawDataUUID']!.text()));
    check(link.preview!.toSamples().colorSamples).deepEquals(createdImageSamples().colorSamples);
    check(link.relativeDirectoryBytes!).deepEquals(latin1.encode('../Links/'));
    check(latin1.decode(drawing.records.program.bytes)).contains('%%DocumentFiles:Links/picture (1).png');
  });

  test('interleaves paths after linked and embedded artwork without state leakage', () {
    AiNativeDrawing drawing = _drawing();
    drawing = drawing.createRaster(definition: createdImageDefinition(), layer: drawing.records.program.layers.single);
    drawing = drawing.createPath(definition: newDocumentPath(0), layer: drawing.records.program.layers.single);
    drawing = drawing.createPlacement(definition: createdLinkDefinition(), layer: drawing.records.program.layers.single);
    drawing = drawing.createPath(definition: newDocumentPath(1), layer: drawing.records.program.layers.single);
    final AiNativeRaster image = AiNativeRasters.decode(records: drawing.records).images.single;
    final AiNativePlacedObject link = AiNativePlacements.decode(records: drawing.records).objects.single;
    check(image.end < drawing.paths.first.start && drawing.paths.first.end < link.start && link.end < drawing.paths.last.start).isTrue();
    check(drawing.paths.map((path) => path.segments.first.coordinates.first).toList()).deepEquals([10, 210]);
    check(image.alphaSamples!).deepEquals([255, 128]);
    check(link.preview!.toSamples().alphaSamples!).deepEquals([255, 128]);
  });

  test('creates in an ordinary group and restores distinct private and printing state', () {
    final AiNativeDrawing initial = _drawing();
    final String bytes = latin1.decode(initial.records.program.bytes).replaceFirst('0 1 0 0 0 Xy', '0 0.8 0 0 0 Xy\n%_0 0.3 0 0 0 Xy');
    final AiNativeDrawing source = _drawing(bytes: latin1.encode(bytes)).createGroup();
    final AiNativeDrawing changed = source.createRaster(definition: createdImageDefinition(), parent: source.groups.single);
    final AiNativeRaster image = AiNativeRasters.decode(records: changed.records).images.single;
    check(image.start > changed.groups.single.start && image.end < changed.groups.single.end).isTrue();
    final List<AiNativeInstruction> states = changed.items.whereType<AiNativeInstruction>().where((item) => item.operator == 'Xy' && item.start > image.end).toList();
    check(states.first.isPrivate).isFalse();
    check(states.first.numbers![1]).equals(0.8);
    check(states.last.isPrivate).isTrue();
    check(states.last.numbers![1]).equals(0.3);
  });

  test('keeps shared file dependencies when embedding or relinking new placements', () {
    AiNativeDrawing drawing = _drawing();
    drawing = drawing.createPlacement(definition: createdLinkDefinition());
    drawing = drawing.createPlacement(definition: createdLinkDefinition());
    AiNativePlacements links = AiNativePlacements.decode(records: drawing.records);
    links = links.relink(object: links.objects.first, pathBytes: latin1.encode('other.png'), relativeDirectoryBytes: null, preview: null);
    check(latin1.decode(links.records.program.bytes)).contains('%%+other.png');
    check(latin1.decode(links.records.program.bytes)).contains('%%DocumentFiles:Links/picture (1).png');
    final AiNativeRasters embedded = links.embed(object: links.objects.last, samples: createdImageSamples());
    check(latin1.decode(embedded.records.program.bytes)).contains('%%DocumentFiles:other.png');
    check(latin1.decode(embedded.records.program.bytes)).not((value) => value.contains('%%DocumentFiles:Links/picture (1).png'));
    check(embedded.images.single.matrix).deepEquals([20, 0, 0, 30, 10, 60]);
  });

  test('supports process spaces, packed depths and explicitly painted stencils', () {
    AiNativeDrawing drawing = _drawing();
    for (final int components in [1, 3, 4]) {
      for (final int depth in [1, 2, 4, 8, 16]) {
        final AiNativeRasterSamples samples = AiNativeRasterSamples(
          width: 1,
          height: 1,
          bitsPerComponent: depth,
          components: components,
          colorSamples: List.filled((components * depth + 7) ~/ 8, 127),
        );
        drawing = drawing.createRaster(
          definition: AiNativeRasterDefinition(samples: samples, matrix: [1, 0, 0, 1, 0, 1]),
        );
      }
    }
    drawing = drawing.createRaster(
      definition: AiNativeRasterDefinition(
        samples: AiNativeRasterSamples(width: 8, height: 1, bitsPerComponent: 1, components: 1, colorSamples: [85], imageMask: true),
        matrix: [2, 0, 0, 2, 0, 2],
        stencilColor: AiColor(space: .cmyk, channels: [0, 1, 0, 0]),
      ),
    );
    check(AiNativeRasters.decode(records: drawing.records).images.length).equals(16);
    check(AiNativeRasters.decode(records: drawing.records).images.last.imageMask).isTrue();
  });

  test('rejects identity collisions, foreign parents, unsafe links and unknown state', () {
    final AiNativeDrawing source = _drawing();
    final AiNativeDrawing changed = source.createRaster(definition: createdImageDefinition());
    check(() => changed.createRaster(definition: createdImageDefinition())).throws<ArgumentError>();
    check(
      () => changed.createRaster(
        definition: createdImageDefinition(id: 'fresh'),
        layer: source.records.program.layers.single,
      ),
    ).throws<ArgumentError>();
    for (final String path in ['', 'bad\n%%Trailer', '(atend)', ' padded ']) {
      check(() => source.createPlacement(definition: createdLinkDefinition(path: path))).throws<ArgumentError>();
    }
    final String bytes = latin1.decode(source.records.program.bytes).replaceFirst('0 1 0 0 0 Xy', '0 1 0 0 0 Xy\nunknown_state');
    final AiNativeDrawing unknown = _drawing(bytes: latin1.encode(bytes));
    check(() => unknown.createRaster(definition: createdImageDefinition())).throws<UnsupportedError>();
    check(() => AiNativeRasterDefinition(samples: createdImageSamples(), matrix: [0, 0, 0, 0, 0, 0])).throws<ArgumentError>();
    check(() => AiNativePlacementDefinition(pathBytes: [65], matrix: [1, 0, 0, 1, 0, 0], bounds: [0, 0, 0, 2])).throws<ArgumentError>();
  });

  test('saves, reopens and embeds a created link with matching host image resources', () {
    final AiNativeDrawing drawing = createdImageDocument();
    final AiPdfDocument saved = newDocumentSave(drawing.records, createdImagePdf());
    final AiNativeSource source = AiNativeData.extract(saved).single;
    final AiNativePlacements links = AiNativePlacements.decode(
      records: AiNativeRecords.decode(program: AiProgram.decode(bytes: source.bytes)),
    );
    check(links.objects.single.preview!.toSamples().alphaSamples!).deepEquals([255, 128]);
    final AiNativeRasters embedded = links.embed(object: links.objects.single, samples: createdImageSamples());
    final AiPdfDocument second =
        const AiCodec().decode(const AiCodec().encode(AiNativeData.replace(source: source, program: embedded.records.program.bytes, synchronizedPdf: saved.pdf))) as AiPdfDocument;
    final AiNativeRecords reread = AiNativeRecords.decode(program: AiProgram.decode(bytes: AiNativeData.extract(second).single.bytes));
    check(AiNativeRasters.decode(records: reread).images.length).equals(2);
    check(AiNativePlacements.decode(records: reread).objects).isEmpty();
    check(latin1.decode(reread.program.bytes)).not((value) => value.contains('%%DocumentFiles:'));
    final PdfDictionary resources = second.pdf.dictionary(second.pdf.pages.single.inherited['Resources']!);
    final PdfDictionary images = second.pdf.dictionary(resources['XObject']!);
    final PdfStream image = second.pdf.resolve(images.values.values.single) as PdfStream;
    check(image.data).deepEquals(createdImageSamples().colorSamples);
    final PdfStream alpha = second.pdf.resolve(image.dictionary['SMask']!) as PdfStream;
    check(alpha.data).deepEquals([255, 128]);
  });

  test('rejects aggregate overflow without mutating the source snapshot', () {
    final AiNativeRecords records = newDocumentRecords(blank: true);
    final AiNativeDrawing limited = _drawing(
      bytes: records.program.bytes,
      limits: AiNativeLimits(maxDecodedBytes: records.program.bytes.length + 100),
    );
    check(() => limited.createRaster(definition: createdImageDefinition())).throws<FormatException>();
    check(limited.records.program.bytes).deepEquals(records.program.bytes);
  });
}
