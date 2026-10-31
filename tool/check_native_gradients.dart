import 'dart:convert';
import 'dart:io';

import 'package:aikit/aikit.dart';

/// Exercises native gradient resources against every pinned external fixture.
Future<void> main() async {
  final Map<String, Object?> manifest = (jsonDecode(await File('test/corpus/manifest.json').readAsString()) as Map).cast<String, Object?>();
  final Directory output = await Directory('test/corpus/output/gradients').create(recursive: true);
  final List<Map<String, Object?>> report = [];
  int failures = 0;
  for (final Object? raw in manifest['files']! as List) {
    final String name = (raw! as Map)['file'] as String;
    try {
      final AiDocument document = const AiCodec().decode(await File('test/corpus/files/$name').readAsBytes());
      final AiProgram program = AiProgram.decode(bytes: AiNativeData.extract(document).single.bytes);
      final AiNativeGradientResources source = AiNativeGradientResources.decode(records: AiNativeRecords.decode(program: program));
      await File('${output.path}/$name.original.ps').writeAsBytes(program.bytes);
      final List<AiNativeGradientStop> stops = [
        for (int index = 0; index < 3; index++)
          AiNativeGradientStop(
            color: AiNativeGradientColor(kind: .rgb, components: _components(index)),
            position: const [0.0, 40.0, 100.0][index],
            opacity: index == 1 ? 0.4 : 1,
          ),
      ];
      final List<AiNativeGradientRamp> ramps = [
        for (int interval = 0; interval < 2; interval++)
          AiNativeGradientRamp(
            kind: .rgb,
            channels: [
              for (int channel = 0; channel < 7; channel++)
                AiNativeGradientChannel.samples(
                  values: [
                    for (int sample = 0; sample < 256; sample++) (_components(interval)[channel] * (255 - sample) + _components(interval + 1)[channel] * sample).round(),
                  ],
                ),
            ],
          ),
      ];
      if (source.definitions.isNotEmpty) {
        final AiNativeGradientResources changed = source.replaceStops(definition: source.definitions.first, stops: stops, ramps: ramps);
        await File('${output.path}/$name.edited.ps').writeAsBytes(changed.records.program.bytes);
      }
      if (name == 'circle.ai') {
        final List<Map<String, Object?>> geometry = [];
        for (final int number in [35, 42, 8, 21]) {
          final String name = 'Unnamed gradient $number';
          final AiNativeGradientDefinition definition = source.definitions.singleWhere((definition) => latin1.decode(definition.nameBytes) == name);
          final AiNativeGradientResources changed = source.replaceStops(
            definition: definition,
            stops: [
              for (int index = 0; index < stops.length; index++) AiNativeGradientStop(color: stops[index].color, position: const [10.0, 40.0, 90.0][index], opacity: stops[index].opacity),
            ],
            ramps: ramps,
          );
          final String file = 'geometry-$number.ps';
          await File('${output.path}/$file').writeAsBytes(changed.records.program.bytes);
          geometry.add({'file': file, 'name': name, 'previous': definition.stops.map((stop) => stop.position / 100).toList()..sort()});
        }
        await File('${output.path}/geometry.json').writeAsString(const JsonEncoder.withIndent('  ').convert(geometry));
      }
      if (name == 'gradient_linear.ai') {
        final List<Map<String, Object?>> colors = [];
        for (final AiNativeGradientColorKind kind in AiNativeGradientColorKind.values) {
          final bool named = kind.index >= AiNativeGradientColorKind.customCmyk.index;
          final int count = switch (kind) {
            .gray => 1,
            .cmyk || .customCmyk || .namedCmyk => 4,
            _ => 7,
          };
          final AiNativeGradientStop stop = AiNativeGradientStop(
            color: AiNativeGradientColor(kind: kind, components: List.filled(count, 0.25), nameBytes: named ? latin1.encode('Focale (Ink)') : null, tint: named ? 0.7 : null),
            position: 10,
            midpoint: 23.5,
            opacity: 0.3,
          );
          final AiNativeGradientResources changed = source.replaceStops(definition: source.definitions.first, stops: [stop, stops.last], ramps: [ramps.last]);
          await File('${output.path}/color-${kind.name}.ps').writeAsBytes(changed.records.program.bytes);
          colors.add({'file': 'color-${kind.name}.ps', 'stop': _stop(stop)});
        }
        await File('${output.path}/colors.json').writeAsString(const JsonEncoder.withIndent('  ').convert(colors));
      }
      report.add({'file': name, 'definitions': source.definitions.map(_definition).toList(), 'status': 'passed'});
      stdout.writeln('$name: ${source.definitions.length} gradient resources');
    } on Object catch (error) {
      failures++;
      report.add({'file': name, 'status': 'failed', 'error': '$error'});
      stderr.writeln('$name: $error');
    }
  }
  await File('${output.path}/report.json').writeAsString(const JsonEncoder.withIndent('  ').convert(report));
  if (failures != 0) {
    exitCode = 1;
  }
}

/// Explicit native CMYK alternatives followed by the red, green or blue primary.
List<double> _components(int primary) => [
  for (int index = 0; index < 3; index++)
    if (index == primary) 0 else 1,
  0,
  for (int index = 0; index < 3; index++)
    if (index == primary) 1 else 0,
];

/// Exports source values for comparison with the independent parser.
Map<String, Object?> _definition(AiNativeGradientDefinition value) => {
  'name': latin1.decode(value.nameBytes),
  'radial': value.radial,
  'stops': [for (final AiNativeGradientStop stop in value.stops) _stop(stop)],
  'fallback': [for (final AiNativeGradientStop stop in value.fallbackStops) _stop(stop)],
  'ramps': [
    for (final AiNativeGradientRamp ramp in value.ramps)
      {
        'kind': ramp.kind.index,
        'channels': [for (final AiNativeGradientChannel channel in ramp.channels) channel.constant ?? channel.samples!.toList()],
      },
  ],
};

/// Exports color values without discarding named-color or opacity distinctions.
Map<String, Object?> _stop(AiNativeGradientStop value) => {
  'style': value.color.style,
  'components': value.color.components,
  'name': value.color.nameBytes == null ? null : latin1.decode(value.color.nameBytes!),
  'tint': value.color.tint,
  'position': value.position,
  'midpoint': value.midpoint,
  'opacity': value.opacity,
  'hasOpacity': value.hasOpacity,
};
