import 'dart:convert';

import 'package:checks/checks.dart';
import 'package:illustratorkit/illustratorkit.dart';
import 'package:test/test.dart';

import 'ai_native_artboard_lifecycle_test.dart' show newArtboard;
import 'ai_native_artboards_test.dart' show artboardModel, artboardSource;

/// Encodes literal XML values without borrowing PostScript executable syntax.
String _literal(String value) => '<${latin1.encode(value).map((byte) => byte.toRadixString(16).padLeft(2, '0')).join()}>';

/// Builds the native XML envelope used for both elements and attributes.
String _node({required String name, String value = '', String attributes = '', String children = '', int kind = 1}) =>
    '/XMLNode : /Dictionary : $attributes ; (xmlnode-attributes) , ($name) /String (xmlnode-nodename) , ${_literal(value)} /UnicodeString (xmlnode-nodevalue) , /Array : $children ; (xmlnode-children) , $kind /Int (xmlnode-nodetype) , ;';

/// Creates an element with ordered scalar attribute nodes and child elements.
String artboardSvgElement({required String name, Map<String, String> attributes = const {}, List<String> children = const []}) => _node(
  name: name,
  attributes: attributes.entries.map((field) => '${_node(name: field.key, value: field.value, kind: 2)} (${field.key}) ,').join('\n'),
  children: children.map((child) => '$child ,').join('\n'),
);

/// Stores a local filter graph with duplicate results and a parent animation.
String artboardSvgFilter({String? root}) =>
    '''%AI10_BeginSVGFilter
/SVGFilter : ${root ?? artboardSvgElement(
          name: 'filter',
          attributes: {'id': 'board-0', 'filterRes': '50 50'},
          children: [
            artboardSvgElement(name: 'feFlood', attributes: {'style': 'flood-color:black; flood-opacity:0.4;', 'result': 'board-0'}),
            artboardSvgElement(
              name: 'feGaussianBlur',
              attributes: {'in': 'board-0', 'result': 'board-0', 'stdDeviation': '2'},
              children: [
                artboardSvgElement(name: 'animate', attributes: {'attributeName': 'stdDeviation', 'from': '1', 'to': '5', 'begin': '0s', 'dur': '5s', 'fill': 'freeze'}),
              ],
            ),
            artboardSvgElement(
              name: 'feMerge',
              children: [
                artboardSvgElement(name: 'feMergeNode', attributes: {'in': 'board-0'}),
                artboardSvgElement(name: 'feMergeNode', attributes: {'in': 'SourceGraphic'}),
              ],
            ),
          ],
        )} /Def ;
%AI10_EndSVGFilter
''';

/// Confirms preservation of all bytes outside the explicitly edited Document.
void _retained(AiNativeArtboards before, AiNativeArtboards after) {
  check(after.records.program.bytes.take(after.document.start)).deepEquals(before.records.program.bytes.take(before.document.start));
  check(after.records.program.bytes.skip(after.document.end)).deepEquals(before.records.program.bytes.skip(before.document.end));
}

/// Requires atomic refusal without changing the source snapshot.
void _refused(String filter) {
  final String source = artboardSource(extra: filter);
  final AiNativeArtboards before = artboardModel(source);
  check(() => before.remove(artboards: [before.artboards.first], activeArtboard: null, cropBounds: null)).throws<UnsupportedError>();
  check(latin1.decode(before.records.program.bytes)).equals(source);
}

