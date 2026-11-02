part of 'ai_native_text.dart';

/// Attaches host-composed printable text without introducing a text renderer.
extension AiNativeTextSave on AiNativeTextDocument {
  /// Attaches a complete native view from the host, including printable glyphs.
  ///
  /// The host supplies the full ATE strike tree for this exact model revision,
  /// with font-specific glyphs, advances and shadow styles for point/area frames.
  /// Path text requires a separately qualified per-glyph geometry contract.
  /// Frame references and UTF-16 source coverage are checked; glyph selection,
  /// metrics and visual
  /// equivalence remain the host's responsibility. Unknown node kinds, incomplete
  /// glyph coverage and opaque rendered-data caches reject. [overflowStart]
  /// explicitly identifies any uncomposed suffix, including a fully overset story.
  ///
  /// Raw-data cache identifiers on this story's drawing objects are removed.
  /// Undo-free data, other stories and typography resources stay unchanged. Ink
  /// bounds are supplied by the host in drawing coordinates (y up). Save through
  /// `AiNativeData.replace` with a matching host-produced PDF from the same source.
  AiNativeTextDocument withComposedText({required AiNativeTextStory story, required PsEngineDictionary view, required AiBoundingBox bounds, int? overflowStart}) {
    if (!stories.contains(story)) {
      throw ArgumentError('Invalid or foreign Illustrator text story.');
    }
    _printableTextFrames(this, story);
    PsEngineCodec.encode(value: view, limits: engine.limits);
    _validateComposedText(story, view, overflowStart ?? story.modelText.length);
    final _TextLifecycle edit = _TextLifecycle(source: this);
    edit.storyValues[story.index] = PsEngineDictionary(values: {...story.record.values, _textKey(story.record, '1', 'View'): view});
    objects.where((object) => object.storyIndex == story.index).forEach(edit.invalidateMetadata);
    edit.edits.addAll(AiNativeEditor.includeBoundsEdits(program: records.program, bounds: bounds));
    return edit.finish();
  }

  /// Checks complete composed coverage before packaging a synchronized text save.
  ///
  /// For intentionally overset stories, provide their explicit UTF-16 overflow
  /// offsets. Keys are current story handles. This checks native references and
  /// cached structure, not glyph correctness or equivalence with a supplied PDF.
  /// It is opt-in and does not restrict the general native/PDF serialization API.
  void validateTextForSave({Map<AiNativeTextStory, int> overflowStarts = const {}}) {
    if (overflowStarts.keys.any((story) => !stories.contains(story))) {
      throw ArgumentError('Overflow declarations require current story handles.');
    }
    _TextLifecycle(source: this);
    for (final AiNativeTextStory story in stories) {
      _printableTextFrames(this, story);
      _validateComposedText(story, _dictionary(story.view), overflowStarts[story] ?? story.modelText.length);
    }
  }
}

/// Validates owned frames, complete logical coverage and printable glyph leaves.
void _validateComposedText(AiNativeTextStory story, PsEngineDictionary view, int end) {
  _knownTextKeys(view, {'0', 'Frames', '2', 'Strikes'}, 'composed view');
  if (end < 0 || end > story.modelText.length) {
    throw RangeError.range(end, 0, story.modelText.length, 'overflowStart');
  }
  _textBoundary(story.modelText, end);
  final List<int> frames = [];
  for (final PsEngineValue value in _array(_field(view, '0', 'Frames'))) {
    final PsEngineDictionary reference = _dictionary(value);
    _knownTextKeys(reference, {'0', 'Resource'}, 'composed frame reference');
    frames.add(_index(_field(reference, '0', 'Resource')));
  }
  if (frames.length != story.frameIndices.length || frames.indexed.any((entry) => entry.$2 != story.frameIndices[entry.$1])) {
    throw ArgumentError('Composed frames must match the story resource order.');
  }
  final List<AiNativeTextStrike> roots = [for (final PsEngineValue value in _array(_field(view, '2', 'Strikes'))) AiNativeTextStrike._(record: _dictionary(value))];
  if (roots.length != 1 || roots.single.kind != .story) {
    throw const FormatException('Composed text requires one story strike.');
  }
  final List<int> composedFrames = [];
  int covered = 0;

  /// Checks hierarchy so orphan glyphs cannot satisfy a segment's coverage.
  void visit(AiNativeTextStrike strike, AiNativeTextStrikeKind? parent) {
    final bool allowed = switch (strike.kind) {
      .story => parent == null,
      .frame => parent == .story,
      .rowColumn => parent == .frame || parent == .rowColumn,
      .line => parent == .rowColumn || parent == .frame,
      .segment => parent == .line,
      .glyphs => parent == .segment,
      .unknown => false,
    };
    if (!allowed) {
      throw UnsupportedError('Unsupported or misplaced composed text node ${strike.tag}.');
    }
    strike.origin;
    strike.bounds;
    strike.visualBounds;
    strike.selectionAscent;
    strike.selectionDescent;
    if (strike.kind == .frame) {
      final int? frame = strike.frameIndex;
      if (frame == null) {
        throw const FormatException('Composed frame strike has no resource.');
      }
      composedFrames.add(frame);
    }
    if (strike.kind == .segment) {
      final int? start = strike.firstCharacterIndex;
      final int? length = strike.characterCount;
      if (start == null || length == null || length == 0 || start > end || length > end - start || strike.children.isEmpty || strike.children.any((child) => child.kind != .glyphs)) {
        throw const FormatException('Composed segments require covered source ranges and glyph leaves.');
      }
      _textBoundary(story.modelText, start);
      _textBoundary(story.modelText, start + length);
    }
    if (strike.kind == .glyphs && (strike.glyphIds.isEmpty || strike.children.isNotEmpty)) {
      throw const FormatException('Printable glyph strikes require glyph IDs and no children.');
    }
    for (final AiNativeTextStrike child in strike.children) {
      visit(child, strike.kind);
    }
    if (strike.kind == .line) {
      final int lineStart = covered;
      final List<AiNativeTextStrike> segments = [...strike.children]..sort((first, second) => first.firstCharacterIndex!.compareTo(second.firstCharacterIndex!));
      if (segments.isEmpty) {
        throw const FormatException('Composed lines require explicit source segments.');
      }
      for (final AiNativeTextStrike segment in segments) {
        if (segment.firstCharacterIndex != covered) {
          throw const FormatException('Composed lines leave a gap, overlap or reorder the story flow.');
        }
        covered += segment.characterCount!;
      }
      if (_paragraphRunEnd(story.modelText, lineStart) < covered) {
        throw const FormatException('A composed line cannot cross a paragraph or forced break.');
      }
    }
  }

  visit(roots.single, null);
  if (composedFrames.length != frames.length || composedFrames.indexed.any((entry) => entry.$2 != frames[entry.$1])) {
    throw const FormatException('Composed text must include every frame once in story order.');
  }
  if (covered != end) {
    throw const FormatException('Composed text does not cover the declared model range.');
  }
}

/// Leaves path-specific glyph geometry to a separately qualified contract.
void _printableTextFrames(AiNativeTextDocument document, AiNativeTextStory story) {
  if (story.frameIndices.any((index) => index >= document.frames.length)) {
    throw const FormatException('Text composition references a missing frame resource.');
  }
  if (story.frameIndices.any((index) => document.frames[index].kind != .point && document.frames[index].kind != .area)) {
    throw UnsupportedError('Printable path text requires per-glyph path geometry qualification.');
  }
}
