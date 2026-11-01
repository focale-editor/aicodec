part of 'package:aikit/src/model/ai_native_records.dart';

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
  'Execution' => field.container?.type == 'CompoundFilter',
  'Part' => const {'CompoundFilter', 'BasicFilter'}.contains(field.container?.type),
  'Dict' => field.container?.type == 'Dictionary',
  'FillStyle' || 'StrokeStyle' || 'BlendStyle' => field.container?.type == field.key,
  'DisplayString' => const {'String', 'UnicodeString'}.contains(field.type) && field.stringBytes != null,
  'UseEvenOdd' || 'StrokeOffsetInside' => field.type == 'Bool' && field.boolean != null,
  'NotRecorded' => field.isQualifier,
  _ => false,
};

/// Identifies state writes without executing appearance filters or drawing art.
({Set<String> reads, Set<String> writes}) _shapeCopyStyleState(AiNativeDrawing drawing, AiLiveShape shape) => _nativeLiteralStyleState(drawing, shape.style!);

/// Qualifies a literal style independently of any particular referencing shape.
({Set<String> reads, Set<String> writes}) _nativeLiteralStyleState(AiNativeDrawing drawing, AiNativeContainer style) {
  if (drawing._objects.structure.versions.blocks.any((block) => block.start < style.end && block.end > style.start)) {
    throw UnsupportedError('Shape copies require unconditional native filter execution.');
  }
  if (style['Def']?.container case final AiNativeContainer definition when definition.type == 'SimpleStyle') {
    return _nativeSimpleStyleState(drawing, style, definition);
  }
  _LiveShapeEditor(drawing: drawing, shapes: [])._checkStyle(style);
  final Set<String> writes = {};
  final Set<String> reads = {};
  for (final AiNativeContainer record in drawing.records.containers.where((record) => record.start >= style.start && record.end <= style.end)) {
    if (record.entries.any((field) => !_shapeCopyStyleField(record, field))) {
      throw UnsupportedError('Shape copies require literal, typed native filter fields.');
    }
    final String? plugin = record['PluginFileName']?.text();
    if (plugin != null && !const {'Illustrator.exe', 'StrokeOffset.aip'}.contains(plugin)) {
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

/// Qualifies process-only SimpleStyle commands without assuming disabled paints.
({Set<String> reads, Set<String> writes}) _nativeSimpleStyleState(AiNativeDrawing drawing, AiNativeContainer style, AiNativeContainer definition) {
  _artboardSetupRecord(AiNativeLayers.decode(drawing: drawing), style);
  _artboardStyleFields(style, {'Name', 'Def'});
  _artboardStyleFields(definition, {'Paint'});
  if (style.entries.length != 2 || style['Name']?.stringBytes?.isNotEmpty != true) {
    throw UnsupportedError('Simple appearance state requires an owned named definition.');
  }
  final Set<String> writes = {};
  for (final AiNativeInstruction command in AiNativePaintStyle.decode(records: drawing.records, record: definition).instructions) {
    if (!_solidStyleCommands.contains(command.operator)) {
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
  Set<AiNativeContainer> retainedMetadata = const {},
  String? Function(AiNativeInstruction) stateKey = _nativeArtworkStateKey,
}) {
  final List<int> positions = boundaries.toSet().toList()..sort();
  final Map<int, _NativeShapeInputs> result = {};
  final Map<String, AiNativeInstruction> printing = {};
  final Map<String, AiNativeInstruction> native = {};
  final Map<String, int> printingOrigins = {for (final String key in _nativeArtworkStateKeys) key: -1};
  final Map<String, int> nativeOrigins = Map.of(printingOrigins);
  final Map<int, AiNativeLayer> headers = _layerHeaderItems(AiNativeLayers.decode(drawing: drawing));
  final Set<AiNativeContainer> metadata = {};
  final Map<int, AiLiveShape> styles = {};
  final Set<int> printingStyles = {};
  final Set<int> scopedGradients = {};
  final Set<int> versionComments = {};
  final List<_NativeShapeInputs?> clips = [];
  int compoundDepth = 0;

  /// Freezes source assignments and unknown-value provenance at one boundary.
  _NativeShapeInputs snapshot() => (printing: Map.of(printing), native: Map.of(native), printingOrigins: Map.of(printingOrigins), nativeOrigins: Map.of(nativeOrigins));

  /// Restores only actual contour attributes saved by ordinary clipping groups.
  void restore(_NativeShapeInputs saved) {
    for (final String key in _nativeClipStateKeys) {
      printing.remove(key);
      native.remove(key);
      if (saved.printing[key] case final AiNativeInstruction value) {
        printing[key] = value;
      }
      if (saved.native[key] case final AiNativeInstruction value) {
        native[key] = value;
      }
      printingOrigins[key] = saved.printingOrigins[key]!;
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
  for (final int position in positions) {
    while (index < drawing.items.length && drawing.items[index].end <= position) {
      final AiNativeItem item = drawing.items[index++];
      if (headers.containsKey(item.start) && (headers[item.start]!.bindingIssue == null || retainedMetadata.contains(headers[item.start]!.dictionary)) ||
          _ordinaryObjectAttachment(drawing, item) ||
          retainedMetadata.contains(drawing._objects._attachments[item.start]?.dictionary) ||
          metadata.contains(item) ||
          versionComments.contains(item.start)) {
        continue;
      }
      if (item is AiNativeInstruction) {
        if (clipping && !item.isPrivate && item.operands.isEmpty) {
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
                restore(saved);
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
        if (styles[item.end] case final AiLiveShape shape when _marker(item, 1)) {
          final Set<String> changed = _shapeCopyStyleState(drawing, shape).writes;
          native.removeWhere((key, _) => changed.contains(key));
          for (final String key in changed) {
            nativeOrigins[key] = item.start;
          }
          final List<AiNativeContainer> records = drawing.records.containers.where((record) => record.start >= shape.style!.start && record.end <= shape.style!.end).toList();
          if (records.every((record) => record['Visible'] == null || record['Visible']!.number == 1)) {
            final Map<String, List<AiNativeInstruction>> candidates = {};
            for (final AiNativeContainer record in records.where((record) => const {'FillStyle', 'StrokeStyle', 'BlendStyle'}.contains(record.type))) {
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
  if (const {'s', 'S', 'b', 'B'}.contains(path.paint.operator)) ...['stroke', 'R', 'J', 'j', 'w', 'M', 'd'],
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
