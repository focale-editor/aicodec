import 'dart:convert';

import 'package:checks/checks.dart';
import 'package:illustratorkit/illustratorkit.dart';
import 'package:test/test.dart';

import 'ai_native_printing_test.dart' show printingFixture;

/// Supplies complete native pairs with explicitly declared incoming attributes.
String shapeLifecycleSource() => latin1
    .decode(printingFixture().records.program.bytes)
    .replaceAll('% retained contour comment', '')
    .replaceFirst('0 0 0 k /Def', '0 0 0 1 k /Def')
    .replaceFirst('/ActiveStyle : /BasicFilter :', '/ActiveStyle : /CompoundFilter : (Chain Style Filter) 0 0 /Filter , 1 /Visible , /BasicFilter :')
    .replaceFirst('; /Execution ; /Def ;', '; /Part ; /Execution ; /Def ;')
    .replaceFirst('%%EndComments', '%AI3_TemplateBox: 50 -50 50 -50\n%AI5_ArtSize: 100 100\n%%EndComments')
    .replaceFirst('%%BeginSetup', '%%BeginProlog\n%%EndProlog\n%%BeginSetup')
    .replaceAll('%_8100 /Real (ai::Rectangle::CenterY) ,', '%_8100 /Real (ai::Rectangle::CenterY) ,\n%_20 /Real (ai::Rectangle::Width) , 20 /Real (ai::Rectangle::Height) ,')
    .replaceFirst('17 FutureNeighbor\n%_/FutureRecord : 42 /Int (Opaque) , ;\n', '')
    .replaceFirst('%%EndSetup', '%%EndSetup\n0 A 0 Xw 1 Ap 0 D 0 XR 0 O 0 R 0 g 0 G 0 J 0 j 1 w 10 M []0 d 0 1 0 0 0 Xy');

/// Retains separate saved identities for the newer and older metadata owners.
String identifiedShapeLifecycleSource() => shapeLifecycleSource()
    .replaceFirst('%AI17_Begin_Content_if_version_gt:17 4\n%_/ArtDictionary :', '%AI17_Begin_Content_if_version_gt:17 4\n%_/ArtDictionary :\n%_/XMLUID : (author) ; (AI10_ArtUID) ,')
    .replaceFirst('%_/ArtDictionary : (0)', '%_/ArtDictionary : /XMLUID : (older) ; (AI10_ArtUID) , (0)');

/// Declares different inherited flags for printing and native interpretation.
String shapeLifecycleStateSource() =>
    shapeLifecycleSource().replaceFirst('%%EndSetup', '%%EndSetup\n0 D').replaceFirst('0 A 0 Xw', '%_1 D\n0 A 0 Xw').replaceFirst('0 D 0 XR', '0 XR').replaceFirst('*u', '1 D\n*u');

/// Reads a source without sharing mutable native handles across snapshots.
AiNativeDrawing _drawing(String source, {AiNativeLimits limits = const AiNativeLimits()}) => AiNativeDrawing.decode(
  records: AiNativeRecords.decode(
    program: AiProgram.decode(bytes: latin1.encode(source), limits: limits),
  ),
);

/// Retains exact pair bytes, including both saved metadata alternatives.
List<int> _bytes(AiNativeDrawing drawing, AiLiveShape shape) => drawing.records.program.bytes.sublist(shape.start, shape.end);

