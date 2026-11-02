part of 'ai_native_text.dart';

/// One actual font glyph positioned by the host, without package-side shaping.
final class AiNativeTextGlyphLayout {
  /// Current source-owned font that supplied [glyphId].
  final AiNativeTextFont font;

  /// Font-specific glyph index, including actual whitespace glyphs.
  final int glyphId;

  /// Baseline origin relative to its segment, in native points with y down.
  final double x;

  /// Downward baseline displacement relative to its segment.
  final double y;

  /// Host-measured local bounds `[left, top, right, bottom]`.
  final List<double> bounds;

  /// Host-composed bounds after path placement, before the frame matrix.
  ///
  /// Required for path frames; origins remain distances in the unwrapped line.
  final List<double>? pathBounds;

  /// Whether this is the nonprinting space glyph representing a paragraph mark.
  ///
  /// The host must supply the real space glyph from [font]; this does not select
  /// a glyph or guess a font's whitespace index.
  final bool paragraphMark;

  /// Retains checked original glyph identity and compositor geometry.
  AiNativeTextGlyphLayout({required this.font, required this.glyphId, required this.x, required this.y, required List<double> bounds, List<double>? pathBounds, this.paragraphMark = false})
    : bounds = List.unmodifiable(bounds),
      pathBounds = pathBounds == null ? null : List.unmodifiable(pathBounds) {
    if (glyphId < 0 || glyphId > 65535 || !x.isFinite || !y.isFinite || bounds.length != 4 || bounds.any((value) => !value.isFinite) || bounds[0] > bounds[2] || bounds[1] > bounds[3]) {
      throw ArgumentError('Invalid host-composed Illustrator glyph.');
    }
    if (pathBounds != null && (pathBounds.length != 4 || pathBounds.any((value) => !value.isFinite) || pathBounds[0] > pathBounds[2] || pathBounds[1] > pathBounds[3])) {
      throw ArgumentError('Invalid composed path-glyph bounds.');
    }
  }
}

/// One positioned source segment supplied by the host's text compositor.
///
/// Coordinates are native points with y down, relative to the line origin.
/// Source offsets remain logical UTF-16 offsets even when visual order differs.
final class AiNativeTextSegmentLayout {
  /// Inclusive source offset, counting the story's final paragraph mark.
  final int start;

  /// Exclusive source offset, without splitting a surrogate pair.
  final int end;

  /// Horizontal displacement from the line origin, in points.
  final double x;

  /// Downward displacement from the line origin, in points.
  final double y;

  /// Whether this is an ordered right-to-left segment in the native mapping.
  final bool rightToLeft;

  /// Whether composition inserts a visible terminal hyphen outside the model text.
  final bool automaticHyphen;

  /// Actual glyphs for one logical shaping cluster, used by `withGlyphLayout`.
  ///
  /// Empty for position-only layout. A cluster may contract several UTF-16 units
  /// to one glyph or expand one unit into several glyphs. More general mappings
  /// require the explicit native view API rather than an inferred mapping.
  final List<AiNativeTextGlyphLayout> glyphs;

  /// Creates a source range and position without inventing glyphs or advances.
  AiNativeTextSegmentLayout({required this.start, required this.end, this.x = 0, this.y = 0, this.rightToLeft = false, this.automaticHyphen = false, List<AiNativeTextGlyphLayout> glyphs = const []})
    : glyphs = List.unmodifiable(glyphs) {
    if (start < 0 || end <= start || !x.isFinite || !y.isFinite) {
      throw ArgumentError('Invalid composed Illustrator text segment.');
    }
  }
}

/// A composed line whose segments are retained in the host's visual order.
final class AiNativeTextLineLayout {
  /// Horizontal line origin relative to its frame origin, in points.
  final double x;

  /// Downward line origin relative to its frame origin, in points.
  final double y;

  /// Distance above the baseline used for native selection, when supplied.
  final double? ascent;

  /// Distance below the baseline used for native selection, when supplied.
  final double? descent;

  /// Optional local `[left, top, right, bottom]` bounds supplied by the host.
  final List<double>? bounds;

  /// Positioned source segments in visual order, including paragraph marks.
  final List<AiNativeTextSegmentLayout> segments;

