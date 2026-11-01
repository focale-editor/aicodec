part of 'package:aikit/src/model/ai_native_records.dart';

/// Accumulates lexical ownership before publishing immutable nodes.
final class _NativeStructureBuilder {
  /// Native handle retained for identity-based lookup.
  final Object source;

  /// Structural interpretation of the handle.
  final AiNativeStructureKind kind;

  /// Inclusive source boundary.
  final int start;

  /// Exclusive source boundary.
  final int end;

  /// Immediate lexical parent, assigned by the interval sweep.
  int? parent;

  /// Direct children accumulated in source order.
  final List<int> children = [];

  /// Saved version branch memberships inherited from the owner.
  List<AiNativeVersionMembership> versions = [];

  /// Captures a typed handle without assigning semantic parenthood by adjacency.
  _NativeStructureBuilder({required this.source, required this.kind, required this.start, required this.end});
}

/// Builds the source tree and then resolves separate semantic/reference edges.
AiNativeStructure _nativeStructure(AiNativeDrawing drawing) {
  final AiNativeRecords records = drawing.records;
  final AiNativeVersions versions = AiNativeVersions.decode(records: records);
  final AiNativeGradientResources gradients = AiNativeGradientResources.decode(records: records);
  final List<_NativeStructureBuilder> builders = [];

  /// Retains one item under the source's aggregate token budget.
  void add(Object source, AiNativeStructureKind kind, int start, int end) {
    if (builders.length >= records.program.limits.maxTokens) {
      throw const AiLimitException(message: 'Native structure nodes exceed the inspection limit.');
    }
    builders.add(_NativeStructureBuilder(source: source, kind: kind, start: start, end: end));
  }

  for (final AiNativeContainer record in records.containers) {
    add(record, .record, record.start, record.end);
  }
  for (final AiLayer layer in records.program.layers) {
    add(layer, .layer, layer.begin.start, layer.end.end);
  }
  for (final AiNativePath path in drawing.paths) {
    add(path, .path, path.start, path.end);
  }
  for (final AiNativeGroup group in drawing.groups) {
    add(
      group,
      group.compound
          ? .compound
          : group.opening.operator == 'q'
          ? .clip
          : .group,
      group.start,
      group.end,
    );
  }
  for (final AiNativeVersionBlock block in versions.blocks) {
    add(block, .version, block.start, block.end);
  }
  for (final AiNativeGradientDefinition definition in gradients.definitions) {
    add(definition, .gradientResource, definition.start, definition.end);
  }
  final Set<int> boundaries = {
    for (final AiLayer layer in records.program.layers) ...[layer.begin.token.start, layer.end.token.start],
    for (final AiNativeGroup group in drawing.groups) ...[group.opening.token.start, group.closing.token.start],
    for (final AiNativePath path in drawing.paths) ...[...path.geometry.map((item) => item.token.start), path.paint.token.start],
  };
  for (final AiNativeInstruction instruction in drawing.items.whereType<AiNativeInstruction>()) {
    if (!boundaries.contains(instruction.token.start)) {
      add(instruction, .instruction, instruction.start, instruction.end);
    }
  }
  builders.sort((a, b) => a.start != b.start ? a.start.compareTo(b.start) : b.end.compareTo(a.end));
  final List<int> stack = [];
  for (final (int, _NativeStructureBuilder) entry in builders.indexed) {
    final _NativeStructureBuilder node = entry.$2;
    while (stack.isNotEmpty && builders[stack.last].end <= node.start) {
      stack.removeLast();
    }
    if (stack.length >= records.program.limits.maxDepth) {
      throw const AiLimitException(message: 'Combined native ownership exceeds the nesting limit.');
    }
    if (stack.isNotEmpty) {
      final _NativeStructureBuilder parent = builders[stack.last];
      if (node.end > parent.end || node.start == parent.start && node.end == parent.end) {
        throw UnsupportedError('Native source owners overlap without unique containment at ${node.start}.');
      }
      node.parent = stack.last;
      parent.children.add(entry.$1);
      node.versions = parent.versions;
      if (parent.source case final AiNativeVersionBlock block) {
        final ({int start, int end}) newer = block.newerRange;
        final ({int start, int end})? older = block.olderRange;
        final AiNativeVersionBranch branch;
        if (node.start >= newer.start && node.end <= newer.end) {
          branch = .newer;
        } else if (older != null && node.start >= older.start && node.end <= older.end) {
          branch = .older;
        } else {
          throw UnsupportedError('A native owner crosses version branches at ${node.start}.');
        }
        node.versions = [...parent.versions, AiNativeVersionMembership._(block: block, branch: branch)];
      }
    }
    stack.add(entry.$1);
  }
  final List<AiNativeStructureNode> nodes = [
    for (final (int, _NativeStructureBuilder) entry in builders.indexed)
      AiNativeStructureNode._(
        index: entry.$1,
        kind: entry.$2.kind,
        source: entry.$2.source,
        start: entry.$2.start,
        end: entry.$2.end,
        parentIndex: entry.$2.parent,
        childIndices: entry.$2.children,
        versions: entry.$2.versions,
      ),
  ];
  final Map<Object, AiNativeStructureNode> sources = Map.identity()..addEntries(nodes.map((node) => MapEntry(node.source, node)));
  final List<AiNativeStructureEntry> entries = [
    for (final AiNativeContainer record in records.containers)
      for (final (int, AiNativeEntry) entry in record.entries.indexed) AiNativeStructureEntry._(entry: entry.$2, owner: sources[record]!, index: entry.$1),
  ];
  final int declarationCount = records.roots.where((record) => record.type == 'KnownStyle').length + gradients.definitions.length;
  if (declarationCount * (1 + versions.blocks.length) > records.program.limits.maxTokens) {
    throw const AiLimitException(message: 'Native resource declarations exceed the inspection limit.');
  }
  final List<AiNativeStructureResource> resources = [
    for (final AiNativeContainer record in records.roots.where((record) => record.type == 'KnownStyle'))
      if (record['Name']?.stringBytes case final Uint8List name)
        AiNativeStructureResource._(
          kind: .knownStyle,
          definition: sources[record]!,
          versions: _structureNameVersions(versions, record['Name']!),
          nameBytes: name,
        ),
    for (final AiNativeGradientDefinition definition in gradients.definitions)
      AiNativeStructureResource._(
        kind: .gradient,
        definition: sources[definition]!,
        versions: _structureReferenceVersions(versions, definition.opening.start, definition.opening.end),
        nameBytes: definition.nameBytes,
      ),
  ]..sort((a, b) => a.definition.start.compareTo(b.definition.start));
  final List<AiNativeResourceUse> uses = _nativeResourceUses(drawing, versions, nodes, resources);
  return AiNativeStructure._(
    drawing: drawing,
    versions: versions,
    nodes: nodes,
    entries: entries,
    identifiers: _nativeObjectIdentifiers(records, entries),
    resources: resources,
    resourceUses: uses,
    shapes: [
      for (final AiLiveShape shape in drawing.liveShapes)
        AiNativeShapeOwnership._(
          shape: shape,
          dictionary: sources[shape.dictionary]!,
          path: sources[shape.path],
          printingGroup: sources[shape.appearanceGroup],
          printingPaths: shape.appearancePaths.map((path) => sources[path]!).toList(),
          printingDictionary: sources[shape.appearanceDictionary],
          alternatives: shape.alternativeDictionaries.map((record) => sources[record]!).toList(),
        ),
    ],
  );
}

