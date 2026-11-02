import 'dart:convert';

import 'package:aicodec/aicodec.dart';
import 'package:checks/checks.dart';
import 'package:test/test.dart';

import 'ai_native_appearance_artwork_test.dart' show appearanceArtworkReplacement, appearanceArtworkSource;
import 'ai_native_appearance_editing_test.dart' show appearanceAssignment, appearanceEditingModel, appearanceEditingSource, appearancePrinting;

/// Observed advanced stroke layout, retaining literal recording/version fields.
const String appearanceStrokeSettings = '/Dictionary : /NotRecorded , 1 /Int (BSAdvStrokeDictionaryVersion) , 1 /Bool (BSDashAdj) , ; (kAIBeautifulStrokesParamsDictKey) , ';

/// Inserts settings in one exact stroke part without changing its paint payload.
String appearanceStrokeSource({String? source, int part = 6, String settings = appearanceStrokeSettings, bool private = false}) {
  final String text = source ?? appearanceEditingSource();
  final AiNativeAppearances model = appearanceEditingModel(source: text);
  final int insertion = RegExp(r'/Dictionary\s*:\s*(?:/NotRecorded\s*,)?').matchAsPrefix(text, model.styles.first.parts[part].parameters!.start)!.end;
  final String result = text.replaceRange(insertion, insertion, ' $settings');
  if (!private) {
    return result;
  }
  final int start = result.indexOf('/KnownStyle');
  final int end = result.indexOf('%%EndSetup');
  return result.replaceRange(start, end, '${result.substring(start, end).split('\n').where((line) => line.isNotEmpty).map((line) => '%_$line').join('\n')}\n');
}

/// Keeps the explicitly empty producer provenance collections in setup.
const String appearanceEmptyGenAI = '/Dictionary : /Array : ; (MigratedArtList) , /Dictionary : ; (GenAIVariationsDictionary) , ; (GenAIRecorded) ,';

/// Adds a source-owned document record with no generated artwork references.
String appearanceGenAISource({String recorded = appearanceEmptyGenAI}) => appearanceArtworkSource().replaceFirst('%%EndSetup', '/Document : /Dictionary : $recorded ; /Recorded , ;\n%%EndSetup');

/// Changes one shared fill while supplying both ordinary users' expansions.
AiNativeAppearances _shared(AiNativeAppearances model) => model.updateShared(
  appearance: model.styles.first,
  paints: [
    AiNativePaintChange(assignment: appearanceAssignment(model.styles.first, 2, .fillColor), values: [0.7, 0.6, 0.5]),
  ],
  artwork: [appearanceArtworkReplacement(model, 0), appearanceArtworkReplacement(model, 1)],
);

