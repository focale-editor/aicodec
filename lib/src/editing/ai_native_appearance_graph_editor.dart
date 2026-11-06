part of 'package:illustratorkit/src/model/ai_native_records.dart';

/// Rebuilds an existing execution tree with explicit source ownership and limits.
final class _NativeAppearanceGraphEditor {
  /// Current appearance snapshot owning every retained or copied handle.
  final AiNativeAppearance appearance;

  /// Original native records and projection boundaries.
  final AiNativeRecords records;

  /// Part settings and child replacements keyed by exact source handles.
  final Map<AiNativeAppearancePart, AiNativeAppearancePartChange> changes;

  /// Numeric and flag edits against the original immutable source.
  final List<AiSourceEdit> scalarEdits;

  /// Retained handles used once; copied snapshots do not consume their source.
  final Set<AiNativeAppearancePart> retained = {};

  /// Scalar edits consumed by retained owners rather than silently discarded.
  final Set<AiSourceEdit> consumed = {};

  /// Common representation required before rewriting child-field ownership.
  late final bool private = records._projection.isPrivate(appearance.parts.first.record.start);

  /// Bounded total traversal count, including new definitions and source copies.
  int visited = 0;

  /// Captures original offsets before any ancestor or child is serialized.
  _NativeAppearanceGraphEditor({required this.appearance, required this.records, required this.changes, required this.scalarEdits});

  /// Rejects excessive graph expansion before descending or allocating a child.
  void _visit(int depth) {
    if (++visited > records.program.limits.maxTokens || depth >= records.program.limits.maxDepth) {
      throw const AiLimitException(message: 'Appearance graph expansion exceeds native depth or token limits.');
    }
  }

  /// Binds a full child field while retaining comments between its source tokens.
  List<AiSourceEdit> _removeField(AiNativeContainer parent, AiNativeContainer child) {
    final List<AiToken> tokens = records._projection.tokens;
    int index = _pathOffset(tokens, child.end, (token) => token.start);
    while (index < tokens.length && tokens[index].kind == .comment) {
      index++;
    }
    final AiToken key = tokens[index++];
    if (key.lexeme != '/Part' || key.end >= parent.end) {
      throw const FormatException('Appearance children require owned Part fields.');
    }
    while (index < tokens.length && tokens[index].kind == .comment) {
      index++;
    }
    final AiToken separator = tokens[index];
    if (separator.lexeme != ',' && !(separator.lexeme == ';' && separator.end == parent.end)) {
      throw const FormatException('Appearance child fields require a complete source separator.');
    }
    return [
      AiSourceEdit(start: child.start, end: child.end, bytes: []),
      AiSourceEdit(start: key.start, end: key.end, bytes: []),
      if (separator.lexeme == ',') AiSourceEdit(start: separator.start, end: separator.end, bytes: []),
    ];
  }

  /// Serializes one child without equating retention, copying and authoring.
  Uint8List _child(AiNativeAppearanceChild child, int depth) {
    _visit(depth);
    if (child.definition case final AiNativeAppearancePartDefinition definition) {
      return _createdNativeAppearancePart(definition, records.program.limits, private, (child) => _child(child, depth + 1));
    }
    final AiNativeAppearancePart part = child.part!;
    if (!appearance.parts.contains(part)) {
      throw ArgumentError('Appearance children require current handles from the selected style.');
    }
    if (child.copied) {
      return AiNativeEditor.copyRange(program: records.program, start: part.record.start, end: part.record.end);
    }
    return _part(part, depth);
  }

  /// Builds a retained owner and rejects cycles, duplicate ownership and lost edits.
  Uint8List _part(AiNativeAppearancePart part, int depth) {
    if (!retained.add(part)) {
      throw ArgumentError('A retained appearance part cannot occur twice or form a cycle.');
    }
    final AiNativeContainer record = part.record;
    final List<AiNativeAppearancePart> children = part.childIndices.map((index) => appearance.parts[index]).toList();
    final List<AiSourceEdit> own = scalarEdits
        .where((edit) => edit.start >= record.start && edit.end <= record.end && !children.any((child) => edit.start >= child.record.start && edit.end <= child.record.end))
        .toList();
    consumed.addAll(own);
    final AiNativeAppearancePartChange? change = changes[part];
    final List<AiNativeAppearanceChild>? replacement = change?.children;
    final List<AiNativeAppearancePart>? order = change?.childOrder;
    if ((replacement != null || order != null) && !const {AiNativeAppearancePartKind.stack, AiNativeAppearancePartKind.chain}.contains(part.kind)) {
      throw UnsupportedError('Appearance child replacement requires a stack or chain.');
    }
    if (order != null && (order.length != children.length || order.toSet().length != order.length || order.any((child) => !children.contains(child)))) {
      throw ArgumentError('Appearance child order requires every original direct child once.');
    }
    if (replacement == null) {
      for (final (int, AiNativeAppearancePart) child in (order ?? children).indexed) {
        final AiNativeContainer slot = children[child.$1].record;
        own.add(
          AiSourceEdit(
            start: slot.start,
            end: slot.end,
            bytes: _child(AiNativeAppearanceChild.retain(part: child.$2), depth + 1),
          ),
        );
      }
    } else {
      final int insertion = children.firstOrNull?.record.start ?? record.end - 1;
      final BytesBuilder output = BytesBuilder(copy: false);
      if (children.isEmpty && replacement.isNotEmpty) {
        final AiToken previous = records._projection.tokens.take(_pathOffset(records._projection.tokens, insertion, (token) => token.start)).lastWhere((token) => token.kind != .comment);
        if (previous.lexeme != ',') {
          output.add([44, 32]);
        }
      }
      for (final AiNativeAppearanceChild child in replacement) {
        final Uint8List bytes = _child(child, depth + 1);
        final List<int> suffix = latin1.encode(' /Part ,\n${private ? '%_' : ''}');
        if (output.length + bytes.length + suffix.length > records.program.limits.maxDecodedBytes) {
          throw const AiLimitException(message: 'Appearance child replacements exceed the native byte limit.');
        }
        output
          ..add(bytes)
          ..add(suffix);
      }
      own.add(AiSourceEdit(start: insertion, end: insertion, bytes: output.takeBytes()));
      for (final AiNativeAppearancePart child in children) {
        own.addAll(_removeField(record, child.record));
      }
    }
    return AiNativeEditor.copyRange(program: records.program, start: record.start, end: record.end, edits: own);
  }

  /// Emits one execution replacement while leaving the named declaration intact.
  List<AiSourceEdit> build() {
    if (appearance.parts.isEmpty) {
      throw UnsupportedError('Appearance graph changes require an active execution tree.');
    }
    final AiNativeContainer root = appearance.parts.first.record;
    if (_pathInterval(records._projection.tokens, root.start, root.end, (token) => token.start).any((token) => token.kind != .comment && records._projection.isPrivate(token.start) != private)) {
      throw UnsupportedError('Appearance graph changes require uniform ordinary or private execution records.');
    }
    _visit(0);
    final Uint8List bytes = _part(appearance.parts.first, 0);
    if (consumed.length != scalarEdits.length || changes.keys.any((part) => !retained.contains(part))) {
      throw ArgumentError('Appearance changes cannot target removed parts or source-only copies.');
    }
    return [AiSourceEdit(start: root.start, end: root.end, bytes: bytes)];
  }
}