  /// Owns immutable positions and metrics without measuring or breaking text.
  AiNativeTextLineLayout({
    this.x = 0,
    this.y = 0,
    this.ascent,
    this.descent,
    List<double>? bounds,
    required List<AiNativeTextSegmentLayout> segments,
  }) : bounds = bounds == null ? null : List.unmodifiable(bounds),
       segments = List.unmodifiable(segments) {
    if (!x.isFinite || !y.isFinite || ascent != null && (!ascent!.isFinite || ascent! < 0) || descent != null && (!descent!.isFinite || descent! < 0) || segments.isEmpty) {
      throw ArgumentError('Invalid composed Illustrator text line.');
    }
    if (bounds != null && (bounds.length != 4 || bounds.any((value) => !value.isFinite) || bounds[0] > bounds[2] || bounds[1] > bounds[3])) {
      throw ArgumentError('Invalid composed Illustrator line bounds.');
    }
  }
}

/// A point, area or path frame's composed lines, referencing an owned native resource.
final class AiNativeTextFrameLayout {
  /// Source resource whose path and transform remain unchanged.
  final AiNativeTextFrame frame;

  /// Native frame origin in the retained layout's coordinate space, in points.
  final double x;

  /// Native frame origin with y increasing downwards, in points.
  final double y;

  /// Lines in source progression order; an empty frame is allowed explicitly.
  final List<AiNativeTextLineLayout> lines;

  /// Owns one frame layout without changing its native placement or geometry.
  AiNativeTextFrameLayout({required this.frame, required this.x, required this.y, required List<AiNativeTextLineLayout> lines}) : lines = List.unmodifiable(lines) {
    if (!x.isFinite || !y.isFinite) {
      throw ArgumentError('Invalid composed Illustrator frame origin.');
    }
  }
}

/// Writes host-composed source positions into native ATE layout records.
extension AiNativeTextComposition on AiNativeTextDocument {
  /// Attaches actual host glyphs with checked source clusters and font ownership.
  ///
  /// Each segment describes one shaping cluster. Positions are explicit, so
  /// kerning and tracking do not have to be reconstructed from glyph advances.
  /// The final CR uses a real host-supplied space glyph marked [AiNativeTextGlyphLayout.paragraphMark].
  /// Compact CC point, area and path frames are supported. Path glyphs require
  /// explicit projected [AiNativeTextGlyphLayout.pathBounds]. Complex many-to-many cluster
  /// maps, automatic hyphens and named CS glyph caches use [withComposedText].
  AiNativeTextDocument withGlyphLayout({required AiNativeTextStory story, required List<AiNativeTextFrameLayout> frames, required AiBoundingBox bounds, int? overflowStart}) {
    if (!stories.contains(story)) {
      throw ArgumentError('Invalid or foreign Illustrator text story.');
    }
    if (story.record.values.containsKey('View')) {
      throw UnsupportedError('Typed glyph composition requires compact CC field names.');
    }
    if (frames.length != story.frameIndices.length) {
      throw ArgumentError('Composed Illustrator frames must match the complete story frame list.');
    }
    int remaining = engine.limits.maxNodes ~/ 40;
    for (final AiNativeTextFrameLayout frame in frames) {
      for (final AiNativeTextLineLayout line in frame.lines) {
        for (final AiNativeTextSegmentLayout segment in line.segments) {
          remaining -= segment.glyphs.length;
          if (remaining < 0) {
            throw const FormatException('Composed Illustrator glyphs exceed the engine node limit.');
          }
          final int count = segment.end - segment.start;
          if (segment.glyphs.isEmpty || segment.automaticHyphen || count > 1 && segment.glyphs.length > 1) {
            throw UnsupportedError('Glyph segments require one qualified shaping cluster without automatic insertions.');
          }
          for (final AiNativeTextGlyphLayout glyph in segment.glyphs) {
            if ((frame.frame.kind == .path) != (glyph.pathBounds != null)) {
              throw ArgumentError('Path frames require projected glyph bounds alongside unwrapped origins.');
            }
            if (!(frame.x + line.x + segment.x + glyph.x).isFinite || !(frame.y + line.y + segment.y + glyph.y).isFinite) {
              throw ArgumentError('Composed Illustrator glyph origin overflows its frame.');
            }
            if (!fonts.contains(glyph.font)) {
              throw ArgumentError('Composed glyphs require fonts from this snapshot.');
            }
            if (glyph.paragraphMark && (count != 1 || segment.end > story.modelText.length || story.modelText.codeUnitAt(segment.start) != 13)) {
              throw ArgumentError('A paragraph-mark glyph must cover exactly one native CR.');
            }
          }
          if (segment.end <= story.modelText.length && story.modelText.substring(segment.start, segment.end).contains('\r') && (segment.glyphs.length != 1 || !segment.glyphs.single.paragraphMark)) {
            throw ArgumentError('Native CR coverage requires an explicit paragraph-mark glyph.');
          }
        }
      }
    }
    final AiNativeTextDocument positioned = _withTextLayout(story: story, frames: frames, overflowStart: overflowStart, glyphs: true);
    final AiNativeTextStory changed = positioned.stories[story.index];
    return positioned.withComposedText(story: changed, view: _dictionary(changed.view), bounds: bounds, overflowStart: overflowStart);
  }

