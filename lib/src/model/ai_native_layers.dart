part of 'package:aicodec/src/model/ai_native_records.dart';

/// An empty native layer with an explicitly supplied qualified header layout.
///
/// The ten-, thirteen- and fourteen-operand `Lb` layouts are supported. Supply
/// actual header attributes rather than inferring a producer/version from other
/// artwork. This defines one layer, not a complete new CC document profile.
final class AiNativeLayerDefinition {
  /// Exact integer-valued `Lb` operands, retaining the selected producer layout.
  ///
  /// The first six flags are visibility, preview, enabled, printing, dimming and
  /// multilayer masks. Masks must be zero. The ten-operand layout ends with a
  /// color index and three byte-valued display channels. Extended layouts add
  /// a flag before those colors, then template and image-dimming values. The
  /// fourteenth operand, when present, must be zero.
  final List<double> attributes;

  /// Native display-name bytes, independent of XML identity and text encoding.
  final List<int> nameBytes;

  /// Fresh portable XML identity, or null to create an anonymous layer.
  final List<int>? identifierBytes;

  /// Whether the new layer's panel entry starts expanded.
  final bool expanded;

  /// Freezes and validates a layer definition before any source is edited.
  AiNativeLayerDefinition({required List<double> attributes, required List<int> nameBytes, List<int>? identifierBytes, this.expanded = false})
    : attributes = List.unmodifiable(attributes),
      nameBytes = List.unmodifiable(nameBytes),
      identifierBytes = identifierBytes == null ? null : List.unmodifiable(identifierBytes) {
    if (!const {10, 13, 14}.contains(attributes.length) ||
        attributes.any((value) => !value.isFinite || value != value.truncateToDouble()) ||
        attributes.take(6).any((value) => !const {0, 1}.contains(value)) ||
        attributes[5] != 0 ||
        attributes.length == 14 && attributes.last != 0) {
      throw ArgumentError('New layers require a qualified unmasked native header.');
    }
    final int color = attributes.length == 10 ? 6 : 7;
    if (attributes[color] < -1 ||
        attributes[color] > 26 ||
        attributes.skip(color + 1).take(3).any((value) => value < 0 || value > 255) ||
        attributes.length > 10 && (!const {0, 1}.contains(attributes[6]) || !const {0, 1}.contains(attributes[11]) || attributes[12] < 0 || attributes[12] > 100)) {
      throw ArgumentError('New layers require qualified display attributes.');
    }
    if (nameBytes.any((byte) => byte < 0 || byte > 255) || identifierBytes != null && identifierBytes.any((byte) => byte < 0 || byte > 255)) {
      throw ArgumentError('Native layer names and identifiers must contain bytes.');
    }
  }
}

/// One source-owned layer with its complete wrapper and attached header metadata.
final class AiNativeLayer extends AiNativeItem {
  /// Original low-level header, name, flags and matching closing instruction.
  final AiLayer source;

  /// Source-order index in the owning layer inventory.
  final int index;

  /// Direct parent layer index, independently of ordinary artwork groups.
  final int? parentIndex;

  /// Direct child layers in source order.
  final List<int> childIndices;

  /// Optional matching DSC begin-layer comment.
  final AiToken? openingComment;

  /// Optional matching DSC end-layer comment.
  final AiToken? closingComment;

  /// Saved layer-panel expansion instruction, separate from artwork geometry.
  final AiNativeInstruction? expansion;

  /// Immediately attached layer dictionary, retaining unknown fields.
  final AiNativeContainer? dictionary;

  /// Saved XML identifier with its exact dictionary-field ownership.
  final AiNativeObjectIdentifier? identifier;

  /// Beginning of child artwork/state after the qualified header components.
  final int bodyStart;

  /// Explains a header/owner that needs a separate lifecycle contract.
  final String? bindingIssue;

  /// Structural errors independent of the retained dictionary's field schema.
  final String? _ownershipIssue;

  /// Freezes source associations without converting opaque records into artwork.
  AiNativeLayer._({
    required super.start,
    required super.end,
    required this.source,
    required this.index,
    required this.parentIndex,
    required List<int> childIndices,
    required this.openingComment,
    required this.closingComment,
    required this.expansion,
    required this.dictionary,
    required this.identifier,
    required this.bodyStart,
    required this.bindingIssue,
    required this._ownershipIssue,
  }) : childIndices = List.unmodifiable(childIndices);

  /// Original display-name bytes; no locale or XML-name conversion is guessed.
  Uint8List? get nameBytes => source.naming == null ? null : aiStringBytes(source.naming!.operands.single).asUnmodifiableView();

  /// Saved expansion state, or null when no instruction was stored.
  bool? get expanded => expansion == null ? null : expansion!.numbers!.single == 1;
}

/// Immutable layer ownership, source wrappers and related document declarations.
///
/// A qualified header does not qualify its child artwork. Saved XML identifiers
/// remain separate from display names; duplicate identifiers are not merged.
final class AiNativeLayers {
  /// Complete qualified drawing text references in source order.
  ///
  /// These handles support relocation and ordering without changing ATE indices.
  /// Use the text document's story/frame lifecycle for deletion or duplication.
  List<AiNativeContainer> get textArtwork => List.unmodifiable(drawing._textArtwork.map((owner) => owner.record));

