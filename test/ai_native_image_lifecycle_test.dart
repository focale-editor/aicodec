import 'dart:convert';

import 'package:aikit/aikit.dart';
import 'package:checks/checks.dart';
import 'package:test/test.dart';

import 'ai_native_image_attributes_test.dart' show imageAttributeState;
import 'ai_native_image_creation_test.dart' show createdImageDocument;

/// Opens a mixed, identified image tree with a retained external dependency.
AiNativeLayers imageLifecycleTree() => AiNativeLayers.decode(drawing: createdImageDocument());

/// Lists image identities in native drawing order, independent of scene projection.
List<String> imageLifecycleOrder(AiNativeLayers model) {
  final List<AiNativeItem> images = [...model.rasters.images, ...model.placements.objects]..sort((a, b) => a.start.compareTo(b.start));
  return [
    for (final AiNativeItem image in images)
      (switch (image) {
        AiNativeRaster() => image.dictionary,
        AiNativePlacedObject() => image.dictionary,
        _ => throw StateError('Unexpected test image owner.'),
      })!['AI10_ArtUID']!.container!.entries.single.text()!,
  ];
}

/// Exercises mixed structure, source fidelity, independent state and file dependencies.
void main() {
  test('reorders and reparents complete embedded and linked image owners', () {
    final AiNativeLayers source = imageLifecycleTree();
    final AiNativeLayers ordered = source.reorderArtwork(artwork: [source.placements.objects.single, source.rasters.images.single]);
    check(imageLifecycleOrder(ordered)).deepEquals(['linked', 'embedded']);
    check(ordered.placements.objects.single.preview!.bytes).deepEquals(source.placements.objects.single.preview!.bytes);
    check(ordered.rasters.images.single.colorSamples).deepEquals(source.rasters.images.single.colorSamples);
    final AiNativeLayers global = ordered.moveArtwork(artwork: ordered.placements.objects.single, inheritParentFlags: true);
    final AiNativeStructureNode link = global.structure.nodes.singleWhere((node) => node.kind == .instruction && node.start == global.placements.objects.single.instruction.start);
    check(global.structure.parentOf(link)).isNull();
    final AiNativeLayers returned = global.moveArtwork(artwork: global.placements.objects.single, parent: global.layers.single, inheritParentFlags: true);
    check(imageLifecycleOrder(returned)).deepEquals(['embedded', 'linked']);
    check(returned.rootCount).equals(source.rootCount);
  });

  test('duplicates exact native planes with fresh image and artwork identities', () {
    final AiNativeLayers source = imageLifecycleTree();
    final AiNativeRasters deep = source.rasters.replacePixels(
      image: source.rasters.images.single,
      samples: AiNativeRasterSamples(width: 1, height: 1, bitsPerComponent: 16, components: 4, colorSamples: [0, 1, 16, 32, 128, 64, 255, 254], alphaSamples: [128, 1]),
    );
    final AiNativeDrawing result = AiNativeDrawing.decode(records: deep.records).copyRaster(
      source: deep,
      image: deep.images.single,
      matrix: [8, 2, 3, 9, 70, 80],
      attributes: AiNativeImageAttributes(identifierBytes: ascii.encode('copied_image'), nameBytes: utf8.encode('Copie été'), opacity: 0.4),
      layer: deep.records.program.layers.single,
    );
    final AiNativeRasters images = AiNativeRasters.decode(records: result.records);
    final AiNativeRaster copy = images.images.last;
    check(copy.bitsPerComponent).equals(16);
    check(copy.components).equals(4);
    check(copy.colorSamples).deepEquals(deep.images.single.colorSamples);
    check(copy.alphaSamples!).deepEquals(deep.images.single.alphaSamples!);
    check(copy.dictionary!['AI24 ImageRawDataUUID']!.text()).not((value) => value.equals(deep.images.single.dictionary!['AI24 ImageRawDataUUID']!.text()));
    check(copy.dictionary!['AI24 ImageAlphaRawDataUUID']!.text()).not((value) => value.equals(deep.images.single.dictionary!['AI24 ImageAlphaRawDataUUID']!.text()));
    check(imageAttributeState(result.records, copy.start)['Xy']!).deepEquals([0, 0.4, 0, 0, 0]);
  });

  test('retains a shared external dependency until the last linked owner is deleted', () {
    final AiNativeLayers source = imageLifecycleTree();
    AiNativeLayers model = AiNativeLayers.decode(
      drawing: source.drawing.copyPlacement(
        source: source.placements,
        object: source.placements.objects.single,
        matrix: [10, 0, 0, -20, 70, 60],
        attributes: AiNativeImageAttributes(identifierBytes: ascii.encode('copied_link')),
        layer: source.layers.single.source,
      ),
    );
    check(model.placements.objects.last.preview!.bytes).deepEquals(source.placements.objects.single.preview!.bytes);
    check(model.placements.objects.last.relativeDirectoryBytes!).deepEquals(source.placements.objects.single.relativeDirectoryBytes!);
    model = model.removeArtwork(artwork: [model.placements.objects.first]);
    check(latin1.decode(model.drawing.records.program.bytes)).contains('%%DocumentFiles:');
    model = model.removeArtwork(artwork: [model.placements.objects.single]);
    check(latin1.decode(model.drawing.records.program.bytes)).not((value) => value.contains('%%DocumentFiles:'));
    check(model.rasters.images.single.colorSamples).deepEquals(source.rasters.images.single.colorSamples);
    model = model.removeArtwork(artwork: [model.layers.single]);
    check(model.rasters.images).isEmpty();
    check(model.layers).isEmpty();
    check(model.rootCount).equals(0);
  });

  test('changes linked attributes without rewriting paths previews or neighboring state', () {
    final AiNativeLayers source = imageLifecycleTree();
    final AiNativePlacements changed = source.placements.updateAttributes(
      object: source.placements.objects.single,
      nameBytes: utf8.encode('Lien été'),
      opacity: 0.25,
      hidden: true,
      locked: true,
      overprint: true,
    );
    final AiNativePlacedObject link = changed.objects.single;
    check(link.pathBytes).deepEquals(source.placements.objects.single.pathBytes);
    check(link.preview!.bytes).deepEquals(source.placements.objects.single.preview!.bytes);
    check(imageAttributeState(changed.records, link.start)).deepEquals({
      'A': [1],
      'Xw': [1],
      'Xy': [0, 0.25, 0, 0, 0],
      'O': [1],
    });
    check(imageAttributeState(changed.records, changed.records.program.bodyEnd)).deepEquals(imageAttributeState(source.drawing.records, source.drawing.records.program.bodyEnd));
    check(() => changed.updateAttributes(object: source.placements.objects.single, opacity: 1)).throws<ArgumentError>();
  });
}
