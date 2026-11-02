import 'dart:convert';

import 'package:aikit/aikit.dart';
import 'package:checks/checks.dart';
import 'package:test/test.dart';

import 'ai_native_artwork_resource_lifecycle_test.dart' show resourceLifecycleCreate, resourceLifecycleModel;
import 'ai_native_document_creation_test.dart' show newDocumentPath, newDocumentPdf, newDocumentSave;

/// Authors a source pattern and an immutable style without body consumers.
AiNativeAppearances patternStyle({bool stroke = false, List<double> matrix = const [1, .2, -.3, 2, 13, -7]}) {
  final AiNativeArtworkResources resources = resourceLifecycleCreate(resourceLifecycleModel(), .pattern);
  return AiNativeAppearances.decode(structure: resources.structure).createStyle(
    nameBytes: latin1.encode('Pattern style'),
    execution: AiNativeAppearancePartDefinition(
      kind: stroke ? .stroke : .fill,
      pattern: AiNativePatternPaint(nameBytes: latin1.encode('Resource'), matrix: matrix),
    ),
  );
}

/// Creates one identified contour whose visible paint belongs to the pattern style.
AiNativeAppearances _patternOwner(AiNativeAppearances source, {String identity = 'pattern-owner'}) => source.createPathArtwork(
  definition: AiNativePathDefinition(
    artwork: AiArtworkPath(segments: newDocumentPath(0).artwork.segments, closed: true),
    bounds: newDocumentPath(0).bounds,
    identifierBytes: latin1.encode(identity),
  ),
  styleNameBytes: latin1.encode('Pattern style'),
  printingBytes: latin1.encode('u 0 g 0 0 m 10 0 L 10 10 L f U'),
  layer: source.structure.drawing.records.program.layers.single,
);

