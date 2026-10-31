part of 'ai_native_text.dart';

/// Resolved native feature layers, from inherited defaults to local overrides.
sealed class AiNativeTextFeatures {
  /// Source dictionaries in increasing priority, retaining every unknown feature.
  final List<PsEngineDictionary> layers;

  /// Retains immutable source-backed feature dictionaries.
  AiNativeTextFeatures._({
    required List<PsEngineDictionary> layers,
  }) : layers = List.unmodifiable(layers);

  /// Looks up an established compact/named feature pair across inherited layers.
  PsEngineValue? value({required String compactKey, required String namedKey}) {
    for (final PsEngineDictionary layer in layers.reversed) {
      final PsEngineValue? result = _field(layer, compactKey, namedKey);
      if (result != null) {
        return result;
      }
    }
    return null;
  }

  /// Reads a finite numeric feature without coercing another native value type.
  double? number({required String compactKey, required String namedKey}) => _number(value(compactKey: compactKey, namedKey: namedKey));

  /// Reads a native Boolean feature without inventing a default.
  bool? boolean({required String compactKey, required String namedKey}) => switch (value(compactKey: compactKey, namedKey: namedKey)) {
    null => null,
    PsEngineBoolean(:final bool value) => value,
    _ => throw const FormatException('Expected Illustrator text feature Boolean.'),
  };
}

/// Character features after resolving normal, paragraph and explicit styles.
final class AiNativeCharacterStyle extends AiNativeTextFeatures {
  /// Document font resources used to resolve an explicit font reference.
  final List<AiNativeTextFont> _fonts;

  /// Retains resolved layers and their owning font table.
  AiNativeCharacterStyle._({
    required super.layers,
    required this._fonts,
  }) : super._();

  /// Font resource index, or null when the native model supplies no font.
  int? get fontIndex => _optionalIndex(value(compactKey: '0', namedKey: 'Font'));

  /// Referenced font resource; a dangling index is rejected explicitly.
  AiNativeTextFont? get font {
    final int? index = fontIndex;
    if (index == null) {
      return null;
    }
    if (index >= _fonts.length) {
      throw const FormatException('Missing Illustrator character-style font.');
    }
    return _fonts[index];
  }

  /// Native point size, without applying horizontal or vertical scale.
  double? get fontSize => number(compactKey: '1', namedKey: 'FontSize');

  /// Whether paragraph automatic leading supplies baseline spacing.
  bool? get automaticLeading => boolean(compactKey: '4', namedKey: 'AutoLeading');

  /// Explicit baseline spacing in points, subject to [automaticLeading].
  double? get leading => number(compactKey: '5', namedKey: 'Leading');

  /// Saved size reference; its unit interpretation depends on [fontSizeReferenceType].
  double? get fontSizeReference => number(compactKey: '89', namedKey: 'RefFontSize');

  /// Native size reference mode; zero denotes the point-size reference.
  int? get fontSizeReferenceType => _optionalIndex(value(compactKey: '90', namedKey: 'FontSizeRefType'));

  /// Horizontal glyph scale as a factor, not a percentage.
  double? get horizontalScale => number(compactKey: '6', namedKey: 'HorizontalScale');

  /// Vertical glyph scale as a factor, not a percentage.
  double? get verticalScale => number(compactKey: '7', namedKey: 'VerticalScale');

  /// Native character tracking value.
  double? get tracking => number(compactKey: '8', namedKey: 'Tracking');

  /// Native baseline displacement in points.
  double? get baselineShift => number(compactKey: '9', namedKey: 'BaselineShift');

  /// Native character rotation in degrees.
  double? get rotation => number(compactKey: '10', namedKey: 'CharacterRotation');

  /// Kerning mode retained as its native enumeration value.
  int? get kerningMode => _optionalIndex(value(compactKey: '11', namedKey: 'AutoKern'));