  /// Invalidates one story's composed layout without changing its native model.
  ///
  /// Use this when an external dependency, such as a resolved font, changes.
  /// Text, styles, frame references, other stories and the undo-free model stay
  /// unchanged. Only known rendered-data and strike fields are removed; unknown
  /// view fields reject. The host must supply new composition and matching
  /// printing/PDF artwork before saving a synchronized document.
  AiNativeTextDocument withoutTextLayout({required AiNativeTextStory story}) {
    if (!stories.contains(story)) {
      throw ArgumentError('Invalid or foreign Illustrator text story.');
    }
    final PsEngineDictionary view = _dictionary(_field(story.record, '1', 'View'));
    _knownTextKeys(view, {'0', 'Frames', '1', 'RenderedData', '2', 'Strikes'}, 'view');
    if (view.values.keys.every((key) => key == '0' || key == 'Frames')) {
      return this;
    }
    return _withEngine(engine.replaceValues(replacements: {view: _textViewWithoutCaches(view)}));
  }

  /// Replaces one story's layout with checked frame, line and segment positions.
  ///
  /// Frames must match the story's resource order, including empty linked frames.
  /// Lines advance through the logical source without gaps or overlap; segments
  /// within each line may appear in visual order. A line cannot cross a paragraph
  /// or forced break. [overflowStart] explicitly identifies a remaining uncomposed
  /// suffix; otherwise every UTF-16 unit, including the final CR, must be covered.
  ///
  /// This writes PC/F/R/R/L/S records, preserving model text, styles, resources,
  /// frame references and other stories. It removes old rendered-data/glyph
  /// caches and does not fabricate GlyphStrike IDs or font metrics. The host must
  /// shape text and synchronize printable/PDF artwork from the same composition.
  /// Text-on-path requires additional per-glyph geometry and is rejected here.
  AiNativeTextDocument withTextLayout({required AiNativeTextStory story, required List<AiNativeTextFrameLayout> frames, int? overflowStart}) =>
      _withTextLayout(story: story, frames: frames, overflowStart: overflowStart, glyphs: false);