/// Reads qualified saved identifiers without merging equal values or owners.
List<AiNativeObjectIdentifier> _nativeObjectIdentifiers(AiNativeRecords records, List<AiNativeStructureEntry> entries) {
  final Set<AiNativeContainer> artboards = records.artboards.map((board) => board.record).toSet();
  final List<AiNativeObjectIdentifier> result = [];
  for (final AiNativeStructureEntry field in entries) {
    final AiNativeContainer owner = field.owner.source as AiNativeContainer;
    final AiNativeEntry entry = field.entry;
    if (artboards.contains(owner) && entry.key == 'ArtboardUUID') {
      result.add(AiNativeObjectIdentifier._(kind: .artboard, field: field, bytes: entry.stringBytes!));
    } else if (owner.type == 'ArtDictionary' && entry.key == 'AI10_ArtUID') {
      final AiNativeContainer? value = entry.container;
      if (value == null ||
          value.type != 'XMLUID' ||
          value.entries.length != 1 ||
          value.entries.single.key != null ||
          value.entries.single.items.length != 1 ||
          value.entries.single.stringBytes == null) {
        throw const FormatException('Invalid native XML artwork identifier.');
      }
      result.add(AiNativeObjectIdentifier._(kind: .xmlArt, field: field, bytes: value.entries.single.stringBytes!));
    }
  }
  return result;
}