/// Covers literal stroke options, exact edits and reference-free provenance.
void main() {
  test('reads advanced settings separately from literal dash arrays and absent values', () {
    final AiNativeAppearances source = appearanceEditingModel(source: appearanceStrokeSource());
    final AiNativeAppearancePart part = source.styles.first.parts[6];
    check(part.strokeSettings!.version).equals(1);
    check(part.strokeSettings!.adjustDashes).equals(true);
    check(part.strokeSettings!.record).identicalTo(part.parameters!['kAIBeautifulStrokesParamsDictKey']!.container!);
    check(appearanceAssignment(source.styles.first, 6, .dash).dash!.lengths).deepEquals([2, 3, 0]);
    check(source.styles.first.parts[5].strokeSettings).isNull();
    final AiNativeAppearances incomplete = appearanceEditingModel(source: appearanceStrokeSource(settings: appearanceStrokeSettings.replaceFirst('1 /Bool (BSDashAdj) ,', '')));
    check(incomplete.styles.first.parts[6].strokeSettings!.adjustDashes).isNull();
    final AiNativeAppearances future = appearanceEditingModel(source: appearanceStrokeSource(settings: appearanceStrokeSettings.replaceFirst('1 /Int', '2 /Int')));
    check(future.styles.first.parts[6].strokeSettings!.version).equals(2);
  });

  test('edits saved flags with dash operands and preserves private source syntax', () {
    for (final bool private in [false, true]) {
      final String text = appearanceStrokeSource(private: private);
      final AiNativeAppearances source = appearanceEditingModel(source: text);
      final AiNativeAppearance style = source.styles.first;
      final AiNativeAppearances changed = source.updateSelected(
        appearance: style,
        parts: [AiNativeAppearancePartChange(part: style.parts[6], adjustDashes: false)],
        paints: [
          AiNativePaintChange(assignment: appearanceAssignment(style, 6, .dash), values: [4, 2], dashPhase: 3),
        ],
        printing: [appearancePrinting(source, 1)],
        nameBytes: latin1.encode('Adjusted stroke'),
      );
      check(changed.styles.last.parts[6].strokeSettings!.adjustDashes).equals(false);
      check(appearanceAssignment(changed.styles.last, 6, .dash).dash!.lengths).deepEquals([4, 2]);
      check(appearanceAssignment(changed.styles.last, 6, .dash).dash!.phase).equals(3);
      check(changed.styles.first.parts[6].strokeSettings!.adjustDashes).equals(true);
      final AiNativeStructureNode before = style.resource.definition;
      final AiNativeStructureNode after = changed.styles.first.resource.definition;
      check(changed.structure.drawing.records.program.bytes.sublist(after.start, after.end)).deepEquals(source.structure.drawing.records.program.bytes.sublist(before.start, before.end));
      check(latin1.decode(source.structure.drawing.records.program.bytes)).equals(text);
    }
  });

  test('changes shared settings only with complete dependent printing coverage', () {
    final AiNativeAppearances source = appearanceEditingModel(source: appearanceStrokeSource(source: appearanceArtworkSource()));
    final AiNativeAppearance style = source.styles.first;
    final List<AiNativeAppearancePartChange> parts = [AiNativeAppearancePartChange(part: style.parts[6], adjustDashes: false)];
    check(() => source.updateShared(appearance: style, parts: parts, artwork: [appearanceArtworkReplacement(source, 0)])).throws<UnsupportedError>();
    final AiNativeAppearances changed = source.updateShared(appearance: style, parts: parts, artwork: [appearanceArtworkReplacement(source, 0), appearanceArtworkReplacement(source, 1)]);
    check(changed.styles).length.equals(1);
    check(changed.styles.first.parts[6].strokeSettings!.adjustDashes).equals(false);
    check(changed.styles.first.uses).length.equals(2);
  });

  test('creates explicit adjusted and unadjusted centered or offset stroke settings', () {
    final AiNativeAppearances source = appearanceEditingModel();
    final AiNativeAppearance style = source.styles.first;
    final AiNativeAppearancePart stack = style.parts[1];
    final AiNativeAppearances changed = source.updateSelected(
      appearance: style,
      parts: [
        AiNativeAppearancePartChange(
          part: stack,
          children: [
            for (final AiNativeStrokeAlignment alignment in AiNativeStrokeAlignment.values)
              AiNativeAppearanceChild.create(
                definition: AiNativeAppearancePartDefinition(
                  kind: .stroke,
                  colors: [
                    AiColor(space: .rgb, channels: [0, 0, 0]),
                  ],
                  dash: [4, 3],
                  adjustDashes: alignment != .outside,
                  strokeAlignment: alignment,
                  alignmentLabelBytes: alignment == .center ? null : latin1.encode(alignment.name),
                ),
              ),
          ],
        ),
      ],
      printing: [appearancePrinting(source, 1)],
      nameBytes: [65],
    );
    final List<AiNativeAppearancePart> strokes = changed.styles.last.parts.where((part) => part.strokeSettings != null).toList();
    check(strokes.map((part) => part.strokeSettings!.version)).deepEquals([1, 1, 1]);
    check(strokes.map((part) => part.strokeSettings!.adjustDashes)).deepEquals([true, true, false]);
    check(() => AiNativeAppearancePartDefinition(kind: .conduit, adjustDashes: true)).throws<ArgumentError>();
  });

  test('retains future records but rejects unsupported schemas and missing scalar targets', () {
    for (final String settings in [
      '',
      appearanceStrokeSettings.replaceFirst('1 /Int', '2 /Int'),
      appearanceStrokeSettings.replaceFirst('1 /Int (BSAdvStrokeDictionaryVersion) ,', ''),
      appearanceStrokeSettings.replaceFirst('1 /Bool (BSDashAdj) ,', ''),
      appearanceStrokeSettings.replaceFirst('/NotRecorded ,', '/NotRecorded , 1 /Bool (Future) ,'),
    ]) {
      final String text = appearanceStrokeSource(settings: settings);
      final AiNativeAppearances source = appearanceEditingModel(source: text);
      check(
        () => source.updateSelected(
          appearance: source.styles.first,
          parts: [AiNativeAppearancePartChange(part: source.styles.first.parts[6], adjustDashes: false)],
          printing: [appearancePrinting(source, 1)],
          nameBytes: [65],
        ),
      ).throws<UnsupportedError>();
      check(latin1.decode(source.structure.drawing.records.program.bytes)).equals(text);
    }
    for (final String settings in [
      appearanceStrokeSettings.replaceFirst('1 /Int', '1 /Real'),
      appearanceStrokeSettings.replaceFirst('1 /Int', '1.5 /Int'),
      appearanceStrokeSettings.replaceFirst('1 /Bool', '2 /Bool'),
      appearanceStrokeSettings.replaceFirst('1 /Bool', '1 /Int'),
    ]) {
      check(() => appearanceEditingModel(source: appearanceStrokeSource(settings: settings))).throws<FormatException>();
    }
  });

  test('rejects stroke options on non-stroke parts and retains geometry transform scope', () {
    final AiNativeAppearances misplaced = appearanceEditingModel(source: appearanceStrokeSource(part: 2));
    check(() => _shared(misplaced)).throws<UnsupportedError>();
    final AiNativeAppearances source = appearanceEditingModel(source: appearanceStrokeSource());
    check(() => source.structure.drawing.translateLiveShapes(shapes: [source.structure.drawing.liveShapes.first], deltaX: 1, deltaY: 1)).throws<UnsupportedError>();
  });

  test('retains empty generative provenance during complete shared edits', () {
    final String text = appearanceGenAISource();
    final AiNativeAppearances source = appearanceEditingModel(source: text);
    final AiNativeAppearances changed = _shared(source);
    check(latin1.decode(changed.structure.drawing.records.program.bytes)).contains(appearanceEmptyGenAI);
    check(latin1.decode(source.structure.drawing.records.program.bytes)).equals(text);
  });

  test('rejects populated mistyped repeated or unknown generative dependency owners', () {
    for (final String recorded in [
      appearanceEmptyGenAI.replaceFirst('/Array : ;', '/Array : (artwork) , ;'),
      appearanceEmptyGenAI.replaceFirst('/Dictionary : ;', '/Dictionary : (variation) /String (entry) , ;'),
      appearanceEmptyGenAI.replaceFirst('/Array :', '/Dictionary :'),
      appearanceEmptyGenAI.replaceFirst('(MigratedArtList)', '(Future)'),
      appearanceEmptyGenAI.replaceFirst('/Dictionary :', '/Dictionary : /NotRecorded ,'),
    ]) {
      final String text = appearanceGenAISource(recorded: recorded);
      final AiNativeAppearances source = appearanceEditingModel(source: text);
      check(() => _shared(source)).throws<UnsupportedError>();
      check(latin1.decode(source.structure.drawing.records.program.bytes)).equals(text);
    }
    final String repeated = appearanceGenAISource(recorded: appearanceEmptyGenAI.replaceFirst('(MigratedArtList) ,', '(MigratedArtList) , /Array : ; (MigratedArtList) ,'));
    check(() => appearanceEditingModel(source: repeated)).throws<FormatException>();
  });
}
