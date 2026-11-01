import 'dart:convert';
import 'dart:io';

import 'package:aikit/aikit.dart';

import 'check_native_appearances.dart' show appearanceInventory;

/// Explicit process alternatives supplied by the host for a magenta stroke.
const List<double> _magenta = [0, 1, 0, 0, 1, 0, 1];

/// Requires identical saved alternatives before selecting fixture paint commands.
bool _same(List<double>? first, List<double> second) => first != null && first.length == second.length && first.indexed.every((entry) => entry.$2 == second[entry.$1]);

/// Recolors existing derived stroke paths and restores their outgoing paint.
AiNativeAppearanceReplacement _printing(AiNativeAppearances model, AiNativeAppearanceArtwork artwork, AiNativePaintAssignment paint, {required bool offset, required AiBoundingBox bounds}) {
  final AiProgram program = model.structure.drawing.records.program;
  final AiNativeGroup group = artwork.printingGroup;
  final List<AiNativeInstruction> assignments = model.structure.drawing.items
      .whereType<AiNativeInstruction>()
      .where((item) => item.start > group.start && item.end < group.end && item.operator == (offset ? 'Xa' : 'XA') && _same(item.numbers, paint.numbers!))
      .toList();
  if (assignments.length != 1 || program.bytes[group.end - 1] != 85) {
    throw StateError('Expected exactly one explicit derived stroke color in a closed printing group.');
  }
  final AiNativeInstruction assignment = assignments.single;
  return AiNativeAppearanceReplacement(
    artwork: artwork,
    bytes: AiNativeEditor.copyRange(
      program: program,
      start: group.start,
      end: group.end,
      edits: [
        for (final (int, AiToken) operand in assignment.operands.indexed) AiSourceEdit(start: operand.$2.start, end: operand.$2.end, bytes: latin1.encode(_magenta[operand.$1].toString())),
        AiSourceEdit(start: group.end - 1, end: group.end - 1, bytes: [...program.bytes.sublist(assignment.start, assignment.end), 10]),
      ],
    ),
    bounds: bounds,
  );
}

/// Exercises complete producer files, including all unselected setup and artwork.
Future<void> main() async {
  final Directory output = await Directory('test/corpus/output/appearance-artwork').create(recursive: true);
  final List<Map<String, Object?>> rows = [];
  for (final String name in ['stroke_styles.ai', 'fill_stroke_test_cc.ai', 'fill_stroke_test.ai']) {
    final AiNativeSource source = AiNativeData.extract(const AiCodec().decode(await File('test/corpus/files/$name').readAsBytes())).single;
    final AiNativeAppearances model = AiNativeAppearances.decode(
      structure: AiNativeStructure.decode(
        drawing: AiNativeDrawing.decode(
          records: AiNativeRecords.decode(program: AiProgram.decode(bytes: source.bytes)),
        ),
      ),
    );
    final AiNativeDrawing drawing = model.structure.drawing;
    final List<AiNativeResourceUse> users = model.uses
        .where((use) => use.instruction.start >= drawing.records.program.bodyStart && !drawing.liveShapes.any((shape) => shape.end == use.instruction.end))
        .toList();
    if (users.length != 2) {
      throw StateError('Expected two ordinary appearance users in each producer fixture.');
    }
    await File('${output.path}/$name.before.ps').writeAsBytes(source.bytes);
    for (final (int, AiNativeResourceUse) selected in users.indexed) {
      final AiNativeAppearance style = model.resolve(use: selected.$2)!;
      final AiNativeAppearancePart part = style.parts.singleWhere((part) => const {AiNativeAppearancePartKind.stroke, AiNativeAppearancePartKind.strokeOffset}.contains(part.kind));
      final AiNativePaintAssignment paint = part.paints.single.style.assignments.singleWhere((assignment) => assignment.parameter == .strokeColor);
      final List<AiNativePaintChange> paints = [AiNativePaintChange(assignment: paint, values: _magenta)];
      final AiNativeAppearanceArtwork artwork = model.artworkFor(use: selected.$2);
      final AiNativeAppearanceReplacement group = _printing(model, artwork, paint, offset: part.kind == .strokeOffset, bounds: source.asPostScript().boundingBox!);
      final AiNativeAppearances changed = model.updateSelected(appearance: style, paints: paints, artwork: [group], nameBytes: latin1.encode('Magenta stroke'));
      AiNativeAppearances? shared;
      String? sharedRejection;
      try {
        shared = model.updateShared(
          appearance: style,
          paints: paints,
          artwork: [
            for (final AiNativeResourceUse use in style.uses)
              _printing(
                model,
                model.artworkFor(use: use),
                paint,
                offset: part.kind == .strokeOffset,
                bounds: source.asPostScript().boundingBox!,
              ),
          ],
        );
      } on UnsupportedError catch (error) {
        sharedRejection = error.message;
      }
      final String expectedRejection = name == 'stroke_styles.ai'
          ? 'Native transformation requires a supported appearance style.'
          : 'Reference qualification does not cover Dictionary/GenAIRecorded (null).';
      if (shared != null || sharedRejection != expectedRejection || style.uses.length != 1) {
        throw StateError('The pinned full-source shared boundary changed; inspect it before updating acceptance.');
      }
      final String prefix = '$name.${selected.$1}';
      await File('${output.path}/$prefix.selected.ps').writeAsBytes(changed.structure.drawing.records.program.bytes);
      if (shared != null) {
        await File('${output.path}/$prefix.shared.ps').writeAsBytes(shared.structure.drawing.records.program.bytes);
      }
      rows.add({
        'file': name,
        'user': selected.$1,
        'style': model.styles.indexOf(style),
        'use': model.uses.indexOf(selected.$2),
        'part': part.index,
        'before': {'source': '$name.before', ...appearanceInventory(model)},
        'selected': {'source': '$prefix.selected', ...appearanceInventory(changed)},
        'shared': shared == null ? null : {'source': '$prefix.shared', ...appearanceInventory(shared)},
        'sharedRejection': sharedRejection,
      });
      stdout.writeln('$prefix: selected edit; shared ${sharedRejection ?? 'passed'}, ${style.uses.length} shared owners');
    }
  }
  await File('${output.path}/report.json').writeAsString('${const JsonEncoder.withIndent('  ').convert(rows)}\n');
}
