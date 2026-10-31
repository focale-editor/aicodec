part of 'package:aikit/src/model/ai_native_records.dart';

/// Plans synchronized edits against one immutable authoring snapshot.
final class _LiveShapeTranslation {
  /// Drawing owning every selected source handle.
  final AiNativeDrawing drawing;

  /// Selection captured before any byte offsets change.
  final List<AiLiveShape> shapes;

  /// Horizontal displacement in source drawing units.
  final double deltaX;

  /// Vertical displacement in source drawing units, with y increasing upwards.
  final double deltaY;

  /// Creates an operation without mutating or partially updating the source.
  _LiveShapeTranslation({required this.drawing, required List<AiLiveShape> shapes, required this.deltaX, required this.deltaY}) : shapes = List.unmodifiable(shapes);

  /// Validates all dependencies before applying one source-edit transaction.
  AiNativeDrawing apply() {
    if (!deltaX.isFinite || !deltaY.isFinite || shapes.isEmpty || shapes.toSet().length != shapes.length || shapes.any((shape) => !drawing.liveShapes.contains(shape))) {
      throw ArgumentError('Translation requires finite offsets and distinct shapes from this snapshot.');
    }
    _checkDrawing();
    final List<AiSourceEdit> edits = [];
    final Set<AiNativePath> moved = {};
    final Map<AiNativeContainer, String> copiedStyles = {};
    final Set<String> styleNames = drawing.records.roots.where((record) => record.type == 'KnownStyle').map((record) => record['Name']?.text()).whereType<String>().toSet();
    for (final AiLiveShape shape in shapes) {
      final AiNativeGroup? appearanceGroup = shape.appearanceGroup;
      if (appearanceGroup != null && drawing.items.any((item) => item is AiNativeContainer && item.start > appearanceGroup.start && item.end < appearanceGroup.end)) {
        throw UnsupportedError('Translation requires synchronizing nested appearance metadata.');
      }
      if (!shape.isBound || !_shapeParameters.containsKey(shape.handler)) {
        throw UnsupportedError(shape.bindingIssue ?? 'Unsupported native live-shape handler: ${shape.handler}.');
      }
      _checkDictionary(shape.dictionary, shape.handler);
      for (final AiNativeContainer alternative in shape.alternativeDictionaries) {
        _checkDictionary(alternative, shape.handler);
      }
      final AiNativeContainer? appearance = shape.appearanceDictionary;
      if (appearance != null) {
        _checkDictionary(appearance, shape.handler);
      }
      for (final AiNativeContainer dictionary in [shape.dictionary, ?appearance, ...shape.alternativeDictionaries]) {
        final AiNativeContainer? parameters = dictionary['ai::LiveShape']?.container?['ai::LiveShape::Params']?.container;
        if (parameters == null) {
          continue;
        }
        for (final (String, double) axis in [('CenterX', deltaX), ('CenterY', -deltaY)]) {
          final AiNativeEntry? entry = parameters['${shape.handler}::${axis.$1}'];
          if (entry?.type != 'Real' || entry?.number == null) {
            throw const FormatException('Native live shape has no valid canvas center.');
          }
          edits.add(_numberEdit(entry!.items.single, entry.number! + axis.$2));
        }
      }
      for (final AiNativePath path in {shape.path!, ...shape.appearancePaths}) {
        if (!moved.add(path)) {
          throw const FormatException('Selected native shapes share an appearance path.');
        }
        for (final AiNativeInstruction command in path.geometry) {
          for (int index = 0; index < command.operands.length; index++) {
            final AiToken token = command.operands[index];
            edits.add(_numberEdit(AiNativeToken._(token: token), token.number!.toDouble() + (index.isEven ? deltaX : deltaY)));
          }
        }
      }
      for (final AiNativeGradient gradient in drawing.gradients) {
        final bool owned = gradient.paths.any(shape.appearancePaths.contains) || gradient.start >= shape.start && gradient.end <= shape.end;
        if (!owned) {
          continue;
        }
        if (gradient.paths.any((path) => !shape.appearancePaths.contains(path))) {
          throw UnsupportedError('Translation requires synchronizing a shared gradient instance.');
        }
        edits.addAll(_gradientEdits(gradient));
      }
      final AiNativeContainer? style = shape.style;
      if (style != null) {
        final List<AiSourceEdit> styleEdits = [
          for (final AiNativeContainer record in drawing.records.containers.where(
            (record) => record.start > style.start && record.end < style.end && const {'FillStyle', 'StrokeStyle'}.contains(record.type),
          ))
            for (final AiNativeGradient gradient in AiNativePaintStyle.decode(records: drawing.records, record: record).gradients) ..._gradientEdits(gradient),
        ];
        if (styleEdits.isNotEmpty) {
          String? name = copiedStyles[style];
          if (name == null) {
            int suffix = 1;
            while (styleNames.contains('AiKit translated $suffix')) {
              suffix++;
            }
            name = 'AiKit translated $suffix';
            styleNames.add(name);
            copiedStyles[style] = name;
            final AiNativeEntry naming = style['Name']!;
            styleEdits.add(AiSourceEdit(start: naming.items.first.start, end: naming.items.first.end, bytes: _nativeString(name)));
            styleEdits.addAll(naming.items.skip(1).map((item) => AiSourceEdit(start: item.start, end: item.end, bytes: [])));
            final Uint8List source = drawing.records.program.bytes;
            final bool private = style.start >= 2 && source[style.start - 2] == 37 && source[style.start - 1] == 95;
            final Uint8List copy = AiNativeEditor.copyRange(program: drawing.records.program, start: style.start, end: style.end, edits: styleEdits);
            edits.add(
              AiSourceEdit(
                start: style.end,
                end: style.end,
                bytes: [
                  10,
                  if (private) ...[37, 95],
                  ...copy,
                  10,
                ],
              ),
            );
          }
          final AiNativeInstruction reference = drawing.items.whereType<AiNativeInstruction>().singleWhere((instruction) => instruction.end == shape.end && _marker(instruction, 1));
          final AiToken token = reference.operands[1];
          edits.add(AiSourceEdit(start: token.start, end: token.end, bytes: _nativeString(name)));
        }
      }
    }
    edits.addAll(_boundsEdits());
    return AiNativeDrawing.decode(
      records: AiNativeRecords.decode(
        program: AiNativeEditor.apply(program: drawing.records.program, edits: edits),
      ),
    );
  }

