import 'dart:convert';

import 'package:aikit/aikit.dart';
import 'package:checks/checks.dart';
import 'package:test/test.dart';

import 'ai_native_image_attributes_test.dart' show imageAttributeState;
import 'ai_native_image_creation_test.dart' show createdImageDocument;
import 'ai_native_mesh_artwork_test.dart' show meshArtworkDefinition;
import 'ai_native_path_artwork_test.dart' show artworkStates;
import 'ai_native_path_creation_test.dart' show pathCreationDefinition;

/// Resolves a group by retained native identity, independently of nesting order.
AiNativeGroup mixedGroup(AiNativeLayers model, String id) => model.drawing.groups.singleWhere(
  (group) => latin1.decode(AiNativeObjects.decode(drawing: model.drawing).forSource(group).identifier!.bytes) == id,
);

/// Builds mixed owners beside two empty identified ordinary groups.
AiNativeLayers mixedGroupArtwork() {
  AiNativeDrawing drawing = createdImageDocument();
  drawing = drawing.createPath(definition: pathCreationDefinition(), layer: drawing.records.program.layers.single);
  drawing = drawing.createMeshArtwork(definition: meshArtworkDefinition(), layer: drawing.records.program.layers.single);
  for (final String id in ['outer', 'inner']) {
    drawing = drawing.createGroup(layer: drawing.records.program.layers.single, identifierBytes: id.codeUnits, nameBytes: id.codeUnits, inheritParentFlags: true);
  }
  return AiNativeLayers.decode(drawing: drawing);
}

/// Resolves concrete source ownership for heterogeneous native handles.
AiNativeStructureNode? _parent(AiNativeLayers model, AiNativeItem item) {
  final AiNativeStructureNode node = switch (item) {
    AiNativeRaster() => model.structure.nodes.singleWhere((node) => node.kind == .instruction && node.start == item.instruction.start),
    AiNativePlacedObject() => model.structure.nodes.singleWhere((node) => node.kind == .instruction && node.start == item.instruction.start),
    AiNativeMeshArtwork() => model.structure.nodeFor(item.opening),
    _ => model.structure.nodeFor(item),
  };
  return model.structure.parentOf(node);
}

/// Nests every retained owner using only exact current handles.
AiNativeLayers _nested() {
  AiNativeLayers model = mixedGroupArtwork();
  model = model.moveArtwork(artwork: model.rasters.images.single, group: mixedGroup(model, 'outer'), inheritParentFlags: true);
  model = model.moveArtwork(artwork: model.placements.objects.single, group: mixedGroup(model, 'outer'), inheritParentFlags: true);
  model = model.moveArtwork(artwork: model.drawing.paths.single, group: mixedGroup(model, 'inner'), inheritParentFlags: true);
  return model.moveArtwork(artwork: mixedGroup(model, 'inner'), group: mixedGroup(model, 'outer'), inheritParentFlags: true);
}

