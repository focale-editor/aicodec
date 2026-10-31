part of 'ai_native_text.dart';

/// Native frame categories used by point, area and path text.
enum AiNativeTextFrameKind {
  /// Text placed from a baseline origin.
  point,

  /// Text flowing inside a closed path, possibly across linked frames.
  area,

  /// Text following an open or closed path.
  path,

  /// A future frame category retained without interpreting its geometry.
  unknown,
}

/// Recognized nodes in Illustrator's cached glyph-layout tree.
enum AiNativeTextStrikeKind {
  /// Root grouping for a story's layout.
  story,

  /// Layout assigned to one document frame resource.
  frame,

  /// A row or column within a composed frame.
  rowColumn,

  /// A composed line and its baseline metrics.
  line,

  /// A text segment with a source-character mapping.
  segment,

  /// A sequence of font-specific glyph identifiers.
  glyphs,

  /// An unrecognized native layout node, retained for later interpretation.
  unknown,
}

/// A source-backed cached layout node; it does not imply newly shaped text.
final class AiNativeTextStrike {
  /// Complete original node, including unknown geometry and composition caches.
  final PsEngineDictionary record;

  /// Native stream tag without its slash prefix.
  final String tag;

  /// Recognized meaning of [tag], accepting compact and named ATE variants.
  final AiNativeTextStrikeKind kind;

  /// Child nodes in their native order, without sorting by source character.
  final List<AiNativeTextStrike> children;

  /// Builds a view over the already depth- and node-bounded engine tree.
  factory AiNativeTextStrike._({
    required PsEngineDictionary record,
  }) {
    final PsEngineValue? name = _field(record, '99', 'StreamTag');
    if (name is! PsEngineName) {
      throw const FormatException('Missing Illustrator text-layout stream tag.');
    }
    final AiNativeTextStrikeKind kind = switch (name.value) {
      'PC' || 'PathSelectGroupCharacter' => .story,
      'F' || 'FrameStrike' => .frame,
      'R' || 'RowColStrike' => .rowColumn,
      'L' || 'LineStrike' => .line,
      'S' || 'Segment' => .segment,
      'G' || 'GlyphStrike' => .glyphs,
      _ => .unknown,
    };
    return AiNativeTextStrike._checked(
      record: record,
      tag: name.value,
      kind: kind,
      children: [for (final PsEngineValue child in _array(_field(record, '6', 'Children'))) AiNativeTextStrike._(record: _dictionary(child))],
    );
  }

  /// Retains immutable node metadata and child views.
  AiNativeTextStrike._checked({
    required this.record,
    required this.tag,
    required this.kind,
    required List<AiNativeTextStrike> children,
  }) : children = List.unmodifiable(children);

  /// Traverses this node and all descendants in source order.
  Iterable<AiNativeTextStrike> get descendants sync* {
    yield this;
    for (final AiNativeTextStrike child in children) {
      yield* child.descendants;
    }
  }

  /// Local transform origin, or null when omitted rather than explicitly zero.
  List<double>? get origin => _coordinates(_at(record, [('0', 'Transform'), ('0', 'Origin')]), 2);

  /// Local cached bounds in the native order; omitted bounds remain null.
  List<double>? get bounds => _coordinates(_field(record, '1', 'Bounds'), 4);

  /// Global frame-resource index for a frame strike.
  int? get frameIndex => kind == .frame ? _optionalIndex(_field(record, '10', 'Frame')) : null;

  /// First story UTF-16 code-unit index for a segment.
  int? get firstCharacterIndex => kind == .segment ? _optionalIndex(_field(record, '20', 'FirstCharacterIndexInSegment')) : null;

  /// Number of source UTF-16 code units represented by a segment.
  int? get characterCount => kind == .segment ? _optionalIndex(_at(record, [('15', 'Mapping'), ('0', 'CharacterCount')])) : null;

  /// Font-specific glyph IDs, preserving visual ordering and hidden CR glyphs.
  List<int> get glyphIds => kind != .glyphs ? const [] : List.unmodifiable([for (final PsEngineValue glyph in _array(_field(record, '5', 'Glyphs'))) _index(glyph)]);

  /// Retained shadow styles supplying per-glyph font and scale information.
  PsEngineDictionary? get shadowStyles => kind == .glyphs ? _optionalDictionary(_field(record, '10', 'ShadowStylesRun')) : null;

  /// Retained visual bounds before the frame matrix, when explicitly stored.
  List<double>? get visualBounds => kind == .glyphs ? _coordinates(_field(record, '8', 'VisualBounds'), 4) : null;

  /// Native signed selection ascent for line and glyph nodes, when present.
  double? get selectionAscent => switch (kind) {
    .line => _number(_field(record, '14', 'SelectionAscent')),
    .glyphs => _number(_field(record, '12', 'SelectionAscent')),
    _ => null,
  };

  /// Native signed selection descent for line and glyph nodes, when present.
  double? get selectionDescent => switch (kind) {
    .line => _number(_field(record, '15', 'SelectionDescent')),
    .glyphs => _number(_field(record, '13', 'SelectionDescent')),
    _ => null,
  };

  /// Whether a segment declares a valid native word-reorder mapping.
  bool? get wordReorderValid => kind != .segment
      ? null
      : switch (_at(record, [('15', 'Mapping'), ('5', 'WRValid')])) {
          null => null,
          PsEngineBoolean(:final bool value) => value,
          _ => throw const FormatException('Invalid Illustrator word-reorder validity flag.'),
        };

  /// Whether a compact segment map contains the recognized terminal hyphen insertion.
  ///
  /// This tests the insertion record, not a glyph/character count difference:
  /// ligatures can offset an extra glyph. Other native mapping entries remain
  /// accessible in [record] and are not inferred from this Boolean result.
  bool get hasTerminalHyphenInsertion {
    if (kind != .segment) {
      return false;
    }
    final PsEngineDictionary? mapping = _optionalDictionary(_field(record, '15', 'Mapping'));
    final int? count = characterCount;
    if (mapping == null || count == null) {
      return false;
    }
    for (final PsEngineValue entry in _array(mapping['1'])) {
      final PsEngineDictionary item = _dictionary(entry);
      if (_optionalIndex(item['0']) == 2 && _optionalIndex(item['1']) == count - 1 && _optionalIndex(item['2']) == 2) {
        return true;
      }
    }
    return false;
  }
}

/// Reads a finite coordinate array with an exact format-defined arity.
List<double>? _coordinates(PsEngineValue? value, int count) {
  if (value == null) {
    return null;
  }
  if (value is! PsEngineArray || value.values.length != count) {
    throw const FormatException('Invalid Illustrator text coordinate array.');
  }
  return List.unmodifiable([for (final PsEngineValue coordinate in value.values) _number(coordinate)!]);
}
