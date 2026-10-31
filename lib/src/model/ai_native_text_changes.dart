part of 'ai_native_text.dart';

/// Character properties that can return to their inherited style value.
enum AiNativeCharacterFeature {
  /// Font resource selected by PostScript identity.
  font(compact: '0', named: 'Font'),

  /// Point size and its matching point-size reference.
  fontSize(compact: '1', named: 'FontSize'),

  /// Whether paragraph automatic leading controls line spacing.
  automaticLeading(compact: '4', named: 'AutoLeading'),

  /// Explicit baseline spacing in points.
  leading(compact: '5', named: 'Leading'),

  /// Horizontal glyph scale as a factor.
  horizontalScale(compact: '6', named: 'HorizontalScale'),

  /// Vertical glyph scale as a factor.
  verticalScale(compact: '7', named: 'VerticalScale'),

  /// Extra tracking in thousandths of an em.
  tracking(compact: '8', named: 'Tracking'),

  /// Upward baseline displacement in points.
  baselineShift(compact: '9', named: 'BaselineShift'),

  /// Counterclockwise character rotation in degrees.
  rotation(compact: '10', named: 'CharacterRotation'),

  /// Native kerning mode, including optical and font metrics modes.
  kerning(compact: '11', named: 'AutoKern'),

  /// Standard ligatures.
  ligatures(compact: '18', named: 'Ligatures'),

  /// Discretionary ligatures.
  discretionaryLigatures(compact: '19', named: 'DiscretionaryLigatures'),

  /// Contextual alternates.
  contextualAlternates(compact: '20', named: 'ContextualLigatures'),

  /// Old-style figures.
  oldStyleFigures(compact: '22', named: 'OldStyle'),

  /// Fraction substitutions.
  fractions(compact: '23', named: 'Fractions'),

  /// Ordinal substitutions.
  ordinals(compact: '24', named: 'Ordinals'),

  /// Swash substitutions.
  swash(compact: '25', named: 'Swash'),

  /// Titling substitutions.
  titling(compact: '26', named: 'Titling'),

  /// Stylistic alternates.
  stylisticAlternates(compact: '28', named: 'StylisticAlternates'),

  /// Ornament substitutions.
  ornaments(compact: '29', named: 'Ornaments'),

  /// Slashed zero substitutions.
  slashedZero(compact: '84', named: 'SlashedZero'),

  /// The complete mask of twenty OpenType stylistic sets.
  stylisticSets(compact: '85', named: 'StylisticSets');

  /// Compact CC field name.
  final String _compact;

  /// Named CS field name.
  final String _named;

  /// Associates both observed field spellings with one semantic property.
  const AiNativeCharacterFeature({
    required this._compact,
    required this._named,
  });
}

/// Paragraph properties that can return to their inherited style value.
enum AiNativeParagraphFeature {
  /// Native alignment/justification enumeration, from zero through six.
  justification(compact: '0', named: 'Justification'),

  /// First-line indentation in points, including hanging negative indents.
  firstLineIndent(compact: '1', named: 'FirstLineIndent'),

  /// Start indentation in points.
  startIndent(compact: '2', named: 'StartIndent'),

  /// End indentation in points.
  endIndent(compact: '3', named: 'EndIndent'),

  /// Space preceding a paragraph, in points.
  spaceBefore(compact: '4', named: 'SpaceBefore'),

  /// Space following a paragraph, in points.
  spaceAfter(compact: '5', named: 'SpaceAfter'),

  /// Automatic leading as a font-size factor.
  automaticLeading(compact: '7', named: 'AutoLeading'),

  /// Automatic word hyphenation.
  hyphenate(compact: '9', named: 'AutoHyphenate'),

  /// Single-line or every-line composition.
  everyLineComposer(compact: '29', named: 'EveryLineComposer'),

  /// Native direction: zero for left-to-right, one for right-to-left.
  direction(compact: '33', named: 'ParagraphDirection'),

