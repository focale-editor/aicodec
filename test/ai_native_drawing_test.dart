import 'dart:convert';

import 'package:aicodec/aicodec.dart';
import 'package:checks/checks.dart';
import 'package:test/test.dart';

/// Creates a source-backed drawing with ordinary DSC bounds and fixed artboards.
AiNativeDrawing _drawing(String body, {String setup = ''}) => AiNativeDrawing.decode(
  records: AiNativeRecords.decode(
    program: AiProgram.decode(bytes: latin1.encode('%!PS-Adobe-3.0\n%%BoundingBox: 0 0 100 100\n%%HiResBoundingBox: 0 0 100 100\n%%EndComments\n$setup\n%%EndSetup\n$body\n%%PageTrailer\n%%EOF\n')),
  ),
);

/// Native parameter dictionary independent of fixture artwork or source code.
String _dictionary({String handler = 'ai::Rectangle', bool redundant = false, String extra = ''}) =>
    '''%_/ArtDictionary :
%_/Dictionary : ${redundant ? '/NotRecorded ,' : ''}
%_($handler) /UnicodeString (ai::LiveShape::HandlerName) ,
%_/Dictionary : ${redundant ? '/NotRecorded ,' : ''}
%_8000 /Real ($handler::CenterX) ,
%_8100 /Real ($handler::CenterY) ,
%_$extra
%_; (ai::LiveShape::Params) ,
%_; (ai::LiveShape) ,
%_;
''';

/// Synthetic self-contained solid style with an editable authoring appearance.
const String _style = '''/KnownStyle : (Solid) /Name ,
/ActiveStyle : /BasicFilter :
(Fill Style Filter) 0 0 /Filter ,
/Dictionary : /FillStyle : 0 0 0 k /Def ; (FillStyle) , ; /Dict ; /Execution ; /Def ;
''';

/// Printable compound appearance and private outline sharing one live shape.
String _alternate({bool versioned = false, String between = ''}) =>
    '''u
10 20 m 30 20 L 30 40 L 10 40 L f
*u
9 19 m 31 19 L 31 41 L 9 41 L f
11 21 m 11 39 L 29 39 L 29 21 L f
*U
U
${_dictionary(redundant: true)}
$between
0 0 Xd
6 () XW
%_10 20 m
%_30 20 L
%_30 40 L
%_10 40 L
%_n
${versioned ? '%AI17_Begin_Content_if_version_gt:17 4' : ''}
${_dictionary()}
${versioned ? '%AI17_Alternate_Content\n%_/ArtDictionary : (0) /String (BBAccumRotation) , ;\n%AI17_End_Versioned_Content' : ''}
1 (Solid) XW
''';

