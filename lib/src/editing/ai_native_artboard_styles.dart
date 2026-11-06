part of 'package:illustratorkit/src/model/ai_native_records.dart';

/// Qualifies retained appearance graphs without applying or transforming them.
void _artboardRetainedStyle(AiNativeLayers layers, AiNativeContainer style, Map<int, AiNativeResourceUse> references, Set<String> patterns, Set<(String, String)> brushes) {
  _artboardSetupRecord(layers, style);
  _artboardStyleFields(style, {'Name', 'Def'});
  if (style.entries.length != 2 || style['Name']?.stringBytes?.isNotEmpty != true) {
    throw UnsupportedError('Retained styles require a literal nonempty name and one definition.');
  }
  final AiNativeContainer? definition = style['Def']?.container;
  if (definition?.type == 'SimpleStyle') {
    _artboardStyleFields(definition!, {'Paint'});
    _artboardStylePaint(layers, definition, 'Paint', references, patterns);
  } else if (definition?.type == 'ActiveStyle') {
    _artboardStyleFields(definition!, {'Execution'});
    final AiNativeContainer? execution = definition['Execution']?.container;
    if (definition.entries.length != 1 || !const {'CompoundFilter', 'BasicFilter'}.contains(execution?.type)) {
      throw UnsupportedError('Retained active styles require one owned filter execution graph.');
    }
    _artboardStyleFilter(layers, execution!, references, patterns, brushes);
  } else {
    throw UnsupportedError('Artboard edits require a qualified retained style definition.');
  }
}

/// Requires unique untyped fields, except for ordered compound appearance parts.
void _artboardStyleFields(AiNativeContainer record, Set<String> keys, {bool parts = false}) {
  final Set<String?> seen = {};
  if (record.hasBinary || record.entries.any((entry) => entry.isQualifier || entry.type != null || !keys.contains(entry.key) || !(seen.add(entry.key) || parts && entry.key == 'Part'))) {
    throw UnsupportedError('Retained ${record.type} has unknown, typed or duplicated appearance fields.');
  }
}

