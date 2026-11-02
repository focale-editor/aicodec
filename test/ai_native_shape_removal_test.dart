import 'dart:convert';

import 'package:aicodec/aicodec.dart';
import 'package:checks/checks.dart';
import 'package:test/test.dart';

import 'ai_native_shape_lifecycle_test.dart' show identifiedShapeLifecycleSource, shapeLifecycleSource, shapeLifecycleStateSource;

/// Opens complete immutable native snapshots under optional source limits.
AiNativeDrawing _drawing(String source, {AiNativeLimits limits = const AiNativeLimits()}) => AiNativeDrawing.decode(
  records: AiNativeRecords.decode(
    program: AiProgram.decode(bytes: latin1.encode(source), limits: limits),
  ),
);

/// Retains each complete authoring/printing pair's original bytes.
List<int> _bytes(AiNativeDrawing drawing, AiLiveShape shape) => drawing.records.program.bytes.sublist(shape.start, shape.end);

/// Supplies ordinary artwork after the final pair's applied native style.
String followingShapeSource({bool reset = false}) => shapeLifecycleSource().replaceFirst('%%Trailer', '${reset ? '0.7 g\n' : ''}70 70 m 80 70 L 80 80 L f\n%%Trailer');

/// Checks complete removal, inherited state, references and atomic refusals.
void main() {
  test('removes both representations and alternatives while retaining the shared style', () {
    final String text = shapeLifecycleSource();
    final AiNativeDrawing source = _drawing(text);
    final AiNativeDrawing result = source.removeLiveShapes(shapes: [source.liveShapes.first]);
    check(result.liveShapes).length.equals(1);
    check(result.paths).length.equals(4);
    check(result.groups).length.equals(2);
    check(_bytes(result, result.liveShapes.single)).deepEquals(_bytes(source, source.liveShapes.last));
    final AiNativeContainer style = result.liveShapes.single.style!;
    check(result.records.program.bytes.sublist(style.start, style.end)).deepEquals(source.records.program.bytes.sublist(source.liveShapes.first.style!.start, source.liveShapes.first.style!.end));
    check(latin1.decode(source.records.program.bytes)).equals(text);
  });

  test('removes all selected pairs atomically against original source offsets', () {
    final AiNativeDrawing source = _drawing(shapeLifecycleSource());
    final AiNativeDrawing result = source.removeLiveShapes(shapes: source.liveShapes.reversed.toList());
    check(result.liveShapes).isEmpty();
    check(result.paths).isEmpty();
    check(result.groups).isEmpty();
    check(result.records.containers.where((record) => record.type == 'KnownStyle')).length.equals(1);
    check(result.items.whereType<AiNativeInstruction>().where((item) => item.operator == 'XW')).isEmpty();
  });

  test('deletes distinct saved identities in both native metadata alternatives', () {
    final AiNativeDrawing source = _drawing(identifiedShapeLifecycleSource());
    final AiNativeDrawing result = source.removeLiveShapes(shapes: [source.liveShapes.first]);
    check(AiNativeStructure.decode(drawing: result).identifiers).isEmpty();
    check(result.liveShapes).length.equals(1);
    check(_bytes(result, result.liveShapes.single)).deepEquals(_bytes(source, source.liveShapes.last));
  });

  test('retains public and private assignments in their original order', () {
    final String text = shapeLifecycleStateSource().replaceFirst('%_10 20 m', '%_[3 4] 2 d\n%_10 20 m');
    final AiNativeDrawing source = _drawing(text);
    final AiNativeDrawing result = source.removeLiveShapes(shapes: [source.liveShapes.first]);
    final List<AiNativeInstruction> before = source.items
        .whereType<AiNativeInstruction>()
        .where((item) => item.start < source.liveShapes.last.start && const {'D', 'd'}.contains(item.operator))
        .toList();
    final List<AiNativeInstruction> after = result.items
        .whereType<AiNativeInstruction>()
        .where((item) => item.start < result.liveShapes.single.start && const {'D', 'd'}.contains(item.operator))
        .toList();
    check(after.map((item) => [item.operator, item.isPrivate, item.operands.map((operand) => operand.lexeme).toList()])).deepEquals(
      before.map((item) => [item.operator, item.isPrivate, item.operands.map((operand) => operand.lexeme).toList()]),
    );
    check(latin1.decode(result.records.program.bytes)).contains('%_[3 4] 2 d');
  });

  test('does not require unknown incoming defaults that deleted artwork never reads', () {
    final AiNativeDrawing source = _drawing(shapeLifecycleSource().replaceFirst('0 D ', '').replaceFirst('*u', '1 D\n*u'));
    check(() => source.duplicateLiveShapes(shapes: [source.liveShapes.first])).throws<UnsupportedError>();
    check(source.removeLiveShapes(shapes: [source.liveShapes.first]).liveShapes).length.equals(1);
  });

  test('refuses deletion when following ordinary art inherits unresolved style effects', () {
    final String text = followingShapeSource();
    final AiNativeDrawing source = _drawing(text);
    check(() => source.removeLiveShapes(shapes: [source.liveShapes.last])).throws<UnsupportedError>();
    check(() => source.removeLiveShapes(shapes: source.liveShapes)).throws<UnsupportedError>();
    check(latin1.decode(source.records.program.bytes)).equals(text);
    final AiNativeDrawing reset = _drawing(followingShapeSource(reset: true));
    final AiNativeDrawing result = reset.removeLiveShapes(shapes: reset.liveShapes);
    check(result.paths).length.equals(1);
    check(result.paths.single.geometry.first.numbers).isNotNull().deepEquals([70, 70]);
  });

  test('restores definite scalar style assignments before retained artwork', () {
    final String text = shapeLifecycleSource().replaceFirst('0 0 0 1 k /Def', '2 w 0 0 0 1 k /Def').replaceFirst('1 (Shared) XW', '1 (Shared) XW\n10 10 m 20 20 L s');
    final AiNativeDrawing source = _drawing(text);
    final AiNativeDrawing result = source.removeLiveShapes(shapes: [source.liveShapes.first]);
    check(latin1.decode(result.records.program.bytes)).contains('%_2 w');
    check(result.paths).length.equals(5);
    final AiNativeDrawing hidden = _drawing(text.replaceFirst('1 /Visible', '0 /Visible'));
    check(() => hidden.removeLiveShapes(shapes: [hidden.liveShapes.first])).throws<UnsupportedError>();
  });

  test('retains anonymous opaque setup data but refuses identified deletion beside it', () {
    for (final bool identified in [false, true]) {
      final String text = (identified ? identifiedShapeLifecycleSource() : shapeLifecycleSource()).replaceFirst('%%EndSetup', '/Dictionary : /XMLUID : (author) ; (UnknownReference) , ;\n%%EndSetup');
      final AiNativeDrawing source = _drawing(text);
      if (identified) {
        check(() => source.removeLiveShapes(shapes: [source.liveShapes.first])).throws<UnsupportedError>();
      } else {
        check(latin1.decode(source.removeLiveShapes(shapes: [source.liveShapes.first]).records.program.bytes)).contains('(UnknownReference)');
      }
      check(latin1.decode(source.records.program.bytes)).equals(text);
    }
  });

  test('refuses ambiguous saved aliases and unknown shared style reference owners', () {
    for (final String text in [
      identifiedShapeLifecycleSource().replaceFirst('(older)', '(author)'),
      identifiedShapeLifecycleSource().replaceFirst('%%EndSetup', '/KnownStyle : (Unused) /Name , /ActiveStyle : /Dictionary : /XMLUID : (author) ; (Reference) , ; /Execution ; /Def ;\n%%EndSetup'),
    ]) {
      final AiNativeDrawing source = _drawing(text);
      check(() => source.removeLiveShapes(shapes: [source.liveShapes.first])).throws<UnsupportedError>();
    }
  });

  test('rejects malformed, conditional and unresolved selected pairs', () {
    for (final String text in [
      shapeLifecycleSource().replaceFirst('1 (Shared) XW', '1 (Missing) XW'),
      shapeLifecycleSource().replaceFirst('6 () XW', '6 (Other) XW'),
      shapeLifecycleSource().replaceFirst('%_/ArtDictionary :', '%_/ArtDictionary : (x) /String (UnknownReference) ,'),
      shapeLifecycleSource().replaceFirst('/BasicFilter :', '/BasicFilter : (Unknown.aip) /PluginFileName ,'),
    ]) {
      final AiNativeDrawing source = _drawing(text);
      check(() => source.removeLiveShapes(shapes: [source.liveShapes.first])).throws<UnsupportedError>();
      check(latin1.decode(source.records.program.bytes)).equals(text);
    }
  });

  test('removes owned counts and panel flags without leaving consumed attachments', () {
    final String text = shapeLifecycleSource().replaceFirst('\nu\n', '\n0 Ae\nu\n').replaceFirst('%_10 20 m', '%_4 As\n%_10 20 m').replaceFirst('30 40 L 10 40 L n', '30 40 L 10 40 L 10 20 L n');
    final AiNativeDrawing source = _drawing(text);
    final AiNativeDrawing result = source.removeLiveShapes(shapes: [source.liveShapes.first]);
    check(result.items.whereType<AiNativeInstruction>().where((item) => const {'Ae', 'As'}.contains(item.operator))).isEmpty();
    check(result.liveShapes).length.equals(1);
  });

  test('rejects empty, duplicate, foreign and stale source selections', () {
    final AiNativeDrawing source = _drawing(shapeLifecycleSource());
    for (final List<AiLiveShape> shapes in [
      <AiLiveShape>[],
      [source.liveShapes.first, source.liveShapes.first],
      [_drawing(shapeLifecycleSource()).liveShapes.first],
    ]) {
      check(() => source.removeLiveShapes(shapes: shapes)).throws<ArgumentError>();
    }
    final AiNativeDrawing changed = source.removeLiveShapes(shapes: [source.liveShapes.first]);
    check(() => changed.removeLiveShapes(shapes: [source.liveShapes.last])).throws<ArgumentError>();
  });

  test('retains parser limits after deletion and permits further native edits', () {
    final String text = shapeLifecycleSource();
    final AiNativeDrawing source = _drawing(text, limits: AiNativeLimits(maxDecodedBytes: text.length));
    final AiNativeDrawing result = source.removeLiveShapes(shapes: [source.liveShapes.first]);
    check(result.records.program.limits).identicalTo(source.records.program.limits);
    final AiNativeDrawing translated = result.translateLiveShapes(shapes: result.liveShapes, deltaX: 5, deltaY: 3);
    check(translated.liveShapes.single.parameters['ai::Rectangle::CenterX']!.number).equals(8005);
  });

  test('reports pair removal as requiring state and reference qualification', () {
    final AiNativeSource source = AiNativeData.extract(const AiCodec().decode(latin1.encode(shapeLifecycleSource()))).single;
    final AiNativeCapabilityReport report = AiNativeCapabilityReport.inspect(source: source);
    for (final AiNativeCapability finding in report.findings.where((finding) => finding.feature == .liveShape)) {
      check(finding.edits.singleWhere((edit) => edit.operation == .liveShapeRemoval).support).equals(AiNativeEditSupport.requiresValidation);
    }
  });
}
