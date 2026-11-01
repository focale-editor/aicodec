import 'dart:convert';

import 'package:aikit/aikit.dart';
import 'package:checks/checks.dart';
import 'package:test/test.dart';

import 'ai_native_appearances_test.dart' show appearanceStyle;
import 'ai_native_shape_lifecycle_test.dart' show shapeLifecycleSource;

/// Keeps two independent CC users of a complete ordered multiple-paint style.
String appearanceEditingSource() {
  final String source = shapeLifecycleSource();
  final String style = appearanceStyle().replaceAll('(board-0)', '(Shared)').replaceAll('9 0.8 1 2 1 Xy', '0 0.8 0 0 0 Xy').replaceAll('15 0.5 0 0 0 Xy', '0 0.5 0 0 0 Xy');
  return source.replaceRange(source.indexOf('/KnownStyle'), source.indexOf('%%EndSetup'), style);
}

/// Decodes current handles without sharing mutable fixture state.
AiNativeAppearances appearanceEditingModel({String? source, AiNativeLimits limits = const AiNativeLimits()}) => AiNativeAppearances.decode(
  structure: AiNativeStructure.decode(
    drawing: AiNativeDrawing.decode(
      records: AiNativeRecords.decode(
        program: AiProgram.decode(bytes: latin1.encode(source ?? appearanceEditingSource()), limits: limits),
      ),
    ),
  ),
);

/// Host-authored expansion with different paint and the original outgoing color.
const String appearanceEditedGroup = 'u\n0.7 0.6 0.5 Xa\n0 0 m 10 0 L 10 10 L f\n0 0 0 1 k\nU';

/// Supplies an expansion for one exact user without generating artwork in AiKit.
AiNativePrintingGroupReplacement appearancePrinting(AiNativeAppearances model, int index, {String bytes = appearanceEditedGroup}) => AiNativePrintingGroupReplacement(
  shape: model.structure.drawing.liveShapes[index],
  bytes: latin1.encode(bytes),
  bounds: AiBoundingBox(left: -20, bottom: -30, right: 120, top: 140),
);

/// Selects an exact assignment without collapsing repeated settings or paints.
AiNativePaintAssignment appearanceAssignment(AiNativeAppearance style, int part, AiNativePaintParameter parameter) =>
    style.parts[part].paints.single.style.assignments.singleWhere((assignment) => assignment.parameter == parameter);

/// Reads exact source owners for preservation assertions.
List<int> _bytes(AiNativeAppearances model, AiNativeItem owner) => model.structure.drawing.records.program.bytes.sublist(owner.start, owner.end);

/// Reads one complete authoring/printing pair without discarding its metadata.
List<int> _shapeBytes(AiNativeAppearances model, AiLiveShape shape) => model.structure.drawing.records.program.bytes.sublist(shape.start, shape.end);

