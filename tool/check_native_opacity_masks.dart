import 'dart:convert';
import 'dart:io';

import 'package:aikit/aikit.dart';

import '../test/ai_native_appearance_editing_test.dart' show appearanceEditingModel;
import '../test/ai_native_artboard_masks_test.dart' show artboardOpacityMask;
import '../test/ai_native_opacity_masks_test.dart' show editOpacityMask, opacityMaskSource;
import '../test/ai_native_opacity_save_test.dart' show activeOpacitySave, opacitySave;
import '../test/ai_native_transparency_creation_test.dart' show createTransparency;

/// Emits complete saves and exact native spans for an independent reader.
Future<void> main() async {
  final Directory output = await Directory('test/corpus/output/opacity-masks').create(recursive: true);
  final Map<String, String> sources = {
    'path': opacityMaskSource(),
    'group': opacityMaskSource(grouped: true),
    'child': opacityMaskSource(grouped: true, child: true),
    'raster': opacityMaskSource(mask: artboardOpacityMask()),
  };
  final AiNativeSource producer = AiNativeData.extract(const AiCodec().decode(await File('test/corpus/files/simple_v2020.ai').readAsBytes())).single;
  final AiNativeRecords records = AiNativeRecords.decode(program: AiProgram.decode(bytes: producer.bytes));
  final List<AiNativeContainer> masks = records.containers.where((record) => record.type == 'Mask').toList();
  if (masks.length != 2) {
    throw StateError('The pinned producer must have two original masks.');
  }
  await File('${output.path}/producer.ps').writeAsBytes(producer.bytes);
  for (final (int, AiNativeContainer) item in masks.indexed) {
    sources['producer-${item.$1}'] = opacityMaskSource(mask: '%_${latin1.decode(producer.bytes.sublist(item.$2.start, item.$2.end))}\n');
  }
  await File('${output.path}/active.ai').writeAsBytes(const AiCodec().encode(activeOpacitySave()));
  final List<Map<String, Object?>> rows = [];
  for (final MapEntry<String, String> source in sources.entries) {
    final AiNativeAppearances before = appearanceEditingModel(source: source.value);
    final AiNativeAppearances after = editOpacityMask(before);
    final AiNativeAppearanceArtwork oldOwner = before.artworkFor(use: before.uses.first);
    final AiNativeAppearanceArtwork newOwner = after.artworkFor(use: after.uses.first);
    for (final (String, AiNativeAppearances) stage in [('before', before), ('after', after)]) {
      await File('${output.path}/${source.key}.${stage.$1}.ps').writeAsBytes(stage.$2.structure.drawing.records.program.bytes);
    }
    await File('${output.path}/${source.key}.ai').writeAsBytes(const AiCodec().encode(opacitySave(after, originalSource: source.value)));
    rows.add({
      'name': source.key,
      'beforeMask': [oldOwner.opacityMasks.single.record.start, oldOwner.opacityMasks.single.record.end],
      'afterMask': [newOwner.opacityMasks.single.record.start, newOwner.opacityMasks.single.record.end],
      'printing': [oldOwner.printingGroup.start, oldOwner.printingGroup.end],
    });
  }
  for (final AiNativeAppearancePartKind kind in [AiNativeAppearancePartKind.blend, AiNativeAppearancePartKind.fill, AiNativeAppearancePartKind.stroke]) {
    final AiNativeAppearances created = createTransparency(appearanceEditingModel(source: sources['path']), kind: kind);
    final AiNativeContainer part = created.styles.last.parts.last.record;
    await File('${output.path}/created-${kind.name}.part').writeAsBytes(created.structure.drawing.records.program.bytes.sublist(part.start, part.end));
  }
  await File('${output.path}/report.json').writeAsString('${const JsonEncoder.withIndent('  ').convert(rows)}\n');
  stdout.writeln('${rows.length + 1} complete opacity-mask saves written.');
}
