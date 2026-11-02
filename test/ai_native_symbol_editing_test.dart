import 'dart:convert';

import 'package:aikit/aikit.dart';
import 'package:checks/checks.dart';
import 'package:test/test.dart';

import 'ai_native_document_creation_test.dart' show newDocumentPath, newDocumentRecords;

/// Builds a complete static instance and a separately declared local master.
AiNativeAppearances editableSymbol() {
  AiNativeArtworkResources resources = AiNativeArtworkResources.decode(
    structure: AiNativeStructure.decode(drawing: AiNativeDrawing.decode(records: newDocumentRecords(blank: true))),
  );
  resources = resources.create(
    kind: .symbol,
    nameBytes: utf8.encode('Étoile'),
    artworkBytes: AiNativeArtworkResources.encodeVectorArtwork(
      records: resources.structure.drawing.records,
      elements: [
        AiNativeAppearancePathDefinition(
          definition: AiNativePathDefinition(artwork: newDocumentPath(0).artwork, bounds: newDocumentPath(0).bounds),
        ),
      ],
    ),
  );
  final AiNativeAppearances model = AiNativeAppearances.decode(structure: resources.structure).createStyle(
    nameBytes: ascii.encode('Instance'),
    execution: AiNativeAppearancePartDefinition(kind: .conduit),
  );
  return model.createGroupArtwork(
    definition: AiNativeAppearanceGroupDefinition(
      children: [],
      styleNameBytes: ascii.encode('Instance'),
      identifierBytes: ascii.encode('instance'),
      leaf: AiNativeAppearanceSymbolDefinition(nameBytes: utf8.encode('Étoile'), relativeTransform: [2, 0.5, 0.25, -3, 10, 20]),
    ),
    printingBytes: ascii.encode('u\n0 g\n0 0 m 10 0 L 10 10 L f\nU'),
    bounds: AiBoundingBox(left: 0, bottom: 0, right: 240, top: 50),
    layer: model.structure.drawing.records.program.layers.single,
  );
}

void main() {
  test('creates a literal shared reference and renames its master atomically', () {
    final AiNativeAppearances appearance = editableSymbol();
    final AiNativeAppearanceArtwork owner = appearance.artworkFor(use: appearance.uses.singleWhere((use) => !use.instruction.isPrivate));
    check(owner.leaves.values.single.symbol).isNotNull();
    final AiNativeArtworkResources resources = AiNativeArtworkResources.decode(structure: appearance.structure);
    final AiNativeArtworkResource master = resources.resources.single;
    final AiNativeSymbols symbols = AiNativeSymbols.decode(artworkResources: resources);
    check(symbols.instances.single.relativeTransform!).deepEquals([2, 0.5, 0.25, -3, 10, 20]);
    check(symbols.instances.single.definition).equals(master);
    check(() => resources.remove(resources: [master])).throws<UnsupportedError>();
    final AiNativeArtworkResources renamed = resources.renameSymbol(resource: master, nameBytes: utf8.encode('Renommé'));
    final AiNativeSymbolInstance instance = AiNativeSymbols.decode(artworkResources: renamed).instances.single;
    check(utf8.decode(instance.nameBytes!)).equals('Renommé');
    check(instance.definition).equals(renamed.resources.single);
    check(utf8.decode(master.nameBytes)).equals('Étoile');
    check(() => renamed.renameSymbol(resource: master, nameBytes: ascii.encode('stale'))).throws<ArgumentError>();
    final AiNativeAppearances revised = AiNativeAppearances.decode(structure: renamed.structure);
    final AiNativeAppearances removed = revised.removeArtwork(artwork: [revised.artworkFor(use: revised.uses.singleWhere((use) => !use.instruction.isPrivate))]);
    final AiNativeArtworkResources unused = AiNativeArtworkResources.decode(structure: removed.structure);
    check(unused.remove(resources: unused.resources).resources).isEmpty();
  });

  test('rejects singular or nonportable instance matrices before authoring', () {
    for (final List<double> matrix in [
      [1, 0, 1, 0, 0, 0],
      [1, 0, 0, 1, double.infinity, 0],
      [1, 0, 0],
    ]) {
      check(() => AiNativeAppearanceSymbolDefinition(nameBytes: [65], relativeTransform: matrix)).throws<ArgumentError>();
    }
    final List<int> name = [65];
    final List<double> matrix = [1, 0, 0, 1, 0, 0];
    final AiNativeAppearanceSymbolDefinition definition = AiNativeAppearanceSymbolDefinition(nameBytes: name, relativeTransform: matrix);
    name[0] = 66;
    matrix[0] = 2;
    check(definition.nameBytes).deepEquals([65]);
    check(definition.relativeTransform.first).equals(1);
  });
  test('rejects unknown instance fields and colliding master names atomically', () {
    final AiNativeAppearances appearance = editableSymbol();
    final String source = latin1.decode(appearance.structure.drawing.records.program.bytes);
    final String opaque = source.replaceFirst(' /RTransformMatrix , ;', ' /RTransformMatrix , 1 /Dynamic , ;');
    check(opaque == source).isFalse();
    final AiNativeArtworkResources unsupported = AiNativeArtworkResources.decode(
      structure: AiNativeStructure.decode(
        drawing: AiNativeDrawing.decode(
          records: AiNativeRecords.decode(program: AiProgram.decode(bytes: latin1.encode(opaque))),
        ),
      ),
    );
    check(() => unsupported.renameSymbol(resource: unsupported.resources.single, nameBytes: [65])).throws<UnsupportedError>();
    check(latin1.decode(unsupported.structure.drawing.records.program.bytes)).equals(opaque);
    final AiNativeArtworkResources initial = AiNativeArtworkResources.decode(structure: appearance.structure);
    final AiNativeArtworkResource original = initial.resources.single;
    final AiNativeArtworkResources withUnused = initial.create(
      kind: .symbol,
      nameBytes: [65],
      artworkBytes: initial.structure.drawing.records.program.bytes.sublist(original.artworkStart, original.artworkEnd),
    );
    check(() => withUnused.renameSymbol(resource: withUnused.resources.first, nameBytes: [65])).throws<ArgumentError>();
    check(withUnused.resources).length.equals(2);
  });
}
