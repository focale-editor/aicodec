part of 'package:aikit/src/model/ai_native_records.dart';

/// Checks complete literal definitions and references before changing a namespace.
void _qualifiedArtworkResources(AiNativeArtworkResources model) => _paintResourceScope(model.structure.drawing.records);

/// Serializes one declaration around host-supplied native artwork without rendering.
Uint8List _nativeArtworkResourceBytes(AiNativeArtworkResourceKind kind, List<int> name, List<int> artwork, AiBoundingBox? bounds, int maximum) {
  if (artwork.length > maximum) {
    throw const AiLimitException(message: 'Artwork resource declaration exceeds the native output limit.');
  }
  if (name.isEmpty || artwork.any((byte) => byte < 0 || byte > 255)) {
    throw ArgumentError('Resource creation requires a nonempty name and bounded native artwork bytes.');
  }
  if ((kind == .pattern) != (bounds != null)) {
    throw ArgumentError('Only pattern declarations require an explicit tile rectangle.');
  }
  if (bounds != null &&
      (![bounds.left, bounds.bottom, bounds.right, bounds.top].every((value) => value.isFinite && value.abs() <= 9007199254740991) || bounds.left >= bounds.right || bounds.bottom >= bounds.top)) {
    throw ArgumentError('Pattern declarations require a nonempty portable tile rectangle.');
  }
  final List<int> literal = _nativeLiteralString(name, maximum);
  final BytesBuilder output = BytesBuilder(copy: false);

  /// Bounds all wrappers, escaped names and raw payload under one output budget.
  void append(List<int> bytes) {
    if (bytes.length > maximum - output.length) {
      throw const AiLimitException(message: 'Artwork resource declaration exceeds the native output limit.');
    }
    output.add(bytes);
  }

  append(
    latin1.encode(switch (kind) {
      .pattern => '\n%AI3_BeginPattern: ',
      .symbol => '\n%AI14_BeginSymbol\n',
      .brush => '\n%AI8_BeginBrushPattern\n',
    }),
  );
  if (kind == .pattern) {
    append(literal);
    append([10]);
  }
  append(literal);
  if (bounds != null) {
    append(latin1.encode(' ${bounds.left} ${bounds.bottom} ${bounds.right} ${bounds.top}'));
  }
  append([10]);
  append(artwork);
  append(
    latin1.encode(switch (kind) {
      .pattern => '\nE\n%AI3_EndPattern\n',
      .symbol => '\n%AI10_EndSymbol\n',
      .brush => '\n%AI8_EndBrushPattern\n',
    }),
  );
  return output.takeBytes();
}

/// Owns literal symbol-panel entries independently of resource artwork.
typedef _NativeSymbolList = ({AiToken opening, AiToken closing, List<AiToken> names});

/// Reads panel ranges only after complete setup reference qualification.
List<_NativeSymbolList> _nativeSymbolLists(AiNativeArtworkResources model) {
  final AiNativeRecords records = model.structure.drawing.records;
  final List<_NativeSymbolList> result = [];
  AiToken? opening;
  bool setup = false;
  final List<AiToken> names = [];
  for (final AiToken token in records._projection.tokens.takeWhile((token) => token.start < records.program.bodyStart)) {
    if (token.kind == .comment && token.lexeme == '%%BeginSetup') {
      setup = true;
    } else if (token.kind == .comment && token.lexeme == '%%EndSetup') {
      setup = false;
    }
    if (!setup) {
      continue;
    }
    if (token.kind == .comment) {
      final String marker = _artboardSetupName(token.lexeme);
      if (const {'%AI10_BeginSymbolList', '%AI24_BeginSymbolList'}.contains(marker)) {
        if (opening != null) {
          throw UnsupportedError('Symbol inventories cannot overlap.');
        }
        opening = token;
        names.clear();
      } else if (const {'%AI10_EndSymbolList', '%AI24_EndSymbolList'}.contains(marker)) {
        if (opening == null || _artboardSetupName(opening.lexeme).replaceFirst('Begin', 'End') != marker) {
          throw const FormatException('Symbol inventory boundaries do not match.');
        }
        result.add((opening: opening, closing: token, names: List.of(names)));
        opening = null;
      }
    } else if (opening != null) {
      names.add(token);
    }
  }
  if (opening != null) {
    throw const FormatException('A symbol inventory has no closing boundary.');
  }
  return result;
}

