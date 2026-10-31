part of 'package:aikit/src/model/ai_native_records.dart';

/// Pairs only real body layer comments with their matching executable owners.
Map<AiLayer, ({AiToken opening, AiToken closing})> _nativeLayerComments(AiNativeDrawing drawing) {
  final Map<int, AiLayer> openings = {for (final AiLayer layer in drawing.records.program.layers) layer.begin.start: layer};
  final Map<int, AiLayer> closings = {for (final AiLayer layer in drawing.records.program.layers) layer.end.end: layer};
  final List<({AiLayer layer, AiToken token})> stack = [];
  final Map<AiLayer, ({AiToken opening, AiToken closing})> result = {};
  final List<AiNativeItem> items = drawing.items;
  int procedures = 0;
  int embedded = 0;
  for (final AiToken token in _pathInterval(drawing.records._projection.tokens, drawing.records.program.bodyStart, drawing.records.program.bodyEnd, (token) => token.start)) {
    if (token.kind == .procedureStart) {
      procedures++;
    } else if (token.kind == .procedureEnd) {
      procedures--;
    }
    if (token.kind != .comment || procedures != 0) {
      continue;
    }
    if (token.lexeme.startsWith('%%BeginDocument')) {
      embedded++;
    } else if (token.lexeme == '%%EndDocument') {
      embedded--;
      continue;
    }
    if (embedded != 0 || !token.lexeme.startsWith('%AI5_BeginLayer') && !token.lexeme.startsWith('%AI5_EndLayer')) {
      continue;
    }
    final int index = _pathOffset(items, token.start, (item) => item.start);
    if (index > 0 && items[index - 1] is AiNativeContainer && items[index - 1].end > token.start) {
      continue;
    }
    if (token.lexeme == '%AI5_BeginLayer') {
      final AiLayer? layer = index < items.length ? openings[items[index].start] : null;
      if (layer == null || stack.length >= drawing.records.program.limits.maxDepth || result.containsKey(layer) || stack.any((entry) => identical(entry.layer, layer))) {
        throw const FormatException('Unowned, repeated or excessively nested layer declaration.');
      }
      stack.add((layer: layer, token: token));
    } else {
      final AiLayer? layer = index > 0 ? closings[items[index - 1].end] : null;
      if (!const {'%AI5_EndLayer', '%AI5_EndLayer--'}.contains(token.lexeme) || stack.isEmpty || !identical(stack.last.layer, layer)) {
        throw const FormatException('Unmatched native layer comment boundary.');
      }
      final ({AiLayer layer, AiToken token}) opening = stack.removeLast();
      result[opening.layer] = (opening: opening.token, closing: token);
    }
  }
  if (stack.isNotEmpty || embedded != 0 || procedures != 0) {
    throw const FormatException('Unterminated native layer declaration.');
  }
  return result;
}

