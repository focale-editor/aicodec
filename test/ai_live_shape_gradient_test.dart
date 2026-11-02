import 'dart:convert';

import 'package:aicodec/aicodec.dart';
import 'package:checks/checks.dart';
import 'package:test/test.dart';

/// Two-stop radial definition with explicit printing and fallback data.
String _definition({String name = 'Ink'}) =>
    '''%AI5_BeginGradient: ($name)
($name) 1 2 Bd
[
<ff8000> 0 %_Br
[
1 0 50 0 %_BS
%_1 0 1 6 50 0 Bs
0 0 50 100 %_BS
%_0 0 1 6 50 100 Bs
BD
%AI5_EndGradient
''';

/// Native geometry with a centered focus, before its enclosing path paint.
String _gradient({String name = 'Ink', bool note = false}) => 'Bb 0 0 0 0 Bh ${note ? 2 : 1} ($name) 0 0 0 1 1 0 0 1 0 0 1 Bg ${note ? '' : '20 0 0 -30 10 20 Bm'}';

/// A qualified native shape dictionary without unrelated geometry dependencies.
String _dictionary({bool redundant = false, String extra = ''}) =>
    '''%_/ArtDictionary :
%_/Dictionary : ${redundant ? '/NotRecorded ,' : ''}
%_(ai::Rectangle) /UnicodeString (ai::LiveShape::HandlerName) ,
%_/Dictionary : 20 /Real (ai::Rectangle::Width) , 20 /Real (ai::Rectangle::Height) ,
%_1020 /Real (ai::Rectangle::CenterX) , 1970 /Real (ai::Rectangle::CenterY) , 0 /Real (ai::Rectangle::Angle) ,
%_; (ai::LiveShape::Params) , ; (ai::LiveShape) ,
%_$extra
%_;
''';

/// One direct or shared-style appearance, including a private gradient note.
String _shape({bool styled = false}) {
  final String painted = '10 20 m 30 40 L ${_gradient()} f 0 BB';
  return styled ? 'u\n$painted\nU\n${_dictionary(redundant: true)}\n6 () XW\n%_${_gradient(note: true)} 0 BB\n%_10 20 m 30 40 L n\n${_dictionary()}\n1 (Shared) XW' : '$painted\n${_dictionary()}';
}

/// A shared native style referencing the same gradient as its printed contour.
String _style() =>
    '/KnownStyle : (Shared) /Name , /ActiveStyle : /BasicFilter : (Fill Style Filter) 0 0 /Filter , /Dictionary : /FillStyle : ${_gradient(note: true)} 0 BB /Def ; (FillStyle) , ; /Dict ; /Execution ; /Def ;';

/// Builds a bounded source with independently counted gradient banks.
AiNativeDrawing _drawing(String body, {String? setup, int? limit}) => AiNativeDrawing.decode(
  records: AiNativeRecords.decode(
    program: AiProgram.decode(
      bytes: latin1.encode('''%!PS-Adobe-3.0
%%BoundingBox: 0 0 100 100
%%BeginSetup
${setup ?? '1 Bn\n${_definition()}'}
%%EndSetup
$body
%%Trailer
%%EOF
'''),
      limits: AiNativeLimits(maxDecodedBytes: limit ?? 128 * 1024 * 1024),
    ),
  ),
);

/// Isolates the first selected shape to a new explicitly supplied byte name.
AiNativeDrawing _isolate(AiNativeDrawing source, {List<int> name = const [78, 101, 119], List<AiLiveShape>? shapes}) => source.isolateLiveShapeGradient(
  shapes: shapes ?? [source.liveShapes.first],
  sourceNameBytes: latin1.encode('Ink'),
  nameBytes: name,
);

/// Names in source order, retaining private note/printing distinctions.
List<String> _names(AiNativeDrawing source) => source.gradients.map((gradient) => latin1.decode(gradient.geometry.nameBytes)).toList();

