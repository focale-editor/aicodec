import 'dart:convert';

import 'package:aikit/aikit.dart';
import 'package:checks/checks.dart';
import 'package:test/test.dart';

import 'ai_native_appearance_artwork_test.dart' show appearanceArtworkSource;
import 'ai_native_appearance_editing_test.dart' show appearanceAssignment, appearanceEditingModel;
import 'ai_native_appearance_graph_test.dart' show newAppearanceFill;
import 'ai_native_document_creation_test.dart' show newDocumentPdf, newDocumentRecords, newDocumentSave;

/// Builds a resource inventory without inventing a preexisting style or user.
AiNativeAppearances _new({bool blank = false}) => AiNativeAppearances.decode(
  structure: AiNativeStructure.decode(
    drawing: AiNativeDrawing.decode(records: newDocumentRecords(blank: blank)),
  ),
);

/// Creates an explicit stack and whole-object blend with ordinary process parts.
AiNativeAppearancePartDefinition _execution() => AiNativeAppearancePartDefinition(
  kind: .chain,
  children: [
    AiNativeAppearanceChild.create(
      definition: AiNativeAppearancePartDefinition(
        kind: .stack,
        children: [
          AiNativeAppearanceChild.create(definition: newAppearanceFill()),
          AiNativeAppearanceChild.create(
            definition: AiNativeAppearancePartDefinition(
              kind: .stroke,
              colors: [
                AiColor(space: .gray, channels: [.25]),
              ],
              strokeWidth: 3,
              lineCap: 1,
              lineJoin: 2,
              dash: [5, 2],
              dashPhase: 1.5,
              overprint: true,
              strokeAlignment: .inside,
              alignmentLabelBytes: latin1.encode('Inside'),
            ),
          ),
        ],
      ),
    ),
    AiNativeAppearanceChild.create(
      definition: AiNativeAppearancePartDefinition(
        kind: .blend,
        transparency: AiNativeTransparency(blendMode: .multiply, opacity: .6, isolated: true, knockout: .inherit, alphaIsShape: true),
      ),
    ),
  ],
);

/// Exact document body bytes, independent of shifted setup offsets.
List<int> _body(AiNativeAppearances model) => model.structure.drawing.records.program.bytes.sublist(model.structure.drawing.records.program.bodyStart);

