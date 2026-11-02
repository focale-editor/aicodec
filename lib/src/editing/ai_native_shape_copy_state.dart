part of 'package:aicodec/src/model/ai_native_records.dart';

/// Known values and unknown-value provenance for both source interpretations.
typedef _NativeShapeInputs = ({
  Map<String, AiNativeInstruction> printing,
  Map<String, AiNativeInstruction> native,
  Map<String, int> printingOrigins,
  Map<String, int> nativeOrigins,
});

/// Attributes read before assignment and potentially written by a complete pair.
typedef _NativeShapeAccess = ({Set<String> printingReads, Set<String> nativeReads, Set<String> printingWrites, Set<String> nativeWrites});

/// Serializes a qualified scalar assignment in its requested source projection.
String _shapeStateText(AiNativeInstruction value, {required bool private}) {
  final String operands = value.operator == 'd'
      ? '[${value.operands.sublist(1, value.operands.length - 2).map((operand) => operand.lexeme).join(' ')}] ${value.operands.last.lexeme}'
      : value.operands.map((operand) => operand.lexeme).join(' ');
  return '${private ? '%_' : ''}$operands ${value.operator}\n';
}

/// Qualifies literal filter fields without treating executable values as data.
bool _shapeCopyStyleField(AiNativeContainer owner, AiNativeEntry field) => switch (field.key) {
  'Name' || 'PluginFileName' || 'Title' => field.stringBytes != null,
  'Visible' => const {0, 1}.contains(field.number),
  'FillOrStroke' => const {0, 1, 2}.contains(field.number),
  'Filter' =>
    field.items.length == 3 &&
        field.items.first is AiNativeToken &&
        const {AiTokenKind.string, AiTokenKind.hexString}.contains((field.items.first as AiNativeToken).token.kind) &&
        field.items[1] is AiNativeToken &&
        const {0, 1}.contains((field.items[1] as AiNativeToken).token.number) &&
        field.items[2] is AiNativeToken &&
        (field.items[2] as AiNativeToken).token.number == 0,
  'Def' when owner.type == 'KnownStyle' => field.container?.type == 'ActiveStyle',
  'Def' => field.items.every((item) => item is AiNativeToken),
  'Execution' => const {'CompoundFilter', 'BasicFilter'}.contains(field.container?.type),
  'Part' => const {'CompoundFilter', 'BasicFilter'}.contains(field.container?.type),
  'Dict' => field.container?.type == 'Dictionary',
  'FillStyle' || 'StrokeStyle' || 'BlendStyle' => field.container?.type == field.key,
  'DisplayString' => const {'String', 'UnicodeString'}.contains(field.type) && field.stringBytes != null,
  'UseEvenOdd' || 'StrokeOffsetInside' => field.type == 'Bool' && field.boolean != null,
  'kAIBeautifulStrokesParamsDictKey' => field.container?.type == 'Dictionary',
  'BSAdvStrokeDictionaryVersion' => field.type == 'Int' && field.number == 1,
  'BSDashAdj' => field.type == 'Bool' && const {0, 1}.contains(field.number),
  'Brush' => field.container?.type == 'GObjRef',
  'PluginObject' => owner.type == 'GObjRef' && field.items.length == 2 && field.items.every((item) => item is AiNativeToken && _artboardPaletteName(item.token)),
  'Angle' || 'Diameter' || 'Roundness' || 'AngleVariation' || 'DiameterVariation' || 'RoundnessVariation' => field.type == 'Real' && field.number != null,
  'AngleDependsOn' || 'DiameterDependsOn' || 'RoundnessDependsOn' || 'AngleRelativeTo' => field.type == 'Int' && field.number == 0,
  'NotRecorded' => field.isQualifier,
  _ when AiNativeArtworkBrushPaint.realFields.contains(field.key) => field.type == 'Real' && field.number != null,
  _ when AiNativeArtworkBrushPaint.integerFields.contains(field.key) => field.type == 'Int' && field.number != null && field.number == field.number!.truncateToDouble(),
  _ when AiNativeArtworkBrushPaint.booleanFields.contains(field.key) => field.type == 'Bool' && field.boolean != null,
  _ => false,
};

/// Identifies state writes without executing appearance filters or drawing art.
({Set<String> reads, Set<String> writes}) _shapeCopyStyleState(AiNativeDrawing drawing, AiLiveShape shape) => _nativeLiteralStyleState(drawing, shape.style!);

