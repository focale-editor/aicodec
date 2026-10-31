import 'dart:convert';
import 'dart:io';

import 'package:aikit/aikit.dart';

/// A counted native fixture with different inherited states and nested owners.
const String _synthetic = '''%!PS-Adobe-3.0
%%Creator: Adobe Illustrator
%%BoundingBox: 0 0 100 100
%%EndComments
%%BeginProlog
%%EndProlog
%%BeginSetup
%%EndSetup
%AI5_BeginLayer
0 1 0 1 0 0 1 0 79 128 255 0 50 0 Lb
(Hidden locked) Ln
0 AE
1 A 1 Xw
u
0.2 g
3 As
0 0 m 10 0 L 10 10 L 0 0 L f
0 A 0 Xw
0 G 3 w
2 As
20 20 m 30 30 L S
U
LB
%AI5_EndLayer
%%PageTrailer
%%Trailer
%%EOF
''';

/// Records exact path/count spans for independent byte-preservation checks.
List<Map<String, Object?>> _paths(AiNativeDrawing drawing) {
  final List<Map<String, Object?>> result = [];
  int previous = drawing.records.program.bodyStart;
  for (final AiNativePath path in drawing.paths) {
    final List<AiNativeInstruction> counts = drawing.items.whereType<AiNativeInstruction>().where((item) => item.operator == 'As' && item.start >= previous && item.end <= path.start).toList();
    result.add({
      'start': path.start,
      'end': path.end,
      'count': counts.isEmpty ? null : [counts.single.start, counts.single.end],
      'geometry': [
        for (final AiNativeInstruction command in path.geometry) {'operator': command.operator, 'numbers': command.numbers},
      ],
      'paint': path.paint.operator,
    });
    previous = path.end;
  }
  return result;
}

/// Writes lifecycle operations for two pinned CC sources and counted fixtures.
Future<void> main() async {
  final Directory output = await Directory('test/corpus/output/path-lifecycle').create(recursive: true);
  final List<Map<String, Object?>> rows = [];
  for (final String name in ['simple_shapes.ai', 'simple_shapes_cc.ai', 'synthetic-counted']) {
    final List<int> bytes = name == 'synthetic-counted' ? latin1.encode(_synthetic) : AiNativeData.extract(const AiCodec().decode(await File('test/corpus/files/$name').readAsBytes())).single.bytes;
    final AiNativeDrawing before = AiNativeDrawing.decode(
      records: AiNativeRecords.decode(program: AiProgram.decode(bytes: bytes)),
    );
    final List<int> selection = name == 'synthetic-counted' ? [0, 1] : [18];
    final List<AiNativePath> paths = selection.map((index) => before.paths[index]).toList();
    await File('${output.path}/$name.original.ps').writeAsBytes(bytes);
    final List<AiNativePathInsertion> insertions = [
      for (final (int, AiNativePath) entry in paths.indexed)
        AiNativePathInsertion(
          after: entry.$2,
          segments: [
            AiPathSegment(operator: 'm', coordinates: [200 + 20 * entry.$1.toDouble(), 20]),
            AiPathSegment(operator: 'C', coordinates: [205, 25, 210, 30, 220, 40]),
          ],
          bounds: AiBoundingBox(left: -1000, bottom: -2000, right: 3000, top: 1500),
        ),
    ];
    for (final String operation in ['duplicate', 'remove', 'insert']) {
      final AiNativeDrawing after = switch (operation) {
        'duplicate' => before.duplicatePaths(paths: paths),
        'remove' => before.removePaths(paths: paths),
        _ => before.insertPaths(insertions: insertions),
      };
      final String file = '$name.$operation.ps';
      await File('${output.path}/$file').writeAsBytes(after.records.program.bytes);
      rows.add({
        'source': name,
        'original': '$name.original.ps',
        'result': file,
        'operation': operation,
        'selected': selection,
        'before': _paths(before),
        'after': _paths(after),
        'insertions': [
          for (final AiNativePathInsertion insertion in insertions)
            [
              for (final AiPathSegment segment in insertion.segments) {'operator': segment.operator, 'numbers': segment.coordinates},
            ],
        ],
      });
      stdout.writeln('$file: ${before.paths.length} -> ${after.paths.length} paths');
    }
    final AiNativeDrawing prepared = before.insertPaths(insertions: insertions);
    final List<int> selected = name == 'synthetic-counted' ? [0, 1] : [18, 19];
    final AiNativeDrawing reordered = prepared.reorderPaths(paths: selected.reversed.map((index) => prepared.paths[index]).toList());
    await File('${output.path}/$name.reorder.ps').writeAsBytes(reordered.records.program.bytes);
    rows.add({
      'source': name,
      'original': '$name.insert.ps',
      'result': '$name.reorder.ps',
      'operation': 'reorder',
      'selected': selected,
      'before': _paths(prepared),
      'after': _paths(reordered),
    });
  }
  final AiNativeDrawing grouped = AiNativeDrawing.decode(
    records: AiNativeRecords.decode(program: AiProgram.decode(bytes: latin1.encode(_synthetic.replaceFirst('0 A 0 Xw\n0 G 3 w', 'U\nu')))),
  );
  final AiNativeDrawing moved = grouped.movePathAfter(path: grouped.paths.first, after: grouped.paths.last);
  await File('${output.path}/synthetic-groups.original.ps').writeAsBytes(grouped.records.program.bytes);
  await File('${output.path}/synthetic-groups.move.ps').writeAsBytes(moved.records.program.bytes);
  rows.add({
    'source': 'synthetic-groups',
    'original': 'synthetic-groups.original.ps',
    'result': 'synthetic-groups.move.ps',
    'operation': 'move',
    'selected': [0],
    'anchor': 1,
    'before': _paths(grouped),
    'after': _paths(moved),
  });
  await File('${output.path}/report.json').writeAsString(const JsonEncoder.withIndent('  ').convert(rows));
}
