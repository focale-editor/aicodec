import 'dart:convert';

import 'package:aicodec/aicodec.dart';
import 'package:checks/checks.dart';
import 'package:test/test.dart';

/// A deliberately skewed radial placement with an off-origin center.
const String _matrix = '100 20 30 -80 400 500 Bm';

/// One editable gradient instance with separately stored authoring geometry.
String _instance({String highlight = '25 5 0 0.25 Bh', String matrix = _matrix, String geometry = '1 (Ink) 0 0 0 1 1 0 0 1 0 0 1 Bg'}) => 'Bb\n$highlight\n$geometry\n$matrix\n0 BB';

/// Creates a bounded source with a radial global resource and arbitrary owners.
AiNativeGradientResources _source({String? body, String setup = '', bool radial = true, int? limit}) => AiNativeGradientResources.decode(
  records: AiNativeRecords.decode(
    program: AiProgram.decode(
      bytes: latin1.encode('''%!PS-Adobe-3.0
%%BeginSetup
%AI5_BeginGradient: (Ink)
(Ink) ${radial ? 1 : 0} 2 Bd
[
%_0 0 50 0 Bs
%_1 0 50 100 Bs
BD
%AI5_EndGradient
$setup
%%EndSetup
${body ?? _instance()}
%%Trailer
%%EOF
'''),
      limits: AiNativeLimits(maxDecodedBytes: limit ?? 128 * 1024 * 1024),
    ),
  ),
);

/// Sets an explicit global focus on the source's owned radial definition.
AiNativeGradientResources _edit(AiNativeGradientResources source, {double angle = 90, double length = 0.5}) =>
    source.setRadialFocus(definition: source.definitions.first, angle: angle, length: length);

/// Reads the body highlight independently of its expected printing coordinates.
List<double> _focus(AiNativeGradientResources source) => AiNativeDrawing.decode(records: source.records).gradients.first.highlight!.numbers!;