  /// Rejects drawing state that would require additional positional edits.
  void _checkDrawing() {
    final Map<String, AiNativeContainer> styles = {
      for (final AiNativeContainer record in drawing.records.roots.where((record) => record.type == 'KnownStyle' && record['Name']?.text() != null)) record['Name']!.text()!: record,
    };
    final Set<AiNativeContainer> checked = {};
    for (final AiNativeItem item in drawing.items) {
      if (item is AiNativeVersionComment &&
          !drawing.liveShapes.any((shape) => shape.alternativeDictionaries.isNotEmpty && shape.path != null && item.start >= shape.path!.end && item.end <= shape.end)) {
        throw UnsupportedError('Translation requires resolved version-dependent artwork.');
      }
      if (item is AiNativeContainer && item.type != 'ArtDictionary') {
        throw UnsupportedError('Translation cannot synchronize the native ${item.type} drawing resource.');
      }
      if (item is! AiNativeInstruction) {
        continue;
      }
      if (!_translationCommands.contains(item.operator)) {
        throw UnsupportedError('Translation cannot synchronize the native ${item.operator} operator.');
      }
      if (item.operator == 'XW') {
        if (!_marker(item, 1) && !_marker(item, 6)) {
          throw UnsupportedError('Translation requires a resolved XW appearance binding.');
        }
        if (_marker(item, 1)) {
          final AiNativeContainer? style = styles[latin1.decode(aiStringBytes(item.operands[1]))];
          if (style == null) {
            throw const FormatException('Native appearance references a missing known style.');
          }
          if (checked.add(style)) {
            _checkStyle(style);
          }
        }
      }
    }
    for (final AiLiveShape shape in shapes) {
      // A parent appearance may also keep an authoring copy outside the moved
      // paths. Only ordinary group/compound boundaries are supported here.
      for (final AiNativeGroup group in drawing.groups.where((group) => group.start < shape.start && group.end > shape.end)) {
        final int closing = drawing.items.indexWhere((item) => item.end == group.end);
        if (closing >= 0 && closing + 1 < drawing.items.length && drawing.items[closing + 1] is AiNativeContainer) {
          throw UnsupportedError('Translation requires synchronizing the parent appearance.');
        }
      }
    }
  }

