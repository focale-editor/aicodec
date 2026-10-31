import 'package:aikit/aikit.dart';

/// Retains source boundaries and exact metadata for independent native decoding.
Map<String, Object?> nativeLayerInventory(AiNativeLayers model) => {
  'rootCount': model.rootCount,
  'declaredRootCount': model.declaredRootCount,
  'rootCountSpan': model.rootCountHeader == null ? null : [model.rootCountHeader!.token.start, model.rootCountHeader!.token.end],
  'viewSpans': [
    for (final AiToken token in model.viewComments) [token.start, token.end],
  ],
  'layers': [
    for (final AiNativeLayer layer in model.layers)
      {
        'start': layer.start,
        'end': layer.end,
        'opening': [layer.source.begin.start, layer.source.begin.end],
        'closing': [layer.source.end.start, layer.source.end.end],
        'openingComment': layer.openingComment?.lexeme,
        'closingComment': layer.closingComment?.lexeme,
        'bodyStart': layer.bodyStart,
        'parent': layer.parentIndex,
        'children': layer.childIndices,
        'name': layer.nameBytes?.toList(),
        'attributes': layer.source.begin.numbers,
        'expanded': layer.expanded,
        'identifier': layer.identifier?.bytes.toList(),
        'issue': layer.bindingIssue,
      },
  ],
};
