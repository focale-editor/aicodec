part of 'package:illustratorkit/src/model/ai_native_records.dart';

/// Keeps literal pattern references separate from process-paint assignments.
Iterable<AiNativeInstruction> _nativeAppearancePatternPaints(AiNativeAppearance style) => [
  ?style.simplePaint,
  for (final AiNativeAppearancePart part in style.parts) ...part.paints.map((paint) => paint.style),
].expand((paint) => paint.instructions).where((command) => const {'p', 'P'}.contains(command.operator));

/// Avoids inspecting unrelated resources for process-only source appearances.
Set<String> _nativeAppearancePatterns(AiNativeAppearances model, AiNativeAppearance style) => _nativeAppearancePatternPaints(style).isEmpty ? const {} : model._patternNames;

/// Indexes unique ordinary pattern definitions without selecting version branches.
Set<String> _nativeAppearancePatternNames(AiNativeAppearances model) {
  final Map<String, List<AiNativeArtworkResource>> names = {};
  for (final AiNativeArtworkResource resource in model.artworkResources.resources.where((resource) => resource.kind == .pattern)) {
    (names[latin1.decode(resource.nameBytes)] ??= []).add(resource);
  }
  return Set.unmodifiable({
    for (final MapEntry<String, List<AiNativeArtworkResource>> entry in names.entries)
      if (entry.value.length == 1 && entry.value.single.versions.isEmpty && !entry.value.single.isPrivate) entry.key,
  });
}

/// Reads global native style state while retaining resource-local geometry.
({Set<String> reads, Set<String> writes}) _nativeAppearanceStyleState(AiNativeAppearances model, AiNativeAppearance style) => _nativeLiteralStyleState(
  model.structure.drawing,
  style.resource.definition.source as AiNativeContainer,
  patterns: _nativeAppearancePatterns(model, style),
);

/// Requires all transitive pattern-style expansions before changing resource ink.
Map<AiNativeResourceUse, Set<String>> _nativeAppearanceDependents(
  AiNativeAppearances model,
  List<AiNativeAppearanceReplacement> selected,
  List<AiNativeAppearanceReplacement> supplied,
  _ArtboardBrushScope brushes,
) {
  final Set<AiNativeArtworkResource> changed = {for (final AiNativeAppearanceReplacement replacement in selected) ?replacement.artwork.resource};
  final Map<AiNativeResourceUse, Set<String>> affected = {};
  final Map<AiNativeArtworkResource, Set<AiNativeArtworkResource>> edges = {};
  final List<AiNativeArtworkResource> pending = changed.toList();
  int work = 0;
  for (int index = 0; index < pending.length; index++) {
    final AiNativeArtworkResource resource = pending[index];
    final String name = latin1.decode(resource.nameBytes);
    if (resource.kind == .brush && brushes.artwork.contains(name)) {
      throw UnsupportedError('Changed brush artwork requires a qualified dependent brush expansion contract.');
    }
    if (resource.kind != .pattern) {
      continue;
    }
    for (final AiNativeAppearance style in model.styles) {
      if (++work > model.structure.drawing.records.program.limits.maxTokens) {
        throw const AiLimitException(message: 'Appearance resource dependencies exceed the inspection limit.');
      }
      final Set<String> keys = {};
      for (final AiNativeInstruction command in _nativeAppearancePatternPaints(style)) {
        if (++work > model.structure.drawing.records.program.limits.maxTokens) {
          throw const AiLimitException(message: 'Appearance resource dependencies exceed the inspection limit.');
        }
        if (latin1.decode(aiStringBytes(command.operands.first)) == name) {
          keys.add(command.operator == 'p' ? 'fill' : 'stroke');
        }
      }
      if (keys.isEmpty) {
        continue;
      }
      _nativeAppearanceStyleState(model, style);
      for (final AiNativeResourceUse use in style.uses) {
        if (++work > model.structure.drawing.records.program.limits.maxTokens) {
          throw const AiLimitException(message: 'Appearance resource dependencies exceed the inspection limit.');
        }
        if (!identical(model.resolve(use: use), style)) {
          throw UnsupportedError('Dependent appearances require unique unconditional style ownership.');
        }
        (affected[use] ??= {}).addAll(keys);
        final AiNativeArtworkResource? enclosing = model.artworkResources.forUse(use: use);
        if (enclosing != null) {
          (edges[resource] ??= {}).add(enclosing);
          if (changed.add(enclosing)) {
            pending.add(enclosing);
          }
        }
      }
    }
  }
  final Set<AiNativeArtworkResource> visited = {};
  final Set<AiNativeArtworkResource> visiting = {};

  /// Rejects recursive resource composition rather than silently truncating it.
  void visit(AiNativeArtworkResource resource) {
    if (visited.contains(resource)) {
      return;
    }
    if (!visiting.add(resource)) {
      throw UnsupportedError('Appearance resource dependencies cannot be recursive.');
    }
    if (visiting.length > model.structure.drawing.records.program.limits.maxDepth) {
      throw const AiLimitException(message: 'Appearance resource dependencies exceed the nesting limit.');
    }
    (edges[resource] ?? const {}).forEach(visit);
    visiting.remove(resource);
    visited.add(resource);
  }

  changed.forEach(visit);
  final Set<String> patterns = changed.where((resource) => resource.kind == .pattern).map((resource) => latin1.decode(resource.nameBytes)).toSet();
  final Iterable<AiNativeInstruction> local = [
    for (final AiNativeArtworkResource resource in model.artworkResources.resources) ...resource.items.whereType<AiNativeInstruction>(),
    for (final AiNativeContainer record in model.structure.drawing.records.containers.where((record) => record.type == 'Art'))
      ...AiNativeArt.decode(records: model.structure.drawing.records, record: record).items.whereType<AiNativeInstruction>(),
  ];
  if (local.any((command) => const {'p', 'P'}.contains(command.operator) && patterns.contains(latin1.decode(aiStringBytes(command.operands.first))))) {
    throw UnsupportedError('Direct pattern consumers require a separate native printing-owner contract.');
  }
  final Set<AiNativeResourceUse> covered = {
    for (final AiNativeAppearanceReplacement replacement in selected) ...[replacement.artwork.use, ...replacement.artwork.nestedUses],
  };
  for (final AiNativeAppearanceReplacement replacement in supplied) {
    if (replacement.uses.any((use) => !affected.containsKey(use))) {
      throw ArgumentError('Dependent expansions must select affected pattern-style uses.');
    }
    covered.addAll(replacement.uses);
  }
  if (!covered.containsAll(affected.keys)) {
    throw UnsupportedError('Resource appearance edits require every dependent pattern-style printing owner.');
  }
  return affected;
}

