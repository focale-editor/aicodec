part of 'package:aikit/src/model/ai_native_records.dart';

/// Changes vertex paint atomically without leaving stale neighboring corners.
AiNativeMeshes _paintMeshVertices(AiNativeMeshes source, AiNativeMesh mesh, List<AiNativeMeshVertexPaint> changes) {
  if (!source.meshes.contains(mesh)) {
    throw ArgumentError('The mesh belongs to another native snapshot.');
  }
  final Set<AiNativeMeshVertex> owned = mesh.vertices.toSet();
  final Set<AiNativeMeshVertex> selected = {};
  for (final AiNativeMeshVertexPaint change in changes) {
    if (!owned.contains(change.vertex) || !selected.add(change.vertex)) {
      throw ArgumentError('Mesh paint requires unique vertices from the selected mesh.');
    }
  }
  if (changes.isEmpty) {
    return source;
  }
  _validateMeshPaintOwner(source.records, mesh);
  final List<AiSourceEdit> edits = [];
  int available = source.records.program.limits.maxDecodedBytes - source.records.program.bytes.length;
  final Map<AiNativeMeshField, int> indices = {for (final (int, AiNativeMeshField) item in mesh.fields.indexed) item.$2: item.$1};

  /// Reserves the aggregate output growth before retaining a replacement.
  void replace(int start, int end, List<int> bytes) {
    available -= bytes.length - (end - start);
    if (available < 0) {
      throw const FormatException('Mesh paint exceeds the native output limit.');
    }
    edits.add(AiSourceEdit(start: start, end: end, bytes: bytes));
  }

  for (final AiNativeMeshVertexPaint change in changes) {
    for (final AiNativeMeshNode corner in change.vertex.corners) {
      final List<AiToken> values = corner.field.values;
      if (change.opacity case final double opacity when opacity != corner.opacity) {
        final AiToken previous = values[corner.color.length + 1];
        replace(previous.start, previous.end, latin1.encode(opacity.toString()));
      }
      final AiNativeMeshProcessColor? color = change.color;
      if (color == null) {
        continue;
      }
      final AiNativeMeshColorSpace space = corner.colorSpace!;
      if (space.componentCount == null) {
        throw UnsupportedError('Replacing mesh color requires a qualified source color-space declaration.');
      }
      if (space.deviceName != color.space.nativeName) {
        final int index = indices[corner.field]!;
        final AiNativeMeshField? previous = index > 0 ? mesh.fields[index - 1] : null;
        final AiNativeMeshField? following = index + 1 < mesh.fields.length ? mesh.fields[index + 1] : null;
        if (previous == space.field && following?.key == 'CS') {
          // A declaration bounded by the next CS belongs only to this corner.
          // Reuse it on subsequent edits instead of accumulating switch pairs.
          replace(previous!.values.first.start, previous.values.last.end, latin1.encode('/${color.space.nativeName}'));
        } else {
          final String prefix = corner.field.instruction.isPrivate ? '%_' : '';
          replace(corner.field.start, corner.field.start, latin1.encode('/${color.space.nativeName} /CS X#\n$prefix'));
          final _GradientResourceWriter writer = _GradientResourceWriter(limit: available);
          writer.add('\n$prefix');
          final List<AiToken>? original = space.field?.values;
          if (original == null) {
            writer.add('/DeviceGray');
          } else {
            for (final AiToken token in original) {
              if (const {AiTokenKind.string, AiTokenKind.hexString}.contains(token.kind)) {
                writer.string(aiStringBytes(token));
              } else {
                writer.add(token.lexeme);
              }
              writer.add(' ');
            }
          }
          writer.add(' /CS X#');
          replace(corner.field.end, corner.field.end, writer.output.takeBytes());
        }
      }
      if (corner.color.length != color.components.length || corner.color.indexed.any((item) => item.$2 != color.components[item.$1])) {
        replace(values[1].start, values[corner.color.length].end, latin1.encode(color.components.join(' ')));
      }
    }
  }
  if (edits.isEmpty) {
    return source;
  }
  return AiNativeMeshes.decode(
    records: AiNativeRecords.decode(
      program: AiNativeEditor.apply(program: source.records.program, edits: edits),
    ),
    bodyOnly: source.bodyOnly,
  );
}

/// Rejects unqualified native copies, extensions and dependent appearance data.
void _validateMeshPaintOwner(AiNativeRecords records, AiNativeMesh mesh) {
  if (mesh.isPrivate || mesh.start < records.program.bodyStart || mesh.end > records.program.bodyEnd || records.containers.any((record) => record.start < mesh.start && record.end > mesh.end)) {
    throw UnsupportedError('Mesh paint editing requires direct printable body artwork.');
  }
  if (mesh.fields.any((field) => !const {'Version', 'Type', 'Size', 'Data', 'P', 'R', 'CS', 'N', 'A', 'S', 'E'}.contains(field.key))) {
    throw UnsupportedError('Mesh paint cannot synchronize unknown native fields.');
  }
  final AiNativeDrawing drawing = AiNativeDrawing.decode(records: records);
  if (drawing.items.any((item) => item is AiNativeVersionComment)) {
    throw UnsupportedError('Mesh paint requires resolved version-dependent artwork.');
  }

  /// Checks the immediately attached dictionary and style binding.
  void following(int end, {bool parent = false}) {
    final List<AiNativeItem> items = drawing.items.where((item) => item.start >= end).take(3).toList();
    int index = 0;
    if (items.firstOrNull case final AiNativeInstruction command when command.operator == 'N' && command.operands.isEmpty) {
      index++;
    }
    if (index < items.length && items[index] is AiNativeContainer) {
      final AiNativeContainer dictionary = items[index++] as AiNativeContainer;
      if (parent || dictionary.type != 'ArtDictionary' || dictionary.entries.any((entry) => !const {'BBAccumRotation', 'AI10_ArtUID', 'AIArtName', 'Object name'}.contains(entry.key))) {
        throw UnsupportedError('Mesh paint cannot synchronize dependent artwork metadata.');
      }
    }
    final AiNativeItem? next = index < items.length ? items[index] : null;
    if (next case final AiNativeInstruction command when command.operator == 'XW') {
      final List<AiToken> operands = command.operands;
      if (operands.length != 2 ||
          !const {AiTokenKind.string, AiTokenKind.hexString}.contains(operands.last.kind) ||
          aiStringBytes(operands.last).isNotEmpty ||
          operands.first.number != 6 && !(parent && operands.first.number == 9)) {
        throw UnsupportedError('Mesh paint requires an independently owned appearance.');
      }
    }
  }

  following(mesh.end);
  for (final AiNativeGroup group in drawing.groups.where((group) => group.start < mesh.start && group.end > mesh.end)) {
    following(group.end, parent: true);
  }
}
