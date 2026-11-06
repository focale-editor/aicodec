part of 'package:illustratorkit/src/model/ai_native_records.dart';

/// Declares scalar filter parameters independently of any rendering capability.
const Map<String, Set<String>> _artboardSvgParameters = {
  'filter': {'filterUnits', 'primitiveUnits', 'filterRes'},
  'feBlend': {'mode'},
  'feColorMatrix': {'type', 'values'},
  'feComponentTransfer': {},
  'feComposite': {'operator', 'k1', 'k2', 'k3', 'k4'},
  'feConvolveMatrix': {'order', 'kernelMatrix', 'divisor', 'bias', 'targetX', 'targetY', 'edgeMode', 'kernelUnitLength', 'preserveAlpha'},
  'feDiffuseLighting': {'surfaceScale', 'diffuseConstant', 'kernelUnitLength', 'resultScale'},
  'feDisplacementMap': {'scale', 'xChannelSelector', 'yChannelSelector'},
  'feFlood': {},
  'feGaussianBlur': {'stdDeviation'},
  'feMerge': {},
  'feMorphology': {'operator', 'radius'},
  'feOffset': {'dx', 'dy'},
  'feSpecularLighting': {'surfaceScale', 'specularConstant', 'specularExponent', 'kernelUnitLength'},
  'feTile': {},
  'feTurbulence': {'baseFrequency', 'numOctaves', 'seed', 'stitchTiles', 'type'},
  'feDistantLight': {'azimuth', 'elevation'},
  'fePointLight': {'x', 'y', 'z'},
  'feSpotLight': {'x', 'y', 'z', 'pointsAtX', 'pointsAtY', 'pointsAtZ', 'specularExponent', 'limitingConeAngle'},
  'feMergeNode': {'in'},
  'feFuncR': {'type', 'tableValues', 'slope', 'intercept', 'amplitude', 'exponent', 'offset'},
  'feFuncG': {'type', 'tableValues', 'slope', 'intercept', 'amplitude', 'exponent', 'offset'},
  'feFuncB': {'type', 'tableValues', 'slope', 'intercept', 'amplitude', 'exponent', 'offset'},
  'feFuncA': {'type', 'tableValues', 'slope', 'intercept', 'amplitude', 'exponent', 'offset'},
  'animate': {
    'attributeName',
    'attributeType',
    'begin',
    'end',
    'dur',
    'min',
    'max',
    'restart',
    'repeatCount',
    'repeatDur',
    'fill',
    'calcMode',
    'values',
    'keyTimes',
    'keySplines',
    'from',
    'to',
    'by',
    'additive',
    'accumulate',
  },
  'set': {'attributeName', 'attributeType', 'begin', 'end', 'dur', 'min', 'max', 'restart', 'repeatCount', 'repeatDur', 'fill', 'to'},
};

/// Identifies top-level primitives without external image or document references.
const Set<String> _artboardSvgPrimitives = {
  'feBlend',
  'feColorMatrix',
  'feComponentTransfer',
  'feComposite',
  'feConvolveMatrix',
  'feDiffuseLighting',
  'feDisplacementMap',
  'feFlood',
  'feGaussianBlur',
  'feMerge',
  'feMorphology',
  'feOffset',
  'feSpecularLighting',
  'feTile',
  'feTurbulence',
};

/// Lists presentation values whose literal syntax cannot reference another owner.
const Set<String> _artboardSvgPresentation = {'lighting-color', 'flood-color', 'flood-opacity', 'color-interpolation-filters'};

/// Returns the local scalar vocabulary for one retained filter element.
Set<String> _artboardSvgAttributes(String name) => {
  ...?_artboardSvgParameters[name],
  'id',
  if (name == 'filter' || _artboardSvgPrimitives.contains(name)) ...{'x', 'y', 'width', 'height', 'style', ..._artboardSvgPresentation},
  if (_artboardSvgPrimitives.contains(name)) ...{'in', 'in2', 'result'},
};

