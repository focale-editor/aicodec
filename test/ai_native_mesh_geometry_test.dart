import 'dart:convert';

import 'package:checks/checks.dart';
import 'package:illustratorkit/illustratorkit.dart';
import 'package:test/test.dart';

/// Independent two-patch packet with shared corners and distinct native handles.
String meshGeometryPacket({bool ink = false}) {
  final StringBuffer output = StringBuffer('/Mesh X!\n%_2 /Version X#\n%_/Cartesian /Type X#\n%_[2 1] /Size X#\n%_/Data X#\n');
  output.writeln(ink ? '%_[0 0 0 1 /DeviceCMYK (Named ink) /Separation] /CS X#' : '%_/DeviceRGB /CS X#');
  for (int first = 0; first < 2; first++) {
    output.writeln('%_[$first 0] /P X#\n%_[0.25] /R X#');
    if (first == 0) {
      output.writeln('%_[0 5 0 4 0 6 .75] /A X#');
    }
    for (final (int x, int y) in [(first * 10, 0), ((first + 1) * 10, 0), ((first + 1) * 10, 10), (first * 10, 10)]) {
      output.writeln('%_[${ink ? '.4' : '1 .25 0'} .8 $x $y ${x + 2} $y 1 $x ${y + 2} .9] /N X#');
    }
    output.writeln('%_/E X#');
  }
  output.write('/End X!');
  return output.toString();
}

/// Gives geometry edits stable explicit bounds and ordinary neighboring artwork.
AiNativeMeshes meshGeometrySource({String? packet, AiNativeLimits limits = const AiNativeLimits()}) => AiNativeMeshes.decode(
  records: AiNativeRecords.decode(
    program: AiProgram.decode(
      limits: limits,
      bytes: latin1.encode('''%!PS-Adobe-3.0
%%BoundingBox: -100 -100 100 100
%%HiResBoundingBox: -100.0 -100.0 100.0 100.0
%%BeginSetup
%%EndSetup
${packet ?? meshGeometryPacket()}
0 g
50 50 m
60 60 L
S
%%Trailer
%%EOF
'''),
    ),
  ),
);

/// Complete host-supplied ink rectangle, not inferred through tessellation.
final AiBoundingBox meshGeometryBounds = AiBoundingBox(left: -50, bottom: -50, right: 50, top: 50);

/// Supplies a different coherent grid explicitly, including native patch parameters.
AiNativeMeshDefinition meshReplacementGrid() => AiNativeMeshDefinition(
  firstSize: 1,
  secondSize: 2,
  patches: [
    for (int second = 0; second < 2; second++)
      AiNativeMeshPatchDefinition(
        firstIndex: 0,
        secondIndex: second,
        nativeParameters: [-1],
        nodes: [
          for (final (double x, double y) in [(0.0, second * 10.0), (10.0, second * 10.0), (10.0, (second + 1) * 10.0), (0.0, (second + 1) * 10.0)])
            AiNativeMeshNodeDefinition.corner(
              position: (x: x, y: y),
              firstHandle: (x: x + 1, y: y),
              secondHandle: (x: x, y: y + 1),
              weights: [1, 1],
              color: AiNativeMeshProcessColor(space: .gray, components: [.6]),
              opacity: .3,
            ),
        ],
      ),
  ],
);

