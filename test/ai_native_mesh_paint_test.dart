import 'dart:convert';

import 'package:aikit/aikit.dart';
import 'package:checks/checks.dart';
import 'package:test/test.dart';

/// Creates four adjacent cells with duplicated source corners and sharp handles.
String _grid() {
  final StringBuffer source = StringBuffer('/Mesh X!\n%_2 /Version X#\n%_/Cartesian /Type X#\n%_[2 2] /Size X#\n%_/Data X#\n%_/DeviceCMYK /CS X#\n');
  for (int first = 0; first < 2; first++) {
    for (int second = 0; second < 2; second++) {
      source.writeln('%_[$first $second] /P X#\n%_[-1] /R X#');
      for (final (int, int) offset in [(0, 0), (1, 0), (1, 1), (0, 1)]) {
        final int x = 10 * (first + offset.$1);
        final int y = 10 * (second + offset.$2);
        source.writeln('%_[0 0.5 1 0 1 $x $y $x $y 1 $x $y 1] /N X#');
      }
      source.writeln('%_/E X#');
    }
  }
  source.write('/End X!');
  return source.toString();
}

/// Wraps body artwork independently of the native writer.
AiNativeMeshes _decode(String mesh, {String setup = '', AiNativeLimits limits = const AiNativeLimits()}) => AiNativeMeshes.decode(
  records: AiNativeRecords.decode(
    program: AiProgram.decode(bytes: latin1.encode('%!PS-Adobe-3.0\n%%BeginSetup\n$setup\n%%EndSetup\n$mesh\n%%Trailer\n%%EOF\n'), limits: limits),
  ),
);

/// Selects a logical vertex without depending on list order or source offsets.
AiNativeMeshVertex _vertex(AiNativeMesh mesh, int first, int second) => mesh.vertices.singleWhere((vertex) => vertex.firstIndex == first && vertex.secondIndex == second);

/// Provides a known device replacement with a different source component count.
AiNativeMeshProcessColor _red() => AiNativeMeshProcessColor(space: .rgb, components: [1, 0, 0]);

