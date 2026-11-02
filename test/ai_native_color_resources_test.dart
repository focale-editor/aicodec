import 'dart:convert';

import 'package:aikit/aikit.dart';
import 'package:checks/checks.dart';
import 'package:test/test.dart';

import 'ai_native_objects_test.dart' show objectSource;

/// Complete literal setup with explicit inherited artwork attributes.
AiNativeGradientResources colorResources({String setup = '', String body = '0 0 m 20 20 L S', int? limit}) => AiNativeGradientResources.decode(
  records: AiNativeRecords.decode(
    program: AiProgram.decode(
      bytes: latin1.encode(objectSource(body, setup: setup)),
      limits: AiNativeLimits(maxDecodedBytes: limit ?? 128 * 1024 * 1024),
    ),
  ),
);

/// Host-composed opaque gray stop; duplicate positions retain distinct colors.
AiNativeGradientStop colorStop(double position, double value) => AiNativeGradientStop(
  color: AiNativeGradientColor(kind: .gray, components: [value]),
  position: position,
);

/// Explicit constant interval including the unused zero-width hard transition.
AiNativeGradientRamp colorRamp(double value) => AiNativeGradientRamp(
  kind: .gray,
  channels: [AiNativeGradientChannel.constant(value: value)],
);

/// Source-backed bank creation, deletion and hard-stop persistence.
void main() {
  test('creates first resource and removes its complete counted definition', () {
    final AiNativeGradientResources source = colorResources();
    final AiNativeGradientResources created = source.create(nameBytes: [65, 40, 255], radial: false, stops: [colorStop(0, 0), colorStop(100, 1)], ramps: [colorRamp(1)]);
    check(created.definitions.single.nameBytes).deepEquals([65, 40, 255]);
    check(latin1.decode(created.records.program.bytes)).contains('1 Bn');
    final AiNativeGradientResources removed = created.remove(definition: created.definitions.single);
    check(removed.definitions).isEmpty();
    check(latin1.decode(removed.records.program.bytes)).contains('0 Bn');
    check(removed.records.program.bytes.sublist(removed.records.program.bodyStart)).deepEquals(source.records.program.bytes.sublist(source.records.program.bodyStart));
  });

  test('adds to every existing counted bank and updates all same-name copies', () {
    final AiNativeGradientResources source = colorResources(setup: '0 Bn\n0 Bn');
    final AiNativeGradientResources created = source.create(
      nameBytes: [65],
      radial: true,
      stops: [colorStop(0, 0), colorStop(50, 0.2), colorStop(50, 0.8), colorStop(100, 1)],
      ramps: [colorRamp(0), colorRamp(0), colorRamp(1)],
    );
    check(created.definitions).length.equals(2);
    for (final AiNativeGradientDefinition definition in created.definitions) {
      check(definition.stops.map((stop) => stop.color.components.single)).deepEquals([0.0, 0.2, 0.8, 1.0]);
    }
    check(created.remove(definition: created.definitions.last).definitions).isEmpty();
  });

  test('retains ordered hard edges in linear resources and their compatibility copies', () {
    final AiNativeGradientResources source = colorResources().create(nameBytes: [65], radial: false, stops: [colorStop(0, 0), colorStop(100, 1)], ramps: [colorRamp(1)]);
    final AiNativeGradientResources changed = source.replaceStops(
      definition: source.definitions.single,
      stops: [colorStop(0, 0), colorStop(50, 0.2), colorStop(50, 0.8), colorStop(100, 1)],
      ramps: [colorRamp(0), colorRamp(0), colorRamp(1)],
    );
    check(changed.definitions.single.stops.map((stop) => stop.position)).deepEquals([100.0, 50.0, 50.0, 0.0]);
    check(changed.definitions.single.stops.map((stop) => stop.color.components.single)).deepEquals([1.0, 0.8, 0.2, 0.0]);
    check(changed.definitions.single.fallbackStops.map((stop) => stop.color.components.single)).deepEquals([1.0, 0.8, 0.2, 0.0]);
  });

  test('rejects live references, duplicate names, stale handles and opaque reference owners', () {
    final AiNativeGradientResources source = colorResources().create(nameBytes: [65], radial: false, stops: [colorStop(0, 0), colorStop(100, 1)], ramps: [colorRamp(1)]);
    check(() => source.create(nameBytes: [65], radial: false, stops: [colorStop(0, 0), colorStop(100, 1)], ramps: [colorRamp(1)])).throws<ArgumentError>();
    check(
      () => source.remove(
        definition: colorResources().create(nameBytes: [65], radial: true, stops: [colorStop(0, 0), colorStop(100, 1)], ramps: [colorRamp(1)]).definitions.single,
      ),
    ).throws<ArgumentError>();
    final String text = latin1.decode(source.records.program.bytes).replaceFirst('0 0 m 20 20 L S', '0 0 m 20 20 L\nBb 1 (A) 0 0 0 20 1 0 0 1 0 0 Bg\n20 0 0 20 0 0 Bm\nf 0 BB');
    final AiNativeGradientResources used = AiNativeGradientResources.decode(
      records: AiNativeRecords.decode(program: AiProgram.decode(bytes: latin1.encode(text))),
    );
    check(() => used.remove(definition: used.definitions.single)).throws<UnsupportedError>();
    check(
      () => used.replaceStops(definition: used.definitions.single, stops: [colorStop(0, 0), colorStop(50, 0), colorStop(50, 1), colorStop(100, 1)], ramps: [colorRamp(0), colorRamp(0), colorRamp(1)]),
    ).throws<UnsupportedError>();
    check(() => colorResources(setup: '/Future : (A) /String (Ref) , ;').create(nameBytes: [65], radial: false, stops: [colorStop(0, 0), colorStop(100, 1)], ramps: [colorRamp(1)]))
        .throws<UnsupportedError>();
    final AiNativeGradientResources bounded = colorResources(limit: colorResources().records.program.bytes.length + 20);
    check(() => bounded.create(nameBytes: [65], radial: false, stops: [colorStop(0, 0), colorStop(100, 1)], ramps: [colorRamp(1)])).throws<FormatException>();
  });
}
