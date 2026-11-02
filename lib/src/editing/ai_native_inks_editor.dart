part of 'package:aikit/src/model/ai_native_records.dart';

/// Collects named applications from source-owned commands without scanning bytes.
List<AiNativeInstruction> _nativeInkPaints(AiNativeAppearances model) => {
  for (final AiNativeInstruction command in [
    ..._structureCommands(model.structure.drawing),
    for (final AiNativeArtworkResource resource in model.artworkResources.resources) ...resource._drawing.items.whereType<AiNativeInstruction>(),
    for (final AiNativePalette palette in AiNativeSwatches.decode(records: model.structure.drawing.records).palettes)
      for (final AiNativeSwatch cell in palette.swatches) ...cell.commands,
  ])
    if (_nativeNamedColorOperators.contains(command.operator)) command.start: command,
}.values.toList();

/// Groups explicit references by exact decoded bytes rather than display names.
AiNativeInks _readNativeInks(AiNativeRecords records) {
  final AiNativeDrawing drawing = AiNativeDrawing.decode(records: records);
  final AiNativeAppearances appearances = AiNativeAppearances.decode(structure: AiNativeStructure.decode(drawing: drawing));
  final Map<String, List<AiNativeInstruction>> paints = {};
  final Map<String, Set<AiNativeGradientDefinition>> gradients = {};
  final Map<String, Set<AiNativeMesh>> meshes = {};
  for (final AiNativeInstruction command in _nativeInkPaints(appearances)) {
    final AiNativeNamedColor color = AiNativeNamedColor.decode(instruction: command)!;
    (paints[latin1.decode(color.nameBytes)] ??= []).add(command);
  }
  for (final AiNativeGradientDefinition definition in AiNativeGradientResources.decode(records: records).definitions) {
    for (final AiNativeGradientStop stop in [...definition.stops, ...definition.fallbackStops]) {
      if (stop.color.nameBytes case final Uint8List name) {
        (gradients[latin1.decode(name)] ??= {}).add(definition);
      }
    }
  }
  for (final AiNativeMesh mesh in AiNativeMeshes.decode(records: records).meshes) {
    for (final AiNativeMeshField field in mesh.fields.where((field) => field.key == 'CS')) {
      for (final AiNativeMeshInk ink in _meshColorSpace(field).inks) {
        (meshes[latin1.decode(ink.nameBytes)] ??= {}).add(mesh);
      }
    }
  }
  return AiNativeInks._(
    appearances: appearances,
    inks: [
      for (final String name in {...paints.keys, ...gradients.keys, ...meshes.keys})
        AiNativeInk._(nameBytes: latin1.encode(name), paints: paints[name] ?? [], gradients: gradients[name]?.toList() ?? [], meshes: meshes[name]?.toList() ?? []),
    ],
  );
}

/// Covers each application exactly once through its complete printing owner.
List<AiNativeAppearanceArtwork> _nativeInkPrintingOwners(AiNativeAppearances model) {
  final Map<int, AiNativeAppearanceArtwork> owners = {};
  final Set<AiNativeResourceUse> covered = {};
  for (final AiNativeResourceUse use in model.uses) {
    try {
      final AiNativeAppearanceArtwork owner = model.artworkFor(use: use);
      owners[owner.printingGroup.start] = owner;
      covered.addAll([owner.use, ...owner.nestedUses]);
    } on UnsupportedError {
      // Nested applications are covered by the complete outer pair. Every use
      // still has to be covered after all possible outer owners were inspected.
    }
  }
  if (model.uses.any((use) => !covered.contains(use))) {
    throw UnsupportedError('Global ink changes require complete printing ownership for every appearance application.');
  }
  return owners.values.toList();
}

/// Requires every explicit alternative without silently choosing a color profile.
List<double> _nativeInkComponents(AiColorSpace space, AiColor? cmyk, AiColor? rgb, AiColor? gray) {
  final AiColor? value = switch (space) {
    .cmyk => cmyk,
    .rgb => rgb,
    .gray => gray,
  };
  if (value == null) {
    throw ArgumentError('The source ink requires an explicit ${space.name} alternative.');
  }
  return value.channels;
}

