part of 'package:illustratorkit/src/model/ai_native_records.dart';

/// Edits numeric geometry tokens while retaining colors and opaque byte layout.
AiNativeMeshes _editMeshGeometry(AiNativeMeshes source, AiNativeMesh mesh, List<AiNativeMeshNodeGeometry> changes, AiBoundingBox bounds, {List<AiSourceEdit> auxiliary = const []}) {
  if (!source.meshes.contains(mesh)) {
    throw ArgumentError('Mesh geometry requires a current source handle.');
  }
  _nativeTopologyBounds(bounds);
  final Set<AiNativeMeshNode> owned = {for (final AiNativeMeshPatch patch in mesh.patches) ...patch.nodes};
  final Set<AiNativeMeshNode> selected = {};
  for (final AiNativeMeshNodeGeometry change in changes) {
    if (!owned.contains(change.node) || !selected.add(change.node)) {
      throw ArgumentError('Mesh geometry changes require distinct owned node occurrences.');
    }
  }
  if (changes.isEmpty && auxiliary.isEmpty) {
    return source;
  }
  _validateMeshPaintOwner(source.records, mesh);
  // Reading vertices validates shared patch boundaries before mutation.
  // ignore: unnecessary_statements
  mesh.vertices;
  final List<AiSourceEdit> edits = [...auxiliary];
  int available = source.records.program.limits.maxDecodedBytes - source.records.program.bytes.length - auxiliary.fold<int>(0, (count, edit) => count + edit.bytes.length - (edit.end - edit.start));

  /// Changes a single numeric token only when its original value differs.
  void replace(AiToken token, double value) {
    if (token.number == value) {
      return;
    }
    final List<int> bytes = latin1.encode(value.toString());
    available -= bytes.length - (token.end - token.start);
    if (available < 0) {
      throw const AiLimitException(message: 'Mesh geometry exceeds the native output limit.');
    }
    edits.add(AiSourceEdit(start: token.start, end: token.end, bytes: bytes));
  }

  for (final AiNativeMeshNodeGeometry change in changes) {
    final AiNativeMeshNode node = change.node;
    final bool corner = node.kind == .corner;
    final int offset = 1 + (corner ? node.color.length + 1 : 0);
    final List<AiToken> tokens = node.field.values;
    if (change.position case final ({double x, double y}) point) {
      replace(tokens[offset], point.x);
      replace(tokens[offset + 1], point.y);
    }
    if (change.firstHandle case final ({double x, double y}) point) {
      replace(tokens[offset + 2], point.x);
      replace(tokens[offset + 3], point.y);
    }
    if (change.secondHandle case final ({double x, double y}) point) {
      replace(tokens[offset + (corner ? 5 : 4)], point.x);
      replace(tokens[offset + (corner ? 6 : 5)], point.y);
    }
    if (change.weights case final List<double> weights) {
      replace(tokens[offset + (corner ? 4 : 6)], weights.first);
      if (corner) {
        replace(tokens[offset + 7], weights.last);
      }
    }
  }
  if (edits.isEmpty) {
    return source;
  }
  return _meshGeometryResult(source, mesh, edits, bounds);
}

/// Applies one affine basis to every position and handle, preserving native paint.
AiNativeMeshes _transformNativeMesh(AiNativeMeshes source, AiNativeMesh mesh, AiNativeAffineTransform transform, AiBoundingBox bounds, double? rotationRadians) {
  if (!source.meshes.contains(mesh)) {
    throw ArgumentError('Mesh transforms require a current source handle.');
  }
  _nativeTopologyBounds(bounds);
  if (transform.isIdentity && rotationRadians == null) {
    return source;
  }
  final List<AiSourceEdit> frame = _meshFrameRotationEdits(source.records, mesh, rotationRadians);
  final _NativeAffinePoints points = _NativeAffinePoints(transform: transform);

  /// Keeps shared coordinates exact and rejects newly collapsed distinct points.
  ({double x, double y}) mapped(({double x, double y}) point) {
    final List<double> values = points.point(point.x, point.y);
    return (x: values[0], y: values[1]);
  }

  return _editMeshGeometry(
    source,
    mesh,
    [
      for (final AiNativeMeshPatch patch in mesh.patches)
        for (final AiNativeMeshNode node in patch.nodes)
          AiNativeMeshNodeGeometry(node: node, position: mapped(node.position), firstHandle: mapped(node.firstHandle), secondHandle: mapped(node.secondHandle)),
    ],
    bounds,
    auxiliary: frame,
  );
}

/// Resolves optional framing metadata without treating unrelated records as owned.
AiNativeContainer? _meshMetadata(AiNativeDrawing drawing, AiNativeMesh mesh) {
  int index = _pathOffset(drawing.items, mesh.end, (item) => item.start);
  if (index < drawing.items.length) {
    if (drawing.items[index] case final AiNativeInstruction command when command.operator == 'N' && command.operands.isEmpty) {
      index++;
    }
  }
  final AiNativeItem? next = index < drawing.items.length ? drawing.items[index] : null;
  return next is AiNativeContainer && next.type == 'ArtDictionary' ? next : null;
}

