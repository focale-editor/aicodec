part of 'package:illustratorkit/src/model/ai_native_records.dart';

/// Import provenance and export preferences that do not define native contours.
const Set<String> _nativeSvgDocumentAttributes = {
  'sodipodi:version',
  'sodipodi:docname',
  'inkscape:version',
  'inkscape:export-xdpi',
  'inkscape:export-ydpi',
  'inkscape:export-filename',
  'inkscape:output_extension',
  'xmlns:svg',
  'xmlns:inkscape',
  'xmlns:sodipodi',
  'xmlns:rdf',
  'xmlns:dc',
  'xmlns:cc',
};

/// Saved editor preferences, including an identity reference retained verbatim.
const Set<String> _nativeSvgViewAttributes = {
  'id',
  'bordercohor',
  'bordercolor',
  'borderopacity',
  'pagecolor',
  'showgrid',
  'gridtolerance',
  'guidetolerance',
  'objecttolerance',
  'inkscape:zoom',
  'inkscape:cx',
  'inkscape:cy',
  'inkscape:current-layer',
  'inkscape:window-width',
  'inkscape:window-height',
  'inkscape:window-x',
  'inkscape:window-y',
  'inkscape:window-maximized',
  'inkscape:pageshadow',
  'inkscape:pageopacity',
  'inkscape:showpageshadow',
  'inkscape:pagecheckerboard',
  'inkscape:deskcolor',
};

/// Qualifies retained import metadata without granting its owners lifecycle edits.
///
/// These dictionaries deliberately stay outside the reference-independent body
/// inventory. Deleting identities still requires a separate reference contract.
Set<AiNativeContainer> _nativeContourMetadata(AiNativeLayers layers) {
  final Set<AiNativeContainer> retained = {};
  for (final AiNativeLayer layer in layers.layers) {
    final AiNativeContainer? dictionary = layer.dictionary;
    if (layer.bindingIssue != null && layer._ownershipIssue == null && dictionary != null && dictionary['SVG_ThisElement'] != null) {
      _nativeSvgMetadata(dictionary, group: null);
      retained.add(dictionary);
    }
  }
  for (final AiNativeObject object in layers.drawing._objects.objects) {
    final AiNativeContainer? dictionary = object.dictionary;
    if (object.source is AiNativeGroup &&
        object.bindingIssue != null &&
        object._ownershipIssue == null &&
        dictionary != null &&
        dictionary.entries.any((entry) => entry.key?.startsWith('SVG_') ?? false)) {
      _nativeSvgMetadata(dictionary, group: object.source as AiNativeGroup);
      retained.add(dictionary);
    }
  }
  return retained;
}

/// Qualifies imported references before explicitly discarding contour parents.
void _nativeContourRemovalReferences(AiNativeDrawing drawing, List<AiNativeObject> owners) {
  if (owners.any((owner) => owner.dictionary?['AdobeObjectMatrix'] != null)) {
    throw UnsupportedError('Dissolving an imported transform owner requires explicit coordinate rebasing.');
  }
  final List<AiNativeObjectIdentifier> identifiers = [for (final AiNativeObject owner in owners) ?owner.identifier];
  if (identifiers.isEmpty) {
    return;
  }
  final Set<String> removed = identifiers.map((identifier) => latin1.decode(identifier.bytes)).toSet();
  final Map<String, int> identities = {};
  for (final AiNativeObjectIdentifier identifier in drawing._objects.structure.identifiers.where((identifier) => identifier.kind == .xmlArt)) {
    identities.update(latin1.decode(identifier.bytes), (count) => count + 1, ifAbsent: () => 1);
  }
  final Set<AiNativeContainer> discarded = owners.map((owner) => owner.dictionary).whereType<AiNativeContainer>().toSet();
  final Set<AiNativeContainer> metadata = drawing._pathTopologyScope.retainedMetadata;
  for (final AiNativeContainer dictionary in metadata.difference(discarded)) {
    final AiNativeContainer? node = dictionary['SVG_ThisElement']?.container;
    if (node == null) {
      continue;
    }
    for (final AiNativeEntry child in node['xmlnode-children']!.container!.entries) {
      final AiNativeContainer attributes = child.container!['xmlnode-attributes']!.container!;
      final AiNativeContainer? reference = attributes['inkscape:current-layer']?.container;
      if (reference == null) {
        continue;
      }
      final String name = reference['xmlnode-nodevalue']!.text()!;
      if (identities[name] != 1 || removed.contains(name)) {
        throw UnsupportedError('Dissolution requires an unambiguous retained imported current-layer target.');
      }
    }
  }
  final AiNativeLayers layers = drawing._pathTopologyScope.layers;
  _nativeRemovalReferences(layers, identifiers, _layerHeaderItems(layers), bodyDictionaries: {...drawing._pathTopologyScope.dictionaries, ...metadata});
}

