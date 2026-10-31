import 'dart:convert';
import 'dart:io';

import 'package:aikit/aikit.dart';

import '../test/ai_native_subtree_copy_test.dart' show subtreeArtworkIdentifiers, subtreeCopyGroups, subtreeStyleCopySource;
import '../test/ai_native_subtree_removal_test.dart' show subtreeRemovalSource;
import 'check_native_shape_lifecycle.dart' show shapeLifecycleInventory;
import 'native_layer_support.dart' show nativeLayerInventory;
import 'native_object_support.dart' show nativeObjectInventory;
import 'native_subtree_support.dart';

/// Opens bounded immutable native source for source-based copying.
AiNativeDrawing _drawing(String text) => AiNativeDrawing.decode(
  records: AiNativeRecords.decode(program: AiProgram.decode(bytes: latin1.encode(text))),
);

/// Records complete pair and ordinary owner inventories independently of copying.
Map<String, Object?> _inventory(AiNativeDrawing drawing) => {
  'layers': nativeLayerInventory(AiNativeLayers.decode(drawing: drawing)),
  'objects': nativeObjectInventory(drawing),
  'pairs': shapeLifecycleInventory(drawing).where((shape) => shape['printing'] != null).toList(),
};

/// Emits declared real and synthetic whole-parent copy transactions.
Future<void> main() async {
  final Directory output = await Directory('test/corpus/output/subtree-copy').create(recursive: true);
  final List<Map<String, Object?>> rows = [];

  /// Requires fresh identities and retains both programs for independent checking.
  Future<void> record(String name, String operation, AiNativeDrawing source, List<int> selected, {Map<String, Object?>? provenance, bool reject = false, bool translate = false}) async {
    final AiNativeLayers layers = AiNativeLayers.decode(drawing: source);
    final AiNativeObjects objects = AiNativeObjects.decode(drawing: source);
    final List<AiNativeGroup> groups = subtreeCopyGroups(source);
    final List<AiNativeItem> roots = operation == 'group' ? selected.map((index) => groups[index]).toList() : selected.map((index) => layers.layers[index]).toList();
    final List<AiNativeItem> owners = roots.map((root) => root is AiNativeGroup ? objects.forSource(root) : root).toList();
    final Map<AiNativeItem, List<int>> artwork = subtreeArtworkIdentifiers(source, roots);
    final List<AiNativeLayer> descendants = operation == 'layer' ? layers.layers.where((layer) => roots.any((root) => layer.start >= root.start && layer.end <= root.end)).toList() : [];
    final Map<AiNativeLayer, List<int>> identities = {
      for (final AiNativeLayer layer in descendants)
        if (layer.identifier != null) layer: latin1.encode('copy_${latin1.decode(layer.identifier!.bytes)}'),
    };
    final Map<AiNativeLayer, List<int>> names = {
      for (final AiNativeLayer layer in descendants)
        if (layer.nameBytes != null) layer: latin1.encode('Copy of ${latin1.decode(layer.nameBytes!)}'),
    };
    AiNativeDrawing result = source;
    String? issue;
    try {
      result = operation == 'group'
          ? source.duplicateGroups(groups: selected.map((index) => groups[index]).toList(), identifiers: artwork)
          : layers.duplicate(layers: selected.map((index) => layers.layers[index]).toList(), identifiers: identities, names: names, artworkIdentifiers: artwork, discardViewState: true).drawing;
    } on UnsupportedError catch (error) {
      if (!reject) {
        rethrow;
      }
      issue = error.message;
    }
    if (reject != (issue != null)) {
      throw StateError('Unexpected subtree copy qualification for $name/$operation.');
    }
    final String original = '$name.original.ps';
    final String target = '$name.$operation.ps';
    await File('${output.path}/$original').writeAsBytes(source.records.program.bytes);
    await File('${output.path}/$target').writeAsBytes(result.records.program.bytes);
    final List<Map<String, Object?>> replacements = [];
    for (final AiNativeObjectIdentifier identity in objects.structure.identifiers) {
      if (!owners.any((owner) => identity.field.owner.start >= owner.start && identity.field.owner.end <= owner.end)) {
        continue;
      }
      final AiNativeItem token = identity.field.entry.container!.entries.single.items.single;
      replacements.add({'start': token.start, 'end': token.end, 'kind': 'identity', 'value': latin1.encode('copy_${latin1.decode(identity.bytes)}')});
    }
    for (final MapEntry<AiNativeLayer, List<int>> name in names.entries) {
      final AiToken token = name.key.source.naming!.operands.single;
      replacements.add({'start': token.start, 'end': token.end, 'kind': 'name', 'value': name.value});
    }
    String? translated;
    if (translate) {
      translated = '$name.$operation.translated.ps';
      final AiNativeDrawing changed = result.translateLiveShapes(shapes: [result.liveShapes[1]], deltaX: 2, deltaY: 3);
      await File('${output.path}/$translated').writeAsBytes(changed.records.program.bytes);
    }
    rows.add({
      'source': name,
      'operation': operation,
      'selected': selected,
      'spans': [
        for (final AiNativeItem owner in owners) [owner.start, owner.end],
      ],
      'original': original,
      'result': target,
      'translated': translated,
      'rejected': reject,
      'issue': issue,
      'provenance': provenance,
      'replacements': replacements,
      'before': _inventory(source),
      'after': _inventory(result),
    });
    stdout.writeln('$target passed');
  }

  for (final NativeSubtreeFixture fixture in await nativeSubtreeSources(copies: true)) {
    await record(fixture.name, fixture.operation, fixture.drawing, [if (fixture.operation == 'group') 0 else 1], provenance: fixture.provenance, reject: fixture.name == 'group-opacity.ai');
  }
  final AiNativeDrawing synthetic = _drawing(subtreeRemovalSource());
  await record('synthetic', 'group', synthetic, [0], translate: true);
  await record('synthetic-inner', 'group', synthetic, [1]);
  await record('synthetic-all', 'group', synthetic, [2, 0]);
  await record('synthetic', 'layer', synthetic, [0]);
  await record('synthetic-nested', 'layer', synthetic, [1]);
  await record('synthetic-child', 'layer', synthetic, [2]);
  await record('synthetic-all', 'layer', synthetic, [1, 0]);
  await record('synthetic-following', 'group', _drawing(subtreeRemovalSource(following: true)), [0]);
  await record('synthetic-style', 'group', _drawing(subtreeStyleCopySource()), [0]);
  await record('synthetic-hidden-style', 'group', _drawing(subtreeStyleCopySource(hidden: true)), [0], reject: true);
  await record(
    'synthetic-state',
    'group',
    _drawing(subtreeRemovalSource().replaceFirst('0 D 0 XR', '0 XR').replaceFirst('0 A 0 Xw', '0 D\n%_1 D\n0 A 0 Xw').replaceFirst('*u', '1 D\n*u')),
    [0],
  );
  for (final ({String name, String text}) invalid in [
    (name: 'unknown-state', text: subtreeRemovalSource().replaceFirst('0 D ', '').replaceFirst('*u', '1 D\n*u')),
    (name: 'alias', text: subtreeRemovalSource().replaceFirst('(older)', '(author)')),
    (name: 'unknown', text: subtreeRemovalSource().replaceFirst('70 0 m', '17 Future\n70 0 m')),
  ]) {
    await record('synthetic-${invalid.name}', 'group', _drawing(invalid.text), [0], reject: true);
  }
  await File('${output.path}/report.json').writeAsString('${const JsonEncoder.withIndent('  ').convert(rows)}\n');
}
