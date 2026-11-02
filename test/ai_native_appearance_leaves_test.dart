import 'dart:convert';

import 'package:aikit/aikit.dart';
import 'package:checks/checks.dart';
import 'package:test/test.dart';

import 'ai_native_document_creation_test.dart' show newDocumentPath, newDocumentRecords;
import 'ai_native_mesh_geometry_test.dart' show meshReplacementGrid;
import 'ai_native_text_creation_test.dart' show newDocumentText;

/// Independent native families share a complete printing owner.
AiNativeAppearances mixedAppearanceModel({bool text = false}) {
  final AiNativeRecords records = text ? newDocumentText().records : newDocumentRecords(blank: true);
  final AiNativeAppearances model =
      AiNativeAppearances.decode(
        structure: AiNativeStructure.decode(drawing: AiNativeDrawing.decode(records: records)),
      ).createStyle(
        nameBytes: ascii.encode('Mixed'),
        execution: AiNativeAppearancePartDefinition(kind: .conduit),
      );
  return model.createGroupArtwork(
    definition: AiNativeAppearanceGroupDefinition(
      styleNameBytes: ascii.encode('Mixed'),
      identifierBytes: ascii.encode('mixed'),
      children: [
        AiNativeAppearancePathDefinition(definition: newDocumentPath(0)),
        AiNativeAppearanceGroupDefinition(children: [], identifierBytes: ascii.encode('image'), leaf: mixedAppearanceImage(7)),
        AiNativeAppearanceGroupDefinition(
          children: [],
          identifierBytes: ascii.encode('mesh'),
          leaf: AiNativeAppearanceMeshDefinition(definition: meshReplacementGrid()),
        ),
        if (text) AiNativeAppearanceGroupDefinition(children: [], identifierBytes: ascii.encode('text')),
      ],
    ),
    printingBytes: ascii.encode('u\n0 g\n0 0 m 10 0 L 10 10 L f\nU'),
    bounds: AiBoundingBox(left: 0, bottom: 0, right: 240, top: 50),
    layer: model.structure.drawing.records.program.layers.single,
  );
}

/// Uses delimiter-like sample bytes to catch accidental private-line rewriting.
AiNativeAppearanceRasterDefinition mixedAppearanceImage(int value) => AiNativeAppearanceRasterDefinition(
  definition: AiNativeRasterDefinition(
    samples: AiNativeRasterSamples(width: 2, height: 1, bitsPerComponent: 8, components: 3, colorSamples: [value, 10, 37, 95, 88, 73]),
    matrix: [1, 0, 0, 1, 20, 20],
  ),
);

/// Returns the unique complete authoring and printing pair.
AiNativeAppearanceArtwork mixedAppearanceOwner(AiNativeAppearances model) => model.artworkFor(use: model.uses.singleWhere((use) => !use.instruction.isPrivate));

void main() {
  test('keeps image samples and mesh topology inside an editable private tree', () {
    final AiNativeAppearances model = mixedAppearanceModel();
    final AiNativeAppearanceArtwork owner = mixedAppearanceOwner(model);
    check(owner.leaves).length.equals(2);
    check(owner.leaves.values.first.raster!.colorSamples).deepEquals([7, 10, 37, 95, 88, 73]);
    check(owner.leaves.values.last.mesh!.patches).length.equals(2);
    final AiNativeAppearances changed = model.replaceArtworkTrees(
      changes: [
        AiNativeAppearanceTreeChange(
          artwork: AiNativeAppearanceReplacement(
            artwork: owner,
            bytes: model.structure.drawing.records.program.bytes.sublist(owner.printingGroup.start, owner.printingGroup.end),
            bounds: AiBoundingBox(left: 0, bottom: 0, right: 240, top: 50),
          ),
          children: [
            for (final AiNativeItem child in owner.group!.children)
              AiNativeAppearanceTreeChild.retain(source: child, leaf: identical(child, owner.leaves.keys.first) ? mixedAppearanceImage(99) : null),
          ],
        ),
      ],
    );
    check(mixedAppearanceOwner(changed).leaves.values.first.raster!.colorSamples.first).equals(99);
    check(changed.structure.identifiers.map((identity) => latin1.decode(identity.bytes))).deepEquals(model.structure.identifiers.map((identity) => latin1.decode(identity.bytes)));
    check(owner.leaves.values.first.raster!.colorSamples.first).equals(7);
  });

  test('creates and updates global text references inside a qualified private wrapper', () {
    final AiNativeAppearances model = mixedAppearanceModel(text: true);
    final AiNativeGroup wrapper = mixedAppearanceOwner(model).group!.children.last as AiNativeGroup;
    final AiNativeTextDocument original = AiNativeTextDocument.decode(records: model.structure.drawing.records);
    final AiNativeTextDocument created = original.createStory(text: 'First\rSecond', frames: [AiNativeTextFrameDefinition.point(x: 10, y: 20)], appearanceParent: wrapper);
    check(created.referenceIssues).isEmpty();
    final AiNativeTextDocument revised = created.replaceText(story: created.stories.single, start: 0, end: 5, text: 'Changed');
    check(revised.stories.single.text).equals('Changed\rSecond');
    final AiNativeAppearances result = AiNativeAppearances.decode(
      structure: AiNativeStructure.decode(drawing: AiNativeDrawing.decode(records: revised.records)),
    );
    check(mixedAppearanceOwner(result).leaves.values.where((leaf) => leaf.text != null)).length.equals(1);
    final AiNativeAppearanceArtwork owner = mixedAppearanceOwner(result);
    check(() => result.removeArtwork(artwork: [owner])).throws<UnsupportedError>();
    check(
      () => result.replaceArtworkTrees(
        changes: [
          AiNativeAppearanceTreeChange(
            artwork: AiNativeAppearanceReplacement(
              artwork: owner,
              bytes: result.structure.drawing.records.program.bytes.sublist(owner.printingGroup.start, owner.printingGroup.end),
              bounds: AiBoundingBox(left: 0, bottom: 0, right: 240, top: 50),
            ),
            children: [for (final AiNativeItem child in owner.group!.children.take(3)) AiNativeAppearanceTreeChild.retain(source: child)],
          ),
        ],
      ),
    ).throws<UnsupportedError>();
    check(revised.stories.single.text).equals('Changed\rSecond');
    check(revised.removeStory(story: revised.stories.single).referenceIssues).isEmpty();
  });
}