  /// Checks native metadata whose positions are updated with the shape outline.
  void _checkDictionary(AiNativeContainer dictionary, String handler) {
    if (dictionary.entries.any((entry) => !const {'ai::LiveShape', 'BBAccumRotation', 'AI10_ArtUID'}.contains(entry.key))) {
      throw UnsupportedError('Translation cannot synchronize unknown native artwork metadata.');
    }
    final AiNativeContainer? definition = dictionary['ai::LiveShape']?.container;
    if (definition == null) {
      return;
    }
    if (definition.entries.any((entry) => !const {'NotRecorded', 'ai::LiveShape::HandlerName', 'ai::LiveShape::Params'}.contains(entry.key)) ||
        definition['ai::LiveShape::HandlerName']?.text() != handler) {
      throw UnsupportedError('Translation cannot synchronize this native live-shape definition.');
    }
    final AiNativeContainer? parameters = definition['ai::LiveShape::Params']?.container;
    if (parameters == null) {
      if (!definition.notRecorded) {
        throw const FormatException('Recorded native live shape has no parameters.');
      }
      return;
    }
    final Set<String> supported = _shapeParameters[handler]!;
    for (final AiNativeEntry entry in parameters.entries) {
      if (entry.isQualifier && entry.key == 'NotRecorded') {
        continue;
      }
      final String? key = entry.key;
      if (key == null || !key.startsWith('$handler::') || !supported.contains(key.substring(handler.length + 2))) {
        throw UnsupportedError('Translation cannot synchronize the native $key parameter.');
      }
    }
  }

  /// Checks supported fill, stroke and blend graphs, including gradient blocks.
  void _checkStyle(AiNativeContainer style) {
    for (final AiNativeContainer container in drawing.records.containers.where((container) => container.start >= style.start && container.end <= style.end)) {
      final Set<String>? keys = _solidStyleKeys[container.type];
      if (keys == null || container.entries.any((entry) => !keys.contains(entry.key))) {
        throw UnsupportedError('Translation requires a supported appearance style.');
      }
      final AiNativeEntry? filter = container['Filter'];
      if (filter != null) {
        final AiNativeItem? name = filter.items.firstOrNull;
        if (name is! AiNativeToken || name.token.kind != .string || !_solidFilters.contains(latin1.decode(aiStringBytes(name.token)))) {
          throw UnsupportedError('Translation cannot synchronize this native appearance filter.');
        }
      }
      for (final AiNativeToken item in container.entries.expand((entry) => entry.items).whereType<AiNativeToken>()) {
        if (item.token.kind == .executableName && !_solidStyleCommands.contains(item.token.lexeme) && !_gradientCommands.contains(item.token.lexeme)) {
          throw UnsupportedError('Translation cannot synchronize the native ${item.token.lexeme} style command.');
        }
      }
      if (const {'FillStyle', 'StrokeStyle', 'BlendStyle'}.contains(container.type)) {
        final AiNativePaintStyle paint = AiNativePaintStyle.decode(records: drawing.records, record: container);
        if (container.type == 'BlendStyle' && paint.gradients.isNotEmpty) {
          throw UnsupportedError('A native blend style cannot own a positional gradient.');
        }
      }
    }
  }

  /// Moves absolute gradient imaging matrices while retaining relative vectors.
  List<AiSourceEdit> _gradientEdits(AiNativeGradient gradient) {
    final AiNativeGradientGeometry geometry = gradient.geometry;
    return [
      if (!geometry.relativeToArtwork)
        for (int axis = 0; axis < 2; axis++)
          _numberEdit(AiNativeToken._(token: geometry.instruction.operands[geometry.nameIndex + 9 + axis]), geometry.matrix[4 + axis] + (axis == 0 ? deltaX : deltaY)),
      for (final AiNativeInstruction matrix in gradient.imagingMatrices)
        for (int axis = 0; axis < 2; axis++) _numberEdit(AiNativeToken._(token: matrix.operands[4 + axis]), matrix.numbers![4 + axis] + (axis == 0 ? deltaX : deltaY)),
    ];
  }

