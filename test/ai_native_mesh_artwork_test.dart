import 'dart:convert';

import 'package:aikit/aikit.dart';
import 'package:checks/checks.dart';
import 'package:test/test.dart';

import 'ai_native_document_creation_test.dart' show newDocumentRecords;
import 'ai_native_mesh_geometry_test.dart' show meshGeometryBounds, meshGeometryPacket, meshGeometrySource, meshReplacementGrid;
import 'ai_native_path_artwork_test.dart' show artworkStates;

/// Supplies a complete explicit grid with a fresh object identity.
AiNativeMeshArtworkDefinition meshArtworkDefinition({bool fresh = true, double opacity = 1, bool hidden = false}) => AiNativeMeshArtworkDefinition(
  mesh: meshReplacementGrid(),
  bounds: meshGeometryBounds,
  opacity: opacity,
  hidden: hidden,
  nameBytes: fresh ? latin1.encode('Authored mesh') : null,
  identifierBytes: fresh ? latin1.encode('mesh-object') : null,
);

/// Authors a mesh beside the source's ordinary paths and child layer.
AiNativeDrawing meshArtworkDocument() {
  final AiNativeDrawing source = AiNativeDrawing.decode(records: newDocumentRecords());
  return source.createMeshArtwork(definition: meshArtworkDefinition(), layer: source.records.program.layers.first);
}

