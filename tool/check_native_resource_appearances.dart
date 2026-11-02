import 'dart:convert';
import 'dart:io';

import 'package:aicodec/aicodec.dart';

import '../test/ai_native_appearance_clipping_test.dart' show clippingAppearanceSource;
import '../test/ai_native_appearance_editing_test.dart' show appearanceEditingModel, appearanceEditingSource;
import '../test/ai_native_appearance_nested_styles_test.dart' show nestedAppearanceSource;
import '../test/ai_native_resource_appearances_test.dart' show resourceAppearanceSource;
import 'check_native_artwork_resources.dart' show artworkResourceInventory;

/// Reports complete qualified pairs without interpreting their native styles.
Map<String, Object?> resourceAppearanceInventory(AiNativeAppearances model, AiNativeArtworkResource resource) {
  final List<Map<String, Object?>> pairs = [];
  final List<int> rejected = [];
  for (final AiNativeResourceUse use in resource.uses.where((use) => use.kind == .knownStyle)) {
    final AiNativeAppearanceArtwork artwork;
    try {
      artwork = model.artworkFor(use: use);
    } on UnsupportedError {
      rejected.add(resource.uses.indexOf(use));
      continue;
    }
    if (!identical(artwork.resource, resource)) {
      throw StateError('A resource appearance lost its enclosing source owner.');
    }
    pairs.add({
      'span': [artwork.start, artwork.end],
      'use': resource.uses.indexOf(use),
      'printing': [artwork.printingGroup.start, artwork.printingGroup.end],
      'authoring': [artwork.authoring.start, artwork.authoring.end],
      'kind': artwork.liveShape != null
          ? 'liveShape'
          : artwork.path != null
          ? 'path'
          : 'group',
      'nestedUses': artwork.nestedUses.map(resource.uses.indexOf).toList(),
      'nestedOwners': [
        for (final AiNativeResourceUse nested in artwork.nestedUses) [artwork.authoringFor(use: nested).start, artwork.authoringFor(use: nested).end],
      ],
      'metadata': [
        for (final AiNativeContainer record in artwork.metadata) [record.start, record.end],
      ],
    });
  }
  return {...artworkResourceInventory(resource), 'appearances': pairs, 'rejectedUses': rejected};
}

/// Keeps every pinned producer intact while locating resource-local expansions.
Future<void> main() async {
  final Directory output = await Directory('test/corpus/output/resource-appearances').create(recursive: true);
  final Map<String, AiNativeAppearances> sources = {
    'paths': appearanceEditingModel(source: resourceAppearanceSource()),
    'groups': appearanceEditingModel(source: resourceAppearanceSource(original: nestedAppearanceSource())),
    'clips': appearanceEditingModel(
      source: resourceAppearanceSource(original: clippingAppearanceSource(variant: 'compound')),
    ),
    'live': appearanceEditingModel(source: resourceAppearanceSource(original: appearanceEditingSource())),
    'patterns': appearanceEditingModel(source: resourceAppearanceSource(kind: .pattern)),
    'brushes': appearanceEditingModel(source: resourceAppearanceSource(kind: .brush)),
  };
  for (final String name in ['simple_shapes.ai', 'simple_shapes_cc.ai', 'stroke_styles.ai', 'fill_stroke_test_cc.ai', 'styles.ai', 'text_transforms.ai', 'opacity.ai']) {
    final AiNativeSource source = AiNativeData.extract(const AiCodec().decode(await File('test/corpus/files/$name').readAsBytes())).single;
    sources[name] = AiNativeAppearances.decode(
      structure: AiNativeStructure.decode(
        drawing: AiNativeDrawing.decode(
          records: AiNativeRecords.decode(program: AiProgram.decode(bytes: source.bytes)),
        ),
      ),
    );
  }
  final List<Map<String, Object?>> rows = [];
  for (final MapEntry<String, AiNativeAppearances> entry in sources.entries) {
    final AiNativeAppearances model = entry.value;
    await File('${output.path}/${entry.key}.ps').writeAsBytes(model.structure.drawing.records.program.bytes);
    final List<Map<String, Object?>> resources = model.artworkResources.resources.map((resource) => resourceAppearanceInventory(model, resource)).toList();
    rows.add({'source': entry.key, 'resources': resources});
    stdout.writeln('${entry.key}: ${resources.fold(0, (count, resource) => count + (resource['appearances']! as List).length)} qualified resource pairs');
  }
  await File('${output.path}/report.json').writeAsString('${const JsonEncoder.withIndent('  ').convert(rows)}\n');
}