/// Checks complete setup collections and rejects unattached filter owners.
List<({int start, int end})> _artboardSvgFilterRanges(AiNativeLayers layers) {
  final AiNativeRecords records = layers.drawing.records;
  final List<AiToken> tokens = records._projection.tokens;
  final Map<int, AiNativeContainer> roots = {for (final AiNativeContainer root in records.roots.where((root) => root.type == 'SVGFilter')) root.start: root};
  final Set<AiNativeContainer> checked = {};
  final List<({int start, int end})> ranges = [];
  bool setup = false;
  for (int index = 0; index < tokens.length && tokens[index].start < records.program.bodyStart; index++) {
    final AiToken token = tokens[index];
    if (token.kind == .comment && token.lexeme == '%%BeginSetup') {
      setup = true;
    }
    if (!setup || token.kind != .comment || token.lexeme != '%AI10_BeginSVGFilter') {
      continue;
    }
    final int count = checked.length;
    index++;
    while (index < tokens.length && tokens[index].start < records.program.bodyStart && tokens[index].lexeme != '%AI10_EndSVGFilter') {
      final AiToken value = tokens[index];
      if (value.kind == .comment && !value.lexeme.startsWith('%AI') && !value.lexeme.startsWith('%%')) {
        index++;
        continue;
      }
      final AiNativeContainer? filter = roots[value.start];
      if (filter == null || !checked.add(filter)) {
        throw UnsupportedError('Retained SVG filter sections require complete native filter owners.');
      }
      _artboardSetupRecord(layers, filter);
      _referenceFields(filter, const {}, nested: {'Def': (entry) => _artboardSvgNode(entry, parent: null)});
      if (filter.entries.length != 1) {
        throw UnsupportedError('Retained SVG filters require exactly one XML definition.');
      }
      while (index < tokens.length && tokens[index].start < filter.end) {
        index++;
      }
    }
    if (index >= tokens.length || tokens[index].start >= records.program.bodyStart || checked.length == count) {
      throw UnsupportedError('Retained SVG filter sections require complete nonempty boundaries.');
    }
    final AiToken end = tokens[index];
    if (records._projection.isPrivate(token.start) || records._projection.isPrivate(end.start) || layers.structure.versions.blocks.any((block) => block.start < end.end && block.end > token.start)) {
      throw UnsupportedError('Retained SVG filters require ordinary unconditional section boundaries.');
    }
    ranges.add((start: token.start, end: end.end));
  }
  if (checked.length != roots.length) {
    throw UnsupportedError('Retained SVG filters require complete setup section ownership.');
  }
  return ranges;
}