/// Complete object bytes, including private notes and the final style binding.
List<int> _objectBytes(AiNativeDrawing drawing, int index) {
  final AiLiveShape shape = drawing.liveShapes[index];
  return drawing.records.program.bytes.sublist(shape.start, shape.end);
}

/// Checks complete native isolation before composing stop and focus edits.
void main() {
  test('isolates a direct shape without altering colors, geometry or other users', () {
    final AiNativeDrawing source = _drawing('${_shape()}\n${_shape()}');
    final AiNativeDrawing isolated = _isolate(source);
    check(_names(isolated)).deepEquals(['New', 'Ink']);
    final AiNativeGradientResources resources = AiNativeGradientResources.decode(records: isolated.records);
    check(resources.definitions).length.equals(2);
    check(resources.definitions.last.stops.map((stop) => stop.color.components).toList()).deepEquals([
      [1],
      [0],
    ]);
    check(resources.definitions.last.ramps.single.channels.single.samples!).deepEquals([255, 128, 0]);
    check(latin1.decode(isolated.records.program.bytes)).contains(_definition());
    check(latin1.decode(isolated.records.program.bytes)).contains('2 Bn');
    check(isolated.paths.map((path) => path.segments.first.coordinates).toList()).deepEquals([
      [10, 20],
      [10, 20],
    ]);
    check(isolated.liveShapes.last.dictionary['Adobe_AI9_ArtStyle_Dictionary']).isNull();
    check(_objectBytes(isolated, 1)).deepEquals(_objectBytes(source, 1));
  });

  test('copies one shared style for the selection and keeps swatch references intact', () {
    final String style = _style();
    final String swatch = '/FillStyle : ${_gradient(note: true)} 0 BB /Def ;';
    final AiNativeDrawing source = _drawing('${_shape(styled: true)}\n${_shape(styled: true)}\n${_shape(styled: true)}', setup: '1 Bn\n${_definition()}\n$style\n$swatch');
    final AiNativeDrawing isolated = _isolate(source, shapes: source.liveShapes.take(2).toList());
    check(_names(isolated)).deepEquals(['New', 'New', 'New', 'New', 'Ink', 'Ink']);
    check(isolated.liveShapes.first.styleName).equals(isolated.liveShapes[1].styleName);
    check(isolated.liveShapes.last.styleName).equals('Shared');
    check(isolated.records.roots.where((record) => record.type == 'KnownStyle')).length.equals(2);
    check(latin1.decode(isolated.records.program.bytes)).contains(style);
    check(latin1.decode(isolated.records.program.bytes)).contains(swatch);
    check(_objectBytes(isolated, 2)).deepEquals(_objectBytes(source, 2));
    final AiNativeContainer paint = isolated.records.containers.firstWhere((record) => record.type == 'FillStyle' && record.start > isolated.liveShapes.first.style!.start);
    check(AiNativePaintStyle.decode(records: isolated.records, record: paint).gradients.single.geometry.nameBytes).deepEquals(latin1.encode('New'));
  });

  test('subsequent global focus and stop edits change only the isolated object', () {
    final AiNativeDrawing source = _drawing('${_shape()}\n${_shape()}');
    final AiNativeDrawing isolated = _isolate(source);
    AiNativeGradientResources resources = AiNativeGradientResources.decode(records: isolated.records);
    resources = resources.setRadialFocus(definition: resources.definitions.last, angle: 90, length: 0.5);
    resources = resources.replaceStops(
      definition: resources.definitions.last,
      stops: [
        AiNativeGradientStop(
          color: AiNativeGradientColor(kind: .gray, components: [0.25]),
          position: 0,
        ),
        AiNativeGradientStop(
          color: AiNativeGradientColor(kind: .gray, components: [0.75]),
          position: 100,
        ),
      ],
      ramps: [
        AiNativeGradientRamp(
          kind: .gray,
          channels: [
            AiNativeGradientChannel.samples(values: [64, 128, 191]),
          ],
        ),
      ],
    );
    final AiNativeDrawing changed = AiNativeDrawing.decode(records: resources.records);
    check(changed.gradients.first.highlight!.numbers![1]).equals(15);
    check(changed.gradients.last.highlight!.numbers!).deepEquals([0, 0, 0, 0]);
    check(resources.definitions.first.stops.map((stop) => stop.color.components).toList()).deepEquals([
      [1],
      [0],
    ]);
    check(resources.definitions.last.stops.map((stop) => stop.color.components).toList()).deepEquals([
      [0.25],
      [0.75],
    ]);
    check(latin1.decode(changed.records.program.bytes)).contains(_definition());
    check(_objectBytes(changed, 1)).deepEquals(_objectBytes(source, 1));
  });

  test('isolates stroke styles repeatedly without reusing existing style names', () {
    final String object = _shape(styled: true).replaceAll('Bb', '1 Bb').replaceFirst('f 0 BB', 'S 1 BB');
    final String style = _style().replaceAll('Fill', 'Stroke').replaceAll('Bb', '1 Bb');
    final AiNativeDrawing source = _drawing('$object\n$object', setup: '1 Bn\n${_definition()}\n$style');
    final AiNativeDrawing first = _isolate(source);
    final AiNativeDrawing second = _isolate(first, name: latin1.encode('Other'), shapes: [first.liveShapes.last]);
    check(_names(second)).deepEquals(['New', 'New', 'Other', 'Other']);
    check(second.gradients.every((gradient) => gradient.onStroke)).isTrue();
    check(second.liveShapes.first.styleName).equals('AiCodec gradient 1');
    check(second.liveShapes.last.styleName).equals('AiCodec gradient 2');
    check(_objectBytes(second, 0)).deepEquals(_objectBytes(first, 0));
    check(second.records.roots.where((record) => record.type == 'KnownStyle')).length.equals(3);
    final AiNativeContainer copied = second.liveShapes.last.style!;
    final AiNativeContainer paint = second.records.containers.singleWhere((record) => record.type == 'StrokeStyle' && record.start > copied.start && record.end < copied.end);
    check(AiNativePaintStyle.decode(records: second.records, record: paint).gradients.single.geometry.nameBytes).deepEquals(latin1.encode('Other'));
  });

  test('copies matching definitions into both printing and nonprinting banks', () {
    final String setup = '1 Bn\n${_definition()}\n%AI5_Begin_NonPrinting\nNp\n2 Bn\n${_definition()}\n${_definition(name: 'Other')}\nNP\n%AI5_End_NonPrinting';
    final AiNativeDrawing isolated = _isolate(_drawing(_shape(), setup: setup));
    final AiNativeGradientResources resources = AiNativeGradientResources.decode(records: isolated.records);
    check(resources.definitions.map((definition) => latin1.decode(definition.nameBytes)).toList()).deepEquals(['Ink', 'New', 'Ink', 'New', 'Other']);
    final String bytes = latin1.decode(isolated.records.program.bytes);
    check(bytes).contains('2 Bn\n');
    check(bytes).contains('Np\n3 Bn\n');
    final AiNativeGradientResources changed = resources.setRadialFocus(definition: resources.definitions[1], angle: 45, length: 0.5);
    check(AiNativeDrawing.decode(records: changed.records).gradients.single.highlight!.numbers![3]).equals(0.5);
  });

  test('escapes arbitrary byte names and ignores fake counts in procedures and nested documents', () {
    const String nested = '%%BeginDocument: nested\n99 Bn\n%%EndDocument\n/proc { 98 Bn } def\n[/dummy 96 Bn] pop\n<< /dummy [95 Bn] >> pop\n';
    final AiNativeDrawing source = _drawing(_shape(), setup: '$nested\n1 Bn\n${_definition()}');
    const List<int> name = [40, 41, 92, 0, 255];
    final AiNativeDrawing isolated = _isolate(source, name: name);
    check(isolated.gradients.single.geometry.nameBytes).deepEquals(name);
    check(AiNativeGradientResources.decode(records: isolated.records).definitions.last.nameBytes).deepEquals(name);
    check(latin1.decode(isolated.records.program.bytes)).contains(nested);
  });

  test('rejects foreign selection, used names and unrelated selected shapes', () {
    final AiNativeDrawing source = _drawing('${_shape()}\n0 0 m 1 1 L f\n${_dictionary()}');
    check(() => _isolate(source, shapes: _drawing(_shape()).liveShapes)).throws<ArgumentError>();
    check(() => _isolate(source, shapes: source.liveShapes)).throws<UnsupportedError>();
    for (final List<int> name in [
      <int>[],
      [256],
      latin1.encode('Ink'),
    ]) {
      check(() => _isolate(source, name: name)).throws<ArgumentError>();
    }
    final AiNativeDrawing occupied = _drawing(_shape(), setup: '2 Bn\n${_definition()}\n${_definition(name: 'New')}');
    check(() => _isolate(occupied)).throws<ArgumentError>();
    final AiNativeDrawing dangling = _drawing(_shape(), setup: '1 Bn\n${_definition()}\n/FillStyle : ${_gradient(name: 'New', note: true)} 0 BB /Def ;');
    check(() => _isolate(dangling)).throws<ArgumentError>();
  });

  test('counts ordinary gradient banks after mark-based font declarations', () {
    const String fonts = '[39/quotesingle 96/grave TE\n%AI3_BeginEncoding: _Font Font\n[/_Font/Font 0 0 1 TZ\n%AI3_EndEncoding AdobeType\n';
    final AiNativeDrawing before = _drawing(_shape(), setup: '${fonts}1 Bn\n${_definition()}');
    final AiNativeDrawing after = _isolate(before);
    check(AiNativeGradientResources.decode(records: after.records).definitions).length.equals(2);
    check(latin1.decode(after.records.program.bytes)).contains('${fonts}2 Bn');
    for (final String changed in ['[1 Bn\n${_definition()}] pop', '[39/quotesingle TE 1 Bn\n${_definition()}] pop']) {
      final AiNativeDrawing nested = _drawing(_shape(), setup: '[$changed] pop');
      check(() => _isolate(nested)).throws<UnsupportedError>();
    }
  });

  test('rejects missing, stale and ambiguous banks and preserves the source on size failure', () {
    check(() => _isolate(_drawing(_shape(), setup: _definition()))).throws<UnsupportedError>();
    check(() => _isolate(_drawing(_shape(), setup: '2 Bn\n${_definition()}'))).throws<FormatException>();
    check(() => _isolate(_drawing(_shape(), setup: '2 Bn\n${_definition()}\n${_definition()}'))).throws<UnsupportedError>();
    final AiNativeDrawing source = _drawing(_shape());
    final AiNativeDrawing limited = _drawing(_shape(), limit: source.records.program.bytes.length + 12);
    final List<int> original = limited.records.program.bytes.toList();
    check(() => _isolate(limited)).throws<FormatException>();
    check(limited.records.program.bytes).deepEquals(original);
  });

  test('rejects unmatched known styles and unresolved appearance metadata', () {
    final AiNativeDrawing mismatch = _drawing(_shape(styled: true), setup: '1 Bn\n${_definition()}\n${_style().replaceAll('(Ink)', '(Other)')}');
    check(() => _isolate(mismatch)).throws<UnsupportedError>();
    final AiNativeDrawing unknown = _drawing(_shape().replaceFirst('%_/ArtDictionary :', '%_/ArtDictionary : 1 /Real (UnknownEffect) ,'));
    check(() => _isolate(unknown)).throws<UnsupportedError>();
  });
}