/// Associates names, expansion flags and dictionaries with explicit layer owners.
AiNativeLayers _nativeLayers(AiNativeDrawing drawing) {
  final AiNativeStructure structure = AiNativeStructure.decode(drawing: drawing);
  final Map<AiLayer, ({AiToken opening, AiToken closing})> comments = _nativeLayerComments(drawing);
  final Map<String, AiNativeHeaderField> header = _nativeNumericHeader(drawing.records, {'AI5_NumLayers', 'AI5_OpenViewLayers'});
  for (final MapEntry<String, AiNativeHeaderField> entry in header.entries) {
    if (entry.value.values.any((value) => value < 0 || value != value.truncateToDouble()) || entry.key == 'AI5_NumLayers' && entry.value.values.length != 1) {
      throw FormatException('Invalid native layer declaration ${entry.key}.');
    }
  }
  final List<AiLayer> sources = drawing.records.program.layers;
  final Map<int, int> indices = {for (final (int, AiLayer) entry in sources.indexed) entry.$2.begin.start: entry.$1};
  final Map<int, List<int>> children = {};
  for (final (int, AiLayer) entry in sources.indexed) {
    if (entry.$2.parentStart case final int parent) {
      (children[indices[parent]!] ??= []).add(entry.$1);
    }
  }
  final Map<AiNativeContainer, AiNativeObjectIdentifier> identifiers = {
    for (final AiNativeObjectIdentifier identifier in structure.identifiers) identifier.field.owner.source as AiNativeContainer: identifier,
  };
  final List<AiNativeLayer> layers = [];
  for (final (int, AiLayer) entry in sources.indexed) {
    final AiLayer source = entry.$2;
    final AiNativeStructureNode node = structure.nodeFor(source);
    final AiNativeStructureNode? parent = structure.parentOf(node);
    final List<double> attributes = source.begin.numbers!;
    String? issue;
    if (node.versions.isNotEmpty || parent != null && parent.kind != .layer) {
      issue = 'The layer has conditional or non-layer ownership.';
    } else if (!const {10, 13, 14}.contains(attributes.length) || attributes.length == 14 && attributes.last != 0) {
      issue = 'The layer header has an unqualified producer layout.';
    } else if (attributes[5] != 0) {
      issue = 'Multilayer masks require a separate ownership contract.';
    }
    final int color = attributes.length == 10 ? 6 : 7;
    if (const {10, 13, 14}.contains(attributes.length) &&
        (attributes[color] < -1 ||
            attributes[color] > 26 ||
            attributes[color] != attributes[color].truncateToDouble() ||
            attributes.skip(color + 1).take(3).any((value) => value < 0 || value > 255 || value != value.truncateToDouble()) ||
            attributes.length > 10 && (!const {0, 1}.contains(attributes[6]) || !const {0, 1}.contains(attributes[11]) || attributes[12] < 0 || attributes[12] > 100))) {
      throw const FormatException('Invalid native layer display attributes.');
    }
    if (source.end.operands.isNotEmpty ||
        _pathInterval(
          drawing.records._projection.tokens,
          source.begin.start,
          source.begin.end,
          (token) => token.start,
        ).any((token) => token.kind == .comment && (token.lexeme.startsWith('%AI') || token.lexeme.startsWith('%%')))) {
      issue ??= 'The layer boundary has additional operands or metadata.';
    }
    final List<AiNativeItem> items = drawing.items;
    int position = _pathOffset(items, source.begin.end, (item) => item.start);
    int bodyStart = source.begin.end;
    AiNativeInstruction? expansion;
    AiNativeContainer? dictionary;
    if (position < items.length && items[position] is AiNativeInstruction && (items[position] as AiNativeInstruction).operator == 'Ln') {
      final AiNativeInstruction naming = items[position++] as AiNativeInstruction;
      if (naming.isPrivate || naming.token.start != source.naming?.token.start) {
        issue ??= 'The layer has repeated or unowned name instructions.';
      }
      bodyStart = naming.end;
    } else if (source.naming != null) {
      issue ??= 'The layer name is not part of its initial header.';
    }
    if (position < items.length && items[position] is AiNativeInstruction && (items[position] as AiNativeInstruction).operator == 'AE') {
      expansion = items[position++] as AiNativeInstruction;
      if (expansion.isPrivate || expansion.numbers?.length != 1 || !const {0, 1}.contains(expansion.numbers!.single)) {
        throw const FormatException('Invalid native layer expansion flag.');
      }
      bodyStart = expansion.end;
    }
    if (position < items.length && items[position] is AiNativeContainer && (items[position] as AiNativeContainer).type == 'ArtDictionary') {
      dictionary = items[position++] as AiNativeContainer;
      bodyStart = dictionary.end;
      if (dictionary.notRecorded || dictionary.entries.any((field) => field.key != 'AI10_ArtUID') || dictionary.entries.length > 1) {
        issue ??= 'The layer dictionary has additional appearance or reference fields.';
      }
    }
    if (bodyStart > source.end.start) {
      throw const FormatException('Native layer metadata crosses its closing boundary.');
    }
    if (position < items.length && items[position] is AiNativeVersionComment) {
      issue ??= 'The layer header has unresolved conditional ownership.';
    }
    if (_pathInterval(drawing.records._projection.tokens, comments[source]?.opening.end ?? source.begin.start, bodyStart, (token) => token.start).any(
      (token) => token.kind == .data || token.kind == .comment && (token.lexeme.startsWith('%AI') || token.lexeme.startsWith('%%')),
    )) {
      issue ??= 'The layer header contains conditional or unresolved native metadata.';
    }
    layers.add(
      AiNativeLayer._(
        start: comments[source]?.opening.start ?? source.begin.start,
        end: comments[source]?.closing.end ?? source.end.end,
        source: source,
        index: entry.$1,
        parentIndex: source.parentStart == null ? null : indices[source.parentStart],
        childIndices: children[entry.$1] ?? [],
        openingComment: comments[source]?.opening,
        closingComment: comments[source]?.closing,
        expansion: expansion,
        dictionary: dictionary,
        identifier: identifiers[dictionary],
        bodyStart: bodyStart,
        bindingIssue: issue,
      ),
    );
  }
  final List<AiToken> viewComments = [];
  if (header['AI5_OpenViewLayers'] case final AiNativeHeaderField view) {
    viewComments.add(view.token);
    final List<AiToken> tokens = drawing.records._projection.tokens;
    for (int index = _pathOffset(tokens, view.token.end, (token) => token.start); index < tokens.length && tokens[index].kind == .comment && tokens[index].lexeme.startsWith('%%+'); index++) {
      viewComments.add(tokens[index]);
    }
  }
  return AiNativeLayers._(drawing: drawing, structure: structure, layers: layers, rootCountHeader: header['AI5_NumLayers'], viewHeader: header['AI5_OpenViewLayers'], viewComments: viewComments);
}