  /// Explicit OpenType switches established for ATE character styles.
  ///
  /// Missing values remain absent so the shaping host can apply its font policy.
  /// Native optical kerning, synthetic styles and figure-position enums require
  /// additional composition logic and are not approximated by these switches.
  Map<String, int> get openTypeFeatures {
    final Map<String, int> result = {};
    for (final (String key, String name, String tag) in [
      ('18', 'Ligatures', 'liga'),
      ('19', 'DiscretionaryLigatures', 'dlig'),
      ('20', 'ContextualLigatures', 'calt'),
      ('22', 'OldStyle', 'onum'),
      ('23', 'Fractions', 'frac'),
      ('24', 'Ordinals', 'ordn'),
      ('25', 'Swash', 'swsh'),
      ('26', 'Titling', 'titl'),
      ('28', 'StylisticAlternates', 'salt'),
      ('29', 'Ornaments', 'ornm'),
      ('84', 'SlashedZero', 'zero'),
    ]) {
      final bool? enabled = boolean(compactKey: key, namedKey: name);
      if (enabled != null) {
        result[tag] = enabled ? 1 : 0;
      }
    }
    final int? sets = _optionalIndex(value(compactKey: '85', namedKey: 'StylisticSets'));
    if (sets != null) {
      if (sets >= 1 << 20) {
        throw const FormatException('Unsupported Illustrator stylistic-set mask.');
      }
      for (int bit = 0; bit < 20; bit++) {
        result['ss${(bit + 1).toString().padLeft(2, '0')}'] = (sets >> bit) & 1;
      }
    }
    return Map.unmodifiable(result);
  }
}

/// Paragraph features after resolving normal styles, parents and local overrides.
final class AiNativeParagraphStyle extends AiNativeTextFeatures {
  /// Retains inherited feature layers without flattening unknown settings.
  AiNativeParagraphStyle._({
    required super.layers,
  }) : super._();

  /// Native paragraph alignment and justification enumeration.
  int? get justification => _optionalIndex(value(compactKey: '0', namedKey: 'Justification'));

  /// Inherited character-default dictionaries in increasing priority.
  ///
  /// A child paragraph's partial character defaults retain unrelated inherited
  /// character features instead of replacing the complete parent dictionary.
  List<PsEngineDictionary> get defaultCharacterLayers => List.unmodifiable([
    for (final PsEngineDictionary layer in layers)
      if (_optionalDictionary(_field(layer, '32', 'DefaultStyle')) case final PsEngineDictionary defaults) defaults,
  ]);

  /// Native paragraph direction enumeration.
  int? get direction => _optionalIndex(value(compactKey: '33', namedKey: 'ParagraphDirection'));

  /// Native composer, independent of paragraph direction.
  int? get composer => _optionalIndex(value(compactKey: '35', namedKey: 'ComposerEngine'));

  /// First-line indentation in points.
  double? get firstLineIndent => number(compactKey: '1', namedKey: 'FirstLineIndent');

  /// Start indentation in points.
  double? get startIndent => number(compactKey: '2', namedKey: 'StartIndent');

  /// End indentation in points.
  double? get endIndent => number(compactKey: '3', namedKey: 'EndIndent');

  /// Space preceding a paragraph, in points.
  double? get spaceBefore => number(compactKey: '4', namedKey: 'SpaceBefore');

  /// Space following a paragraph, in points.
  double? get spaceAfter => number(compactKey: '5', namedKey: 'SpaceAfter');

  /// Automatic leading as a font-size factor.
  double? get automaticLeading => number(compactKey: '7', namedKey: 'AutoLeading');

  /// Whether automatic word hyphenation is enabled.
  bool? get hyphenate => boolean(compactKey: '9', namedKey: 'AutoHyphenate');

  /// Whether every-line rather than single-line composition is selected.
  bool? get everyLineComposer => boolean(compactKey: '29', namedKey: 'EveryLineComposer');
}

/// A text range split at both character-style and paragraph-style boundaries.
final class AiNativeStyledTextRange {
  /// Inclusive UTF-16 code-unit offset, including the model's final paragraph mark.
  final int start;

  /// Exclusive UTF-16 code-unit offset.
  final int end;

  /// Effective character features at every position in this range.
  final AiNativeCharacterStyle characterStyle;

  /// Effective paragraph features at every position in this range.
  final AiNativeParagraphStyle paragraphStyle;

  /// Creates an immutable range resolved against one document snapshot.
  const AiNativeStyledTextRange._({
    required this.start,
    required this.end,
    required this.characterStyle,
    required this.paragraphStyle,
  });
}

/// Resolves native text features while preserving source dictionaries and keys.
extension AiNativeTextStyles on AiNativeTextDocument {
  /// Character style used when a story omits its explicit style-run table.
  int? get normalCharacterStyleIndex => _optionalIndex(_at(engine.root, [('1', 'DocumentObjects'), ('0', 'DocumentSettings'), ('1', 'NormalStyleSheet')]));

  /// Paragraph style used when a story omits its explicit paragraph-run table.
  int? get normalParagraphStyleIndex => _optionalIndex(_at(engine.root, [('1', 'DocumentObjects'), ('0', 'DocumentSettings'), ('2', 'NormalParagraphSheet')]));

