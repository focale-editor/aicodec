part of 'package:illustratorkit/src/model/ai_native_records.dart';

/// Checks finite portable coordinates before constructing any native edit.
void _nativeArtboardCoordinates(Iterable<double> values) {
  if (values.any((value) => !value.isFinite || value.abs() > 9007199254740991)) {
    throw ArgumentError('Artboard coordinates require finite portable native values.');
  }
}

/// Replaces native geometry without deriving ink, crop, ruler or PDF coordinates.
AiNativeArtboards _resizeNativeArtboard(
  AiNativeArtboards model,
  AiNativeArtboard artboard,
  AiBoundingBox bounds,
  AiBoundingBox? cropBounds,
  List<double>? rulerOrigin,
  AiNativePrintSelection? artboardPrinting,
  AiNativePrintSelection? pagePrinting,
) {
  _requireNativeArtboard(model, artboard);
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
  _nativeArtboardReferenceScope(model);
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
  edits.addAll(_nativeArtboardCropEdits(model, cropBounds));
  edits.addAll(
    _nativeArtboardPrintEdits(
      model,
      order: [for (int index = 0; index < model.artboards.length; index++) index],
      changed: edits.isNotEmpty,
      artboardPrinting: artboardPrinting,
      pagePrinting: pagePrinting,
    ),
  );
  return _applyNativeArtboardEdits(model, edits);
}

/// Resolves current ownership by record identity, never by a reused saved UUID.
int _requireNativeArtboard(AiNativeArtboards model, AiNativeArtboard artboard) {
  final int index = model.artboards.indexWhere((board) => identical(board.record, artboard.record));
  if (!identical(artboard.document, model.document) || index < 0) {
    throw ArgumentError('Artboard edits require an owned current source record.');
  }
  return index;
}

/// Changes a crop declaration only when the host explicitly supplies its bounds.
List<AiSourceEdit> _nativeArtboardCropEdits(AiNativeArtboards model, AiBoundingBox? cropBounds) {
  final List<AiSourceEdit> edits = [];
  if (cropBounds != null) {
    _nativeArtboardCoordinates([cropBounds.left, cropBounds.bottom, cropBounds.right, cropBounds.top]);
    final AiNativeHeaderField? crop = model.cropHeader;
    if (crop == null) {
      throw UnsupportedError('Artboard edits cannot invent a missing native crop declaration.');
    }
    final List<double> values = [cropBounds.left, cropBounds.bottom, cropBounds.right, cropBounds.top];
    if (values.indexed.any((value) => value.$2 != crop.values[value.$1])) {
      final String prefix = crop.token.lexeme.substring(0, crop.token.lexeme.indexOf(':') + 1);
      edits.add(AiSourceEdit(start: crop.token.start, end: crop.token.end, bytes: latin1.encode('$prefix ${values.join(' ')}')));
    }
  }
  return edits;
}

/// Reparses under original limits and retains the selected root Document owner.
AiNativeArtboards _applyNativeArtboardEdits(AiNativeArtboards model, List<AiSourceEdit> edits) {
  if (edits.isEmpty) {
    return model;
  }
  final int ownerIndex = model.records.roots.indexOf(model.document);
  final AiNativeRecords result = AiNativeRecords.decode(
    program: AiNativeEditor.apply(program: model.records.program, edits: edits),
  );
  return AiNativeArtboards.decode(records: result, document: result.roots[ownerIndex]);
}