/// Qualifies a literal style independently of any particular referencing shape.
({Set<String> reads, Set<String> writes}) _nativeLiteralStyleState(AiNativeDrawing drawing, AiNativeContainer style, {Set<String> patterns = const {}}) {
  if (drawing._objects.structure.versions.blocks.any((block) => block.start < style.end && block.end > style.start)) {
    throw UnsupportedError('Shape copies require unconditional native filter execution.');
  }
  if (style['Def']?.container case final AiNativeContainer definition when definition.type == 'SimpleStyle') {
    return _nativeSimpleStyleState(drawing, style, definition, patterns: patterns);
  }
  final AiNativeLayers layers = AiNativeLayers.decode(drawing: drawing);
  _artboardRetainedStyle(layers, style, {for (final AiNativeResourceUse use in layers.structure.resourceUses) use.instruction.start: use}, patterns, _nativeStyleBrushes(drawing, style));
  final List<AiNativeContainer> effects = drawing.records.containers
      .where((record) => record.start >= style.start && record.end <= style.end && _nativeAppearanceKind(record, _nativeAppearanceFilter(record)) == .nativeEffect)
      .toList();
  for (final AiNativeContainer effect in effects) {
    AiNativeEffect._decode(drawing.records, effect);
  }
  final Set<String> writes = {};
  final Set<String> reads = {};
  for (final AiNativeContainer record in drawing.records.containers.where((record) => record.start >= style.start && record.end <= style.end)) {
    // Effect-local color records do not assign the enclosing artwork's paint.
    if (effects.any((effect) => record.start >= effect.start && record.end <= effect.end)) {
      continue;
    }
    if (const {'BasicFilter', 'CompoundFilter'}.contains(record.type) &&
        const {AiNativeAppearancePartKind.effect, AiNativeAppearancePartKind.opaque}.contains(_nativeAppearanceKind(record, _nativeAppearanceFilter(record)))) {
      throw UnsupportedError('Native appearance state requires qualified literal filter roles.');
    }
    if (record.entries.any((field) => !_shapeCopyStyleField(record, field))) {
      throw UnsupportedError('Shape copies require literal, typed native filter fields.');
    }
    final String? plugin = record['PluginFileName']?.text();
    if (plugin != null && !const {'Illustrator.exe', 'StrokeOffset.aip', 'CalligraphicBrushTool.aip', 'ArtOnPathBrushTool.aip', 'PatternOnPathBrushTool.aip'}.contains(plugin)) {
      throw UnsupportedError('Shape copies cannot qualify external appearance plug-ins.');
    }
    if (const {'FillStyle', 'StrokeStyle', 'BlendStyle'}.contains(record.type)) {
      final Set<String> local = {};
      if (record.type != 'BlendStyle') {
        local.add(record.type == 'FillStyle' ? 'fill' : 'stroke');
      }
      final AiNativePaintStyle paint = AiNativePaintStyle.decode(records: drawing.records, record: record);
      for (final AiNativeInstruction command in paint.instructions) {
        final String? key = _nativeArtworkStateKey(command);
        if (key != null) {
          local.add(key);
        } else if (const {'p', 'P'}.contains(command.operator)) {
          _artboardPatternUse(command, patterns);
          local.add(command.operator == 'p' ? 'fill' : 'stroke');
        } else if (command.operator == 'Xd' && command.numbers?.length == 2 && command.numbers!.every((value) => value == 0 || value == 1)) {
          // Each retained paint part carries its explicit fill/stroke flags.
        } else if (!_gradientCommands.contains(command.operator)) {
          throw UnsupportedError('Shape copies have no state contract for the native ${command.operator} style command.');
        }
      }
      final Set<String> required = switch (record.type) {
        'FillStyle' => {'fill', 'O', 'Xy', 'XR'},
        'StrokeStyle' => {'stroke', 'R', 'Xy', 'J', 'j', 'w', 'M', 'd', 'XR'},
        _ => {'Xy'},
      };
      reads.addAll(required.difference(local));
      writes.addAll(local);
    }
  }
  return (reads: reads, writes: writes);
}