/// Decodes an atomic candidate and checks every newly reachable dependency.
AiNativeArtworkResources _artworkResourceResult(AiNativeArtworkResources model, List<AiSourceEdit> edits, int count) {
  final AiNativeRecords records = AiNativeRecords.decode(
    program: AiNativeEditor.apply(program: model.structure.drawing.records.program, edits: edits),
  );
  final AiNativeArtworkResources result = AiNativeArtworkResources.decode(
    structure: AiNativeStructure.decode(drawing: AiNativeDrawing.decode(records: records)),
  );
  if (result.resources.length != count) {
    throw const FormatException('Resource editing changed an unexpected declaration count.');
  }
  _qualifiedArtworkResources(result);
  _nativeArtworkResourceCycles(result);
  return result;
}

/// Prevents recursive tile composition through direct paints or named styles.
void _nativeArtworkResourceCycles(AiNativeArtworkResources model) {
  final AiNativeAppearances appearances = AiNativeAppearances.decode(structure: model.structure);
  final Map<String, AiNativeArtworkResource> patterns = {
    for (final AiNativeArtworkResource resource in model.resources.where((resource) => resource.kind == .pattern)) latin1.decode(resource.nameBytes): resource,
  };
  final Map<AiNativeArtworkResource, Set<AiNativeArtworkResource>> edges = {};
  final AiNativeLimits limits = model.structure.drawing.records.program.limits;
  int work = 0;
  final Map<AiNativeAppearance, Set<String>> stylePatterns = {};

  /// Charges dependency work before expanding shared styles at each application.
  void inspect() {
    if (++work > limits.maxTokens) {
      throw const AiLimitException(message: 'Artwork resource dependencies exceed the inspection limit.');
    }
  }

  for (final AiNativeArtworkResource resource in model.resources) {
    final Set<AiNativeArtworkResource> targets = edges[resource] = {};

    /// Resolves a qualified pattern name without treating display labels as links.
    void add(String name) {
      inspect();
      final AiNativeArtworkResource? target = patterns[name];
      if (target == null) {
        throw UnsupportedError('Artwork resource paints require uniquely resolved pattern declarations.');
      }
      targets.add(target);
    }

    for (final AiNativeInstruction command in resource.items.whereType<AiNativeInstruction>()) {
      if (const {'p', 'P'}.contains(command.operator)) {
        add(latin1.decode(aiStringBytes(command.operands.first)));
      }
    }
    for (final AiNativeResourceUse use in resource.uses.where((use) => use.kind == .knownStyle)) {
      inspect();
      final AiNativeAppearance style = appearances.resolve(use: use)!;
      final Set<String> names = stylePatterns.putIfAbsent(style, () {
        final Set<String> result = {};
        for (final AiNativeInstruction paint in _nativeAppearancePatternPaints(style)) {
          inspect();
          result.add(latin1.decode(aiStringBytes(paint.operands.first)));
        }
        return result;
      });
      names.forEach(add);
    }
  }
  final Set<AiNativeArtworkResource> visited = {};
  final Set<AiNativeArtworkResource> visiting = {};

  /// Bounds recursive dependency traversal independently of lexical group depth.
  void visit(AiNativeArtworkResource resource) {
    if (visited.contains(resource)) {
      return;
    }
    if (!visiting.add(resource)) {
      throw UnsupportedError('Artwork resource dependencies cannot be recursive.');
    }
    if (visiting.length > limits.maxDepth) {
      throw const AiLimitException(message: 'Artwork resource dependencies exceed the nesting limit.');
    }
    (edges[resource] ?? const {}).forEach(visit);
    visiting.remove(resource);
    visited.add(resource);
  }

  model.resources.forEach(visit);
}

/// Identifies source-owned object and sample identities without conflating names.
List<({AiNativeContainer owner, String value})> _nativeArtworkResourceIdentities(AiNativeRecords records) {
  final List<({AiNativeContainer owner, String value})> result = [];
  for (final AiNativeContainer record in records.containers) {
    if (record.type == 'XMLUID') {
      result.add((owner: record, value: latin1.decode(record.entries.single.stringBytes!)));
      continue;
    }
    for (final AiNativeEntry entry in record.entries) {
      if (const {'AI24 ImageRawDataUUID', 'AI24 ImageAlphaRawDataUUID'}.contains(entry.key)) {
        final Uint8List? value = entry.stringBytes;
        if (value == null || value.isEmpty) {
          throw UnsupportedError('Artwork sample identities require nonempty literal strings.');
        }
        result.add((owner: record, value: latin1.decode(value)));
      }
    }
  }
  return result;
}