/// Qualifies native XML envelopes and local filter dependencies without evaluation.
void _artboardSvgNode(AiNativeEntry entry, {required String? parent, String? attribute}) {
  final AiNativeContainer node = _referenceRecord(entry, 'XMLNode');
  _referenceFields(
    node,
    const {
      'Int': {'xmlnode-nodetype'},
      'String': {'xmlnode-nodename', 'xmlnode-nodevalue'},
    },
    nested: {
      'xmlnode-attributes': (field) => _referenceRecord(field, 'Dictionary'),
      'xmlnode-children': (field) => _referenceRecord(field, 'Array'),
    },
  );
  final String? name = node['xmlnode-nodename']?.text();
  final String? value = node['xmlnode-nodevalue']?.text();
  if (node.entries.length != 5 || name == null || value == null || node['xmlnode-nodetype']?.number != (attribute == null ? 1 : 2)) {
    throw UnsupportedError('Retained SVG nodes require complete literal XML fields.');
  }
  final AiNativeContainer attributes = node['xmlnode-attributes']!.container!;
  final AiNativeContainer children = node['xmlnode-children']!.container!;
  if (attribute != null) {
    if (name != attribute || attributes.entries.isNotEmpty || children.entries.isNotEmpty) {
      throw UnsupportedError('Retained SVG attributes require matching names and no nested owners.');
    }
    return;
  }
  final Set<String> allowed = switch (parent) {
    null => {'filter'},
    'filter' => {..._artboardSvgPrimitives, 'animate', 'set'},
    'feMerge' => {'feMergeNode'},
    'feComponentTransfer' => {'feFuncR', 'feFuncG', 'feFuncB', 'feFuncA'},
    'feDiffuseLighting' || 'feSpecularLighting' => {'feDistantLight', 'fePointLight', 'feSpotLight', 'animate', 'set'},
    'animate' || 'set' => {},
    _ => {'animate', 'set'},
  };
  if (!allowed.contains(name) || value.isNotEmpty) {
    throw UnsupportedError('Retained SVG filter elements cannot contain unknown or executable content.');
  }
  final Map<String, String> values = {};
  final Set<String> fields = _artboardSvgAttributes(name);
  for (final AiNativeEntry field in attributes.entries) {
    final String? key = field.key;
    if (field.isQualifier || key == null || !fields.contains(key) || values.containsKey(key)) {
      throw UnsupportedError('Retained SVG filters have an unqualified attribute owner.');
    }
    _artboardSvgNode(field, parent: name, attribute: key);
    values[key] = field.container!['xmlnode-nodevalue']!.text()!;
  }
  for (final MapEntry<String, String> field in values.entries) {
    if (_artboardSvgPresentation.contains(field.key)) {
      _artboardSvgPresentationValue(field.key, field.value);
    } else if (field.key == 'style') {
      for (final String declaration in field.value.split(';').where((part) => part.trim().isNotEmpty)) {
        final List<String> parts = declaration.split(':');
        if (parts.length != 2 || !_artboardSvgPresentation.contains(parts.first.trim())) {
          throw UnsupportedError('Retained SVG style declarations require known local scalar properties.');
        }
        _artboardSvgPresentationValue(parts.first.trim(), parts.last);
      }
    }
  }
  if (name == 'animate' || name == 'set') {
    final String? target = values['attributeName'];
    if (target == null || !_artboardSvgAttributes(parent!).contains(target) || const {'id', 'in', 'in2', 'result', 'style'}.contains(target)) {
      throw UnsupportedError('Retained SVG animations require a scalar attribute on their parent.');
    }
    for (final String timing in ['begin', 'end', 'dur', 'min', 'max', 'repeatDur']) {
      if (values[timing] case final String clock) {
        if (clock.split(';').any((part) => !RegExp(r'^(indefinite|[+-]?(\d+:)?(\d+:)?\d+(\.\d+)?(h|min|s|ms)?)$').hasMatch(part.trim()))) {
          throw UnsupportedError('Retained SVG animation timing cannot reference external elements or events.');
        }
      }
    }
    if (_artboardSvgPresentation.contains(target)) {
      for (final String key in ['from', 'to', 'by', 'values']) {
        for (final String value in values[key]?.split(';') ?? const <String>[]) {
          _artboardSvgPresentationValue(target, value);
        }
      }
    }
  }
  for (final AiNativeEntry child in children.entries) {
    if (child.isQualifier || child.key != null) {
      throw UnsupportedError('Retained SVG child arrays require ordinary XML entries.');
    }
    _artboardSvgNode(child, parent: name);
  }
}

/// Excludes URLs, CSS escapes and external color profiles from retained styles.
void _artboardSvgPresentationValue(String name, String value) {
  final String literal = value.trim();
  final bool scalar = name == 'flood-opacity'
      ? double.tryParse(literal)?.isFinite == true || literal == 'inherit'
      : name == 'color-interpolation-filters'
      ? const {'auto', 'sRGB', 'linearRGB', 'inherit'}.contains(literal)
      : RegExp(r'^([a-zA-Z]+|#[0-9a-fA-F]+|(rgb|rgba|hsl|hsla)\([0-9.+% ,/\-]*\))$').hasMatch(literal);
  if (!scalar) {
    throw UnsupportedError('Retained SVG presentation values cannot reference outside resources.');
  }
}
