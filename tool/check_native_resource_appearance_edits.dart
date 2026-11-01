import 'dart:convert';
import 'dart:io';

import 'package:aikit/aikit.dart';

import '../test/ai_native_appearance_editing_test.dart' show appearanceAssignment, appearanceEditingModel;
import '../test/ai_native_resource_appearance_editing_test.dart' show resourceAppearanceEdit, resourceAppearanceEditingSource;
import 'check_native_appearances.dart' show appearanceInventory;

/// Reports complete source owners independently of whether their style changes.
Map<String, Object?> _owner(AiNativeAppearances model, AiNativeResourceUse use) {
  final AiNativeAppearanceArtwork artwork = model.artworkFor(use: use);
  return {
    'use': model.uses.indexOf(use),
    'span': [artwork.start, artwork.end],
    'printing': [artwork.printingGroup.start, artwork.printingGroup.end],
    'authoring': [artwork.authoring.start, artwork.authoring.end],
    'resource': artwork.resource == null ? null : model.artworkResources.resources.indexOf(artwork.resource!),
    'resourceSpan': artwork.resource == null ? null : [artwork.resource!.start, artwork.resource!.end],
    'resourceName': artwork.resource?.nameBytes,
  };
}

/// Recolors one symbol expansion and preserves its original outgoing paint.
AiNativeAppearanceReplacement _symbolPrinting(AiNativeAppearances model, AiNativeResourceUse use) {
  final AiNativeAppearanceArtwork artwork = model.artworkFor(use: use);
  final AiProgram program = model.structure.drawing.records.program;
  final AiNativeInstruction color = artwork.resource!.items.whereType<AiNativeInstruction>().singleWhere(
    (item) => item.start > artwork.printingGroup.start && item.end < artwork.printingGroup.end && item.operator == 'Xa',
  );
  return AiNativeAppearanceReplacement(
    artwork: artwork,
    bytes: AiNativeEditor.copyRange(
      program: program,
      start: artwork.printingGroup.start,
      end: artwork.printingGroup.end,
      edits: [
        AiSourceEdit(start: color.start, end: color.end, bytes: latin1.encode('0 1 0 0 1 0 1 Xa')),
        AiSourceEdit(start: artwork.printingGroup.end - 1, end: artwork.printingGroup.end - 1, bytes: [...program.bytes.sublist(color.start, color.end), 10]),
      ],
    ),
    bounds: AiBoundingBox(left: -40, bottom: -40, right: 40, top: 40),
  );
}

/// Exercises used pattern chains and complete producer symbol transactions.
Future<void> main() async {
  final Directory output = await Directory('test/corpus/output/resource-appearance-edits').create(recursive: true);
  final List<Map<String, Object?>> rows = [];

  /// Stores full programs and exact inventory handles for a separate reader.
  Future<void> save(String name, AiNativeAppearances before, AiNativeAppearances after, AiNativeAppearance style, AiNativePaintAssignment paint, List<AiNativeResourceUse> owners, bool shared) async {
    final String prefix = '$name.${shared ? 'shared' : 'selected'}';
    final AiNativeEntry naming = (style.resource.definition.source as AiNativeContainer)['Name']!;
    for (final (String, AiNativeAppearances) value in [('before', before), ('after', after)]) {
      await File('${output.path}/$prefix.${value.$1}.ps').writeAsBytes(value.$2.structure.drawing.records.program.bytes);
    }
    rows.add({
      'file': name,
      'shared': shared,
      'style': before.styles.indexOf(style),
      'name': [naming.items.single.start, naming.items.single.end],
      'paint': [paint.instruction.start, paint.instruction.end],
      'before': {'source': '$prefix.before', ...appearanceInventory(before)},
      'after': {'source': '$prefix.after', ...appearanceInventory(after)},
      'ownersBefore': owners.map((use) => _owner(before, use)).toList(),
      'ownersAfter': owners.map((use) => _owner(after, after.uses[before.uses.indexOf(use)])).toList(),
    });
    stdout.writeln('$prefix: ${owners.length} synchronized source owners');
  }

  for (final bool chain in [false, true]) {
    final AiNativeAppearances before = appearanceEditingModel(source: resourceAppearanceEditingSource(chain: chain));
    for (final bool shared in [false, true]) {
      await save(
        chain ? 'chain' : 'pattern',
        before,
        resourceAppearanceEdit(before, shared: shared),
        before.styles.first,
        appearanceAssignment(before.styles.first, 2, .fillColor),
        before.uses,
        shared,
      );
    }
  }
  for (final String name in ['simple_shapes.ai', 'simple_shapes_cc.ai', 'stroke_styles.ai', 'fill_stroke_test_cc.ai', 'opacity.ai']) {
    final AiNativeSource source = AiNativeData.extract(const AiCodec().decode(await File('test/corpus/files/$name').readAsBytes())).single;
    final AiNativeAppearances before = AiNativeAppearances.decode(
      structure: AiNativeStructure.decode(
        drawing: AiNativeDrawing.decode(
          records: AiNativeRecords.decode(program: AiProgram.decode(bytes: source.bytes)),
        ),
      ),
    );
    final AiNativeResourceUse use = before.artworkResources.resources.singleWhere((resource) => latin1.decode(resource.nameBytes) == 'Add Favorite').uses.first;
    final AiNativeAppearance style = before.resolve(use: use)!;
    if (style.uses.length != 1) {
      throw StateError('The pinned symbol style must have one complete source user.');
    }
    final AiNativePaintAssignment paint = style.parts.expand((part) => part.paints).expand((paint) => paint.style.assignments).firstWhere((paint) => paint.parameter == .fillColor);
    for (final bool shared in [false, true]) {
      final List<AiNativePaintChange> paints = [
        AiNativePaintChange(assignment: paint, values: [0, 1, 0, 0, 1, 0, 1]),
      ];
      final List<AiNativeAppearanceReplacement> artwork = [_symbolPrinting(before, use)];
      final AiNativeAppearances after = shared
          ? before.updateShared(appearance: style, paints: paints, artwork: artwork)
          : before.updateSelected(appearance: style, paints: paints, artwork: artwork, nameBytes: latin1.encode('Edited resource'));
      await save(name, before, after, style, paint, [use], shared);
    }
  }
  await File('${output.path}/report.json').writeAsString('${const JsonEncoder.withIndent('  ').convert(rows)}\n');
}