/// Checks duplicated-corner edits, local color scope and explicit rejections.
void main() {
  test('indexes shared Cartesian vertices and edits all selected corner copies', () {
    final AiNativeMeshes source = _decode(_grid());
    final AiNativeMesh mesh = source.meshes.single;
    check(mesh.vertices.length).equals(9);
    check(_vertex(mesh, 1, 1).corners.length).equals(4);
    check(_vertex(mesh, 1, 0).corners.length).equals(2);
    check(_vertex(mesh, 0, 0).corners.length).equals(1);
    final AiNativeMeshes changed = source.paintVertices(
      mesh: mesh,
      changes: [
        AiNativeMeshVertexPaint(vertex: _vertex(mesh, 1, 1), color: _red(), opacity: 0.4),
        AiNativeMeshVertexPaint(
          vertex: _vertex(mesh, 0, 0),
          color: AiNativeMeshProcessColor(space: .gray, components: [0.8]),
        ),
        AiNativeMeshVertexPaint(vertex: _vertex(mesh, 1, 0), opacity: 0.2),
      ],
    );
    for (final AiNativeMeshVertex vertex in changed.meshes.single.vertices) {
      final AiNativeMeshVertex before = _vertex(mesh, vertex.firstIndex, vertex.secondIndex);
      check(vertex.position).equals(before.position);
      for (final (int, AiNativeMeshNode) entry in vertex.corners.indexed) {
        final AiNativeMeshNode node = entry.$2;
        check(node.firstHandle).equals(before.corners[entry.$1].firstHandle);
        check(node.secondHandle).equals(before.corners[entry.$1].secondHandle);
        check(node.weights).deepEquals(before.corners[entry.$1].weights);
        final bool center = vertex.firstIndex == 1 && vertex.secondIndex == 1;
        final bool corner = vertex.firstIndex == 0 && vertex.secondIndex == 0;
        check(node.color).deepEquals(
          center
              ? [1.0, 0.0, 0.0]
              : corner
              ? [0.8]
              : [0.0, 0.5, 1.0, 0.0],
        );
        check(node.colorSpace!.deviceName).equals(
          center
              ? 'DeviceRGB'
              : corner
              ? 'DeviceGray'
              : 'DeviceCMYK',
        );
        check(node.opacity).equals(
          center
              ? 0.4
              : vertex.firstIndex == 1 && vertex.secondIndex == 0
              ? 0.2
              : 1.0,
        );
      }
    }
    check(source.records.program.bytes).deepEquals(_decode(_grid()).records.program.bytes);
    check(() => mesh.vertices.clear()).throws<UnsupportedError>();
    check(() => mesh.vertices.first.corners.clear()).throws<UnsupportedError>();
  });

  test('keeps exact no-ops and reuses local switches during repeated edits', () {
    AiNativeMeshes source = _decode(_grid());
    final AiNativeMesh original = source.meshes.single;
    check(identical(source.paintVertices(mesh: original, changes: []), source)).isTrue();
    check(
      identical(
        source.paintVertices(
          mesh: original,
          changes: [AiNativeMeshVertexPaint(vertex: _vertex(original, 1, 1), opacity: 1)],
        ),
        source,
      ),
    ).isTrue();
    int fields = 0;
    for (int index = 0; index < 20; index++) {
      final AiNativeMesh mesh = source.meshes.single;
      final AiNativeMeshProcessColor color = index.isEven ? _red() : AiNativeMeshProcessColor(space: .gray, components: [0.5]);
      source = source.paintVertices(
        mesh: mesh,
        changes: [AiNativeMeshVertexPaint(vertex: _vertex(mesh, 1, 1), color: color)],
      );
      if (index == 0) {
        fields = source.meshes.single.fields.length;
      }
      check(source.meshes.single.fields.length).equals(fields);
      check(
        identical(
          source.paintVertices(
            mesh: source.meshes.single,
            changes: [AiNativeMeshVertexPaint(vertex: _vertex(source.meshes.single, 1, 1), color: color)],
          ),
          source,
        ),
      ).isTrue();
    }
  });

  test('models named inks and restores neighboring tints after local recoloring', () {
    final String grid = _grid()
        .replaceFirst('/DeviceCMYK /CS', '[[0 0 0 1 /DeviceCMYK (Bl\\141ck) /Separation] [0 1 0 0 /DeviceCMYK <4d6167656e7461> /Separation] 2 /NChannel] /CS')
        .replaceAll('0 0.5 1 0 1', '0.4 0.7 1');
    final AiNativeMeshes source = _decode(grid);
    final AiNativeMesh mesh = source.meshes.single;
    final AiNativeMeshColorSpace space = mesh.vertices.first.corners.first.colorSpace!;
    check(space.componentCount).equals(2);
    check(space.inks.map((ink) => latin1.decode(ink.nameBytes))).deepEquals(['Black', 'Magenta']);
    check(space.inks.first.components).deepEquals([0.0, 0.0, 0.0, 1.0]);
    check(space.inks.clear).throws<UnsupportedError>();
    final AiNativeMeshes changed = source.paintVertices(
      mesh: mesh,
      changes: [AiNativeMeshVertexPaint(vertex: _vertex(mesh, 1, 1), color: _red())],
    );
    for (final AiNativeMeshVertex vertex in changed.meshes.single.vertices) {
      for (final AiNativeMeshNode corner in vertex.corners) {
        if (vertex.firstIndex == 1 && vertex.secondIndex == 1) {
          check(corner.color).deepEquals([1.0, 0.0, 0.0]);
        } else {
          check(corner.color).deepEquals([0.4, 0.7]);
          check(corner.colorSpace!.inks.map((ink) => latin1.decode(ink.nameBytes))).deepEquals(['Black', 'Magenta']);
        }
      }
    }
    final AiNativeMeshes alpha = source.paintVertices(
      mesh: mesh,
      changes: [AiNativeMeshVertexPaint(vertex: _vertex(mesh, 1, 1), opacity: 0.2)],
    );
    check(alpha.meshes.single.fields.length).equals(mesh.fields.length);
    final String separation = _grid().replaceFirst('/DeviceCMYK /CS', '[0.1 0.2 0.3 /DeviceRGB (Ink) /Separation] /CS').replaceAll('0 0.5 1 0 1', '0.6 1');
    check(_decode(separation).meshes.single.vertices.first.corners.first.colorSpace!.inks.single.deviceName).equals('DeviceRGB');
    check(() => _decode(grid.replaceFirst('2 /NChannel', '3 /NChannel'))).throws<FormatException>();
    check(() => _decode(grid.replaceFirst('0.4 0.7 1', '0.4 1'))).throws<FormatException>();
  });

  test('finds body meshes after mark-based setup gradients and preserves resources', () {
    const String gradient = '%AI5_BeginGradient: (Unused)\n(Unused) 0 1 Bd\n[ 0 50 100 %_Bs\nBD\n%AI5_EndGradient';
    final AiNativeMeshes source = _decode(_grid(), setup: gradient);
    check(source.meshes.length).equals(1);
    final AiNativeMeshes changed = source.paintVertices(
      mesh: source.meshes.single,
      changes: [AiNativeMeshVertexPaint(vertex: source.meshes.single.vertices.first, color: _red())],
    );
    check(latin1.decode(changed.records.program.bytes).contains(gradient)).isTrue();
    final AiNativeMeshes grouped = _decode('u\n${_grid()}\nU\n9 () XW');
    check(
      grouped
          .paintVertices(
            mesh: grouped.meshes.single,
            changes: [AiNativeMeshVertexPaint(vertex: grouped.meshes.single.vertices.first, color: _red())],
          )
          .meshes
          .length,
    ).equals(1);
  });

  test('rejects foreign and duplicate selections, invalid input and output overflow', () {
    final AiNativeMeshes source = _decode(_grid());
    final AiNativeMeshes other = _decode(_grid());
    final AiNativeMesh mesh = source.meshes.single;
    final AiNativeMeshVertexPaint change = AiNativeMeshVertexPaint(vertex: mesh.vertices.first, color: _red());
    check(() => source.paintVertices(mesh: other.meshes.single, changes: [])).throws<ArgumentError>();
    check(
      () => source.paintVertices(
        mesh: mesh,
        changes: [AiNativeMeshVertexPaint(vertex: other.meshes.single.vertices.first, color: _red())],
      ),
    ).throws<ArgumentError>();
    check(() => source.paintVertices(mesh: mesh, changes: [change, change])).throws<ArgumentError>();
    check(() => AiNativeMeshVertexPaint(vertex: mesh.vertices.first)).throws<ArgumentError>();
    check(() => AiNativeMeshVertexPaint(vertex: mesh.vertices.first, opacity: double.nan)).throws<ArgumentError>();
    check(() => AiNativeMeshProcessColor(space: .rgb, components: [1, 0])).throws<ArgumentError>();
    check(() => AiNativeMeshProcessColor(space: .gray, components: [double.infinity])).throws<ArgumentError>();
    final AiNativeMeshes bounded = _decode(_grid(), limits: AiNativeLimits(maxDecodedBytes: source.records.program.bytes.length + 1));
    check(
      () => bounded.paintVertices(
        mesh: bounded.meshes.single,
        changes: [AiNativeMeshVertexPaint(vertex: bounded.meshes.single.vertices.first, color: _red())],
      ),
    ).throws<FormatException>();
  });

  test('rejects inconsistent shared positions and unresolved native dependencies', () {
    final AiNativeMeshes broken = _decode(_grid().replaceFirst('1 10 10 10 10', '1 11 10 10 10'));
    check(() => broken.meshes.single.vertices).throws<FormatException>();
    final List<String> unsupported = [
      _grid().replaceFirst('/Mesh X!', '%_/Mesh X!').replaceFirst('/End X!', '%_/End X!'),
      _grid().replaceFirst('%_/E X#', '%_[2] /Future X#\n%_/E X#'),
      '${_grid()}\n%_/ArtDictionary :\n%_1 /Real (Unknown paint cache) ,\n%_;',
      '${_grid()}\n1 (Unknown style) XW',
      'u\n${_grid()}\nU\n%_/ArtDictionary :\n%_1 /Real (Parent paint) ,\n%_;',
    ];
    for (final String body in unsupported) {
      final AiNativeMeshes source = _decode(body);
      check(
        () => source.paintVertices(
          mesh: source.meshes.single,
          changes: [AiNativeMeshVertexPaint(vertex: source.meshes.single.vertices.first, color: _red())],
        ),
      ).throws<UnsupportedError>();
    }
  });
}
