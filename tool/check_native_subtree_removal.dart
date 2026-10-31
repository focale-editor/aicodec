import 'dart:convert';
import 'dart:io';

import 'package:aikit/aikit.dart';

import '../test/ai_native_artwork_movement_test.dart' show movementLayer;
import '../test/ai_native_subtree_removal_test.dart' show subtreeRemovalSource;
import 'check_native_reference_resources.dart' show mixedReferenceSource;
import 'check_native_shape_lifecycle.dart' show shapeLifecycleInventory;
import 'native_layer_support.dart' show nativeLayerInventory;
import 'native_object_support.dart' show nativeObjectInventory;

/// Opens immutable native source without composing derived document appearances.
AiNativeDrawing _drawing(List<int> bytes) => AiNativeDrawing.decode(
  records: AiNativeRecords.decode(program: AiProgram.decode(bytes: bytes)),
);

/// Retains native trees and pair associations for independent source checks.
Map<String, Object?> _inventory(AiNativeDrawing drawing) => {
  'layers': nativeLayerInventory(AiNativeLayers.decode(drawing: drawing)),
  'objects': nativeObjectInventory(drawing),
  'pairs': shapeLifecycleInventory(drawing).where((shape) => shape['printing'] != null).toList(),
};

/// Returns ordinary enclosing groups in stable source order.
List<AiNativeGroup> _groups(AiNativeDrawing drawing) =>
    drawing.groups.where((group) => group.opening.operator == 'u' && group.paths.any((path) => path.isPrivate)).toList()..sort((first, second) => first.start.compareTo(second.start));

/// Records exact wrapped real-source recipes and full-subtree removal results.
Future<void> main() async {
  final Directory output = await Directory('test/corpus/output/subtree-removal').create(recursive: true);
  final List<Map<String, Object?>> rows = [];

  /// Stores immutable before/after programs, selections and expected refusals.
  Future<void> record(String name, String operation, AiNativeDrawing source, List<int> selected, {Map<String, Object?>? provenance, bool reject = false}) async {
    final AiNativeLayers layers = AiNativeLayers.decode(drawing: source);
    final AiNativeObjects objects = AiNativeObjects.decode(drawing: source);
    final List<AiNativeGroup> groups = _groups(source);
    final List<AiNativeItem> owners = operation == 'group' ? selected.map((index) => objects.forSource(groups[index])).toList() : selected.map((index) => layers.layers[index]).toList();
    AiNativeDrawing result = source;
    String? issue;
    try {
      result = operation == 'group'
          ? source.removeGroups(groups: selected.map((index) => groups[index]).toList())
          : layers.remove(layers: selected.map((index) => layers.layers[index]).toList(), discardViewState: true).drawing;
    } on UnsupportedError catch (error) {
      if (!reject) {
        rethrow;
      }
      issue = error.message;
    }
    if (reject != (issue != null)) {
      throw StateError('Unexpected subtree removal qualification for $name/$operation.');
    }
    final String original = '$name.original.ps';
    final String target = '$name.$operation.ps';
    await File('${output.path}/$original').writeAsBytes(source.records.program.bytes);
    await File('${output.path}/$target').writeAsBytes(result.records.program.bytes);
    rows.add({
      'source': name,
      'operation': operation,
      'selected': selected,
      'spans': [
        for (final AiNativeItem owner in owners) [owner.start, owner.end],
      ],
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
  for (final String name in ['simple_shapes.ai', 'simple_shapes_cc.ai', 'opacity.ai', 'gradient_linear.ai', 'gradient_radial.ai']) {
    final AiNativeDrawing donor = _drawing(AiNativeData.extract(const AiCodec().decode(await File('test/corpus/files/$name').readAsBytes())).single.bytes);
    final AiNativeObjects objects = AiNativeObjects.decode(drawing: donor);
    final List<AiLiveShape> pairs = donor.liveShapes.where((shape) => shape.appearanceGroup != null && shape.path?.isPrivate == true).toList();
    final int start = objects.forSource(pairs.first.appearanceGroup!).start;
    final int end = pairs[pairs.length > 1 ? 1 : 0].end;
    final String text = latin1.decode(donor.records.program.bytes);
    const String opening = 'u\nu\n';
    const String closing = '\nU\nU\n';
    final String wrapped = '${text.substring(0, start)}$opening${text.substring(start, end)}$closing${text.substring(end)}';
    await record('group-$name', 'group', _drawing(latin1.encode(wrapped)), [0], provenance: {'donor': name, 'start': start, 'end': end, 'opening': opening, 'closing': closing});
    if (name == 'opacity.ai') {
      continue;
    }
    final ({AiNativeDrawing drawing, Map<String, Object?> provenance}) mixed = mixedReferenceSource(base, donor);
    final AiLiveShape pair = mixed.drawing.liveShapes.single;
    final int boundary = AiNativeObjects.decode(drawing: mixed.drawing).forSource(pair.appearanceGroup!).start;
    final String combined = latin1.decode(mixed.drawing.records.program.bytes);
    final String body = combined.substring(boundary, pair.end);
    final String layer = movementLayer('Derived', 'u\n$body\nU');
    final AiNativeDrawing source = _drawing(latin1.encode(combined.replaceRange(boundary, pair.end, layer).replaceFirst('%AI5_NumLayers: 1', '%AI5_NumLayers: 2')));
    await record(
      'layer-$name',
      'layer',
      source,
      [1],
      provenance: {
        ...mixed.provenance,
        'donor': name,
        'start': boundary,
        'end': pair.end,
        'opening': layer.substring(0, layer.indexOf(body)),
        'closing': layer.substring(layer.indexOf(body) + body.length),
      },
    );
  }
  final AiNativeDrawing synthetic = _drawing(latin1.encode(subtreeRemovalSource()));
  await record('synthetic', 'group', synthetic, [0]);
  await record('synthetic-inner', 'group', synthetic, [1]);
  await record('synthetic-all', 'group', synthetic, [2, 0]);
  await record('synthetic', 'layer', synthetic, [0]);
  await record('synthetic-nested', 'layer', synthetic, [1]);
  await record('synthetic-child', 'layer', synthetic, [2]);
  await record('synthetic-all', 'layer', synthetic, [1, 0]);
  await record('synthetic-reset', 'layer', _drawing(latin1.encode(subtreeRemovalSource(following: true, reset: true))), [1]);
  for (final String operation in ['group', 'layer']) {
    await record('synthetic-following', operation, _drawing(latin1.encode(subtreeRemovalSource(following: true))), [if (operation == 'group') 2 else 1], reject: true);
  }
  for (final ({String name, String text}) invalid in [
    (name: 'reference', text: subtreeRemovalSource().replaceFirst('%%EndSetup', '/Dictionary : /XMLUID : (older) ; (Reference) , ;\n%%EndSetup')),
    (name: 'alias', text: subtreeRemovalSource().replaceFirst('(older)', '(author)')),
    (name: 'unknown', text: subtreeRemovalSource().replaceFirst('70 0 m', '17 Future\n70 0 m')),
  ]) {
    await record('synthetic-${invalid.name}', 'layer', _drawing(latin1.encode(invalid.text)), [0], reject: true);
  }
  await File('${output.path}/report.json').writeAsString('${const JsonEncoder.withIndent('  ').convert(rows)}\n');
}
