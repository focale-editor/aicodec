import 'dart:convert';

import 'package:aicodec/aicodec.dart';
import 'package:checks/checks.dart';
import 'package:test/test.dart';

import 'ai_native_artboards_test.dart' show mixedArtboardSource;
import 'ai_native_artwork_movement_test.dart' show movementLayer;
import 'ai_native_group_creation_test.dart' show groupCreationDrawing;
import 'ai_native_objects_test.dart' show objectDictionary, objectSource;
import 'ai_native_path_topology_test.dart' show topologyBounds, topologyGeometry, topologyRectangle;

/// Encodes the complete five-field native XML envelope, including empty values.
String contourMetadataNode(String name, {String value = '', String attributes = '', String children = '', bool attribute = false}) =>
    '/XMLNode : /Dictionary : $attributes ; (xmlnode-attributes) , ${attribute ? 2 : 1} /Int (xmlnode-nodetype) , '
    '/Array : $children ; (xmlnode-children) , ($value) /String (xmlnode-nodevalue) , ($name) /String (xmlnode-nodename) , ;';

/// Retains one named view, its current-layer reference and import provenance.
String contourMetadataSource({String documentAttributes = '', String viewAttributes = '', String groupFields = '', String compoundFields = '', String state = '0 1 0 2 0 Xy'}) {
  final String document =
      '${contourMetadataNode('SVG_ThisElement', attributes: '${contourMetadataNode('inkscape:version', value: '1.2.1', attribute: true)} (inkscape:version) , $documentAttributes')} (SVG_ThisElement) ,';
  final String view =
      '${contourMetadataNode(
        'SVG_ThisElement',
        children: '${contourMetadataNode('sodipodi:namedview', attributes: '${contourMetadataNode('inkscape:current-layer', value: 'Current', attribute: true)} (inkscape:current-layer) , $viewAttributes')} ,',
      )} (SVG_ThisElement) ,';
  final String compound = '*u $state $topologyRectangle f $topologyRectangle f *U\n${objectDictionary(identifier: 'Compound', extra: '7 /Int (SVG_ShapeType) , $compoundFields')}';
  final String transformed =
      'u $compound\nU\n${objectDictionary(identifier: 'Current', extra: '/Dictionary : /Dictionary : (matrix\\(1,0,0,1,2,3\\)) /String (transform) , ; (SVG_AttributesDict) , ; (SVG_Dict) , (1 0 0 1 2 3) /String (AdobeObjectMatrix) , $groupFields')}';
  final String layer = movementLayer('Root', 'u U\n${objectDictionary(identifier: 'View', extra: '$view 1 /Bool (SVG_CreatedByImporter) ,')}\nq $transformed\nQ');
  return objectSource(layer.replaceFirst('%_/XMLUID : (Root)', '%_$document\n%_/XMLUID : (Root)'), setup: '');
}

/// Applies a host contour replacement without requesting metadata interpretation.
AiNativeDrawing _edit(AiNativeDrawing drawing) => drawing.editPaths(
  edits: [AiNativePathEdit(path: drawing.paths.first, segments: topologyGeometry())],
  bounds: topologyBounds,
);

/// Requires exact original dictionaries, identities, scalar state and owners.
void _retained(AiNativeDrawing before, AiNativeDrawing after) {
  final List<AiNativeContainer> original = before.records.roots.where((record) => record.type == 'ArtDictionary').toList();
  final List<AiNativeContainer> result = after.records.roots.where((record) => record.type == 'ArtDictionary').toList();
  check(result).length.equals(original.length);
  for (final (int, AiNativeContainer) entry in original.indexed) {
    check(after.records.program.bytes.sublist(result[entry.$1].start, result[entry.$1].end)).deepEquals(before.records.program.bytes.sublist(entry.$2.start, entry.$2.end));
  }
  check(after.groups.map((group) => group.opening.operator)).deepEquals(before.groups.map((group) => group.opening.operator));
  check(after.items.whereType<AiNativeInstruction>().where((item) => item.operator == 'Xy').map((item) => item.numbers)).deepEquals(
    before.items.whereType<AiNativeInstruction>().where((item) => item.operator == 'Xy').map((item) => item.numbers),
  );
}