  /// Source snapshot owning the native commands and returned layer handles.
  final AiNativeDrawing drawing;

  /// Structural ownership and references shared with other native model views.
  final AiNativeStructure structure;

  /// Embedded raster handles owned by this mixed-artwork snapshot.
  late final AiNativeRasters rasters = AiNativeRasters.decode(records: drawing.records);

  /// Owned linked image handles for mixed artwork transactions.
  late final AiNativePlacements placements = AiNativePlacements.decode(records: drawing.records);

  /// All layers in source order, including nested and hidden owners.
  final List<AiNativeLayer> layers;

  /// Optional declared count of root layers, excluding nested sublayers.
  final AiNativeHeaderField? rootCountHeader;

  /// Saved panel/view data, retained without treating values as layer indices.
  final AiNativeHeaderField? viewHeader;

  /// Complete saved view declaration, including any DSC continuation comments.
  final List<AiToken> viewComments;

  /// Reads source-owned wrappers and metadata without executing artwork.
  factory AiNativeLayers.decode({required AiNativeDrawing drawing}) => _nativeLayers(drawing);

  /// Keeps one bounded inventory and immutable source relationships.
  AiNativeLayers._({required this.drawing, required this.structure, required List<AiNativeLayer> layers, required this.rootCountHeader, required this.viewHeader, required List<AiToken> viewComments})
    : layers = List.unmodifiable(layers),
      viewComments = List.unmodifiable(viewComments);

  /// Actual number of root layers in this source snapshot.
  int get rootCount => layers.where((layer) => layer.parentIndex == null).length;

  /// Declared root count, or null when the source omits the declaration.
  int? get declaredRootCount => rootCountHeader?.values.single.toInt();

  /// Whether a present count agrees with the parsed root owners.
  bool get rootCountMatches => declaredRootCount == null || declaredRootCount == rootCount;

  /// Finds the corresponding layer using the original low-level source handle.
  AiNativeLayer layerFor(AiLayer source) => layers.firstWhere((layer) => identical(layer.source, source), orElse: () => throw ArgumentError('The layer does not belong to this native inventory.'));

  /// Returns direct children without accepting a handle from another snapshot.
  List<AiNativeLayer> childrenOf(AiNativeLayer layer) {
    _requireOwned(layer);
    return List.unmodifiable(layer.childIndices.map((index) => layers[index]));
  }

  /// Inserts an empty sibling using the selected layer's qualified header layout.
  ///
  /// [nameBytes] is an explicit native name. Identified templates require fresh
  /// [identifierBytes]; anonymous templates remain anonymous. Flags and wrapper
  /// conventions come from [after], with a closed panel entry and no artwork.
  /// Fresh names cannot reuse any saved native XMLUID, including opaque owners.
  /// A saved layer-view declaration requires [discardViewState] because its
  /// reference mapping is unqualified. Root counts update in the same transaction.
  AiNativeLayers insertAfter({required AiNativeLayer after, required List<int> nameBytes, List<int>? identifierBytes, bool discardViewState = false}) =>
      _insertNativeLayer(this, after, nameBytes, identifierBytes, discardViewState);

  /// Appends an empty layer without requiring an existing sibling or template.
  ///
  /// Omit [parent] to append at the document root, including after all layers
  /// have been removed. An owned [parent] creates a last sublayer, including in
  /// an empty parent. Existing artwork, state and layer headers remain exact.
  /// Root counts update atomically; saved view declarations require explicit
  /// [discardViewState]. Supplied identities must be fresh across the document.
  AiNativeLayers create({required AiNativeLayerDefinition definition, AiNativeLayer? parent, bool discardViewState = false}) => _createNativeLayer(this, definition, parent, discardViewState);

  /// Permutes selected sibling slots while retaining identities and child artwork.
  ///
  /// Selected ordinary parents may contain qualified complete CC pairs, including
  /// their saved metadata alternatives. Native and printing state are checked
  /// separately at each slot and wherever following artwork reads changed state.
  /// Saved view data requires explicit [discardViewState], as for insertion.
  AiNativeLayers reorder({required List<AiNativeLayer> layers, bool discardViewState = false}) => _reorderNativeLayers(this, layers, discardViewState);

  /// Permutes sibling paths, gradients, meshes, images, text, groups and layers.
  ///
  /// Supply exact [AiNativePath] or [AiNativeLayer] handles from this inventory's
  /// drawing, image handles from [rasters]/[placements], or records from
  /// [textArtwork], or complete [AiNativeGradientArtwork]/[AiNativeMeshArtwork]
  /// handles from the drawing, or complete ordinary [AiNativeGroup] handles.
  /// Selected owners share one root, layer or ordinary group parent. Containers
  /// retain complete qualified appearance pairs, including nested styles and
  /// clipping scopes; individual private or printing children cannot be selected.
  /// Names, identities, metadata and both outgoing states remain intact. Layer
  /// view declarations require explicit [discardViewState] when layers move.
  AiNativeLayers reorderArtwork({required List<AiNativeItem> artwork, bool discardViewState = false}) => _reorderNativeLayerArtwork(this, artwork, discardViewState);