/// Deferred source-ownership regressions, independent of mesh rendering.
void main() {
  test('creates identified native mesh data without an existing mesh template', () {
    final AiNativeDrawing source = AiNativeDrawing.decode(records: newDocumentRecords());
    final List<int> original = List.of(source.records.program.bytes);
    final AiNativeDrawing changed = source.createMeshArtwork(definition: meshArtworkDefinition(), layer: source.records.program.layers.first);
    final AiNativeMeshArtwork owner = changed.meshArtwork.single;
    check(owner.mesh.size).equals((first: 1, second: 2));
    check(owner.mesh.patches.expand((patch) => patch.nodes).length).equals(8);
    check(owner.identifierBytes!).deepEquals(latin1.encode('mesh-object'));
    check(owner.nameBytes!).deepEquals(latin1.encode('Authored mesh'));
    check(changed.paths.length).equals(source.paths.length);
    check(changed.records.program.layers.length).equals(source.records.program.layers.length);
    check(source.records.program.bytes).deepEquals(original);
    for (final bool native in [false, true]) {
      check(artworkStates(changed, native: native)).deepEquals(artworkStates(source, native: native));
    }
  });

  test('copies the complete mesh with a fresh identity and explicit inherited flags', () {
    final AiNativeDrawing source = meshArtworkDocument();
    final AiNativeMeshArtwork owner = source.meshArtwork.single;
    check(() => source.duplicateMeshArtwork(artwork: [owner])).throws<ArgumentError>();
    final AiNativeDrawing changed = source.duplicateMeshArtwork(artwork: [owner], identifiers: {owner: latin1.encode('mesh-copy')});
    check(changed.meshArtwork.length).equals(2);
    check(changed.meshArtwork.last.identifierBytes!).deepEquals(latin1.encode('mesh-copy'));
    final AiNativeMesh copy = changed.meshArtwork.last.mesh;
    check(changed.records.program.bytes.sublist(copy.start, copy.end)).deepEquals(source.records.program.bytes.sublist(owner.mesh.start, owner.mesh.end));
    check(latin1.decode(changed.records.program.bytes).contains('aikit:mesh')).isFalse();
    for (final bool native in [false, true]) {
      check(artworkStates(changed, native: native)).deepEquals(artworkStates(source, native: native));
    }
  });

  test('reorders mixed owners and reparents the entire mesh with its metadata', () {
    final AiNativeLayers source = AiNativeLayers.decode(drawing: meshArtworkDocument());
    final AiNativeMeshArtwork owner = source.drawing.meshArtwork.single;
    final AiNativeLayers reordered = source.reorderArtwork(artwork: [owner, source.drawing.paths.first]);
    check(reordered.drawing.meshArtwork.single.start).isLessThan(reordered.drawing.paths.first.start);
    final AiNativeLayers moved = reordered.moveArtwork(artwork: reordered.drawing.meshArtwork.single, parent: reordered.layers[1], inheritParentFlags: true);
    final AiNativeMeshArtwork retained = moved.drawing.meshArtwork.single;
    check(moved.structure.parentOf(moved.structure.nodeFor(retained.opening))!.source).identicalTo(moved.layers[1].source);
    check(retained.identifierBytes!).deepEquals(owner.identifierBytes!);
    check(retained.nameBytes!).deepEquals(owner.nameBytes!);
  });

  test('replaces topology and object flags without changing neighbor attributes', () {
    final AiNativeDrawing source = meshArtworkDocument();
    final AiNativeMesh sourceGrid = meshGeometrySource(packet: meshGeometryPacket(ink: true)).meshes.single;
    final AiNativeDrawing changed = source.replaceMeshArtwork(
      artwork: source.meshArtwork.single,
      definition: AiNativeMeshArtworkDefinition(
        mesh: AiNativeMeshDefinition.fromSource(mesh: sourceGrid),
        bounds: meshGeometryBounds,
        opacity: .25,
        hidden: true,
        locked: true,
        overprint: true,
      ),
    );
    final AiNativeMeshArtwork retained = changed.meshArtwork.single;
    check(retained.mesh.size).equals((first: 2, second: 1));
    check(retained.mesh.patches.first.nodes.first.kind).equals(AiNativeMeshNodeKind.anchor);
    check(retained.mesh.vertices.first.corners.first.colorSpace!.inks.single.nameBytes).deepEquals(latin1.encode('Named ink'));
    check(retained.identifierBytes!).deepEquals(source.meshArtwork.single.identifierBytes!);
    for (final bool native in [false, true]) {
      check(artworkStates(changed, native: native)).deepEquals(artworkStates(source, native: native));
    }
  });

  test('removes complete mesh metadata without removing neighboring paths', () {
    final AiNativeLayers source = AiNativeLayers.decode(drawing: meshArtworkDocument());
    final AiNativeLayers removed = source.removeArtwork(artwork: [source.drawing.meshArtwork.single]);
    check(removed.drawing.meshArtwork).isEmpty();
    check(AiNativeMeshes.decode(records: removed.drawing.records).meshes).isEmpty();
    check(removed.drawing.paths.length).equals(source.drawing.paths.length);
    check(removed.structure.identifiers.any((identifier) => latin1.decode(identifier.bytes) == 'mesh-object')).isFalse();
  });

  test('layer copies allocate identities for contained meshes and ordinary owners', () {
    final AiNativeLayers source = AiNativeLayers.decode(drawing: meshArtworkDocument());
    final Map<AiNativeItem, List<int>> artworkIdentifiers = {
      for (final AiNativeObject object in AiNativeObjects.decode(drawing: source.drawing).objects)
        if (object.identifier != null) object.source: latin1.encode('copy-${latin1.decode(object.identifier!.bytes)}'),
      source.drawing.meshArtwork.single: latin1.encode('copy-mesh'),
    };
    final AiNativeLayers copied = source.duplicate(
      layers: [source.layers.first],
      identifiers: {for (final AiNativeLayer layer in source.layers) layer: latin1.encode('layer-copy-${layer.index}')},
      artworkIdentifiers: artworkIdentifiers,
    );
    check(copied.drawing.meshArtwork.length).equals(2);
    check(copied.drawing.meshArtwork.last.identifierBytes!).deepEquals(latin1.encode('copy-mesh'));
    check(copied.drawing.paths.length).equals(source.drawing.paths.length * 2);
  });

  test('retains complete mesh packets during artboard ordering', () {
    final AiNativeDrawing source = meshArtworkDocument();
    final AiNativeArtboards boards = AiNativeArtboards.decode(records: source.records);
    final AiNativeArtboards changed = boards.reorder(artboards: boards.artboards.reversed.toList(), cropBounds: null);
    final AiNativeDrawing drawing = AiNativeDrawing.decode(records: changed.records);
    final AiNativeMesh before = source.meshArtwork.single.mesh;
    final AiNativeMesh after = drawing.meshArtwork.single.mesh;
    check(drawing.records.program.bytes.sublist(after.start, after.end)).deepEquals(source.records.program.bytes.sublist(before.start, before.end));
  });

  test('creates and copies a mesh in an ordinary named group', () {
    final AiNativeDrawing source = AiNativeDrawing.decode(records: newDocumentRecords(blank: true)).createGroup(identifierBytes: latin1.encode('mesh-group'));
    final AiNativeDrawing created = source.createMeshArtwork(definition: meshArtworkDefinition(), parent: source.groups.single);
    final AiNativeDrawing copied = created.duplicateGroups(
      groups: created.groups,
      identifiers: {created.groups.single: latin1.encode('group-copy'), created.meshArtwork.single: latin1.encode('mesh-in-copy')},
    );
    check(copied.meshArtwork.length).equals(2);
    final AiNativeDrawing removed = copied.removeGroups(groups: [copied.groups.first]);
    check(removed.meshArtwork.single.identifierBytes!).deepEquals(latin1.encode('mesh-in-copy'));
  });

  test('rejects stale owners, duplicate identities and replacement metadata', () {
    final AiNativeDrawing source = meshArtworkDocument();
    final AiNativeDrawing reopened = AiNativeDrawing.decode(records: source.records);
    check(() => reopened.replaceMeshArtwork(artwork: source.meshArtwork.single, definition: meshArtworkDefinition(fresh: false))).throws<ArgumentError>();
    check(() => source.createMeshArtwork(definition: meshArtworkDefinition())).throws<ArgumentError>();
    check(() => source.replaceMeshArtwork(artwork: source.meshArtwork.single, definition: meshArtworkDefinition())).throws<ArgumentError>();
  });

  test('unknown fields and attached appearance bindings receive no movable owner', () {
    final String packet = meshGeometryPacket();
    for (final String changed in [packet.replaceFirst('%_/Data X#', '%_42 /Unknown X#\n%_/Data X#'), '$packet\n6 () XW']) {
      final AiNativeDrawing drawing = AiNativeDrawing.decode(records: meshGeometrySource(packet: changed).records);
      check(drawing.meshArtwork).isEmpty();
    }
  });
}
