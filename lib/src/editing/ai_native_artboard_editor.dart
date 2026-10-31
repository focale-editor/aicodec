part of 'package:aikit/src/model/ai_native_records.dart';

/// Checks finite portable coordinates before constructing any native edit.
void _nativeArtboardCoordinates(Iterable<double> values) {
  if (values.any((value) => !value.isFinite || value.abs() > 9007199254740991)) {
    throw ArgumentError('Artboard coordinates require finite portable native values.');
  }
}

/// Replaces native geometry without deriving ink, crop, ruler or PDF coordinates.
AiNativeArtboards _resizeNativeArtboard(AiNativeArtboards model, AiNativeArtboard artboard, AiBoundingBox bounds, AiBoundingBox? cropBounds, List<double>? rulerOrigin) {
  if (!identical(artboard.document, model.document) || !model.artboards.any((board) => identical(board.record, artboard.record))) {
    throw ArgumentError('Artboard resizing requires an owned current source record.');
  }
  _nativeArtboardCoordinates([
    bounds.left,
    bounds.bottom,
    bounds.right,
    bounds.top,
    ...?rulerOrigin,
    if (cropBounds != null) ...[cropBounds.left, cropBounds.bottom, cropBounds.right, cropBounds.top],
  ]);
  if (bounds.left == bounds.right || bounds.bottom == bounds.top || rulerOrigin != null && rulerOrigin.length != 2) {
    throw ArgumentError('An artboard needs positive dimensions and a two-coordinate ruler origin.');
  }
  final AiNativeLayers layers = AiNativeLayers.decode(drawing: AiNativeDrawing.decode(records: model.records));
  _nativeReferenceScope(layers, _layerHeaderItems(layers));
  final List<AiSourceEdit> edits = [];

  /// Keeps field types, source prefixes and all unselected spelling unchanged.
  void coordinates(AiNativeEntry? entry, List<double> values) {
    if (entry == null || entry.numbers?.length != values.length) {
      throw UnsupportedError('Artboard resizing requires existing coordinate fields.');
    }
    for (final (int, double) value in values.indexed) {
      if (entry.numbers![value.$1] != value.$2) {
        final AiNativeItem token = entry.items[value.$1];
        edits.add(AiSourceEdit(start: token.start, end: token.end, bytes: latin1.encode(value.$2.toString())));
      }
    }
  }

  coordinates(artboard.record['PositionPoint1'], [bounds.left, bounds.top]);
  coordinates(artboard.record['PositionPoint2'], [bounds.right, bounds.bottom]);
  if (rulerOrigin != null) {
    coordinates(artboard.record['RulerOrigin'], rulerOrigin);
  }
  if (cropBounds != null) {
    final AiNativeHeaderField? crop = model.cropHeader;
    if (crop == null) {
      throw UnsupportedError('Artboard resizing cannot invent a missing native crop declaration.');
    }
    final List<double> values = [cropBounds.left, cropBounds.bottom, cropBounds.right, cropBounds.top];
    if (values.indexed.any((value) => value.$2 != crop.values[value.$1])) {
      final String prefix = crop.token.lexeme.substring(0, crop.token.lexeme.indexOf(':') + 1);
      edits.add(AiSourceEdit(start: crop.token.start, end: crop.token.end, bytes: latin1.encode('$prefix ${values.join(' ')}')));
    }
  }
  if (edits.isEmpty) {
    return model;
  }
  final int ownerIndex = model.records.roots.indexOf(model.document);
  final AiNativeRecords result = AiNativeRecords.decode(
    program: AiNativeEditor.apply(program: model.records.program, edits: edits),
  );
  return AiNativeArtboards.decode(records: result, document: result.roots[ownerIndex]);
}
