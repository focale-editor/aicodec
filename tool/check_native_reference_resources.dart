import 'dart:convert';
import 'dart:io';

import 'package:aikit/aikit.dart';

import '../test/ai_native_artwork_movement_test.dart' show movementState;
import '../test/ai_native_reference_resources_test.dart' show referenceResourcesSource;
import 'check_native_shape_lifecycle.dart' show shapeLifecycleInventory;
import 'native_layer_support.dart' show nativeLayerInventory;
import 'native_object_support.dart' show nativeObjectInventory;

/// Opens bounded immutable source handles without producing host appearances.
AiNativeDrawing _drawing(List<int> bytes) => AiNativeDrawing.decode(
  records: AiNativeRecords.decode(program: AiProgram.decode(bytes: bytes)),
);

/// Retains the exact complete source bank wrapper around a parsed definition.
({int start, int end}) _gradientRange(String text, AiNativeGradientDefinition definition) => (
  start: text.lastIndexOf('%AI5_BeginGradient:', definition.start),
  end: text.indexOf('%AI5_EndGradient', definition.end) + '%AI5_EndGradient'.length,
);

/// Builds a declared mixed fixture from exact real document, pair and resource spans.
({AiNativeDrawing drawing, Map<String, Object?> provenance}) _combined(AiNativeDrawing base, AiNativeDrawing donor) {
  final String text = latin1.decode(donor.records.program.bytes);
  final AiLiveShape pair = donor.liveShapes[1];
  final AiNativeStructure structure = AiNativeStructure.decode(drawing: donor);
  final List<AiNativeGradientDefinition> gradients = {
    for (final AiNativeResourceUse use in structure.resourceUses.where(
      (use) =>
          use.kind == .gradient && (use.instruction.start >= pair.start && use.instruction.end <= pair.end || use.instruction.start >= pair.style!.start && use.instruction.end <= pair.style!.end),
    ))
      use.candidates.single.definition.source as AiNativeGradientDefinition,
    structure.resources.firstWhere((resource) => resource.kind == .gradient).definition.source as AiNativeGradientDefinition,
  }.toList()..sort((first, second) => first.start.compareTo(second.start));
  final List<({int start, int end})> ranges = gradients.map((definition) => _gradientRange(text, definition)).toList();
  final int start = AiNativeObjects.decode(drawing: donor).forSource(pair.appearanceGroup!).expansion?.start ?? pair.start;
  final String setup = '${ranges.length} Bn\n${ranges.map((range) => text.substring(range.start, range.end)).join('\n')}\n${text.substring(pair.style!.start, pair.style!.end)}\n';
  const String bridge = '$movementState 0 1 0 0 0 Xy\n';
  final String original = latin1.decode(base.records.program.bytes);
  final int setupPosition = original.indexOf('%%EndSetup');
  final int bodyPosition = base.records.program.bodyEnd;
  final String combined =
      '${original.substring(0, setupPosition)}$setup${original.substring(setupPosition, bodyPosition)}\n$bridge${text.substring(start, pair.end)}\n${original.substring(bodyPosition)}';
  return (
    drawing: _drawing(latin1.encode(combined)),
    provenance: {
      'base': 'units-20x40mm_origin_topleft_CC.ai',
      'baseSetupPosition': setupPosition,
      'baseBodyPosition': bodyPosition,
      'donorPair': [start, pair.end],
      'donorStyle': [pair.style!.start, pair.style!.end],
      'donorGradients': [
        for (final ({int start, int end}) range in ranges) [range.start, range.end],
      ],
      'bridge': bridge,
    },
  );
}

/// Records setup, ordinary ownership and pair metadata for independent readers.
Map<String, Object?> _inventory(AiNativeDrawing drawing) => {
  'layers': nativeLayerInventory(AiNativeLayers.decode(drawing: drawing)),
  'objects': nativeObjectInventory(drawing),
  'pairs': shapeLifecycleInventory(drawing),
};

