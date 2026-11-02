import 'package:aicodec/aicodec.dart';
import 'package:checks/checks.dart';
import 'package:test/test.dart';

import 'ai_native_document_creation_test.dart' show newDocumentRecords;
import 'ai_native_image_attributes_test.dart' show attributedImages, imageAttributeBytes, imageAttributeState;
import 'ai_native_image_creation_test.dart' show createdImageDocument, createdImageSamples, createdLinkDefinition;
import 'ai_native_mesh_geometry_test.dart' show meshGeometryBounds, meshReplacementGrid;

/// Exercises all tuple fields independently of raster and mesh sample opacity.
AiNativeTransparency _value(AiNativeBlendMode mode, {AiNativeKnockout knockout = .inherit}) =>
    AiNativeTransparency(blendMode: mode, opacity: .375, isolated: true, knockout: knockout, alphaIsShape: true);

/// Checks independent native and printable state at an explicit object boundary.
void _expectState(AiNativeRecords records, int offset, AiNativeTransparency value) {
  for (final bool native in [false, true]) {
    check(imageAttributeState(records, offset, native: native)['Xy']!).deepEquals(value.operands);
  }
}

/// Deferred regressions for full blending on images, links and direct meshes.
void main() {
  test('creates every blend mode on raster link and mesh carriers with exact tuples', () {
    final AiNativeDrawing initial = AiNativeDrawing.decode(records: newDocumentRecords(blank: true));
    final AiNativePlacementDefinition link = createdLinkDefinition();
    for (final AiNativeBlendMode mode in AiNativeBlendMode.values) {
      final AiNativeTransparency value = _value(mode, knockout: AiNativeKnockout.values[mode.index % 3]);
      AiNativeDrawing drawing = initial.createRaster(
        definition: AiNativeRasterDefinition(
          samples: createdImageSamples(),
          matrix: [1, 0, 0, 1, 0, 0],
          attributes: AiNativeImageAttributes(transparency: value),
        ),
        layer: initial.records.program.layers.single,
      );
      drawing = drawing.createPlacement(
        definition: AiNativePlacementDefinition(
          pathBytes: link.pathBytes,
          relativeDirectoryBytes: link.relativeDirectoryBytes,
          matrix: link.matrix,
          bounds: link.bounds,
          preview: link.preview,
          attributes: AiNativeImageAttributes(transparency: value),
        ),
        layer: drawing.records.program.layers.single,
      );
      drawing = drawing.createMeshArtwork(
        definition: AiNativeMeshArtworkDefinition(mesh: meshReplacementGrid(), bounds: meshGeometryBounds, transparency: value),
        layer: drawing.records.program.layers.single,
      );
      final AiNativeRasters images = AiNativeRasters.decode(records: drawing.records);
      final AiNativePlacements links = AiNativePlacements.decode(records: drawing.records);
      for (final int start in [images.images.single.start, links.objects.single.start, drawing.meshArtwork.single.start]) {
        _expectState(drawing.records, start, value);
      }
      check(images.images.single.alphaSamples!).deepEquals(createdImageSamples().alphaSamples!);
      check(links.objects.single.preview!.toSamples().alphaSamples!).deepEquals(link.preview!.alphaSamples!);
      for (final bool native in [false, true]) {
        check(imageAttributeState(drawing.records, drawing.records.program.bodyEnd, native: native)).deepEquals(
          imageAttributeState(initial.records, initial.records.program.bodyEnd, native: native),
        );
      }
    }
  });

  test('changes all image flags while preserving independent outgoing states and exact payloads', () {
    final AiNativeRasters original = attributedImages();
    final AiProgram program = AiNativeEditor.apply(
      program: original.records.program,
      edits: [AiSourceEdit(start: original.images.first.start, end: original.images.first.start, bytes: '2 0.5 0 1 0 Xy\n%_3 0.2 1 2 1 Xy\n'.codeUnits)],
    );
    final AiNativeRasters source = AiNativeRasters.decode(records: AiNativeRecords.decode(program: program));
    final AiNativeTransparency value = _value(.colorBurn);
    final AiNativeRasters changed = source.updateAttributes(image: source.images.first, transparency: value);
    _expectState(changed.records, changed.images.first.start, value);
    for (final (int index, AiNativeRaster image) in changed.images.indexed) {
      check(imageAttributeBytes(changed, image)).deepEquals(imageAttributeBytes(source, source.images[index]));
    }
    final List<AiNativeInstruction> restored = AiNativeDrawing.decode(records: changed.records).items
        .whereType<AiNativeInstruction>()
        .where((command) => command.start >= changed.images.first.dictionary!.end && command.operator == 'Xy')
        .take(2)
        .toList();
    check(restored.first.isPrivate).isFalse();
    check(restored.first.numbers!).deepEquals([2, .5, 0, 1, 0]);
    check(restored.last.isPrivate).isTrue();
    check(restored.last.numbers!).deepEquals([3, .2, 1, 2, 1]);
    for (final bool native in [false, true]) {
      check(imageAttributeState(changed.records, changed.images.last.start, native: native)).deepEquals(imageAttributeState(source.records, source.images.last.start, native: native));
    }
    check(changed.updateAttributes(image: changed.images.first, transparency: value)).identicalTo(changed);
    final AiNativeRasters alpha = changed.updateAttributes(image: changed.images.first, opacity: .6);
    check(imageAttributeState(alpha.records, alpha.images.first.start)['Xy']!).deepEquals([7, .6, 1, 2, 1]);
  });

  test('changes link blending without changing link preview metadata or dependencies', () {
    final AiNativeDrawing drawing = createdImageDocument();
    final AiNativePlacements source = AiNativePlacements.decode(records: drawing.records);
    final AiNativePlacedObject before = source.objects.single;
    final AiNativeTransparency value = _value(.luminosity, knockout: .on);
    final AiNativePlacements changed = source.updateAttributes(object: before, transparency: value);
    final AiNativePlacedObject after = changed.objects.single;
    _expectState(changed.records, after.start, value);
    check(changed.records.program.bytes.sublist(after.start, after.dictionary!.end)).deepEquals(source.records.program.bytes.sublist(before.start, before.dictionary!.end));
    check(changed.records.program.bytes.sublist(0, changed.records.program.bodyStart)).deepEquals(source.records.program.bytes.sublist(0, source.records.program.bodyStart));
    check(changed.updateAttributes(object: after, transparency: value)).identicalTo(changed);
    for (final bool native in [false, true]) {
      check(imageAttributeState(changed.records, changed.records.program.bodyEnd, native: native)).deepEquals(imageAttributeState(source.records, source.records.program.bodyEnd, native: native));
    }
  });

  test('copies full blending with exact image planes and linked previews', () {
    final AiNativeDrawing initial = createdImageDocument();
    final AiNativeRasters rasters = AiNativeRasters.decode(records: initial.records);
    final AiNativePlacements links = AiNativePlacements.decode(records: initial.records);
    final AiNativeTransparency value = _value(.softLight);
    AiNativeDrawing drawing = initial.copyRaster(
      source: rasters,
      image: rasters.images.single,
      matrix: rasters.images.single.matrix,
      attributes: AiNativeImageAttributes(identifierBytes: 'blended_raster'.codeUnits, transparency: value),
      layer: initial.records.program.layers.single,
    );
    drawing = drawing.copyPlacement(
      source: links,
      object: links.objects.single,
      matrix: links.objects.single.matrix,
      attributes: AiNativeImageAttributes(identifierBytes: 'blended_link'.codeUnits, transparency: value),
      layer: drawing.records.program.layers.single,
    );
    final AiNativeRaster copied = AiNativeRasters.decode(records: drawing.records).images.last;
    final AiNativePlacedObject linked = AiNativePlacements.decode(records: drawing.records).objects.last;
    _expectState(drawing.records, copied.start, value);
    _expectState(drawing.records, linked.start, value);
    check(copied.colorSamples).deepEquals(rasters.images.single.colorSamples);
    check(copied.alphaSamples!).deepEquals(rasters.images.single.alphaSamples!);
    check(linked.preview!.bytes).deepEquals(links.objects.single.preview!.bytes);
    check(copied.dictionary!['AI24 ImageRawDataUUID']!.text()).not((identity) => identity.equals(rasters.images.single.dictionary!['AI24 ImageRawDataUUID']!.text()));
  });

  test('replaces and duplicates mesh blending without rewriting its corner alpha', () {
    final AiNativeDrawing initial = createdImageDocument();
    final AiNativeDrawing source = initial.createMeshArtwork(
      definition: AiNativeMeshArtworkDefinition(mesh: meshReplacementGrid(), bounds: meshGeometryBounds, identifierBytes: 'mesh'.codeUnits),
      layer: initial.records.program.layers.single,
    );
    final AiNativeTransparency value = _value(.hue);
    final AiNativeDrawing changed = source.replaceMeshArtwork(
      artwork: source.meshArtwork.single,
      definition: AiNativeMeshArtworkDefinition(
        mesh: AiNativeMeshDefinition.fromSource(mesh: source.meshArtwork.single.mesh),
        bounds: meshGeometryBounds,
        transparency: value,
      ),
    );
    _expectState(changed.records, changed.meshArtwork.single.start, value);
    check(changed.meshArtwork.single.mesh.patches.expand((patch) => patch.nodes).map((node) => node.opacity))
        .deepEquals(source.meshArtwork.single.mesh.patches.expand((patch) => patch.nodes).map((node) => node.opacity));
    final AiNativeDrawing copied = changed.duplicateMeshArtwork(artwork: changed.meshArtwork, identifiers: {changed.meshArtwork.single: 'mesh_copy'.codeUnits});
    for (final AiNativeMeshArtwork owner in copied.meshArtwork) {
      _expectState(copied.records, owner.start, value);
    }
    final AiNativeDrawing normal = changed.replaceMeshArtwork(
      artwork: changed.meshArtwork.single,
      definition: AiNativeMeshArtworkDefinition(mesh: meshReplacementGrid(), bounds: meshGeometryBounds, opacity: .6),
    );
    check(imageAttributeState(normal.records, normal.meshArtwork.single.start)['Xy']!).deepEquals([0, .6, 0, 0, 0]);
  });

  test('rejects ambiguous shorthand and full tuples without mutating the source', () {
    final AiNativeDrawing drawing = createdImageDocument();
    final List<int> original = List.of(drawing.records.program.bytes);
    final AiNativeTransparency value = _value(.screen);
    check(() => AiNativeImageAttributes(opacity: .5, transparency: value)).throws<ArgumentError>();
    check(() => AiNativeMeshArtworkDefinition(mesh: meshReplacementGrid(), bounds: meshGeometryBounds, opacity: .5, transparency: value)).throws<ArgumentError>();
    final AiNativeRasters images = AiNativeRasters.decode(records: drawing.records);
    final AiNativePlacements links = AiNativePlacements.decode(records: drawing.records);
    check(() => images.updateAttributes(image: images.images.single, opacity: 1, transparency: value)).throws<ArgumentError>();
    check(() => links.updateAttributes(object: links.objects.single, opacity: 1, transparency: value)).throws<ArgumentError>();
    check(drawing.records.program.bytes).deepEquals(original);
  });
}