/// Checks complete import dictionaries while preserving source-owned transforms.
void _nativeSvgMetadata(AiNativeContainer dictionary, {required AiNativeGroup? group}) {
  _referenceFields(
    dictionary,
    const {},
    nested: {
      'AI10_ArtUID': (field) {
        final AiNativeContainer identifier = _referenceRecord(field, 'XMLUID');
        if (identifier.entries.length != 1 || identifier.entries.single.key != null || identifier.entries.single.type != null || identifier.entries.single.stringBytes == null) {
          throw UnsupportedError('Retained SVG metadata requires a literal native identity.');
        }
      },
      'SVG_ThisElement': (field) => _nativeSvgMetadataNode(field, name: 'SVG_ThisElement', layer: group == null),
      if (group != null) ...{
        'SVG_CreatedByImporter': (field) {
          if (field.type != 'Bool' || field.boolean == null) {
            throw UnsupportedError('Retained SVG import flags require literal Booleans.');
          }
        },
        'SVG_ShapeType': (field) {
          if (!group.compound || field.type != 'Int' || field.number != 7) {
            throw UnsupportedError('Retained SVG shape metadata requires an ordinary compound contour owner.');
          }
        },
        'SVG_Dict': (field) => _referenceFields(
          _referenceRecord(field, 'Dictionary'),
          const {},
          nested: {
            'SVG_AttributesDict': (field) => _referenceFields(
              _referenceRecord(field, 'Dictionary'),
              const {},
              nested: {
                'transform': (field) => _nativeSvgMetadataMatrix(field, svg: true),
              },
            ),
          },
        ),
        'AdobeObjectMatrix': (field) => _nativeSvgMetadataMatrix(field, svg: false),
      },
    },
  );
  if ((dictionary['SVG_Dict'] != null) != (dictionary['AdobeObjectMatrix'] != null)) {
    throw UnsupportedError('Retained SVG transforms require both imported and native matrix records.');
  }
  final AiNativeContainer? imported = dictionary['SVG_Dict']?.container;
  if (imported != null && (imported.entries.length != 1 || imported['SVG_AttributesDict']?.container?.entries.length != 1)) {
    throw UnsupportedError('Retained SVG transforms require a complete imported matrix field.');
  }
}

/// Requires a literal six-coordinate affine transform, without applying it.
void _nativeSvgMetadataMatrix(AiNativeEntry field, {required bool svg}) {
  final String? text = field.type == 'String' ? field.text()?.trim() : null;
  final String? values = svg ? (text == null ? null : RegExp(r'^matrix\(([^()]*)\)$').firstMatch(text)?.group(1)) : text;
  final List<String> coordinates = values?.trim().split(RegExp(r'[\s,]+')) ?? const [];
  if (coordinates.length != 6 || coordinates.any((coordinate) => double.tryParse(coordinate)?.isFinite != true || double.parse(coordinate).abs() > 9007199254740991)) {
    throw UnsupportedError('Retained SVG transforms require six finite portable matrix values.');
  }
}

/// Recognizes only import provenance and named-view XML, never SVG drawing data.
void _nativeSvgMetadataNode(AiNativeEntry entry, {required String name, required bool layer, bool attribute = false}) {
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
  if (node.entries.length != 5 || node['xmlnode-nodetype']?.number != (attribute ? 2 : 1) || node['xmlnode-nodename']?.text() != name || node['xmlnode-nodevalue']?.text() == null) {
    throw UnsupportedError('Retained SVG metadata requires complete literal XML nodes.');
  }
  final AiNativeContainer attributes = node['xmlnode-attributes']!.container!;
  final AiNativeContainer children = node['xmlnode-children']!.container!;
  if (attribute) {
    if (attributes.entries.isNotEmpty || children.entries.isNotEmpty) {
      throw UnsupportedError('Retained SVG attributes cannot hide child nodes.');
    }
    return;
  }
  if (node['xmlnode-nodevalue']!.text()!.isNotEmpty) {
    throw UnsupportedError('Retained SVG metadata elements cannot contain artwork or text.');
  }
  final Set<String> allowed = name == 'sodipodi:namedview'
      ? _nativeSvgViewAttributes
      : layer
      ? _nativeSvgDocumentAttributes
      : const {};
  _referenceFields(
    attributes,
    const {},
    nested: {
      for (final String key in allowed) key: (field) => _nativeSvgMetadataNode(field, name: key, layer: layer, attribute: true),
    },
  );
  if (layer || name == 'sodipodi:namedview') {
    if (children.entries.isNotEmpty) {
      throw UnsupportedError('Retained SVG document/view metadata cannot contain drawing nodes.');
    }
  } else {
    if (children.entries.length > 1 || children.entries.any((field) => field.key != null || field.type != null || field.isQualifier)) {
      throw UnsupportedError('Retained SVG metadata requires a single unnamed view child.');
    }
    for (final AiNativeEntry child in children.entries) {
      _nativeSvgMetadataNode(child, name: 'sodipodi:namedview', layer: false);
    }
  }
}
