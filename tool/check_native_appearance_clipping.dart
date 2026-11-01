import 'dart:convert';
import 'dart:io';

import 'package:aikit/aikit.dart';

import '../test/ai_native_appearance_clipping_test.dart' show clippingAppearanceEdit, clippingAppearancePrinting, clippingAppearanceSource, clippingChildEdit, clippingChildSource;
import '../test/ai_native_appearance_editing_test.dart' show appearanceEditingModel;
import 'check_native_appearance_groups.dart' show appearanceGroupInventory;
import 'check_native_appearances.dart' show appearanceInventory;
import 'check_native_path_topology.dart' show pathTopologyInventory;

/// Emits complete clipped transactions and source-backed contour ownership.
Future<void> main() async {
  final Directory output = await Directory('test/corpus/output/appearance-clipping').create(recursive: true);
  final List<Map<String, Object?>> rows = [];
  for (final String variant in [
    for (final String kind in ['closed', 'open', 'compound', 'leaves', 'nested', 'counted']) ...['$kind-selected', '$kind-shared'],
    'child',
  ]) {
    final bool child = variant == 'child';
    final String kind = variant.split('-').first;
    final AiNativeAppearances before = appearanceEditingModel(
      source: child ? clippingChildSource() : clippingAppearanceSource(variant: kind, countedPrinting: kind == 'counted'),
    );
    final AiNativeAppearances after = child
        ? clippingChildEdit(before)
        : clippingAppearanceEdit(
            before,
            shared: variant.endsWith('shared'),
            printing: clippingAppearancePrinting(counted: kind == 'counted'),
          );
    for (final (String, AiNativeAppearances) item in [('before', before), ('after', after)]) {
      final String name = '$variant.${item.$1}';
      final AiNativeDrawing drawing = item.$2.structure.drawing;
      await File('${output.path}/$name.ps').writeAsBytes(drawing.records.program.bytes);
      rows.add({
        'source': name,
        ...appearanceInventory(item.$2),
        ...appearanceGroupInventory(item.$2),
        'paths': pathTopologyInventory(drawing),
        'groups': [
          for (final AiNativeGroup group in drawing.groups)
            {
              'span': [group.start, group.end],
              'private': group.opening.isPrivate,
              'paths': group.paths.map(drawing.paths.indexOf).toList(),
            },
        ],
        'contours': [
          for (final AiNativeResourceUse use in item.$2.uses.where((use) => !use.instruction.isPrivate))
            for (final AiNativePathTopology path in item.$2.artworkFor(use: use).groupContours)
              {
                'path': drawing.paths.indexOf(path.path),
                'groups': path.groups.map(drawing.groups.indexOf).toList(),
                'mask': path.mask.name,
                'clip': path.clippingGroup == null ? null : drawing.groups.indexOf(path.clippingGroup!),
                'compound': path.compound == null ? null : drawing.groups.indexOf(path.compound!),
                'count': path.pointCount == null ? null : [path.pointCount!.start, path.pointCount!.end],
              },
        ],
      });
    }
    stdout.writeln('$variant: complete clipped owners and scoped contour state');
  }
  await File('${output.path}/report.json').writeAsString('${const JsonEncoder.withIndent('  ').convert(rows)}\n');
}