/// Qualifies retention independently of metadata lifecycle or reference removal.
void main() {
  test('edits compound contours while retaining imported document view and transform metadata', () {
    final String source = contourMetadataSource();
    final AiNativeDrawing drawing = groupCreationDrawing(source);
    final AiNativeDrawing result = _edit(drawing);
    _retained(drawing, result);
    check(result.paths.first.segments.map((segment) => segment.operator)).deepEquals(['m', 'C', 'L']);
    check(result.pathTopology(path: result.paths.first).groups.map((group) => group.opening.operator)).deepEquals(['q', 'u', '*u']);
    check(AiNativeLayers.decode(drawing: result).layers.single.bindingIssue).isNotNull();
    check(AiNativeObjects.decode(drawing: result).objects.where((object) => object.source is AiNativeGroup && object.dictionary != null).every((object) => object.bindingIssue != null)).isTrue();
    check(latin1.decode(drawing.records.program.bytes)).equals(source);
  });

  test('updates all compound masks atomically without moving imported owners', () {
    final AiNativeDrawing drawing = groupCreationDrawing(contourMetadataSource());
    final AiNativeDrawing masked = drawing.editPaths(
      edits: [for (final AiNativePath path in drawing.paths) AiNativePathEdit(path: path, mask: .closed)],
      bounds: topologyBounds,
    );
    final AiNativeDrawing cleared = masked.editPaths(
      edits: [for (final AiNativePath path in masked.paths) AiNativePathEdit(path: path, mask: .none)],
      bounds: topologyBounds,
    );
    _retained(drawing, masked);
    _retained(drawing, cleared);
    check(masked.paths.every((path) => masked.pathTopology(path: path).mask == .closed)).isTrue();
    check(cleared.paths.every((path) => cleared.pathTopology(path: path).mask == .none)).isTrue();
    check(
      () => drawing.editPaths(
        edits: [AiNativePathEdit(path: drawing.paths.first, mask: .closed)],
        bounds: topologyBounds,
      ),
    ).throws<UnsupportedError>();
  });

  test('keeps metadata lifecycle and removed-reference qualification separate', () {
    final AiNativeDrawing drawing = groupCreationDrawing(contourMetadataSource());
    check(() => drawing.releaseCompounds(groups: [drawing.groups.firstWhere((group) => group.compound)], bounds: topologyBounds, inheritParentFlags: true)).throws<UnsupportedError>();
    final AiNativeDrawing released = drawing.releaseCompounds(groups: [drawing.groups.firstWhere((group) => group.compound)], bounds: topologyBounds, discardMetadata: true);
    check(released.groups.any((group) => group.compound)).isFalse();
    check(released.paths.length).equals(drawing.paths.length);
    final String source = contourMetadataSource()
        .replaceFirst('%%Trailer', '*u $topologyRectangle f *U\n${objectDictionary(identifier: 'Removable')}\n%%Trailer')
        .replaceFirst('(Current) /String (xmlnode-nodevalue)', '(Removable) /String (xmlnode-nodevalue)');
    final AiNativeDrawing retainedReference = groupCreationDrawing(source);
    final AiNativeDrawing edited = _edit(retainedReference);
    final List<String> identities = AiNativeObjects.decode(drawing: edited).objects.where((object) => object.identifier != null).map((object) => latin1.decode(object.identifier!.bytes)).toList();
    check(identities.toSet()).length.equals(identities.length);
    check(() => edited.releaseCompounds(groups: [edited.groups.last], bounds: topologyBounds, discardMetadata: true, inheritParentFlags: true)).throws<UnsupportedError>();
    check(latin1.decode(retainedReference.records.program.bytes)).equals(source);
  });

  test('rejects drawing XML unknown fields malformed matrices and disguised attributes', () {
    final String valid = contourMetadataSource();
    final List<String> invalid = [
      contourMetadataSource(documentAttributes: '${contourMetadataNode('d', value: 'M0 0L1 1', attribute: true)} (d) ,'),
      contourMetadataSource(viewAttributes: '${contourMetadataNode('href', value: '#Compound', attribute: true)} (href) ,'),
      contourMetadataSource(groupFields: '(foreign) /String (FutureMetadata) ,'),
      contourMetadataSource(compoundFields: '7 /Int (SVG_ShapeType) ,'),
      valid.replaceFirst('(sodipodi:namedview)', '(svg:path)'),
      valid.replaceFirst('(inkscape:current-layer)', '(href)'),
      valid.replaceFirst('7 /Int (SVG_ShapeType)', '6 /Int (SVG_ShapeType)'),
      valid.replaceFirst('1 /Bool (SVG_CreatedByImporter)', '2 /Int (SVG_CreatedByImporter)'),
      valid.replaceFirst('(1 0 0 1 2 3)', '(1 0 0 1 2 Infinity)'),
      valid.replaceFirst('matrix\\(1,0,0,1,2,3\\)', 'translate\\(2,3\\)'),
      valid.replaceFirst('(1 0 0 1 2 3) /String (AdobeObjectMatrix) ,', ''),
      valid.replaceFirst('(matrix\\(1,0,0,1,2,3\\)) /String (transform) ,', ''),
      valid.replaceFirst('/ArtDictionary :', '/ArtDictionary : /NotRecorded'),
    ];
    for (final String source in invalid) {
      expect(() => _edit(groupCreationDrawing(source)), throwsA(anyOf(isA<FormatException>(), isA<UnsupportedError>())));
    }
  });

  test('does not turn SVG-tagged path caches into editable ordinary geometry', () {
    final String source = objectSource(
      '$topologyRectangle f\n${objectDictionary(identifier: 'Path', extra: '${contourMetadataNode('SVG_ThisElement')} (SVG_ThisElement) ,')}',
      setup: '',
    );
    final AiNativeDrawing drawing = groupCreationDrawing(source);
    check(() => _edit(drawing)).throws<UnsupportedError>();
    check(latin1.decode(drawing.records.program.bytes)).equals(source);
  });

  test('never relaxes lexical ownership conditional boundaries or applied group styles', () {
    final String valid = contourMetadataSource();
    for (final String source in [
      valid.replaceFirst('u U', '2 Ae u U'),
      valid.replaceFirst('u U', 'u U\n1 (NamedStyle) XW'),
      valid.replaceFirst('\n%_;\nq ', '\n%_;\n1 (NamedStyle) XW\nq '),
      valid.replaceFirst('u U', '%AI17_Begin_Content_if_version_gt:24 4\nu U').replaceFirst('\nq ', '\n%AI17_End_Versioned_Content\nq '),
      valid.replaceFirst('u U', 'u U\n%%FutureAttachedData: opaque'),
      valid.replaceFirst('1 AE', '1 AE\n%%FutureLayerData: opaque'),
      valid.replaceFirst('1 1 1 1 0 0 1 0 79 128 255 0 50 0 Lb', '1 1 1 1 0 1 1 0 79 128 255 0 50 0 Lb'),
    ]) {
      expect(() => _edit(groupCreationDrawing(source)), throwsA(anyOf(isA<FormatException>(), isA<UnsupportedError>())));
    }
  });

  test('preserves all literal transparency modes and refuses malformed state without replaying it', () {
    for (int mode = 0; mode <= 15; mode++) {
      final AiNativeDrawing drawing = groupCreationDrawing(contourMetadataSource(state: '$mode 0.25 1 2 1 Xy'));
      _retained(drawing, _edit(drawing));
    }
    for (final String state in ['16 1 0 0 0 Xy', '-1 1 0 0 0 Xy', '0 1.5 0 0 0 Xy', '0 1 2 0 0 Xy', '0 1 0 3 0 Xy', '0 1 0 0 2 Xy', '0 1 0 0 Xy']) {
      expect(() => _edit(groupCreationDrawing(contourMetadataSource(state: state))), throwsA(anyOf(isA<FormatException>(), isA<UnsupportedError>())));
    }
  });

  test('retains complete CC neighbors without promoting their printing paths', () {
    final String ordinary = 'u $topologyRectangle f $topologyRectangle f U\n${objectDictionary(identifier: 'Imported', extra: '${contourMetadataNode('SVG_ThisElement')} (SVG_ThisElement) ,')}';
    final String source = mixedArtboardSource().replaceFirst('%%Trailer', '$ordinary\n%%Trailer');
    final AiNativeDrawing drawing = groupCreationDrawing(source);
    final AiNativeDrawing result = drawing.editPaths(
      edits: [AiNativePathEdit(path: drawing.paths.last, segments: topologyGeometry())],
      bounds: topologyBounds,
    );
    _retained(drawing, result);
    check(result.records.program.bytes.take(drawing.paths.last.start).toList()).deepEquals(drawing.records.program.bytes.take(drawing.paths.last.start).toList());
    check(
      () => result.editPaths(
        edits: [AiNativePathEdit(path: result.liveShapes.first.path!, segments: topologyGeometry())],
        bounds: topologyBounds,
      ),
    ).throws<UnsupportedError>();
    final AiNativeDrawing limited = groupCreationDrawing(source, limits: AiNativeLimits(maxDecodedBytes: source.length + 8));
    check(
      () => limited.editPaths(
        edits: [
          AiNativePathEdit(
            path: limited.paths.last,
            segments: [
              AiPathSegment(operator: 'm', coordinates: [0, 0]),
              for (int index = 0; index < 200; index++) AiPathSegment(operator: 'L', coordinates: [index.toDouble(), 0]),
            ],
          ),
        ],
        bounds: topologyBounds,
      ),
    ).throws<FormatException>();
  });
}
