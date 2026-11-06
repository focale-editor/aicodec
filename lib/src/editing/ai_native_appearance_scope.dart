part of 'package:illustratorkit/src/model/ai_native_records.dart';

/// Qualifies retained ordinary masks and state between complete appearance pairs.
List<AiNativeInstruction> _nativeAppearanceInterval(AiNativeLayers layers, int start, int end, Map<int, AiNativeLayer> headers) {
  _artboardArtworkInterval(layers, start, end, headers, textOwners: {}, styles: {});
  final AiNativeDrawing drawing = layers.drawing;
  for (final AiNativeGroup group in drawing.groups.where((group) => group.compound && group.start >= start && group.end <= end)) {
    final List<AiNativeGroup> ancestors = _artworkParents(
      layers.structure,
      layers.structure.parentOf(layers.structure.nodeFor(group)),
    ).map((node) => node.source).whereType<AiNativeGroup>().toList().reversed.toList();
    if (!ancestors.any((parent) => parent.compound)) {
      _nativeGroupContours(drawing, group, ancestors: ancestors);
    }
  }
  return [
    for (final AiNativeInstruction item in _pathInterval(drawing.items, start, end, (item) => item.start).whereType<AiNativeInstruction>())
      if (!headers.containsKey(item.start) && !_ordinaryObjectAttachment(drawing, item)) item,
  ];
}
