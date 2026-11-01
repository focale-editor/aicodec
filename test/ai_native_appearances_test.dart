import 'dart:convert';

import 'package:aikit/aikit.dart';
import 'package:checks/checks.dart';
import 'package:test/test.dart';

import 'ai_native_artboard_references_test.dart' show artboardSimpleStyle;
import 'ai_native_artboard_styles_test.dart' show artboardActiveStyle, artboardEffect;
import 'ai_native_group_creation_test.dart' show groupCreationDrawing;
import 'ai_native_objects_test.dart' show objectSource;

/// Adds a second fill and an explicitly aligned stroke without flattening the tree.
String appearanceStyle({String alignment = '1 /Bool (StrokeOffsetInside) ,'}) =>
    artboardActiveStyle(
      effect: artboardEffect(name: 'Adobe Stroke Offset', parameters: '$alignment /StrokeStyle : 0.1 0.2 0.3 0.4 0.5 0.6 0.7 XA 3 w 1 J 2 j 4 M [2 3 0] -1 d /Def ; (StrokeStyle) ,'),
    ).replaceFirst(
      '/BasicFilter : (Conduit Filter)',
      '/BasicFilter : (Fill Style Filter) 0 0 /Filter , /Dictionary : /FillStyle : 0.9 g /Def ; (FillStyle) , ; /Dict ; /Part ,\n/BasicFilter : (Conduit Filter)',
    );

/// Builds a source-owned appearance inventory with two uses of the same style.
AiNativeAppearances appearanceModel(String style, {String body = '0 (board-0) XW 0 0 m 10 10 L N 1 (board-0) XW', AiNativeLimits limits = const AiNativeLimits()}) => AiNativeAppearances.decode(
  structure: AiNativeStructure.decode(
    drawing: groupCreationDrawing(objectSource(body, setup: style), limits: limits),
  ),
);

/// Reads one selected paint without resolving shared styles or rendering it.
AiNativePaintStyle _paint(String commands) {
  final AiNativeRecords records = groupCreationDrawing(objectSource('', setup: '/StrokeStyle : $commands /Def ;')).records;
  return AiNativePaintStyle.decode(records: records, record: records.roots.single);
}

