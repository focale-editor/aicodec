import 'dart:convert';

import 'package:checks/checks.dart';
import 'package:illustratorkit/illustratorkit.dart';
import 'package:test/test.dart';

import 'ai_native_document_creation_test.dart' show newDocumentRecords;
import 'ai_native_path_artwork_test.dart' show artworkStates;

/// Supplies independent paths and a native story in the same complete CC tree.
AiNativeTextDocument textArtworkDocument() {
  final AiNativeTextDocument initialized = AiNativeTextDocument.create(
    records: newDocumentRecords(),
    font: AiNativeFontDefinition(postScriptName: 'Example-Regular', technology: AiNativeFontTechnology.trueType),
    fontSize: 12,
    fillColor: AiNativeTextProcessColor(space: AiNativeTextColorSpace.rgb, components: [0, 0, 0]),
    rulerOrigin: [0, 0],
  );
  return initialized.createStory(
    text: 'Shared drawing',
    frames: [AiNativeTextFrameDefinition.point(x: 20, y: 30)],
    layer: initialized.records.program.layers.first,
  );
}

/// Keeps ATE resources unchanged when only drawing ownership and order change.
void main() {
  test('orders text and paths without rewriting text resources or path state', () {
    final AiNativeTextDocument text = textArtworkDocument();
    final AiNativeLayers source = AiNativeLayers.decode(drawing: AiNativeDrawing.decode(records: text.records));
    final AiNativeLayers reordered = source.reorderArtwork(artwork: [source.textArtwork.single, source.drawing.paths.first]);
    check(reordered.textArtwork.single.start).isLessThan(reordered.drawing.paths.first.start);
    check(AiNativeTextDocument.decode(records: reordered.drawing.records).engine.bytes).deepEquals(text.engine.bytes);
    for (final bool native in [false, true]) {
      final List<Map<String, List<Object>>> before = artworkStates(source.drawing, native: native);
      final List<Map<String, List<Object>>> after = artworkStates(reordered.drawing, native: native);
      check(after).deepEquals(before.reversed);
    }
  });

  test('moves the complete text reference into a layer with explicit inheritance', () {
    final AiNativeTextDocument text = textArtworkDocument();
    final AiNativeLayers source = AiNativeLayers.decode(drawing: AiNativeDrawing.decode(records: text.records));
    check(() => source.moveArtwork(artwork: source.textArtwork.single, parent: source.layers[1])).throws<UnsupportedError>();
    final AiNativeLayers moved = source.moveArtwork(artwork: source.textArtwork.single, parent: source.layers[1], inheritParentFlags: true);
    check(moved.structure.parentOf(moved.structure.nodeFor(moved.textArtwork.single))!.source).identicalTo(moved.layers[1].source);
    final AiNativeTextDocument retained = AiNativeTextDocument.decode(records: moved.drawing.records);
    check(retained.engine.bytes).deepEquals(text.engine.bytes);
    check(retained.referenceIssues).isEmpty();
    check(retained.removeStory(story: retained.stories.single).objects).isEmpty();
  });

  test('deletes an identified neighboring path while preserving native text', () {
    final AiNativeTextDocument text = textArtworkDocument();
    final AiNativeLayers source = AiNativeLayers.decode(drawing: AiNativeDrawing.decode(records: text.records));
    final AiNativeLayers removed = source.removeArtwork(artwork: [source.drawing.paths.first]);
    check(removed.drawing.paths.length).equals(1);
    check(AiNativeTextDocument.decode(records: removed.drawing.records).engine.bytes).deepEquals(text.engine.bytes);
    check(() => source.removeArtwork(artwork: [source.textArtwork.single])).throws<UnsupportedError>();
    check(() => source.removeArtwork(artwork: [source.layers.first])).throws<UnsupportedError>();
  });

  test('retains opaque text as a barrier instead of exposing movable handles', () {
    final AiNativeTextDocument text = textArtworkDocument();
    final String source = latin1.decode(text.records.program.bytes).replaceFirst('0 /FreeUndo', '2 /FreeUndo');
    final AiNativeLayers layers = AiNativeLayers.decode(
      drawing: AiNativeDrawing.decode(
        records: AiNativeRecords.decode(program: AiProgram.decode(bytes: latin1.encode(source))),
      ),
    );
    check(layers.textArtwork).isEmpty();
    check(() => layers.moveArtwork(artwork: layers.drawing.records.containers.singleWhere((record) => record.type == 'AI11Text'), inheritParentFlags: true)).throws<UnsupportedError>();
  });
}