/// Retains ordered stack/chain nodes and filter-local typed parameters.
void _artboardStyleFilter(AiNativeLayers layers, AiNativeContainer filter, Map<int, AiNativeResourceUse> references, Set<String> patterns, Set<(String, String)> brushes) {
  final bool compound = filter.type == 'CompoundFilter';
  if (!compound && filter.type != 'BasicFilter') {
    throw UnsupportedError('Retained appearance parts require compound or basic filters.');
  }
  _artboardStyleFields(filter, compound ? {'Filter', 'Visible', 'Part'} : {'Filter', 'Visible', 'PluginFileName', 'Title', 'FillOrStroke', 'Dict'}, parts: compound);
  final List<AiNativeItem>? descriptor = filter['Filter']?.items;
  if (descriptor == null ||
      descriptor.length != 3 ||
      descriptor.any((item) => item is! AiNativeToken) ||
      !const {AiTokenKind.string, AiTokenKind.hexString}.contains((descriptor.first as AiNativeToken).token.kind) ||
      !const {0, 1}.contains((descriptor[1] as AiNativeToken).token.number) ||
      (descriptor.last as AiNativeToken).token.number != 0 ||
      filter['Visible'] != null && !const {0, 1}.contains(filter['Visible']!.number) ||
      filter['Title'] != null && filter['Title']!.stringBytes == null ||
      filter['FillOrStroke'] != null && !const {0, 1, 2}.contains(filter['FillOrStroke']!.number)) {
    throw UnsupportedError('Retained appearance filters require literal descriptors and flags.');
  }
  final String name = latin1.decode(aiStringBytes((descriptor.first as AiNativeToken).token));
  final bool plugin = (descriptor[1] as AiNativeToken).token.number == 1;
  if (compound) {
    if (plugin || !const {'Chain Style Filter', 'Stack Style Filter'}.contains(name)) {
      throw UnsupportedError('Retained compound styles require a known stack or chain.');
    }
    for (final AiNativeEntry entry in filter.entries.where((entry) => entry.key == 'Part')) {
      final AiNativeContainer? part = entry.container;
      if (part == null) {
        throw UnsupportedError('Retained appearance parts cannot contain executable values.');
      }
      _artboardStyleFilter(layers, part, references, patterns, brushes);
    }
    return;
  }
  final String? pluginFile = filter['PluginFileName']?.text();
  final String? legacyPlugin = _artboardStylePlugins[name];
  if (plugin != (legacyPlugin != null) || plugin && pluginFile != 'Illustrator.exe' && pluginFile != legacyPlugin || !plugin && filter['PluginFileName'] != null) {
    throw UnsupportedError('Retained appearance plug-ins require a qualified native descriptor.');
  }
  final Map<String, Set<String>>? fields = _artboardStyleParameters[name];
  if (fields == null) {
    throw UnsupportedError('Artboard dependency qualification does not cover the $name filter.');
  }
  final AiNativeEntry? entry = filter['Dict'];
  if (entry == null && name == 'Conduit Filter') {
    return;
  }
  if (entry == null) {
    throw UnsupportedError('Retained appearance filters require their owned parameter dictionary.');
  }
  final Map<String, String> paints = switch (name) {
    'Fill Style Filter' => {'FillStyle': 'FillStyle'},
    'Stroke Style Filter' || 'Adobe Stroke Offset' || 'Adobe Calligraphic Brush Tool' || 'Adobe ArtOnPath Brush Tool' || 'Adobe PatternOnPath Brush Tool' => {'StrokeStyle': 'StrokeStyle'},
    'Blend Style Filter' => {'BlendStyle': 'BlendStyle'},
    'Adobe Drop Shadow' || 'Adobe Outer Glow' => {'sclr': 'FillStyle'},
    _ => {},
  };
  final AiNativeContainer dictionary = _referenceRecord(entry, 'Dictionary');
  if (const {'Adobe Calligraphic Brush Tool', 'Adobe ArtOnPath Brush Tool', 'Adobe PatternOnPath Brush Tool'}.contains(name) && (dictionary['Brush'] == null || dictionary['StrokeStyle'] == null)) {
    throw UnsupportedError('Retained calligraphic styles require an owned brush reference and stroke.');
  }
  _referenceFields(
    dictionary,
    fields,
    notRecorded: true,
    nested: {
      if (const {'Stroke Style Filter', 'Adobe Stroke Offset'}.contains(name)) 'kAIBeautifulStrokesParamsDictKey': _nativeAppearanceStrokeDictionary,
      if (const {'Adobe Calligraphic Brush Tool', 'Adobe ArtOnPath Brush Tool', 'Adobe PatternOnPath Brush Tool'}.contains(name)) 'Brush': (field) => _artboardBrushReference(field, name, brushes),
      for (final MapEntry<String, String> paint in paints.entries)
        paint.key: (field) {
          final AiNativeContainer record = _referenceRecord(field, paint.value);
          _artboardStyleFields(record, {'Def'});
          _artboardStylePaint(layers, record, 'Def', references, patterns);
        },
    },
  );
  for (final AiNativeEntry field in dictionary.entries) {
    if (field.numbers?.any((number) => number.abs() > 9007199254740991) ?? false) {
      throw const FormatException('Retained appearance parameters must be finite portable numbers.');
    }
  }
}

/// Checks retained paint commands and their resource links without emitting art.
void _artboardStylePaint(AiNativeLayers layers, AiNativeContainer record, String key, Map<int, AiNativeResourceUse> references, Set<String> patterns) {
  final AiNativeEntry? entry = record[key];
  if (record.entries.length != 1 || entry == null || entry.items.any((item) => item is! AiNativeToken)) {
    throw UnsupportedError('Retained paints require one literal command field.');
  }
  final List<AiNativeInstruction> commands = [];
  final _NativeCommandReader reader = _NativeCommandReader(maxDepth: layers.drawing.records.program.limits.maxDepth);
  for (final AiNativeToken item in entry.items.cast<AiNativeToken>()) {
    final AiNativeInstruction? command = reader.add(item.token, isPrivate: layers.drawing.records._projection.isPrivate(item.start));
    if (command != null) {
      if (!_solidStyleCommands.contains(command.operator) &&
          !_gradientCommands.contains(command.operator) &&
          !const {'p', 'P'}.contains(command.operator) &&
          !_nativeNamedColorOperators.contains(command.operator)) {
        throw UnsupportedError('Retained paints cannot execute ${command.operator}.');
      }
      commands.add(command);
    }
  }
  reader.finish();
  final AiNativeDrawing drawing = _NativeDrawingReader(records: layers.drawing.records).readItems(commands);
  if (record.type == 'BlendStyle' && drawing.gradients.isNotEmpty) {
    throw UnsupportedError('A retained blend style cannot own a positional gradient.');
  }
  _artboardResourceArtwork(layers, drawing, references, patterns);
}