/// Checks atomic polar/cartesian editing and conservative rejection policies.
void main() {
  test('maps focus through skewed printing axes without adding the center', () {
    final AiNativeGradientResources source = _source();
    final AiNativeGradientResources changed = _edit(source);
    final List<double> focus = _focus(changed);
    check(focus[0]).isCloseTo(-15, 1e-12);
    check(focus[1]).isCloseTo(40, 1e-12);
    check(focus.skip(2).toList()).deepEquals([90, 0.5]);
    check(_focus(source)).deepEquals([25, 5, 0, 0.25]);
    check(changed.definitions.first.stops.map((stop) => stop.position).toList()).deepEquals([0, 100]);
    check(latin1.decode(changed.records.program.bytes)).contains(_matrix);
    check(identical(_edit(changed), changed)).isTrue();
  });

  test('updates styles, setup patterns and private art with the same resource', () {
    final String note = _instance(highlight: '0 0 0 0.25 Bh', matrix: '', geometry: '2 (Ink) 0 0 0 1 1 0 0 1 0 0 0.5 Bg');
    final AiNativeGradientResources source = _source(
      setup: '/FillStyle : $note /Def ;\n%AI5_BeginPattern: (Tile)\n${_instance()}\n%AI5_EndPattern',
      body: '${_instance()}\n${_instance().split('\n').map((line) => '%_$line').join('\n')}\n/Art : ${_instance()} ;',
    );
    final AiNativeGradientResources changed = _edit(source, angle: 0, length: 0.5);
    final String text = latin1.decode(changed.records.program.bytes);
    final RegExp edited = RegExp(r'50(?:\.0)? 10(?:\.0)? 0 0.5 Bh');
    check(edited.allMatches(text)).length.equals(4);
    check(RegExp('%_${edited.pattern}').hasMatch(text)).isTrue();
    final AiNativePaintStyle style = AiNativePaintStyle.decode(records: changed.records, record: changed.records.containers.firstWhere((record) => record.type == 'FillStyle'));
    check(style.gradients.single.highlight!.numbers!).deepEquals([0, 0, 0, 0.5]);
  });

  test('inserts absent highlights in ordinary and private CC style syntax', () {
    final String ordinary = _instance(highlight: '');
    final String note = _instance(highlight: '', matrix: '', geometry: '2 (Ink) 0 0 0 1 1 0 0 1 0 0 1 Bg');
    final AiNativeGradientResources source = _source(body: '$ordinary\n${note.split('\n').map((line) => '%_$line').join('\n')}');
    final AiNativeGradientResources changed = _edit(source, angle: 0, length: 0.5);
    final List<AiNativeGradient> gradients = AiNativeDrawing.decode(records: changed.records).gradients;
    check(gradients.first.highlight!.numbers!).deepEquals([50, 10, 0, 0.5]);
    check(gradients.last.highlight!.numbers!).deepEquals([0, 0, 0, 0.5]);
    check(gradients.last.highlight!.isPrivate).isTrue();
    check(gradients.last.geometry.instruction.isPrivate).isTrue();
    check(RegExp(r'%_0(?:\.0)? 0(?:\.0)? 0(?:\.0)? 0.5 Bh\n%_2 \(Ink\)').hasMatch(latin1.decode(changed.records.program.bytes))).isTrue();
  });

  test('retains exact no-op bytes and supports centered and boundary foci', () {
    final AiNativeGradientResources source = _source(body: _instance(highlight: '25.0000000001 5 00 .25 Bh'));
    check(identical(_edit(source, angle: 0, length: 0.25), source)).isTrue();
    check(_focus(_edit(source, angle: 360, length: 1))).deepEquals([100, 20, 360, 1]);
    check(_focus(_edit(source, angle: -360, length: 0))).deepEquals([0, 0, -360, 0]);
    final AiNativeGradientResources absent = _source(body: _instance(highlight: ''));
    check(identical(_edit(absent, angle: 0, length: 0), absent)).isTrue();
  });

  test('supports legacy printing matrices without rewriting legacy geometry', () {
    const String geometry = '(Ink) 400 500 30 100 1 0 0 1 7 8 Bg';
    final AiNativeGradientResources source = _source(body: _instance(geometry: geometry));
    final AiNativeGradientResources changed = _edit(source, angle: 0, length: 0.75);
    check(_focus(changed)).deepEquals([75, 15, 0, 0.75]);
    check(latin1.decode(changed.records.program.bytes)).contains(geometry);
    final AiNativeGradientResources note = _source(
      body: _instance(highlight: '0 0 0 0 Bh', matrix: '', geometry: '2 (Ink) 0 0 0 1 1 0 0 1 0 0 Bg'),
    );
    check(_focus(_edit(note))).deepEquals([0, 0, 90, 0.5]);
  });

  test('preserves unrelated resources and skips procedures and embedded artwork', () {
    final String untouched = _instance(geometry: '1 (Other) 0 0 0 1 1 0 0 1 0 0 1 Bg');
    final String embedded = '%%BeginDocument: old.ai\n${_instance()}\n%%EndDocument';
    final String procedure = '/Deferred { ${_instance()} } def';
    final AiNativeGradientResources source = _source(body: '${_instance()}\n$untouched', setup: '$embedded\n$procedure');
    final String text = latin1.decode(_edit(source).records.program.bytes);
    [untouched, embedded, procedure].forEach(check(text).contains);
  });

  test('rejects foreign definitions, linear gradients and invalid inputs', () {
    final AiNativeGradientResources source = _source();
    check(() => source.setRadialFocus(definition: _source().definitions.first, angle: 0, length: 0)).throws<ArgumentError>();
    check(() => _edit(_source(radial: false))).throws<ArgumentError>();
    for (final double angle in [double.nan, double.infinity, -361, 361]) {
      check(() => _edit(source, angle: angle)).throws<ArgumentError>();
    }
    for (final double length in [double.nan, double.infinity, -0.1, 1.1]) {
      check(() => _edit(source, length: length)).throws<ArgumentError>();
    }
  });

  test('rejects ambiguous resources and inconsistent or unknown printing layouts', () {
    final AiNativeGradientResources duplicate = _source(setup: '%AI5_BeginGradient: (Ink)\n(Ink) 0 2 Bd [ 0 0 50 100 %_Bs\n1 0 50 0 %_Bs\nBD\n%AI5_EndGradient');
    check(() => _edit(duplicate)).throws<FormatException>();
    for (final String block in [
      _instance(highlight: '250 50 0 0.25 Bh'),
      _instance(matrix: ''),
      _instance(matrix: '$_matrix\n$_matrix'),
      _instance(matrix: _matrix.replaceFirst('Bm', 'Xm')),
      _instance(matrix: '', geometry: '2 (Ink) 1 2 0 100 1 0 0 1 0 0 Bg'),
      _instance(matrix: '', geometry: '2 (Ink) 0 0 0 1 1 0 0 1 0 0 1 Bg'),
    ]) {
      check(() => _edit(_source(body: block))).throws<UnsupportedError>();
    }
    for (final String block in [
      _instance(matrix: '0 0 0 0 0 0 Bm'),
      _instance(matrix: '1e20 0 0 1 0 0 Bm'),
      _instance(highlight: '25 5 0 2 Bh'),
    ]) {
      check(() => _edit(_source(body: block))).throws<FormatException>();
    }
  });

  test('rejects partial global edits and bounded output expansion atomically', () {
    final AiNativeGradientResources malformed = _source(body: '${_instance()}\n${_instance(matrix: '')}');
    final List<int> original = malformed.records.program.bytes.toList();
    check(() => _edit(malformed)).throws<UnsupportedError>();
    check(malformed.records.program.bytes).deepEquals(original);
    final String body = _instance(highlight: '');
    final AiNativeGradientResources limited = _source(
      body: body,
      limit: _source(body: body).records.program.bytes.length,
    );
    check(() => _edit(limited)).throws<FormatException>();
    check(() => _edit(_source(body: '1 (Ink) 0 0 0 1 1 0 0 1 0 0 1 Bg'))).throws<FormatException>();
  });
}
