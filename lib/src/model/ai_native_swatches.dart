part of 'package:aikit/src/model/ai_native_records.dart';

/// A source-owned palette cell, distinct from artwork using the same color.
final class AiNativeSwatch extends AiNativeItem {
  /// Exact paint commands, including unsupported retained cell paints.
  final List<AiNativeInstruction> commands;

  /// Explicit display-name bytes, or null for an unnamed source cell.
  final Uint8List? nameBytes;

  /// Captures a complete cell through its Pc terminator.
  AiNativeSwatch._({required super.start, required super.end, required List<AiNativeInstruction> commands, required this.nameBytes}) : commands = List.unmodifiable(commands);

  /// Named ink for a single literal color cell, without converting tint semantics.
  AiNativeNamedColor? get namedColor => commands.length == 1 ? AiNativeNamedColor.decode(instruction: commands.single) : null;

  /// Source gradient reference for this cell, independently of its display name.
  AiNativeGradient? get gradient => commands.isNotEmpty && commands.first.operator == 'Bb' ? _readNativeGradients(instructions: commands, paths: []).single : null;

  /// Literal process/named paint data for a single color cell.
  AiNativePaintAssignment? get color => commands.length == 1 ? _nativePaintAssignments(commands).singleOrNull : null;
}

/// One complete ordinary palette, retaining group boundaries and cell order.
final class AiNativePalette extends AiNativeItem {
  /// Opening Pb command retaining native palette indices.
  final AiNativeInstruction opening;

  /// Closing PB command used for append-only creation in the final group.
  final AiNativeInstruction closing;

  /// Source cells in their authored order.
  final List<AiNativeSwatch> swatches;

  /// Whether saved alternative branches prevent unconditional mutation.
  final bool conditional;

  /// Freezes source-owned cells and palette boundary commands.
  AiNativePalette._({required super.start, required super.end, required this.opening, required this.closing, required List<AiNativeSwatch> swatches, required this.conditional})
    : swatches = List.unmodifiable(swatches);
}

/// Bounded palette color/gradient creation and source-preserving cell removal.
final class AiNativeSwatches {
  /// Immutable native source owning every palette and cell handle.
  final AiNativeRecords records;

  /// Complete palettes; unknown paints stay inspectable without becoming editable.
  final List<AiNativePalette> palettes;

  /// Reads ordinary palettes without evaluating private paint programs.
  factory AiNativeSwatches.decode({required AiNativeRecords records}) => AiNativeSwatches._(records: records, palettes: _readNativePalettes(records));

  /// Captures immutable palette inventory.
  AiNativeSwatches._({required this.records, required List<AiNativePalette> palettes}) : palettes = List.unmodifiable(palettes);

  /// Creates a process-color cell; dual RGB alternatives are always explicit.
  ///
  /// With no existing palette, one ordinary palette is created. Otherwise select
  /// a palette when several exist. Appending retains the last native group; an
  /// explicit before handle inserts within that cell's group. Artwork is unchanged.
  AiNativeSwatches createProcess({required List<int> nameBytes, required AiColor color, AiColor? cmykAlternative, AiNativePalette? palette, AiNativeSwatch? before}) {
    if (cmykAlternative != null && (color.space != .rgb || cmykAlternative.space != .cmyk)) {
      throw ArgumentError('A dual palette color requires RGB and its explicit CMYK alternative.');
    }
    final String operator = switch (color.space) {
      .gray => 'g',
      .rgb => 'Xa',
      .cmyk => 'k',
    };
    return _createNativeSwatch(this, nameBytes, latin1.encode('${[...?cmykAlternative?.channels, ...color.channels].join(' ')} $operator'), palette, before);
  }

  /// Creates a named-ink cell without rewriting any existing artwork application.
  AiNativeSwatches createNamed({required List<int> nameBytes, required AiNativeNamedColor color, AiNativePalette? palette, AiNativeSwatch? before}) {
    if (records._projection.tokens.any((token) => const {AiTokenKind.string, AiTokenKind.hexString}.contains(token.kind) && _sameNativeBytes(aiStringBytes(token), color.nameBytes))) {
      throw ArgumentError('A new named-ink cell requires an unused ink identity; existing references cannot be redefined implicitly.');
    }
    return _createNativeSwatch(this, nameBytes, color._bytes(stroke: false, limit: records.program.limits.maxDecodedBytes), palette, before);
  }

  /// Adds a palette reference to an existing gradient in the same snapshot.
  AiNativeSwatches createGradient({required List<int> nameBytes, required AiNativeGradientDefinition definition, AiNativePalette? palette, AiNativeSwatch? before}) {
    if (!records._projection.tokens.contains(definition.opening.token)) {
      throw ArgumentError('A gradient swatch requires a current resource handle.');
    }
    final List<int> name = _nativeLiteralString(definition.nameBytes, records.program.limits.maxDecodedBytes);
    return _createNativeSwatch(this, nameBytes, [...latin1.encode('Bb\n2 '), ...name, ...latin1.encode(' 0 0 0 1 1 0 0 1 0 0 1 Bg\n0 BB')], palette, before);
  }

  /// Removes explicit cells, retaining palette groups, other cells and artwork.
  ///
  /// Referenced named inks reject; removal does not detach or recolor their
  /// applications. A gradient cell may be removed while its resource remains.
  /// Remove the now-unused global gradient separately when desired.
  AiNativeSwatches remove({required List<AiNativeSwatch> swatches}) => _removeNativeSwatches(this, swatches);
}
