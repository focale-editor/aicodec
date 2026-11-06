part of 'package:illustratorkit/src/model/ai_native_records.dart';

/// One unchanged text reference with its exclusively attached drawing metadata.
typedef _NativeTextArtwork = ({AiNativeContainer record, AiNativeContainer? metadata, _NativeSubtreeSpan span, AiNativeInstruction access});

/// Detects text even when its unresolved profile grants no movable handle.
bool _containsNativeText(AiNativeDrawing drawing, List<_NativeSubtreeSpan> spans) =>
    drawing.records.containers.any((record) => record.type == 'AI11Text' && spans.any((span) => record.start >= span.start && record.end <= span.end));

/// Isolates known text references for source moves without changing the engine.
List<_NativeTextArtwork> _readNativeTextArtwork(AiNativeDrawing drawing) {
  if (!drawing.items.any((item) => item is AiNativeContainer && item.type == 'AI11Text')) {
    return [];
  }
  final Set<AiNativeContainer> owned;
  try {
    owned = _artboardTextScope(AiNativeLayers.decode(drawing: drawing)).objects;
  } on AiLimitException {
    rethrow;
  } on UnsupportedError {
    return [];
  } on FormatException {
    return [];
  }
  final List<_NativeTextArtwork> result = [];
  for (final AiNativeContainer record in owned.where((record) => record.type == 'AI11Text')) {
    final int index = _pathOffset(drawing.items, record.end, (item) => item.start);
    final AiNativeItem? next = index < drawing.items.length ? drawing.items[index] : null;
    final AiNativeContainer? metadata = next is AiNativeContainer && next.type == 'ArtDictionary' && owned.contains(next) ? next : null;
    result.add((
      record: record,
      metadata: metadata,
      span: (start: record.start, end: metadata?.end ?? record.end),
      // This analysis-only command models incoming native attributes. It is
      // never serialized: relocation copies the complete original record bytes.
      access: AiNativeInstruction._(
        token: AiToken(kind: .executableName, start: record.start, end: record.end, lexeme: 'aikit:text'),
        operands: [],
        isPrivate: true,
      ),
    ));
  }
  result.sort((first, second) => first.span.start.compareTo(second.span.start));
  return result;
}

/// Keeps complete text, image and direct-gradient payloads neutral to scalar writes.
List<_NativeSubtreeSpan> _nativeNeutralArtwork(AiNativeDrawing drawing) => [
  ..._imageCreationNeutralSpans(drawing),
  for (final AiNativeGradientArtwork owner in drawing.gradientArtwork) (start: owner.start, end: owner.end),
  for (final AiNativeMeshArtwork owner in drawing.meshArtwork) (start: owner.start, end: owner.end),
  for (final _NativeTextArtwork owner in drawing._textArtwork) owner.span,
]..sort((first, second) => first.start.compareTo(second.start));
