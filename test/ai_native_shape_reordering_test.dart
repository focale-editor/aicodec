import 'dart:convert';

import 'package:checks/checks.dart';
import 'package:illustratorkit/illustratorkit.dart';
import 'package:test/test.dart';

import 'ai_native_shape_lifecycle_test.dart' show identifiedShapeLifecycleSource;

/// Opens an immutable native snapshot under optional byte and token ceilings.
AiNativeDrawing _drawing(String text, {AiNativeLimits limits = const AiNativeLimits()}) => AiNativeDrawing.decode(
  records: AiNativeRecords.decode(
    program: AiProgram.decode(bytes: latin1.encode(text), limits: limits),
  ),
);

/// Supplies distinct identified pairs with separate inherited native/printing state.
String shapeReorderingSource() {
  final String text = identifiedShapeLifecycleSource();
  final AiNativeDrawing drawing = _drawing(text);
  final String pair = text.substring(drawing.liveShapes.first.start, drawing.liveShapes.first.end);
  final List<String> pairs = [];
  for (int index = 0; index < 3; index++) {
    final String content = pair
        .replaceAll('(author)', '(author_$index)')
        .replaceAll('(older)', '(older_$index)')
        .replaceAll('10 20 m', '${10 + index * 10} 20 m')
        .replaceAll('8000 /Real', '${8000 + index * 100} /Real');
    pairs.add('0 ${0.2 + index * 0.2} 0 0 0 Xy\n%_0 ${0.3 + index * 0.2} 0 0 0 Xy\n${index % 2} D\n%_${1 - index % 2} D\n$content\n');
  }
  return text.replaceRange(drawing.liveShapes.first.start, drawing.liveShapes.last.end, pairs.join('\n'));
}

/// Retains complete pair bytes independently of replay instructions around them.
List<int> _bytes(AiNativeDrawing drawing, AiLiveShape shape) => drawing.records.program.bytes.sublist(shape.start, shape.end);

/// Tracks the fixture's explicit inherited flags and opacity at every contour.
List<List<Object?>> _inputs(AiNativeDrawing drawing, {required bool private}) {
  double? flag;
  double? opacity;
  final List<List<Object?>> result = [];
  for (final AiNativeInstruction item in drawing.items.whereType<AiNativeInstruction>()) {
    if (item.isPrivate && !private) {
      continue;
    }
    if (item.operator == 'D') {
      flag = item.numbers!.single;
    } else if (item.operator == 'Xy') {
      opacity = item.numbers![1];
    } else if (item.operator == 'm') {
      result.add([item.isPrivate, item.numbers!.first, flag, opacity]);
    }
  }
  return result;
}