/// Checks typed placements, source namespace resolution and shared local encoding.
void main() {
  for (final bool stroke in [false, true]) {
    test('authors and reopens a literal ${stroke ? 'stroke' : 'fill'} pattern style', () {
      final AiNativeAppearances model = patternStyle(stroke: stroke);
      final AiNativePaintAssignment paint = model.styles.single.parts.single.paints.single.style.assignments.firstWhere((assignment) => assignment.pattern != null);
      check(paint.parameter).equals(stroke ? AiNativePaintParameter.strokeColor : AiNativePaintParameter.fillColor);
      check(paint.colors).isEmpty();
      check(paint.numbers).isNull();
      check(paint.pattern!.matrix).deepEquals([1, .2, -.3, 2, 13, -7]);
      check(paint.pattern!.nameBytes).deepEquals(latin1.encode('Resource'));
      check(() => AiNativePaintChange(assignment: paint, values: [])).throws<ArgumentError>();
      final AiPdfDocument saved = newDocumentSave(model.structure.drawing.records, newDocumentPdf(blank: true));
      final AiNativeRecords records = AiNativeRecords.decode(program: AiProgram.decode(bytes: AiNativeData.extract(saved).single.bytes));
      final AiNativeAppearances reopened = AiNativeAppearances.decode(
        structure: AiNativeStructure.decode(drawing: AiNativeDrawing.decode(records: records)),
      );
      check(reopened.styles.single.parts.single.paints.single.style.assignments.firstWhere((assignment) => assignment.pattern != null).pattern!.matrix).deepEquals(paint.pattern!.matrix);
      final AiNativeArtworkResources resources = AiNativeArtworkResources.decode(structure: reopened.structure);
      check(() => resources.remove(resources: resources.resources)).throws<UnsupportedError>();
    });
  }

  test('removes identified pattern owners while preserving independent declarations and styles', () {
    final AiNativeAppearances source = _patternOwner(patternStyle());
    final AiProgram before = source.structure.drawing.records.program;
    final AiNativeAppearances result = source.removeArtwork(artwork: [source.artworkFor(use: source.uses.single)]);
    final AiProgram after = result.structure.drawing.records.program;
    check(result.uses).isEmpty();
    check(after.bytes.sublist(0, after.bodyStart)).deepEquals(before.bytes.sublist(0, before.bodyStart));
    check(result.styles).length.equals(1);
    check(AiNativeArtworkResources.decode(structure: result.structure).resources).length.equals(1);
    check(source.uses).length.equals(1);
  });

  test('removes an ordinary identified neighbor without changing the pattern pair', () {
    final AiNativeAppearances styles = patternStyle();
    final AiNativeDrawing ordinary = styles.structure.drawing.createPath(
      definition: newDocumentPath(1),
      layer: styles.structure.drawing.records.program.layers.single,
    );
    final AiNativeAppearances before = _patternOwner(AiNativeAppearances.decode(structure: AiNativeStructure.decode(drawing: ordinary)));
    final AiNativeDrawing drawing = before.structure.drawing;
    final AiNativeAppearanceArtwork owner = before.artworkFor(use: before.uses.single);
    final List<int> pair = drawing.records.program.bytes.sublist(owner.start, owner.end);
    final AiNativeDrawing result = drawing.removePaths(paths: [drawing.paths.first]);
    final AiNativeAppearances after = AiNativeAppearances.decode(structure: AiNativeStructure.decode(drawing: result));
    final AiNativeAppearanceArtwork retained = after.artworkFor(use: after.uses.single);
    check(result.records.program.bytes.sublist(retained.start, retained.end)).deepEquals(pair);
  });

  test('rejects uncertain retained resource references to removed identities atomically', () {
    for (final AiNativeArtworkResourceKind kind in AiNativeArtworkResourceKind.values) {
      final AiNativeAppearances styles = patternStyle();
      final AiNativeArtworkResources resources = resourceLifecycleCreate(
        AiNativeArtworkResources.decode(structure: styles.structure),
        kind,
        name: 'pattern-owner',
      );
      final AiNativeAppearances source = _patternOwner(AiNativeAppearances.decode(structure: resources.structure));
      final List<int> original = [...source.structure.drawing.records.program.bytes];
      check(() => source.removeArtwork(artwork: [source.artworkFor(use: source.uses.single)])).throws<UnsupportedError>();
      check(source.structure.drawing.records.program.bytes).deepEquals(original);
    }
  });

  test('requires resolved pattern names and exclusive literal paint inputs', () {
    final AiNativePatternPaint pattern = AiNativePatternPaint(nameBytes: [65], matrix: [1, 0, 0, 1, 0, 0]);
    final AiNativeAppearances source = AiNativeAppearances.decode(structure: resourceLifecycleModel().structure);
    check(
      () => source.createStyle(
        nameBytes: [66],
        execution: AiNativeAppearancePartDefinition(kind: .fill, pattern: pattern),
      ),
    ).throws<UnsupportedError>();
    check(source.styles).isEmpty();
    check(() => AiNativeAppearancePartDefinition(kind: .blend, pattern: pattern)).throws<ArgumentError>();
    check(
      () => AiNativeAppearancePartDefinition(
        kind: .fill,
        pattern: pattern,
        colors: [
          AiColor(space: .gray, channels: [0]),
        ],
      ),
    ).throws<ArgumentError>();
    check(() => AiNativePatternPaint(nameBytes: [], matrix: [1, 0, 0, 1, 0, 0])).throws<ArgumentError>();
    check(() => AiNativePatternPaint(nameBytes: [256], matrix: [1, 0, 0, 1, 0, 0])).throws<ArgumentError>();
    check(() => AiNativePatternPaint(nameBytes: [65], placement: [0, 0, 1, 1, 0, 2, 0, 0, 0], matrix: [1, 0, 0, 1, 0, 0])).throws<ArgumentError>();
    check(() => AiNativePatternPaint(nameBytes: [65], matrix: [1, 0, 0, double.nan, 0, 0])).throws<ArgumentError>();
  });

  test('freezes placement bytes and retains noncanonical producer operands', () {
    final List<int> name = [65];
    final List<double> matrix = [1, 0, 0, 1, 0, 0];
    final List<double> placement = [4, -3, 2, .5, 45, 1, 30, 15, 60];
    final AiNativePatternPaint value = AiNativePatternPaint(nameBytes: name, placement: placement, matrix: matrix);
    name[0] = 66;
    matrix[0] = 2;
    placement[0] = 0;
    check(value.nameBytes).deepEquals([65]);
    check(value.matrix).deepEquals([1, 0, 0, 1, 0, 0]);
    check(value.placement).deepEquals([4, -3, 2, .5, 45, 1, 30, 15, 60]);
  });

  test('shares bounded local vector serialization without adding mask envelopes', () {
    final AiNativeArtworkResources source = resourceLifecycleModel();
    final List<AiNativeAppearanceElementDefinition> elements = [
      AiNativeAppearancePathDefinition(
        definition: AiNativePathDefinition(
          artwork: AiArtworkPath(
            segments: [
              AiPathSegment(operator: 'm', coordinates: [0, 0]),
              AiPathSegment(operator: 'L', coordinates: [10, 0]),
              AiPathSegment(operator: 'L', coordinates: [10, 10]),
            ],
            closed: true,
            fill: AiColor(space: .gray, channels: [.5]),
          ),
          bounds: AiBoundingBox(left: 0, bottom: 0, right: 10, top: 10),
        ),
      ),
    ];
    final List<int> bytes = AiNativeArtworkResources.encodeVectorArtwork(records: source.structure.drawing.records, elements: elements);
    check(latin1.decode(bytes).contains('X=')).isFalse();
    final AiNativeArtworkResources created = source.create(kind: .pattern, nameBytes: [65], artworkBytes: bytes, bounds: AiBoundingBox(left: 0, bottom: 0, right: 10, top: 10));
    final AiNativeDrawing local = created.qualifiedArtwork(resource: created.resources.single);
    check(local.paths).length.equals(1);
    check(local.paths.single.isPrivate).isTrue();
    check(() => source.qualifiedArtwork(resource: created.resources.single)).throws<ArgumentError>();
    check(created.structure.drawing.paths).isEmpty();
  });
}