/// Qualifies literal paints and explicitly allowed patterns without paint defaults.
({Set<String> reads, Set<String> writes}) _nativeSimpleStyleState(AiNativeDrawing drawing, AiNativeContainer style, AiNativeContainer definition, {Set<String> patterns = const {}}) {
  _artboardSetupRecord(AiNativeLayers.decode(drawing: drawing), style);
  _artboardStyleFields(style, {'Name', 'Def'});
  _artboardStyleFields(definition, {'Paint'});
  if (style.entries.length != 2 || style['Name']?.stringBytes?.isNotEmpty != true) {
    throw UnsupportedError('Simple appearance state requires an owned named definition.');
  }
  final Set<String> writes = {};
  for (final AiNativeInstruction command in AiNativePaintStyle.decode(records: drawing.records, record: definition).instructions) {
    if (const {'p', 'P'}.contains(command.operator)) {
      _artboardPatternUse(command, patterns);
      writes.add(command.operator == 'p' ? 'fill' : 'stroke');
      continue;
    }
    if (!_solidStyleCommands.contains(command.operator) && !_nativeNamedColorOperators.contains(command.operator)) {
      throw UnsupportedError('Simple appearance state requires qualified literal process paint.');
    }
    final String? key = _nativeArtworkStateKey(command);
    if (key != null) {
      writes.add(key);
    } else if (command.operator != 'Xd' || command.numbers?.length != 2 || command.numbers!.any((value) => value != 0 && value != 1)) {
      throw UnsupportedError('Simple appearance state has no contract for ${command.operator}.');
    }
  }
  // Xd is retained literally; without executing it, either paint may read its
  // inherited values. Only explicit local assignments remove those dependencies.
  return (reads: {'fill', 'stroke', 'O', 'R', 'Xy', 'J', 'j', 'w', 'M', 'd', 'XR'}.difference(writes), writes: writes);
}

