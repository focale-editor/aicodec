part of 'package:aicodec/src/model/ai_native_records.dart';

/// Finds explicit mesh packets without interpreting other drawing commands.
List<AiNativeMesh> _readNativeMeshes(AiNativeRecords records, bool bodyOnly) {
  final _NativeRecordProjection projection = records._projection;
  final List<AiToken> tokens = projection.tokens;
  final List<AiNativeMesh> meshes = [];
  int literals = 0;
  int embedded = 0;
  bool pendingOperand = false;
  for (int index = 0; index < tokens.length; index++) {
    final AiToken token = tokens[index];
    if (bodyOnly && (token.start < records.program.bodyStart || token.start >= records.program.bodyEnd)) {
      continue;
    }
    if (token.kind == .comment) {
      if (literals == 0 && embedded == 0 && token.lexeme.startsWith('%AI5_BeginGradient:')) {
        // Gradient ramps use `[` as an executable mark, consumed by BD/Bs.
        // Skip their explicit resource envelope rather than counting arrays.
        int procedures = 0;
        bool ended = false;
        for (index++; index < tokens.length; index++) {
          final AiToken next = tokens[index];
          if (next.kind == .procedureStart) {
            procedures++;
          } else if (next.kind == .procedureEnd) {
            procedures--;
          }
          if (procedures == 0 && next.kind == .comment && next.lexeme == '%AI5_EndGradient') {
            ended = true;
            break;
          }
          if (next.start >= records.program.bodyStart || next.kind == .comment && next.lexeme.startsWith('%AI5_BeginGradient:')) {
            throw const FormatException('Unterminated gradient resource before native mesh inspection.');
          }
        }
        if (!ended) {
          throw const FormatException('Unterminated gradient resource before native mesh inspection.');
        }
        pendingOperand = false;
        continue;
      }
      if (literals == 0 && token.lexeme.startsWith('%%BeginDocument')) {
        embedded++;
      } else if (literals == 0 && token.lexeme == '%%EndDocument') {
        embedded--;
      }
      continue;
    }
    if (embedded != 0) {
      continue;
    }
    if (const {AiTokenKind.procedureStart, AiTokenKind.arrayStart, AiTokenKind.dictionaryStart}.contains(token.kind)) {
      literals++;
    } else if (const {AiTokenKind.procedureEnd, AiTokenKind.arrayEnd, AiTokenKind.dictionaryEnd}.contains(token.kind)) {
      literals--;
    }
    if (literals != 0) {
      continue;
    }
    final bool opening = !pendingOperand && token.kind == .literalName && token.lexeme == '/Mesh';
    pendingOperand = token.kind != .executableName && token.kind != .data;
    if (!opening) {
      continue;
    }
    int next = index + 1;
    while (next < tokens.length && tokens[next].kind == .comment && !tokens[next].lexeme.startsWith('%%')) {
      next++;
    }
    if (next >= tokens.length || tokens[next].kind != .executableName || tokens[next].lexeme != 'X!') {
      continue;
    }
    final bool private = projection.isPrivate(token.start);
    if (private != projection.isPrivate(tokens[next].start)) {
      throw const FormatException('Native mesh opening mixes representations.');
    }
    final _NativeCommandReader reader = _NativeCommandReader(maxDepth: records.program.limits.maxDepth);
    final List<AiNativeMeshField> fields = [];
    bool closed = false;
    for (index = next + 1; index < tokens.length; index++) {
      final AiToken current = tokens[index];
      if (bodyOnly && current.end > records.program.bodyEnd || current.kind == .data || current.kind == .comment && current.lexeme.startsWith('%%')) {
        throw const FormatException('Native mesh crosses a source boundary.');
      }
      final AiNativeInstruction? command = reader.add(current, isPrivate: projection.isPrivate(current.start));
      if (command == null) {
        continue;
      }
      if (command.operator == 'X!' && command.operands.length == 1 && command.operands.single.lexeme == '/End' && command.operands.single.kind == .literalName) {
        if (command.isPrivate != private) {
          throw const FormatException('Native mesh closing disagrees with its opening.');
        }
        meshes.add(_meshFromFields(start: token.start, end: command.end, private: private, fields: fields));
        closed = true;
        pendingOperand = false;
        break;
      }
      if (command.operator != 'X#' || command.operands.isEmpty || command.operands.last.kind != .literalName) {
        throw const FormatException('Invalid native mesh field or nested mesh.');
      }
      fields.add(AiNativeMeshField._(instruction: command));
    }
    if (!closed) {
      throw const FormatException('Unterminated native mesh.');
    }
  }
  return meshes;
}