/// Deferred geometry/topology regressions independent of application rendering.
void main() {
  test('requires explicit frame orientation for affine and topology replacement', () {
    final AiNativeMeshes source = meshGeometrySource(packet: '${meshGeometryPacket()}\n%_/ArtDictionary :\n%_(0.5) /String (BBAccumRotation) ,\n%_;');
    final AiNativeMesh mesh = source.meshes.single;
    check(() => source.transform(mesh: mesh, transform: AiNativeAffineTransform(tx: 4), bounds: meshGeometryBounds)).throws<ArgumentError>();
    final AiNativeMeshes changed = source.transform(mesh: mesh, transform: AiNativeAffineTransform(tx: 4), bounds: meshGeometryBounds, rotationRadians: .25);
    check(changed.records.containers.singleWhere((record) => record.type == 'ArtDictionary')['BBAccumRotation']!.text()).equals('0.250000');
    check(() => source.replaceTopology(mesh: mesh, definition: meshReplacementGrid(), bounds: meshGeometryBounds)).throws<ArgumentError>();
    final AiNativeMeshes replaced = source.replaceTopology(mesh: mesh, definition: meshReplacementGrid(), bounds: meshGeometryBounds, rotationRadians: 0);
    check(replaced.records.containers.singleWhere((record) => record.type == 'ArtDictionary')['BBAccumRotation']!.text()).equals('0.000000');
  });

  test('bounds aggregate geometry growth without mutating the source', () {
    final int size = meshGeometrySource().records.program.bytes.length;
    final AiNativeMeshes source = meshGeometrySource(limits: AiNativeLimits(maxDecodedBytes: size + 1));
    final List<int> original = List.of(source.records.program.bytes);
    check(() => source.transform(mesh: source.meshes.single, transform: AiNativeAffineTransform(tx: 1234), bounds: meshGeometryBounds)).throws<AiLimitException>();
    check(source.records.program.bytes).deepEquals(original);
  });

  test('moves every shared corner occurrence and retains native paint and neighbors', () {
    final AiNativeMeshes source = meshGeometrySource();
    final AiNativeMesh mesh = source.meshes.single;
    final AiNativeMeshVertex vertex = mesh.vertices.singleWhere((vertex) => vertex.firstIndex == 1 && vertex.secondIndex == 0);
    final AiNativeMeshes changed = source.editGeometry(
      mesh: mesh,
      bounds: meshGeometryBounds,
      changes: [
        for (final AiNativeMeshNode corner in vertex.corners) AiNativeMeshNodeGeometry(node: corner, position: (x: 12, y: -3)),
      ],
    );
    final AiNativeMesh updated = changed.meshes.single;
    final AiNativeMeshVertex moved = updated.vertices.singleWhere((vertex) => vertex.firstIndex == 1 && vertex.secondIndex == 0);
    check(moved.corners.map((corner) => corner.position)).deepEquals([(x: 12.0, y: -3.0), (x: 12.0, y: -3.0)]);
    check(moved.corners.first.color).deepEquals(vertex.corners.first.color);
    check(moved.corners.first.firstHandle).equals(vertex.corners.first.firstHandle);
    check(changed.records.program.bytes.sublist(0, updated.start)).deepEquals(source.records.program.bytes.sublist(0, mesh.start));
    check(changed.records.program.bytes.sublist(updated.end)).deepEquals(source.records.program.bytes.sublist(mesh.end));
  });

  test('rejects a partial shared-position update without mutating the original', () {
    final AiNativeMeshes source = meshGeometrySource();
    final AiNativeMesh mesh = source.meshes.single;
    final AiNativeMeshVertex vertex = mesh.vertices.firstWhere((vertex) => vertex.corners.length == 2);
    final List<int> original = List.of(source.records.program.bytes);
    check(
      () => source.editGeometry(
        mesh: mesh,
        bounds: meshGeometryBounds,
        changes: [AiNativeMeshNodeGeometry(node: vertex.corners.first, position: (x: 42, y: 24))],
      ),
    ).throws<FormatException>();
    check(source.records.program.bytes).deepEquals(original);
  });

  test('edits source-order handles and weights without moving their vertex', () {
    final AiNativeMeshes source = meshGeometrySource();
    final AiNativeMesh mesh = source.meshes.single;
    final AiNativeMeshNode corner = mesh.vertices.first.corners.single;
    final AiNativeMeshes changed = source.editGeometry(
      mesh: mesh,
      bounds: meshGeometryBounds,
      changes: [
        AiNativeMeshNodeGeometry(node: corner, firstHandle: (x: 4, y: 2), secondHandle: (x: -2, y: 5), weights: [.5, 1.25]),
      ],
    );
    final AiNativeMeshNode node = changed.meshes.single.vertices.first.corners.single;
    check(node.position).equals(corner.position);
    check(node.firstHandle).equals((x: 4.0, y: 2.0));
    check(node.secondHandle).equals((x: -2.0, y: 5.0));
    check(node.weights).deepEquals([.5, 1.25]);
    check(node.opacity).equals(.8);
  });

  test('edits an intermediate node using its distinct seven-value layout', () {
    final AiNativeMeshes source = meshGeometrySource();
    final AiNativeMesh mesh = source.meshes.single;
    final AiNativeMeshNode anchor = mesh.patches.first.nodes.first;
    final AiNativeMeshes changed = source.editGeometry(
      mesh: mesh,
      bounds: meshGeometryBounds,
      changes: [
        AiNativeMeshNodeGeometry(node: anchor, position: (x: -2, y: 5), firstHandle: (x: -1, y: 4), secondHandle: (x: -3, y: 6), weights: [.25]),
      ],
    );
    final AiNativeMeshNode node = changed.meshes.single.patches.first.nodes.first;
    check(node.kind).equals(AiNativeMeshNodeKind.anchor);
    check(node.position).equals((x: -2.0, y: 5.0));
    check(node.secondHandle).equals((x: -3.0, y: 6.0));
    check(node.weights).deepEquals([.25]);
    check(node.color).isEmpty();
  });

  test('transforms every corner and intermediate node while retaining named inks', () {
    final AiNativeMeshes source = meshGeometrySource(packet: meshGeometryPacket(ink: true));
    final AiNativeMesh mesh = source.meshes.single;
    final AiNativeAffineTransform transform = AiNativeAffineTransform(a: -2, c: .5, d: 3, tx: 5, ty: -7);
    final AiNativeMeshes changed = source.transform(mesh: mesh, transform: transform, bounds: meshGeometryBounds);
    final List<AiNativeMeshNode> before = mesh.patches.expand((patch) => patch.nodes).toList();
    final List<AiNativeMeshNode> after = changed.meshes.single.patches.expand((patch) => patch.nodes).toList();
    for (final (int index, AiNativeMeshNode node) in after.indexed) {
      final AiNativeMeshNode old = before[index];
      final List<double> expected = transform.point(x: old.position.x, y: old.position.y);
      check(node.position).equals((x: expected[0], y: expected[1]));
      check(node.weights).deepEquals(old.weights);
      check(node.color).deepEquals(old.color);
      expect(node.colorSpace?.inks.first.nameBytes, old.colorSpace?.inks.first.nameBytes);
    }
    check(changed.meshes.single.vertices.length).equals(mesh.vertices.length);
  });

  test('replaces dimensions and cells while retaining external identity bytes', () {
    final String packet = '${meshGeometryPacket()}\n%_/ArtDictionary :\n%_/XMLUID : (mesh-id) ; (AI10_ArtUID) ,\n%_;';
    final AiNativeMeshes source = meshGeometrySource(packet: packet);
    final AiNativeMesh original = source.meshes.single;
    final AiNativeMeshes changed = source.replaceTopology(mesh: original, definition: meshReplacementGrid(), bounds: meshGeometryBounds);
    final AiNativeMesh result = changed.meshes.single;
    check(result.size).equals((first: 1, second: 2));
    check(result.vertices.length).equals(6);
    check(result.patches.map((patch) => (patch.firstIndex, patch.secondIndex))).deepEquals([(0, 0), (0, 1)]);
    check(result.vertices.last.position).equals((x: 10.0, y: 20.0));
    check(result.vertices.last.corners.single.opacity).equals(.3);
    check(changed.records.program.bytes.sublist(result.end)).deepEquals(source.records.program.bytes.sublist(original.end));
  });

  test('retains intermediate nodes, weights and exact named spaces in supplied topology', () {
    final AiNativeMeshes source = meshGeometrySource(packet: meshGeometryPacket(ink: true));
    final AiNativeMesh mesh = source.meshes.single;
    final AiNativeMeshDefinition definition = AiNativeMeshDefinition.fromSource(mesh: mesh);
    final AiNativeMeshes changed = source.replaceTopology(mesh: mesh, definition: definition, bounds: meshGeometryBounds);
    final List<AiNativeMeshNode> nodes = changed.meshes.single.patches.expand((patch) => patch.nodes).toList();
    final List<AiNativeMeshNode> originals = mesh.patches.expand((patch) => patch.nodes).toList();
    for (final (int index, AiNativeMeshNode node) in nodes.indexed) {
      check(node.kind).equals(originals[index].kind);
      check(node.position).equals(originals[index].position);
      check(node.firstHandle).equals(originals[index].firstHandle);
      check(node.weights).deepEquals(originals[index].weights);
      check(node.inkTints.map((ink) => (latin1.decode(ink.ink.nameBytes), ink.tint))).deepEquals(originals[index].inkTints.map((ink) => (latin1.decode(ink.ink.nameBytes), ink.tint)));
    }
    check(definition.patches.clear).throws<UnsupportedError>();
    check(definition.patches.first.nodes.clear).throws<UnsupportedError>();
  });

  test('retains exact no-op snapshots and rejects stale or duplicate geometry handles', () {
    final AiNativeMeshes source = meshGeometrySource();
    final AiNativeMesh mesh = source.meshes.single;
    final AiNativeMeshNode node = mesh.vertices.first.corners.single;
    check(source.editGeometry(mesh: mesh, bounds: meshGeometryBounds, changes: [])).identicalTo(source);
    check(
      source.editGeometry(
        mesh: mesh,
        bounds: meshGeometryBounds,
        changes: [AiNativeMeshNodeGeometry(node: node, position: node.position)],
      ),
    ).identicalTo(source);
    final AiNativeMeshNodeGeometry edit = AiNativeMeshNodeGeometry(node: node, firstHandle: (x: 4, y: 4));
    check(() => source.editGeometry(mesh: mesh, bounds: meshGeometryBounds, changes: [edit, edit])).throws<ArgumentError>();
    final AiNativeMeshes changed = source.editGeometry(mesh: mesh, bounds: meshGeometryBounds, changes: [edit]);
    check(() => changed.editGeometry(mesh: mesh, bounds: meshGeometryBounds, changes: [edit])).throws<ArgumentError>();
  });

  test('rejects incomplete and inconsistent replacement grids before serialization', () {
    final AiNativeMeshDefinition source = meshReplacementGrid();
    check(() => AiNativeMeshDefinition(firstSize: 9007199254740991, secondSize: 9007199254740991, patches: source.patches)).throws<ArgumentError>();
    check(() => AiNativeMeshDefinition(firstSize: 1, secondSize: 2, patches: [source.patches.first, source.patches.first])).throws<ArgumentError>();
    final AiNativeMeshPatchDefinition last = source.patches.last;
    check(
      () => AiNativeMeshDefinition(
        firstSize: 1,
        secondSize: 2,
        patches: [
          source.patches.first,
          AiNativeMeshPatchDefinition(
            firstIndex: 0,
            secondIndex: 1,
            nativeParameters: [-1],
            nodes: [
              last.nodes.first.withGeometry(position: (x: 99, y: 10)),
              ...last.nodes.skip(1),
            ],
          ),
        ],
      ),
    ).throws<ArgumentError>();
  });

  test('rejects unknown source dependencies and unowned patch parameters', () {
    final AiNativeMeshes source = meshGeometrySource(packet: meshGeometryPacket().replaceFirst('%_/Data X#', '%_/Data X#\n%_[42] /Future X#'));
    check(() => source.replaceTopology(mesh: source.meshes.single, definition: meshReplacementGrid(), bounds: meshGeometryBounds)).throws<UnsupportedError>();
    final AiNativeMeshes unowned = meshGeometrySource(packet: meshGeometryPacket().replaceFirst('%_/Data X#', '%_/Data X#\n%_[42] /R X#'));
    check(() => AiNativeMeshDefinition.fromSource(mesh: unowned.meshes.single)).throws<UnsupportedError>();
  });
}