  /// Appends one complete artwork owner under a group, layer or global root.
  ///
  /// Supply either [parent] or [group], or neither for the global document root.
  /// Native layers cannot be children of ordinary groups. Changing ancestry requires
  /// [inheritParentFlags]; the host supplies geometry changes and matching PDF
  /// artwork separately. Root-layer counts update with the relocation. Source
  /// identities and native/printing state are retained; descendants cannot be
  /// their own destination. Reorder siblings afterward for an exact mixed slot.
  /// Complete appearance descendants retain both representations and masks.
  /// Text moves retain ATE frame/story indices and composition; moving its canvas
  /// geometry remains a separate text-frame operation.
  AiNativeLayers moveArtwork({required AiNativeItem artwork, AiNativeLayer? parent, AiNativeGroup? group, bool inheritParentFlags = false, bool discardViewState = false}) =>
      _moveNativeLayerArtwork(this, artwork, parent, group, inheritParentFlags, discardViewState);

  /// Removes disjoint path, gradient, mesh, image, group or layer owners and descendants.
  ///
  /// Text references and layers still containing text require prior story/frame
  /// removal through `AiNativeTextDocument`, so no orphan engine resources remain.
  ///
  /// Image handles come from [rasters] or [placements]. All saved identities require a complete
  /// reference check; persistent scalar state remains at each removed position.
  /// Complete appearance descendants leave with their container; shared styles remain.
  /// Root counts and optional saved-view invalidation follow layer lifecycle.
  AiNativeLayers removeArtwork({required List<AiNativeItem> artwork, bool discardViewState = false}) => _removeNativeLayerArtwork(this, artwork, discardViewState);

  /// Moves a complete subtree after another layer, retaining its saved identities.
  ///
  /// Changing its parent requires [inheritParentFlags]: the moved layer retains
  /// its own flags and explicitly inherits its destination ancestors' attributes.
  /// Persistent paint and object flags are preserved independently. An ancestor
  /// can be the anchor when lifting a child out; a descendant cannot be an anchor.
  /// Qualified CC descendants retain their complete authoring/printing pairs and
  /// metadata alternatives, with separate native and printing state validation.
  AiNativeLayers moveAfter({required AiNativeLayer layer, required AiNativeLayer after, bool inheritParentFlags = false, bool discardViewState = false}) =>
      _moveNativeLayer(this, layer, after, inside: false, inheritParentFlags: inheritParentFlags, discardViewState: discardViewState);

  /// Appends a complete subtree inside a layer, including an empty destination.
  ///
  /// [inheritParentFlags] explicitly accepts the destination ancestors' flags
  /// when the immediate parent changes. Source identities and the moved subtree's
  /// own flags remain unchanged. No geometry or appearance is generated.
  AiNativeLayers moveInto({required AiNativeLayer layer, required AiNativeLayer parent, bool inheritParentFlags = false, bool discardViewState = false}) =>
      _moveNativeLayer(this, layer, parent, inside: true, inheritParentFlags: inheritParentFlags, discardViewState: discardViewState);

  /// Duplicates selected ordinary subtrees immediately after their source layers.
  ///
  /// [identifiers] must supply a fresh native XML name for every identified layer
  /// in the copied subtrees, including descendants. Anonymous layers stay
  /// anonymous. [artworkIdentifiers] supplies fresh IDs for every identified
  /// path/group descendant, keyed by its original drawing handle. Complete
  /// qualified CC pairs instead use each identified metadata dictionary's
  /// [AiNativeContainer] handle, including saved alternatives. Optional
  /// [names] replace existing layer display names in copies only.
  /// Existing identities, references, paint state and unselected bytes remain.
  AiNativeLayers duplicate({
    required List<AiNativeLayer> layers,
    Map<AiNativeLayer, List<int>> identifiers = const {},
    Map<AiNativeLayer, List<int>> names = const {},
    Map<AiNativeItem, List<int>> artworkIdentifiers = const {},
    bool discardViewState = false,
  }) => _duplicateNativeLayers(this, layers, identifiers, names, artworkIdentifiers, discardViewState);

  /// Removes qualified subtrees while retaining their outgoing state assignments.
  ///
  /// Identified layers or artwork require a qualified declarative reference scope;
  /// opaque records, external executable sections and ambiguous identities reject.
  /// Anonymous subtrees retain local dependency checks. Root counts update and
  /// saved panel data requires explicit [discardViewState]. Bounds do not shrink.
  /// Complete qualified CC pairs are removed with their parent, including
  /// both metadata alternatives. Retained artwork keeps both state streams.
  AiNativeLayers remove({required List<AiNativeLayer> layers, bool discardViewState = false}) => _removeNativeLayers(this, layers, discardViewState);

  /// Requires the exact immutable layer instance supplied by this inventory.
  void _requireOwned(AiNativeLayer layer) {
    if (layer.index >= layers.length || !identical(layers[layer.index], layer)) {
      throw ArgumentError('The layer does not belong to this native inventory.');
    }
  }
}
