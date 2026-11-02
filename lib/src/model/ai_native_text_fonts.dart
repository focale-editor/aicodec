part of 'ai_native_text.dart';

/// Technologies recognized by Illustrator's native CoolType font identifier.
enum AiNativeFontTechnology {
  /// PostScript outlines, including OpenType CFF faces.
  postScript,

  /// TrueType outlines, including OpenType TrueType faces.
  trueType,
}

/// Host-supplied font identity, without embedding or loading a font program.
final class AiNativeFontDefinition {
  /// Actual PostScript name of the face or variable instance used for shaping.
  final String postScriptName;

  /// Outline technology of the supplied face, without guessing from its name.
  final AiNativeFontTechnology technology;

  /// Optional font-authored version string, without inventing one when absent.
  final String? version;

  /// Signed 16.16 variation coordinates, in the font's own axis order.
  ///
  /// Axis tags and defaults must be resolved by the host from the font program.
  /// These are fixed-point integers, not point sizes or normalized percentages.
  final List<int> axisCoordinates;

  /// Owns a checked font identity suitable for appending a native resource.
  AiNativeFontDefinition({required this.postScriptName, required this.technology, this.version, List<int> axisCoordinates = const []}) : axisCoordinates = List.unmodifiable(axisCoordinates) {
    if (postScriptName.isEmpty || postScriptName.codeUnits.any((unit) => unit < 33 || unit > 126 || '[](){}<>/%'.codeUnits.contains(unit))) {
      throw ArgumentError('Use the font face\'s printable PostScript name without whitespace or delimiters.');
    }
    if (version != null) {
      _editableText(version!);
      if (version!.contains('\u0000') || version!.contains('\r') || version!.contains('\u0003')) {
        throw ArgumentError('Invalid Illustrator font version string.');
      }
    }
    if (axisCoordinates.any((value) => value < -0x80000000 || value > 0x7fffffff)) {
      throw ArgumentError('Illustrator font axes must fit signed 16.16 coordinates.');
    }
  }
}

/// Appends native font identities without renumbering existing text resources.
extension AiNativeTextFontEditing on AiNativeTextDocument {
  /// Appends [font] and returns a snapshot with the new resource in `fonts.last`.
  ///
  /// Existing font indices, stories, styles and caches remain unchanged. A stored
  /// display list receives the new index; an omitted list remains omitted. Each
  /// call adds a distinct resource, even when names match: versions, variation
  /// coordinates and unmodeled existing metadata must not be conflated by name.
  ///
  /// Use the returned snapshot's font and story with [setCharacterFeatures] to
  /// assign it. The host must provide the matching font program for composition
  /// and PDF output. This does not install fonts, embed their bytes or generate
  /// glyphs.
  AiNativeTextDocument addFont({required AiNativeFontDefinition font}) {
    for (final String value in [font.postScriptName, if (font.version != null) font.version!]) {
      if (value.length > (engine.limits.maxStringBytes - 2) ~/ 2 || value.length > (engine.limits.maxBytes - 2) ~/ 2) {
        throw const FormatException('Illustrator font identity exceeds the engine string limit.');
      }
    }
    if (font.axisCoordinates.length > engine.limits.maxNodes - 16) {
      throw const FormatException('Illustrator font axes exceed the engine node limit.');
    }
    final PsEngineDictionary root = _dictionary(engine.root);
    final PsEngineDictionary resources = _dictionary(_field(root, '0', 'DocumentResources'));
    final PsEngineDictionary? previous = _optionalDictionary(_field(resources, '1', 'FontSet'));
    final PsEngineDictionary fontSet = previous ?? PsEngineDictionary(values: {});
    final bool named = root.values.containsKey('DocumentResources');
    final String resourceKey = _featureKey(fontSet, '0', 'Resources', named);
    final String displayKey = _featureKey(fontSet, '1', 'DisplayList', named);
    final PsEngineValue? display = fontSet[displayKey];
    if (display != null) {
      for (final PsEngineValue entry in _array(display)) {
        if (_index(_field(_dictionary(entry), '0', 'Resource')) >= fonts.length) {
          throw const FormatException('Invalid Illustrator font display-list reference.');
        }
      }
    }
    final PsEngineDictionary wrapper = PsEngineDictionary(
      values: {
        named ? 'Resource' : '0': PsEngineDictionary(
          values: {
            named ? 'StreamTag' : '99': const PsEngineName(value: 'CoolTypeFont'),
            named ? 'UUID' : '97': PsEngineString(bytes: _TextIdentifiers(engine: engine).next().codeUnits),
            named ? 'Identifier' : '0': PsEngineDictionary(
              values: {
                named ? 'Name' : '0': PsEngineString.fromText(text: font.postScriptName),
                named ? 'Type' : '2': PsEngineNumber(value: font.technology.index),
                if (font.version case final String version) named ? 'VersionString' : '5': PsEngineString.fromText(text: version),
                if (font.axisCoordinates.isNotEmpty) named ? 'MMAxis' : '4': PsEngineArray(values: [for (final int coordinate in font.axisCoordinates) PsEngineNumber(value: coordinate)]),
              },
            ),
          },
        ),
      },
    );
    final PsEngineDictionary changed = PsEngineDictionary(
      values: {
        ...fontSet.values,
        resourceKey: PsEngineArray(values: [..._array(fontSet[resourceKey]), wrapper]),
        if (display != null)
          displayKey: PsEngineArray(
            values: [
              ..._array(display),
              PsEngineDictionary(values: {named ? 'Resource' : '0': PsEngineNumber(value: fonts.length)}),
            ],
          ),
      },
    );
    final AiNativeTextDocument appended = _withEngine(
      engine.replaceValues(
        replacements: {
          if (previous != null) previous: changed else resources: PsEngineDictionary(values: {...resources.values, _featureKey(resources, '1', 'FontSet', named): changed}),
        },
      ),
    );
    final AiProgram program = appended.records.program;
    final List<AiToken> tokens = AiPostScript.tokenize(program.bytes, maxBytes: program.limits.maxDecodedBytes, maxTokens: program.limits.maxTokens, maxDepth: program.limits.maxDepth);
    // Complete document producers declare every newly required face. Fragments
    // without a DSC header retain their existing namespace-only behavior.
    if (!tokens.any((token) => token.kind == .comment && token.lexeme == '%%EndComments' && token.start < program.bodyStart)) {
      return appended;
    }
    final List<AiSourceEdit> headers = _initialTextFontHeaders(tokens, font.postScriptName, program.bodyStart);
    return headers.isEmpty
        ? appended
        : AiNativeTextDocument.decode(
            records: AiNativeRecords.decode(
              program: AiNativeEditor.apply(program: program, edits: headers),
            ),
            limits: engine.limits,
          );
  }
}

/// Requires the native signed fixed-point representation without rounding it.
int _fontAxisCoordinate(PsEngineValue value) {
  if (value is! PsEngineNumber || value.value < -0x80000000 || value.value > 0x7fffffff || value.value != value.value.truncateToDouble()) {
    throw const FormatException('Invalid Illustrator font axis coordinate.');
  }
  return value.value.toInt();
}