/// Exercises unused style lifecycle, graph preservation and complete reference checks.
void main() {
  test('creates the first complete style in blank and populated CC documents', () {
    for (final bool blank in [false, true]) {
      final AiNativeAppearances source = _new(blank: blank);
      check(source.styles).isEmpty();
      final List<int> name = [0, 40, 92, 255, 10, 41];
      final AiNativeAppearances result = source.createStyle(nameBytes: name, execution: _execution());
      name[0] = 1;
      final AiNativeAppearance style = result.styles.single;
      check(style.resource.nameBytes).deepEquals([0, 40, 92, 255, 10, 41]);
      check(style.uses).isEmpty();
      check(style.parts.map((part) => part.kind))
          .deepEquals([AiNativeAppearancePartKind.chain, AiNativeAppearancePartKind.stack, AiNativeAppearancePartKind.fill, AiNativeAppearancePartKind.strokeOffset, AiNativeAppearancePartKind.blend]);
      check(appearanceAssignment(style, 2, .fillColor).colors.map((color) => color.space)).deepEquals([AiColorSpace.cmyk, AiColorSpace.rgb]);
      check(style.parts[3].strokeAlignment).equals(AiNativeStrokeAlignment.inside);
      check(appearanceAssignment(style, 3, .dash).dash!.lengths).deepEquals([5, 2]);
      check(appearanceAssignment(style, 4, .transparency).transparency!.operands).deepEquals([1, .6, 1, 2, 1]);
      check(_body(result)).deepEquals(_body(source));
      final AiPdfDocument saved = newDocumentSave(result.structure.drawing.records, newDocumentPdf(blank: blank));
      final AiNativeAppearances reopened = appearanceEditingModel(source: latin1.decode(AiNativeData.extract(saved).single.bytes));
      check(reopened.styles.single.parts).length.equals(5);
      check(reopened.styles.single.resource.nameBytes).deepEquals(style.resource.nameBytes);
    }
  });

  test('creates basic paint conduit and empty compound executions without hidden defaults', () {
    final AiNativeAppearances source = _new();
    for (final AiNativeAppearancePartDefinition definition in [
      newAppearanceFill(visible: false),
      AiNativeAppearancePartDefinition(kind: .conduit),
      AiNativeAppearancePartDefinition(kind: .stack),
      AiNativeAppearancePartDefinition(kind: .chain),
    ]) {
      final AiNativeAppearances result = source.createStyle(nameBytes: latin1.encode('Basic'), execution: definition);
      check(result.styles.single.parts.single.kind).equals(definition.kind);
      check(result.styles.single.parts.single.visible).equals(definition.visible);
      check(_body(result)).deepEquals(_body(source));
      final AiNativeAppearances removed = result.removeStyles(styles: result.styles);
      check(removed.styles).isEmpty();
      check(_body(removed)).deepEquals(_body(source));
    }
  });

  test('removes several unused styles while retaining used declarations and artwork exactly', () {
    final AiNativeAppearances original = appearanceEditingModel(source: appearanceArtworkSource(metadata: true));
    final AiNativeContainer retained = original.styles.single.resource.definition.source as AiNativeContainer;
    final List<int> retainedBytes = original.structure.drawing.records.program.bytes.sublist(retained.start, retained.end);
    final AiNativeAppearances first = original.createStyle(nameBytes: latin1.encode('First'), execution: _execution());
    final AiNativeAppearances second = first.createStyle(nameBytes: latin1.encode('Second'), execution: newAppearanceFill());
    final AiNativeAppearances result = second.removeStyles(styles: second.styles.where((style) => latin1.decode(style.resource.nameBytes) != 'Shared').toList());
    check(result.styles).length.equals(1);
    final AiNativeContainer declaration = result.styles.single.resource.definition.source as AiNativeContainer;
    check(result.structure.drawing.records.program.bytes.sublist(declaration.start, declaration.end)).deepEquals(retainedBytes);
    check(_body(result)).deepEquals(_body(original));
    check(result.styles.single.uses).length.equals(original.styles.single.uses.length);
  });

  test('edits a newly authored unused basic style through the existing shared contract', () {
    final AiNativeAppearances source = _new().createStyle(nameBytes: latin1.encode('Editable'), execution: newAppearanceFill());
    final AiNativeAppearance style = source.styles.single;
    final AiNativeAppearances result = source.updateShared(
      appearance: style,
      paints: [
        AiNativePaintChange(assignment: appearanceAssignment(style, 0, .fillColor), values: [.2, .3, .4, .1, .6, .5, .4]),
      ],
    );
    check(appearanceAssignment(result.styles.single, 0, .fillColor).numbers!).deepEquals([.2, .3, .4, .1, .6, .5, .4]);
    check(result.styles.single.uses).isEmpty();
    check(_body(result)).deepEquals(_body(source));
  });

  test('rejects referenced duplicate stale foreign or empty selections atomically', () {
    final AiNativeAppearances source = appearanceEditingModel(source: appearanceArtworkSource());
    check(() => source.removeStyles(styles: source.styles)).throws<UnsupportedError>();
    check(() => source.createStyle(nameBytes: latin1.encode('Shared'), execution: _execution())).throws<ArgumentError>();
    check(() => source.createStyle(nameBytes: [], execution: _execution())).throws<ArgumentError>();
    final AiNativeAppearances created = source.createStyle(nameBytes: latin1.encode('Unused'), execution: _execution());
    final AiNativeAppearance unused = created.styles.last;
    check(() => created.removeStyles(styles: [])).throws<ArgumentError>();
    check(() => created.removeStyles(styles: [unused, unused])).throws<ArgumentError>();
    check(() => created.removeStyles(styles: [source.styles.single])).throws<ArgumentError>();
    check(() => source.removeStyles(styles: [unused])).throws<ArgumentError>();
    final AiNativeAppearances unresolved = appearanceEditingModel(source: appearanceArtworkSource().replaceFirst('1 (Shared) XW', '1 (Missing) XW'));
    check(() => unresolved.createStyle(nameBytes: latin1.encode('Missing'), execution: _execution())).throws<ArgumentError>();
  });

  test('does not treat opaque body dependencies as proof that a style is unused', () {
    final AiNativeAppearances created = _new().createStyle(nameBytes: latin1.encode('Unused'), execution: _execution());
    final String opaque = latin1.decode(created.structure.drawing.records.program.bytes).replaceFirst('%%Trailer', '17 FutureStyleUser\n%%Trailer');
    final AiNativeAppearances source = appearanceEditingModel(source: opaque);
    check(() => source.removeStyles(styles: source.styles)).throws<UnsupportedError>();
    check(() => source.createStyle(nameBytes: latin1.encode('Fresh'), execution: _execution())).throws<UnsupportedError>();
    check(latin1.decode(source.structure.drawing.records.program.bytes)).equals(opaque);
  });

  test('does not import source-owned children into an authored resource graph', () {
    final AiNativeAppearances source = appearanceEditingModel();
    for (final AiNativeAppearanceChild child in [
      AiNativeAppearanceChild.copy(part: source.styles.single.parts[1]),
      AiNativeAppearanceChild.retain(part: source.styles.single.parts[1]),
    ]) {
      check(
        () => source.createStyle(
          nameBytes: latin1.encode('Bad child'),
          execution: AiNativeAppearancePartDefinition(kind: .chain, children: [child]),
        ),
      ).throws<ArgumentError>();
    }
  });

  test('bounds nested execution and aggregate output before publishing a new source', () {
    final String source = latin1.decode(newDocumentRecords(blank: true).program.bytes);
    AiNativeAppearancePartDefinition execution = newAppearanceFill();
    for (int index = 0; index < 20; index++) {
      execution = AiNativeAppearancePartDefinition(
        kind: .chain,
        children: [AiNativeAppearanceChild.create(definition: execution)],
      );
    }
    final AiNativeAppearances bounded = appearanceEditingModel(source: source, limits: const AiNativeLimits(maxDepth: 16));
    check(() => bounded.createStyle(nameBytes: latin1.encode('Deep'), execution: execution)).throws<AiLimitException>();
    final AiNativeAppearances small = appearanceEditingModel(
      source: source,
      limits: AiNativeLimits(maxDecodedBytes: source.length + 20),
    );
    check(() => small.createStyle(nameBytes: latin1.encode('Large'), execution: _execution())).throws<AiLimitException>();
    check(latin1.decode(small.structure.drawing.records.program.bytes)).equals(source);
  });
}