/// Captures known source values separately for printing and private authoring.
Map<int, _NativeShapeInputs> _shapeCopyInputs(
  AiNativeDrawing drawing,
  Iterable<int> boundaries, {
  bool clipping = false,
  List<_NativeSubtreeSpan>? neutralSpans,
  Set<AiNativeContainer> retainedMetadata = const {},
  List<AiNativeAppearanceArtwork> appearanceArtwork = const [],
  String? Function(AiNativeInstruction) stateKey = _nativeArtworkStateKey,
}) {
  final List<_NativeSubtreeSpan> qualifiedNeutral = [
    ...neutralSpans ?? _nativeNeutralArtwork(drawing),
    for (final AiNativeAppearanceArtwork owner in appearanceArtwork)
      for (final AiNativeAppearanceLeaf leaf in owner.leaves.values) ...[
        if (leaf.raster case final AiNativeRaster raster) (start: raster.start, end: raster.end),
        if (leaf.mesh case final AiNativeMesh mesh) (start: mesh.start, end: mesh.end),
        if (leaf.text case final AiNativeContainer text) (start: text.start, end: text.end),
        if (leaf.symbol case final AiNativeContainer symbol) (start: symbol.start, end: symbol.end),
        if (leaf.shape case final AiLiveShape shape) (start: shape.dictionary.start, end: shape.dictionary.end),
      ],
  ]..sort((first, second) => first.start.compareTo(second.start));
  final List<int> positions = boundaries.toSet().toList()..sort();
  if (positions.isEmpty) {
    return {};
  }
  final Map<int, _NativeShapeInputs> result = {};
  final Map<String, AiNativeInstruction> printing = {};
  final Map<String, AiNativeInstruction> native = {};
  final Map<String, int> printingOrigins = {for (final String key in _nativeArtworkStateKeys) key: -1};
  final Map<String, int> nativeOrigins = Map.of(printingOrigins);
  final Map<int, AiNativeLayer> headers = _layerHeaderItems(AiNativeLayers.decode(drawing: drawing));
  final Set<AiNativeContainer> metadata = {};
  final Map<int, ({Set<String> writes, Map<String, AiNativeInstruction> values})> appearanceStyles = {};
  final Map<int, AiLiveShape> styles = {};
  final Set<int> printingStyles = {};
  final Set<int> scopedGradients = {};
  final Set<int> versionComments = {};
  final Set<int> privateScopes = {};
  final List<_NativeShapeInputs?> clips = [];
  int compoundDepth = 0;

  for (final AiNativeAppearanceArtwork owner in appearanceArtwork) {
    if (!identical(owner._owner.structure.drawing, drawing)) {
      throw ArgumentError('Appearance state requires current complete artwork handles.');
    }
    metadata.addAll(owner.metadata);
    privateScopes.addAll(owner._commands.where((command) => command.isPrivate && command.start >= owner.authoring.start && command.end <= owner.authoring.end).map((command) => command.start));
    if (owner.liveShape != null) {
      versionComments.addAll(drawing.items.whereType<AiNativeVersionComment>().where((comment) => comment.start >= owner.authoring.end && comment.end <= owner.end).map((comment) => comment.start));
    }
    for (final AiNativeResourceUse use in [owner.use, ...owner.nestedUses]) {
      final AiNativeAppearance style = owner._owner.resolve(use: use)!;
      final ({Set<String> reads, Set<String> writes}) state = _nativeAppearanceStyleState(owner._owner, style);
      appearanceStyles[use.instruction.end] = (writes: state.writes, values: _nativeAppearanceScalarState(style, state.reads, colors: true));
    }
    printingStyles.addAll(owner._commands.where((command) => _marker(command, 6)).map((command) => command.start));
    scopedGradients.addAll(
      owner._commands
          .where((command) => command.start >= owner.printingGroup.start && command.end <= owner.printingGroup.end && _gradientCommands.contains(command.operator))
          .map((command) => command.start),
    );
  }

  /// Freezes source assignments and unknown-value provenance at one boundary.
  _NativeShapeInputs snapshot() => (printing: Map.of(printing), native: Map.of(native), printingOrigins: Map.of(printingOrigins), nativeOrigins: Map.of(nativeOrigins));

  /// Restores only actual contour attributes saved by ordinary clipping groups.
  void restore(_NativeShapeInputs saved, {bool private = false}) {
    for (final String key in _nativeClipStateKeys) {
      if (!private) {
        printing.remove(key);
      }
      native.remove(key);
      if (saved.printing[key] case final AiNativeInstruction value when !private) {
        printing[key] = value;
      }
      if (saved.native[key] case final AiNativeInstruction value) {
        native[key] = value;
      }
      if (!private) {
        printingOrigins[key] = saved.printingOrigins[key]!;
      }
      nativeOrigins[key] = saved.nativeOrigins[key]!;
    }
  }

  /// Distinguishes unknown values across opaque or conditional source boundaries.
  void barrier(int start, {required bool private}) {
    native.clear();
    for (final String key in _nativeArtworkStateKeys) {
      nativeOrigins[key] = start;
    }
    if (!private) {
      printing.clear();
      printingOrigins.addAll(nativeOrigins);
    }
  }

  for (final AiLiveShape shape in drawing.liveShapes.where((shape) => shape.isBound && shape.start < positions.last)) {
    try {
      for (final AiNativeContainer dictionary in [shape.dictionary, ?shape.appearanceDictionary, ...shape.alternativeDictionaries]) {
        _shapeCopyDictionary(drawing, shape, dictionary);
        metadata.add(dictionary);
      }
      if (shape.alternativeDictionaries.isNotEmpty) {
        versionComments.addAll(drawing.items.whereType<AiNativeVersionComment>().where((item) => item.start >= shape.path!.end && item.end <= shape.end).map((item) => item.start));
      }
      if (shape.style != null) {
        final List<AiNativeResourceUse> uses = drawing._objects.structure.resourceUses.where((use) => use.kind == .knownStyle && use.instruction.end == shape.end).toList();
        if (uses.length != 1 || uses.single.resolution != .resolved || uses.single.candidates.single.versions.isNotEmpty) {
          throw UnsupportedError('Conditional style declarations cannot establish inherited state.');
        }
        _shapeCopyStyleState(drawing, shape);
        if (shape.appearanceGroup case final AiNativeGroup group) {
          _printingState(drawing, group);
          scopedGradients.addAll(
            _pathInterval(
              drawing.items,
              group.start,
              group.end,
              (item) => item.start,
            ).whereType<AiNativeInstruction>().where((item) => _gradientCommands.contains(item.operator)).map((item) => item.start),
          );
        }
        styles[shape.end] = shape;
        printingStyles.addAll(drawing.items.whereType<AiNativeInstruction>().where((item) => item.start >= shape.start && item.end <= shape.end && _marker(item, 6)).map((item) => item.start));
      }
    } on UnsupportedError {
      // Unknown neighboring owners retain their state barrier.
    } on FormatException {
      // Malformed neighboring state does not establish inherited values.
    }
  }
  int index = 0;
  int neutralIndex = 0;
  for (final int position in positions) {
    while (index < drawing.items.length && drawing.items[index].end <= position) {
      final AiNativeItem item = drawing.items[index++];
      while (neutralIndex < qualifiedNeutral.length && qualifiedNeutral[neutralIndex].end <= item.start) {
        neutralIndex++;
      }
      if (neutralIndex < qualifiedNeutral.length && item.start >= qualifiedNeutral[neutralIndex].start && item.end <= qualifiedNeutral[neutralIndex].end) {
        continue;
      }
      if (headers.containsKey(item.start) && (headers[item.start]!.bindingIssue == null || retainedMetadata.contains(headers[item.start]!.dictionary)) ||
          _ordinaryObjectAttachment(drawing, item) ||
          retainedMetadata.contains(drawing._objects._attachments[item.start]?.dictionary) ||
          metadata.contains(item) ||
          versionComments.contains(item.start)) {
        continue;
      }
      if (item is AiNativeInstruction) {
        if (clipping && (!item.isPrivate || privateScopes.contains(item.start)) && item.operands.isEmpty) {
          switch (item.operator) {
            case '*u':
              compoundDepth++;
              continue;
            case '*U':
              compoundDepth--;
              continue;
            case 'q':
              clips.add(compoundDepth == 0 ? snapshot() : null);
              continue;
            case 'Q':
              if (clips.isEmpty) {
                throw const FormatException('Clipping state requires matched group boundaries.');
              }
              if (clips.removeLast() case final _NativeShapeInputs saved) {
                restore(saved, private: item.isPrivate);
              }
              continue;
            case 'h' || 'H' || 'W':
              continue;
          }
        }
        final String? key;
        try {
          key = stateKey(item);
        } on FormatException {
          barrier(item.start, private: item.isPrivate);
          continue;
        }
        if (key != null) {
          native[key] = item;
          if (!item.isPrivate) {
            printing[key] = item;
          }
          continue;
        }
        if (appearanceStyles[item.end] case final ({Set<String> writes, Map<String, AiNativeInstruction> values}) style when _marker(item, 0) || _marker(item, 1)) {
          native.removeWhere((key, _) => style.writes.contains(key));
          for (final String key in style.writes) {
            nativeOrigins[key] = item.start;
          }
          native.addAll(style.values);
          continue;
        }
        if (styles[item.end] case final AiLiveShape shape when _marker(item, 1)) {
          final Set<String> changed = _shapeCopyStyleState(drawing, shape).writes;
          native.removeWhere((key, _) => changed.contains(key));
          for (final String key in changed) {
            nativeOrigins[key] = item.start;
          }
          final List<AiNativeContainer> records = drawing.records.containers.where((record) => record.start >= shape.style!.start && record.end <= shape.style!.end).toList();
          final List<AiNativeContainer> effectOwners = records.where((record) => _nativeAppearanceKind(record, _nativeAppearanceFilter(record)) == .nativeEffect).toList();
          final List<AiNativeContainer> outgoing = records.where((record) => !effectOwners.any((effect) => record.start >= effect.start && record.end <= effect.end)).toList();
          if (outgoing.every((record) => record['Visible'] == null || record['Visible']!.number == 1)) {
            final Map<String, List<AiNativeInstruction>> candidates = {};
            for (final AiNativeContainer record in outgoing.where((record) => const {'FillStyle', 'StrokeStyle', 'BlendStyle'}.contains(record.type))) {
              for (final AiNativeInstruction command in AiNativePaintStyle.decode(records: drawing.records, record: record).instructions) {
                final String? key = _nativeArtworkStateKey(command);
                if (key != null && key != 'fill' && key != 'stroke') {
                  (candidates[key] ??= []).add(command);
                }
              }
            }
            for (final MapEntry<String, List<AiNativeInstruction>> entry in candidates.entries) {
              if (entry.value.every((command) => _sameNativeArtworkState(command, entry.value.first))) {
                native[entry.key] = entry.value.first;
              }
            }
          }
          continue;
        }
        if (scopedGradients.contains(item.start) || printingStyles.contains(item.start) || item.operator == 'Xd' && item.numbers?.length == 2 && item.numbers!.every((value) => value == 0)) {
          continue;
        }
        if (_nativeGeometry.contains(item.operator) || _nativePaint.contains(item.operator) || const {'u', 'U', '*u', '*U', 'As', 'Ae'}.contains(item.operator)) {
          continue;
        }
      }
      barrier(item.start, private: drawing.records._projection.isPrivate(item.start));
    }
    result[position] = snapshot();
  }
  return result;
}

