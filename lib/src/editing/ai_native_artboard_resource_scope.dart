part of 'package:aikit/src/model/ai_native_records.dart';

/// Qualified artwork resource names, source spans and owned metadata retained together.
typedef _ArtboardResourceScope = ({Set<String> patterns, Set<String> symbols, Set<String> brushes, List<({int start, int end})> ranges, Set<AiNativeContainer> objects});

/// Qualifies direct CC resource artwork without evaluating PostScript programs.
_ArtboardResourceScope _artboardResourceScope(AiNativeLayers layers) {
  final AiNativeRecords records = layers.drawing.records;
  final AiNativeArtworkResources resources = _nativeArtworkResources(layers.structure, requireOrdinary: true);
  final Set<String> patterns = {};
  final Set<String> symbols = {};
  final Set<String> brushes = {};
  final _ArtboardResourceInspection scope = _ArtboardResourceInspection(layers: layers);
  final List<({int start, int end})> ranges = [];
  final Set<AiNativeContainer> objects = {};
  final Map<int, AiNativeResourceUse> references = {for (final AiNativeResourceUse use in layers.structure.resourceUses) use.instruction.start: use};
  for (final AiNativeArtworkResource resource in resources.resources) {
    if (resource.nameBytes.isEmpty) {
      throw const FormatException('Retained resources require nonempty literal names.');
    }
    final Set<String> names = switch (resource.kind) {
      .pattern => patterns,
      .symbol => symbols,
      .brush => brushes,
    };
    if (!names.add(latin1.decode(resource.nameBytes))) {
      throw UnsupportedError('Retained resource names must identify a unique definition in their namespace.');
    }
    if (resource.tokens.any((token) => token.number != null && (!token.number!.isFinite || token.number!.abs() > 9007199254740991))) {
      throw const FormatException('Retained resource values must be finite portable numbers.');
    }
    final List<AiNativeRaster> rasters = resource.rasters;
    final Map<AiNativeContainer, AiNativeRaster> rasterOwners = {};
    if (resource.tokens.any((token) => token.kind == .data)) {
      scope._rasters ??= resource._reader.rasters;
    }
    for (final AiNativeRaster image in rasters) {
      if (image.end > resource.artworkEnd) {
        throw const FormatException('A retained image crosses its resource boundary.');
      }
      _artboardResourceRaster(records, image);
      if (image.dictionary != null) {
        rasterOwners[image.dictionary!] = image;
      }
    }
    final AiNativeDrawing drawing = resource._drawing;
    for (final AiNativeContainer record in resource.metadata) {
      if (resource.kind == .pattern && !rasterOwners.containsKey(record)) {
        _artboardPatternMetadata(layers, record);
      } else {
        _artboardSymbolMetadata(scope, record, raster: rasterOwners[record]);
      }
      objects.add(record);
    }
    _artboardResourceAnnotations(scope, resource.opening.end, resource.closing.start, rasters, metadata: resource.metadata);
    scope.drawings.add(drawing);
    ranges.add((start: resource.start, end: resource.end));
  }
  for (final AiNativeDrawing drawing in scope.drawings) {
    _artboardResourceArtwork(layers, drawing, references, patterns);
  }
  return (patterns: Set.unmodifiable(patterns), symbols: Set.unmodifiable(symbols), brushes: Set.unmodifiable(brushes), ranges: List.unmodifiable(ranges), objects: Set.unmodifiable(objects));
}

/// Keeps tile-editor settings and local gradient transforms free of board links.
void _artboardPatternMetadata(AiNativeLayers layers, AiNativeContainer record) {
  _artboardSetupRecord(layers, record);
  if (record.type != 'ArtDictionary' || record.hasBinary) {
    throw UnsupportedError('Retained patterns require qualified art metadata.');
  }
  _referenceFields(
    record,
    {
      'Bool': {
        'AIPattern_Editor_Backing_Tile_Rect',
        'AIPattern_Is_Main_Copy_of_EditGroup',
        'AIPattern_Is_Repeated_Art',
        'AIPattern_Editor_Dim_Copies_Key',
        'AIPattern_Editor_Left_in_Front',
        'AIPattern_Editor_Top_in_Front',
        'AIPattern_Editor_AutoGrow',
      },
      'Int': {'AIPattern_Editor_Preview_Rows', 'AIPattern_Editor_Preview_Cols', 'AIPattern_Editor_Editable_Copy_Loc_Key', 'AIPattern_Editor_Repetition_Type'},
      'Real': {'AIPattern_Editor_Dim_Percent_Key', 'AIPattern_Editor_Tile_Height', 'AIPattern_Editor_Tile_Width', 'AIPattern_Editor_AutoSpacing_H', 'AIPattern_Editor_AutoSpacing_V'},
      'String': {'BBAccumRotation', 'AIArtName', 'Object name'},
    },
    nested: {
      'Adobe_AI9_ArtStyle_Dictionary': (entry) => _referenceFields(_referenceRecord(entry, 'Dictionary'), {
        'RealMatrix': {'CAIGradientTformMatrix'},
      }, notRecorded: true),
    },
  );
  _artboardResourceRotation(record);
}

