import 'dart:convert';

import 'package:aikit/aikit.dart';
import 'package:checks/checks.dart';
import 'package:test/test.dart';

import 'ai_native_artboard_brush_descriptors_test.dart' show artboardCalligraphicStyle;
import 'ai_native_artwork_resource_lifecycle_test.dart' show resourceLifecycleCreate, resourceLifecycleModel;
import 'ai_native_document_creation_test.dart' show newDocumentPath, newDocumentPdf, newDocumentSave;

/// Supplies literal producer layouts independently of the descriptor writer.
String brushLifecyclePayload(AiNativeBrushKind kind, {bool revised = false}) => switch (kind) {
  .calligraphic => revised ? '1 7 7 25 25 30 30 0 0 0 0' : '1 5 5 100 100 0 0 0 0 0 0',
  .art || .pattern => '2 / Tile/ / / / / 0 0/ ${revised ? '5 0.2 0.4 0.6' : '0 1'} / 1 0 1 0 1 0 0 0 1 1 0 1 25 25 1',
  .bristle => '0 4 0.5 ${revised ? '0.25' : '0.75'} 0.33 0.75 1.5 6 AI_BristleBrushLibary_CS5 05_Round_Fan',
};

/// Creates a complete new source with an independent tile declaration.
AiNativeBrushes brushLifecycleModel() => AiNativeBrushes.decode(structure: resourceLifecycleCreate(resourceLifecycleModel(), .brush, name: 'Tile').structure);

/// Adds one descriptor through the public byte-oriented lifecycle contract.
AiNativeBrushes brushLifecycleCreate(AiNativeBrushes model, AiNativeBrushKind kind, {String name = 'Brush (é)\\', bool listed = true}) =>
    model.create(kind: kind, nameBytes: latin1.encode(name), payloadBytes: latin1.encode(brushLifecyclePayload(kind)), listed: listed);

/// Compares the unchanged drawing despite edited setup byte offsets.
void _retainedBody(AiNativeBrushes before, AiNativeBrushes after) {
  final AiProgram first = before.structure.drawing.records.program;
  final AiProgram second = after.structure.drawing.records.program;
  check(second.bytes.sublist(second.bodyStart)).deepEquals(first.bytes.sublist(first.bodyStart));
}