  /// Shares logical coverage checks between positioned and glyph-bearing views.
  AiNativeTextDocument _withTextLayout({required AiNativeTextStory story, required List<AiNativeTextFrameLayout> frames, required bool glyphs, int? overflowStart}) {
    if (!stories.contains(story)) {
      throw ArgumentError('Invalid or foreign Illustrator text story.');
    }
    final int end = overflowStart ?? story.modelText.length;
    if (end < 0 || end > story.modelText.length) {
      throw RangeError.range(end, 0, story.modelText.length, 'overflowStart');
    }
    _textBoundary(story.modelText, end);
    if (frames.length != story.frameIndices.length) {
      throw ArgumentError('Composed Illustrator frames must match the complete story frame list.');
    }
    final _TextCompositionWriter writer = _TextCompositionWriter(named: story.record.values.containsKey('View'), maxNodes: engine.limits.maxNodes, glyphs: glyphs);
    int next = 0;
    final List<PsEngineValue> frameNodes = [];
    for (int index = 0; index < frames.length; index++) {
      final AiNativeTextFrameLayout frame = frames[index];
      if (frame.frame.index >= this.frames.length || !identical(this.frames[frame.frame.index], frame.frame) || frame.frame.index != story.frameIndices[index]) {
        throw ArgumentError('Foreign, stale or reordered Illustrator composition frame.');
      }
      if (frame.frame.kind != .point && frame.frame.kind != .area && !(glyphs && frame.frame.kind == .path)) {
        throw UnsupportedError('Composed Illustrator path text requires per-glyph path geometry.');
      }
      final List<PsEngineValue> lines = [];
      for (final AiNativeTextLineLayout line in frame.lines) {
        writer.reserve(16);
        if (!(frame.x + line.x).isFinite || !(frame.y + line.y).isFinite) {
          throw ArgumentError('Composed Illustrator line origin overflows its frame.');
        }
        final List<AiNativeTextSegmentLayout> ordered = [];
        for (final AiNativeTextSegmentLayout segment in line.segments) {
          writer.reserve(20);
          if (glyphs) {
            writer.reserve(segment.glyphs.length * 40);
          }
          if (writer.named && (segment.rightToLeft || segment.automaticHyphen)) {
            throw UnsupportedError('Named CS reordered or automatically hyphenated mappings are not yet supported.');
          }
          if (segment.end > end || !(frame.x + line.x + segment.x).isFinite || !(frame.y + line.y + segment.y).isFinite) {
            throw ArgumentError('Composed Illustrator segment exceeds the source range or coordinate limits.');
          }
          _textBoundary(story.modelText, segment.start);
          _textBoundary(story.modelText, segment.end);
          if (segment.automaticHyphen) {
            final int last = story.modelText.codeUnitAt(segment.end - 1);
            if (last == 13 || last == 3 || last >= 0xdc00 && last <= 0xdfff) {
              throw UnsupportedError('Automatic hyphen mapping requires a terminal BMP source character, excluding line breaks.');
            }
          }
          ordered.add(segment);
        }
        ordered.sort((first, second) => first.start.compareTo(second.start));
        final int lineStart = next;
        for (final AiNativeTextSegmentLayout segment in ordered) {
          if (segment.start != next) {
            throw ArgumentError('Composed Illustrator text has a gap, overlap or reordered line.');
          }
          next = segment.end;
        }
        if (ordered.any((segment) => segment.automaticHyphen && segment.end != next)) {
          throw ArgumentError('An automatic hyphen must terminate its composed line.');
        }
        for (int position = lineStart; position < next - 1; position++) {
          final int unit = story.modelText.codeUnitAt(position);
          if (unit == 13 || unit == 3) {
            throw ArgumentError('Composed Illustrator line crosses a paragraph or forced break.');
          }
        }
        lines.add(writer.line(line));
      }
      writer.reserve(40);
      frameNodes.add(writer.frame(frame, lines));
    }
    if (next != end) {
      throw ArgumentError('Composed Illustrator text does not cover the declared source range.');
    }
    writer.reserve(8);
    final PsEngineDictionary view = _dictionary(_field(story.record, '1', 'View'));
    _knownTextKeys(view, {'0', 'Frames', '1', 'RenderedData', '2', 'Strikes'}, 'view');
    final PsEngineDictionary changed = PsEngineDictionary(
      values: {
        ..._textViewWithoutCaches(view).values,
        _featureKey(view, '2', 'Strikes', writer.named): PsEngineArray(values: [writer.node('PC', 'PathSelectGroupCharacter', children: frameNodes, procession: 0)]),
      },
    );
    return _withEngine(engine.replaceValues(replacements: {view: changed}));
  }
}

/// Serializes observed source-position nodes without pretending to shape glyphs.
final class _TextCompositionWriter {
  /// Whether the destination story uses the original CS field names.
  final bool named;

  /// Whether actual font glyphs accompany the checked source positions.
  final bool glyphs;

  /// Remaining conservative allocation budget for the newly authored tree.
  int _remaining;

  /// Starts a writer bounded by the owning engine's node policy.
  _TextCompositionWriter({required this.named, required int maxNodes, required this.glyphs}) : _remaining = maxNodes;

  /// Bounds allocations before retaining line/segment lists and dictionaries.
  void reserve(int count) {
    if (_remaining < count) {
      throw const FormatException('Composed Illustrator layout exceeds the engine node limit.');
    }
    _remaining -= count;
  }

  /// Selects the destination's authored field spelling.
  String key(String compact, String name) => named ? name : compact;

  /// Encodes a checked coordinate array.
  PsEngineArray coordinates(List<double> values) => PsEngineArray(values: [for (final double value in values) PsEngineNumber(value: value)]);

  /// Creates a tagged node using the established transform/child wrappers.
  PsEngineDictionary node(String tag, String name, {List<PsEngineValue>? children, int? procession, double? x, double? y, Map<String, PsEngineValue> fields = const {}}) => PsEngineDictionary(
    values: {
      key('99', 'StreamTag'): PsEngineName(value: named ? name : tag),
      if (x != null && y != null)
        key('0', 'Transform'): PsEngineDictionary(
          values: {
            key('0', 'Origin'): coordinates([x, y]),
          },
        ),
      if (procession != null) key('5', 'Procession'): PsEngineNumber(value: procession),
      if (children != null) key('6', 'Children'): PsEngineArray(values: children),
      ...fields,
    },
  );

