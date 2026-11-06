import 'package:checks/checks.dart';
import 'package:illustratorkit/illustratorkit.dart';
import 'package:test/test.dart';

import 'ai_native_text_artwork_test.dart' show textArtworkDocument;

/// Places a valid native story under nested ordinary groups with stable identities.
AiNativeLayers groupedTextArtwork() {
  AiNativeDrawing drawing = AiNativeDrawing.decode(records: textArtworkDocument().records);
  drawing = drawing.createGroup(layer: drawing.records.program.layers.first, identifierBytes: 'outer'.codeUnits, inheritParentFlags: true);
  drawing = drawing.createGroup(parent: drawing.groups.single, identifierBytes: 'inner'.codeUnits, inheritParentFlags: true);
  final AiNativeLayers model = AiNativeLayers.decode(drawing: drawing);
  return model.moveArtwork(artwork: model.textArtwork.single, group: drawing.groups.first, inheritParentFlags: true);
}

/// Reads the group's identity at a retained text reference without relying on offsets.
List<int> _parentIdentity(AiNativeLayers model, AiNativeContainer record) {
  final AiNativeItem source = model.structure.parentOf(model.structure.nodeFor(record))!.source as AiNativeItem;
  return AiNativeObjects.decode(drawing: model.drawing).forSource(source).identifier!.bytes;
}

/// Deferred ordinary-group text lifecycle regressions; clipped profiles stay separate.
void main() {
  test('moves grouped text while retaining exact engine bytes and reference indices', () {
    final AiNativeTextDocument original = textArtworkDocument();
    final AiNativeLayers source = groupedTextArtwork();
    final AiNativeTextDocument text = AiNativeTextDocument.decode(records: source.drawing.records);
    // Resource IDs are fresh for each fixture, so compare the moved immutable snapshot.
    final AiNativeLayers returned = source.moveArtwork(artwork: source.textArtwork.single, parent: source.layers.first, inheritParentFlags: true);
    check(AiNativeTextDocument.decode(records: returned.drawing.records).engine.bytes).deepEquals(text.engine.bytes);
    check(_parentIdentity(source, source.textArtwork.single)).deepEquals('inner'.codeUnits);
    check(text.stories.single.modelText).equals(original.stories.single.modelText);
    check(text.referenceIssues).isEmpty();
    check(returned.structure.parentOf(returned.structure.nodeFor(returned.textArtwork.single))!.source).identicalTo(returned.layers.first.source);
  });

  test('duplicates inserts and deletes grouped frames without losing enclosing identities', () {
    final AiNativeLayers source = groupedTextArtwork();
    AiNativeTextDocument text = AiNativeTextDocument.decode(records: source.drawing.records);
    text = text.duplicateStory(story: text.stories.single);
    AiNativeLayers model = AiNativeLayers.decode(drawing: AiNativeDrawing.decode(records: text.records));
    check(model.textArtwork.length).equals(2);
    for (final AiNativeContainer object in model.textArtwork) {
      check(_parentIdentity(model, object)).deepEquals('inner'.codeUnits);
    }
    text = text.insertFrame(story: text.stories.last, index: 1, frame: AiNativeTextFrameDefinition.point(x: 40, y: 50));
    check(text.frames.length).equals(3);
    check(text.referenceIssues).isEmpty();
    text = text.removeStory(story: text.stories.first);
    check(text.stories.length).equals(1);
    check(text.frames.length).equals(2);
    check(text.objects.map((object) => object.storyIndex)).deepEquals([0, 0]);
    text = text.removeStory(story: text.stories.single);
    model = AiNativeLayers.decode(drawing: AiNativeDrawing.decode(records: text.records));
    check(model.drawing.groups.length).equals(2);
    check(model.textArtwork).isEmpty();
    check(text.frames).isEmpty();
    check(text.referenceIssues).isEmpty();
  });

  test('retains literal group panel flags and neutral style applications around text', () {
    final AiNativeLayers source = groupedTextArtwork();
    final AiNativeObjects objects = AiNativeObjects.decode(drawing: source.drawing);
    final AiProgram program = AiNativeEditor.apply(
      program: source.drawing.records.program,
      edits: [
        for (final AiNativeGroup group in source.drawing.groups) ...[
          AiSourceEdit(start: group.start, end: group.start, bytes: '1 Ae\n'.codeUnits),
          AiSourceEdit(start: objects.forSource(group).end, end: objects.forSource(group).end, bytes: '\n9 () XW\n'.codeUnits),
        ],
      ],
    );
    final AiNativeTextDocument text = AiNativeTextDocument.decode(records: AiNativeRecords.decode(program: program));
    final AiNativeTextDocument copied = text.duplicateStory(story: text.stories.single);
    final AiNativeDrawing drawing = AiNativeDrawing.decode(records: copied.records);
    for (final AiNativeGroup group in drawing.groups) {
      final AiNativeObject owner = AiNativeObjects.decode(drawing: drawing).forSource(group);
      check(owner.expanded).equals(true);
      check(owner.styleApplication!.operands.first.number).equals(9);
      check(owner.bindingIssue).isNull();
    }
    check(copied.referenceIssues).isEmpty();
  });

  test('keeps clipped or opaque group parents outside text lifecycle', () {
    final AiNativeLayers source = groupedTextArtwork();
    final AiNativeGroup inner = source.drawing.groups.first;
    final AiProgram program = AiNativeEditor.apply(
      program: source.drawing.records.program,
      edits: [
        AiSourceEdit(start: inner.opening.start, end: inner.opening.end, bytes: 'q'.codeUnits),
        AiSourceEdit(start: inner.closing.start, end: inner.closing.end, bytes: 'Q'.codeUnits),
      ],
    );
    final AiNativeTextDocument text = AiNativeTextDocument.decode(records: AiNativeRecords.decode(program: program));
    check(() => text.duplicateStory(story: text.stories.single)).throws<UnsupportedError>();
    check(() => text.removeStory(story: text.stories.single)).throws<UnsupportedError>();
    check(text.records.program.bytes).deepEquals(program.bytes);
  });
}