/// Checks complete pair ordering, inherited attributes, identities and refusals.
void main() {
  test('reorders complete pairs with unchanged identifiers and metadata alternatives', () {
    final AiNativeDrawing source = _drawing(shapeReorderingSource());
    final List<int> order = [2, 0, 1];
    final AiNativeDrawing result = source.reorderLiveShapes(shapes: order.map((index) => source.liveShapes[index]).toList());
    check(result.paths.length).equals(source.paths.length);
    check(result.groups.length).equals(source.groups.length);
    check(result.liveShapes).length.equals(3);
    for (final (int, int) entry in order.indexed) {
      check(_bytes(result, result.liveShapes[entry.$1])).deepEquals(_bytes(source, source.liveShapes[entry.$2]));
    }
    check(AiNativeStructure.decode(drawing: result).identifiers.map((identity) => latin1.decode(identity.bytes))).deepEquals([
      for (final int index in order) ...['author_$index', 'older_$index'],
    ]);
    check(latin1.decode(source.records.program.bytes)).equals(shapeReorderingSource());
  });

  test('moves both printing and native inherited attributes with their source artwork', () {
    final AiNativeDrawing source = _drawing(shapeReorderingSource());
    final List<int> order = [2, 0, 1];
    final AiNativeDrawing result = source.reorderLiveShapes(shapes: order.map((index) => source.liveShapes[index]).toList());
    for (final bool private in [false, true]) {
      final List<List<Object?>> original = _inputs(source, private: private);
      final int count = private ? 4 : 3;
      check(_inputs(result, private: private)).deepEquals([for (final int index in order) ...original.sublist(index * count, (index + 1) * count)]);
    }
  });

  test('reorders selected slots without changing an unselected sibling or its state', () {
    final AiNativeDrawing source = _drawing(shapeReorderingSource());
    final AiNativeDrawing result = source.reorderLiveShapes(shapes: [source.liveShapes.last, source.liveShapes.first]);
    check(_bytes(result, result.liveShapes[1])).deepEquals(_bytes(source, source.liveShapes[1]));
    for (final bool private in [false, true]) {
      final int count = private ? 4 : 3;
      check(_inputs(result, private: private).sublist(count, count * 2)).deepEquals(_inputs(source, private: private).sublist(count, count * 2));
    }
  });

  test('retains external opaque reference records without reallocating saved identities', () {
    final String text = shapeReorderingSource().replaceFirst('%%EndSetup', '/Dictionary : /XMLUID : (author_0) ; (Reference) , ;\n%%EndSetup');
    final AiNativeDrawing source = _drawing(text);
    final AiNativeDrawing result = source.reorderLiveShapes(shapes: source.liveShapes.reversed.toList());
    check(latin1.decode(result.records.program.bytes)).contains('/XMLUID : (author_0) ; (Reference) ,');
    check(AiNativeStructure.decode(drawing: result).identifiers).length.equals(6);
  });

  test('moves the outer panel flag with its complete pair', () {
    final AiNativeDrawing source = _drawing(shapeReorderingSource().replaceFirst('\nu\n', '\n0 Ae\nu\n'));
    final AiNativeDrawing result = source.reorderLiveShapes(shapes: source.liveShapes.reversed.toList());
    final AiNativeObjects objects = AiNativeObjects.decode(drawing: result);
    check(objects.forSource(result.liveShapes.last.appearanceGroup!).expanded).equals(false);
    check(objects.forSource(result.liveShapes.first.appearanceGroup!).expansion).isNull();
  });

  test('returns the original snapshot for an unchanged qualified order', () {
    final AiNativeDrawing source = _drawing(shapeReorderingSource());
    check(source.reorderLiveShapes(shapes: source.liveShapes)).identicalTo(source);
    check(source.reorderLiveShapes(shapes: [source.liveShapes[1]])).identicalTo(source);
  });

  test('preserves unchanged unknown flag origins without inventing defaults', () {
    final AiNativeDrawing source = _drawing(identifiedShapeLifecycleSource().replaceFirst('0 A 0 Xw ', ''));
    final AiNativeDrawing result = source.reorderLiveShapes(shapes: source.liveShapes.reversed.toList());
    check(result.items.whereType<AiNativeInstruction>().where((item) => const {'A', 'Xw'}.contains(item.operator))).isEmpty();
    check(_bytes(result, result.liveShapes.first)).deepEquals(_bytes(source, source.liveShapes.last));
  });

  test('refuses an unknown required input instead of replacing it with a later value', () {
    final String text = identifiedShapeLifecycleSource().replaceFirst('0 D ', '').replaceFirst('*u', '1 D\n*u');
    final AiNativeDrawing source = _drawing(text);
    check(() => source.reorderLiveShapes(shapes: source.liveShapes.reversed.toList())).throws<UnsupportedError>();
    check(latin1.decode(source.records.program.bytes)).equals(text);
  });

  test('refuses an unknown native color inherited from another applied style', () {
    final String text = identifiedShapeLifecycleSource().replaceAll('\n0 0 0 1 k\n', '\n');
    final AiNativeDrawing source = _drawing(text);
    check(() => source.reorderLiveShapes(shapes: source.liveShapes.reversed.toList())).throws<UnsupportedError>();
  });

  test('rejects unresolved outgoing native dependencies and accepts an explicit reset', () {
    for (final bool reset in [false, true]) {
      final String text = shapeReorderingSource().replaceFirst('%%Trailer', '${reset ? '0.7 g\n' : ''}70 70 m 80 80 L f\n%%Trailer');
      final AiNativeDrawing source = _drawing(text);
      if (reset) {
        check(source.reorderLiveShapes(shapes: source.liveShapes.reversed.toList()).paths).length.equals(13);
      } else {
        check(() => source.reorderLiveShapes(shapes: source.liveShapes.reversed.toList())).throws<UnsupportedError>();
      }
    }
  });

  test('permits an unknown outgoing printing stroke when no retained artwork reads it', () {
    final String text = identifiedShapeLifecycleSource().replaceFirst('0 G ', '');
    final AiNativeDrawing initial = _drawing(text);
    final int start = initial.liveShapes.last.start;
    final AiNativeDrawing source = _drawing('${text.substring(0, start)}${text.substring(start).replaceFirst('u\n', 'u\n1 G\n')}');
    check(source.items.whereType<AiNativeInstruction>().where((item) => item.operator == 'G')).length.equals(1);
    final AiNativeDrawing result = source.reorderLiveShapes(shapes: source.liveShapes.reversed.toList());
    check(_bytes(result, result.liveShapes.first)).deepEquals(_bytes(source, source.liveShapes.last));
    check(_bytes(result, result.liveShapes.last)).deepEquals(_bytes(source, source.liveShapes.first));
  });

  test('does not let private restoration hide a changed printing dependency', () {
    final String text = identifiedShapeLifecycleSource().replaceFirst('0 G ', '');
    final AiNativeDrawing initial = _drawing(text);
    final AiLiveShape first = initial.liveShapes.first;
    final AiNativeDrawing source = _drawing(
      '${text.substring(0, first.end)}\n%_0 G\n70 70 m 80 80 L s\n'
      '${text.substring(first.end).replaceFirst('\nu\n', '\nu\n1 G\n')}',
    );
    check(() => source.reorderLiveShapes(shapes: source.liveShapes.reversed.toList()))
        .throws<UnsupportedError>()
        .has((error) => error.message, 'message')
        .isNotNull()
        .contains('unresolved printing state: stroke');
  });

  test('requires the same immediate native parent for every reordered slot', () {
    final String text = identifiedShapeLifecycleSource();
    final AiNativeDrawing initial = _drawing(text);
    final AiLiveShape first = initial.liveShapes.first;
    final AiNativeDrawing source = _drawing('${text.substring(0, first.start)}u\n${text.substring(first.start, first.end)}\nU\n${text.substring(first.end)}');
    check(() => source.reorderLiveShapes(shapes: source.liveShapes.reversed.toList())).throws<ArgumentError>();
  });

  test('rejects empty, duplicate, foreign and stale selections atomically', () {
    final AiNativeDrawing source = _drawing(shapeReorderingSource());
    for (final List<AiLiveShape> shapes in [
      <AiLiveShape>[],
      [source.liveShapes.first, source.liveShapes.first],
      [_drawing(shapeReorderingSource()).liveShapes.first],
    ]) {
      check(() => source.reorderLiveShapes(shapes: shapes)).throws<ArgumentError>();
    }
    final AiNativeDrawing result = source.reorderLiveShapes(shapes: source.liveShapes.reversed.toList());
    check(() => result.reorderLiveShapes(shapes: source.liveShapes)).throws<ArgumentError>();
  });

  test('bounds replay growth under the original native byte limit', () {
    final String text = shapeReorderingSource();
    final AiNativeDrawing source = _drawing(text, limits: AiNativeLimits(maxDecodedBytes: text.length));
    check(() => source.reorderLiveShapes(shapes: source.liveShapes.reversed.toList())).throws<FormatException>();
    check(latin1.decode(source.records.program.bytes)).equals(text);
  });

  test('reports pair reordering as requiring source-specific state validation', () {
    final AiNativeSource source = AiNativeData.extract(const AiCodec().decode(latin1.encode(shapeReorderingSource()))).single;
    final AiNativeCapabilityReport report = AiNativeCapabilityReport.inspect(source: source);
    for (final AiNativeCapability finding in report.findings.where((finding) => finding.feature == .liveShape)) {
      check(finding.edits.singleWhere((edit) => edit.operation == .liveShapeReordering).support).equals(AiNativeEditSupport.requiresValidation);
    }
  });
}