/// Reads only a finite numeric array, preserving the complete original record.
List<double> _meshNumbers(AiNativeMeshField field) {
  final List<AiToken> values = field.values;
  if (values.length < 2 || values.first.kind != .arrayStart || values.last.kind != .arrayEnd || values.skip(1).take(values.length - 2).any((value) => value.number == null)) {
    throw const FormatException('Invalid native mesh numeric array.');
  }
  return values.skip(1).take(values.length - 2).map((value) => value.number!.toDouble()).toList();
}

/// Checks positive grid extents without allocating from an untrusted product.
int _meshInteger(double value, {bool positive = false}) {
  if (value < (positive ? 1 : 0) || value != value.truncateToDouble() || value > 9007199254740991) {
    throw const FormatException('Invalid native mesh grid index.');
  }
  return value.toInt();
}

/// Decodes a checked named ink with an explicit device-color alternative.
AiNativeMeshInk? _meshInk(List<AiToken> values) {
  if (values.length < 6 || values.first.kind != .arrayStart || values.last.kind != .arrayEnd || values[values.length - 2].lexeme != '/Separation') {
    return null;
  }
  final String name = values[values.length - 4].lexeme;
  final int? count = switch (name) {
    '/DeviceGray' => 1,
    '/DeviceRGB' => 3,
    '/DeviceCMYK' => 4,
    _ => null,
  };
  if (count == null) {
    return null;
  }
  final AiToken inkName = values[values.length - 3];
  if (values.length != count + 5 || !const {AiTokenKind.string, AiTokenKind.hexString}.contains(inkName.kind)) {
    throw const FormatException('Invalid native mesh ink declaration.');
  }
  final List<double> components = [];
  for (final AiToken value in values.skip(1).take(count)) {
    final double? component = value.number?.toDouble();
    if (component == null || !_gradientUnit(component)) {
      throw const FormatException('Invalid native mesh ink alternative.');
    }
    components.add(component);
  }
  return AiNativeMeshInk._(nameBytes: aiStringBytes(inkName), deviceName: name.substring(1), components: components);
}

/// Recognizes device and named-ink arities without converting source tints.
AiNativeMeshColorSpace _meshColorSpace(AiNativeMeshField field) {
  if (field.values.isEmpty) {
    throw const FormatException('Empty native mesh color space.');
  }
  final String? name = field.values.length == 1 && field.values.single.kind == .literalName ? field.values.single.lexeme.substring(1) : null;
  final int? count = switch (name) {
    'DeviceGray' => 1,
    'DeviceRGB' => 3,
    'DeviceCMYK' => 4,
    _ => null,
  };
  if (count != null) {
    return AiNativeMeshColorSpace._(field: field, deviceName: name, componentCount: count);
  }
  final List<AiToken> values = field.values;
  if (_meshInk(values) case final AiNativeMeshInk ink) {
    return AiNativeMeshColorSpace._(field: field, deviceName: null, componentCount: 1, inks: List.unmodifiable([ink]));
  }
  if (values.length >= 4 && values.first.kind == .arrayStart && values.last.kind == .arrayEnd && values[values.length - 2].lexeme == '/NChannel') {
    final num? declared = values[values.length - 3].number;
    if (declared == null || declared <= 0 || declared % 1 != 0 || declared > values.length) {
      throw const FormatException('Invalid native mesh ink count.');
    }
    final List<AiNativeMeshInk> inks = [];
    int position = 1;
    while (position < values.length - 3) {
      final int start = position;
      if (values[position].kind != .arrayStart) {
        throw const FormatException('Invalid native mesh ink list.');
      }
      int depth = 0;
      do {
        if (values[position].kind == .arrayStart) {
          depth++;
        } else if (values[position].kind == .arrayEnd) {
          depth--;
        }
        position++;
      } while (depth != 0 && position < values.length - 3);
      if (depth != 0) {
        throw const FormatException('Unterminated native mesh ink.');
      }
      final AiNativeMeshInk? ink = _meshInk(values.sublist(start, position));
      if (ink == null) {
        return AiNativeMeshColorSpace._(field: field, deviceName: null, componentCount: null);
      }
      inks.add(ink);
    }
    if (inks.length != declared) {
      throw const FormatException('Native mesh ink count disagrees with its declarations.');
    }
    return AiNativeMeshColorSpace._(field: field, deviceName: null, componentCount: inks.length, inks: List.unmodifiable(inks));
  }
  return AiNativeMeshColorSpace._(field: field, deviceName: null, componentCount: null);
}