  /// Writes frame/row wrappers while keeping line origins frame-relative.
  PsEngineDictionary frame(AiNativeTextFrameLayout frame, List<PsEngineValue> lines) => node(
    'F',
    'FrameStrike',
    x: frame.x,
    y: frame.y,
    procession: 2,
    fields: {key('10', 'Frame'): PsEngineNumber(value: frame.frame.index)},
    children: [
      node('R', 'RowColStrike', children: [node('R', 'RowColStrike', procession: 2, children: lines)]),
    ],
  );

  /// Writes a line and its source mappings in the supplied visual order.
  PsEngineDictionary line(AiNativeTextLineLayout line) => node(
    'L',
    'LineStrike',
    x: line.x,
    y: line.y,
    fields: {
      if (line.ascent case final double ascent) key('14', 'SelectionAscent'): PsEngineNumber(value: -ascent),
      if (line.descent case final double descent) key('15', 'SelectionDescent'): PsEngineNumber(value: descent),
      if (line.bounds case final List<double> bounds) key('1', 'Bounds'): coordinates(bounds),
    },
    children: [
      for (final AiNativeTextSegmentLayout segment in line.segments)
        node(
          'S',
          'Segment',
          x: segment.x,
          y: segment.y,
          children: glyphs ? [for (final AiNativeTextGlyphLayout glyph in segment.glyphs) this.glyph(glyph)] : null,
          fields: {
            key('20', 'FirstCharacterIndexInSegment'): PsEngineNumber(value: segment.start),
            key('15', 'Mapping'): PsEngineDictionary(
              values: {
                key('0', 'CharacterCount'): PsEngineNumber(value: segment.end - segment.start),
                if (glyphs && (segment.end - segment.start != 1 || segment.glyphs.length != 1))
                  '1': PsEngineArray(
                    values: [
                      PsEngineDictionary(
                        values: {
                          '0': PsEngineNumber(value: segment.glyphs.length == 1 ? 1 : 2),
                          '1': PsEngineNumber(value: 0),
                          '2': PsEngineNumber(value: segment.glyphs.length == 1 ? segment.end - segment.start : segment.glyphs.length),
                        },
                      ),
                    ],
                  ),
                if (segment.automaticHyphen)
                  '1': PsEngineArray(
                    values: [
                      PsEngineDictionary(
                        values: {
                          '0': PsEngineNumber(value: 2),
                          '1': PsEngineNumber(value: segment.end - segment.start - 1),
                          '2': PsEngineNumber(value: 2),
                        },
                      ),
                    ],
                  ),
                key('2', 'GlyphCount'): PsEngineNumber(
                  value: segment.automaticHyphen
                      ? 1
                      : glyphs && segment.glyphs.length > 1
                      ? segment.glyphs.length - 1
                      : 0,
                ),
                key('5', 'WRValid'): PsEngineBoolean(value: segment.rightToLeft),
                if (segment.rightToLeft) '7': PsEngineDictionary(values: {'0': PsEngineNumber(value: segment.end - segment.start)}),
              },
            ),
          },
        ),
    ],
  );

  /// Encodes one explicit origin so native readers need not infer advances.
  PsEngineDictionary glyph(AiNativeTextGlyphLayout glyph) => node(
    'G',
    'GlyphStrike',
    x: glyph.x,
    y: glyph.y,
    fields: {
      '1': coordinates(glyph.bounds),
      '5': PsEngineArray(values: [PsEngineNumber(value: glyph.glyphId)]),
      if (glyph.pathBounds != null) '8': coordinates(glyph.pathBounds!),
      if (glyph.pathBounds != null) '24': PsEngineNumber(value: 0),
      '10': PsEngineDictionary(
        values: {
          '0': PsEngineArray(
            values: [
              PsEngineDictionary(
                values: {
                  '4': PsEngineNumber(value: glyph.font.index),
                  '9': PsEngineNumber(value: 0),
                  '10': PsEngineNumber(value: 0),
                },
              ),
            ],
          ),
          '1': PsEngineArray(values: [PsEngineNumber(value: 1)]),
        },
      ),
      if (glyph.paragraphMark) '11': const PsEngineBoolean(value: true),
      '12': PsEngineNumber(value: glyph.bounds[1]),
      '13': PsEngineNumber(value: glyph.bounds[3]),
      '20': PsEngineNumber(value: 0),
    },
  );
}
