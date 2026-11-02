part of 'package:aikit/src/model/ai_native_records.dart';

/// Qualifies a live shape whose single ordinary path is its complete appearance.
///
/// Structural edits retain the parameters and geometry together. Separate
/// printing expansions and version alternatives require their own lifecycle.
String? _directNativeShapeIssue(AiLiveShape shape, {bool appearanceLeaf = false}) {
  if (!appearanceLeaf && (!shape.isBound || shape.path?.isPrivate != false) ||
      shape.appearanceGroup != null ||
      shape.appearanceDictionary != null ||
      shape.alternativeDictionaries.isNotEmpty ||
      shape.style != null ||
      !appearanceLeaf && (shape.appearancePaths.length != 1 || !identical(shape.appearancePaths.single, shape.path))) {
    return 'The live shape requires a separate authoring/printing lifecycle contract.';
  }
  final Set<String>? fields = _shapeParameters[shape.handler];
  if (fields == null ||
      shape.definition.entries.length != 2 ||
      shape.definition['ai::LiveShape::HandlerName']?.type != 'UnicodeString' ||
      shape.definition['ai::LiveShape::Params']?.container?.type != 'Dictionary') {
    return 'The live shape has an unqualified handler or parameter owner.';
  }
  if (shape.parameters.notRecorded || shape.parameters.entries.map((field) => field.key).toSet().length != shape.parameters.entries.length) {
    return 'The live shape has conditional or repeated parameter fields.';
  }
  for (final AiNativeEntry field in shape.parameters.entries) {
    final String prefix = '${shape.handler}::';
    if (field.key == null || !field.key!.startsWith(prefix) || !fields.contains(field.key!.substring(prefix.length))) {
      return 'The live shape has unknown parameter or reference fields.';
    }
    final String name = field.key!.substring(prefix.length);
    final String type = _nativeShapeParameterType(shape.handler, name);
    if (field.type != type || (type == 'UnicodeString' ? field.stringBytes == null : field.number == null || field.number!.abs() > 9007199254740991)) {
      return 'The live shape has an unqualified parameter value.';
    }
  }
  return null;
}

/// Retains handler-specific scalar encodings without coercing source values.
String _nativeShapeParameterType(String handler, String name) => switch (name) {
  'Clockwise' || 'IsRegular' => 'Bool',
  'InitialQuadrant' || 'NumSides' || 'NumPoints' => 'Int',
  _ when name.contains('Type') => handler == 'ai::Rectangle' ? 'UnicodeString' : 'Int',
  _ => 'Real',
};

/// Counts authoritative shape owners carried by disjoint complete object trees.
int _selectedLiveShapeCount(AiNativeDrawing drawing, List<AiNativeItem> sources) => _selectedNativeObjects(drawing, sources).where((object) => object.liveShape != null).length;