/// Rejects hidden same-name references outside qualified native color fields.
void _nativeInkReferenceScope(AiNativeInks model, AiNativeInk ink) {
  _paintResourceScope(model.records);
  _nativeInkResourceDependencies(model, ink);
  final List<({int start, int end})> spans = [
    for (final AiNativeInstruction command in ink.paints) (start: command.start, end: command.end),
    for (final AiNativeGradientDefinition definition in ink.gradients) (start: definition.start, end: definition.end),
    for (final AiNativeMesh mesh in ink.meshes)
      for (final AiNativeMeshField field in mesh.fields.where((field) => field.key == 'CS')) (start: field.start, end: field.end),
    for (final AiNativePalette palette in AiNativeSwatches.decode(records: model.records).palettes)
      for (final AiNativeSwatch cell in palette.swatches) (start: cell.commands.last.end, end: cell.end),
  ]..sort((first, second) => first.start.compareTo(second.start));
  int index = 0;
  for (final AiToken token in model.records._projection.tokens) {
    if (!const {AiTokenKind.string, AiTokenKind.hexString}.contains(token.kind) || !_sameNativeBytes(aiStringBytes(token), ink.nameBytes)) {
      continue;
    }
    while (index < spans.length && spans[index].end <= token.start) {
      index++;
    }
    if (index == spans.length || token.start < spans[index].start || token.end > spans[index].end) {
      throw UnsupportedError('A same-name ink reference has no qualified color owner.');
    }
  }
  final AiNativeVersions versions = AiNativeVersions.decode(records: model.records);
  if (spans.any((span) => versions.memberships(start: span.start, end: span.end).isNotEmpty)) {
    throw UnsupportedError('Global ink changes cannot select a conditional reference branch.');
  }
  for (final AiNativeMesh mesh in ink.meshes) {
    _validateMeshPaintOwner(model.records, mesh, drawing: model.appearances.structure.drawing);
    if (mesh.fields.where((field) => field.key == 'CS').any((field) => _meshColorSpace(field).componentCount == null)) {
      throw UnsupportedError('Global ink changes require qualified mesh color-space declarations.');
    }
  }
}

/// Compares full authoritative stops before merging duplicate gradient banks.
bool _sameInkGradient(AiNativeGradientDefinition first, AiNativeGradientDefinition second) =>
    first.radial == second.radial &&
    first.stops.length == second.stops.length &&
    first.stops.indexed.every((entry) {
      final AiNativeGradientStop a = entry.$2;
      final AiNativeGradientStop b = second.stops[entry.$1];
      return a.position == b.position &&
          a.midpoint == b.midpoint &&
          a.opacity == b.opacity &&
          a.hasOpacity == b.hasOpacity &&
          a.color.kind == b.color.kind &&
          a.color.tint == b.color.tint &&
          _sameNativeBytes(a.color.nameBytes ?? [], b.color.nameBytes ?? []) &&
          a.color.components.length == b.color.components.length &&
          a.color.components.indexed.every((component) => component.$2 == b.color.components[component.$1]);
    });