/// Decodes version-two node tails without guessing named-ink color semantics.
AiNativeMeshNode _meshNode(AiNativeMeshField field, AiNativeMeshColorSpace space) {
  final List<double> values = _meshNumbers(field);
  final bool corner = field.key == 'N';
  final int components = corner ? values.length - 9 : 0;
  if (corner && (components < 1 || space.componentCount != null && components != space.componentCount) || !corner && values.length != 7) {
    throw const FormatException('Invalid native mesh node arity.');
  }
  final int geometry = corner ? components + 1 : 0;
  if (corner && (values[components] < 0 || values[components] > 1 || space.componentCount != null && values.take(components).any((value) => value < 0 || value > 1))) {
    throw const FormatException('Native mesh color or opacity is outside zero to one.');
  }
  return AiNativeMeshNode._(
    field: field,
    kind: corner
        ? .corner
        : field.key == 'A'
        ? .anchor
        : .subdivision,
    position: (x: values[geometry], y: values[geometry + 1]),
    firstHandle: (x: values[geometry + 2], y: values[geometry + 3]),
    secondHandle: (x: values[geometry + (corner ? 5 : 4)], y: values[geometry + (corner ? 6 : 5)]),
    weights: corner ? [values[geometry + 4], values[geometry + 7]] : [values[6]],
    color: values.take(components).toList(),
    opacity: corner ? values[components] : null,
    colorSpace: corner ? space : null,
  );
}