/// Covers all descriptor families, native panel ownership and immutable failures.
void main() {
  for (final AiNativeBrushKind kind in AiNativeBrushKind.values) {
    test('creates revises saves and removes a complete ${kind.name} descriptor', () {
      final AiNativeBrushes source = brushLifecycleModel();
      final AiNativeBrushes first = brushLifecycleCreate(source, kind);
      check(first.brushes.single.kind).equals(kind);
      check(first.brushes.single.payloadBytes).deepEquals(latin1.encode(brushLifecyclePayload(kind)));
      check(first.order.single).identicalTo(first.brushes.single);
      final AiNativeBrushes revised = first.replaceUnused(brush: first.brushes.single, payloadBytes: latin1.encode(brushLifecyclePayload(kind, revised: true)));
      final AiPdfDocument saved = newDocumentSave(revised.structure.drawing.records, newDocumentPdf(blank: true));
      final AiNativeBrushes reopened = AiNativeBrushes.decode(
        structure: AiNativeStructure.decode(
          drawing: AiNativeDrawing.decode(
            records: AiNativeRecords.decode(program: AiProgram.decode(bytes: AiNativeData.extract(saved).single.bytes)),
          ),
        ),
      );
      check(reopened.brushes.single.nameBytes).deepEquals(first.brushes.single.nameBytes);
      check(reopened.brushes.single.payloadBytes).deepEquals(latin1.encode(brushLifecyclePayload(kind, revised: true)));
      final AiNativeBrushes removed = reopened.remove(brushes: reopened.brushes);
      check(removed.brushes).isEmpty();
      check(removed.order).isEmpty();
      check(AiNativeArtworkResources.decode(structure: removed.structure).resources).length.equals(1);
      _retainedBody(source, revised);
      _retainedBody(source, removed);
      check(source.brushes).isEmpty();
    });
  }

  test('authors a fixed calligraphic path and preserves its brush through complete lifecycle edits', () {
    final AiNativeCalligraphicPaint nib = AiNativeCalligraphicPaint(brushNameBytes: latin1.encode('Nib'), diameter: 1, roundness: 25, angle: 30);
    final AiNativeBrushes resources = brushLifecycleModel().create(kind: .calligraphic, nameBytes: nib.brushNameBytes, payloadBytes: nib.descriptorPayload);
    final AiNativeAppearances styles = AiNativeAppearances.decode(structure: resources.structure).createStyle(
      nameBytes: latin1.encode('Nib style'),
      execution: AiNativeAppearancePartDefinition(
        kind: .calligraphic,
        calligraphic: nib,
        colors: [
          AiColor(space: .rgb, channels: [0, .5, 1]),
        ],
        strokeWidth: 8,
      ),
    );
    final AiNativeAppearances created = styles.createPathArtwork(
      definition: AiNativePathDefinition(
        artwork: AiArtworkPath(segments: newDocumentPath(0).artwork.segments),
        bounds: newDocumentPath(0).bounds,
        identifierBytes: latin1.encode('nib-owner'),
      ),
      styleNameBytes: latin1.encode('Nib style'),
      printingBytes: latin1.encode('u 0 0.5 1 XA 8 w 10 10 m 30 10 L 30 30 L S U'),
      layer: styles.structure.drawing.records.program.layers.single,
    );
    check(created.styles.single.parts.single.kind).equals(.calligraphic);
    check(created.styles.single.parts.single.calligraphic!.roundness).equals(25);
    check(created.artworkFor(use: created.uses.single).path).isNotNull();
    final AiPdfDocument saved = newDocumentSave(created.structure.drawing.records, newDocumentPdf(blank: true));
    final AiNativeBrushes reopened = AiNativeBrushes.decode(
      structure: AiNativeStructure.decode(
        drawing: AiNativeDrawing.decode(
          records: AiNativeRecords.decode(program: AiProgram.decode(bytes: AiNativeData.extract(saved).single.bytes)),
        ),
      ),
    );
    check(() => reopened.remove(brushes: reopened.brushes)).throws<UnsupportedError>();
    final AiNativeAppearances appearances = AiNativeAppearances.decode(structure: reopened.structure);
    final AiNativeAppearances removed = appearances.removeArtwork(artwork: [appearances.artworkFor(use: appearances.uses.single)]);
    check(AiNativeBrushes.decode(structure: removed.structure).brushes.single.payloadBytes).deepEquals(nib.descriptorPayload);
    check(removed.styles).length.equals(1);
  });

  test('requires an exact fixed nib and a resolved descriptor for authored calligraphy', () {
    final AiNativeCalligraphicPaint nib = AiNativeCalligraphicPaint(brushNameBytes: [65], diameter: 2, roundness: 40, angle: -25);
    final AiNativeAppearances source = AiNativeAppearances.decode(structure: resourceLifecycleModel().structure);
    check(
      () => source.createStyle(
        nameBytes: [66],
        execution: AiNativeAppearancePartDefinition(
          kind: .calligraphic,
          calligraphic: nib,
          colors: [
            AiColor(space: .gray, channels: [0]),
          ],
        ),
      ),
    ).throws<UnsupportedError>();
    check(
      () => AiNativeAppearancePartDefinition(
        kind: .stroke,
        calligraphic: nib,
        colors: [
          AiColor(space: .gray, channels: [0]),
        ],
      ),
    ).throws<ArgumentError>();
    final AiNativeBrushes different = brushLifecycleCreate(brushLifecycleModel(), .calligraphic, name: 'A');
    final AiNativeAppearances mismatched = AiNativeAppearances.decode(structure: different.structure);
    check(
      () => mismatched.createStyle(
        nameBytes: [66],
        execution: AiNativeAppearancePartDefinition(
          kind: .calligraphic,
          calligraphic: nib,
          colors: [
            AiColor(space: .gray, channels: [0]),
          ],
        ),
      ),
    ).throws<UnsupportedError>();
    check(() => AiNativeCalligraphicPaint(brushNameBytes: [65], diameter: 0, roundness: 25, angle: 0)).throws<ArgumentError>();
    check(() => AiNativeCalligraphicPaint(brushNameBytes: [65], diameter: 1, roundness: 101, angle: 0)).throws<ArgumentError>();
    check(() => AiNativeCalligraphicPaint(brushNameBytes: [65], diameter: 1, roundness: 25, angle: double.nan)).throws<ArgumentError>();
  });

  test('keeps equal names independent across plug-ins and edits only panel membership', () {
    AiNativeBrushes source = brushLifecycleModel();
    for (final AiNativeBrushKind kind in AiNativeBrushKind.values) {
      source = brushLifecycleCreate(source, kind, name: 'Same');
    }
    final AiNativeBrushes reversed = source.setOrder(brushes: source.brushes.reversed.toList());
    check(reversed.order.map((brush) => brush.kind)).deepEquals(AiNativeBrushKind.values.reversed);
    for (final (int index, AiNativeBrushDescriptor brush) in reversed.brushes.indexed) {
      final AiNativeBrushDescriptor original = source.brushes[index];
      check(reversed.structure.drawing.records.program.bytes.sublist(brush.start, brush.end)).deepEquals(source.structure.drawing.records.program.bytes.sublist(original.start, original.end));
    }
    final AiNativeBrushes partial = reversed.setOrder(brushes: [reversed.brushes.last]);
    check(partial.brushes).length.equals(4);
    check(partial.order.single.kind).equals(.bristle);
    final AiNativeBrushes unlisted = partial.setOrder(brushes: []);
    check(unlisted.order).isEmpty();
    final AiNativeBrushes removed = unlisted.remove(brushes: [unlisted.brushes.first, unlisted.brushes.last]);
    check(removed.brushes.map((brush) => brush.kind)).deepEquals([AiNativeBrushKind.art, AiNativeBrushKind.pattern]);
    _retainedBody(source, removed);
  });

  test('retains unlisted names that cannot round-trip through panel delimiters', () {
    final AiNativeBrushes source = brushLifecycleModel();
    for (final String name in ['slash/name', ' padded ', 'line\nbreak']) {
      check(() => brushLifecycleCreate(source, .calligraphic, name: name)).throws<UnsupportedError>();
      final AiNativeBrushes hidden = brushLifecycleCreate(source, .calligraphic, name: name, listed: false);
      check(hidden.order).isEmpty();
      check(hidden.brushes.single.nameBytes).deepEquals(latin1.encode(name));
      check(() => hidden.setOrder(brushes: hidden.brushes)).throws<UnsupportedError>();
    }
  });

  test('refuses referenced descriptors even when the owning style has no users', () {
    final AiNativeBrushes source = brushLifecycleCreate(brushLifecycleModel(), .calligraphic, name: 'Referenced');
    final AiProgram program = source.structure.drawing.records.program;
    final int position = latin1.decode(program.bytes).indexOf('%%EndSetup');
    final AiProgram inserted = AiNativeEditor.apply(
      program: program,
      edits: [
        AiSourceEdit(
          start: position,
          end: position,
          bytes: latin1.encode(artboardCalligraphicStyle(name: 'Referenced')),
        ),
      ],
    );
    final AiNativeBrushes retained = AiNativeBrushes.decode(
      structure: AiNativeStructure.decode(
        drawing: AiNativeDrawing.decode(records: AiNativeRecords.decode(program: inserted)),
      ),
    );
    check(() => retained.remove(brushes: retained.brushes)).throws<UnsupportedError>();
    check(() => retained.replaceUnused(brush: retained.brushes.single, payloadBytes: latin1.encode(brushLifecyclePayload(.calligraphic, revised: true)))).throws<UnsupportedError>();
    check(retained.setOrder(brushes: []).order).isEmpty();
    check(retained.structure.drawing.records.program.bytes).deepEquals(inserted.bytes);
  });

  test('bounds new descriptor output and freezes authored nib names', () {
    final AiNativeBrushes original = brushLifecycleModel();
    final AiProgram program = original.structure.drawing.records.program;
    final AiNativeBrushes limited = AiNativeBrushes.decode(
      structure: AiNativeStructure.decode(
        drawing: AiNativeDrawing.decode(
          records: AiNativeRecords.decode(
            program: AiProgram.decode(
              bytes: program.bytes,
              limits: AiNativeLimits(maxDecodedBytes: program.bytes.length),
            ),
          ),
        ),
      ),
    );
    check(() => brushLifecycleCreate(limited, .calligraphic)).throws<FormatException>();
    check(() => limited.create(kind: .calligraphic, nameBytes: [65], payloadBytes: List.filled(program.bytes.length + 1, 32))).throws<AiLimitException>();
    check(limited.structure.drawing.records.program.bytes).deepEquals(program.bytes);
    final List<int> name = [65];
    final AiNativeCalligraphicPaint nib = AiNativeCalligraphicPaint(brushNameBytes: name, diameter: 1, roundness: 25, angle: 0);
    name[0] = 66;
    check(nib.brushNameBytes).deepEquals([65]);
    check(() => nib.brushNameBytes[0] = 67).throws<UnsupportedError>();
  });

  test('rejects missing tiles duplicate namespaces malformed payloads and foreign handles', () {
    final AiNativeBrushes source = AiNativeBrushes.decode(structure: resourceLifecycleModel().structure);
    check(() => brushLifecycleCreate(source, .art)).throws<UnsupportedError>();
    final AiNativeBrushes first = brushLifecycleCreate(source, .calligraphic);
    check(() => brushLifecycleCreate(first, .calligraphic)).throws<ArgumentError>();
    check(() => first.remove(brushes: [])).throws<ArgumentError>();
    check(() => source.remove(brushes: first.brushes)).throws<ArgumentError>();
    check(() => first.setOrder(brushes: [first.brushes.single, first.brushes.single])).throws<ArgumentError>();
    check(() => first.replaceUnused(brush: first.brushes.single, payloadBytes: latin1.encode('1 2 NaN'))).throws<FormatException>();
    check(() => source.create(kind: .calligraphic, nameBytes: [256], payloadBytes: [0])).throws<ArgumentError>();
    check(() => source.create(kind: .calligraphic, nameBytes: [65], payloadBytes: [256])).throws<ArgumentError>();
    final AiNativeBrushes next = first.setOrder(brushes: []);
    check(() => next.replaceUnused(brush: first.brushes.single, payloadBytes: first.brushes.single.payloadBytes)).throws<ArgumentError>();
    check(source.brushes).isEmpty();
  });
}
