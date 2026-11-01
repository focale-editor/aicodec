import 'dart:convert';
import 'dart:io';

import 'package:aikit/aikit.dart';

import '../test/ai_native_artwork_resources_test.dart' show artworkResourcesModel;

/// Reports exact local source spans without granting body-edit ownership.
Map<String, Object?> artworkResourceInventory(AiNativeArtworkResource resource) {
  int previous = resource.artworkStart;
  return {
    'kind': resource.kind.name,
    'span': [resource.start, resource.end],
    'name': resource.nameBytes,
    'body': [resource.artworkStart, resource.artworkEnd],
    'bounds': resource.bounds == null ? null : [resource.bounds!.left, resource.bounds!.bottom, resource.bounds!.right, resource.bounds!.top],
    'paths': [
      for (final AiNativePath path in resource.paths)
        () {
          final AiNativeInstruction? count = resource.items.whereType<AiNativeInstruction>().where((item) => item.start >= previous && item.end <= path.start && item.operator == 'As').singleOrNull;
          previous = path.end;
          return {
            'geometry': [
              for (final AiNativeInstruction item in path.geometry) [item.start, item.end],
            ],
            'paint': [path.paint.start, path.paint.end],
            'controls': [
              for (final AiNativeInstruction item in resource.items.whereType<AiNativeInstruction>().where(
                (item) => item.start >= path.geometry.last.end && item.end <= path.paint.start && const {'h', 'H', 'W'}.contains(item.operator),
              ))
                [item.start, item.end],
            ],
            'count': count == null ? null : [count.start, count.end],
            'countOperand': count == null ? null : [count.operands.single.start, count.operands.single.end],
          };
        }(),
    ],
    'groups': [
      for (final AiNativeGroup group in resource.groups)
        {
          'span': [group.start, group.end],
          'private': group.opening.isPrivate,
          'paths': group.paths.map(resource.paths.indexOf).toList(),
        },
    ],
    'metadata': [
      for (final AiNativeContainer record in resource.metadata) [record.start, record.end],
    ],
    'uses': [
      for (final AiNativeResourceUse use in resource.uses)
        {
          'span': [use.instruction.start, use.instruction.end],
          'kind': use.kind.name,
          'name': use.nameBytes,
          'resolution': use.resolution.name,
        },
    ],
    'rasters': [
      for (final AiNativeRaster image in resource.rasters)
        {
          'span': [image.start, image.end],
          'data': [image.data.start, image.data.end],
          'width': image.width,
          'height': image.height,
          'components': image.components,
        },
    ],
  };
}

/// Inspects complete pinned producer programs and one explicit resource fixture.
Future<void> main() async {
  final Directory output = await Directory('test/corpus/output/artwork-resources').create(recursive: true);
  final Map<String, AiNativeArtworkResources> sources = {'synthetic': artworkResourcesModel()};
  for (final String name in ['simple_shapes.ai', 'simple_shapes_cc.ai', 'stroke_styles.ai', 'fill_stroke_test_cc.ai', 'styles.ai', 'text_transforms.ai', 'opacity.ai']) {
    final AiNativeSource source = AiNativeData.extract(const AiCodec().decode(await File('test/corpus/files/$name').readAsBytes())).single;
    sources[name] = AiNativeArtworkResources.decode(
      structure: AiNativeStructure.decode(
        drawing: AiNativeDrawing.decode(
          records: AiNativeRecords.decode(program: AiProgram.decode(bytes: source.bytes)),
        ),
      ),
    );
  }
  final List<Map<String, Object?>> rows = [];
  for (final MapEntry<String, AiNativeArtworkResources> entry in sources.entries) {
    final AiNativeArtworkResources model = entry.value;
    await File('${output.path}/${entry.key}.ps').writeAsBytes(model.structure.drawing.records.program.bytes);
    rows.add({'source': entry.key, 'resources': model.resources.map(artworkResourceInventory).toList()});
    stdout.writeln('${entry.key}: ${model.resources.length} declarations, ${model.resources.fold(0, (count, resource) => count + resource.paths.length)} paths');
  }
  await File('${output.path}/report.json').writeAsString('${const JsonEncoder.withIndent('  ').convert(rows)}\n');
}