/// Selects attributes read by a path before any following style application.
Set<String> _shapeCopyReads(AiNativeDrawing drawing, AiNativePath path) => {
  'A',
  'Xw',
  'Ap',
  'D',
  'XR',
  if (!const {'n', 'N'}.contains(path.paint.operator)) 'Xy',
  if (const {'f', 'F', 'b', 'B'}.contains(path.paint.operator)) ...[
    'O',
    if (!drawing.gradients.any((gradient) => gradient.paths.contains(path))) 'fill',
  ],
  if (const {'s', 'S', 'b', 'B'}.contains(path.paint.operator) || drawing.gradients.any((gradient) => gradient.paths.contains(path) && gradient.closing.numbers!.single != 0)) ...[
    'stroke',
    'R',
    'J',
    'j',
    'w',
    'M',
    'd',
  ],
};

/// Describes source dependencies without executing a pair's retained appearance.
_NativeShapeAccess _shapeAccess(AiNativeDrawing drawing, _NativeShapeBundle copy) {
  final Map<int, AiNativePath> paths = {
    for (final AiNativePath path in [...copy.shape.appearancePaths, copy.shape.path!]) path.start: path,
  };
  final Set<String> printingWrites = {};
  final Set<String> nativeWrites = {};
  final Set<String> printingReads = {};
  final Set<String> nativeReads = {};
  for (final AiNativeInstruction command in copy.commands) {
    final String? key = _nativeArtworkStateKey(command);
    if (key != null) {
      nativeWrites.add(key);
      if (!command.isPrivate) {
        printingWrites.add(key);
      }
      continue;
    }
    final Set<String> reads = paths.containsKey(command.start)
        ? _shapeCopyReads(drawing, paths[command.start]!)
        : const {'u', '*u'}.contains(command.operator)
        ? {'A', 'Xw'}
        : _marker(command, 6)
        ? {'Xy'}
        : _marker(command, 1)
        ? copy.styleReads
        : {};
    nativeReads.addAll(reads.difference(nativeWrites));
    if (!command.isPrivate && command.operator != 'XW') {
      printingReads.addAll(reads.difference(printingWrites));
    }
  }
  nativeWrites.addAll(copy.styleWrites);
  return (printingReads: printingReads, nativeReads: nativeReads, printingWrites: printingWrites, nativeWrites: nativeWrites);
}