  /// Expands top-level DSC extents without altering fixed artboard coordinates.
  List<AiSourceEdit> _boundsEdits() => AiNativeEditor.translationBoundsEdits(program: drawing.records.program, deltaX: deltaX, deltaY: deltaY);
}

/// Creates one finite numeric-token edit without changing native comment syntax.
AiSourceEdit _numberEdit(AiNativeItem item, double value) {
  if (!value.isFinite) {
    throw ArgumentError('Translation exceeds finite native coordinate values.');
  }
  return AiSourceEdit(start: item.start, end: item.end, bytes: latin1.encode(value.toString()));
}

/// Drawing operations whose state has no independent spatial reference.
const Set<String> _translationCommands = {
  ..._nativeGeometry,
  ..._nativePaint,
  ..._solidStyleCommands,
  ..._gradientCommands,
  'Lb',
  'LB',
  'Ln',
  'AE',
  'A',
  'Xw',
  'Ap',
  'As',
  'Ae',
  'D',
  'u',
  'U',
  '*u',
  '*U',
  'q',
  'Q',
  'XW',
};

/// Encodes a newly allocated resource name without depending on locale escaping.
List<int> _nativeString(String value) => latin1.encode('(${latin1.encode(value).map((byte) => '\\${byte.toRadixString(8).padLeft(3, '0')}').join()})');

/// Solid painting attributes that remain unchanged under translation.
const Set<String> _solidStyleCommands = {'O', 'R', 'k', 'K', 'g', 'G', 'x', 'X', 'Xa', 'XA', 'Xy', 'J', 'j', 'w', 'M', 'd', 'XR', 'Xd'};

/// Known appearance filters whose parameters are translation invariant.
const Set<String> _solidFilters = {'Chain Style Filter', 'Stack Style Filter', 'Adobe Stroke Offset', 'Conduit Filter', 'Fill Style Filter', 'Stroke Style Filter', 'Blend Style Filter'};

/// Allowed fields for the supported solid appearance graph.
const Map<String, Set<String>> _solidStyleKeys = {
  'KnownStyle': {'Name', 'Def'},
  'ActiveStyle': {'Execution'},
  'CompoundFilter': {'Filter', 'Visible', 'Part'},
  'BasicFilter': {'Filter', 'Visible', 'PluginFileName', 'Title', 'FillOrStroke', 'Dict'},
  'Dictionary': {'NotRecorded', 'StrokeStyle', 'DisplayString', 'StrokeOffsetInside', 'UseEvenOdd', 'FillStyle', 'BlendStyle'},
  'StrokeStyle': {'Def'},
  'FillStyle': {'Def'},
  'BlendStyle': {'Def'},
};

/// Native shape fields with known translation behavior.
const Map<String, Set<String>> _shapeParameters = {
  'ai::Rectangle': {
    'Width',
    'Height',
    'CenterX',
    'CenterY',
    'Angle',
    'Clockwise',
    'InitialQuadrant',
    'CornerRadius::0',
    'CornerRadius::1',
    'CornerRadius::2',
    'CornerRadius::3',
    'CornerType::0',
    'CornerType::1',
    'CornerType::2',
    'CornerType::3',
    'RoundingType::0',
    'RoundingType::1',
    'RoundingType::2',
    'RoundingType::3',
  },
  'ai::Ellipse': {'Width', 'Height', 'CenterX', 'CenterY', 'RotationAngle', 'Clockwise', 'InitialQuadrant', 'PieStartAngle', 'PieEndAngle'},
  'ai::Polygon': {'CenterX', 'CenterY', 'RotationAngle', 'CornerRadius', 'CornerRoundingType', 'IsRegular', 'Radius', 'CornerType', 'Clockwise', 'NumSides'},
  'ai::Star': {
    'CenterX',
    'CenterY',
    'RotationAngle',
    'IsRegular',
    'Clockwise',
    'NumPoints',
    'Radius1',
    'Radius2',
    'Corner1Radius',
    'Corner2Radius',
    'Corner1Type',
    'Corner2Type',
    'Corner1RoundingType',
    'Corner2RoundingType',
  },
  'ai::Line': {'CenterX', 'CenterY', 'Length', 'RotationAngle'},
};
