import 'dart:convert';

import 'package:checks/checks.dart';
import 'package:illustratorkit/illustratorkit.dart';
import 'package:test/test.dart';

import 'ai_native_document_creation_test.dart' show newDocumentPath, newDocumentPdf, newDocumentRecords, newDocumentSave;

/// Explicit process stops and interpolation supplied independently of the kit.
AiNativeAppearances gradientPaintModel({bool radial = false}) {
  final AiNativeGradientResources gradients = AiNativeGradientResources.decode(records: newDocumentRecords(blank: true)).create(
    nameBytes: latin1.encode('Gradient (shared)'),
    radial: radial,
    stops: [
      for (final double position in [0, 100])
        AiNativeGradientStop(
          color: AiNativeGradientColor(kind: .gray, components: [position / 100]),
          position: position,
        ),
    ],
    ramps: [
      AiNativeGradientRamp(
        kind: .gray,
        channels: [
          AiNativeGradientChannel.samples(values: [0, 85, 170, 255]),
        ],
      ),
    ],
  );
  return AiNativeAppearances.decode(
    structure: AiNativeStructure.decode(drawing: AiNativeDrawing.decode(records: gradients.records)),
  );
}

/// Deliberately asymmetric relative placement, including shear and aspect ratio.
AiNativeGradientPaint gradientPaintPlacement({List<int>? name}) => AiNativeGradientPaint(
  nameBytes: name ?? latin1.encode('Gradient (shared)'),
  origin: [-.25, .125],
  angle: 37,
  length: 1.25,
  matrix: [1, .2, -.3, 2, .1, -.4],
  aspectRatio: .75,
);

/// Creates one complete owner while keeping the native contour editable.
AiNativeAppearances gradientPaintOwner({bool stroke = false, bool radial = false}) {
  final AiNativeAppearances styles = gradientPaintModel(radial: radial).createStyle(
    nameBytes: latin1.encode('Gradient style'),
    execution: AiNativeAppearancePartDefinition(
      kind: .chain,
      children: [
        AiNativeAppearanceChild.create(
          definition: AiNativeAppearancePartDefinition(kind: stroke ? .stroke : .fill, gradient: gradientPaintPlacement()),
        ),
      ],
    ),
  );
  return styles.createPathArtwork(
    definition: AiNativePathDefinition(
      artwork: AiArtworkPath(segments: newDocumentPath(0).artwork.segments, closed: true),
      bounds: newDocumentPath(0).bounds,
      identifierBytes: latin1.encode('gradient-owner'),
    ),
    styleNameBytes: latin1.encode('Gradient style'),
    printingBytes: latin1.encode('u 0 g 0 0 m 10 0 L 10 10 L f U'),
    layer: styles.structure.drawing.records.program.layers.single,
  );
}

/// Resolves the selected style's only positional gradient.
AiNativeGradient _gradient(AiNativeAppearance style) => style.parts.last.paints.single.style.gradients.single;

