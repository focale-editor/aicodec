import 'dart:convert';

import 'package:checks/checks.dart';
import 'package:illustratorkit/illustratorkit.dart';
import 'package:test/test.dart';

/// Creates a source with explicit stop positions and independently placed strips.
AiNativeGradientResources _source({List<int> positions = const [0, 100], String? body, String setup = '', bool radial = false, int? maxBytes}) => AiNativeGradientResources.decode(
  records: AiNativeRecords.decode(
    program: AiProgram.decode(
      bytes: latin1.encode('''%!PS-Adobe-3.0
%%Creator: Adobe Illustrator
%%BeginSetup
%AI5_BeginGradient: (Ink)
(Ink) ${radial ? 1 : 0} ${positions.length} Bd
[
${positions.map((position) => '%_${position / 100} 0 1 6 50 $position Bs').join('\n')}
BD
%AI5_EndGradient
$setup
%%EndSetup
${body ?? _instance()}
%%Trailer
%%EOF
'''),
      limits: AiNativeLimits(maxDecodedBytes: maxBytes ?? 128 * 1024 * 1024),
    ),
  ),
);

/// A full linear gradient with two exterior caps and a deliberately skewed axis.
String _instance({String? matrices}) =>
    '''Bb
1 (Ink) 10 20 0 100 1 0 0 1 0 0 Bg
${matrices ?? '100 50 20 -40 10 20 Xm\n200 100 20 -40 -190 -80 Bc\n100 50 20 -40 10 20 Bm\n100 50 20 -40 110 70 Bc'}
0 BB''';

/// Explicit grayscale colors and sampled intervals supplied by the caller.
AiNativeGradientResources _edit(AiNativeGradientResources source, List<int> positions) => source.replaceStops(
  definition: source.definitions.single,
  stops: [
    for (final int position in positions)
      AiNativeGradientStop(
        color: AiNativeGradientColor(kind: .gray, components: [position / 100]),
        position: position.toDouble(),
      ),
  ],
  ramps: [
    for (int index = 1; index < positions.length; index++)
      AiNativeGradientRamp(
        kind: .gray,
        channels: [
          AiNativeGradientChannel.samples(values: [positions[index - 1], positions[index]]),
        ],
      ),
  ],
);

/// Reads the cached strip geometry, without inferring it from edited stops.
List<List<double>> _matrices(AiNativeGradientResources source, String operator) =>
    AiNativeDrawing.decode(records: source.records).gradients.single.imagingMatrices.where((matrix) => matrix.operator == operator).map((matrix) => matrix.numbers!).toList();

