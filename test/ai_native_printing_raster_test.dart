import 'dart:convert';

import 'package:aikit/aikit.dart';
import 'package:checks/checks.dart';
import 'package:test/test.dart';

import 'ai_native_appearance_artwork_test.dart' show appearanceArtworkPair, appearanceArtworkSource, appearanceArtworkState;
import 'ai_native_appearance_duplication_test.dart' show appearanceCopyIdentities;
import 'ai_native_appearance_editing_test.dart' show appearanceEditingModel;
import 'ai_native_document_creation_test.dart' show newDocumentRecords, newDocumentSave;
import 'ai_native_image_creation_test.dart' show createdImagePdf, createdImageSamples;
import 'ai_native_opacity_masks_test.dart' show changedMaskSettings;
import 'ai_native_transparency_test.dart' show transparencySource;

/// Original vector expansion, independent of the replacement serializer.
const String _vector = 'u\n\n0 0 0 1 k\n0 0 m 10 0 L 10 10 L 0 0 L f\nU';

/// Complete host bytes retaining the fixture's outgoing fill assignment.
List<int> _group({AiNativeRasterSamples? samples, bool transparency = false, String prefix = '', String suffix = ''}) => [
  ...latin1.encode('u\n0 0 0 1 k\n$prefix'),
  ...(samples ?? createdImageSamples()).encodePrintingArtwork(matrix: [10, 0, 0, 20, 0, 60]),
  ...latin1.encode('\n$suffix${transparency ? '0 1 0 0 0 Xy\n' : ''}U'),
];

/// Supplies complete immutable artwork to one current appearance owner.
AiNativeAppearanceReplacement _replacement(AiNativeAppearances model, List<int> bytes) => AiNativeAppearanceReplacement(
  artwork: model.artworkFor(use: model.uses.first),
  bytes: bytes,
  bounds: AiBoundingBox(left: 0, bottom: 0, right: 100, top: 100),
);

/// Updates only the derived view while retaining the exact named native style.
AiNativeAppearances _replace(AiNativeAppearances model, List<int> bytes) => model.applyStyle(appearance: model.styles.first, artwork: [_replacement(model, bytes)]);

/// Reads exact native owner bytes for authoring and neighbor preservation.
List<int> _bytes(AiNativeAppearances model, AiNativeItem item) => model.structure.drawing.records.program.bytes.sublist(item.start, item.end);

