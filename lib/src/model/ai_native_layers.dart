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
  /// A saved layer-view declaration requires [discardViewState] because its
  /// reference mapping is unqualified. Root counts update in the same transaction.
  AiNativeLayers insertAfter({required AiNativeLayer after, required List<int> nameBytes, List<int>? identifierBytes, bool discardViewState = false}) =>
      _insertNativeLayer(this, after, nameBytes, identifierBytes, discardViewState);

  /// Requires the exact immutable layer instance supplied by this inventory.
  void _requireOwned(AiNativeLayer layer) {
    if (layer.index >= layers.length || !identical(layers[layer.index], layer)) {
      throw ArgumentError('The layer does not belong to this native inventory.');
    }
  }
}
