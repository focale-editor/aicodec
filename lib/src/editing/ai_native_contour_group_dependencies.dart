part of 'package:aikit/src/model/ai_native_records.dart';

/// Differences awaiting an explicit assignment in each native interpretation.
typedef _NativeContourDifferences = ({Set<String> printing, Set<String> native});

/// Requires original input values whenever a retained owner consumes an attribute.
void _nativeContourRead(_NativeContourDifferences changed, Set<String> printing, Set<String> native) {
  if (changed.printing.intersection(printing).isNotEmpty || changed.native.intersection(native).isNotEmpty) {
    throw UnsupportedError('Following contour artwork consumes an unresolved moved-group attribute.');
  }
}

/// Clears differences overwritten by literal source assignments in both streams.
void _nativeContourAssigned(_NativeContourDifferences changed, String key, {required bool private}) {
  changed.native.remove(key);
  if (!private) {
    changed.printing.remove(key);
  }
}

/// Checks the next placed tree before accumulating its unresolved output values.
void _nativeContourPlaced(_NativeContourDifferences changed, _NativeShapeAccess access, _NativeSourceReplacement placed) {
  for (final _NativeShapeReplay replay in placed.prefix) {
    _nativeContourAssigned(changed, _nativeContourStateKey(replay.value)!, private: replay.private);
  }
  _nativeContourRead(changed, access.printingReads, access.nativeReads);
  changed.printing.removeAll(access.printingWrites);
  changed.native.removeAll(access.nativeWrites);
  for (final _NativeShapeReplay replay in placed.suffix) {
    _nativeContourAssigned(changed, _nativeContourStateKey(replay.value)!, private: replay.private);
  }
  changed.printing.addAll(placed.printingUnresolved);
  changed.native.addAll(placed.unresolved);
}

/// Proves unknown output is overwritten before any retained artwork consumes it.
void _nativeContourFollowing(
  AiNativeDrawing drawing,
  int position,
  List<AiNativeStructureNode> parents,
  List<AiNativeObject> removed,
  Map<int, _NativeShapeInputs> states,
  _NativeContourDifferences changed,
) {
  final Map<int, AiNativeObject> removals = {for (final AiNativeObject owner in removed) owner.start: owner};
  final Map<int, AiNativeLayer> headers = _layerHeaderItems(drawing._pathTopologyScope.layers);
  final Map<int, AiNativePath> paths = {for (final AiNativePath path in drawing.paths) path.start: path};
  final Map<int, AiNativeGroup> endings = {for (final AiNativeGroup group in drawing.groups) group.closing.start: group};
  final List<_NativeContourDifferences?> clips = [
    for (final AiNativeStructureNode parent in parents.reversed)
      if (parent.kind == .clip) (printing: {}, native: {}),
  ];
  int compoundDepth = 0;
  int consumed = position;
  for (final AiNativeItem item in _pathInterval(drawing.items, position, drawing.records.program.bodyEnd, (item) => item.start)) {
    if (changed.printing.isEmpty && changed.native.isEmpty && clips.every((saved) => saved == null || saved.printing.isEmpty && saved.native.isEmpty)) {
      return;
    }
    if (item.start < consumed) {
      continue;
    }
    if (removals[item.start] case final AiNativeObject owner) {
      final _NativeShapeInputs before = states[owner.start]!;
      final _NativeShapeInputs after = states[owner.end]!;
      for (final String key in _nativeArtworkStateKeys) {
        if (!_sameShapeAttribute(before.printing, before.printingOrigins, after.printing, after.printingOrigins, key)) {
          _nativeContourAssigned(changed, key, private: false);
        }
        if (!_sameShapeAttribute(before.native, before.nativeOrigins, after.native, after.nativeOrigins, key)) {
          _nativeContourAssigned(changed, key, private: true);
        }
      }
      consumed = owner.end;
      continue;
    }
    if (headers.containsKey(item.start) || _ordinaryObjectAttachment(drawing, item) || drawing._pathTopologyScope.retainedMetadata.contains(drawing._objects._attachments[item.start]?.dictionary)) {
      continue;
    }
    if (item is! AiNativeInstruction) {
      throw UnsupportedError('Unresolved group output cannot cross an opaque native owner.');
    }
    final String? key = _nativeContourStateKey(item);
    if (key != null) {
      _nativeContourAssigned(changed, key, private: item.isPrivate);
      continue;
    }
    if (item.isPrivate || drawing._pathTopologyScope.derived.contains(paths[item.start])) {
      throw UnsupportedError('Unresolved group output cannot cross derived or private artwork.');
    }
    if (paths[item.start] case final AiNativePath path) {
      final Set<String> reads = compoundDepth == 0 ? _shapeCopyReads(drawing, path) : _nativeContourFlags;
      _nativeContourRead(changed, reads, reads);
    }
    if (const {'u', '*u', 'q'}.contains(item.operator)) {
      _nativeContourRead(changed, {'A', 'Xw'}, {'A', 'Xw'});
    }
    switch (item.operator) {
      case '*u':
        if (compoundDepth != 0) {
          throw UnsupportedError('Unresolved group output cannot cross nested compound owners.');
        }
        compoundDepth++;
      case '*U':
        if (endings[item.start]!.paths.isEmpty) {
          throw UnsupportedError('Unresolved group output cannot cross an empty compound owner.');
        }
        final Set<String> reads = _shapeCopyReads(drawing, endings[item.start]!.paths.last)..removeAll(_nativeContourFlags);
        _nativeContourRead(changed, reads, reads);
        compoundDepth--;
      case 'q':
        clips.add(compoundDepth == 0 ? (printing: changed.printing.intersection(_nativeClipStateKeys), native: changed.native.intersection(_nativeClipStateKeys)) : null);
      case 'Q':
        if (clips.removeLast() case final _NativeContourDifferences saved) {
          changed.printing
            ..removeAll(_nativeClipStateKeys)
            ..addAll(saved.printing.intersection(_nativeClipStateKeys));
          changed.native
            ..removeAll(_nativeClipStateKeys)
            ..addAll(saved.native.intersection(_nativeClipStateKeys));
        }
      default:
        if (!_nativeGeometry.contains(item.operator) && !_nativePaint.contains(item.operator) && !const {'u', 'U', 'As', 'h', 'H', 'W'}.contains(item.operator)) {
          throw UnsupportedError('Unresolved group output crosses an unqualified state consumer.');
        }
    }
  }
  if (changed.printing.isNotEmpty || changed.native.isNotEmpty) {
    throw UnsupportedError('Contour group movement cannot restore unknown final attributes.');
  }
}
