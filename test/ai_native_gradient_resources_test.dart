import 'dart:convert';

import 'package:aikit/aikit.dart';
import 'package:checks/checks.dart';
import 'package:test/test.dart';

/// Builds a native setup with retained drawing and unknown unrelated records.
AiNativeGradientResources _resources(String definitions, {int? maxBytes}) {
  final List<int> bytes = latin1.encode('''%!PS-Adobe-3.0
%%Creator: Adobe Illustrator
%%BeginSetup
/Dictionary : 7 /Integer (Retain) , ;
$definitions
%%EndSetup
0 0 m 10 0 L 10 10 L f
%%Trailer
%%EOF
''');
  return AiNativeGradientResources.decode(
    records: AiNativeRecords.decode(
      program: AiProgram.decode(
        bytes: bytes,
        limits: AiNativeLimits(maxDecodedBytes: maxBytes ?? 128 * 1024 * 1024),
      ),
    ),
  );
}

/// Two-stop CC resource with independent fallback precision and sampled channels.
String _definition({String name = 'Ink', int kind = 0, bool paired = true}) =>
    '''%AI5_BeginGradient: ($name)
($name) $kind 2 Bd
[
<000080ff> 0 %_Br
[
${paired ? '0.91 0 50 100 %_BS\n%_0.9 0 1 6 50 100 Bs\n0.11 0 50 0 %_BS\n%_0.1 0 1 6 50 0 Bs' : '0.9 0 50 100 %_Bs\n0.1 0 50 0 %_Bs'}
BD
%AI5_EndGradient''';

/// Explicit host-composed grayscale interval, independent of a color engine.
AiNativeGradientRamp _ramp() => AiNativeGradientRamp(
  kind: .gray,
  channels: [
    AiNativeGradientChannel.samples(values: [0, 64, 128, 255]),
  ],
);

/// Creates a simple stop while retaining the chosen generation's opacity syntax.
AiNativeGradientStop _gray(double position, {bool hasOpacity = true}) => AiNativeGradientStop(
  color: AiNativeGradientColor(kind: .gray, components: [position / 100]),
  position: position,
  hasOpacity: hasOpacity,
);

