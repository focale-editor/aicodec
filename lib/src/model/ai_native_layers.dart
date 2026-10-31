part of 'package:aikit/src/model/ai_native_records.dart';

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
  /// Source snapshot owning the native commands and returned layer handles.
  final AiNativeDrawing drawing;

  /// Structural ownership and references shared with other native model views.
  final AiNativeStructure structure;

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

  /// Permutes selected sibling slots while retaining identities and child artwork.
  ///
  /// Selected ordinary parents may contain qualified complete CC pairs, including
  /// their saved metadata alternatives. Native and printing state are checked
  /// separately at each slot and wherever following artwork reads changed state.
  /// Saved view data requires explicit [discardViewState], as for insertion.
  AiNativeLayers reorder({required List<AiNativeLayer> layers, bool discardViewState = false}) => _reorderNativeLayers(this, layers, discardViewState);

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