/// Verifies global source edits keep authoring and printing coordinates coherent.
void main() {
  test('splits and merges printing strips while retaining the global transform and caps', () {
    final AiNativeGradientResources original = _source();
    final AiNativeGradientResources changed = _edit(original, [0, 40, 100]);
    check(_matrices(changed, 'Bm')).deepEquals([
      [40, 20, 20, -40, 10, 20],
      [60, 30, 20, -40, 50, 40],
    ]);
    check(_matrices(changed, 'Xm')).deepEquals(_matrices(original, 'Xm'));
    check(_matrices(changed, 'Bc')).deepEquals(_matrices(original, 'Bc'));
    final AiNativeGradientResources merged = _edit(changed, [0, 100]);
    check(_matrices(merged, 'Bm')).deepEquals(_matrices(original, 'Bm'));
    check(_matrices(original, 'Bm')).length.equals(1);
  });

  test('moves both interior cap boundaries and preserves their exterior edges', () {
    final AiNativeGradientResources original = _source(
      positions: [20, 80],
      body: _instance(matrices: '100 50 20 -40 10 20 Xm\n200 100 20 -40 -170 -70 Bc\n60 30 20 -40 30 30 Bm\n100 50 20 -40 90 60 Bc'),
    );
    final AiNativeGradientResources changed = _edit(original, [10, 40, 90]);
    final List<List<double>> strips = _matrices(changed, 'Bm');
    check(strips[0][0]).isCloseTo(30, 1e-10);
    check(strips[0].sublist(2)).deepEquals([20, -40, 20, 25]);
    check(strips[1]).deepEquals([50, 25, 20, -40, 50, 40]);
    check(_matrices(changed, 'Bc')).deepEquals([
      [190, 95, 20, -40, -170, -70],
      [90, 45, 20, -40, 100, 65],
    ]);
  });

  test('recovers the whole axis from legacy partial intervals without adding Xm', () {
    final AiNativeGradientResources original = _source(
      positions: [20, 50, 80],
      body: _instance(matrices: '200 100 20 -40 -170 -70 Bc\n30 15 20 -40 30 30 Bm\n30 15 20 -40 60 45 Bm\n100 50 20 -40 90 60 Bc'),
    );
    final AiNativeGradientResources changed = _edit(original, [0, 100]);
    check(_matrices(changed, 'Xm')).isEmpty();
    check(_matrices(changed, 'Bm')).deepEquals([
      [100, 50, 20, -40, 10, 20],
    ]);
    check(_matrices(changed, 'Bc')).deepEquals([
      [180, 90, 20, -40, -170, -70],
      [80, 40, 20, -40, 110, 70],
    ]);
  });

  test('updates ordinary and private drawing, styles and nested art together', () {
    final String instance = _instance();
    final String private = instance.split('\n').map((line) => '%_$line').join('\n');
    final AiNativeGradientResources original = _source(
      setup: '/FillStyle : $instance /Def ;\n%_/StrokeStyle :\n$private\n%_/Def ;\n/Art : $instance /Dictionary : 7 /Integer (Retain) , ; ;',
      body: '$instance\n$private',
    );
    final AiNativeGradientResources changed = _edit(original, [0, 40, 100]);
    final AiNativeDrawing drawing = AiNativeDrawing.decode(records: changed.records);
    check(drawing.gradients).length.equals(2);
    check(drawing.gradients.map((instance) => instance.opening.isPrivate).toList()).deepEquals([false, true]);
    for (final AiNativeGradient instance in drawing.gradients) {
      check(instance.imagingMatrices.where((matrix) => matrix.operator == 'Bm')).length.equals(2);
    }
    for (final AiNativeContainer container in changed.records.containers.where((record) => record.type.endsWith('Style'))) {
      final AiNativePaintStyle style = AiNativePaintStyle.decode(records: changed.records, record: container);
      final List<AiNativeInstruction> matrices = style.gradients.single.imagingMatrices.where((matrix) => matrix.operator == 'Bm').toList();
      check(matrices).length.equals(2);
      if (container.type == 'StrokeStyle') {
        for (final AiNativeInstruction matrix in matrices) {
          check(latin1.decode(changed.records.program.bytes.sublist(matrix.start - 2, matrix.start))).equals('%_');
        }
      }
    }
    final AiNativeArt art = AiNativeArt.decode(records: changed.records, record: changed.records.containers.singleWhere((record) => record.type == 'Art'));
    check(art.items.whereType<AiNativeInstruction>().where((instruction) => instruction.operator == 'Bm')).length.equals(2);
    check(changed.records.containers.singleWhere((record) => record.type == 'Dictionary')['Retain']!.number).equals(7);
  });

  test('leaves radial matrices and matrix-free style notes unchanged', () {
    for (final AiNativeGradientResources original in [
      _source(radial: true, body: _instance(matrices: '100 0 0 -100 10 20 Bm')),
      _source(body: _instance(matrices: '')),
    ]) {
      final AiNativeGradientResources changed = _edit(original, [10, 40, 90]);
      check(changed.records.program.bytes.sublist(changed.records.program.bodyStart)).deepEquals(original.records.program.bytes.sublist(original.records.program.bodyStart));
    }
  });

  test('rewrites complete instances inside setup patterns and palette resources', () {
    final AiNativeGradientResources original = _source(setup: '%AI5_BeginPattern: (Tile)\n${_instance()}\n%AI5_EndPattern\n/Palette : ${_instance()} ;', body: '');
    final AiNativeGradientResources changed = _edit(original, [0, 40, 100]);
    final String source = latin1.decode(changed.records.program.bytes);
    final List<List<double>> strips = source.split('\n').where((line) => line.endsWith(' Bm')).map((line) => line.split(' ').take(6).map(double.parse).toList()).toList();
    check(strips).deepEquals([
      [40, 20, 20, -40, 10, 20],
      [60, 30, 20, -40, 50, 40],
      [40, 20, 20, -40, 10, 20],
      [60, 30, 20, -40, 50, 40],
    ]);
    check(source).contains('%AI5_BeginPattern: (Tile)');
    check(source).contains('%AI5_EndPattern\n/Palette :');
  });

  test('requires complete global references but skips procedures and embedded documents', () {
    final AiNativeGradientResources unknown = _source(setup: '/FuturePaint : 1 (Ink) 10 20 0 100 1 0 0 1 0 0 Bg ;');
    check(() => _edit(unknown, [0, 40, 100])).throws<FormatException>();
    final AiNativeGradientResources embedded = _source(setup: '/Sample { ${_instance()} } def\n%%BeginDocument: embedded\n${_instance()}\n%%EndDocument');
    final AiNativeGradientResources changed = _edit(embedded, [0, 40, 100]);
    check(_matrices(changed, 'Bm')).length.equals(2);
    check(latin1.decode(changed.records.program.bytes)).contains('/Sample { ${_instance()} } def');
    check(latin1.decode(changed.records.program.bytes)).contains('%%BeginDocument: embedded\n${_instance()}\n%%EndDocument');
  });

  test('rejects mismatched intervals, inconsistent placements and missing exterior caps', () {
    for (final String matrices in [
      '100 50 20 -40 10 20 Xm\n90 50 20 -40 10 20 Bm',
      '100 50 20 -40 10 20 Bm\n100 50 20 -40 10 20 Bm',
      '100 50 20 -40 10 20 Bm\n100 50 20 -40 10 20 Bc\n100 50 20 -40 10 20 Bc',
    ]) {
      final AiNativeGradientResources original = _source(body: _instance(matrices: matrices));
      check(() => _edit(original, [0, 40, 100])).throws<UnsupportedError>();
    }
    final AiNativeGradientResources noCaps = _source(body: _instance(matrices: '100 50 20 -40 10 20 Bm'));
    check(() => _edit(noCaps, [10, 90])).throws<UnsupportedError>();
    check(_matrices(_edit(noCaps, [0, 40, 100]), 'Bm')).length.equals(2);
    final AiNativeGradientResources degenerate = _source(body: _instance(matrices: '0 0 0 0 10 20 Bm'));
    check(() => _edit(degenerate, [0, 40, 100])).throws<FormatException>();
    final AiNativeGradientResources narrowCaps = _source(
      positions: [20, 80],
      body: _instance(matrices: '1 0.5 20 -40 29 29.5 Bc\n60 30 20 -40 30 30 Bm\n1 0.5 20 -40 90 60 Bc'),
    );
    check(() => _edit(narrowCaps, [0, 100])).throws<UnsupportedError>();
  });

  test('rejects incomplete instances, invalid selectors and unrepresentable interval widths', () {
    for (final String body in [_instance().replaceFirst('Bb', '10 1 Bb'), _instance().replaceFirst('0 BB', '')]) {
      final AiNativeGradientResources original = _source(body: body);
      check(() => _edit(original, [0, 40, 100])).throws<FormatException>();
    }
    final AiNativeGradientResources executable = _source(body: _instance().replaceFirst('0 BB', '{ 1 2 add } exec 0 BB'));
    check(() => _edit(executable, [0, 40, 100])).throws<UnsupportedError>();
    final AiNativeGradientResources original = _source();
    final List<AiNativeGradientRamp> ramps = _edit(original, [0, 40, 100]).definitions.single.ramps;
    check(
      () => original.replaceStops(
        definition: original.definitions.single,
        stops: [
          for (final double position in [0.0, double.minPositive, 100.0])
            AiNativeGradientStop(
              color: AiNativeGradientColor(kind: .gray, components: [0]),
              position: position,
            ),
        ],
        ramps: ramps,
      ),
    ).throws<FormatException>();
  });

  test('does not reinterpret geometry when only colors and ramps change', () {
    final AiNativeGradientResources original = _source(
      setup: '/FuturePaint : ${_instance()} ;',
      body: _instance(matrices: '100 50 20 -40 10 20 Xm\n90 50 20 -40 10 20 Bm'),
    );
    final AiNativeGradientResources changed = _edit(original, [0, 100]);
    check(changed.records.program.bytes.sublist(changed.records.program.bodyStart)).deepEquals(original.records.program.bytes.sublist(original.records.program.bodyStart));
  });

  test('bounds repeated instance expansion before publishing any source edit', () {
    final String body = List.filled(30, _instance()).join('\n');
    final AiNativeGradientResources original = _source(body: body);
    final AiNativeGradientResources bounded = _source(body: body, maxBytes: original.records.program.bytes.length + 800);
    check(() => _edit(bounded, [0, 20, 40, 60, 80, 100])).throws<FormatException>();
    check(bounded.records.program.bytes).deepEquals(original.records.program.bytes);
  });
}