  /// Native composer: zero for Latin, one for Middle Eastern.
  composer(compact: '35', named: 'ComposerEngine');

  /// Compact CC field name.
  final String _compact;

  /// Named CS field name.
  final String _named;

  /// Associates both observed field spellings with one semantic property.
  const AiNativeParagraphFeature({
    required this._compact,
    required this._named,
  });
}

/// Immutable character overrides for a source-owned text range.
///
/// Omitted arguments leave local features unchanged. [inherit] removes local
/// overrides only; named resource styles and other inherited layers are retained.
final class AiNativeCharacterChanges {
  /// Optional source-owned font; a foreign or stale resource is rejected.
  final AiNativeTextFont? font;

  /// Features explicitly returned to their inherited value.
  final Set<AiNativeCharacterFeature> inherit;

  /// Validated scalar overrides, independent of the destination key spelling.
  final Map<AiNativeCharacterFeature, PsEngineValue> _values;

  /// Creates point-size, spacing, scale and OpenType feature changes.
  ///
  /// [leading] also disables automatic leading unless explicitly enabled by
  /// [automaticLeading]. [stylisticSets] is a twenty-bit mask, with bit zero
  /// representing ss01. [kerning] retains the native mode 0–3; this API does
  /// not emulate optical kerning or produce shaped glyphs.
  AiNativeCharacterChanges({
    this.font,
    double? fontSize,
    bool? automaticLeading,
    double? leading,
    double? horizontalScale,
    double? verticalScale,
    double? tracking,
    double? baselineShift,
    double? rotation,
    int? kerning,
    bool? ligatures,
    bool? discretionaryLigatures,
    bool? contextualAlternates,
    bool? oldStyleFigures,
    bool? fractions,
    bool? ordinals,
    bool? swash,
    bool? titling,
    bool? stylisticAlternates,
    bool? ornaments,
    bool? slashedZero,
    int? stylisticSets,
    Set<AiNativeCharacterFeature> inherit = const {},
  }) : inherit = Set.unmodifiable(inherit),
       _values = Map.unmodifiable({
         if (fontSize != null) AiNativeCharacterFeature.fontSize: _featureNumber(fontSize, positive: true),
         if (automaticLeading != null || leading != null) AiNativeCharacterFeature.automaticLeading: PsEngineBoolean(value: automaticLeading ?? false),
         if (leading != null) AiNativeCharacterFeature.leading: _featureNumber(leading, nonnegative: true),
         if (horizontalScale != null) AiNativeCharacterFeature.horizontalScale: _featureNumber(horizontalScale, positive: true),
         if (verticalScale != null) AiNativeCharacterFeature.verticalScale: _featureNumber(verticalScale, positive: true),
         if (tracking != null) AiNativeCharacterFeature.tracking: _featureNumber(tracking),
         if (baselineShift != null) AiNativeCharacterFeature.baselineShift: _featureNumber(baselineShift),
         if (rotation != null) AiNativeCharacterFeature.rotation: _featureNumber(rotation),
         if (kerning != null) AiNativeCharacterFeature.kerning: _featureIndex(kerning, 3),
         if (ligatures != null) AiNativeCharacterFeature.ligatures: PsEngineBoolean(value: ligatures),
         if (discretionaryLigatures != null) AiNativeCharacterFeature.discretionaryLigatures: PsEngineBoolean(value: discretionaryLigatures),
         if (contextualAlternates != null) AiNativeCharacterFeature.contextualAlternates: PsEngineBoolean(value: contextualAlternates),
         if (oldStyleFigures != null) AiNativeCharacterFeature.oldStyleFigures: PsEngineBoolean(value: oldStyleFigures),
         if (fractions != null) AiNativeCharacterFeature.fractions: PsEngineBoolean(value: fractions),
         if (ordinals != null) AiNativeCharacterFeature.ordinals: PsEngineBoolean(value: ordinals),
         if (swash != null) AiNativeCharacterFeature.swash: PsEngineBoolean(value: swash),
         if (titling != null) AiNativeCharacterFeature.titling: PsEngineBoolean(value: titling),
         if (stylisticAlternates != null) AiNativeCharacterFeature.stylisticAlternates: PsEngineBoolean(value: stylisticAlternates),
         if (ornaments != null) AiNativeCharacterFeature.ornaments: PsEngineBoolean(value: ornaments),
         if (slashedZero != null) AiNativeCharacterFeature.slashedZero: PsEngineBoolean(value: slashedZero),
         if (stylisticSets != null) AiNativeCharacterFeature.stylisticSets: _featureIndex(stylisticSets, (1 << 20) - 1),
       }) {
    if (inherit.any(_values.containsKey) || font != null && inherit.contains(AiNativeCharacterFeature.font)) {
      throw ArgumentError('A character feature cannot be assigned and inherited in the same edit.');
    }
  }
}

