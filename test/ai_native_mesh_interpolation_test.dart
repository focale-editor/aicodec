import 'dart:convert';

import 'package:aikit/aikit.dart';
import 'package:checks/checks.dart';
import 'package:test/test.dart';

/// Creates straight-sided cells with an independently specified linear field.
String _grid({Set<int> compoundAxes = const {}, bool zeroHandles = false, bool collapsedInterior = false, double weight = 1, double opacity = 1, double Function(int, int)? color}) {
  final StringBuffer source = StringBuffer('/Mesh X!\n%_2 /Version X#\n%_/Cartesian /Type X#\n%_[2 2] /Size X#\n%_/Data X#\n');
  for (int first = 0; first < 2; first++) {
    for (int second = 0; second < 2; second++) {
      source.writeln('%_[$first $second] /P X#\n%_[-1] /R X#');
      final List<(int, int)> corners = [(first, second), (first + 1, second), (first + 1, second + 1), (first, second + 1)];
      final List<({double x, double y, int edge, bool corner, double color})> nodes = [];
      for (int edge = 0; edge < 4; edge++) {
        final (int, int) current = corners[edge];
        final (int, int) next = corners[(edge + 1) % 4];
        nodes.add((x: 3.0 * current.$1, y: 3.0 * current.$2, edge: edge, corner: true, color: color?.call(current.$1, current.$2) ?? (current.$1 + current.$2) / 4));
        if (compoundAxes.contains(edge % 2)) {
          final int across = edge.isEven ? current.$2 : current.$1;
          final double fraction = across == 0 ? 0.25 : 0.75;
          final double direction = edge < 2 ? fraction : 1 - fraction;
          nodes.add((x: 3 * (current.$1 + direction * (next.$1 - current.$1)), y: 3 * (current.$2 + direction * (next.$2 - current.$2)), edge: edge, corner: false, color: 0));
        }
      }
      for (int index = 0; index < nodes.length; index++) {
        final ({double color, bool corner, int edge, double x, double y}) node = nodes[index];
        final ({double color, bool corner, int edge, double x, double y}) previous = nodes[(index + nodes.length - 1) % nodes.length];
        final ({double color, bool corner, int edge, double x, double y}) next = nodes[(index + 1) % nodes.length];
        final bool reverse = !node.corner && node.edge < 2;
        final before = reverse ? next : previous;
        final after = reverse ? previous : next;
        final double outgoingX = zeroHandles || collapsedInterior && node.x == 3 ? node.x : (2 * node.x + after.x) / 3;
        final double outgoingY = zeroHandles ? node.y : (2 * node.y + after.y) / 3;
        final double incomingX = zeroHandles || collapsedInterior && node.x == 3 ? node.x : (2 * node.x + before.x) / 3;
        final double incomingY = zeroHandles ? node.y : (2 * node.y + before.y) / 3;
        final List<double> values = node.corner
            ? [node.color, opacity, node.x, node.y, outgoingX, outgoingY, weight, incomingX, incomingY, weight]
            : [node.x, node.y, outgoingX, outgoingY, incomingX, incomingY, weight];
        final String operator = node.corner
            ? 'N'
            : node.edge.isEven
            ? 'A'
            : 'S';
        source.writeln('%_[${values.map(_number).join(' ')}] /$operator X#');
      }
      source.writeln('%_/E X#');
    }
  }
  source.write('/End X!');
  return source.toString();
}

/// Keeps fixture lexemes identical on the VM and JavaScript runtimes.
String _number(double value) => value == value.truncateToDouble() ? value.toStringAsFixed(1) : value.toString();

/// Wraps synthetic native data without involving a mesh writer.
AiNativeMeshes _decode(String body) => AiNativeMeshes.decode(
  records: AiNativeRecords.decode(program: AiProgram.decode(bytes: latin1.encode('%!PS-Adobe-3.0\n%%EndSetup\n$body\n%%Trailer\n%%EOF\n'))),
);

/// Requires numerically close coordinates without exact floating-point ties.
void _near(double actual, double expected) => check((actual - expected).abs()).isLessThan(1e-10);