/// Checks ordered source models, explicit settings, shared identity and limits.
void main() {
  test('exposes multiple paints with their exact stack chain and field ownership', () {
    final AiNativeAppearances model = appearanceModel(appearanceStyle());
    final AiNativeAppearance style = model.styles.single;
    check(style.parts.map((part) => part.kind)).deepEquals([
      AiNativeAppearancePartKind.chain,
      AiNativeAppearancePartKind.stack,
      AiNativeAppearancePartKind.fill,
      AiNativeAppearancePartKind.fill,
      AiNativeAppearancePartKind.conduit,
      AiNativeAppearancePartKind.stroke,
      AiNativeAppearancePartKind.strokeOffset,
      AiNativeAppearancePartKind.blend,
    ]);
    check(style.parts.first.childIndices).deepEquals([1, 6, 7]);
    check(style.parts[1].childIndices).deepEquals([2, 3, 4, 5]);
    check(style.parts.map((part) => part.parentIndex)).deepEquals([null, 0, 1, 1, 1, 1, 0, 0]);
    check(style.parts[2].visible).equals(false);
    check(style.parts[3].visible).isNull();
    check(style.parts[2].evenOdd).equals(true);
    check(style.parts[3].evenOdd).isNull();
    check(style.parts[5].strokeAlignment).equals(AiNativeStrokeAlignment.center);
    check(style.parts[6].strokeAlignment).equals(AiNativeStrokeAlignment.inside);
    check(style.parts[5].fillOrStroke).equals(2);
    check(style.forSource(record: style.parts[6].record)).identicalTo(style.parts[6]);
    for (final AiNativeAppearancePart part in style.parts) {
      for (final AiNativeAppearancePaint paint in part.paints) {
        check(part.parameters!.entries.contains(paint.field)).isTrue();
        check(paint.field.container).identicalTo(paint.style.record);
      }
    }
  });

  test('retains shared definitions and distinguishes unresolved or foreign uses', () {
    final AiNativeAppearances model = appearanceModel(appearanceStyle());
    check(model.uses).length.equals(2);
    check(model.styles.single.uses).deepEquals(model.uses);
    for (final AiNativeResourceUse use in model.uses) {
      check(model.resolve(use: use)).identicalTo(model.styles.single);
    }
    final AiNativeAppearances ambiguous = appearanceModel('${appearanceStyle()}${appearanceStyle()}');
    check(ambiguous.styles).length.equals(2);
    check(ambiguous.uses.every((use) => use.resolution == .ambiguous && ambiguous.resolve(use: use) == null)).isTrue();
    check(ambiguous.styles.every((style) => style.uses.length == 2)).isTrue();
    final AiNativeAppearances missing = appearanceModel('', body: '0 (missing) XW');
    check(missing.resolve(use: missing.uses.single)).isNull();
    check(() => model.resolve(use: ambiguous.uses.first)).throws<ArgumentError>();
    check(() => model.styles.single.forSource(record: ambiguous.styles.first.parts.first.record)).throws<ArgumentError>();
  });

  test('keeps conditional declarations unresolved and retains their own graph', () {
    final AiNativeAppearances model = appearanceModel('%AI17_Begin_Content_if_version_gt:24 4\n${appearanceStyle()}%AI17_End_Versioned_Content\n');
    check(model.styles.single.resource.versions).isNotEmpty();
    check(model.uses.every((use) => use.resolution == .conditional && model.resolve(use: use) == null)).isTrue();
    check(model.styles.single.parts).length.equals(8);
  });

  test('retains explicit outside alignment without assuming missing offset settings', () {
    for (final (String, AiNativeStrokeAlignment?) entry in [('0 /Bool (StrokeOffsetInside) ,', AiNativeStrokeAlignment.outside), ('', null)]) {
      final AiNativeAppearancePart part = appearanceModel(appearanceStyle(alignment: entry.$1)).styles.single.parts[6];
      check(part.strokeAlignment).equals(entry.$2);
    }
    final AiNativeAppearancePart external = appearanceModel(appearanceStyle().replaceFirst('Illustrator.exe', 'External.aip')).styles.single.parts[6];
    check(external.kind).equals(AiNativeAppearancePartKind.effect);
    check(external.strokeAlignment).isNull();
    check(external.paints).length.equals(1);
    final AiNativeAppearancePart extended = appearanceModel(appearanceStyle().replaceFirst('/StrokeStyle : 0 0 0 1 K', '1 /Bool (StrokeOffsetInside) , /StrokeStyle : 0 0 0 1 K'))
        .styles
        .single
        .parts[5];
    check(extended.kind).equals(AiNativeAppearancePartKind.stroke);
    check(extended.strokeAlignment).isNull();
    check(extended.parameters!['StrokeOffsetInside']!.number).equals(1);
    final AiNativeAppearancePart plugin = appearanceModel(appearanceStyle().replaceFirst('(Stroke Style Filter) 0 0 /Filter ,', '(Stroke Style Filter) 0 0 /Filter , (External.aip) /PluginFileName ,'))
        .styles
        .single
        .parts[5];
    check(plugin.kind).equals(AiNativeAppearancePartKind.opaque);
    check(plugin.strokeAlignment).isNull();
  });

  test('preserves unknown graphs descriptors parameters and opaque siblings', () {
    final String source = appearanceStyle()
        .replaceFirst('(Stack Style Filter) 0 0', '(Future Stack) 2 9')
        .replaceFirst('/Execution', '/FutureFilter : (opaque) /Payload ; /Part , /Execution')
        .replaceFirst('1 /Bool (UseEvenOdd) ,', '1 /Bool (UseEvenOdd) , (retained) /String (FutureParameter) ,');
    // The unknown sibling belongs to the execution owner, not a synthetic child.
    final String nested = source.replaceFirst('; /FutureFilter : (opaque) /Payload ; /Part , /Execution', '/FutureFilter : (opaque) /Payload ; /Part , ; /Execution');
    final AiNativeAppearances model = appearanceModel(nested);
    final AiNativeAppearance style = model.styles.single;
    check(style.parts[1].kind).equals(AiNativeAppearancePartKind.opaque);
    check(style.parts[1].filter!.flags).deepEquals([2, 9]);
    check(style.parts[1].childIndices).deepEquals([2, 3, 4, 5]);
    check(style.parts.last.kind).equals(AiNativeAppearancePartKind.opaque);
    check(style.parts.last.record['Payload']!.text()).equals('opaque');
    check(style.parts[2].parameters!['FutureParameter']!.text()).equals('retained');
    check(latin1.decode(model.structure.drawing.records.program.bytes)).equals(objectSource('0 (board-0) XW 0 0 m 10 10 L N 1 (board-0) XW', setup: nested));
  });

  test('exposes simple styles and preserves unknown future definitions', () {
    final AiNativeAppearance simple = appearanceModel(artboardSimpleStyle).styles.single;
    check(simple.parts).isEmpty();
    check(simple.simplePaint!.record).identicalTo(simple.definition);
    check(simple.simplePaint!.assignments.map((assignment) => assignment.parameter)).contains(AiNativePaintParameter.fillColor);
    final AiNativeAppearance unknown = appearanceModel('/KnownStyle : (board-0) /Name , /FutureStyle : (payload) /Data ; /Def ;').styles.single;
    check(unknown.definition.type).equals('FutureStyle');
    check(unknown.parts).isEmpty();
    check(unknown.simplePaint).isNull();
  });

  test('exposes exact repeated color stroke dash and display assignments', () {
    final AiNativePaintStyle paint = _paint('0.5 g 1 0 0 0 0.2 0.3 0.4 XA 2 w FuturePaint 3 w 1 J 2 j 4 M [2 3 0] -1 d 1 O 0 R 1 XR 1 0 Xd');
    check(paint.instructions.map((instruction) => instruction.operator)).contains('FuturePaint');
    check(paint.assignments.where((assignment) => assignment.parameter == .strokeWidth).map((assignment) => assignment.numbers)).deepEquals([
      [2.0],
      [3.0],
    ]);
    check(paint.assignments.first.colors.single.space).equals(AiColorSpace.gray);
    check(paint.assignments[1].colors.map((color) => color.space)).deepEquals([AiColorSpace.cmyk, AiColorSpace.rgb]);
    check(paint.assignments[1].colors.map((color) => color.channels)).deepEquals([
      [1.0, 0.0, 0.0, 0.0],
      [0.2, 0.3, 0.4],
    ]);
    final AiNativePaintAssignment dash = paint.assignments.singleWhere((assignment) => assignment.parameter == .dash);
    check(dash.numbers).isNull();
    check(dash.dash!.lengths).deepEquals([2.0, 3.0, 0.0]);
    check(dash.dash!.phase).equals(-1);
    check(paint.assignments.last.numbers).isNotNull().deepEquals([1.0, 0.0]);
    check(_paint('').assignments).isEmpty();
    check(_paint('[] 0 d').assignments.single.dash!.lengths).isEmpty();
    check(paint.assignments[2].colors).isEmpty();
    check(paint.assignments[2].dash).isNull();
  });

  test('rejects malformed literal settings without hiding unknown instructions', () {
    for (final String commands in ['-1 w', '0.5 J', '3 j', '0 M', '[0 0] 1 d', '[-1 2] 0 d', '[2] /phase d', '[2] 0 1 d', '2 g', '0 0 Xa', '2 O', '2 R', '3 XR', '1 2 Xd', '9007199254740992 w']) {
      check(() => _paint(commands).assignments).throws<FormatException>();
    }
    final AiNativePaintStyle named = _paint('0 0 0 1 (Spot) 0.5 Xs');
    check(named.assignments).isEmpty();
    check(named.instructions.single.operator).equals('Xs');
  });

  test('rejects malformed owned fields without discarding source records', () {
    for (final String source in [
      appearanceStyle().replaceFirst('1 /Visible', '2 /Visible'),
      appearanceStyle().replaceFirst('(Chain Style Filter) 0 0', '(Chain Style Filter) 0.5 0'),
      appearanceStyle().replaceFirst('(Chain Style Filter) 0 0', '(Chain Style Filter) 0'),
      appearanceStyle().replaceFirst('1 /Bool (UseEvenOdd)', '1 /Int (UseEvenOdd)'),
      appearanceStyle().replaceFirst('1 /Bool (StrokeOffsetInside)', '2 /Bool (StrokeOffsetInside)'),
      appearanceStyle().replaceFirst('/Execution', '/OtherExecution'),
      '/KnownStyle : (board-0) /Name , 1 /Def ;',
      '/KnownStyle : (board-0) /Name , /ActiveStyle : /CompoundFilter : (Stack Style Filter) 0 0 /Filter , (execute) /Part ; /Execution ; /Def ;',
    ]) {
      check(() => appearanceModel(source)).throws<FormatException>();
    }
    check(() => appearanceModel(appearanceStyle().replaceFirst('/Visible ,', '/Visible , 0 /Visible ,'))).throws<AiNativeAmbiguousFieldError>();
  });

  test('freezes every list and rejects foreign paint records', () {
    final AiNativeAppearances model = appearanceModel(appearanceStyle());
    final AiNativeAppearance style = model.styles.single;
    final AiNativeAppearancePart part = style.parts[6];
    final AiNativePaintStyle paint = part.paints.single.style;
    for (final void Function() mutate in [
      model.styles.clear,
      model.uses.clear,
      style.parts.clear,
      style.uses.clear,
      part.childIndices.clear,
      part.paints.clear,
      part.filter!.flags.clear,
      paint.assignments.clear,
    ]) {
      check(mutate).throws<UnsupportedError>();
    }
    check(() => part.filter!.nameBytes[0] = 0).throws<UnsupportedError>();
    check(paint.assignments.singleWhere((assignment) => assignment.parameter == .dash).dash!.lengths.clear).throws<UnsupportedError>();
    check(() => AiNativePaintStyle.decode(records: model.structure.drawing.records, record: _paint('2 w').record)).throws<ArgumentError>();
  });

  test('keeps large sibling inventories linear and respects original depth limits', () {
    const String part = '/BasicFilter : (Fill Style Filter) 0 0 /Filter , /Dictionary : /FillStyle : 0.3 g /Def ; (FillStyle) , ; /Dict ; /Part ,';
    final String source = '/KnownStyle : (board-0) /Name , /ActiveStyle : /CompoundFilter : (Stack Style Filter) 0 0 /Filter , ${part * 200} ; /Execution ; /Def ;';
    final AiNativeAppearance style = appearanceModel(source).styles.single;
    check(style.parts).length.equals(201);
    check(style.parts.first.childIndices).length.equals(200);
    check(() => appearanceModel(source, limits: const AiNativeLimits(maxDepth: 3))).throws<AiLimitException>();
  });

  test('reports typed appearance data separately from opaque effects and editing', () {
    final String style = artboardActiveStyle();
    for (final bool malformed in [false, true]) {
      final String source = objectSource('', setup: malformed ? style.replaceFirst('2 w', '-2 w') : style);
      final AiNativeCapabilityReport report = AiNativeCapabilityReport.inspect(source: AiNativeData.extract(const AiCodec().decode(latin1.encode(source))).single);
      final List<AiNativeCapability> findings = report.findings.where((finding) => finding.feature == .appearance).toList();
      check(findings.any((finding) => finding.support == .typed)).isTrue();
      check(findings.any((finding) => finding.support == .preserved)).isTrue();
      check(findings.any((finding) => finding.support == .malformed)).equals(malformed);
      check(findings.every((finding) => !finding.editable && finding.edits.isEmpty)).isTrue();
    }
  });
}
