part of 'package:illustratorkit/src/model/ai_native_records.dart';

/// Explicit native mask flags, independent of the mask's grayscale artwork.
final class AiNativeOpacityMaskSettings {
  /// Whether the mask follows transformations of its owning artwork.
  final bool linked;

  /// Whether the saved mask is disabled without discarding its artwork.
  final bool disabled;

  /// Native clipping flag, retained without synthesizing background pixels.
  final bool clipping;

  /// Whether the host should invert the mask's resulting opacity.
  final bool inverted;

  /// Requires every saved flag instead of inferring Illustrator defaults.
  const AiNativeOpacityMaskSettings({required this.linked, required this.disabled, required this.clipping, required this.inverted});

  /// Native dictionary keys and their explicit Boolean values.
  Map<String, bool> get _values => {'Linked': linked, 'Disabled': disabled, 'Clipping': clipping, 'Inverted': inverted};
}

/// Source-backed opacity-mask fields without flattening or composing the artwork.
///
/// Decoding validates the literal fields and X=/X+ boundaries. Artwork remains
/// preserved data until an owning appearance qualifies it for a transaction.
final class AiNativeOpacityMask {
  /// Serializes editable literal paints and paths/groups for a mask's complete Art payload.
  ///
  /// The result includes `X=`/`X+`; only subsequent lines receive private prefixes
  /// when [private] is true. Attach it through mask creation/update together with
  /// complete host-composed printing and matching PDF. Group clips are supported;
  /// named applications and XML identities require separate reference contracts.
  /// This method preserves colors and opacity without evaluating mask coverage.
  static Uint8List encodeVectorArtwork({
    required AiNativeRecords records,
    required List<AiNativeAppearanceElementDefinition> elements,
    bool private = true,
  }) => _createdNativeLocalArtwork(records, elements, private, mask: true);

  /// Native source snapshot owning the mask and its exact source offsets.
  final AiNativeRecords records;

  /// Original /Mask container, including private prefixes and binary payloads.
  final AiNativeContainer record;

  /// Parsed dictionary fields retaining their original source positions.
  final AiNativeContainer _fields;

  /// Explicit flags read from this immutable source.
  final AiNativeOpacityMaskSettings settings;

  /// Complete Art field including its two literal boundary commands.
  final AiNativeEntry artwork;

  /// Reads one exact owned mask without qualifying unknown artwork as editable.
  factory AiNativeOpacityMask.decode({required AiNativeRecords records, required AiNativeContainer record}) {
    if (!records._ownedContainers.contains(record) || record.type != 'Mask') {
      throw ArgumentError('An opacity mask requires a current owned Mask record.');
    }
    final AiNativeContainer fields = _nativeOpacityMaskFields(record);
    final AiNativeEntry artwork = fields['Art']!;
    final AiNativeItem first = artwork.items.first;
    final AiNativeItem last = artwork.items.last;
    if (first is! AiNativeToken ||
        last is! AiNativeToken ||
        first.token.lexeme != 'X=' ||
        last.token.lexeme != 'X+' ||
        first.token.kind != .executableName ||
        last.token.kind != .executableName ||
        records._projection.isPrivate(first.start) != records._projection.isPrivate(last.start)) {
      throw const FormatException('Opacity masks require matching literal X=/X+ artwork boundaries.');
    }
    return AiNativeOpacityMask._(
      records: records,
      record: record,
      fields: fields,
      artwork: artwork,
      settings: AiNativeOpacityMaskSettings(linked: fields['Linked']!.boolean!, disabled: fields['Disabled']!.boolean!, clipping: fields['Clipping']!.boolean!, inverted: fields['Inverted']!.boolean!),
    );
  }

  /// Retains source fields without copying or interpreting binary samples.
  AiNativeOpacityMask._({required this.records, required this.record, required this._fields, required this.settings, required this.artwork});

  /// Qualified vector/group/image syntax for host composition, without rendering.
  ///
  /// Raster items retain their samples and placement. Nested mask dictionaries
  /// remain attached source metadata. Unknown commands, named dependencies or
  /// conditional data throw; the raw artworkBytes remain available for preservation.
  late final AiNativeDrawing artworkDrawing = _nativeOpacityMaskDrawing(records, record);