  /// Resolves character inheritance for one source-owned UTF-16 position.
  AiNativeCharacterStyle characterStyleAt({required AiNativeTextStory story, required int offset}) {
    _checkPosition(story, offset);
    final List<PsEngineDictionary> normal = _styleLayers(kind: .character, selection: null);
    final AiNativeParagraphStyle paragraph = paragraphStyleAt(story: story, offset: offset);
    final PsEngineValue? selected = _runAt(story.characterRuns, offset)?.style;
    final List<PsEngineDictionary> explicit = selected == null ? const [] : _styleLayers(kind: .character, selection: selected);
    int shared = 0;
    while (shared < normal.length && shared < explicit.length && identical(normal[shared], explicit[shared])) {
      shared++;
    }
    return AiNativeCharacterStyle._(layers: [...normal, ...paragraph.defaultCharacterLayers, ...explicit.skip(shared)], fonts: fonts);
  }

  /// Resolves paragraph inheritance for one source-owned UTF-16 position.
  AiNativeParagraphStyle paragraphStyleAt({required AiNativeTextStory story, required int offset}) {
    _checkPosition(story, offset);
    return AiNativeParagraphStyle._(
      layers: _styleLayers(kind: .paragraph, selection: _runAt(story.paragraphRuns, offset)?.style),
    );
  }

  /// Returns all effective ranges, splitting at both source run tables.
  List<AiNativeStyledTextRange> styledRanges({required AiNativeTextStory story}) {
    _checkPosition(story, 0);
    final List<int> boundaries = {
      0,
      story.modelText.length,
      for (final AiNativeTextRun run in [...story.characterRuns, ...story.paragraphRuns]) run.end,
    }.toList()..sort();
    return List.unmodifiable([
      for (int index = 0; index + 1 < boundaries.length; index++)
        AiNativeStyledTextRange._(
          start: boundaries[index],
          end: boundaries[index + 1],
          characterStyle: characterStyleAt(story: story, offset: boundaries[index]),
          paragraphStyle: paragraphStyleAt(story: story, offset: boundaries[index]),
        ),
    ]);
  }

  /// Rejects stale story handles and positions outside the model string.
  void _checkPosition(AiNativeTextStory story, int offset) {
    if (!stories.contains(story)) {
      throw ArgumentError('Foreign Illustrator text story.');
    }
    if (offset < 0 || offset >= story.modelText.length) {
      throw RangeError.range(offset, 0, story.modelText.length - 1, 'offset');
    }
  }

  /// Resolves a bounded parent chain, then applies the local feature dictionary.
  List<PsEngineDictionary> _styleLayers({required AiNativeTextStyleKind kind, required PsEngineValue? selection}) {
    final List<AiNativeTextStyle> styles = kind == .character ? characterStyles : paragraphStyles;
    final int? normal = kind == .character ? normalCharacterStyleIndex : normalParagraphStyleIndex;
    final PsEngineDictionary? local = selection is PsEngineDictionary ? selection : null;
    int? index = selection is PsEngineNumber ? _index(selection) : _optionalIndex(_field(local, kind == .character ? '5' : '6', 'Parent')) ?? normal;
    final Set<int> visited = {};
    final List<PsEngineDictionary> layers = [];
    while (index != null) {
      if (index >= styles.length || !visited.add(index) || visited.length > engine.limits.maxDepth) {
        throw const FormatException('Missing, cyclic or excessive Illustrator text style inheritance.');
      }
      final AiNativeTextStyle style = styles[index];
      if (style.features case final PsEngineDictionary features) {
        layers.add(features);
      }
      index = style.parentIndex ?? (index == normal ? null : normal);
    }
    final PsEngineDictionary? features = _optionalDictionary(_field(local, kind == .character ? '6' : '5', 'Features'));
    return [...layers.reversed, ?features];
  }
}

/// Finds a run in logarithmic time without treating an absent table as corruption.
AiNativeTextRun? _runAt(List<AiNativeTextRun> runs, int offset) {
  int low = 0;
  int high = runs.length;
  while (low < high) {
    final int middle = (low + high) ~/ 2;
    final AiNativeTextRun run = runs[middle];
    if (offset < run.start) {
      high = middle;
    } else if (offset >= run.end) {
      low = middle + 1;
    } else {
      return run;
    }
  }
  return null;
}

/// Reads a finite native number without guessing a default.
double? _number(PsEngineValue? value) => switch (value) {
  null => null,
  PsEngineNumber(:final value) => value.toDouble(),
  _ => throw const FormatException('Expected Illustrator text-engine number.'),
};