/// Restores only read-before-write values that the preceding original can change.
List<int> _shapeCopyPrefix(AiNativeDrawing drawing, _NativeShapeBundle copy, _NativeShapeInputs inputs, int maxBytes) => _nativeCopyPrefix(_shapeAccess(drawing, copy), inputs, maxBytes);

/// Restores read-before-write inputs of a qualified interval in both projections.
List<int> _nativeCopyPrefix(_NativeShapeAccess access, _NativeShapeInputs inputs, int maxBytes) {
  final Set<String> printingNeeded = access.printingReads.intersection(access.printingWrites);
  final Set<String> nativeNeeded = access.nativeReads.intersection(access.nativeWrites);
  final StringBuffer prefix = StringBuffer();

  /// Bounds generated source before retaining an additional replay instruction.
  void append(AiNativeInstruction value, {bool private = false}) {
    final String text = _shapeStateText(value, private: private);
    if (prefix.length + text.length > maxBytes) {
      throw const AiLimitException(message: 'Native copy state exceeds the native byte limit.');
    }
    prefix.write(text);
  }

  for (final String key in printingNeeded) {
    final AiNativeInstruction? value = inputs.printing[key];
    if (value == null) {
      throw UnsupportedError('The native copy requires an unknown inherited printing $key value.');
    }
    append(value);
  }
  for (final String key in nativeNeeded) {
    final AiNativeInstruction? value = inputs.native[key];
    if (value == null) {
      throw UnsupportedError('The native copy requires an unknown inherited native $key value.');
    }
    if (printingNeeded.contains(key) && _sameNativeArtworkState(value, inputs.printing[key])) {
      continue;
    }
    append(value, private: true);
  }
  return latin1.encode(prefix.toString());
}