/// Refreshes all representations before returning a globally redefined snapshot.
AiNativeInks _redefineNativeInk(
  AiNativeInks model,
  AiNativeInk ink,
  AiColor? cmyk,
  AiColor? rgb,
  AiColor? gray,
  Map<AiNativeGradientDefinition, List<AiNativeGradientRamp>> ramps,
  List<AiNativeAppearanceReplacement> artwork,
) {
  if (!model.inks.contains(ink) || cmyk != null && cmyk.space != .cmyk || rgb != null && rgb.space != .rgb || gray != null && gray.space != .gray || cmyk == null && rgb == null && gray == null) {
    throw ArgumentError('Global ink changes require a current ink and correctly typed explicit device alternatives.');
  }
  _nativeInkReferenceScope(model, ink);
  final Map<String, AiNativeGradientDefinition> definitions = {};
  for (final AiNativeGradientDefinition definition in ink.gradients) {
    if (definition.fallbackStops.isNotEmpty &&
        (definition.fallbackStops.length != definition.stops.length ||
            definition.stops.indexed.any((entry) => !_sameNativeBytes(entry.$2.color.nameBytes ?? [], definition.fallbackStops[entry.$1].color.nameBytes ?? [])))) {
      throw UnsupportedError('Authoritative and compatibility gradient stops must bind the same ink identities.');
    }
    final String key = latin1.decode(definition.nameBytes);
    if (definitions[key] case final AiNativeGradientDefinition other when !_sameInkGradient(other, definition)) {
      throw UnsupportedError('Global ink changes require consistent duplicate gradient banks.');
    }
    definitions[key] = definition;
  }
  final Map<String, List<AiNativeGradientRamp>> supplied = {};
  for (final MapEntry<AiNativeGradientDefinition, List<AiNativeGradientRamp>> entry in ramps.entries) {
    final String key = latin1.decode(entry.key.nameBytes);
    if (!ink.gradients.contains(entry.key) || supplied.containsKey(key)) {
      throw ArgumentError('Supply one current ramp set per affected gradient name.');
    }
    supplied[key] = entry.value;
  }
  if (definitions.length != supplied.length || definitions.keys.any((key) => !supplied.containsKey(key))) {
    throw ArgumentError('Every gradient using the ink requires freshly composed printing ramps.');
  }
  final List<AiNativeAppearanceArtwork> owners = model.printingOwners;
  if (artwork.length != owners.length ||
      artwork.map((value) => value.artwork.printingGroup).toSet().length != owners.length ||
      artwork.any((value) => !identical(value.artwork._owner, model.appearances) || !owners.any((owner) => owner.printingGroup == value.artwork.printingGroup))) {
    throw ArgumentError('Global ink changes require one current replacement for every complete printing owner.');
  }
  final AiNativeAppearances printed = _nativeAppearanceResult(model.appearances, _nativeAppearancePrintingEdits(model.appearances, artwork), owners.map((owner) => owner.use).toList());
  AiNativeInks current = AiNativeInks.decode(records: printed.structure.drawing.records);
  for (final MapEntry<String, List<AiNativeGradientRamp>> entry in supplied.entries) {
    final AiNativeGradientResources gradients = AiNativeGradientResources.decode(records: current.records);
    final AiNativeGradientDefinition definition = gradients.definitions.firstWhere((definition) => latin1.decode(definition.nameBytes) == entry.key);
    final List<AiNativeGradientStop> stops = [
      for (final AiNativeGradientStop stop in definition.radial ? definition.stops : definition.stops.reversed)
        if (stop.color.nameBytes == null || !_sameNativeBytes(stop.color.nameBytes!, ink.nameBytes))
          stop
        else
          AiNativeGradientStop(
            color: AiNativeGradientColor(
              kind: stop.color.kind,
              components: [
                ..._nativeInkComponents(.cmyk, cmyk, rgb, gray),
                if (stop.color.kind == .customRgb || stop.color.kind == .namedRgb) ..._nativeInkComponents(.rgb, cmyk, rgb, gray),
              ],
              nameBytes: stop.color.nameBytes,
              tint: stop.color.tint,
            ),
            position: stop.position,
            midpoint: stop.midpoint,
            opacity: stop.opacity,
            hasOpacity: stop.hasOpacity,
          ),
    ];
    current = AiNativeInks.decode(
      records: gradients.replaceStops(definition: definition, stops: stops, ramps: entry.value).records,
    );
  }
  final AiNativeInk? remaining = current.inks.where((value) => _sameNativeBytes(value.nameBytes, ink.nameBytes)).singleOrNull;
  if (remaining == null) {
    throw UnsupportedError('The supplied printing removed the selected ink without any authoritative reference.');
  }
  final Map<int, AiSourceEdit> edits = {};

  /// Preserves unchanged numeric spelling and deduplicates overlapping inventories.
  void component(AiToken token, double value) {
    if (token.number != value) {
      edits[token.start] = AiSourceEdit(start: token.start, end: token.end, bytes: latin1.encode('$value'));
    }
  }

  for (final AiNativeInstruction command in remaining.paints) {
    final AiNativeNamedColor color = AiNativeNamedColor.decode(instruction: command)!;
    final List<double> components = switch (color.kind) {
      .customRgb => _nativeInkComponents(.rgb, cmyk, rgb, gray),
      .namedRgb => [..._nativeInkComponents(.cmyk, cmyk, rgb, gray), ..._nativeInkComponents(.rgb, cmyk, rgb, gray)],
      _ => _nativeInkComponents(.cmyk, cmyk, rgb, gray),
    };
    for (final (int index, double value) in components.indexed) {
      component(command.operands[index], value);
    }
  }
  for (final AiNativeMesh mesh in remaining.meshes) {
    for (final AiNativeMeshField field in mesh.fields.where((field) => field.key == 'CS')) {
      final List<AiToken> values = field.values;
      for (int index = 0; index < values.length; index++) {
        if (!const {AiTokenKind.string, AiTokenKind.hexString}.contains(values[index].kind) || !_sameNativeBytes(aiStringBytes(values[index]), ink.nameBytes)) {
          continue;
        }
        final AiColorSpace space = switch (values[index - 1].lexeme) {
          '/DeviceGray' => .gray,
          '/DeviceRGB' => .rgb,
          '/DeviceCMYK' => .cmyk,
          _ => throw UnsupportedError('Unknown mesh ink alternative.'),
        };
        final List<double> components = _nativeInkComponents(space, cmyk, rgb, gray);
        for (final (int offset, double value) in components.indexed) {
          component(values[index - components.length - 1 + offset], value);
        }
      }
    }
  }
  final AiNativeInks result = AiNativeInks.decode(
    records: AiNativeRecords.decode(
      program: AiNativeEditor.apply(program: current.records.program, edits: [...edits.values, ..._nativeInkHeaderEdits(current.records, ink.nameBytes, cmyk, rgb, gray)]),
    ),
  );
  _nativeInkReferenceScope(result, result.inks.singleWhere((value) => _sameNativeBytes(value.nameBytes, ink.nameBytes)));
  return result;
}

