import 'dart:convert';
import 'dart:io';

import 'package:aicodec/aicodec.dart';

import '../test/ai_native_artwork_movement_test.dart' show movementPath;
import '../test/ai_native_group_metadata_test.dart' show groupMetadataSource, groupResetEmptySource, groupResetSource;
import '../test/ai_native_objects_test.dart' show objectSource;
import '../test/ai_native_subtree_reordering_test.dart' show subtreeReorderingGroups;

/// Opens exact source without generating compatibility artwork.
AiNativeDrawing _drawing(List<int> bytes) => AiNativeDrawing.decode(
  records: AiNativeRecords.decode(program: AiProgram.decode(bytes: bytes)),
);

/// Orders source groups independently of their closing-event traversal order.
List<AiNativeGroup> _groups(AiNativeDrawing drawing) => drawing.groups.toList()..sort((first, second) => first.start.compareTo(second.start));

/// Supplies an explicit canvas origin for the independent reader's SVG view.
String _canvas(String text) => text.replaceFirst('%%EndComments', '%AI3_TemplateBox: 50 -50 50 -50\n%AI5_ArtSize: 100 100\n%%EndComments');

/// Writes fixed reset-owning parent transactions for independent verification.
Future<void> main() async {
  final Directory output = await Directory('test/corpus/output/group-resets').create(recursive: true);
  final List<Map<String, Object?>> rows = [];

  /// Retains exact input, selection and explicit policies for accepted/refused edits.
  Future<void> record(String name, String variant, AiNativeDrawing source, List<AiNativeGroup> groups, {Object? recipe, bool discardMetadata = false}) async {
    AiNativeDrawing result = source;
    String? issue;
    try {
      result = source.ungroup(groups: groups, discardMetadata: discardMetadata, inheritParentFlags: true);
    } on UnsupportedError catch (error) {
      issue = error.toString();
    }
    final AiNativeObjects objects = AiNativeObjects.decode(drawing: source);
    final String original = '$name.$variant.original.ps';
    final String changed = '$name.$variant.ps';
    await File('${output.path}/$original').writeAsBytes(source.records.program.bytes);
    await File('${output.path}/$changed').writeAsBytes(result.records.program.bytes);
    rows.add({
      'source': name,
      'variant': variant,
      'operation': 'dissolve',
      'original': original,
      'result': changed,
      'recipe': recipe,
      'inheritParentFlags': true,
      'discardMetadata': discardMetadata,
      'issue': issue,
      'selected': [
        for (final AiNativeGroup group in groups)
          {
            'kind': 'group',
            'name': objects.forSource(group).identifier == null ? '' : latin1.decode(objects.forSource(group).identifier!.bytes),
            'reset': true,
            'index': _groups(source).indexOf(group),
            'start': objects.forSource(group).start,
            'end': objects.forSource(group).end,
            'openingEnd': group.opening.end,
            'closingStart': group.closing.start,
          },
      ],
    });
    stdout.writeln('$changed: ${issue ?? 'saved'}');
  }

  for (final String name in ['layers_and_sublayers.ai', 'simple_shapes.ai', 'simple_shapes_cc.ai', 'gradient_linear.ai', 'gradient_radial.ai']) {
    final AiNativeDrawing original = _drawing(AiNativeData.extract(const AiCodec().decode(await File('test/corpus/files/$name').readAsBytes())).single.bytes);
    if (name == 'layers_and_sublayers.ai') {
      await record(name, 'original', original, [original.groups.single]);
      continue;
    }
    final int start = AiNativeObjects.decode(drawing: original).forSource(original.liveShapes.first.appearanceGroup!).start;
    final int end = original.liveShapes[1].end;
    const String opening = '0 Ae\nu\n';
    const String closing = '\nU\n9 () XW\n';
    final List<int> bytes = original.records.program.bytes;
    final AiNativeDrawing source = _drawing([...bytes.take(start), ...latin1.encode(opening), ...bytes.sublist(start, end), ...latin1.encode(closing), ...bytes.skip(end)]);
    final AiNativeGroup group = source.groups.singleWhere((group) => group.start == start + 5);
    await record(name, 'wrapped', source, [group], recipe: {'start': start, 'end': end, 'opening': opening, 'closing': closing});
  }
  final AiNativeDrawing ordinary = _drawing(latin1.encode(_canvas(groupMetadataSource)));
  final List<AiNativeGroup> groups = _groups(ordinary);
  await record('synthetic', 'outer', ordinary, [groups.first]);
  await record('synthetic', 'inner', ordinary, [groups[1]]);
  await record('synthetic', 'disjoint', ordinary, [groups.first, groups.last]);
  final AiNativeDrawing empty = _drawing(latin1.encode(_canvas(groupResetEmptySource)));
  await record('synthetic', 'empty', empty, [empty.groups.last]);
  final AiNativeDrawing mixed = _drawing(latin1.encode(groupResetSource()));
  await record('synthetic', 'mixed', mixed, subtreeReorderingGroups(mixed), discardMetadata: true);
  for (final (int, String) entry in ['1 (Named) XW', '2 () XW', '6 () XW', '7 () XW', '9 (Named) XW', '%_9 () XW', '9 0 XW', '9 () XW 9 () XW'].indexed) {
    final AiNativeDrawing source = _drawing(latin1.encode(_canvas(objectSource('u ${movementPath(10)} U\n${entry.$2}', setup: ''))));
    await record('synthetic', 'reject-${entry.$1}', source, source.groups);
  }
  await File('${output.path}/report.json').writeAsString('${const JsonEncoder.withIndent('  ').convert(rows)}\n');
}