/// Covers creation, resource references, complete saving and immutable rejection.
void main() {
  for (final bool radial in [false, true]) {
    for (final bool stroke in [false, true]) {
      test('authors ${radial ? 'radial' : 'linear'} ${stroke ? 'stroke' : 'fill'} style with retained relative geometry', () {
        final AiNativeAppearances model = gradientPaintOwner(stroke: stroke, radial: radial);
        final AiNativeGradient gradient = _gradient(model.styles.single);
        check(gradient.onStroke).equals(stroke);
        check(gradient.closing.numbers).isNotNull().deepEquals([if (stroke) 1 else 0]);
        check(gradient.geometry.flag).equals(2);
        check(gradient.geometry.relativeToArtwork).isTrue();
        check(gradient.geometry.origin).deepEquals([-.25, .125]);
        check(gradient.geometry.angle).equals(37);
        check(gradient.geometry.length).equals(1.25);
        check(gradient.geometry.matrix).deepEquals([1, .2, -.3, 2, .1, -.4]);
        check(gradient.geometry.aspectRatio).equals(.75);
        check(gradient.paths).isEmpty();
        final AiNativeResourceUse reference = model.structure.resourceUses.singleWhere((use) => use.kind == .gradient);
        check(reference.resolution).equals(AiNativeResourceResolution.resolved);
        check(gradient.geometry.nameBytes).deepEquals(reference.nameBytes);
        final AiPdfDocument saved = newDocumentSave(model.structure.drawing.records, newDocumentPdf(blank: true));
        final AiNativeRecords records = AiNativeRecords.decode(program: AiProgram.decode(bytes: AiNativeData.extract(saved).single.bytes));
        final AiNativeAppearances reopened = AiNativeAppearances.decode(
          structure: AiNativeStructure.decode(drawing: AiNativeDrawing.decode(records: records)),
        );
        check(_gradient(reopened.styles.single).geometry.matrix).deepEquals(gradient.geometry.matrix);
        check(reopened.artworkFor(use: reopened.uses.single).path).isNotNull();
        final AiNativeGradientResources resources = AiNativeGradientResources.decode(records: records);
        check(() => resources.remove(definition: resources.definitions.first)).throws<UnsupportedError>();
      });
    }
  }

  test('replaces a retained paint child and removes the complete owner without dropping its resource', () {
    final AiNativeAppearances source = gradientPaintOwner();
    final AiNativeAppearanceArtwork owner = source.artworkFor(use: source.uses.single);
    final AiNativeAppearances changed = source.updateShared(
      appearance: source.styles.single,
      parts: [
        AiNativeAppearancePartChange(
          part: source.styles.single.parts.first,
          children: [
            AiNativeAppearanceChild.create(
              definition: AiNativeAppearancePartDefinition(kind: .stroke, gradient: gradientPaintPlacement()),
            ),
          ],
        ),
      ],
      artwork: [AiNativeAppearanceReplacement(artwork: owner, bytes: latin1.encode('u 1 g 0 0 m 10 0 L 10 10 L f 0 g U'), bounds: newDocumentPath(0).bounds)],
    );
    check(_gradient(changed.styles.single).onStroke).isTrue();
    check(_gradient(source.styles.single).onStroke).isFalse();
    final AiNativeAppearances removed = changed.removeArtwork(artwork: [changed.artworkFor(use: changed.uses.single)]);
    check(removed.uses).isEmpty();
    check(AiNativeGradientResources.decode(records: removed.structure.drawing.records).definitions).isNotEmpty();
  });

  test('rejects unresolved resources and conflicting paint inputs atomically', () {
    final AiNativeAppearances source = gradientPaintModel();
    final List<int> bytes = [...source.structure.drawing.records.program.bytes];
    check(
      () => source.createStyle(
        nameBytes: [65],
        execution: AiNativeAppearancePartDefinition(
          kind: .fill,
          gradient: gradientPaintPlacement(name: [66]),
        ),
      ),
    ).throws<UnsupportedError>();
    check(source.structure.drawing.records.program.bytes).deepEquals(bytes);
    final AiNativeGradientPaint paint = gradientPaintPlacement();
    check(() => AiNativeAppearancePartDefinition(kind: .blend, gradient: paint)).throws<ArgumentError>();
    check(
      () => AiNativeAppearancePartDefinition(
        kind: .fill,
        gradient: paint,
        colors: [
          AiColor(space: .gray, channels: [0]),
        ],
      ),
    ).throws<ArgumentError>();
    check(
      () => AiNativeAppearancePartDefinition(
        kind: .stroke,
        gradient: paint,
        pattern: AiNativePatternPaint(nameBytes: [65], matrix: [1, 0, 0, 1, 0, 0]),
      ),
    ).throws<ArgumentError>();
  });

  test('freezes caller data and rejects nonportable or singular placements', () {
    final List<int> name = [65, 0, 255];
    final List<double> origin = [0, 0];
    final List<double> matrix = [1, 0, 0, 1, 0, 0];
    final AiNativeGradientPaint paint = AiNativeGradientPaint(nameBytes: name, origin: origin, angle: 0, length: 1, matrix: matrix, aspectRatio: 1);
    name[0] = 66;
    origin[0] = 1;
    matrix[0] = 2;
    check(paint.nameBytes).deepEquals([65, 0, 255]);
    check(paint.origin).deepEquals([0, 0]);
    check(paint.matrix).deepEquals([1, 0, 0, 1, 0, 0]);
    check(() => paint.nameBytes[0] = 0).throws<UnsupportedError>();
    check(paint.matrix.clear).throws<UnsupportedError>();
    for (final List<double> values in [
      [1, 0, 0, 0, 0, 0],
      [1, 0, 0, 1, 0],
      [double.nan, 0, 0, 1, 0, 0],
    ]) {
      check(() => AiNativeGradientPaint(nameBytes: [65], origin: [0, 0], angle: 0, length: 1, matrix: values, aspectRatio: 1)).throws<ArgumentError>();
    }
    for (final double value in [0, -1, double.infinity, 9007199254740992]) {
      check(() => AiNativeGradientPaint(nameBytes: [65], origin: [0, 0], angle: 0, length: value, matrix: paint.matrix, aspectRatio: 1)).throws<ArgumentError>();
      check(() => AiNativeGradientPaint(nameBytes: [65], origin: [0, 0], angle: 0, length: 1, matrix: paint.matrix, aspectRatio: value)).throws<ArgumentError>();
    }
  });

  test('rejects style output beyond the source byte budget atomically', () {
    final List<int> bytes = gradientPaintModel().structure.drawing.records.program.bytes;
    final AiNativeRecords records = AiNativeRecords.decode(
      program: AiProgram.decode(
        bytes: bytes,
        limits: AiNativeLimits(maxDecodedBytes: bytes.length + 100),
      ),
    );
    final AiNativeAppearances source = AiNativeAppearances.decode(
      structure: AiNativeStructure.decode(drawing: AiNativeDrawing.decode(records: records)),
    );
    check(
      () => source.createStyle(
        nameBytes: [65],
        execution: AiNativeAppearancePartDefinition(kind: .fill, gradient: gradientPaintPlacement()),
      ),
    ).throws<AiLimitException>();
    check(source.structure.drawing.records.program.bytes).deepEquals(bytes);
  });
}