/// Validates local groups without merging resource coordinates into document bounds.
List<AiSourceEdit> _nativeAppearancePrintingEdits(AiNativeAppearances model, List<AiNativeAppearanceReplacement> replacements) {
  final Map<AiNativeArtworkResource?, List<AiNativeAppearanceReplacement>> contexts = {};
  int size = 0;
  for (final AiNativeAppearanceReplacement replacement in replacements) {
    size += replacement.bytes.length;
    if (size > model.structure.drawing.records.program.limits.maxDecodedBytes) {
      throw const AiLimitException(message: 'Supplied appearance expansions exceed native output limits.');
    }
    (contexts[replacement.artwork.resource] ??= []).add(replacement);
  }
  return [
    for (final MapEntry<AiNativeArtworkResource?, List<AiNativeAppearanceReplacement>> context in contexts.entries)
      ..._nativePrintingSourceEdits(context.key?._drawing ?? model.structure.drawing, [
        for (final AiNativeAppearanceReplacement replacement in context.value) (group: replacement.artwork.printingGroup, bytes: replacement.bytes, bounds: replacement.bounds),
      ], documentBounds: context.key == null),
  ];
}

/// Inspects local state consumers after the complete resource scope was qualified.
List<AiNativeInstruction> _nativeResourceAppearanceInterval(AiNativeDrawing drawing, int start, int end) {
  if (_nativeObjectMetadataComments(drawing, start, end)) {
    throw UnsupportedError('Resource state dependencies cannot cross opaque annotations.');
  }
  final List<AiNativeInstruction> result = [];
  for (final AiNativeItem item in _pathInterval(drawing.items, start, end, (item) => item.start)) {
    if (item.end > end) {
      throw UnsupportedError('Resource state inspection crosses an unfinished native owner.');
    }
    if (item is AiNativeContainer) {
      final AiNativeObject? owner = drawing._objects._attachments[item.start];
      if (owner == null || !identical(owner.dictionary, item) || owner._ownershipIssue != null) {
        throw UnsupportedError('Resource state inspection requires direct qualified metadata ownership.');
      }
      if (owner.source case final AiNativeGroup group) {
        _nativeAppearanceResourceParent(drawing, group);
      } else {
        _nativeAppearanceDictionary(item);
      }
      continue;
    }
    if (item is! AiNativeInstruction ||
        _nativeArtworkStateKey(item) == null &&
            !_nativeGeometry.contains(item.operator) &&
            !_nativePaint.contains(item.operator) &&
            !const {'u', 'U', '*u', '*U', 'q', 'Q', 'h', 'H', 'W', 'As', 'Ae', 'Xd', 'XW'}.contains(item.operator)) {
      throw UnsupportedError('Resource artwork has an unresolved following state consumer.');
    }
    result.add(item);
  }
  return result;
}