/// Checks mixed-family deletion and preservation of counted shared resources.
Future<void> main() async {
  final Directory output = await Directory('test/corpus/output/reference-resources').create(recursive: true);
  final List<Map<String, Object?>> rows = [];

  /// Keeps successful and refused requests separate from their recorded inputs.
  Future<void> record(String name, String operation, AiNativeDrawing source, {bool reject = false, Map<String, Object?>? provenance}) async {
    AiNativeDrawing result = source;
    String? issue;
    final AiNativeLayers layers = AiNativeLayers.decode(drawing: source);
    try {
      result = switch (operation) {
        'path' => source.removePaths(paths: [source.paths.first]),
        'group' => source.removeGroups(groups: [source.groups.first]),
        'pair' => source.removeLiveShapes(shapes: [source.liveShapes.first]),
        'layer' => layers.remove(layers: [layers.layers.first], discardViewState: true).drawing,
        _ => throw ArgumentError('Unknown deletion operation $operation.'),
      };
    } on UnsupportedError catch (error) {
      if (!reject) {
        rethrow;
      }
      issue = error.message;
    }
    if (reject != (issue != null)) {
      throw StateError('Unexpected reference qualification for $name/$operation.');
    }
    final String original = '$name.original.ps';
    final String target = '$name.$operation.ps';
    await File('${output.path}/$original').writeAsBytes(source.records.program.bytes);
    await File('${output.path}/$target').writeAsBytes(result.records.program.bytes);
    rows.add({
      'source': name,
      'operation': operation,
      'original': original,
      'result': target,
      'rejected': reject,
      'issue': issue,
      'provenance': provenance,
      'before': _inventory(source),
      'after': _inventory(result),
    });
    stdout.writeln('$target passed');
  }

  final AiNativeDrawing base = _drawing(AiNativeData.extract(const AiCodec().decode(await File('test/corpus/files/units-20x40mm_origin_topleft_CC.ai').readAsBytes())).single.bytes);
  for (final String name in ['simple_shapes.ai', 'simple_shapes_cc.ai', 'gradient_linear.ai', 'gradient_radial.ai']) {
    final AiNativeDrawing donor = _drawing(AiNativeData.extract(const AiCodec().decode(await File('test/corpus/files/$name').readAsBytes())).single.bytes);
    final ({AiNativeDrawing drawing, Map<String, Object?> provenance}) combined = _combined(base, donor);
    await record('mixed-$name', 'layer', combined.drawing, provenance: {...combined.provenance, 'donor': name});
    await record(name, 'layer', donor, reject: true);
  }
  final AiNativeDrawing source = _drawing(latin1.encode(referenceResourcesSource()));
  for (final String operation in ['path', 'group', 'layer', 'pair']) {
    await record('synthetic', operation, source);
  }
  await record('synthetic-replay', 'path', source.removeLiveShapes(shapes: [source.liveShapes.first]));
  await record('synthetic-unused', 'path', source.removeLiveShapes(shapes: source.liveShapes));
  final String text = referenceResourcesSource();
  for (final ({String name, String text}) invalid in [
    (
      name: 'style-reference',
      text: text.replaceFirst('%%EndSetup', '/KnownStyle : (Unused) /Name , /ActiveStyle : /Dictionary : /XMLUID : (path_target) ; (Reference) , ; /Execution ; /Def ;\n%%EndSetup'),
    ),
    (name: 'bank-comment', text: text.replaceFirst('1 Bn', '1\n%AI99_Ref: path_target\nBn')),
    (name: 'identity-alias', text: text.replaceFirst('(older)', '(path_target)')),
    (name: 'private', text: text.replaceFirst('%%Trailer', '%_17 FutureState\n%%Trailer')),
  ]) {
    await record('synthetic-${invalid.name}', 'path', _drawing(latin1.encode(invalid.text)), reject: true);
  }
  await File('${output.path}/report.json').writeAsString('${const JsonEncoder.withIndent('  ').convert(rows)}\n');
}
