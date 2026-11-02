import 'dart:convert';

import 'package:aikit/aikit.dart';
import 'package:checks/checks.dart';
import 'package:test/test.dart';

import 'ai_native_appearance_editing_test.dart' show appearanceEditingModel;
import 'ai_native_document_creation_test.dart' show newDocumentPath, newDocumentPdf, newDocumentRecords, newDocumentSave;
import 'ai_native_path_artwork_test.dart' show artworkStates;

/// A retained pair of independent identified ordinary paths and one unused style.
AiNativeAppearances _model() =>
    AiNativeAppearances.decode(
      structure: AiNativeStructure.decode(drawing: AiNativeDrawing.decode(records: newDocumentRecords())),
    ).createStyle(
      nameBytes: ascii.encode('Converted'),
      execution: AiNativeAppearancePartDefinition(
        kind: .fill,
        colors: [
          AiColor(space: .rgb, channels: [0, 1, 0]),
        ],
      ),
    );

/// Supplies separate editable geometry and complete printing without new metadata.
AiNativeAppearances _convert(AiNativeAppearances model, {AiNativePath? path, String name = 'Converted', AiArtworkPath? artwork}) => model.convertPathArtwork(
  path: path ?? model.structure.drawing.paths.first,
  artwork: artwork ?? AiArtworkPath(segments: newDocumentPath(0).artwork.segments, closed: true, locked: true),
  bounds: newDocumentPath(0).bounds,
  styleNameBytes: ascii.encode(name),
  printingBytes: ascii.encode('u\n0 1 0 Xa\n4 w\n10 10 m 30 10 L 30 30 L f\nU'),
  hidden: true,
);

/// Checks identity-preserving promotion independently of host projections.
void main() {
  test('converts an ordinary path in place and preserves source metadata and neighbors', () {
    final AiNativeAppearances source = _model();
    final AiNativeDrawing before = source.structure.drawing;
    final AiNativeObject original = AiNativeObjects.decode(drawing: before).forSource(before.paths.first);
    final AiNativeAppearances result = _convert(source);
    final AiNativeDrawing after = result.structure.drawing;
    final AiNativeAppearanceArtwork owner = result.artworkFor(use: result.uses.single);
    final AiNativeObject converted = AiNativeObjects.decode(drawing: after).forSource(owner.path!);
    check(converted.identifier!.bytes).deepEquals(original.identifier!.bytes);
    check(after.records.program.bytes.sublist(converted.dictionary!.start, converted.end)).deepEquals(before.records.program.bytes.sublist(original.dictionary!.start, original.end));
    check(owner.path!.isPrivate).isTrue();
    check(owner.path!.paint.operator).equals('n');
    check(owner.group).isNull();
    check(after.paths.last.isPrivate).isFalse();
    check(after.records.program.bytes.sublist(after.paths.last.start, after.paths.last.end)).deepEquals(before.records.program.bytes.sublist(before.paths.last.start, before.paths.last.end));
    check(result.structure.identifiers.map((id) => latin1.decode(id.bytes))).deepEquals(source.structure.identifiers.map((id) => latin1.decode(id.bytes)));
    for (final bool native in [false, true]) {
      check(artworkStates(after, native: native).last).deepEquals(artworkStates(before, native: native).last);
    }
    final AiPdfDocument saved = newDocumentSave(after.records, newDocumentPdf());
    final AiNativeAppearances reopened = appearanceEditingModel(source: latin1.decode(AiNativeData.extract(saved).single.bytes));
    check(reopened.artworkFor(use: reopened.uses.single).dictionary!['AI10_ArtUID']!.container!.entries.single.stringBytes!).deepEquals(original.identifier!.bytes);
    check(source.uses).isEmpty();
  });

  test('restores inherited neighbor state in both interpretations', () {
    final AiNativeAppearances base = _model();
    final String source = latin1.decode(base.structure.drawing.records.program.bytes).replaceFirst('%%PageTrailer', '50 0 m 60 0 L 60 10 L f\n%%PageTrailer');
    final AiNativeAppearances model = appearanceEditingModel(source: source);
    final AiNativeAppearances result = _convert(model, path: model.structure.drawing.paths[1]);
    for (final bool native in [false, true]) {
      check(artworkStates(result.structure.drawing, native: native).last).deepEquals(artworkStates(model.structure.drawing, native: native).last);
    }
  });

  test('converts successive paths beside an existing complete pair', () {
    final AiNativeAppearances first = _convert(_model());
    final AiNativeAppearanceArtwork previous = first.artworkFor(use: first.uses.single);
    final AiNativeAppearances second = _convert(first, path: first.structure.drawing.paths.last);
    final AiNativeAppearanceArtwork retained = second.artworkFor(use: second.uses.first);
    check(second.structure.drawing.records.program.bytes.sublist(retained.start, retained.end)).deepEquals(first.structure.drawing.records.program.bytes.sublist(previous.start, previous.end));
    check(second.uses).length.equals(2);
    check(second.uses.map((use) => second.artworkFor(use: use).path!.isPrivate)).every((value) => value.isTrue());
  });

  test('retains absent metadata and each source point-count convention', () {
    for (final bool counted in [false, true]) {
      final AiNativeAppearances source = _model();
      final AiNativeDrawing drawing = source.structure.drawing.createPath(
        definition: AiNativePathDefinition(artwork: newDocumentPath(0).artwork, bounds: newDocumentPath(0).bounds, counted: counted),
        layer: source.structure.drawing.records.program.layers.last,
      );
      final AiNativeAppearances model = AiNativeAppearances.decode(structure: AiNativeStructure.decode(drawing: drawing));
      final AiNativeAppearances result = _convert(model, path: drawing.paths.last);
      final AiNativeAppearanceArtwork owner = result.artworkFor(use: result.uses.single);
      check(owner.dictionary).isNull();
      check(result.structure.identifiers).length.equals(model.structure.identifiers.length);
      check(result.structure.drawing.items.whereType<AiNativeInstruction>().where((item) => item.isPrivate && item.operator == 'As')).length.equals(counted ? 1 : 0);
    }
  });

  test('rejects stale private painted and unresolved inputs atomically', () {
    final AiNativeAppearances source = _model();
    final List<int> bytes = source.structure.drawing.records.program.bytes.toList();
    check(() => _convert(source, path: _model().structure.drawing.paths.first)).throws<ArgumentError>();
    check(() => _convert(source, artwork: newDocumentPath(0).artwork)).throws<ArgumentError>();
    check(() => _convert(source, name: 'Missing')).throws<UnsupportedError>();
    final AiNativeAppearances converted = _convert(source);
    check(() => _convert(converted, path: converted.artworkFor(use: converted.uses.single).path)).throws<UnsupportedError>();
    check(source.structure.drawing.records.program.bytes).deepEquals(bytes);
  });
}