/// Deferred mixed hierarchy regressions with independent ownership and state checks.
void main() {
  test('moves mixed owners into groups and back without changing samples or identities', () {
    final AiNativeLayers source = mixedGroupArtwork();
    AiNativeLayers model = source.moveArtwork(artwork: source.rasters.images.single, group: mixedGroup(source, 'outer'), inheritParentFlags: true);
    model = model.moveArtwork(artwork: model.placements.objects.single, group: mixedGroup(model, 'outer'), inheritParentFlags: true);
    model = model.moveArtwork(artwork: model.drawing.meshArtwork.single, group: mixedGroup(model, 'outer'), inheritParentFlags: true);
    for (final AiNativeItem item in [model.rasters.images.single, model.placements.objects.single, model.drawing.meshArtwork.single]) {
      check(_parent(model, item)!.source).identicalTo(mixedGroup(model, 'outer'));
    }
    check(model.rasters.images.single.colorSamples).deepEquals(source.rasters.images.single.colorSamples);
    check(model.rasters.images.single.alphaSamples!).deepEquals(source.rasters.images.single.alphaSamples!);
    check(model.placements.objects.single.preview!.bytes).deepEquals(source.placements.objects.single.preview!.bytes);
    check(model.rasters.images.single.dictionary!['AI24 ImageRawDataUUID']!.text()).equals(source.rasters.images.single.dictionary!['AI24 ImageRawDataUUID']!.text());
    check(model.drawing.meshArtwork.single.identifierBytes!).deepEquals(source.drawing.meshArtwork.single.identifierBytes!);
    model = model.moveArtwork(artwork: model.drawing.meshArtwork.single, inheritParentFlags: true);
    check(_parent(model, model.drawing.meshArtwork.single)).isNull();
    model = model.moveArtwork(artwork: model.drawing.meshArtwork.single, parent: model.layers.single, inheritParentFlags: true);
    check(_parent(model, model.drawing.meshArtwork.single)!.source).identicalTo(model.layers.single.source);
    check(model.rootCount).equals(source.rootCount);
    check(model.rootCountMatches).isTrue();
  });

  test('reorders complete groups together with images and links in an ordinary parent', () {
    final AiNativeLayers source = _nested();
    final AiNativeGroup inner = mixedGroup(source, 'inner');
    final AiNativeLayers result = source.reorderArtwork(artwork: [inner, source.placements.objects.single, source.rasters.images.single]);
    check(mixedGroup(result, 'inner').end).isLessThan(result.placements.objects.single.start);
    check(result.placements.objects.single.end).isLessThan(result.rasters.images.single.start);
    check(_parent(result, mixedGroup(result, 'inner'))!.source).identicalTo(mixedGroup(result, 'outer'));
    for (final bool native in [false, true]) {
      check(artworkStates(result.drawing, native: native)).deepEquals(artworkStates(source.drawing, native: native));
      check(imageAttributeState(result.drawing.records, result.rasters.images.single.start, native: native))
          .deepEquals(imageAttributeState(source.drawing.records, source.rasters.images.single.start, native: native));
      check(imageAttributeState(result.drawing.records, result.placements.objects.single.start, native: native))
          .deepEquals(imageAttributeState(source.drawing.records, source.placements.objects.single.start, native: native));
    }
    check(result.reorderArtwork(artwork: [mixedGroup(result, 'inner'), result.placements.objects.single, result.rasters.images.single])).identicalTo(result);
  });

  test('moves populated groups across ancestry and preserves all descendant ownership', () {
    final AiNativeLayers source = _nested();
    final AiNativeGroup outer = mixedGroup(source, 'outer');
    final AiNativeLayers global = source.moveArtwork(artwork: outer, inheritParentFlags: true);
    check(_parent(global, mixedGroup(global, 'outer'))).isNull();
    check(_parent(global, global.drawing.paths.single)!.source).identicalTo(mixedGroup(global, 'inner'));
    check(_parent(global, global.rasters.images.single)!.source).identicalTo(mixedGroup(global, 'outer'));
    final AiNativeLayers returned = global.moveArtwork(artwork: mixedGroup(global, 'outer'), parent: global.layers.single, inheritParentFlags: true);
    check(_parent(returned, mixedGroup(returned, 'outer'))!.source).identicalTo(returned.layers.single.source);
    check(returned.layers.single.identifier!.bytes).deepEquals(source.layers.single.identifier!.bytes);
    check(returned.rootCount).equals(source.rootCount);
  });

  test('removes complete groups and file dependencies while retaining the surrounding mesh', () {
    final AiNativeLayers source = _nested();
    final AiNativeMesh mesh = source.drawing.meshArtwork.single.mesh;
    final AiNativeLayers result = source.removeArtwork(artwork: [mixedGroup(source, 'outer')]);
    check(result.drawing.groups).isEmpty();
    check(result.drawing.paths).isEmpty();
    check(result.rasters.images).isEmpty();
    check(result.placements.objects).isEmpty();
    check(result.rootCount).equals(source.rootCount);
    check(latin1.decode(result.drawing.records.program.bytes)).not((bytes) => bytes.contains('%%DocumentFiles:'));
    final AiNativeMesh retained = result.drawing.meshArtwork.single.mesh;
    check(result.drawing.records.program.bytes.sublist(retained.start, retained.end)).deepEquals(source.drawing.records.program.bytes.sublist(mesh.start, mesh.end));
    for (final bool native in [false, true]) {
      check(imageAttributeState(result.drawing.records, retained.start, native: native)).deepEquals(imageAttributeState(source.drawing.records, mesh.start, native: native));
    }
  });

  test('retains independent native and printing state when changing mixed group order', () {
    final AiNativeLayers original = _nested();
    final AiNativeRaster image = original.rasters.images.single;
    final AiProgram program = AiNativeEditor.apply(
      program: original.drawing.records.program,
      edits: [AiSourceEdit(start: image.start, end: image.start, bytes: '2 0.7 0 1 0 Xy\n%_3 0.2 1 2 1 Xy\n'.codeUnits)],
    );
    final AiNativeLayers source = AiNativeLayers.decode(
      drawing: AiNativeDrawing.decode(records: AiNativeRecords.decode(program: program)),
    );
    final AiNativeLayers result = source.reorderArtwork(artwork: [source.placements.objects.single, mixedGroup(source, 'inner'), source.rasters.images.single]);
    for (final bool native in [false, true]) {
      check(imageAttributeState(result.drawing.records, result.rasters.images.single.start, native: native))
          .deepEquals(imageAttributeState(source.drawing.records, source.rasters.images.single.start, native: native));
      check(imageAttributeState(result.drawing.records, result.drawing.records.program.bodyEnd, native: native))
          .deepEquals(imageAttributeState(source.drawing.records, source.drawing.records.program.bodyEnd, native: native));
    }
  });

  test('rejects cycles conflicting destinations unknown parents and stale owners atomically', () {
    final AiNativeLayers source = _nested();
    final List<int> bytes = List.of(source.drawing.records.program.bytes);
    check(() => source.moveArtwork(artwork: mixedGroup(source, 'outer'), group: mixedGroup(source, 'inner'), inheritParentFlags: true)).throws<ArgumentError>();
    check(() => source.moveArtwork(artwork: source.layers.single, group: mixedGroup(source, 'outer'), inheritParentFlags: true)).throws<UnsupportedError>();
    check(() => source.moveArtwork(artwork: source.rasters.images.single, group: mixedGroup(source, 'inner'), parent: source.layers.single)).throws<ArgumentError>();
    check(() => source.moveArtwork(artwork: source.rasters.images.single, group: mixedGroup(_nested(), 'inner'))).throws<ArgumentError>();
    check(() => source.reorderArtwork(artwork: [mixedGroup(source, 'outer'), source.rasters.images.single])).throws<ArgumentError>();
    check(() => source.moveArtwork(artwork: source.rasters.images.single, group: mixedGroup(source, 'inner'))).throws<UnsupportedError>();
    final AiNativeGroup inner = mixedGroup(source, 'inner');
    final AiProgram clipped = AiNativeEditor.apply(
      program: source.drawing.records.program,
      edits: [
        AiSourceEdit(start: inner.opening.start, end: inner.opening.end, bytes: 'q'.codeUnits),
        AiSourceEdit(start: inner.closing.start, end: inner.closing.end, bytes: 'Q'.codeUnits),
      ],
    );
    final AiNativeLayers unsafe = AiNativeLayers.decode(
      drawing: AiNativeDrawing.decode(records: AiNativeRecords.decode(program: clipped)),
    );
    check(() => unsafe.moveArtwork(artwork: unsafe.rasters.images.single, group: mixedGroup(unsafe, 'inner'), inheritParentFlags: true)).throws<UnsupportedError>();
    check(source.drawing.records.program.bytes).deepEquals(bytes);
  });
}