/// Checks declarations and patch structure while retaining all unknown fields.
AiNativeMesh _meshFromFields({required int start, required int end, required bool private, required List<AiNativeMeshField> fields}) {
  final Map<String, AiNativeMeshField> headers = {};
  final List<AiNativeMeshPatch> patches = [];
  final List<AiNativeMeshField> patchFields = [];
  final List<AiNativeMeshNode> nodes = [];
  final Set<(int, int)> positions = {};
  AiNativeMeshColorSpace space = const AiNativeMeshColorSpace._(field: null, deviceName: 'DeviceGray', componentCount: 1);
  ({int first, int second})? size;
  (int, int)? position;
  bool data = false;
  for (final AiNativeMeshField field in fields) {
    if (field.key == 'CS') {
      space = _meshColorSpace(field);
    }
    if (!data) {
      if (const {'P', 'R', 'N', 'A', 'S', 'E'}.contains(field.key)) {
        throw const FormatException('Native mesh patch precedes its data declaration.');
      }
      if (const {'Version', 'Type', 'Size', 'Data'}.contains(field.key) && headers.containsKey(field.key)) {
        throw const FormatException('Repeated native mesh declaration.');
      }
      headers[field.key] = field;
      if (field.key == 'Data') {
        if (field.values.isNotEmpty || !headers.keys.toSet().containsAll(['Version', 'Type', 'Size'])) {
          throw const FormatException('Incomplete native mesh declarations.');
        }
        final List<AiToken> version = headers['Version']!.values;
        final List<AiToken> type = headers['Type']!.values;
        if (version.length != 1 || version.single.number != 2 || type.length != 1 || type.single.kind != .literalName || type.single.lexeme != '/Cartesian') {
          throw UnsupportedError('Native mesh inspection requires version-two Cartesian data.');
        }
        final List<double> dimensions = _meshNumbers(headers['Size']!);
        if (dimensions.length != 2) {
          throw const FormatException('Invalid native mesh grid size.');
        }
        size = (first: _meshInteger(dimensions[0], positive: true), second: _meshInteger(dimensions[1], positive: true));
        // Every patch requires at least P, four N records and E. Division
        // avoids both integer overflow and any allocation from the size header.
        if (size.first > fields.length ~/ 6 ~/ size.second) {
          throw const FormatException('Native mesh size exceeds available patch records.');
        }
        data = true;
      }
      continue;
    }
    if (field.key == 'P') {
      if (position != null) {
        throw const FormatException('Nested native mesh patch.');
      }
      final List<double> indices = _meshNumbers(field);
      if (indices.length != 2) {
        throw const FormatException('Invalid native mesh patch position.');
      }
      position = (_meshInteger(indices[0]), _meshInteger(indices[1]));
      if (position.$1 >= size!.first || position.$2 >= size.second || !positions.add(position)) {
        throw const FormatException('Duplicate or out-of-range native mesh patch.');
      }
    }
    if (position != null) {
      patchFields.add(field);
    }
    if (const {'N', 'A', 'S'}.contains(field.key)) {
      if (position == null) {
        throw const FormatException('Native mesh node is outside a patch.');
      }
      nodes.add(_meshNode(field, space));
    } else if (field.key == 'E') {
      if (position == null || field.values.isNotEmpty || nodes.where((node) => node.kind == .corner).length != 4) {
        throw const FormatException('Invalid native mesh patch ending or corner count.');
      }
      patches.add(AiNativeMeshPatch._(firstIndex: position.$1, secondIndex: position.$2, nodes: nodes, fields: patchFields));
      position = null;
      nodes.clear();
      patchFields.clear();
    } else if (const {'Version', 'Type', 'Size', 'Data'}.contains(field.key)) {
      throw const FormatException('Native mesh declaration follows its data.');
    }
  }
  if (!data || position != null || size == null || patches.length ~/ size.second != size.first || patches.length % size.second != 0) {
    throw const FormatException('Incomplete native mesh patch grid.');
  }
  return AiNativeMesh._(start: start, end: end, version: 2, size: size, isPrivate: private, fields: fields, patches: patches);
}

/// Indexes shared corners by Cartesian topology, never by coordinate proximity.
List<AiNativeMeshVertex> _meshVertices(AiNativeMesh mesh) {
  final Map<(int, int), List<AiNativeMeshNode>> corners = {};
  for (final AiNativeMeshPatch patch in mesh.patches) {
    final int first = patch.firstIndex;
    final int second = patch.secondIndex;
    final List<(int, int)> positions = [(first, second), (first + 1, second), (first + 1, second + 1), (first, second + 1)];
    for (final (int, AiNativeMeshNode) item in patch.nodes.where((node) => node.kind == .corner).indexed) {
      final (int, int) position = positions[item.$1];
      corners.putIfAbsent(position, () => []).add(item.$2);
    }
  }
  final List<AiNativeMeshVertex> vertices = [];
  for (final MapEntry<(int, int), List<AiNativeMeshNode>> entry in corners.entries) {
    if (entry.value.any((node) => node.position != entry.value.first.position)) {
      throw const FormatException('Adjacent native mesh corners disagree on their position.');
    }
    vertices.add(AiNativeMeshVertex._(firstIndex: entry.key.$1, secondIndex: entry.key.$2, corners: entry.value));
  }
  vertices.sort((first, second) => first.firstIndex != second.firstIndex ? first.firstIndex.compareTo(second.firstIndex) : first.secondIndex.compareTo(second.secondIndex));
  return List.unmodifiable(vertices);
}