/// Rejects identity collisions while allowing a replacement to retain its own IDs.
void _validateCreatedResourceIdentities(AiNativeArtworkResources before, AiNativeArtworkResources after, AiNativeArtworkResource added, {AiNativeArtworkResource? replaced}) {
  final AiNativeRecords records = before.structure.drawing.records;
  _nativeIdentityNames(before.structure);
  _nativeIdentityNames(after.structure);
  final Set<String> reserved = {
    for (final ({AiNativeContainer owner, String value}) identity in _nativeArtworkResourceIdentities(records))
      if (replaced == null || identity.owner.start < replaced.start || identity.owner.end > replaced.end) identity.value,
  };
  for (final ({AiNativeContainer owner, String value}) identity in _nativeArtworkResourceIdentities(after.structure.drawing.records)) {
    if (identity.owner.start >= added.start && identity.owner.end <= added.end) {
      if (identity.owner.type == 'XMLUID') {
        _newNativeIdentity(latin1.encode(identity.value), reserved, records.program.limits.maxDecodedBytes);
      } else if (!reserved.add(identity.value)) {
        throw ArgumentError('New resource artwork requires distinct fresh sample identities.');
      }
    }
  }
}

/// Initializes a declaration and its symbol-panel membership as one transaction.
AiNativeArtworkResources _createNativeArtworkResource(AiNativeArtworkResources model, AiNativeArtworkResourceKind kind, List<int> name, List<int> artwork, AiBoundingBox? bounds, bool listed) {
  if (model.resources.any((resource) => resource.kind == kind && _sameNativeBytes(resource.nameBytes, name))) {
    throw ArgumentError('A new artwork resource requires a fresh name in its namespace.');
  }
  final AiNativeRecords records = model.structure.drawing.records;
  final Uint8List bytes = _nativeArtworkResourceBytes(kind, name, artwork, bounds, records.program.limits.maxDecodedBytes - records.program.bytes.length);
  _qualifiedArtworkResources(model);
  final int position = _nativeAppearanceSetupEnd(records);
  final List<AiSourceEdit> edits = [];
  final List<int> declaration = [...bytes];
  if (kind == .symbol && listed) {
    final List<int> literal = _nativeLiteralString(name, records.program.limits.maxDecodedBytes);
    final List<_NativeSymbolList> panels = _nativeSymbolLists(model);
    if (panels.isEmpty) {
      declaration.addAll([...latin1.encode('%AI24_BeginSymbolList\n'), ...literal, ...latin1.encode('\n%AI24_EndSymbolList\n')]);
    } else {
      for (final _NativeSymbolList panel in panels) {
        edits.add(AiSourceEdit(start: panel.closing.start, end: panel.closing.start, bytes: [...literal, 10]));
      }
    }
  }
  edits.add(AiSourceEdit(start: position, end: position, bytes: declaration));
  final AiNativeArtworkResources result = _artworkResourceResult(model, edits, model.resources.length + 1);
  final AiNativeArtworkResource added = result.resources.singleWhere((resource) => resource.kind == kind && _sameNativeBytes(resource.nameBytes, name));
  _validateCreatedResourceIdentities(model, result, added);
  return result;
}

