import 'dart:convert';

import 'package:aicodec/aicodec.dart';
import 'package:checks/checks.dart';
import 'package:test/test.dart';

import 'ai_native_document_creation_test.dart' show newDocumentRecords;
import 'ai_native_path_artwork_test.dart' show artworkStates;

/// Opens a complete CC tree with a direct path and one populated sublayer.
AiNativeLayers mixedArtwork() => AiNativeLayers.decode(drawing: AiNativeDrawing.decode(records: newDocumentRecords()));

/// Lists native owners in drawing order, distinguishing layer wrappers and paths.
List<String> mixedOrder(AiNativeLayers model) {
  final List<AiNativeItem> items = [...model.layers, ...model.drawing.paths]..sort((a, b) => a.start.compareTo(b.start));
  return [
    for (final AiNativeItem item in items)
      if (item is AiNativeLayer) latin1.decode(item.identifier!.bytes) else latin1.decode(AiNativeObjects.decode(drawing: model.drawing).forSource(item).identifier!.bytes),
  ];
}

/// Covers interleaved ordering, cross-layer moves and source identity retention.
void main() {
  test('reorders a path and populated sublayer without losing identities or paint', () {
    final AiNativeLayers source = mixedArtwork();
    final AiNativeLayers result = source.reorderArtwork(artwork: [source.layers[1], source.drawing.paths.first]);
    check(mixedOrder(result)).deepEquals(['root', 'child', 'path_1', 'path_0']);
    check(result.rootCount).equals(1);
    for (final bool native in [false, true]) {
      final List<Map<String, List<Object>>> before = artworkStates(source.drawing, native: native);
      final List<Map<String, List<Object>>> after = artworkStates(result.drawing, native: native);
      check(after).deepEquals(before.reversed);
    }
    check(mixedOrder(source)).deepEquals(['root', 'path_0', 'child', 'path_1']);
  });

  test('moves paths to another layer and to the global root with explicit inheritance', () {
    final AiNativeLayers source = mixedArtwork();
    check(() => source.moveArtwork(artwork: source.drawing.paths.first, parent: source.layers[1])).throws<UnsupportedError>();
    final AiNativeLayers nested = source.moveArtwork(artwork: source.drawing.paths.first, parent: source.layers[1], inheritParentFlags: true);
    check(mixedOrder(nested)).deepEquals(['root', 'child', 'path_1', 'path_0']);
    check(nested.structure.parentOf(nested.structure.nodeFor(nested.drawing.paths.last))!.source).identicalTo(nested.layers[1].source);
    final AiNativeLayers global = nested.moveArtwork(artwork: nested.drawing.paths.last, inheritParentFlags: true);
    check(global.structure.parentOf(global.structure.nodeFor(global.drawing.paths.last))).isNull();
    check(global.rootCount).equals(1);
  });

  test('lifts a sublayer to root and nests it again with coherent declarations', () {
    final AiNativeLayers source = mixedArtwork();
    final AiNativeLayers lifted = source.moveArtwork(artwork: source.layers[1], inheritParentFlags: true);
    check(lifted.rootCount).equals(2);
    check(lifted.declaredRootCount).equals(2);
    final AiNativeLayers nested = lifted.moveArtwork(artwork: lifted.layers[1], parent: lifted.layers.first, inheritParentFlags: true);
    check(nested.rootCount).equals(1);
    check(nested.rootCountMatches).isTrue();
    check(mixedOrder(nested)).deepEquals(mixedOrder(source));
  });

  test('preserves different native and printing states through mixed ordering', () {
    final AiNativeLayers original = mixedArtwork();
    final int position = original.drawing.pathTopology(path: original.drawing.paths.first).pointCount!.start;
    final AiProgram program = AiNativeEditor.apply(
      program: original.drawing.records.program,
      edits: [AiSourceEdit(start: position, end: position, bytes: latin1.encode('%_0 0.2 0 0 0 Xy\n'))],
    );
    final AiNativeLayers source = AiNativeLayers.decode(
      drawing: AiNativeDrawing.decode(records: AiNativeRecords.decode(program: program)),
    );
    final AiNativeLayers result = source.reorderArtwork(artwork: [source.layers[1], source.drawing.paths.first]);
    for (final bool native in [false, true]) {
      check(artworkStates(result.drawing, native: native)).deepEquals(artworkStates(source.drawing, native: native).reversed);
    }
  });

  test('requires explicit saved-view invalidation when a layer slot changes', () {
    final String text = latin1.decode(mixedArtwork().drawing.records.program.bytes).replaceFirst('%%EndComments', '%AI5_OpenViewLayers: 2\n%%EndComments');
    final AiNativeLayers source = AiNativeLayers.decode(
      drawing: AiNativeDrawing.decode(
        records: AiNativeRecords.decode(program: AiProgram.decode(bytes: latin1.encode(text))),
      ),
    );
    check(() => source.reorderArtwork(artwork: [source.layers[1], source.drawing.paths.first])).throws<UnsupportedError>();
    final AiNativeLayers result = source.reorderArtwork(artwork: [source.layers[1], source.drawing.paths.first], discardViewState: true);
    check(result.viewComments).isEmpty();
    check(latin1.decode(source.drawing.records.program.bytes)).equals(text);
  });

  test('rejects foreign handles, overlapping owners and destination cycles', () {
    final AiNativeLayers source = mixedArtwork();
    check(() => source.reorderArtwork(artwork: [source.layers.first, source.drawing.paths.first])).throws<ArgumentError>();
    check(() => source.reorderArtwork(artwork: [source.drawing.paths.first, source.drawing.paths.first])).throws<ArgumentError>();
    check(() => source.reorderArtwork(artwork: [mixedArtwork().layers.first])).throws<ArgumentError>();
    check(() => source.moveArtwork(artwork: source.layers.first, parent: source.layers[1], inheritParentFlags: true)).throws<ArgumentError>();
    check(mixedOrder(source)).deepEquals(['root', 'path_0', 'child', 'path_1']);
  });
}