/// Immutable paragraph overrides applied to every touched paragraph.
final class AiNativeParagraphChanges {
  /// Features explicitly returned to their inherited value.
  final Set<AiNativeParagraphFeature> inherit;

  /// Validated scalar overrides, independent of the destination key spelling.
  final Map<AiNativeParagraphFeature, PsEngineValue> _values;

  /// Creates paragraph spacing and composition changes using native enumerations.
  ///
  /// Direction and composer are independent. Assigning either does not silently
  /// alter the other. Unknown character defaults and other paragraph features
  /// remain in the source style, including advanced composition settings.
  AiNativeParagraphChanges({
    int? justification,
    double? firstLineIndent,
    double? startIndent,
    double? endIndent,
    double? spaceBefore,
    double? spaceAfter,
    double? automaticLeading,
    bool? hyphenate,
    bool? everyLineComposer,
    int? direction,
    int? composer,
    Set<AiNativeParagraphFeature> inherit = const {},
  }) : inherit = Set.unmodifiable(inherit),
       _values = Map.unmodifiable({
         if (justification != null) AiNativeParagraphFeature.justification: _featureIndex(justification, 6),
         if (firstLineIndent != null) AiNativeParagraphFeature.firstLineIndent: _featureNumber(firstLineIndent),
         if (startIndent != null) AiNativeParagraphFeature.startIndent: _featureNumber(startIndent),
         if (endIndent != null) AiNativeParagraphFeature.endIndent: _featureNumber(endIndent),
         if (spaceBefore != null) AiNativeParagraphFeature.spaceBefore: _featureNumber(spaceBefore, nonnegative: true),
         if (spaceAfter != null) AiNativeParagraphFeature.spaceAfter: _featureNumber(spaceAfter, nonnegative: true),
         if (automaticLeading != null) AiNativeParagraphFeature.automaticLeading: _featureNumber(automaticLeading, positive: true),
         if (hyphenate != null) AiNativeParagraphFeature.hyphenate: PsEngineBoolean(value: hyphenate),
         if (everyLineComposer != null) AiNativeParagraphFeature.everyLineComposer: PsEngineBoolean(value: everyLineComposer),
         if (direction != null) AiNativeParagraphFeature.direction: _featureIndex(direction, 1),
         if (composer != null) AiNativeParagraphFeature.composer: _featureIndex(composer, 1),
       }) {
    if (inherit.any(_values.containsKey)) {
      throw ArgumentError('A paragraph feature cannot be assigned and inherited in the same edit.');
    }
  }
}

/// Validates finite scalar values before retaining a patch.
PsEngineNumber _featureNumber(double value, {bool positive = false, bool nonnegative = false}) {
  if (!value.isFinite || positive && value <= 0 || nonnegative && value < 0) {
    throw ArgumentError.value(value, 'value', 'Invalid Illustrator text feature value.');
  }
  return PsEngineNumber(value: value);
}

/// Validates bounded native enumerations and bit masks.
PsEngineNumber _featureIndex(int value, int maximum) {
  if (value < 0 || value > maximum) {
    throw RangeError.range(value, 0, maximum, 'value');
  }
  return PsEngineNumber(value: value);
}