/// Requires an explicit host frame angle when geometry changes an existing frame.
List<AiSourceEdit> _meshFrameRotationEdits(AiNativeRecords records, AiNativeMesh mesh, double? rotationRadians) {
  if (rotationRadians != null && (!rotationRadians.isFinite || rotationRadians.abs() > 2 * pi)) {
    throw ArgumentError('Native mesh frame angles must lie in -2π..2π.');
  }
  final AiNativeDrawing drawing = AiNativeDrawing.decode(records: records);
  _validateMeshPaintOwner(records, mesh, drawing: drawing);
  return _nativeFrameRotationEdits(records, _meshMetadata(drawing, mesh), mesh.end, rotationRadians);
}

/// Replaces all explicit cells without deriving new handles, colors or parameters.
AiNativeMeshes _replaceMeshTopology(AiNativeMeshes source, AiNativeMesh mesh, AiNativeMeshDefinition definition, AiBoundingBox bounds, double? rotationRadians) {
  if (!source.meshes.contains(mesh)) {
    throw ArgumentError('Mesh topology replacement requires a current source handle.');
  }
  _nativeTopologyBounds(bounds);
  _validateMeshPaintOwner(source.records, mesh);
  // Reading vertices validates shared patch boundaries before mutation.
  // ignore: unnecessary_statements
  mesh.vertices;
  // R is explicit numeric source data. References or duplicate declarations
  // cannot be dropped merely because a caller supplies a replacement grid.
  _validateMeshTopologyFields(mesh);
  for (final AiNativeMeshPatch patch in mesh.patches) {
    final List<AiNativeMeshField> parameters = patch.fields.where((field) => field.key == 'R').toList();
    if (parameters.length > 1) {
      throw UnsupportedError('Mesh topology has repeated native patch parameters.');
    }
    if (parameters.isNotEmpty) {
      _meshNumbers(parameters.single);
    }
  }
  final int limit = source.records.program.limits.maxDecodedBytes - source.records.program.bytes.length + mesh.end - mesh.start;
  final Uint8List bytes = _nativeMeshDefinitionBytes(definition, limit);
  return _meshGeometryResult(
    source,
    mesh,
    [AiSourceEdit(start: mesh.start, end: mesh.end, bytes: bytes), ..._meshFrameRotationEdits(source.records, mesh, rotationRadians)],
    bounds,
    expectedSize: (first: definition.firstSize, second: definition.secondSize),
  );
}

/// Writes only explicit native data, with bounded output and literal ink names.
Uint8List _nativeMeshDefinitionBytes(AiNativeMeshDefinition definition, int limit) {
  final _GradientResourceWriter writer = _GradientResourceWriter(limit: limit);
  writer.add('/Mesh X!\n%_2 /Version X#\n%_/Cartesian /Type X#\n%_[${definition.firstSize} ${definition.secondSize}] /Size X#\n%_/Data X#\n');
  for (final AiNativeMeshPatchDefinition patch in definition.patches) {
    writer.add('%_[${patch.firstIndex} ${patch.secondIndex}] /P X#\n');
    if (patch.nativeParameters case final List<double> parameters) {
      writer.add('%_[${parameters.join(' ')}] /R X#\n');
    }
    for (final AiNativeMeshNodeDefinition node in patch.nodes) {
      final bool corner = node.kind == .corner;
      if (corner) {
        writer.add('%_');
        if (node.processColor case final AiNativeMeshProcessColor color) {
          writer.add('/${color.space.nativeName}');
        } else if (node.retainedColorSpace!.field case final AiNativeMeshField declaration) {
          for (final AiToken token in declaration.values) {
            if (const {AiTokenKind.string, AiTokenKind.hexString}.contains(token.kind)) {
              writer.string(aiStringBytes(token));
            } else {
              writer.add(token.lexeme);
            }
            writer.add(' ');
          }
        } else {
          writer.add('/DeviceGray');
        }
        writer.add(' /CS X#\n');
      }
      final List<double> values = [
        if (corner) ...[...node.processColor?.components ?? node.retainedComponents!, node.opacity!],
        node.position.x,
        node.position.y,
        node.firstHandle.x,
        node.firstHandle.y,
        if (corner) node.weights.first,
        node.secondHandle.x,
        node.secondHandle.y,
        node.weights.last,
      ];
      final String key = switch (node.kind) {
        .corner => 'N',
        .anchor => 'A',
        .subdivision => 'S',
      };
      writer.add('%_[${values.join(' ')}] /$key X#\n');
    }
    writer.add('%_/E X#\n');
  }
  writer.add('/End X!');
  return writer.output.takeBytes();
}

/// Reopens before returning, enforcing inventory and shared-vertex consistency.
AiNativeMeshes _meshGeometryResult(AiNativeMeshes source, AiNativeMesh mesh, List<AiSourceEdit> edits, AiBoundingBox bounds, {({int first, int second})? expectedSize}) {
  final int index = source.meshes.indexOf(mesh);
  final AiNativeMeshes result = AiNativeMeshes.decode(
    records: AiNativeRecords.decode(
      program: AiNativeEditor.apply(
        program: source.records.program,
        edits: [
          ...edits,
          ...AiNativeEditor.includeBoundsEdits(program: source.records.program, bounds: bounds),
        ],
      ),
    ),
    bodyOnly: source.bodyOnly,
  );
  if (result.meshes.length != source.meshes.length || result.meshes[index].size != (expectedSize ?? mesh.size)) {
    throw const FormatException('Mesh transaction changed unexpected source ownership or dimensions.');
  }
  // Reading vertices validates shared patch boundaries after mutation.
  // ignore: unnecessary_statements
  result.meshes[index].vertices;
  return result;
}