/// Checks gradient syntax, immutable ownership and atomic cache replacement.
void main() {
  test('writes radial stops from the center outward and linear stops in reverse order', () {
    for (final int kind in [0, 1]) {
      final AiNativeGradientResources source = _resources(_definition(kind: kind));
      final AiNativeGradientResources changed = source.replaceStops(definition: source.definitions.single, stops: [_gray(0), _gray(100)], ramps: [_ramp()]);
      check(changed.definitions.single.stops.map((stop) => stop.position).toList()).deepEquals(kind == 1 ? [0, 100] : [100, 0]);
      check(changed.definitions.single.fallbackStops.map((stop) => stop.position).toList()).deepEquals(kind == 1 ? [0, 100] : [100, 0]);
    }
  });

  test('reads paired stops, precision alternatives and sampled ramps', () {
    final AiNativeGradientResources source = _resources(_definition());
    final AiNativeGradientDefinition gradient = source.definitions.single;
    check(latin1.decode(gradient.nameBytes)).equals('Ink');
    check(gradient.radial).isFalse();
    check(gradient.hasPairedStops).isTrue();
    check(gradient.stops.map((stop) => stop.color.components.single).toList()).deepEquals([0.9, 0.1]);
    check(gradient.fallbackStops.map((stop) => stop.color.components.single).toList()).deepEquals([0.91, 0.11]);
    check(gradient.ramps.single.channels.single.samples!).deepEquals([0, 0, 128, 255]);
    check(gradient.stops.clear).throws<UnsupportedError>();
    check(() => gradient.nameBytes[0] = 0).throws<UnsupportedError>();
    check(() => gradient.ramps.single.channels.single.samples![0] = 3).throws<UnsupportedError>();
  });

  test('replaces shared-name resources, fallback stops and every printing interval together', () {
    final AiNativeGradientResources source = _resources('${_definition()}\n${_definition()}\n${_definition(name: 'Other', kind: 1)}');
    final AiNativeGradientResources changed = source.replaceStops(definition: source.definitions.first, stops: [_gray(0), _gray(35), _gray(100)], ramps: [_ramp(), _ramp()]);
    check(changed.definitions).length.equals(3);
    for (final AiNativeGradientDefinition gradient in changed.definitions.take(2)) {
      check(gradient.stops.map((stop) => stop.position).toList()).deepEquals([100.0, 35.0, 0.0]);
      check(gradient.fallbackStops.map((stop) => stop.position).toList()).deepEquals([100.0, 35.0, 0.0]);
      check(gradient.ramps).length.equals(2);
    }
    check(changed.definitions.last.stops).length.equals(2);
    check(changed.definitions.last.radial).isTrue();
    check(latin1.decode(changed.records.program.bytes)).contains(_definition(name: 'Other', kind: 1));
    check(changed.records.program.bytes.sublist(changed.records.program.bodyStart)).deepEquals(source.records.program.bytes.sublist(source.records.program.bodyStart));
    check(changed.records.roots.single['Retain']!.number).equals(7);
    check(source.definitions.first.stops).length.equals(2);
  });

  test('reads and writes all process, custom and named color layouts with opacity', () {
    final AiNativeGradientResources source = _resources(_definition());
    for (final AiNativeGradientColorKind kind in AiNativeGradientColorKind.values) {
      final bool named = kind.index >= AiNativeGradientColorKind.customCmyk.index;
      final int count = switch (kind) {
        .gray => 1,
        .cmyk || .customCmyk || .namedCmyk => 4,
        _ => 7,
      };
      final AiNativeGradientColor color = AiNativeGradientColor(kind: kind, components: List.filled(count, 0.25), nameBytes: named ? [65, 0, 255, 40] : null, tint: named ? 0.7 : null);
      final AiNativeGradientStop first = AiNativeGradientStop(color: color, position: 10, midpoint: 23.5, opacity: 0.3);
      final AiNativeGradientResources changed = source.replaceStops(definition: source.definitions.single, stops: [first, _gray(90)], ramps: [_ramp()]);
      final AiNativeGradientStop stop = changed.definitions.single.stops.last;
      check(stop.color.kind).equals(kind);
      check(stop.color.components).deepEquals(color.components);
      if (named) {
        check(stop.color.nameBytes!).deepEquals(color.nameBytes!);
      } else {
        check(stop.color.nameBytes).isNull();
      }
      check(stop.color.tint).equals(color.tint);
      check(stop.position).equals(10);
      check(stop.midpoint).equals(23.5);
      check(stop.opacity).equals(0.3);
    }
  });

  test('retains old stop syntax without introducing new opacity fields', () {
    final AiNativeGradientResources source = _resources(_definition(paired: false));
    final AiNativeGradientResources changed = source.replaceStops(definition: source.definitions.single, stops: [_gray(0, hasOpacity: false), _gray(100, hasOpacity: false)], ramps: [_ramp()]);
    check(changed.definitions.single.usesPrivateStops).isFalse();
    check(changed.definitions.single.stops.first.hasOpacity).isFalse();
    check(() => source.replaceStops(definition: source.definitions.single, stops: [_gray(0), _gray(100)], ramps: [_ramp()])).throws<UnsupportedError>();
  });

  test('retains normalized constants and legacy byte constants without inferring a scale', () {
    final AiNativeGradientResources source = _resources(_definition());
    for (final AiNativeGradientRampKind kind in AiNativeGradientRampKind.values) {
      final int count = const [1, 4, 5, 6, 7, 8, 9][kind.index];
      final AiNativeGradientRamp ramp = AiNativeGradientRamp(
        kind: kind,
        channels: [
          for (int index = 0; index < count; index++) AiNativeGradientChannel.constant(value: index.isEven ? 0.25 : 255),
        ],
      );
      final AiNativeGradientResources changed = source.replaceStops(definition: source.definitions.single, stops: [_gray(0), _gray(100)], ramps: [ramp]);
      check(changed.definitions.single.ramps.single.kind).equals(kind);
      check(changed.definitions.single.ramps.single.channels.map((channel) => channel.constant).toList()).deepEquals(ramp.channels.map((channel) => channel.constant).toList());
    }
  });

  test('rejects foreign handles, inconsistent selections, ambiguity and stale ramps', () {
    final AiNativeGradientResources source = _resources(_definition());
    final AiNativeGradientResources foreign = _resources(_definition());
    check(() => source.replaceStops(definition: foreign.definitions.single, stops: [_gray(0), _gray(100)], ramps: [_ramp()])).throws<ArgumentError>();
    for (final List<AiNativeGradientStop> stops in [
      <AiNativeGradientStop>[],
      [_gray(0)],
      [_gray(100), _gray(0)],
      [_gray(0), _gray(0)],
    ]) {
      check(() => source.replaceStops(definition: source.definitions.single, stops: stops, ramps: [_ramp()])).throws<ArgumentError>();
    }
    check(() => source.replaceStops(definition: source.definitions.single, stops: [_gray(0), _gray(100)], ramps: [])).throws<ArgumentError>();
    final AiNativeGradientResources ambiguous = _resources('${_definition()}\n${_definition(kind: 1)}');
    check(() => ambiguous.replaceStops(definition: ambiguous.definitions.first, stops: [_gray(0), _gray(100)], ramps: [_ramp()])).throws<FormatException>();
  });

  test('bounds output expansion before allocating oversized sampled syntax', () {
    final String definition = _definition();
    final AiNativeGradientResources source = _resources(definition);
    final AiNativeGradientResources bounded = _resources(definition, maxBytes: source.records.program.bytes.length + 20);
    final AiNativeGradientRamp large = AiNativeGradientRamp(
      kind: .gray,
      channels: [AiNativeGradientChannel.samples(values: List.filled(500, 128))],
    );
    check(() => bounded.replaceStops(definition: bounded.definitions.single, stops: [_gray(0), _gray(100)], ramps: [large])).throws<FormatException>();
    check(bounded.records.program.bytes).deepEquals(source.records.program.bytes);
  });

  test('skips gradient-shaped comments inside embedded documents and procedures', () {
    final String nested = '%%BeginDocument: embedded\n${_definition(name: 'Embedded')}\n%%EndDocument';
    final String procedure = '/Example {\n${_definition(name: 'Procedure')}\n} def';
    final AiNativeGradientResources source = _resources('$nested\n$procedure\n${_definition()}');
    check(source.definitions.map((definition) => latin1.decode(definition.nameBytes)).toList()).deepEquals(['Ink']);
  });

  test('rejects malformed headers, stop records, channel tables and future operators', () {
    for (final String malformed in [
      _definition().replaceFirst('(Ink) 0 2 Bd', '(Other) 0 2 Bd'),
      _definition().replaceFirst('0 2 Bd', '3 2 Bd'),
      _definition().replaceFirst('0 2 Bd', '0 3 Bd'),
      _definition().replaceFirst('0 %_Br', '1 %_Br'),
      _definition().replaceFirst('0 %_Br', '7 %_Br'),
      _definition().replaceFirst('6 50 100 Bs', '7 50 100 Bs'),
      _definition().replaceFirst('6 50 100 Bs', '6 0 100 Bs'),
      _definition().replaceFirst('0.9 0 1 6', '0.9 6 1 6'),
      _definition().replaceFirst('BD\n', '42 FutureGradient\nBD\n'),
      _definition().replaceFirst('BD\n', '%AI99_FutureColorSpace: 3\nBD\n'),
      _definition().replaceFirst('%AI5_EndGradient', ''),
      _definition().replaceFirst('BD\n', ''),
      _definition().replaceFirst('BD\n', '4 BD\n'),
    ]) {
      check(() => _resources(malformed)).throws<FormatException>();
    }
  });

  test('validates caller colors, ranges, channel sizes and owned byte storage', () {
    check(() => AiNativeGradientColor(kind: .rgb, components: [1, 0, 0])).throws<ArgumentError>();
    check(() => AiNativeGradientColor(kind: .gray, components: [double.nan])).throws<ArgumentError>();
    check(() => AiNativeGradientColor(kind: .customCmyk, components: [0, 0, 0, 1])).throws<ArgumentError>();
    check(() => AiNativeGradientColor(kind: .gray, components: [0], nameBytes: [65])).throws<ArgumentError>();
    check(() => _gray(double.infinity)).throws<ArgumentError>();
    check(() => AiNativeGradientChannel.constant(value: -1)).throws<ArgumentError>();
    check(() => AiNativeGradientChannel.samples(values: [256])).throws<ArgumentError>();
    check(() => AiNativeGradientRamp(kind: .cmyk, channels: [_ramp().channels.single])).throws<ArgumentError>();
    check(
      () => AiNativeGradientRamp(
        kind: .cmyk,
        channels: [
          _ramp().channels.single,
          _ramp().channels.single,
          _ramp().channels.single,
          AiNativeGradientChannel.samples(values: [0, 1]),
        ],
      ),
    ).throws<ArgumentError>();
    final List<int> values = [1, 2];
    final AiNativeGradientChannel channel = AiNativeGradientChannel.samples(values: values);
    values[0] = 99;
    check(channel.samples!).deepEquals([1, 2]);
  });
}
