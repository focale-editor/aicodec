import 'dart:convert';
import 'dart:io';

import 'package:aikit/aikit.dart';

/// Exercises state changes at both nested object and sibling slot boundaries.
const String _synthetic = '''%!PS-Adobe-3.0
%%Creator: Adobe Illustrator
%%BoundingBox: 0 0 100 100
%%EndComments
%%BeginProlog
%%EndProlog
%%BeginSetup
%%EndSetup
0 1 0 1 0 0 1 0 79 128 255 0 50 0 Lb
(Hidden locked) Ln
0 AE
0 A 0 Xw 0.1 g 0 G 2 w [] 0 d
u
3 As 0 0 m 10 0 L 10 10 L 0 0 L f
0.7 g 1 A 1 Xw [2 3] 1 d 5 w
u 2 As 20 20 m 30 30 L S U
U
0 A 0 Xw 0.4 g 0 G 2 w [] 0 d
u 40 40 m 50 50 L f 0.9 g 4 w U
60 60 m 70 70 L N
LB
%%PageTrailer
%%Trailer
%%EOF
''';

/// Reopens native bytes through the ordinary source model.
AiNativeDrawing _drawing(List<int> bytes) => AiNativeDrawing.decode(
  records: AiNativeRecords.decode(program: AiProgram.decode(bytes: bytes)),
);

/// Records native group spans for independent ownership and byte checks.
List<Map<String, Object>> _groups(AiNativeDrawing drawing) => [
  for (final AiNativeGroup group in drawing.groups)
    {
      'start': group.start,
      'end': group.end,
      'opening': [group.opening.start, group.opening.end],
      'closing': [group.closing.start, group.closing.end],
      'paths': group.paths.map((path) => drawing.paths.indexOf(path)).toList(),
    },
];

/// Writes exact source transactions for external native decoding.
Future<void> main() async {
  final Directory output = await Directory('test/corpus/output/group-lifecycle').create(recursive: true);
  final List<Map<String, Object>> rows = [];

  /// Saves one independently checkable operation and its original selection.
  Future<void> record(String source, String original, String operation, AiNativeDrawing before, AiNativeDrawing after, List<int> selected, {int? anchor}) async {
    final String file = '$source.$operation.ps';
    await File('${output.path}/$file').writeAsBytes(after.records.program.bytes);
    rows.add({
      'source': source,
      'original': original,
      'result': file,
      'operation': operation,
      'selected': selected,
      'anchor': ?anchor,
      'before': _groups(before),
      'after': _groups(after),
      'pathSpans': [
        for (final AiNativePath path in before.paths) [path.start, path.end],
      ],
    });
    stdout.writeln('$file: ${before.groups.length} -> ${after.groups.length} groups');
  }

  for (final String name in ['simple_shapes.ai', 'simple_shapes_cc.ai']) {
    final AiNativeDrawing before = _drawing(AiNativeData.extract(const AiCodec().decode(await File('test/corpus/files/$name').readAsBytes())).single.bytes);
    await File('${output.path}/$name.original.ps').writeAsBytes(before.records.program.bytes);
    final AiNativeDrawing grouped = before.groupPaths(paths: [before.paths[18]]);
    await record(name, '$name.original.ps', 'group', before, grouped, [18]);
    final AiNativeGroup group = grouped.groups.singleWhere((group) => group.paths.contains(grouped.paths[18]));
    final List<int> selected = [grouped.groups.indexOf(group)];
    await record(name, '$name.group.ps', 'duplicate', grouped, grouped.duplicateGroups(groups: [group]), selected);
    await record(name, '$name.group.ps', 'remove', grouped, grouped.removeGroups(groups: [group]), selected);
    await record(name, '$name.group.ps', 'ungroup', grouped, grouped.ungroup(groups: [group]), selected);
  }
  final AiNativeDrawing synthetic = _drawing(latin1.encode(_synthetic));
  await File('${output.path}/synthetic-state.original.ps').writeAsBytes(synthetic.records.program.bytes);
  final AiNativeGroup first = synthetic.groups[1];
  final AiNativeGroup last = synthetic.groups[2];
  await record('synthetic-state', 'synthetic-state.original.ps', 'duplicate', synthetic, synthetic.duplicateGroups(groups: [first]), [1]);
  await record('synthetic-state', 'synthetic-state.original.ps', 'remove', synthetic, synthetic.removeGroups(groups: [first]), [1]);
  await record('synthetic-state', 'synthetic-state.original.ps', 'ungroup', synthetic, synthetic.ungroup(groups: [first], inheritParentFlags: true), [1]);
  await record('synthetic-state', 'synthetic-state.original.ps', 'reorder', synthetic, synthetic.reorderGroups(groups: [last, first]), [2, 1]);
  await record('synthetic-state', 'synthetic-state.original.ps', 'move', synthetic, synthetic.moveGroupAfter(group: synthetic.groups.first, after: last, inheritParentFlags: true), [0], anchor: 2);
  await File('${output.path}/report.json').writeAsString(const JsonEncoder.withIndent('  ').convert(rows));
}
