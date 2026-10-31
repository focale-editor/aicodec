import 'dart:convert';
import 'dart:io';

import 'package:aikit/aikit.dart';

/// Records ownership and resource links for every baseline and CC units source.
Future<void> main() async {
  final Directory output = await Directory('test/corpus/output/structure').create(recursive: true);
  final List<Map<String, Object?>> rows = [];
  for (final String manifestName in ['manifest.json', 'document_manifest.json']) {
    final Map<String, Object?> manifest = (jsonDecode(await File('test/corpus/$manifestName').readAsString()) as Map).cast<String, Object?>();
    for (final Object? entry in manifest['files']! as List) {
      final String name = (entry! as Map)['file'] as String;
      final List<AiNativeSource> sources = AiNativeData.extract(const AiCodec().decode(await File('test/corpus/files/$name').readAsBytes()));
      for (final (int, AiNativeSource) source in sources.indexed) {
        final AiNativeDrawing drawing = AiNativeDrawing.decode(
          records: AiNativeRecords.decode(program: AiProgram.decode(bytes: source.$2.bytes)),
        );
        final AiNativeStructure structure = AiNativeStructure.decode(drawing: drawing);

        /// Writes source block identity rather than an inferred target version.
        List<Map<String, Object>> memberships(List<AiNativeVersionMembership> values) => [
          for (final AiNativeVersionMembership value in values) {'block': structure.versions.blocks.indexOf(value.block), 'branch': value.branch.name},
        ];

        final String native = '$name.${source.$1}.ps';
        await File('${output.path}/$native').writeAsBytes(source.$2.bytes);
        rows.add({
          'file': name,
          'manifest': manifestName,
          'sourceIndex': source.$1,
          'native': native,
          'versions': [
            for (final AiNativeVersionBlock block in structure.versions.blocks)
              {
                'start': block.start,
                'end': block.end,
                'major': block.major,
                'minor': block.minor,
                'family': block.family,
                'newer': [block.newerRange.start, block.newerRange.end],
                'older': block.olderRange == null ? null : [block.olderRange!.start, block.olderRange!.end],
              },
          ],
          'nodes': [
            for (final AiNativeStructureNode node in structure.nodes)
              {
                'kind': node.kind.name,
                'start': node.start,
                'end': node.end,
                'parent': node.parentIndex,
                'children': node.childIndices,
                'versions': memberships(node.versions),
                if (node.source case final AiNativeContainer record) 'type': record.type,
                if (node.source case final AiNativePath path) ...{
                  'private': path.isPrivate,
                  'geometry': [
                    for (final AiNativeInstruction item in path.geometry) {'operator': item.operator, 'numbers': item.numbers},
                  ],
                  'paint': path.paint.operator,
                },
                if (node.source case final AiNativeGroup group) ...{'openingEnd': group.opening.end, 'closingStart': group.closing.start, 'operator': group.opening.operator},
                if (node.source case final AiLayer layer) ...{'openingEnd': layer.begin.end, 'closingStart': layer.end.start, 'visible': layer.visible, 'locked': layer.locked},
                if (node.source case final AiNativeGradientDefinition definition) ...{'openingEnd': definition.opening.end, 'closingStart': definition.closing.start},
              },
          ],
          'resources': [
            for (final AiNativeStructureResource resource in structure.resources)
              {'kind': resource.kind.name, 'definition': resource.definition.index, 'name': resource.nameBytes.toList(), 'versions': memberships(resource.versions)},
          ],
          'identifiers': [
            for (final AiNativeObjectIdentifier identifier in structure.identifiers)
              {'kind': identifier.kind.name, 'owner': identifier.field.owner.index, 'entry': identifier.field.index, 'key': identifier.field.entry.key, 'bytes': identifier.bytes.toList()},
          ],
          'uses': [
            for (final AiNativeResourceUse use in structure.resourceUses)
              {
                'kind': use.kind.name,
                'start': use.instruction.start,
                'end': use.instruction.end,
                'name': use.nameBytes.toList(),
                'owner': use.owner?.index,
                'versions': memberships(use.versions),
                'resolution': use.resolution.name,
                'candidates': use.candidates.map(structure.resources.indexOf).toList(),
              },
          ],
          'shapes': [
            for (final AiNativeShapeOwnership shape in structure.shapes)
              {
                'dictionary': shape.dictionary.index,
                'path': shape.path?.index,
                'printingGroup': shape.printingGroup?.index,
                'printingPaths': shape.printingPaths.map((node) => node.index).toList(),
                'printingDictionary': shape.printingDictionary?.index,
                'alternatives': shape.alternatives.map((node) => node.index).toList(),
                'issue': shape.shape.bindingIssue,
              },
          ],
        });
        stdout.writeln('$name: ${structure.nodes.length} nodes, ${structure.resources.length} resources, ${structure.resourceUses.length} uses');
      }
    }
  }
  await File('${output.path}/report.json').writeAsString(const JsonEncoder.withIndent('  ').convert(rows));
}