/// Covers atomic source edits, shared ownership, isolation and state dependencies.
void main() {
  test('isolates one selected paint and user while preserving the original shared style', () {
    final AiNativeAppearances source = appearanceEditingModel();
    final AiNativeAppearance style = source.styles.single;
    final AiNativeAppearances changed = source.updateSelected(
      appearance: style,
      paints: [
        AiNativePaintChange(assignment: appearanceAssignment(style, 2, .fillColor), values: [0.7, 0.6, 0.5]),
      ],
      printing: [appearancePrinting(source, 0)],
      nameBytes: latin1.encode('Selected'),
    );
    check(changed.styles).length.equals(2);
    check(appearanceAssignment(changed.styles.last, 2, .fillColor).numbers).isNotNull().deepEquals([0.7, 0.6, 0.5]);
    check(_bytes(changed, changed.styles.first.resource.definition.source as AiNativeContainer)).deepEquals(_bytes(source, style.resource.definition.source as AiNativeContainer));
    check(changed.structure.drawing.liveShapes.first.style).identicalTo(changed.styles.last.resource.definition.source as AiNativeContainer);
    check(changed.structure.drawing.liveShapes.last.style).identicalTo(changed.styles.first.resource.definition.source as AiNativeContainer);
    check(_shapeBytes(changed, changed.structure.drawing.liveShapes.last)).deepEquals(_shapeBytes(source, source.structure.drawing.liveShapes.last));
    check(_bytes(changed, changed.structure.drawing.liveShapes.first.appearanceGroup!)).deepEquals(latin1.encode(appearanceEditedGroup));
    check(latin1.decode(source.structure.drawing.records.program.bytes)).equals(appearanceEditingSource());
  });

  test('updates a shared definition only with complete dependent printing coverage', () {
    final AiNativeAppearances source = appearanceEditingModel();
    final AiNativeAppearance style = source.styles.single;
    final List<AiNativePaintChange> paints = [
      AiNativePaintChange(assignment: appearanceAssignment(style, 2, .fillColor), values: [0.7, 0.6, 0.5]),
    ];
    final AiNativeAppearances changed = source.updateShared(appearance: style, paints: paints, printing: [appearancePrinting(source, 0), appearancePrinting(source, 1)]);
    check(changed.styles).length.equals(1);
    check(appearanceAssignment(changed.styles.single, 2, .fillColor).numbers).isNotNull().deepEquals([0.7, 0.6, 0.5]);
    check(changed.styles.single.uses).length.equals(2);
    for (final AiLiveShape shape in changed.structure.drawing.liveShapes) {
      check(_bytes(changed, shape.appearanceGroup!)).deepEquals(latin1.encode(appearanceEditedGroup));
    }
    check(() => source.updateShared(appearance: style, paints: paints, printing: [appearancePrinting(source, 0)])).throws<UnsupportedError>();
  });

  test('writes selected explicit part flags dash lengths and dual colors atomically', () {
    final AiNativeAppearances source = appearanceEditingModel();
    final AiNativeAppearance style = source.styles.single;
    final AiNativeAppearances changed = source.updateSelected(
      appearance: style,
      paints: [
        AiNativePaintChange(assignment: appearanceAssignment(style, 6, .dash), values: [5, 2, 3, 4], dashPhase: -2),
        AiNativePaintChange(assignment: appearanceAssignment(style, 6, .strokeWidth), values: [8]),
        AiNativePaintChange(assignment: appearanceAssignment(style, 6, .strokeColor), values: [0, 0.1, 0.2, 0.3, 0.4, 0.5, 0.6]),
      ],
      parts: [
        AiNativeAppearancePartChange(part: style.parts[2], visible: true, evenOdd: false),
        AiNativeAppearancePartChange(part: style.parts[6], strokeAlignment: .outside),
      ],
      printing: [appearancePrinting(source, 1)],
      nameBytes: [0, 40, 92, 255],
    );
    final AiNativeAppearance selected = changed.styles.last;
    check(selected.resource.nameBytes).deepEquals([0, 40, 92, 255]);
    check(selected.parts[2].visible).equals(true);
    check(selected.parts[2].evenOdd).equals(false);
    check(selected.parts[6].strokeAlignment).equals(AiNativeStrokeAlignment.outside);
    check(appearanceAssignment(selected, 6, .dash).dash!.lengths).deepEquals([5.0, 2.0, 3.0, 4.0]);
    check(appearanceAssignment(selected, 6, .dash).dash!.phase).equals(-2);
    check(appearanceAssignment(selected, 6, .strokeColor).colors).length.equals(2);
    check(appearanceAssignment(selected, 6, .strokeWidth).numbers).isNotNull().deepEquals([8.0]);
  });

  test('synchronizes saved alignment labels with explicit host bytes', () {
    final AiNativeAppearances source = appearanceEditingModel(
      source: appearanceEditingSource().replaceFirst('1 /Bool (StrokeOffsetInside)', '(Inside) /String (DisplayString) , 1 /Bool (StrokeOffsetInside)'),
    );
    final AiNativeAppearance style = source.styles.single;
    check(
      () => source.updateSelected(
        appearance: style,
        parts: [AiNativeAppearancePartChange(part: style.parts[6], strokeAlignment: .outside)],
        printing: [appearancePrinting(source, 1)],
        nameBytes: [65],
      ),
    ).throws<UnsupportedError>();
    final List<int> label = latin1.encode('Outside').toList();
    final AiNativeAppearancePartChange change = AiNativeAppearancePartChange(part: style.parts[6], strokeAlignment: .outside, alignmentLabelBytes: label);
    label.clear();
    final AiNativeAppearances changed = source.updateSelected(appearance: style, parts: [change], printing: [appearancePrinting(source, 1)], nameBytes: [65]);
    check(changed.styles.last.parts[6].parameters!['DisplayString']!.text()).equals('Outside');
    check(changed.styles.last.parts[6].strokeAlignment).equals(AiNativeStrokeAlignment.outside);
    check(change.alignmentLabelBytes!.clear).throws<UnsupportedError>();
    check(() => AiNativeAppearancePartChange(part: style.parts[6], alignmentLabelBytes: [65], visible: true)).throws<ArgumentError>();
  });

  test('retains comment prefixes and dash annotations while growing shrinking or clearing lengths', () {
    final String annotated = appearanceEditingSource().replaceFirst('[2 3 0] -1 d', '[2 % retained dash comment\n3 0] -1 d');
    final AiNativeAppearances ordinary = appearanceEditingModel(source: annotated);
    final AiNativeContainer declaration = ordinary.styles.single.resource.definition.source as AiNativeContainer;
    final String text = annotated.substring(declaration.start, declaration.end);
    final String private = annotated.replaceFirst(text, text.split('\n').map((line) => '%_$line').join('\n'));
    for (final List<double> lengths in [
      [8.0, 2.0, 1.0, 3.0],
      [4.0],
      <double>[],
    ]) {
      final AiNativeAppearances source = appearanceEditingModel(source: private);
      final AiNativeAppearance style = source.styles.single;
      final AiNativeAppearances changed = source.updateSelected(
        appearance: style,
        paints: [AiNativePaintChange(assignment: appearanceAssignment(style, 6, .dash), values: lengths, dashPhase: -3)],
        printing: [appearancePrinting(source, 1)],
        nameBytes: [65],
      );
      check(appearanceAssignment(changed.styles.last, 6, .dash).dash!.lengths).deepEquals(lengths);
      check(latin1.decode(_bytes(changed, changed.styles.last.resource.definition.source as AiNativeContainer))).contains('% retained dash comment');
      check(_bytes(changed, changed.styles.first.resource.definition.source as AiNativeContainer)).deepEquals(_bytes(source, style.resource.definition.source as AiNativeContainer));
    }
  });

  test('rejects foreign stale duplicate and empty selections before publishing changes', () {
    final AiNativeAppearances source = appearanceEditingModel();
    final AiNativeAppearance style = source.styles.single;
    final AiNativePaintChange change = AiNativePaintChange(assignment: appearanceAssignment(style, 2, .fillColor), values: [0.7, 0.6, 0.5]);
    final AiNativeAppearances changed = source.updateSelected(appearance: style, paints: [change], printing: [appearancePrinting(source, 0)], nameBytes: [65]);
    for (final void Function() action in [
      () => changed.updateShared(appearance: style, paints: [change], printing: []),
      () => source.updateSelected(appearance: style, paints: [change, change], printing: [appearancePrinting(source, 0)], nameBytes: [65]),
      () => source.updateSelected(appearance: style, paints: [change], printing: [appearancePrinting(source, 0), appearancePrinting(source, 0)], nameBytes: [65]),
      () => source.updateSelected(appearance: style, paints: [change], printing: [appearancePrinting(changed, 0)], nameBytes: [65]),
      () => source.updateSelected(appearance: style, paints: [change], printing: [], nameBytes: [65]),
      () => source.updateShared(appearance: style, printing: []),
      () => source.updateShared(appearance: changed.styles.first, paints: [change], printing: []),
      () => source.updateSelected(
        appearance: style,
        paints: [
          AiNativePaintChange(assignment: appearanceAssignment(changed.styles.first, 2, .fillColor), values: [0, 0, 0]),
        ],
        printing: [appearancePrinting(source, 0)],
        nameBytes: [65],
      ),
    ]) {
      check(action).throws<ArgumentError>();
    }
    final List<double> mutable = [0.7, 0.6, 0.5];
    final AiNativePaintChange owned = AiNativePaintChange(assignment: change.assignment, values: mutable);
    mutable.clear();
    check(owned.values).deepEquals([0.7, 0.6, 0.5]);
    check(owned.values.clear).throws<UnsupportedError>();
    check(latin1.decode(source.structure.drawing.records.program.bytes)).equals(appearanceEditingSource());
  });

  test('validates numeric grammar source layouts and explicit part setting ownership', () {
    final AiNativeAppearances source = appearanceEditingModel();
    final AiNativeAppearance style = source.styles.single;
    for (final (AiNativePaintParameter, List<double>, double?) input in [
      (AiNativePaintParameter.strokeWidth, [-1.0], null),
      (AiNativePaintParameter.lineCap, [0.5], null),
      (AiNativePaintParameter.lineJoin, [3.0], null),
      (AiNativePaintParameter.miterLimit, [0.0], null),
      (AiNativePaintParameter.dash, [0.0, 0.0], 0.0),
      (AiNativePaintParameter.dash, [-1.0, 2.0], 0.0),
      (AiNativePaintParameter.strokeColor, [2.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0], null),
    ]) {
      check(
        () => source.updateSelected(
          appearance: style,
          paints: [AiNativePaintChange(assignment: appearanceAssignment(style, 6, input.$1), values: input.$2, dashPhase: input.$3)],
          printing: [appearancePrinting(source, 1)],
          nameBytes: [65],
        ),
      ).throws<FormatException>();
    }
    for (final AiNativeAppearancePartChange part in [
      AiNativeAppearancePartChange(part: style.parts[3], visible: true),
      AiNativeAppearancePartChange(part: style.parts[3], evenOdd: false),
      AiNativeAppearancePartChange(part: style.parts[5], strokeAlignment: .inside),
      AiNativeAppearancePartChange(part: style.parts[6], strokeAlignment: .center),
    ]) {
      check(() => source.updateSelected(appearance: style, parts: [part], printing: [appearancePrinting(source, 1)], nameBytes: [65])).throws<UnsupportedError>();
    }
    final AiNativePaintAssignment width = appearanceAssignment(style, 6, .strokeWidth);
    for (final void Function() invalid in [
      () => AiNativePaintChange(assignment: width, values: [double.nan]),
      () => AiNativePaintChange(assignment: width, values: [double.infinity]),
      () => AiNativePaintChange(assignment: width, values: [9007199254740992]),
      () => AiNativePaintChange(assignment: width, values: []),
      () => AiNativePaintChange(assignment: width, values: [1], dashPhase: 0),
      () => AiNativePaintChange(assignment: appearanceAssignment(style, 6, .dash), values: [1]),
      () => AiNativeAppearancePartChange(part: style.parts.first),
    ]) {
      check(invalid).throws<ArgumentError>();
    }
  });

  test('protects following native state and rejects inconsistent supplied printing state', () {
    for (final bool reset in [false, true]) {
      final AiNativeAppearances source = appearanceEditingModel(source: appearanceEditingSource().replaceFirst('%%Trailer', '${reset ? '0 g ' : ''}0 0 m 1 1 L F\n%%Trailer'));
      final AiNativeAppearance style = source.styles.single;
      AiNativeAppearances edit() => source.updateSelected(
        appearance: style,
        paints: [
          AiNativePaintChange(assignment: appearanceAssignment(style, 2, .fillColor), values: [0.7, 0.6, 0.5]),
        ],
        printing: [appearancePrinting(source, 1)],
        nameBytes: [65],
      );
      if (reset) {
        check(edit().styles).length.equals(2);
      } else {
        check(edit).throws<UnsupportedError>();
      }
    }
    final AiNativeAppearances source = appearanceEditingModel();
    final AiNativeAppearance style = source.styles.single;
    check(
      () => source.updateShared(
        appearance: style,
        paints: [
          AiNativePaintChange(assignment: appearanceAssignment(style, 2, .fillColor), values: [0.7, 0.6, 0.5]),
        ],
        printing: [
          appearancePrinting(source, 0),
          appearancePrinting(source, 1, bytes: appearanceEditedGroup.replaceFirst('0 0 0 1 k', '0 g')),
        ],
      ),
    ).throws<UnsupportedError>();
    check(latin1.decode(source.structure.drawing.records.program.bytes)).equals(appearanceEditingSource());
  });

  test('rejects name capture conditional styles opaque parameters and unbound shared users', () {
    for (final String sourceText in [
      appearanceEditingSource().replaceFirst('(Shared) /Name', '(Shared) /Name , 4 /Int (FutureCache)'),
      appearanceEditingSource().replaceFirst('(Adobe Stroke Offset)', '(Future Effect)'),
      appearanceEditingSource().replaceFirst('/KnownStyle', '%AI17_Begin_Content_if_version_gt:24 4\n/KnownStyle').replaceFirst('%%EndSetup', '%AI17_End_Versioned_Content\n%%EndSetup'),
      appearanceEditingSource().replaceFirst('%%Trailer', '0 (Shared) XW\n%%Trailer'),
    ]) {
      final AiNativeAppearances source = appearanceEditingModel(source: sourceText);
      final AiNativeAppearance style = source.styles.single;
      check(
        () => source.updateShared(
          appearance: style,
          paints: [
            AiNativePaintChange(assignment: appearanceAssignment(style, 2, .fillColor), values: [0.7, 0.6, 0.5]),
          ],
          printing: [appearancePrinting(source, 0), appearancePrinting(source, 1)],
        ),
      ).throws<UnsupportedError>();
    }
    final AiNativeAppearances source = appearanceEditingModel();
    for (final List<int> name in [
      <int>[],
      latin1.encode('Shared'),
      [-1],
      [256],
    ]) {
      check(
        () => source.updateSelected(
          appearance: source.styles.single,
          paints: [
            AiNativePaintChange(assignment: appearanceAssignment(source.styles.single, 2, .fillColor), values: [0, 0, 0]),
          ],
          printing: [appearancePrinting(source, 1)],
          nameBytes: name,
        ),
      ).throws<ArgumentError>();
    }
  });

  test('edits unused qualified styles without inventing printing owners and bounds output growth', () {
    final String full = appearanceEditingSource();
    final String empty = '${full.substring(0, full.indexOf('%%EndSetup'))}%%EndSetup\n%%Trailer\n%%EOF\n';
    final AiNativeAppearances unused = appearanceEditingModel(source: empty);
    final AiNativeAppearances changed = unused.updateShared(
      appearance: unused.styles.single,
      paints: [
        AiNativePaintChange(assignment: appearanceAssignment(unused.styles.single, 6, .strokeWidth), values: [9]),
      ],
      printing: [],
    );
    check(appearanceAssignment(changed.styles.single, 6, .strokeWidth).numbers).isNotNull().deepEquals([9.0]);
    final AiNativeAppearances bounded = appearanceEditingModel(limits: AiNativeLimits(maxDecodedBytes: full.length + 10));
    check(
      () => bounded.updateSelected(
        appearance: bounded.styles.single,
        paints: [AiNativePaintChange(assignment: appearanceAssignment(bounded.styles.single, 6, .dash), values: List.filled(full.length, 1), dashPhase: 0)],
        printing: [appearancePrinting(bounded, 1)],
        nameBytes: [65],
      ),
    ).throws<AiLimitException>();
    check(
      () => bounded.updateSelected(
        appearance: bounded.styles.single,
        paints: [
          AiNativePaintChange(assignment: appearanceAssignment(bounded.styles.single, 6, .strokeWidth), values: [9]),
        ],
        printing: [appearancePrinting(bounded, 1)],
        nameBytes: [65],
      ),
    ).throws<FormatException>();
    check(latin1.decode(bounded.structure.drawing.records.program.bytes)).equals(full);
    final AiNativeAppearances tokenBounded = appearanceEditingModel(limits: const AiNativeLimits(maxTokens: 4000));
    check(
      () => tokenBounded.updateSelected(
        appearance: tokenBounded.styles.single,
        paints: [
          for (final int part in [5, 6]) AiNativePaintChange(assignment: appearanceAssignment(tokenBounded.styles.single, part, .dash), values: List.filled(2500, 1), dashPhase: 0),
        ],
        printing: [appearancePrinting(tokenBounded, 1)],
        nameBytes: [65],
      ),
    ).throws<AiLimitException>();
  });

  test('reports appearance operations as requiring dependency and supplied-data validation', () {
    final AiNativeSource source = AiNativeData.extract(const AiCodec().decode(latin1.encode(appearanceEditingSource()))).single;
    final AiNativeCapabilityReport report = AiNativeCapabilityReport.inspect(source: source);
    final List<AiNativeEditCapability> edits = report.findings.where((finding) => finding.feature == .appearance).expand((finding) => finding.edits).toList();
    check(edits.map((edit) => edit.operation)).deepEquals([AiNativeEditOperation.sharedAppearance, AiNativeEditOperation.selectedAppearance]);
    check(edits.every((edit) => edit.support == .requiresValidation)).isTrue();
  });
}