/// Resolves fixed brush references without qualifying unrelated brush libraries for ordinary styles.
Set<(String, String)> _nativeStyleBrushes(AiNativeDrawing drawing, AiNativeContainer style) {
  final List<AiNativeContainer> filters = drawing.records.containers.where((record) => record.start >= style.start && record.end <= style.end && record.type == 'BasicFilter').toList();
  final List<AiNativeContainer> brushFilters = filters
      .where((record) => _nativeAppearanceKind(record, _nativeAppearanceFilter(record)) == .calligraphic || _nativeAppearanceKind(record, _nativeAppearanceFilter(record)) == .artworkBrush)
      .toList();
  if (brushFilters.isEmpty) {
    return const {};
  }
  final AiNativeLayers layers = AiNativeLayers.decode(drawing: drawing);
  final _ArtboardResourceScope resources = _artboardResourceScope(layers);
  final Map<(String, String), AiNativeBrushDescriptor> descriptors = {};
  final _ArtboardBrushScope brushes = _artboardBrushScope(
    layers,
    resources.brushes,
    inspect: (brush) {
      descriptors[(brush.plugin, latin1.decode(brush.nameBytes))] = brush;
    },
  );
  for (final AiNativeContainer filter in brushFilters) {
    final String plugin = latin1.decode(_nativeAppearanceFilter(filter)!.nameBytes);
    if (plugin != AiNativeBrushKind.calligraphic.plugin) {
      final AiNativeArtworkBrushPaint paint = AiNativeArtworkBrushPaint._decode(filter, plugin == AiNativeBrushKind.art.plugin ? .art : .pattern);
      final AiNativeBrushDescriptor? descriptor = descriptors[(plugin, latin1.decode(paint.brushNameBytes))];
      if (descriptor == null) {
        throw UnsupportedError('Artwork brush styles require a resolved descriptor.');
      }
      final List<String> fields = latin1.decode(descriptor.payloadBytes).split('/').map((field) => field.trim()).toList();
      final String expected = latin1.decode(paint.descriptorPayload(tileNames: fields.skip(1).take(5).map(latin1.encode).toList()));
      final List<String> normalized = expected.split('/').map((field) => field.trim()).toList();
      if (fields.length != normalized.length || fields.indexed.any((field) => field.$1 < 6 ? field.$2 != normalized[field.$1] : !_sameBrushScalars(field.$2, normalized[field.$1]))) {
        throw UnsupportedError('Artwork brush descriptor and local fixed parameters must agree.');
      }
      continue;
    }
    final AiNativeCalligraphicPaint nib = AiNativeCalligraphicPaint._decode(filter);
    final AiNativeBrushDescriptor? descriptor = descriptors[(plugin, latin1.decode(nib.brushNameBytes))];
    final List<double> expected = _artboardBrushNumbers(latin1.decode(nib.descriptorPayload), count: 11);
    final List<double>? actual = descriptor == null ? null : _artboardBrushNumbers(latin1.decode(descriptor.payloadBytes), count: 11);
    if (actual == null || actual.indexed.any((value) => value.$2 != expected[value.$1])) {
      throw UnsupportedError('Fixed calligraphic editing requires matching descriptor and local nib parameters.');
    }
  }
  return brushes.names;
}

/// Compares bounded descriptor scalar groups without depending on number spelling.
bool _sameBrushScalars(String first, String second) {
  final List<double> expected = _artboardBrushNumbers(second, count: RegExp(r'\S+').allMatches(second).length);
  final List<double> actual = _artboardBrushNumbers(first, count: expected.length);
  return actual.indexed.every((value) => value.$2 == expected[value.$1]);
}