/// Verifies whole-pair copying separately from printing-group replacement.
void main() {
  test('copies both native representations, alternatives and shared style atomically', () {
    final AiNativeDrawing source = _drawing(shapeLifecycleSource());
    final AiNativeDrawing result = source.duplicateLiveShapes(shapes: [source.liveShapes.first]);
    check(result.liveShapes).length.equals(3);
    check(result.paths).length.equals(12);
    check(_bytes(result, result.liveShapes[1])).deepEquals(_bytes(source, source.liveShapes.first));
    check(result.liveShapes.every((shape) => shape.isBound)).isTrue();
    check(result.liveShapes[1].style).identicalTo(result.liveShapes.first.style);
    check(result.liveShapes[1].alternativeDictionaries).length.equals(1);
    check(_bytes(result, result.liveShapes.last)).deepEquals(_bytes(source, source.liveShapes.last));
    check(latin1.decode(source.records.program.bytes)).equals(shapeLifecycleSource());
  });

  test('copies a batch against original offsets and permits subsequent parameter edits', () {
    final AiNativeDrawing source = _drawing(shapeLifecycleSource());
    final AiNativeDrawing result = source.duplicateLiveShapes(shapes: source.liveShapes.reversed.toList());
    check(result.liveShapes).length.equals(4);
    final AiNativeDrawing translated = result.translateLiveShapes(shapes: [result.liveShapes[1]], deltaX: 7, deltaY: 3);
    check(translated.liveShapes[1].parameters['ai::Rectangle::CenterX']!.number).equals(8007);
    check(translated.liveShapes[1].parameters['ai::Rectangle::CenterY']!.number).equals(8097);
    check(_bytes(translated, translated.liveShapes.first)).deepEquals(_bytes(source, source.liveShapes.first));
    check(_bytes(translated, translated.liveShapes.last)).deepEquals(_bytes(source, source.liveShapes.last));
  });

  test('requires fresh identities for every copied metadata owner', () {
    final String text = identifiedShapeLifecycleSource();
    final AiNativeDrawing source = _drawing(text);
    final AiLiveShape shape = source.liveShapes.first;
    final List<int> identity = latin1.encode('copy_author');
    final Map<AiNativeContainer, List<int>> identifiers = {shape.dictionary: identity, shape.alternativeDictionaries.single: latin1.encode('copy_older')};
    final AiNativeDrawing result = source.duplicateLiveShapes(shapes: [shape], identifiers: identifiers);
    identity[0] = 120;
    check(AiNativeStructure.decode(drawing: result).identifiers.map((identifier) => latin1.decode(identifier.bytes))).deepEquals(['author', 'older', 'copy_author', 'copy_older']);
    check(() => source.duplicateLiveShapes(shapes: [shape])).throws<ArgumentError>();
    check(() => source.duplicateLiveShapes(shapes: [shape], identifiers: {...identifiers, shape.dictionary: latin1.encode('older')})).throws<ArgumentError>();
    check(() => source.duplicateLiveShapes(shapes: [shape], identifiers: {...identifiers, source.liveShapes.last.dictionary: latin1.encode('extra')})).throws<ArgumentError>();
    final AiNativeDrawing aliased = _drawing(text.replaceFirst('(older)', '(author)'));
    check(
      () => aliased.duplicateLiveShapes(
        shapes: [aliased.liveShapes.first],
        identifiers: {aliased.liveShapes.first.dictionary: latin1.encode('copy_author'), aliased.liveShapes.first.alternativeDictionaries.single: latin1.encode('copy_older')},
      ),
    ).throws<UnsupportedError>();
  });

  test('restores distinct printing and private input flags before a copied pair', () {
    final AiNativeDrawing initialized = _drawing(shapeLifecycleStateSource());
    final AiNativeDrawing result = initialized.duplicateLiveShapes(shapes: [initialized.liveShapes.first]);
    final String prefix = latin1.decode(result.records.program.bytes.sublist(result.liveShapes.first.end, result.liveShapes[1].start));
    check(prefix).contains('0 D');
    check(prefix).contains('%_1 D');
    check(_bytes(result, result.liveShapes[1])).deepEquals(_bytes(initialized, initialized.liveShapes.first));
  });

  test('refuses unknown inherited values instead of inventing drawing defaults', () {
    final String text = shapeLifecycleSource().replaceFirst('0 D ', '').replaceFirst('*u', '1 D\n*u');
    final AiNativeDrawing source = _drawing(text);
    check(() => source.duplicateLiveShapes(shapes: [source.liveShapes.first])).throws<UnsupportedError>();
    check(latin1.decode(source.records.program.bytes)).equals(text);
  });

  test('copies the outer panel flag with the complete source pair', () {
    final AiNativeDrawing source = _drawing(shapeLifecycleSource().replaceFirst('\nu\n', '\n0 Ae\nu\n'));
    final AiNativeDrawing result = source.duplicateLiveShapes(shapes: [source.liveShapes.first]);
    final AiNativeObjects objects = AiNativeObjects.decode(drawing: result);
    check(objects.forSource(result.liveShapes[1].appearanceGroup!).expanded).equals(false);
    check(result.items.whereType<AiNativeInstruction>().where((item) => item.operator == 'Ae')).length.equals(2);
  });

  test('rejects incomplete pairs, unknown metadata, styles and source wrappers', () {
    for (final String text in [
      shapeLifecycleSource().replaceFirst('1 (Shared) XW', '1 (Missing) XW'),
      shapeLifecycleSource().replaceFirst('%_/ArtDictionary :', '%_/ArtDictionary : (x) /String (UnknownReference) ,'),
      shapeLifecycleSource().replaceFirst('(Fill Style Filter)', '(Unknown Filter)'),
      shapeLifecycleSource().replaceFirst('6 () XW', '6 (Other) XW'),
      shapeLifecycleSource().replaceFirst('%_10 20 m', '%_17 FutureState\n%_10 20 m'),
      shapeLifecycleSource().replaceFirst('0 0 Xd', '%AI99_Future: 1\n0 0 Xd'),
    ]) {
      final AiNativeDrawing source = _drawing(text);
      check(() => source.duplicateLiveShapes(shapes: [source.liveShapes.first])).throws<UnsupportedError>();
      check(latin1.decode(source.records.program.bytes)).equals(text);
    }
  });

  test('does not detach a source from an outer conditional or private owner', () {
    final String text = shapeLifecycleSource();
    final AiNativeDrawing source = _drawing(text);
    final AiLiveShape first = source.liveShapes.first;
    final String conditional =
        '${text.substring(0, first.start)}%AI17_Begin_Content_if_version_gt:24 4\n${text.substring(first.start, first.end)}\n%AI17_End_Versioned_Content\n${text.substring(first.end)}';
    final AiNativeDrawing versioned = _drawing(conditional);
    check(() => versioned.duplicateLiveShapes(shapes: [versioned.liveShapes.first])).throws<UnsupportedError>();
  });

  test('rejects stale, foreign, duplicate and empty selections', () {
    final AiNativeDrawing source = _drawing(shapeLifecycleSource());
    final AiNativeDrawing changed = source.duplicateLiveShapes(shapes: [source.liveShapes.first]);
    for (final List<AiLiveShape> shapes in [
      <AiLiveShape>[],
      [source.liveShapes.first, source.liveShapes.first],
      [_drawing(shapeLifecycleSource()).liveShapes.first],
    ]) {
      check(() => source.duplicateLiveShapes(shapes: shapes)).throws<ArgumentError>();
    }
    check(() => changed.duplicateLiveShapes(shapes: [source.liveShapes.first])).throws<ArgumentError>();
  });

  test('bounds serialized copies under the original byte and token budgets', () {
    final String text = shapeLifecycleSource();
    final AiNativeDrawing source = _drawing(text, limits: AiNativeLimits(maxDecodedBytes: text.length + 20));
    check(() => source.duplicateLiveShapes(shapes: [source.liveShapes.first])).throws<FormatException>();
    check(latin1.decode(source.records.program.bytes)).equals(text);
  });

  test('preserves private point counts and rejects repeated or invalid owners', () {
    final String text = shapeLifecycleSource().replaceFirst('%_10 20 m', '%_4 As\n%_10 20 m').replaceFirst('30 40 L 10 40 L n', '30 40 L 10 40 L 10 20 L n');
    final AiNativeDrawing source = _drawing(text);
    final AiNativeDrawing result = source.duplicateLiveShapes(shapes: [source.liveShapes.first]);
    check(result.items.whereType<AiNativeInstruction>().where((item) => item.operator == 'As' && item.isPrivate)).length.equals(2);
    for (final String invalid in [text.replaceFirst('4 As', '4 As 4 As'), text.replaceFirst('4 As', '8 As'), text.replaceFirst('10 40 L 10 20 L n', '10 40 L 11 20 L n')]) {
      final AiNativeDrawing malformed = _drawing(invalid);
      check(() => malformed.duplicateLiveShapes(shapes: [malformed.liveShapes.first])).throws<UnsupportedError>();
    }
  });

  test('refuses attached prefix and postfix metadata and external plug-in styles', () {
    for (final String text in [
      shapeLifecycleSource().replaceFirst('\nu\n', '\n%AI3_Note: Attached\nu\n'),
      shapeLifecycleSource().replaceFirst('\nu\n', '\n19 FutureOwner\nu\n'),
      shapeLifecycleSource().replaceFirst('1 (Shared) XW', '1 (Shared) XW\n%AI3_Note: Attached'),
      shapeLifecycleSource().replaceFirst('/BasicFilter :', '/BasicFilter : (Unknown.aip) /PluginFileName ,'),
      shapeLifecycleSource().replaceFirst('1 /Visible', '(Unknown) /Visible'),
      shapeLifecycleSource().replaceFirst('(Fill Style Filter) 0 0', '(Fill Style Filter) 99 0'),
      shapeLifecycleSource()
          .replaceFirst('/KnownStyle :', '%AI17_Begin_Content_if_version_gt:24 4\n/KnownStyle :')
          .replaceFirst('%%EndSetup', '%AI17_Alternate_Content\n%AI17_End_Versioned_Content\n%%EndSetup'),
    ]) {
      final AiNativeDrawing source = _drawing(text);
      check(() => source.duplicateLiveShapes(shapes: [source.liveShapes.first])).throws<UnsupportedError>();
    }
  });

  test('does not infer inherited state by executing both saved version branches', () {
    final String text = shapeLifecycleSource()
        .replaceFirst('0 D ', '')
        .replaceFirst('*u', '1 D\n*u')
        .replaceFirst('\nu\n', '\n%AI17_Begin_Content_if_version_gt:24 4\n0 D\n%AI17_Alternate_Content\n1 D\n%AI17_End_Versioned_Content\nu\n');
    final AiNativeDrawing source = _drawing(text);
    check(() => source.duplicateLiveShapes(shapes: [source.liveShapes.first])).throws<UnsupportedError>();
  });

  test('serializes inherited private dash arrays as complete native operands', () {
    final String text = shapeLifecycleSource().replaceFirst('0 0 0 1 k /Def', '[3 4] 1 d 0 0 0 1 k /Def').replaceFirst('30 40 L 10 40 L f', '30 40 L 10 40 L s');
    final AiNativeDrawing source = _drawing(text);
    final AiNativeDrawing result = source.duplicateLiveShapes(shapes: [source.liveShapes.first]);
    final String prefix = latin1.decode(result.records.program.bytes.sublist(result.liveShapes.first.end, result.liveShapes[1].start));
    check(prefix).contains('%_[] 0 d');
    check(_bytes(result, result.liveShapes[1])).deepEquals(_bytes(source, source.liveShapes.first));
  });

  test('reports complete-pair duplication as requiring independent lifecycle validation', () {
    final AiNativeSource source = AiNativeData.extract(const AiCodec().decode(latin1.encode(shapeLifecycleSource()))).single;
    final AiNativeCapabilityReport report = AiNativeCapabilityReport.inspect(source: source);
    final List<AiNativeCapability> shapes = report.findings.where((finding) => finding.feature == .liveShape).toList();
    check(shapes).length.equals(2);
    for (final AiNativeCapability shape in shapes) {
      check(shape.edits.singleWhere((edit) => edit.operation == .liveShapeDuplication).support).equals(AiNativeEditSupport.requiresValidation);
    }
  });
}