/// Checks saved rotation values without changing the resource coordinate basis.
void _artboardResourceRotation(AiNativeContainer record) {
  for (final AiNativeEntry entry in record.entries) {
    if (entry.key == 'BBAccumRotation') {
      final double? angle = entry.stringBytes == null ? null : double.tryParse(latin1.decode(entry.stringBytes!));
      if (angle == null || !angle.isFinite || angle.abs() > 9007199254740991) {
        throw const FormatException('Retained resource rotation metadata must be numeric.');
      }
    }
  }
}

/// Retains symbol-local registration grids, identities and appearance metadata.
void _artboardSymbolMetadata(_ArtboardResourceInspection scope, AiNativeContainer record, {AiNativeRaster? raster}) {
  if (record.type != 'ArtDictionary' || record.hasBinary) {
    throw UnsupportedError('Retained symbols require qualified art metadata.');
  }
  final List<({int start, int end})> checked = [];
  _referenceFields(
    record,
    {
      'Bool': {'AI13PatternEnableGuides', 'AI15PixelPerfectSymbolEnablekey', 'PATH_IS_KAPPA_CURVE', if (raster != null) 'AI9 Fuzzy Mask'},
      'Int': {'AI13PatternExportType', 'AI13PatternRegistrationType', 'AI10 compound shape mode'},
      'RealMatrix': {'AI13Pattern9SliceScalingGridKey'},
      'String': {
        'BBAccumRotation',
        'AIArtName',
        'Object name',
        if (raster == null) ..._artboardResourceBlendFields,
        if (raster != null) ...['AI24 ImageRawDataUUID', 'AI24 ImageAlphaRawDataUUID'],
      },
      if (raster != null) 'Real': {'Raster Art Original Scale'},
    },
    nested: {
      'AI9_Mask': (entry) {
        final AiNativeContainer mask = _referenceRecord(entry, 'Mask');
        _artboardOpacityMask(scope, mask);
        checked.add((start: mask.start, end: mask.end));
      },
      'Adobe_AI9_Observed_Key_Strings': (entry) {
        final AiNativeContainer names = _referenceRecord(entry, 'Array');
        if (names.hasBinary ||
            names.entries.any(
              (field) =>
                  field.key != null ||
                  field.type != null ||
                  field.items.length != 2 ||
                  field.items.first is! AiNativeToken ||
                  field.items.last is! AiNativeToken ||
                  !const {AiTokenKind.string, AiTokenKind.hexString}.contains((field.items.first as AiNativeToken).token.kind) ||
                  (field.items.last as AiNativeToken).token.lexeme != '/String' ||
                  latin1.decode(aiStringBytes((field.items.first as AiNativeToken).token)) != 'AI Auto Rasterize',
            )) {
          throw UnsupportedError('Retained symbol observers require known literal property names.');
        }
      },
      'Adobe_AI9_ArtStyle_Dictionary': (entry) => _referenceFields(_referenceRecord(entry, 'Dictionary'), {
        'RealMatrix': {'CAIGradientTformMatrix'},
      }, notRecorded: true),
      'AI10_ArtUID': (entry) {
        final AiNativeContainer identity = _referenceRecord(entry, 'XMLUID');
        if (identity.entries.length != 1 ||
            identity.entries.single.key != null ||
            identity.entries.single.type != null ||
            identity.entries.single.stringBytes == null ||
            identity.entries.single.stringBytes!.isEmpty) {
          throw const FormatException('Retained symbol identities require one literal XML identifier.');
        }
      },
    },
  );
  _artboardSetupRecord(scope.layers, record, checked: checked);
  _artboardResourceRotation(record);
}