/// Known native plug-in identifiers, including the older separate-module names.
const Map<String, String> _artboardStylePlugins = {
  'Adobe Calligraphic Brush Tool': 'CalligraphicBrushTool.aip',
  'Adobe ArtOnPath Brush Tool': 'ArtOnPathBrushTool.aip',
  'Adobe PatternOnPath Brush Tool': 'PatternOnPathBrushTool.aip',
  'Adobe Stroke Offset': 'StrokeOffset.aip',
  'Adobe Fuzzy Mask': 'FuzzyEffect.aip',
  'Adobe Round Corners': 'Round.aip',
  'Adobe Offset Path': 'OffsetPath.aip',
  'Adobe Drop Shadow': 'DropShadow.aip',
  'Adobe Outer Glow': 'OuterGlow.aip',
  'Adobe Transform': 'Transform.aip',
};

/// Local descriptor fields whose retention cannot bind an artboard identity.
const Map<String, Map<String, Set<String>>> _artboardStyleParameters = {
  'Adobe Calligraphic Brush Tool': {
    'Real': {'Angle', 'Diameter', 'Roundness', 'AngleVariation', 'DiameterVariation', 'RoundnessVariation'},
    'Int': {'AngleDependsOn', 'DiameterDependsOn', 'RoundnessDependsOn', 'AngleRelativeTo'},
    'String': {'DisplayString'},
  },
  'Adobe ArtOnPath Brush Tool': {
    'Real': AiNativeArtworkBrushPaint.realFields,
    'Int': AiNativeArtworkBrushPaint.integerFields,
    'Bool': AiNativeArtworkBrushPaint.booleanFields,
    'String': {'DisplayString'},
    'UnicodeString': {'DisplayString'},
  },
  'Adobe PatternOnPath Brush Tool': {
    'Real': AiNativeArtworkBrushPaint.realFields,
    'Int': AiNativeArtworkBrushPaint.integerFields,
    'Bool': AiNativeArtworkBrushPaint.booleanFields,
    'String': {'DisplayString'},
    'UnicodeString': {'DisplayString'},
  },
  'Conduit Filter': {},
  'Stroke Style Filter': {},
  'Fill Style Filter': {
    'Bool': {'UseEvenOdd'},
  },
  'Blend Style Filter': {},
  'Adobe Stroke Offset': {
    'String': {'DisplayString'},
    'Bool': {'StrokeOffsetInside'},
  },
  'Adobe Fuzzy Mask': {
    'Real': {'Radius'},
  },
  'Adobe Round Corners': {
    'Real': {'radius'},
  },
  'Adobe Offset Path': {
    'Real': {'ofst', 'mlim'},
    'Int': {'jntp'},
  },
  'Adobe Drop Shadow': {
    'Real': {'horz', 'vert', 'blur', 'opac', 'dark'},
    'Bool': {'pair', 'usePSLBlur'},
    'Int': {'blnd', 'csrc', 'Adobe Effect Expand Before Version'},
  },
  'Adobe Outer Glow': {
    'Real': {'blur', 'opac'},
    'Bool': {'usePSLBlur'},
    'Int': {'blnd', 'Adobe Effect Expand Before Version'},
  },
  'Adobe Transform': {
    'Real': {'rotate_Degrees', 'rotate_Radians', 'moveH_Pts', 'moveV_Pts', 'scaleV_Factor', 'scaleH_Factor', 'scaleH_Percent', 'scaleV_Percent'},
    'Bool': {'reflectX', 'reflectY', 'scaleLines', 'transformPatterns', 'randomize'},
    'Int': {'numCopies', 'pinPoint'},
  },
};
