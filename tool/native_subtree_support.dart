import 'dart:convert';
import 'dart:io';

import 'package:aicodec/aicodec.dart';

import '../test/ai_native_artwork_movement_test.dart' show movementLayer;
import '../test/ai_native_objects_test.dart' show objectDictionary;
import 'check_native_reference_resources.dart' show mixedReferenceSource;

/// A declared parent wrapper around exact pinned native source fragments.
typedef NativeSubtreeFixture = ({String name, String operation, AiNativeDrawing drawing, Map<String, Object?> provenance});

/// Opens bounded native source without producing host representations.
AiNativeDrawing _drawing(List<int> bytes) => AiNativeDrawing.decode(
  records: AiNativeRecords.decode(program: AiProgram.decode(bytes: bytes)),
);

/// Shares pinned fixture construction across parent lifecycle acceptance suites.
Future<List<NativeSubtreeFixture>> nativeSubtreeSources({bool copies = false}) async {
  final List<NativeSubtreeFixture> result = [];
  final AiNativeDrawing base = _drawing(AiNativeData.extract(const AiCodec().decode(await File('test/corpus/files/units-20x40mm_origin_topleft_CC.ai').readAsBytes())).single.bytes);
  for (final String name in ['simple_shapes.ai', 'simple_shapes_cc.ai', 'opacity.ai', 'gradient_linear.ai', 'gradient_radial.ai']) {
    final AiNativeDrawing donor = _drawing(AiNativeData.extract(const AiCodec().decode(await File('test/corpus/files/$name').readAsBytes())).single.bytes);
    final AiNativeObjects objects = AiNativeObjects.decode(drawing: donor);
    final List<AiLiveShape> pairs = donor.liveShapes.where((shape) => shape.appearanceGroup != null && shape.path?.isPrivate == true).toList();
    final int first = copies && pairs.length > 1 ? 1 : 0;
    final int start = objects.forSource(pairs[first].appearanceGroup!).start;
    final int end = pairs[first + 1 < pairs.length ? first + 1 : first].end;
    final String text = latin1.decode(donor.records.program.bytes);
    const String opening = 'u\nu\n';
    const String closing = '\nU\nU\n';
    final String wrapped = '${text.substring(0, start)}$opening${text.substring(start, end)}$closing${text.substring(end)}';
    result.add((
      name: 'group-$name',
      operation: 'group',
      drawing: _drawing(latin1.encode(wrapped)),
      provenance: {'donor': name, if (copies) 'firstPair': first, 'start': start, 'end': end, 'opening': opening, 'closing': closing},
    ));
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
    result.add((
      name: 'layer-$name',
      operation: 'layer',
      drawing: source,
      provenance: {
        ...mixed.provenance,
        'donor': name,
        'start': boundary,
        'end': pair.end,
        'opening': layer.substring(0, layer.indexOf(body)),
        'closing': layer.substring(layer.indexOf(body) + body.length),
      },
    ));
  }
  return result;
}

/// Declares wrappers around unchanged pinned real pairs, without source templates.
({AiNativeDrawing drawing, List<Map<String, Object?>> recipe}) wrapNativeSubtrees(AiNativeDrawing original, {required bool layers}) {
  final AiNativeObjects objects = AiNativeObjects.decode(drawing: original);
  final List<Map<String, Object?>> recipe = [];
  final List<AiSourceEdit> edits = [];
  for (final (int, AiLiveShape) entry in original.liveShapes.indexed) {
    final int start = objects.forSource(entry.$2.appearanceGroup!).start;
    final int end = entry.$2.end;
    final String body = latin1.decode(original.records.program.bytes.sublist(start, end));
    const String opening = '0 Ae\nu\nu\n';
    final String closing = '\nU\n${objectDictionary(identifier: 'inner_${entry.$1}')}\nU\n${objectDictionary(identifier: 'outer_${entry.$1}')}';
    final String group = '$opening$body$closing';
    final String wrapper = layers ? movementLayer('Wrapped_${entry.$1}', group) : group;
    final int offset = wrapper.indexOf(body);
    recipe.add({'start': start, 'end': end, 'opening': wrapper.substring(0, offset), 'closing': wrapper.substring(offset + body.length)});
    edits.add(AiSourceEdit(start: start, end: end, bytes: latin1.encode(wrapper)));
  }
  final AiProgram program = AiNativeEditor.apply(program: original.records.program, edits: edits);
  final AiNativeDrawing wrapped = _drawing(program.bytes);
  if (!AiNativeLayers.decode(drawing: wrapped).rootCountMatches) {
    throw StateError('The declared wrappers changed the original root-layer count.');
  }
  return (drawing: wrapped, recipe: recipe);
}
