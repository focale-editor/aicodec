import 'dart:convert';

import 'package:checks/checks.dart';
import 'package:illustratorkit/illustratorkit.dart';
import 'package:test/test.dart';

import 'ai_native_document_creation_test.dart' show newDocumentPath, newDocumentPdf, newDocumentRecords, newDocumentSave;

/// Installs a compound monochrome source independently of a brush application.
AiNativeBrushes artworkBrushResources() {
  final AiNativeRecords records = newDocumentRecords(blank: true);
  final AiNativePathDefinition path = newDocumentPath(0);
  final AiNativeArtworkResources resources = AiNativeArtworkResources.decode(
    structure: AiNativeStructure.decode(drawing: AiNativeDrawing.decode(records: records)),
  );
  return AiNativeBrushes.decode(
    structure: resources
        .create(
          kind: .brush,
          nameBytes: ascii.encode('Tile'),
          artworkBytes: AiNativeArtworkResources.encodeBrushArtwork(
            records: records,
            bounds: path.bounds,
            contours: [
              AiNativePathDefinition(
                artwork: AiArtworkPath(
                  segments: path.artwork.segments,
                  closed: true,
                  fill: AiColor(space: .gray, channels: [0]),
                ),
                bounds: path.bounds,
              ),
            ],
          ),
        )
        .structure,
  );
}

/// Exercises owned tiles, descriptors, appearances and complete file saves.
void main() {
  for (final AiNativeBrushKind kind in [AiNativeBrushKind.art, AiNativeBrushKind.pattern]) {
    test('authors and retains native ${kind.name} source and application', () {
      final AiNativeArtworkBrushPaint paint = AiNativeArtworkBrushPaint(
        kind: kind,
        brushNameBytes: ascii.encode('Brush'),
        scaling: kind == .art ? 1 : 1.5,
        spacing: kind == .art ? 0 : .25,
        adjustment: kind == .art ? 0 : 1,
      );
      final List<List<int>> tiles = [ascii.encode('Tile'), [], [], if (kind == .pattern) ascii.encode('Tile') else [], []];
      final AiNativeBrushes brushes = artworkBrushResources().create(
        kind: kind,
        nameBytes: paint.brushNameBytes,
        payloadBytes: paint.descriptorPayload(tileNames: tiles),
      );
      final AiNativeAppearances styles = AiNativeAppearances.decode(structure: brushes.structure).createStyle(
        nameBytes: ascii.encode('Style'),
        execution: AiNativeAppearancePartDefinition(
          kind: .artworkBrush,
          artworkBrush: paint,
          strokeWidth: 4,
          colors: [
            AiColor(space: .rgb, channels: [.2, .4, .6]),
          ],
        ),
      );
      final AiNativePathDefinition path = newDocumentPath(0);
      final AiNativeAppearances created = styles.createPathArtwork(
        definition: AiNativePathDefinition(
          artwork: AiArtworkPath(segments: path.artwork.segments),
          bounds: path.bounds,
        ),
        styleNameBytes: ascii.encode('Style'),
        printingBytes: ascii.encode('u 0 g 10 10 m 30 10 L 30 30 L f U'),
        layer: styles.structure.drawing.records.program.layers.single,
      );
      check(created.styles.single.parts.single.artworkBrush!.kind).equals(kind);
      check(created.artworkFor(use: created.uses.single).path).isNotNull();
      final AiPdfDocument saved = newDocumentSave(created.structure.drawing.records, newDocumentPdf(blank: true));
      final AiNativeRecords reopened = AiNativeRecords.decode(program: AiProgram.decode(bytes: AiNativeData.extract(saved).single.bytes));
      final AiNativeAppearances actual = AiNativeAppearances.decode(
        structure: AiNativeStructure.decode(drawing: AiNativeDrawing.decode(records: reopened)),
      );
      check(actual.styles.single.parts.single.artworkBrush!.spacing).equals(paint.spacing);
      check(actual.artworkFor(use: actual.uses.single).path).isNotNull();
      final AiNativeBrushes retained = AiNativeBrushes.decode(structure: actual.structure);
      check(() => retained.remove(brushes: retained.brushes)).throws<UnsupportedError>();
      check(AiNativeArtworkResources.decode(structure: actual.structure).resources.single.groups.single.compound).isTrue();
    });

    test('rejects missing and mismatched ${kind.name} descriptors atomically', () {
      final AiNativeBrushes source = artworkBrushResources();
      final AiNativeArtworkBrushPaint paint = AiNativeArtworkBrushPaint(kind: kind, brushNameBytes: ascii.encode('Brush'));
      final AiNativeAppearancePartDefinition definition = AiNativeAppearancePartDefinition(
        kind: .artworkBrush,
        artworkBrush: paint,
        colors: [
          AiColor(space: .gray, channels: [0]),
        ],
      );
      check(() => AiNativeAppearances.decode(structure: source.structure).createStyle(nameBytes: [65], execution: definition)).throws<UnsupportedError>();
      final String payload = latin1.decode(paint.descriptorPayload(tileNames: [ascii.encode('Tile'), [], [], [], []]));
      final AiNativeBrushes mismatch = source.create(kind: kind, nameBytes: paint.brushNameBytes, payloadBytes: latin1.encode(payload.replaceFirst('0 0/ 0 1', '3 3/ 0 1')));
      check(() => AiNativeAppearances.decode(structure: mismatch.structure).createStyle(nameBytes: [65], execution: definition)).throws<UnsupportedError>();
      check(source.brushes).isEmpty();
    });
  }
  test('rejects ambiguous tile names and mismatched part payloads', () {
    final AiNativeArtworkBrushPaint paint = AiNativeArtworkBrushPaint(kind: .art, brushNameBytes: [65]);
    check(() => paint.descriptorPayload(tileNames: [ascii.encode('a/b'), [], [], [], []])).throws<ArgumentError>();
    check(
      () => AiNativeAppearancePartDefinition(
        kind: .stroke,
        artworkBrush: paint,
        colors: [
          AiColor(space: .gray, channels: [0]),
        ],
      ),
    ).throws<ArgumentError>();
    check(() => AiNativeArtworkBrushPaint(kind: .art, brushNameBytes: [65], spacing: .2)).throws<ArgumentError>();
    check(
      () => AiNativeAppearancePartDefinition(
        kind: .artworkBrush,
        artworkBrush: paint,
        pattern: AiNativePatternPaint(nameBytes: [66], matrix: [1, 0, 0, 1, 0, 0]),
      ),
    ).throws<ArgumentError>();
  });
}