/// Exercises native filter retention independently of visual effect support.
void main() {
  test('retains complete local filters and animations through all four board edits', () {
    final AiNativeArtboards before = artboardModel(artboardSource(extra: artboardSvgFilter()));
    for (final AiNativeArtboards after in [
      before.create(definition: newArtboard(), index: 1, lastArtboardId: 68, cropBounds: null),
      before.resize(artboard: before.artboards.first, bounds: AiBoundingBox(left: -20, bottom: -40, right: 100, top: 200), cropBounds: null),
      before.reorder(artboards: before.artboards.reversed.toList(), cropBounds: null),
      before.remove(artboards: [before.artboards.first], activeArtboard: null, cropBounds: null),
    ]) {
      _retained(before, after);
    }
  });

  test('retains scalar primitive families including producer extension and separate filter scopes', () {
    final List<String> primitives = [
      for (final String name in ['feBlend', 'feColorMatrix', 'feComposite', 'feConvolveMatrix', 'feDisplacementMap', 'feMorphology', 'feOffset', 'feTile', 'feTurbulence'])
        artboardSvgElement(name: name, attributes: {'in': 'SourceAlpha', 'result': 'board-0'}),
      artboardSvgElement(
        name: 'feDiffuseLighting',
        attributes: {'resultScale': '1', 'lighting-color': 'rgb(10, 20, 30)'},
        children: [
          artboardSvgElement(name: 'feDistantLight', attributes: {'azimuth': '45', 'elevation': '60'}),
        ],
      ),
      artboardSvgElement(
        name: 'feSpecularLighting',
        children: [
          artboardSvgElement(name: 'fePointLight', attributes: {'x': '10', 'y': '20', 'z': '30'}),
        ],
      ),
      artboardSvgElement(
        name: 'feSpecularLighting',
        children: [
          artboardSvgElement(name: 'feSpotLight', attributes: {'pointsAtX': '20', 'limitingConeAngle': '30'}),
        ],
      ),
      artboardSvgElement(
        name: 'feComponentTransfer',
        children: [
          for (final String name in ['feFuncR', 'feFuncG', 'feFuncB', 'feFuncA']) artboardSvgElement(name: name, attributes: {'type': 'table', 'tableValues': '0 0.5 1'}),
        ],
      ),
    ];
    final String filter = artboardSvgFilter(
      root: artboardSvgElement(name: 'filter', attributes: {'id': 'board-0'}, children: primitives),
    );
    final String collection = '$filter${artboardSvgFilter()}'.replaceFirst('%AI10_EndSVGFilter\n%AI10_BeginSVGFilter', '% retained collection separator');
    final AiNativeArtboards before = artboardModel(artboardSource(extra: collection));
    _retained(before, before.reorder(artboards: before.artboards.reversed.toList(), cropBounds: null));
  });

  test('keeps local clock animations literal including color values and scalar sets', () {
    final String root = artboardSvgElement(
      name: 'filter',
      children: [
        artboardSvgElement(name: 'animate', attributes: {'attributeName': 'filterRes', 'values': '50 50; 20 20; 50 50', 'begin': '-1s;00:00:01.5;2min', 'dur': '10s', 'repeatDur': 'indefinite'}),
        artboardSvgElement(
          name: 'feFlood',
          children: [
            artboardSvgElement(name: 'animate', attributes: {'attributeName': 'flood-color', 'values': '#ff0000;rgb(0, 255, 0);blue', 'dur': '5s'}),
            artboardSvgElement(name: 'set', attributes: {'attributeName': 'flood-opacity', 'to': '0.25', 'begin': '1s'}),
          ],
        ),
      ],
    );
    final AiNativeArtboards before = artboardModel(artboardSource(extra: artboardSvgFilter(root: root)));
    _retained(before, before.remove(artboards: [before.artboards.first], activeArtboard: null, cropBounds: null));
  });

  test('rejects external resources scripts unknown fields and indirect style dependencies', () {
    for (final String child in [
      artboardSvgElement(name: 'script'),
      artboardSvgElement(name: 'feImage', attributes: {'xlink:href': '#board-0'}),
      artboardSvgElement(name: 'feGaussianBlur', attributes: {'onload': 'run()'}),
      artboardSvgElement(name: 'feGaussianBlur', attributes: {'ArtboardIndex': '0'}),
      artboardSvgElement(name: 'feFlood', attributes: {'style': 'flood-color:url(#board-0)'}),
      artboardSvgElement(name: 'feFlood', attributes: {'style': 'flood-color:var(--color)'}),
      artboardSvgElement(name: 'feFlood', attributes: {'style': r'flood-color:\75rl(#board-0)'}),
      artboardSvgElement(name: 'feFlood', attributes: {'lighting-color': 'red icc-color(board-0,1,0,0)'}),
      artboardSvgElement(name: 'feFlood', attributes: {'style': 'filter:url(#board-0)'}),
      _node(name: 'feFlood', value: 'executable'),
    ]) {
      _refused(
        artboardSvgFilter(
          root: artboardSvgElement(name: 'filter', children: [child]),
        ),
      );
    }
    _refused(
      artboardSvgFilter(
        root: artboardSvgElement(name: 'filter', attributes: {'xlink:href': '#board-0'}),
      ),
    );
  });

  test('rejects animations with nonlocal targets events or reference-bearing values', () {
    for (final Map<String, String> attributes in [
      {'attributeName': 'in', 'to': 'board-0'},
      {'attributeName': 'id', 'to': 'board-0'},
      {'attributeName': 'style', 'to': 'flood-color:red'},
      {'attributeName': 'flood-opacity', 'xlink:href': '#board-0'},
      {'attributeName': 'flood-opacity', 'begin': 'board-0.click'},
      {'attributeName': 'flood-opacity', 'end': 'board-0.end'},
      {'attributeName': 'flood-color', 'values': 'red;url(#board-0)'},
      {'attributeName': 'ArtboardIndex', 'to': '1'},
      {'to': '1'},
    ]) {
      _refused(
        artboardSvgFilter(
          root: artboardSvgElement(
            name: 'filter',
            children: [
              artboardSvgElement(
                name: 'feFlood',
                children: [artboardSvgElement(name: 'animate', attributes: attributes)],
              ),
            ],
          ),
        ),
      );
    }
  });

  test('rejects malformed XML ownership without ignoring nested or duplicate records', () {
    final String filter = artboardSvgFilter();
    final List<String> variants = [
      filter.replaceFirst('(id) /String', '(other) /String'),
      filter.replaceFirst('2 /Int (xmlnode-nodetype)', '1 /Int (xmlnode-nodetype)'),
      filter.replaceFirst('(xmlnode-nodetype)', '(unknown-node-field)'),
      filter.replaceFirst('/Dictionary :', '/Dictionary : /NotRecorded ,'),
      filter.replaceFirst('; (xmlnode-attributes)', '${_node(name: 'id', value: 'again', kind: 2)} (id) , ; (xmlnode-attributes)'),
      filter.replaceFirst('/Def ;', '/Other ;'),
      filter.replaceFirst('/Def ;', '/Def , ${artboardSvgElement(name: 'filter')} /Other ;'),
      artboardSvgFilter(root: artboardSvgElement(name: 'feFlood')),
      artboardSvgFilter(
        root: artboardSvgElement(
          name: 'filter',
          children: [artboardSvgElement(name: 'feMergeNode')],
        ),
      ),
    ];
    variants.forEach(_refused);
  });

  test('requires exact unconditional setup boundaries with no hidden programs', () {
    final String filter = artboardSvgFilter();
    final List<String> variants = [
      filter.replaceFirst('%AI10_BeginSVGFilter\n', ''),
      filter.replaceFirst('%AI10_EndSVGFilter', ''),
      filter.replaceFirst('%AI10_BeginSVGFilter', '%AI10_BeginSVGFilter\n%AI24_ArtboardRef: board-0'),
      filter.replaceFirst('%AI10_EndSVGFilter', '0 load\n%AI10_EndSVGFilter'),
      filter.replaceFirst('/SVGFilter :', '/SVGFilter :\n%AI24_ArtboardRef: board-0'),
      '%AI10_BeginSVGFilter\n$filter%AI10_EndSVGFilter\n',
      '%AI17_Begin_Content_if_version_gt:24 4\n$filter%AI17_End_Versioned_Content\n',
      '%AI10_BeginSVGFilter\n%AI10_EndSVGFilter\n',
    ];
    variants.forEach(_refused);
  });

  test('retains original depth and output budgets for nested filter trees', () {
    final String source = artboardSource(extra: artboardSvgFilter());
    check(() => artboardModel(source, limits: const AiNativeLimits(maxDepth: 8))).throws<FormatException>();
    final AiNativeArtboards bounded = artboardModel(source, limits: AiNativeLimits(maxDecodedBytes: source.length));
    check(() => bounded.create(definition: newArtboard(), index: 1, lastArtboardId: 68, cropBounds: null)).throws<FormatException>();
  });
}