/// Returns qualified commands from the drawing and explicitly native art/styles.
Iterable<AiNativeInstruction> _structureCommands(AiNativeDrawing drawing) sync* {
  yield* drawing.items.whereType<AiNativeInstruction>();
  yield* _structureSetupArtwork(drawing.records);
  for (final AiNativeContainer record in drawing.records.containers) {
    if (record.type == 'Art') {
      yield* AiNativeArt.decode(records: drawing.records, record: record).items.whereType<AiNativeInstruction>();
    } else if (const {'FillStyle', 'StrokeStyle', 'BlendStyle', 'SimpleStyle'}.contains(record.type)) {
      final AiNativeEntry? entry = record[record.type == 'SimpleStyle' ? 'Paint' : 'Def'];
      if (entry == null || entry.items.any((item) => item is! AiNativeToken)) {
        throw UnsupportedError('Native style commands have unresolved structural ownership.');
      }
      final _NativeCommandReader reader = _NativeCommandReader(maxDepth: drawing.records.program.limits.maxDepth);
      for (final AiNativeToken item in entry.items.cast<AiNativeToken>()) {
        final AiNativeInstruction? instruction = reader.add(item.token, isPrivate: drawing.records._projection.isPrivate(item.start));
        if (instruction != null) {
          yield instruction;
        }
      }
      reader.finish();
    }
  }
}

/// Reads declarative setup artwork without instantiating its resources.
Iterable<AiNativeInstruction> _structureSetupArtwork(AiNativeRecords records) sync* {
  final RegExp beginning = RegExp(r'^%AI\d+_Begin(Pattern|Symbol|BrushPattern)(?::|$)');
  final RegExp ending = RegExp(r'^%AI\d+_End(Pattern|Symbol|BrushPattern)$');
  final List<AiToken> operands = [];
  final List<String> sections = [];
  int rootIndex = 0;
  int embedded = 0;
  int procedures = 0;
  for (final AiToken token in records._projection.tokens) {
    if (token.start >= records.program.bodyStart) {
      break;
    }
    while (rootIndex < records.roots.length && records.roots[rootIndex].end <= token.start) {
      rootIndex++;
    }
    if (rootIndex < records.roots.length && token.start >= records.roots[rootIndex].start) {
      operands.clear();
      continue;
    }
    if (token.kind == .procedureStart) {
      procedures++;
      operands.clear();
    } else if (token.kind == .procedureEnd) {
      procedures--;
      continue;
    }
    if (token.kind == .comment) {
      if (procedures != 0) {
        continue;
      }
      if (token.lexeme.startsWith('%%BeginDocument')) {
        operands.clear();
        embedded++;
      } else if (token.lexeme == '%%EndDocument') {
        embedded--;
        continue;
      }
      if (embedded != 0) {
        continue;
      }
      final RegExpMatch? opening = beginning.firstMatch(token.lexeme);
      final RegExpMatch? closing = ending.firstMatch(token.lexeme);
      if (opening != null) {
        operands.clear();
        if (sections.length >= records.program.limits.maxDepth) {
          throw const AiLimitException(message: 'Native resource artwork exceeds the nesting limit.');
        }
        sections.add(opening[1]!);
      } else if (closing != null) {
        operands.clear();
        if (sections.isEmpty || sections.removeLast() != closing[1]) {
          throw const FormatException('Unmatched native resource artwork boundary.');
        }
      }
      continue;
    }
    if (embedded != 0 || procedures != 0 || sections.isEmpty) {
      continue;
    }
    if (token.kind == .data) {
      operands.clear();
    } else if (token.kind != .executableName) {
      operands.add(token);
    } else {
      if (token.lexeme == 'XW') {
        final bool isPrivate = records._projection.isPrivate(token.start);
        if (operands.any((operand) => records._projection.isPrivate(operand.start) != isPrivate)) {
          throw const FormatException('A native setup style reference mixes private and printable operands.');
        }
        yield AiNativeInstruction._(token: token, operands: operands, isPrivate: isPrivate);
      }
      operands.clear();
    }
  }
  if (sections.isNotEmpty || embedded != 0 || procedures != 0) {
    throw const FormatException('Unterminated native resource artwork.');
  }
}

