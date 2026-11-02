part of 'package:aicodec/src/model/ai_native_records.dart';

/// Qualifies unchanged gradient neighbors without granting edits to their paths.
Set<AiNativeInstruction> _nativeContourGradientCommands(AiNativeLayers layers) {
  final AiNativeDrawing drawing = layers.drawing;
  final List<AiLiveShape> pairs = drawing.liveShapes.where((shape) => shape.appearanceGroup != null || shape.path?.isPrivate == true).toList();
  final Map<int, AiNativeResourceUse> references = {
    for (final AiNativeResourceUse use in layers.structure.resourceUses.where((use) => use.kind == .gradient)) use.instruction.start: use,
  };
  final Set<AiNativeInstruction> retained = {};
  for (final AiNativeGradient gradient in drawing.gradients) {
    if (pairs.any((shape) => gradient.start >= shape.start && gradient.end <= shape.end)) {
      // Complete shape pairs keep their existing authoring/printing contract.
      continue;
    }
    final AiNativeResourceUse? reference = references[gradient.geometry.instruction.start];
    if (gradient.opening.isPrivate ||
        reference?.resolution != .resolved ||
        reference!.candidates.single.versions.isNotEmpty ||
        layers.structure.versions.memberships(start: gradient.start, end: gradient.end).isNotEmpty) {
      throw UnsupportedError('Retained contour neighbors require ordinary gradients with one unconditional resource definition.');
    }
    final int start = gradient.paths.isEmpty ? gradient.start : min(gradient.start, gradient.paths.first.start);
    if (pairs.any((shape) => shape.start < gradient.end && shape.end > start) || drawing.paths.any((path) => path.start < gradient.end && path.end > start && !gradient.paths.contains(path))) {
      throw UnsupportedError('A retained gradient must own every intersecting contour and remain outside complete shape pairs.');
    }
    final Set<AiNativeInstruction> commands = {gradient.opening, gradient.geometry.instruction, ?gradient.highlight, ...gradient.imagingMatrices, gradient.closing};
    final Set<AiNativeInstruction> geometry = {
      for (final AiNativePath path in gradient.paths) ...[...path.geometry, path.paint],
    };
    for (final AiNativeItem item in _pathInterval(drawing.items, start, gradient.end, (item) => item.start)) {
      if (item is! AiNativeInstruction ||
          item.isPrivate ||
          !commands.contains(item) && !geometry.contains(item) && item.operator != 'As' ||
          item.operands.any((operand) => operand.number != null && (!operand.number!.isFinite || operand.number!.abs() > 9007199254740991))) {
        throw UnsupportedError('Retained contour gradients cannot cross state, metadata, groups or unqualified geometry.');
      }
    }
    retained.addAll(commands);
  }
  return retained;
}
