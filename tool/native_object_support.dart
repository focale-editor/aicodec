import 'package:aikit/aikit.dart';

/// Retains complete artwork, panel, dictionary and style spans for reader checks.
List<Map<String, Object?>> nativeObjectInventory(AiNativeDrawing drawing) => [
  for (final AiNativeObject object in AiNativeObjects.decode(drawing: drawing).objects)
    {
      'start': object.start,
      'artworkStart': object.source.start,
      'artworkEnd': object.source.end,
      'end': object.end,
      'kind': object.node.kind.name,
      'private': object.source is AiNativePath ? (object.source as AiNativePath).isPrivate : (object.source as AiNativeGroup).opening.isPrivate,
      'dictionary': object.dictionary == null ? null : [object.dictionary!.start, object.dictionary!.end],
      'expansion': object.expansion == null ? null : [object.expansion!.start, object.expansion!.end],
      'expanded': object.expanded,
      'styleApplication': object.styleApplication == null ? null : [object.styleApplication!.start, object.styleApplication!.end],
      'identifier': object.identifier?.bytes,
      'identifierSpan': object.identifier == null
          ? null
          : [object.identifier!.field.entry.container!.entries.single.items.single.start, object.identifier!.field.entry.container!.entries.single.items.single.end],
      'count': object.source is AiNativePath ? _count(drawing, object.source as AiNativePath) : null,
    },
];

/// Captures a consumed count separately from geometry and attached metadata.
List<int>? _count(AiNativeDrawing drawing, AiNativePath path) {
  final int index = drawing.paths.indexOf(path);
  final int start = index == 0 ? drawing.records.program.bodyStart : drawing.paths[index - 1].end;
  final List<AiNativeInstruction> counts = drawing.items.whereType<AiNativeInstruction>().where((item) => item.operator == 'As' && item.start >= start && item.end <= path.start).toList();
  return counts.isEmpty ? null : [counts.single.start, counts.single.end];
}
