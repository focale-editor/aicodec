import 'dart:convert';

import 'package:aikit/aikit.dart';

/// Maps only this pinned fixture's canonical process inks into explicit CMYK.
AiNativeMeshProcessColor resolveMeshProcessColor(AiNativeMeshNode corner) {
  if (corner.colorSpace!.deviceName == 'DeviceCMYK') {
    return AiNativeMeshProcessColor(space: .cmyk, components: corner.color);
  }
  if (corner.colorSpace!.deviceName == 'DeviceGray') {
    return AiNativeMeshProcessColor(space: .cmyk, components: [0, 0, 0, 1 - corner.color.single]);
  }
  const Map<String, List<double>> alternatives = {
    'Cyan': [1, 0, 0, 0],
    'Magenta': [0, 1, 0, 0],
    'Yellow': [0, 0, 1, 0],
    'Black': [0, 0, 0, 1],
  };
  final List<double> components = [0, 0, 0, 0];
  if (corner.inkTints.isEmpty) {
    throw StateError('Missing qualified process inks.');
  }
  for (final ({AiNativeMeshInk ink, double tint}) tint in corner.inkTints) {
    final List<double>? expected = alternatives[latin1.decode(tint.ink.nameBytes)];
    if (expected == null || tint.ink.deviceName != 'DeviceCMYK' || tint.ink.components.indexed.any((component) => component.$2 != expected[component.$1])) {
      throw StateError('Unexpected process ink declaration.');
    }
    for (int component = 0; component < 4; component++) {
      components[component] += expected[component] * tint.tint;
    }
  }
  return AiNativeMeshProcessColor(space: .cmyk, components: components);
}