/// Exercises atomic edits and explicit dependency failures on VM and JavaScript.
void main() {
  test('translates direct native geometry and opposite canvas y without mutation', () {
    final String body = '10 20 m 30 20 L 30 40 L 10 40 L b\n${_dictionary(extra: '20 /Real (ai::Rectangle::Width) ,')}';
    final AiNativeDrawing source = _drawing(body);
    final List<int> original = source.records.program.bytes.toList();
    final AiNativeDrawing changed = source.translateLiveShapes(shapes: source.liveShapes, deltaX: 7, deltaY: -3);
    final AiLiveShape shape = changed.liveShapes.single;
    check(shape.path!.segments.map((segment) => segment.coordinates).toList()).deepEquals([
      [17.0, 17.0],
      [37.0, 17.0],
      [37.0, 37.0],
      [17.0, 37.0],
    ]);
    check(shape.parameters['ai::Rectangle::CenterX']!.number).equals(8007);
    check(shape.parameters['ai::Rectangle::CenterY']!.number).equals(8103);
    check(shape.parameters['ai::Rectangle::Width']!.number).equals(20);
    check(shape.path!.paint.operator).equals('b');
    check(source.records.program.bytes).deepEquals(original);
    final String text = latin1.decode(changed.records.program.bytes);
    check(text.contains('%%BoundingBox: 0 -3 107 100')).isTrue();
    check(text.contains('%_20 /Real (ai::Rectangle::Width) ,')).isTrue();
  });

  test('moves every expanded contour, private outline and redundant center together', () {
    final AiNativeDrawing source = _drawing(_alternate(between: '0 0.25 0 0 0 Xy'), setup: _style);
    final AiLiveShape original = source.liveShapes.single;
    check(original.isBound).isTrue();
    check(original.appearancePaths).length.equals(3);
    check(original.path!.isPrivate).isTrue();
    final AiNativeDrawing changed = source.translateLiveShapes(shapes: [original], deltaX: -2, deltaY: 5);
    for (int path = 0; path < source.paths.length; path++) {
      for (int segment = 0; segment < source.paths[path].segments.length; segment++) {
        final List<double> before = source.paths[path].segments[segment].coordinates;
        final List<double> after = changed.paths[path].segments[segment].coordinates;
        check(after[0] - before[0]).equals(-2);
        check(after[1] - before[1]).equals(5);
      }
    }
    final AiLiveShape moved = changed.liveShapes.single;
    final AiNativeContainer redundant = moved.appearanceDictionary!['ai::LiveShape']!.container!['ai::LiveShape::Params']!.container!;
    check(redundant['ai::Rectangle::CenterX']!.number).equals(7998);
    check(redundant['ai::Rectangle::CenterY']!.number).equals(8095);
    check(moved.parameters['ai::Rectangle::CenterY']!.number).equals(8095);
    check(latin1.decode(changed.records.program.bytes).contains('0 0.25 0 0 0 Xy')).isTrue();
    check(changed.records.program.bytes.sublist(moved.style!.start, moved.style!.end)).deepEquals(source.records.program.bytes.sublist(original.style!.start, original.style!.end));
  });

  test('retains version-dependent metadata sharing one authoritative outline', () {
    final AiNativeDrawing source = _drawing(_alternate(versioned: true), setup: _style);
    check(source.liveShapes.single.alternativeDictionaries).length.equals(1);
    final AiNativeDrawing changed = source.translateLiveShapes(shapes: source.liveShapes, deltaX: 2, deltaY: 4);
    check(changed.liveShapes.single.isBound).isTrue();
    check(changed.liveShapes.single.alternativeDictionaries.single['BBAccumRotation']!.text()).equals('0');
    check(changed.items.whereType<AiNativeVersionComment>()).length.equals(3);
  });

  test('moves all supported handlers without changing curve or corner semantics', () {
    for (final String handler in ['ai::Rectangle', 'ai::Ellipse', 'ai::Polygon', 'ai::Star', 'ai::Line']) {
      final AiNativeDrawing source = _drawing('1 2 m 3 4 5 6 7 8 C 9 10 11 12 v 13 14 15 16 Y S\n${_dictionary(handler: handler)}');
      final AiNativeDrawing changed = source.translateLiveShapes(shapes: source.liveShapes, deltaX: 20, deltaY: -10);
      check(changed.paths.single.segments.map((segment) => segment.operator).toList()).deepEquals(['m', 'C', 'v', 'Y']);
      check(changed.paths.single.segments[1].coordinates).deepEquals([23.0, -6.0, 25.0, -4.0, 27.0, -2.0]);
      check(changed.liveShapes.single.parameters['$handler::CenterY']!.number).equals(8110);
    }
  });

  test('rejects stale, duplicate, empty and nonfinite edits atomically', () {
    final AiNativeDrawing source = _drawing('10 20 m 30 40 L S\n${_dictionary()}');
    final AiNativeDrawing changed = source.translateLiveShapes(shapes: source.liveShapes, deltaX: 1, deltaY: 1);
    check(() => changed.translateLiveShapes(shapes: source.liveShapes, deltaX: 1, deltaY: 1)).throws<ArgumentError>();
    check(() => source.translateLiveShapes(shapes: [], deltaX: 1, deltaY: 1)).throws<ArgumentError>();
    check(() => source.translateLiveShapes(shapes: [source.liveShapes.single, source.liveShapes.single], deltaX: 1, deltaY: 1)).throws<ArgumentError>();
    for (final double value in [double.nan, double.infinity, 1e308]) {
      check(() => source.translateLiveShapes(shapes: source.liveShapes, deltaX: value, deltaY: 0)).throws<ArgumentError>();
    }
  });

  test('retains unselected artwork and detects ambiguous authoring ownership', () {
    final String first = '10 20 m 30 40 L S\n${_dictionary()}';
    final String second = '50 60 m 70 80 L S\n${_dictionary(handler: 'ai::Line')}';
    final AiNativeDrawing source = _drawing('$first$second');
    final AiNativeDrawing changed = source.translateLiveShapes(shapes: [source.liveShapes.first], deltaX: 1, deltaY: 2);
    check(changed.paths.last.segments.map((segment) => segment.coordinates).toList()).deepEquals([
      [50.0, 60.0],
      [70.0, 80.0],
    ]);
    check(changed.liveShapes.last.parameters['ai::Line::CenterX']!.number).equals(8000);
    final String extraPath = _alternate().replaceFirst('6 () XW', '6 () XW\n%_0 0 m\n%_1 1 L\n%_N');
    final AiNativeDrawing ambiguous = _drawing(extraPath, setup: _style);
    check(ambiguous.liveShapes.single.isBound).isFalse();
    check(() => ambiguous.translateLiveShapes(shapes: ambiguous.liveShapes, deltaX: 1, deltaY: 2)).throws<UnsupportedError>();
  });

  test('rejects positional style resources, transforms and unrecognized metadata', () {
    for (final String command in ['(Pattern) p', '1 0 0 1 0 0 cm', 'W', 'newEffect']) {
      final AiNativeDrawing source = _drawing('$command\n10 20 m 30 40 L S\n${_dictionary()}');
      check(() => source.translateLiveShapes(shapes: source.liveShapes, deltaX: 1, deltaY: 2)).throws<UnsupportedError>();
    }
    for (final String extra in ['1 /Real (ai::Rectangle::FuturePosition) ,', '/Dictionary : ; (dependency) ,']) {
      final AiNativeDrawing source = _drawing('10 20 m 30 40 L S\n${_dictionary(extra: extra)}');
      check(() => source.translateLiveShapes(shapes: source.liveShapes, deltaX: 1, deltaY: 2)).throws<UnsupportedError>();
    }
    final AiNativeDrawing effect = _drawing(_alternate(), setup: _style.replaceFirst('Fill Style Filter', 'Future Effect'));
    check(() => effect.translateLiveShapes(shapes: effect.liveShapes, deltaX: 1, deltaY: 2)).throws<UnsupportedError>();
  });

  test('reports unresolved bindings and refuses parent appearance dependencies', () {
    final AiNativeDrawing missing = _drawing(_alternate());
    check(missing.liveShapes.single.isBound).isFalse();
    check(() => missing.translateLiveShapes(shapes: missing.liveShapes, deltaX: 1, deltaY: 2)).throws<FormatException>();
    final AiNativeDrawing parent = _drawing('u\n10 20 m 30 40 L S\n${_dictionary()}U\n%_/ArtDictionary : (effect) /String (Unknown) , ;');
    check(() => parent.translateLiveShapes(shapes: parent.liveShapes, deltaX: 1, deltaY: 2)).throws<UnsupportedError>();
  });

  test('rejects malformed native path arities, mixed representations and groups', () {
    for (final String body in ['1 m n', '1 2 m\n%_3 4 L\nn', 'u 1 2 m 3 4 L S *U', '1 2 m', 'u', '*U']) {
      check(() => _drawing(body)).throws<FormatException>();
    }
  });

  test('translates CC gradient printing matrices while retaining relative styles', () {
    const String relative = '1 (Colors) 0.25 0 35 0.8 1 0 0 1 0 0 0.5 Bg';
    final String body = _alternate().replaceFirst('10 40 L f', '10 40 L\nBb\n1 2 90 0.5 Bh\n$relative\n20 0 0 30 10 20 Xm\n20 0 0 30 10 20 Bm\n40 0 0 30 -30 20 Bc\nf\n0 BB');
    final String style = _style.replaceFirst('0 0 0 k', 'Bb\n${relative.replaceFirst('1 (Colors)', '2 (Colors)')}\n0 BB');
    final AiNativeDrawing source = _drawing(body, setup: style);
    final AiNativeDrawing changed = source.translateLiveShapes(shapes: source.liveShapes, deltaX: 7, deltaY: -3);
    final AiNativeGradient gradient = changed.gradients.single;
    check(gradient.paths).length.equals(1);
    check(gradient.geometry.relativeToArtwork).isTrue();
    check(gradient.geometry.origin).deepEquals([0.25, 0.0]);
    check(gradient.geometry.matrix).deepEquals([1.0, 0.0, 0.0, 1.0, 0.0, 0.0]);
    check(gradient.highlight!.numbers!).deepEquals([1.0, 2.0, 90.0, 0.5]);
    check(gradient.imagingMatrices.map((matrix) => matrix.numbers!.skip(4).toList()).toList()).deepEquals([
      [17.0, 17.0],
      [17.0, 17.0],
      [-23.0, 17.0],
    ]);
    final AiNativeContainer originalStyle = source.liveShapes.single.style!;
    final AiNativeContainer changedStyle = changed.liveShapes.single.style!;
    check(changed.records.program.bytes.sublist(changedStyle.start, changedStyle.end)).deepEquals(source.records.program.bytes.sublist(originalStyle.start, originalStyle.end));
    check(changed.records.roots.where((record) => record.type == 'KnownStyle')).length.equals(1);
  });

  test('binds a direct gradient fill across its closing BB command', () {
    final AiNativeDrawing source = _drawing('10 20 m 30 40 L\nBb\n(Colors) 1 2 30 40 2 0 0 3 5 6 Bg\nf\n0 BB\n${_dictionary()}');
    check(source.liveShapes.single.isBound).isTrue();
    check(source.gradients.single.geometry.flag).equals(0);
    check(source.gradients.single.geometry.relativeToArtwork).isFalse();
    final AiNativeDrawing changed = source.translateLiveShapes(shapes: source.liveShapes, deltaX: 7, deltaY: -3);
    check(changed.gradients.single.geometry.origin).deepEquals([1.0, 2.0]);
    check(changed.gradients.single.geometry.matrix).deepEquals([2.0, 0.0, 0.0, 3.0, 12.0, 3.0]);
    check(changed.paths.single.segments.first.coordinates).deepEquals([17.0, 17.0]);
  });

  test('copies positional known styles without modifying unselected references', () {
    final String style = _style.replaceFirst('0 0 0 k', 'Bb 2 (Colors) 1 2 30 40 2 0 0 3 5 6 Bg 0 BB');
    final AiNativeDrawing source = _drawing('${_alternate()}${_alternate()}', setup: '$style${_style.replaceFirst('(Solid)', '(AiCodec translated 1)')}');
    final AiNativeDrawing changed = source.translateLiveShapes(shapes: [source.liveShapes.first], deltaX: 7, deltaY: -3);
    check(changed.liveShapes.first.styleName).equals('AiCodec translated 2');
    check(changed.liveShapes.last.styleName).equals('Solid');
    check(changed.liveShapes.last.path!.segments.first.coordinates).deepEquals([10.0, 20.0]);
    final AiNativeContainer copied = changed.liveShapes.first.style!;
    final AiNativeContainer paint = changed.records.containers.singleWhere((record) => record.type == 'FillStyle' && record.start > copied.start && record.end < copied.end);
    check(AiNativePaintStyle.decode(records: changed.records, record: paint).gradients.single.geometry.matrix).deepEquals([2.0, 0.0, 0.0, 3.0, 12.0, 3.0]);
    final AiNativeContainer untouched = changed.liveShapes.last.style!;
    final AiNativeContainer original = source.liveShapes.first.style!;
    check(changed.records.program.bytes.sublist(untouched.start, untouched.end)).deepEquals(source.records.program.bytes.sublist(original.start, original.end));
    final AiNativeDrawing together = source.translateLiveShapes(shapes: source.liveShapes, deltaX: 1, deltaY: 2);
    check(together.liveShapes.first.styleName).equals(together.liveShapes.last.styleName);
    check(together.records.roots.where((record) => record.type == 'KnownStyle')).length.equals(3);
  });

  test('rejects malformed gradient scopes and geometry before any edit', () {
    for (final String block in [
      'Bb',
      '0 BB',
      'Bb Bb 0 BB',
      '2 Bb',
      'Bb 0 BB',
      'Bb 1 (Colors) 0 0 0 1 1 0 0 1 0 0 0 Bg 0 BB',
      'Bb (Colors) 0 0 0 1 1 0 0 1 0 Bg 0 BB',
      'Bb 1 2 Bm 0 BB',
      '1 2 3 4 Bh',
    ]) {
      check(() => _drawing(block)).throws<FormatException>();
    }
    final AiNativeDrawing drawing = _drawing('', setup: _style.replaceFirst('0 0 0 k', 'Bb'));
    final AiNativeContainer paint = drawing.records.containers.singleWhere((record) => record.type == 'FillStyle');
    check(() => AiNativePaintStyle.decode(records: drawing.records, record: paint)).throws<FormatException>();
    final AiNativeDrawing other = _drawing('', setup: _style);
    check(() => AiNativePaintStyle.decode(records: other.records, record: paint)).throws<ArgumentError>();
  });

  test('bounds source fragment copies used by native resource duplication', () {
    final AiProgram program = _drawing('0 0 m 1 1 L S').records.program;
    final int start = program.bodyStart;
    final int end = program.bodyEnd;
    check(AiNativeEditor.copyRange(program: program, start: start, end: end)).deepEquals(program.bytes.sublist(start, end));
    check(() => AiNativeEditor.copyRange(program: program, start: -1, end: end)).throws<ArgumentError>();
    check(
      () => AiNativeEditor.copyRange(
        program: program,
        start: start,
        end: end,
        edits: [AiSourceEdit(start: 0, end: 1, bytes: [])],
      ),
    ).throws<ArgumentError>();
    check(
      () => AiNativeEditor.copyRange(
        program: program,
        start: start,
        end: end,
        edits: [AiSourceEdit(start: end, end: end + 1, bytes: [])],
      ),
    ).throws<ArgumentError>();
  });

  test('retains private style comment prefixes when allocating a positional copy', () {
    final String style = _style.replaceFirst('0 0 0 k', 'Bb 2 (Colors) 1 2 30 40 1 0 0 1 0 0 Bg 0 BB').split('\n').map((line) => '%_$line').join('\n');
    final AiNativeDrawing source = _drawing(_alternate(), setup: style);
    final AiNativeDrawing changed = source.translateLiveShapes(shapes: source.liveShapes, deltaX: 7, deltaY: -3);
    final AiNativeContainer copied = changed.liveShapes.single.style!;
    check(latin1.decode(changed.records.program.bytes.sublist(copied.start - 2, copied.start))).equals('%_');
    check(changed.records.roots.where((record) => record.type == 'KnownStyle')).length.equals(2);
    final AiNativeContainer paint = changed.records.containers.singleWhere((record) => record.type == 'FillStyle' && record.start > copied.start && record.end < copied.end);
    check(AiNativePaintStyle.decode(records: changed.records, record: paint).gradients.single.geometry.matrix.skip(4).toList()).deepEquals([7.0, -3.0]);
  });

  test('enforces aggregate output limits when duplicating gradient style resources', () {
    final AiNativeDrawing original = _drawing(_alternate(), setup: _style.replaceFirst('0 0 0 k', 'Bb 2 (Colors) 1 2 30 40 1 0 0 1 0 0 Bg 0 BB'));
    final AiNativeDrawing bounded = AiNativeDrawing.decode(
      records: AiNativeRecords.decode(
        program: AiProgram.decode(
          bytes: original.records.program.bytes,
          limits: AiNativeLimits(maxDecodedBytes: original.records.program.bytes.length),
        ),
      ),
    );
    check(() => bounded.translateLiveShapes(shapes: bounded.liveShapes, deltaX: 7, deltaY: -3)).throws<FormatException>();
    check(bounded.records.program.bytes).deepEquals(original.records.program.bytes);
  });
}