/// Deletes unused definitions and their panel entries without removing consumers.
AiNativeArtworkResources _removeNativeArtworkResources(AiNativeArtworkResources model, List<AiNativeArtworkResource> selected) {
  if (selected.isEmpty || selected.toSet().length != selected.length || selected.any((resource) => !model.resources.contains(resource))) {
    throw ArgumentError('Resource removal requires distinct current declaration handles.');
  }
  _qualifiedArtworkResources(model);
  final Set<String> symbols = {for (final AiNativeArtworkResource resource in selected.where((resource) => resource.kind == .symbol)) latin1.decode(resource.nameBytes)};
  final List<AiSourceEdit> edits = [
    for (final AiNativeArtworkResource resource in selected) AiSourceEdit(start: resource.start, end: resource.end, bytes: []),
    for (final _NativeSymbolList panel in _nativeSymbolLists(model))
      for (final AiToken name in panel.names)
        if (symbols.contains(latin1.decode(aiStringBytes(name)))) AiSourceEdit(start: name.start, end: name.end, bytes: []),
  ];
  final AiNativeRecords records = model.structure.drawing.records;
  _nativeIdentityNames(model.structure);
  final Set<String> removed = {
    for (final ({AiNativeContainer owner, String value}) identity in _nativeArtworkResourceIdentities(records))
      if (selected.any((resource) => identity.owner.start >= resource.start && identity.owner.end <= resource.end)) identity.value,
  };
  if (removed.isNotEmpty &&
      records._projection.tokens.any(
        (token) =>
            const {AiTokenKind.string, AiTokenKind.hexString}.contains(token.kind) &&
            !edits.any((edit) => token.start >= edit.start && token.end <= edit.end) &&
            removed.contains(latin1.decode(aiStringBytes(token))),
      )) {
    throw UnsupportedError('Removed resource identities have retained or uncertain external references.');
  }
  return _artworkResourceResult(model, edits, model.resources.length - selected.length);
}

/// Revises an unused declaration while retaining its name and panel position.
AiNativeArtworkResources _replaceUnusedNativeArtworkResource(AiNativeArtworkResources model, AiNativeArtworkResource resource, List<int> artwork, AiBoundingBox? bounds) {
  if (!model.resources.contains(resource)) {
    throw ArgumentError('Resource replacement requires a current declaration handle.');
  }
  _removeNativeArtworkResources(model, [resource]);
  final AiProgram program = model.structure.drawing.records.program;
  final Uint8List bytes = _nativeArtworkResourceBytes(resource.kind, resource.nameBytes, artwork, bounds, program.limits.maxDecodedBytes - program.bytes.length + resource.end - resource.start);
  final AiNativeArtworkResources result = _artworkResourceResult(model, [AiSourceEdit(start: resource.start, end: resource.end, bytes: bytes)], model.resources.length);
  final AiNativeArtworkResource changed = result.resources.singleWhere((value) => value.kind == resource.kind && _sameNativeBytes(value.nameBytes, resource.nameBytes));
  _validateCreatedResourceIdentities(model, result, changed, replaced: resource);
  return result;
}

/// Renames one resolved symbol namespace without touching editable or printed art.
AiNativeArtworkResources _renameNativeSymbol(AiNativeArtworkResources model, AiNativeArtworkResource resource, List<int> name) {
  if (!model.resources.contains(resource) ||
      resource.kind != .symbol ||
      name.isEmpty ||
      model.resources.any((other) => !identical(other, resource) && other.kind == .symbol && _sameNativeBytes(other.nameBytes, name))) {
    throw ArgumentError('Symbol renaming requires a current master and a free literal name.');
  }
  _qualifiedArtworkResources(model);
  final AiNativeSymbols symbols = AiNativeSymbols.decode(artworkResources: model);
  final List<int> literal = _nativeLiteralString(name, model.structure.drawing.records.program.limits.maxDecodedBytes);
  final List<AiSourceEdit> edits = [AiSourceEdit(start: resource.name.start, end: resource.name.end, bytes: literal)];
  for (final AiNativeSymbolInstance instance in symbols.instancesOf(definition: resource)) {
    if (instance.definition != resource || instance.resource != null || instance.node.versions.isNotEmpty) {
      throw UnsupportedError('Symbol renaming requires complete ordinary reference ownership.');
    }
    _nativeSymbolDefinition(instance.record);
    final AiNativeEntry entry = instance.record['SymbolRef']!;
    final AiToken token = (entry.items.single as AiNativeToken).token;
    edits.add(AiSourceEdit(start: token.start, end: token.end, bytes: literal));
  }
  for (final _NativeSymbolList panel in _nativeSymbolLists(model)) {
    for (final AiToken token in panel.names) {
      if (_sameNativeBytes(aiStringBytes(token), resource.nameBytes)) {
        edits.add(AiSourceEdit(start: token.start, end: token.end, bytes: literal));
      }
    }
  }
  return _artworkResourceResult(model, edits, model.resources.length);
}