/// One literal document-level DSC ink declaration or ink-name list.
typedef _AiNativeInkHeader = ({AiToken source, int prefix, AiColorSpace? space, List<AiToken> values});

/// Qualifies only header/trailer comments, never embedded or executable content.
List<_AiNativeInkHeader> _nativeInkHeaders(AiNativeRecords records) {
  final List<_AiNativeInkHeader> result = [];
  final AiProgram program = records.program;
  final int headerEnd =
      records._projection.tokens.where((token) => token.kind == .comment && const {'%%EndComments', '%%BeginProlog', '%%BeginSetup'}.contains(token.lexeme)).firstOrNull?.start ?? program.bodyStart;
  AiColorSpace? continued;
  bool names = false;
  for (final AiToken token in records._projection.tokens) {
    if (token.start >= headerEnd && token.start < program.bodyEnd || token.kind != .comment) {
      continued = null;
      names = false;
      continue;
    }
    final String text = token.lexeme;
    final int prefix;
    final AiColorSpace? space;
    if (text.startsWith('%%DocumentCustomColors:')) {
      space = null;
      names = true;
      prefix = '%%DocumentCustomColors:'.length;
    } else if (text.startsWith('%%CMYKCustomColor:')) {
      space = .cmyk;
      names = false;
      prefix = '%%CMYKCustomColor:'.length;
    } else if (text.startsWith('%%RGBCustomColor:')) {
      space = .rgb;
      names = false;
      prefix = '%%RGBCustomColor:'.length;
    } else if (text.startsWith('%%+') && (continued != null || names)) {
      space = continued;
      prefix = 3;
    } else {
      continued = null;
      names = false;
      continue;
    }
    continued = space;
    final AiNativeLimits limits = program.limits;
    final List<AiToken> values = AiPostScript.tokenize(latin1.encode(text.substring(prefix)), maxBytes: limits.maxDecodedBytes, maxTokens: limits.maxTokens, maxDepth: limits.maxDepth);
    final bool deferred = values.length == 1 && values.single.kind == .string && _sameNativeBytes(aiStringBytes(values.single), ascii.encode('atend'));
    final int count = space == .cmyk ? 4 : 3;
    if (!deferred &&
        (space == null
            ? values.isEmpty || values.any((value) => !const {AiTokenKind.string, AiTokenKind.hexString}.contains(value.kind))
            : values.length != count + 1 ||
                  values.take(count).any((value) => value.number == null || !_gradientUnit(value.number!.toDouble())) ||
                  !const {AiTokenKind.string, AiTokenKind.hexString}.contains(values.last.kind))) {
      throw UnsupportedError('Native ink headers require literal names and device alternatives.');
    }
    result.add((source: token, prefix: prefix, space: deferred ? null : space, values: values));
  }
  return result;
}