  /// Exact source artwork, including X=/X+ and intervening private prefixes.
  Uint8List get artworkBytes => Uint8List.sublistView(records.program.bytes, artwork.items.first.start, artwork.items.last.end).asUnmodifiableView();
}

/// A mask update covered by its complete host-composed printing owner.
final class AiNativeOpacityMaskChange {
  /// Exact mask handle obtained from the selected artwork's opacityMasks.
  final AiNativeOpacityMask mask;

  /// Complete replacement flags; null retains all original flags.
  final AiNativeOpacityMaskSettings? settings;

  /// Optional replacement Art bytes including X=/X+ in the source representation.
  final Uint8List? _artworkBytes;

  /// Freezes explicit changes before offsets or printing ownership can change.
  AiNativeOpacityMaskChange({required this.mask, this.settings, List<int>? artworkBytes}) : _artworkBytes = artworkBytes == null ? null : Uint8List.fromList(artworkBytes) {
    if (settings == null && artworkBytes == null || artworkBytes?.any((byte) => byte < 0 || byte > 255) == true) {
      throw ArgumentError('Mask changes require explicit settings or byte artwork.');
    }
    if ((artworkBytes?.length ?? 0) > mask.records.program.limits.maxDecodedBytes) {
      throw const AiLimitException(message: 'Mask artwork exceeds native output limits.');
    }
  }

  /// Immutable host-supplied native artwork, or null to preserve it byte for byte.
  Uint8List? get artworkBytes => _artworkBytes?.asUnmodifiableView();
}

/// A new mask attached to one current private appearance object.
///
/// The host supplies complete native X=/X+ artwork and the owner's separately
/// composed printing replacement. Binary payloads are copied without rewriting
/// their private prefixes or interpreting their samples.
final class AiNativeOpacityMaskAttachment {
  /// Complete appearance owner whose printing group must be replaced.
  final AiNativeAppearanceArtwork artwork;

  /// Exact private path or group receiving the mask.
  final AiNativeItem target;

  /// Explicit native flags, including disabled and unlinked masks.
  final AiNativeOpacityMaskSettings settings;

  /// Frozen complete Art field in the native source representation.
  final Uint8List _artworkBytes;

  /// Defaults to the outer authoring object; children require exact handles.
  AiNativeOpacityMaskAttachment({required this.artwork, AiNativeItem? target, required this.settings, required List<int> artworkBytes})
    : target = target ?? artwork.authoring,
      _artworkBytes = _copyArtwork(artwork, artworkBytes);

  /// Bounds the allocation before copying caller-owned source bytes.
  static Uint8List _copyArtwork(AiNativeAppearanceArtwork artwork, List<int> bytes) {
    if (bytes.length > artwork._owner.structure.drawing.records.program.limits.maxDecodedBytes) {
      throw const AiLimitException(message: 'New mask artwork exceeds native output limits.');
    }
    if (bytes.isEmpty || bytes.any((byte) => byte < 0 || byte > 255)) {
      throw ArgumentError('New masks require complete byte artwork.');
    }
    return Uint8List.fromList(bytes);
  }

  /// Immutable host-supplied artwork including literal X=/X+ boundaries.
  Uint8List get artworkBytes => _artworkBytes.asUnmodifiableView();
}

/// Parses Mask suffix keys using the existing Dictionary field grammar.
AiNativeContainer _nativeOpacityMaskFields(AiNativeContainer source) {
  if (source.hasBinary || source.entries.any((entry) => entry.key != null || entry.type != null || entry.isQualifier || entry.items.isEmpty)) {
    throw UnsupportedError('Opacity masks require literal dictionary fields.');
  }
  final AiNativeContainer fields = AiNativeContainer._(
    start: source.start,
    end: source.end,
    type: source.type,
    entries: source.entries.map((entry) => _NativeRecordReader._entry(type: 'Dictionary', items: entry.items)).toList(),
  );
  _referenceFields(
    fields,
    {
      'Bool': {'Linked', 'Disabled', 'Clipping', 'Inverted'},
    },
    nested: {
      'Art': (entry) {
        if (entry.type != null || entry.items.length < 2) {
          throw const FormatException('Opacity masks require a complete artwork field.');
        }
      },
    },
  );
  if (fields.entries.length != 5 || fields['Art'] == null) {
    throw UnsupportedError('Opacity masks require artwork and all four flags.');
  }
  return fields;
}