/// Checks interpolation behavior, immutable access and conservative rejection.
void main() {
  test('evaluates straight tensor geometry and a linear color field', () {
    final AiNativeMeshes source = _decode(_grid(opacity: 0.6));
    final List<int> before = source.records.program.bytes.toList();
    final AiNativeMeshInterpolation interpolation = AiNativeMeshInterpolation(mesh: source.meshes.single);
    check(interpolation.space).equals(AiNativeMeshProcessSpace.gray);
    check(interpolation.opacity).equals(0.6);
    check(interpolation.surfaces.length).equals(4);
    for (final AiNativeMeshSurface surface in interpolation.surfaces) {
      for (final double first in [0.0, 0.2, 0.5, 1.0]) {
        for (final double second in [0.0, 0.7, 1.0]) {
          final ({double x, double y}) point = surface.positionAt(first: first, second: second);
          _near(point.x, 3 * (surface.patch.firstIndex + first));
          _near(point.y, 3 * (surface.patch.secondIndex + second));
          _near(interpolation.colorAt(patch: surface.patch, first: first, second: second).components.single, (surface.patch.firstIndex + first + surface.patch.secondIndex + second) / 4);
        }
      }
      check(surface.controlPoints.clear).throws<UnsupportedError>();
    }
    check(interpolation.surfaces.clear).throws<UnsupportedError>();
    check(source.records.program.bytes).deepEquals(before);
  });

  test('partitions unequal opposite boundaries on either grid axis', () {
    for (final int axis in [0, 1]) {
      final AiNativeMeshInterpolation interpolation = AiNativeMeshInterpolation(mesh: _decode(_grid(compoundAxes: {axis})).meshes.single);
      check(interpolation.surfaces.length).equals(10);
      for (final AiNativeMeshSurface surface in interpolation.surfaces) {
        final double first = surface.bounds.firstStart + 0.3 * (surface.bounds.firstEnd - surface.bounds.firstStart);
        final double second = surface.bounds.secondStart + 0.7 * (surface.bounds.secondEnd - surface.bounds.secondStart);
        final ({double x, double y}) point = surface.positionAt(first: 0.3, second: 0.7);
        _near(point.x, 3 * (surface.patch.firstIndex + first));
        _near(point.y, 3 * (surface.patch.secondIndex + second));
        _near(interpolation.colorAt(patch: surface.patch, first: first, second: second).components.single, (surface.patch.firstIndex + first + surface.patch.secondIndex + second) / 4);
      }
    }
  });

  test('limits color extrema while preserving values at every vertex', () {
    final AiNativeMeshInterpolation interpolation = AiNativeMeshInterpolation(mesh: _decode(_grid(color: (first, second) => first == 1 ? 1 : 0)).meshes.single);
    for (final AiNativeMeshSurface surface in interpolation.surfaces) {
      final AiNativeMeshPatch patch = surface.patch;
      _near(interpolation.colorAt(patch: patch, first: 0.5, second: 0.2).components.single, 0.75);
      _near(interpolation.colorAt(patch: patch, first: patch.firstIndex == 0 ? 1 : 0, second: 0.5).components.single, 1);
    }
  });

  test('retains collapsed interior tangents with zero directional color slope', () {
    final AiNativeMeshInterpolation interpolation = AiNativeMeshInterpolation(mesh: _decode(_grid(collapsedInterior: true, color: (first, second) => first / 2)).meshes.single);
    final AiNativeMeshSurface surface = interpolation.surfaces.first;
    _near(surface.positionAt(first: 0.5, second: 0.5).x, 1.875);
    _near(interpolation.colorAt(patch: surface.patch, first: 0.5, second: 0.5).components.single, 0.375);
  });

  test('requires explicit common colors and checks every shared corner copy', () {
    final String mixed = _grid().replaceFirst('%_/Data X#', '%_/Data X#\n%_/DeviceRGB /CS X#').replaceFirst('%_[0.0 1.0', '%_[0 0 0 1.0').replaceFirst(' /N X#', ' /N X#\n%_/DeviceGray /CS X#');
    final AiNativeMesh mesh = _decode(mixed).meshes.single;
    check(() => AiNativeMeshInterpolation(mesh: mesh)).throws<UnsupportedError>();
    int calls = 0;
    final AiNativeMeshInterpolation converted = AiNativeMeshInterpolation(
      mesh: mesh,
      resolveColor: (corner) {
        calls++;
        return AiNativeMeshProcessColor(space: .gray, components: [corner.color.first]);
      },
    );
    check(calls).equals(16);
    _near(converted.colorAt(patch: mesh.patches.first, first: 0.5, second: 0.5).components.single, 0.25);
    check(() => AiNativeMeshInterpolation(mesh: mesh, resolveColor: (corner) => null)).throws<UnsupportedError>();
    final String inconsistent = _grid().replaceFirst('%_[0.25 1.0', '%_[0.3 1.0');
    check(() => AiNativeMeshInterpolation(mesh: _decode(inconsistent).meshes.single)).throws<FormatException>();
  });

  test('keeps named inks explicit and interpolates all resolved components', () {
    final AiNativeMesh mesh = _decode(_grid().replaceFirst('%_/Data X#', '%_/Data X#\n%_[0 0 0 1 /DeviceCMYK (Black) /Separation] /CS X#')).meshes.single;
    check(() => AiNativeMeshInterpolation(mesh: mesh)).throws<UnsupportedError>();
    for (final AiNativeMeshProcessSpace space in [AiNativeMeshProcessSpace.rgb, AiNativeMeshProcessSpace.cmyk]) {
      final AiNativeMeshInterpolation interpolation = AiNativeMeshInterpolation(
        mesh: mesh,
        resolveColor: (corner) => AiNativeMeshProcessColor(space: space, components: List.filled(space.componentCount, corner.inkTints.single.tint)),
      );
      check(interpolation.space).equals(space);
      final AiNativeMeshProcessColor color = interpolation.colorAt(patch: mesh.patches.first, first: 0.4, second: 0.8);
      check(color.components.length).equals(space.componentCount);
      for (final double component in color.components) {
        _near(component, 0.3);
      }
    }
  });

  test('rejects unsupported weights, opacity, extension fields and boundaries', () {
    for (final String body in [
      _grid(weight: 0.5),
      _grid(zeroHandles: true),
      _grid(compoundAxes: {0, 1}),
      _grid().replaceFirst('%_[0.0 1.0', '%_[0.0 0.5'),
      _grid().replaceFirst('%_/Data X#', '%_1 /Future X#\n%_/Data X#'),
    ]) {
      check(() => AiNativeMeshInterpolation(mesh: _decode(body).meshes.single)).throws<UnsupportedError>();
    }
    final AiNativeMeshes source = _decode(_grid());
    final AiNativeMeshNode corner = source.meshes.single.patches.first.nodes[1];
    final String text = latin1.decode(source.records.program.bytes);
    final String field = text.substring(corner.field.start, corner.field.end);
    final String changed = text.replaceFirst(field, field.replaceFirst('3.0 1.0', '3.1 1.0'));
    final AiNativeMeshes inconsistent = AiNativeMeshes.decode(
      records: AiNativeRecords.decode(program: AiProgram.decode(bytes: latin1.encode(changed))),
    );
    check(() => AiNativeMeshInterpolation(mesh: inconsistent.meshes.single)).throws<FormatException>();
  });

  test('rejects foreign cells and invalid evaluation parameters', () {
    final AiNativeMeshInterpolation interpolation = AiNativeMeshInterpolation(mesh: _decode(_grid()).meshes.single);
    final AiNativeMeshSurface surface = interpolation.surfaces.first;
    check(() => interpolation.colorAt(patch: _decode(_grid()).meshes.single.patches.first, first: 0.5, second: 0.5)).throws<ArgumentError>();
    for (final double value in [-0.1, 1.1, double.nan, double.infinity]) {
      check(() => surface.positionAt(first: value, second: 0.5)).throws<ArgumentError>();
      check(() => surface.positionAt(first: 0.5, second: value)).throws<ArgumentError>();
      check(() => interpolation.colorAt(patch: surface.patch, first: value, second: 0.5)).throws<ArgumentError>();
      check(() => interpolation.colorAt(patch: surface.patch, first: 0.5, second: value)).throws<ArgumentError>();
    }
  });

  test('rejects one-cell extents and collapsed numeric ranges without source mutation', () {
    final AiNativeMeshes source = _decode(_grid());
    final AiNativeMesh mesh = source.meshes.single;
    final String text = latin1.decode(source.records.program.bytes);
    final AiNativeMeshPatch patch = mesh.patches.first;
    final String single = '/Mesh X!\n%_2 /Version X#\n%_/Cartesian /Type X#\n%_[1 1] /Size X#\n%_/Data X#\n${text.substring(patch.start, patch.end)}\n/End X!';
    check(() => AiNativeMeshInterpolation(mesh: _decode(single).meshes.single)).throws<UnsupportedError>();
    final List<AiSourceEdit> edits = [
      for (final AiNativeMeshPatch cell in mesh.patches)
        for (final AiNativeMeshNode corner in cell.nodes)
          for (final int index in [3, 4, 5, 6, 8, 9])
            AiSourceEdit(start: corner.field.values[index].start, end: corner.field.values[index].end, bytes: latin1.encode((corner.field.values[index].number! * 1e-200).toString())),
    ];
    final AiProgram shrunken = AiNativeEditor.apply(program: source.records.program, edits: edits);
    final AiNativeMesh tiny = AiNativeMeshes.decode(records: AiNativeRecords.decode(program: shrunken)).meshes.single;
    check(() => AiNativeMeshInterpolation(mesh: tiny)).throws<UnsupportedError>();
    check(latin1.decode(source.records.program.bytes)).equals(text);
  });
}