/// Associates exact names without resolving executable or unknown plug-in data.
List<AiNativeResourceUse> _nativeResourceUses(AiNativeDrawing drawing, AiNativeVersions versions, List<AiNativeStructureNode> nodes, List<AiNativeStructureResource> resources) {
  final Map<(AiNativeStructureResourceKind, String), List<AiNativeStructureResource>> named = {};
  for (final AiNativeStructureResource resource in resources) {
    (named[(resource.kind, latin1.decode(resource.nameBytes))] ??= []).add(resource);
  }
  final List<_NativeStructureReference> references = [];
  for (final AiNativeInstruction instruction in _structureCommands(drawing)) {
    if (instruction.operator == 'XW' && const {0, 1}.contains(instruction.operands.firstOrNull?.number)) {
      if (!_marker(instruction, instruction.operands.first.number!.toInt())) {
        throw const FormatException('Invalid known-style resource reference.');
      }
      if (aiStringBytes(instruction.operands[1]).isNotEmpty) {
        references.add((kind: .knownStyle, instruction: instruction, name: instruction.operands[1]));
      }
    }
  }
  for (final AiNativeGradient gradient in _readGradientInstances(drawing.records)) {
    references.add((kind: .gradient, instruction: gradient.geometry.instruction, name: gradient.geometry.instruction.operands[gradient.geometry.nameIndex]));
  }
  references.sort((a, b) => a.instruction.start.compareTo(b.instruction.start));
  final List<AiNativeResourceUse> result = [];
  int inspected = 0;
  for (final _NativeStructureReference reference in references) {
    final List<AiNativeStructureResource> declarations = named[(reference.kind, latin1.decode(aiStringBytes(reference.name)))] ?? [];
    inspected += 1 + versions.blocks.length + declarations.length;
    if (inspected > drawing.records.program.limits.maxTokens) {
      throw const AiLimitException(message: 'Native resource associations exceed the inspection limit.');
    }
    final AiNativeInstruction instruction = reference.instruction;
    final List<AiNativeVersionMembership> memberships = _structureReferenceVersions(versions, instruction.start, instruction.end);
    final Map<AiNativeVersionBlock, AiNativeVersionBranch> selections = {for (final AiNativeVersionMembership item in memberships) item.block: item.branch};
    final List<AiNativeStructureResource> candidates = declarations
        .where((resource) => resource.versions.every((item) => selections[item.block] == null || selections[item.block] == item.branch))
        .toList();
    final List<AiNativeStructureResource> available = candidates.where((resource) => resource.versions.every((item) => selections[item.block] == item.branch)).toList();
    final AiNativeResourceResolution resolution = candidates.isEmpty
        ? .missing
        : candidates.length == 1 && available.length == 1
        ? .resolved
        : available.length > 1
        ? .ambiguous
        : .conditional;
    int low = 0;
    int high = nodes.length;
    while (low < high) {
      final int middle = (low + high) ~/ 2;
      if (nodes[middle].start <= instruction.start) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    AiNativeStructureNode? owner = low == 0 ? null : nodes[low - 1];
    while (owner != null && owner.end < instruction.end) {
      owner = owner.parentIndex == null ? null : nodes[owner.parentIndex!];
    }
    result.add(AiNativeResourceUse._(kind: reference.kind, instruction: instruction, owner: owner, name: reference.name, versions: memberships, candidates: candidates, resolution: resolution));
  }
  return result;
}

/// Requires one source name/command without embedded alternative operands.
List<AiNativeVersionMembership> _structureReferenceVersions(AiNativeVersions versions, int start, int end) {
  if (versions.blocks.any((block) => start <= block.start && end >= block.end)) {
    throw UnsupportedError('A native resource name or reference encloses version-dependent operands.');
  }
  return versions.memberships(start: start, end: end);
}

/// Uses a scalar type token as the source of an explicitly empty string value.
List<AiNativeVersionMembership> _structureNameVersions(AiNativeVersions versions, AiNativeEntry entry) {
  final int? start = entry.items.firstOrNull?.start ?? entry.typeToken?.start;
  final int? end = entry.items.lastOrNull?.end ?? entry.typeToken?.end;
  if (start == null || end == null) {
    throw const FormatException('A native resource name has no source declaration.');
  }
  return _structureReferenceVersions(versions, start, end);
}

/// Parsed reference awaiting source ownership and declaration matching.
typedef _NativeStructureReference = ({AiNativeStructureResourceKind kind, AiNativeInstruction instruction, AiToken name});
