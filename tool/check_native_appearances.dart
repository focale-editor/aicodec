import 'dart:convert';
import 'dart:io';

import 'package:aikit/aikit.dart';

import '../test/ai_native_appearances_test.dart' show appearanceModel, appearanceStyle;

/// Exposes exact commands and literal assignments for independent decoding.
Map<String, Object?> _paint(AiNativePaintStyle paint) => {
  'record': [paint.record.start, paint.record.end],
  'type': paint.record.type,
  'instructions': [
    for (final AiNativeInstruction instruction in paint.instructions)
      {
        'span': [instruction.start, instruction.end],
        'operator': instruction.operator,
      },
  ],
  'assignments': [
    for (final AiNativePaintAssignment assignment in paint.assignments)
      {
        'instruction': paint.instructions.indexOf(assignment.instruction),
        'parameter': assignment.parameter.name,
        'numbers': assignment.numbers,
        'colors': [
          for (final AiColor color in assignment.colors) {'space': color.space.name, 'channels': color.channels},
        ],
        'dash': assignment.dash == null ? null : {'lengths': assignment.dash!.lengths, 'phase': assignment.dash!.phase},
      },
  ],
};

/// Reports all named source definitions without filtering effects or unused styles.
Map<String, Object?> appearanceInventory(AiNativeAppearances model) => {
  'styles': [
    for (final AiNativeAppearance style in model.styles)
      {
        'record': [style.resource.definition.start, style.resource.definition.end],
        'name': style.resource.nameBytes,
        'definitionType': style.definition.type,
        'uses': style.uses.map(model.uses.indexOf).toList(),
        'simplePaint': style.simplePaint == null ? null : _paint(style.simplePaint!),
        'parts': [
          for (final AiNativeAppearancePart part in style.parts)
            {
              'record': [part.record.start, part.record.end],
              'parent': part.parentIndex,
              'children': part.childIndices,
              'kind': part.kind.name,
              'filter': part.filter == null ? null : {'name': part.filter!.nameBytes, 'flags': part.filter!.flags},
              'visible': part.visible,
              'fillOrStroke': part.fillOrStroke,
              'evenOdd': part.evenOdd,
              'strokeAlignment': part.strokeAlignment?.name,
              'strokeSettings': part.strokeSettings == null
                  ? null
                  : {
                      'record': [part.strokeSettings!.record.start, part.strokeSettings!.record.end],
                      'version': part.strokeSettings!.version,
                      'adjustDashes': part.strokeSettings!.adjustDashes,
                    },
              'paints': [
                for (final AiNativeAppearancePaint paint in part.paints) {'field': paint.field.key, ..._paint(paint.style)},
              ],
            },
        ],
      },
  ],
  'uses': [
    for (final AiNativeResourceUse use in model.uses)
      {
        'span': [use.instruction.start, use.instruction.end],
        'name': use.nameBytes,
        'mode': use.instruction.operands.first.number,
        'resolution': use.resolution.name,
        'candidates': use.candidates.map((candidate) => model.styles.indexWhere((style) => identical(style.resource, candidate))).toList(),
      },
  ],
};

/// Inspects complete pinned CC programs and one explicit multiple-paint fixture.
Future<void> main() async {
  final Directory output = await Directory('test/corpus/output/appearances').create(recursive: true);
  final Map<String, AiNativeAppearances> sources = {'synthetic': appearanceModel(appearanceStyle())};
  for (final String name in ['simple_cc_legacy.ai', 'simple_v2020.ai', 'text_transforms.ai', 'flowtext.ai', 'gradient_linear.ai', 'gradient_radial.ai']) {
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
    await File('${output.path}/${entry.key}.ps').writeAsBytes(entry.value.structure.drawing.records.program.bytes);
    rows.add({'source': entry.key, ...appearanceInventory(entry.value)});
    stdout.writeln('${entry.key}: ${entry.value.styles.length} styles, ${entry.value.styles.fold(0, (count, style) => count + style.parts.length)} parts, ${entry.value.uses.length} uses');
  }
  await File('${output.path}/report.json').writeAsString('${const JsonEncoder.withIndent('  ').convert(rows)}\n');
}