/// Exercises raster printing without rendering pixels or replacing native art.
void main() {
  test('serializes process depths and alpha with exact binary ownership', () {
    for (final int components in [1, 3, 4]) {
      for (final int depth in [1, 2, 4, 8, 16]) {
        final AiNativeRasterSamples samples = AiNativeRasterSamples(
          width: 2,
          height: 1,
          bitsPerComponent: depth,
          components: components,
          colorSamples: List.filled((2 * depth * components + 7) ~/ 8, 127),
          alphaSamples: List.filled((2 * depth + 7) ~/ 8, 128),
        );
        final AiNativeAppearances model = appearanceEditingModel(source: appearanceArtworkSource().replaceFirst(_vector, latin1.decode(_group(samples: samples))));
        final AiNativeAppearanceArtwork owner = model.artworkFor(use: model.uses.first);
        final AiNativeRaster image = owner.printingRasters.single;
        check(owner.printingGroup.paths).isEmpty();
        check(owner.path!.isPrivate).isTrue();
        check(image.colorSamples).deepEquals(samples.colorSamples);
        check(image.alphaSamples!).deepEquals(samples.alphaSamples!);
        check(image.components).equals(components);
        check(image.bitsPerComponent).equals(depth);
        check(image.dictionary).isNull();
        check(image.instruction.isPrivate).isFalse();
        check(image.matrix).deepEquals([10.0, 0.0, 0.0, 20.0, 0.0, 60.0]);
      }
    }
  });

  test('replaces vectors with raster printing and restores vectors without touching authoring', () {
    final AiNativeAppearances source = appearanceEditingModel(source: appearanceArtworkSource(metadata: true));
    final AiNativeAppearanceArtwork before = source.artworkFor(use: source.uses.first);
    final AiNativeAppearanceArtwork neighbor = source.artworkFor(use: source.uses.last);
    final AiNativeAppearances raster = _replace(source, _group());
    final AiNativeAppearanceArtwork after = raster.artworkFor(use: raster.uses.first);
    check(_bytes(raster, after.authoring)).deepEquals(_bytes(source, before.authoring));
    check(_bytes(raster, after.dictionary!)).deepEquals(_bytes(source, before.dictionary!));
    check(_bytes(raster, after.printingDictionary!)).deepEquals(_bytes(source, before.printingDictionary!));
    final AiNativeAppearanceArtwork retained = raster.artworkFor(use: raster.uses.last);
    check(raster.structure.drawing.records.program.bytes.sublist(retained.start, retained.end)).deepEquals(source.structure.drawing.records.program.bytes.sublist(neighbor.start, neighbor.end));
    check(after.printingRasters.single.colorSamples).deepEquals(createdImageSamples().colorSamples);
    final AiNativeAppearances vector = _replace(raster, latin1.encode(_vector));
    check(vector.artworkFor(use: vector.uses.first).printingRasters).isEmpty();
    check(vector.artworkFor(use: vector.uses.first).printingGroup.paths).length.equals(1);
  });

  test('keeps counted contours coherent when a printing view has no contours', () {
    final AiNativeAppearances source = appearanceEditingModel(source: appearanceArtworkSource(counted: true));
    final AiNativeAppearances raster = _replace(source, _group());
    final AiNativeAppearances vector = _replace(raster, latin1.encode(_vector.replaceFirst('0 0 m', '3 As\n0 0 m')));
    check(vector.artworkFor(use: vector.uses.first).printingGroup.paths).length.equals(1);
    check(() => _replace(source, _group(prefix: '3 As\n'))).throws<UnsupportedError>();
  });

  test('creates copies moves removes and saves independently authored raster appearances', () {
    final AiNativeAppearances blank =
        AiNativeAppearances.decode(
          structure: AiNativeStructure.decode(drawing: AiNativeDrawing.decode(records: newDocumentRecords(blank: true))),
        ).createStyle(
          nameBytes: latin1.encode('Shared'),
          execution: AiNativeAppearancePartDefinition(
            kind: .fill,
            colors: [
              AiColor(space: .gray, channels: [0.25]),
            ],
          ),
        );
    final AiNativeAppearances source = blank.createArtwork(
      bytes: latin1.encode(appearanceArtworkPair(metadata: true).replaceFirst(_vector, latin1.decode(_group()))),
      bounds: AiBoundingBox(left: 0, bottom: 0, right: 100, top: 100),
      layer: blank.structure.drawing.records.program.layers.single,
    );
    final AiNativeAppearanceArtwork owner = source.artworkFor(use: source.uses.single);
    final AiNativeAppearances copied = source.duplicateArtwork(artwork: [owner], identifiers: appearanceCopyIdentities(source, [owner]));
    final AiNativeAppearances moved = copied.moveArtwork(
      artwork: copied.artworkFor(use: copied.uses.last),
      before: copied.artworkFor(use: copied.uses.first),
      bounds: AiBoundingBox(left: 0, bottom: 0, right: 100, top: 100),
    );
    final AiNativeAppearances removed = moved.removeArtwork(artwork: [moved.artworkFor(use: moved.uses.last)]);
    final AiPdfDocument saved = newDocumentSave(removed.structure.drawing.records, createdImagePdf());
    final AiNativeAppearances reopened = appearanceEditingModel(source: latin1.decode(AiNativeData.extract(saved).single.bytes));
    final AiNativeAppearanceArtwork result = reopened.artworkFor(use: reopened.uses.single);
    check(result.printingRasters.single.colorSamples).deepEquals(createdImageSamples().colorSamples);
    check(result.printingRasters.single.alphaSamples!).deepEquals(createdImageSamples().alphaSamples!);
    check(result.path!.segments.map((segment) => segment.coordinates)).deepEquals(owner.path!.segments.map((segment) => segment.coordinates));
    check(reopened.structure.identifiers.where((identifier) => identifier.kind == .xmlArt).map((identity) => latin1.decode(identity.bytes))).deepEquals(['root', 'copy_0']);
  });

  test('attaches and removes group masks with complete raster printing', () {
    final AiNativeAppearances source = appearanceEditingModel(source: transparencySource(grouped: true));
    final AiNativeAppearanceArtwork owner = source.artworkFor(use: source.uses.first);
    final AiNativeAppearances masked = source.createOpacityMasks(
      masks: [
        AiNativeOpacityMaskAttachment(
          artwork: owner,
          settings: changedMaskSettings,
          artworkBytes: latin1.encode('X=\n%_0 Ae u 0 Ap\n%_0.5 g 0 0 m 10 0 L 10 10 L f\n%_U\n%_9 () XW\n%_X+'),
        ),
      ],
      artwork: [_replacement(source, _group(transparency: true))],
    );
    final AiNativeAppearanceArtwork after = masked.artworkFor(use: masked.uses.first);
    check(after.group).isNotNull();
    check(after.opacityMasks).length.equals(1);
    check(after.printingRasters.single.alphaSamples!).deepEquals(createdImageSamples().alphaSamples!);
    final AiNativeAppearances removed = masked.deleteOpacityMasks(masks: after.opacityMasks, artwork: [_replacement(masked, _group(transparency: true))]);
    check(removed.artworkFor(use: removed.uses.first).opacityMasks).isEmpty();
    check(_bytes(removed, removed.artworkFor(use: removed.uses.first).authoring)).deepEquals(_bytes(source, owner.authoring));
  });

  test('binary samples cannot inject native boundaries or private dictionaries', () {
    final List<int> pixels = latin1.encode('U\n%%Trailer\n%_/ArtDictionary : ;\n%%EndData\u0000');
    final AiNativeRasterSamples samples = AiNativeRasterSamples(width: pixels.length, height: 1, bitsPerComponent: 8, components: 1, colorSamples: pixels);
    final AiNativeAppearances source = appearanceEditingModel(source: appearanceArtworkSource());
    final AiNativeAppearances result = _replace(source, _group(samples: samples));
    check(result.uses).length.equals(2);
    check(result.artworkFor(use: result.uses.first).printingRasters.single.colorSamples).deepEquals(pixels);
    check(result.structure.identifiers).isEmpty();
  });

  test('retains effective clipping around a derived image and vector contours', () {
    final AiNativeAppearances source = appearanceEditingModel(source: appearanceArtworkSource());
    final AiNativeAppearances result = _replace(
      source,
      _group(prefix: 'q\n0 0 m 100 0 L 100 100 L 0 0 L h W n\n', suffix: '20 20 m 30 20 L 30 30 L f\nQ\n'),
    );
    final AiNativeAppearanceArtwork owner = result.artworkFor(use: result.uses.first);
    check(owner.printingGroup.paths).length.equals(2);
    check(owner.printingRasters).length.equals(1);
    check(owner.path!.isPrivate).isTrue();
    final AiNativeAppearances replaced = _replace(result, latin1.encode(_vector));
    check(replaced.artworkFor(use: replaced.uses.first).printingRasters).isEmpty();
  });

  test('rejects unowned annotations metadata state leaks and compound raster roles atomically', () {
    final AiNativeAppearances source = appearanceEditingModel(source: appearanceArtworkSource());
    final List<int> before = source.structure.drawing.records.program.bytes.toList();
    for (final List<int> group in [
      _group(prefix: '%%PageTrailer\n'),
      _group(suffix: '%_/ArtDictionary : (cache) /String (AI24 ImageRawDataUUID) , ;\n'),
      _group(suffix: '1 g\n'),
      _group(prefix: '*u\n', suffix: '*U\n'),
      _group(prefix: '%AI17_Unknown\n'),
    ]) {
      check(() => _replace(source, group)).throws<UnsupportedError>();
      check(source.structure.drawing.records.program.bytes).deepEquals(before);
    }
  });

  test('limits and matrix validation apply before returning immutable bytes', () {
    final AiNativeRasterSamples samples = createdImageSamples();
    check(() => samples.encodePrintingArtwork(matrix: [0, 0, 0, 0, 0, 0])).throws<ArgumentError>();
    check(() => samples.encodePrintingArtwork(matrix: [1, 0, 0, 1, double.infinity, 0])).throws<ArgumentError>();
    check(() => samples.encodePrintingArtwork(matrix: [1, 0, 0, 1, 0, 0], limits: const AiNativeLimits(maxDecodedBytes: 4))).throws<AiLimitException>();
    check(() => samples.encodePrintingArtwork(matrix: [1, 0, 0, 1, 0, 0], limits: const AiNativeLimits(maxTokens: 4))).throws<AiLimitException>();
    final List<int> encoded = samples.encodePrintingArtwork(matrix: [1, 0, 0, 1, 0, 0]);
    check(() => encoded[0] = 0).throws<UnsupportedError>();
  });

  test('local binding does not decode unrelated unsupported raster neighbors', () {
    final String source = appearanceArtworkSource().replaceFirst(_vector, latin1.decode(_group())).replaceFirst('%%Trailer', '%AI5_BeginRaster\n1 FutureImage\n%AI5_EndRaster\n%%Trailer');
    final AiNativeAppearances model = appearanceEditingModel(source: source);
    check(model.artworkFor(use: model.uses.first).printingRasters.single.width).equals(2);
  });

  test('composed raster replacement restores source state after external blending', () {
    final AiNativeAppearances source = appearanceEditingModel(source: appearanceArtworkSource());
    final AiNativeAppearanceArtwork owner = source.artworkFor(use: source.uses.first);
    final AiNativeAppearanceReplacement replacement = AiNativeAppearanceReplacement.raster(
      artwork: owner,
      samples: createdImageSamples(),
      matrix: [10, 0, 0, 20, 0, 60],
      transparency: AiNativeTransparency(blendMode: .multiply, opacity: 0.25, isolated: true, knockout: .off, alphaIsShape: false),
      bounds: AiBoundingBox(left: 0, bottom: 40, right: 20, top: 60),
    );
    final AiNativeAppearances result = source.applyStyle(appearance: source.styles.first, artwork: [replacement]);
    final AiNativeAppearanceArtwork changed = result.artworkFor(use: result.uses.first);
    final List<AiNativeInstruction> blends = result.structure.drawing.items
        .whereType<AiNativeInstruction>()
        .where((command) => command.operator == 'Xy' && command.start >= changed.printingGroup.start && command.end <= changed.printingGroup.end)
        .toList();
    check(blends.first.numbers).isNotNull().deepEquals([1.0, 0.25, 1.0, 0.0, 0.0]);
    check(blends.last.numbers).isNotNull().deepEquals([0.0, 1.0, 0.0, 0.0, 0.0]);
    check(_bytes(result, changed.authoring)).deepEquals(_bytes(source, owner.authoring));
  });

  test('composed raster replacement does not invent unknown transparency', () {
    final AiNativeAppearances source = appearanceEditingModel(source: appearanceArtworkSource().replaceAll(appearanceArtworkState, ''));
    check(
      () => AiNativeAppearanceReplacement.raster(
        artwork: source.artworkFor(use: source.uses.first),
        samples: createdImageSamples(),
        matrix: [1, 0, 0, 1, 0, 0],
        transparency: AiNativeTransparency(blendMode: .normal, opacity: 1, isolated: false, knockout: .off, alphaIsShape: false),
        bounds: AiBoundingBox(left: 0, bottom: -1, right: 2, top: 0),
      ),
    ).throws<UnsupportedError>();
  });
}