/// Refreshes literal DSC alternatives, including continuation declarations.
List<AiSourceEdit> _nativeInkHeaderEdits(AiNativeRecords records, List<int> name, AiColor? cmyk, AiColor? rgb, AiColor? gray) {
  final List<AiSourceEdit> edits = [];
  for (final _AiNativeInkHeader row in _nativeInkHeaders(records)) {
    if (row.space == null || !_sameNativeBytes(aiStringBytes(row.values.last), name)) {
      continue;
    }
    final List<double> components = _nativeInkComponents(row.space!, cmyk, rgb, gray);
    for (final (int index, double value) in components.indexed) {
      if (row.values[index].number != value) {
        edits.add(AiSourceEdit(start: row.source.start + row.prefix + row.values[index].start, end: row.source.start + row.prefix + row.values[index].end, bytes: latin1.encode('$value')));
      }
    }
  }
  return edits;
}

/// Propagates ink changes through resource/style edges before touching caches.
void _nativeInkResourceDependencies(AiNativeInks model, AiNativeInk ink) {
  final AiNativeAppearances appearances = model.appearances;
  final List<AiNativeArtworkResource> resources = appearances.artworkResources.resources;
  if (resources.isEmpty) {
    return;
  }
  final List<AiNativeInstruction> patternCommands = [
    ..._structureCommands(appearances.structure.drawing).where((command) => const {'p', 'P'}.contains(command.operator)),
    for (final AiNativeArtworkResource resource in resources) ...resource._drawing.items.whereType<AiNativeInstruction>().where((command) => const {'p', 'P'}.contains(command.operator)),
  ];
  final Set<String> gradients = ink.gradients.map((definition) => latin1.decode(definition.nameBytes)).toSet();
  final Set<String> styles = {};
  final Set<AiNativeArtworkResource> changed = {};
  final Set<String> patterns = {};
  int work = 0;
  bool progress;

  /// Bounds transitive inspection independently of source graph depth.
  void charge() {
    if (++work > model.records.program.limits.maxTokens) {
      throw const AiLimitException(message: 'Global ink resource dependencies exceed native inspection limits.');
    }
  }

  /// Recognizes direct ink commands inside an already-owned source interval.
  bool containsInk(int start, int end) {
    for (final AiNativeInstruction command in ink.paints) {
      charge();
      if (command.start >= start && command.end <= end) {
        return true;
      }
    }
    return false;
  }

  do {
    progress = false;
    for (final AiNativeAppearance style in appearances.styles) {
      charge();
      final String name = latin1.decode(style.resource.nameBytes);
      if (styles.contains(name)) {
        continue;
      }
      final bool depends =
          containsInk(style.resource.definition.start, style.resource.definition.end) ||
          [?style.simplePaint, for (final AiNativeAppearancePart part in style.parts) ...part.paints.map((paint) => paint.style)].expand((paint) => paint.instructions).any((command) {
            charge();
            return command.operator == 'Bg' && gradients.contains(latin1.decode(aiStringBytes(command.operands[1]))) ||
                const {'p', 'P'}.contains(command.operator) && patterns.contains(latin1.decode(aiStringBytes(command.operands.first)));
          });
      if (depends) {
        styles.add(name);
        progress = true;
      }
    }
    for (final AiNativeArtworkResource resource in resources) {
      charge();
      if (changed.contains(resource)) {
        continue;
      }
      if (containsInk(resource.artworkStart, resource.artworkEnd) ||
          patternCommands.any((command) {
            charge();
            return command.start >= resource.artworkStart && command.end <= resource.artworkEnd && patterns.contains(latin1.decode(aiStringBytes(command.operands.first)));
          }) ||
          resource.uses.any((use) {
            charge();
            return (use.kind == .gradient ? gradients : styles).contains(latin1.decode(use.nameBytes));
          })) {
        changed.add(resource);
        if (resource.kind == .pattern) {
          patterns.add(latin1.decode(resource.nameBytes));
        }
        progress = true;
      }
    }
  } while (progress);
  final AiNativeLayers layers = AiNativeLayers.decode(drawing: appearances.structure.drawing);
  final _ArtboardBrushScope brushes = _artboardBrushScope(layers, resources.where((resource) => resource.kind == .brush).map((resource) => latin1.decode(resource.nameBytes)).toSet());
  if (changed.any((resource) => resource.kind == .symbol || resource.kind == .brush && brushes.artwork.contains(latin1.decode(resource.nameBytes)))) {
    throw UnsupportedError('Changed symbol or referenced brush ink requires complete instance-cache replacement.');
  }
}
