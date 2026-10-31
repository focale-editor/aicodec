part of 'package:aikit/src/model/ai_native_records.dart';

/// Native commands and unresolved differences replacing one original pair slot.
typedef _NativeShapeReplacement = ({
  _NativeShapeBundle bundle,
  List<_NativeShapeReplay> prefix,
  List<_NativeShapeReplay> suffix,
  Set<String> unresolved,
  Set<String> printingUnresolved,
  bool discard,
});

/// Proves that following objects never consume unresolved replacement effects.
void _shapeFollowingDependencies(AiNativeDrawing drawing, List<_NativeShapeBundle> slots, Map<AiLiveShape, _NativeShapeReplacement> replacements) {
  final Set<String> unresolved = {};
  final Set<String> printingUnresolved = {};
  final AiNativeLayers layers = AiNativeLayers.decode(drawing: drawing);
  final Map<int, AiNativeLayer> headers = _layerHeaderItems(layers);
  final Map<int, AiNativePath> paths = {for (final AiNativePath path in drawing.paths) path.start: path};

  /// Requires identical incoming attributes wherever retained artwork reads them.
  void read(Set<String> keys, {required bool private}) {
    final Set<String> missing = unresolved.intersection(keys);
    if (missing.isNotEmpty) {
      throw UnsupportedError('Following artwork depends on unresolved native style state: ${missing.join(', ')}.');
    }
    if (!private && printingUnresolved.intersection(keys).isNotEmpty) {
      throw UnsupportedError('Following artwork depends on unresolved printing state: ${printingUnresolved.intersection(keys).join(', ')}.');
    }
  }

  /// Accounts for retained assignments before each path or group observes state.
  void command(AiNativeInstruction item, {bool discard = false, _NativeShapeBundle? bundle, bool? private}) {
    final bool nativeOnly = private ?? item.isPrivate;
    final String? key = _nativeArtworkStateKey(item);
    if (key != null) {
      unresolved.remove(key);
      if (!nativeOnly) {
        printingUnresolved.remove(key);
      }
      return;
    }
    if (discard) {
      return;
    }
    if (paths[item.start] case final AiNativePath path) {
      read(_shapeCopyReads(drawing, path), private: nativeOnly);
    } else if (const {'u', '*u'}.contains(item.operator)) {
      read({'A', 'Xw'}, private: nativeOnly);
    } else if (_marker(item, 6)) {
      read({'Xy'}, private: true);
    } else if (_marker(item, 1)) {
      read(bundle!.styleReads, private: true);
      // Potential writes are not definite writes: hidden filter parts may not
      // execute. Keep unresolved keys until an explicit assignment replaces them.
    }
  }

  /// Qualifies ordinary intervening artwork only while state may still differ.
  void interval(int start, int end) {
    if (unresolved.isEmpty && printingUnresolved.isEmpty || start == end) {
      return;
    }
    int position = start;
    for (final AiNativeInstruction item in _pathInterval(drawing.items, start, end, (item) => item.start).whereType<AiNativeInstruction>().where((item) => item.isPrivate)) {
      if (_nativeArtworkStateKey(item) == null) {
        throw UnsupportedError('Following private artwork requires a separate native state contract.');
      }
      _layerInterval(layers, position, item.start, headers).forEach(command);
      command(item);
      position = item.end;
    }
    _layerInterval(layers, position, end, headers).forEach(command);
  }

  int position = slots.first.start;
  for (final AiLiveShape shape in drawing.liveShapes.where((shape) => shape.isBound && shape.appearanceGroup != null && shape.path?.isPrivate == true && shape.end > position)) {
    final int start = drawing._objects.forSource(shape.appearanceGroup!).expansion?.start ?? shape.start;
    interval(position, start);
    if (replacements[shape] case final _NativeShapeReplacement replacement) {
      for (final _NativeShapeReplay replay in replacement.prefix) {
        command(replay.value, private: replay.private);
      }
      for (final AiNativeInstruction item in replacement.bundle.commands) {
        command(item, discard: replacement.discard, bundle: replacement.bundle);
      }
      for (final _NativeShapeReplay replay in replacement.suffix) {
        command(replay.value, private: replay.private);
      }
      unresolved.addAll(replacement.unresolved);
      printingUnresolved.addAll(replacement.printingUnresolved);
    } else if (unresolved.isNotEmpty || printingUnresolved.isNotEmpty) {
      final _NativeShapeBundle bundle = _shapeBundle(drawing, shape, layers.structure);
      for (final AiNativeInstruction item in bundle.commands) {
        command(item, bundle: bundle);
      }
    }
    position = shape.end;
  }
  interval(position, drawing.records.program.bodyEnd);
}
