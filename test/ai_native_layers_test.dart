import 'dart:convert';

import 'package:aikit/aikit.dart';
import 'package:checks/checks.dart';
import 'package:test/test.dart';

/// Writes representative CC layer wrappers with separately owned identifiers.
String _layer(String name, {String? identifier, String children = '', int expanded = 0, String attributes = '1 1 1 1 0 0 1 0 79 128 255 0 50 0'}) =>
    '''%AI5_BeginLayer
$attributes Lb
($name) Ln
$expanded AE
${identifier == null ? '' : '%_/ArtDictionary :\n%_/XMLUID : ($identifier) ; (AI10_ArtUID) ,\n%_;\n%_'}
$children
LB
%AI5_EndLayer--''';

/// Two roots contain a hidden child and unrelated opaque artwork respectively.
String get _body =>
    '${_layer(
      'Parent',
      identifier: 'Parent',
      expanded: 1,
      children: _layer('Child', identifier: 'Child', attributes: '0 1 0 1 0 0 0 1 255 79 79 0 50 0', children: '1 A 1 Xw'),
    )}\n'
    '${_layer('Other', identifier: 'Other', children: '0 A\n17 FuturePaint\n0 0 m 1 1 L N\n/FutureRecord : (opaque) /Data ;')}';

/// Keeps header and body declarations separate under the original parser limits.
AiNativeLayers _layers({String? body, String header = '%AI5_NumLayers: 2\n%AI5_OpenViewLayers: 37', String setup = '', AiNativeLimits limits = const AiNativeLimits()}) => AiNativeLayers.decode(
  drawing: AiNativeDrawing.decode(
    records: AiNativeRecords.decode(
      program: AiProgram.decode(bytes: latin1.encode('%!PS-Adobe-3.0\n$header\n%%EndComments\n$setup\n%%EndSetup\n${body ?? _body}\n%%Trailer\n%%EOF\n'), limits: limits),
    ),
  ),
);

/// Verifies layer-specific source ownership and atomic insertion contracts.
void main() {
  test('binds root counts, source wrappers, names, expansion and header identities', () {
    final AiNativeLayers model = _layers();
    check(model.layers).length.equals(3);
    check(model.rootCount).equals(2);
    check(model.declaredRootCount).equals(2);
    check(model.rootCountMatches).isTrue();
    check(model.viewHeader!.values).deepEquals([37.0]);
    check(model.layers.map((layer) => layer.parentIndex)).deepEquals([null, 0, null]);
    check(model.layers.map((layer) => layer.expanded)).deepEquals([true, false, false]);
    check(model.layers.map((layer) => layer.identifier!.bytes)).deepEquals([latin1.encode('Parent'), latin1.encode('Child'), latin1.encode('Other')]);
    check(model.childrenOf(model.layers.first)).deepEquals([model.layers[1]]);
    check(model.layerFor(model.layers[1].source)).identicalTo(model.layers[1]);
    check(model.layers[1].source.visible).isFalse();
    check(model.layers[1].source.locked).isTrue();
    for (final AiNativeLayer layer in model.layers) {
      check(layer.bindingIssue).isNull();
      check(layer.start).equals(layer.openingComment!.start);
      check(layer.end).equals(layer.closingComment!.end);
      check(layer.identifier!.field.owner.source).identicalTo(layer.dictionary!);
    }
    check(model.layers.clear).throws<UnsupportedError>();
    check(model.layers.first.childIndices.clear).throws<UnsupportedError>();
    check(() => model.layers.first.identifier!.bytes[0] = 0).throws<UnsupportedError>();
    check(() => model.layers.first.nameBytes![0] = 0).throws<UnsupportedError>();
    check(() => model.childrenOf(_layers().layers.first)).throws<ArgumentError>();
    check(() => model.layerFor(_layers().layers.first.source)).throws<ArgumentError>();
  });

  test('inserts an identified root while preserving opaque child artwork and source state', () {
    final AiNativeLayers model = _layers();
    final List<int> source = model.drawing.records.program.bytes.toList();
    final List<int> name = latin1.encode('R\u00e9sum\u00e9 (copy)');
    final AiNativeLayers result = model.insertAfter(after: model.layers.first, nameBytes: name, identifierBytes: latin1.encode('Fresh_layer'), discardViewState: true);
    name[0] = 0;
    check(result.layers).length.equals(4);
    check(result.rootCount).equals(3);
    check(result.declaredRootCount).equals(3);
    check(result.viewComments).isEmpty();
    check(result.layers.map((layer) => layer.source.name)).deepEquals(['Parent', 'Child', 'R\u00e9sum\u00e9 (copy)', 'Other']);
    check(result.layers[2].identifier!.bytes).deepEquals(latin1.encode('Fresh_layer'));
    check(result.layers[2].expanded).equals(false);
    check(result.layers[2].source.begin.numbers!).deepEquals(model.layers.first.source.begin.numbers!);
    check(result.layers[2].childIndices).isEmpty();
    check(result.drawing.paths.single.segments.map((segment) => segment.coordinates)).deepEquals(model.drawing.paths.single.segments.map((segment) => segment.coordinates));
    check(latin1.decode(result.drawing.records.program.bytes)).contains('17 FuturePaint\n0 0 m 1 1 L N\n/FutureRecord : (opaque) /Data ;');
    check(result.drawing.items.whereType<AiNativeInstruction>().where((item) => const {'A', 'Xw'}.contains(item.operator)).map((item) => item.numbers)).deepEquals([
      [1.0],
      [1.0],
      [0.0],
    ]);
    check(model.drawing.records.program.bytes).deepEquals(source);
    check(() => result.insertAfter(after: model.layers.first, nameBytes: [])).throws<ArgumentError>();
  });

  test('inserts a hidden locked sublayer without changing the root count', () {
    final AiNativeLayers model = _layers();
    final AiNativeLayers result = model.insertAfter(after: model.layers[1], nameBytes: latin1.encode('Nested'), identifierBytes: latin1.encode('Nested'), discardViewState: true);
    check(result.rootCount).equals(2);
    check(result.declaredRootCount).equals(2);
    check(result.layers[2].parentIndex).equals(0);
    check(result.layers[2].source.visible).isFalse();
    check(result.layers[2].source.locked).isTrue();
    check(result.childrenOf(result.layers.first).map((layer) => layer.source.name)).deepEquals(['Child', 'Nested']);
  });

  test('requires explicit panel-state invalidation and rejects stale count declarations', () {
    final AiNativeLayers model = _layers(header: '%AI5_NumLayers: 2\n%AI5_OpenViewLayers: 37\n%%+ 8\n%%+ 9');
    check(model.viewComments).length.equals(3);
    check(() => model.insertAfter(after: model.layers.first, nameBytes: [], identifierBytes: latin1.encode('New'))).throws<UnsupportedError>();
    final AiNativeLayers result = model.insertAfter(after: model.layers.first, nameBytes: [], identifierBytes: latin1.encode('New'), discardViewState: true);
    check(result.viewHeader).isNull();
    check(latin1.decode(result.drawing.records.program.bytes)).not((value) => value.contains('%%+'));
    final AiNativeLayers stale = _layers(header: '%AI5_NumLayers: 3');
    check(stale.rootCountMatches).isFalse();
    check(() => stale.insertAfter(after: stale.layers.first, nameBytes: [], identifierBytes: latin1.encode('New'))).throws<FormatException>();
  });

  test('requires fresh identifiers in the source namespace and bounded native byte strings', () {
    final AiNativeLayers model = _layers();
    for (final List<int>? identifier in [
      null,
      [],
      latin1.encode('Child'),
      latin1.encode('bad name'),
      [255],
    ]) {
      check(() => model.insertAfter(after: model.layers.first, nameBytes: [], identifierBytes: identifier, discardViewState: true)).throws<ArgumentError>();
    }
    check(() => model.insertAfter(after: model.layers.first, nameBytes: [256], identifierBytes: latin1.encode('Fresh'), discardViewState: true)).throws<ArgumentError>();
    check(() => model.insertAfter(after: _layers().layers.first, nameBytes: [], identifierBytes: latin1.encode('Fresh'), discardViewState: true)).throws<ArgumentError>();
    final AiNativeLayers anonymous = _layers(body: _layer('Plain'), header: '');
    check(() => anonymous.insertAfter(after: anonymous.layers.first, nameBytes: [], identifierBytes: latin1.encode('Fresh'))).throws<ArgumentError>();
    check(anonymous.insertAfter(after: anonymous.layers.first, nameBytes: [65]).layers.last.identifier).isNull();
  });

  test('retains classic bare layers and missing declarations without inventing CC metadata', () {
    final AiNativeLayers model = _layers(body: '1 1 1 1 0 0 0 79 128 255 Lb (Classic) Ln LB', header: '');
    check(model.layers.single.expanded).isNull();
    check(model.layers.single.openingComment).isNull();
    final AiNativeLayers result = model.insertAfter(after: model.layers.single, nameBytes: [0, 255, 40, 92]);
    check(result.layers.last.nameBytes!).deepEquals([0, 255, 40, 92]);
    check(result.layers.last.source.begin.numbers!).length.equals(10);
    check(result.layers.last.dictionary).isNull();
    check(result.layers.last.expanded).isNull();
    check(result.declaredRootCount).isNull();
    check(latin1.decode(result.drawing.records.program.bytes)).not((value) => value.contains('AI5_BeginLayer'));
  });

  test('rejects unmatched, repeated and crossing DSC layer declarations', () {
    for (final String body in [
      _layer('Broken').replaceFirst('%AI5_BeginLayer', ''),
      _layer('Broken').replaceFirst('%AI5_EndLayer--', ''),
      _layer('Broken').replaceFirst('%AI5_BeginLayer', '%AI5_BeginLayer\n%AI5_BeginLayer'),
      '%AI5_BeginLayer\n0 0 m 1 1 L N\n${_layer('Next')}',
      _layer('Parent', children: _layer('Child').replaceFirst('%AI5_EndLayer--', '')).replaceFirst('LB\nLB', 'LB\n%AI5_EndLayer--\nLB'),
    ]) {
      check(() => _layers(body: body, header: '')).throws<FormatException>();
    }
  });

  test('ignores fake markers in procedures, records, embedded sources and setup', () {
    final AiNativeLayers model = _layers(
      header: '',
      setup: '%AI5_BeginLayer\n%AI5_NumLayers: 99',
      body:
          '{\n%AI5_BeginLayer\n%AI5_EndLayer--\n} FutureProcedure\n'
          '/Future :\n%AI5_BeginLayer\n%AI5_EndLayer--\n;\n'
          '%%BeginDocument: opaque\n%AI5_BeginLayer\n%AI5_EndLayer--\n%%EndDocument\n'
          '${_layer('Actual')}',
    );
    check(model.layers).length.equals(1);
    check(model.declaredRootCount).isNull();
    check(model.layers.single.source.name).equals('Actual');
  });

  test('rejects ambiguous header declarations and reports unqualified layer layouts', () {
    for (final String header in ['%AI5_NumLayers: 2\n%AI5_NumLayers: 2', '%AI17_Begin_Content_if_version_gt:24 4\n%AI5_NumLayers: 2\n%AI17_End_Versioned_Content']) {
      check(() => _layers(header: header)).throws<UnsupportedError>();
    }
    check(() => _layers(header: '%AI5_NumLayers: -1')).throws<FormatException>();
    check(() => _layers(body: _layer('Bad', expanded: 2), header: '')).throws<FormatException>();
    check(
      () => _layers(
        body: _layer('Bad', attributes: '1 1 1 1 0 0 0 79 128 256'),
        header: '',
      ),
    ).throws<FormatException>();
    for (final String body in [
      _layer('Future', attributes: '1 1 1 1 0 0 1 0 79 128 255 0 50 17'),
      _layer('Mask', attributes: '1 1 1 1 0 1 1 0 79 128 255 0 50 0'),
      _layer('Opaque', identifier: 'Opaque').replaceFirst('%_;', '%_7 /Int (FutureField) ,\n%_;'),
    ]) {
      final AiNativeLayers model = _layers(body: body, header: '');
      check(model.layers.single.bindingIssue).isNotNull();
      if (model.layers.single.source.name == 'Opaque') {
        check(model.layers.single.identifier!.bytes).deepEquals(latin1.encode('Opaque'));
      }
      check(() => model.insertAfter(after: model.layers.single, nameBytes: [])).throws<UnsupportedError>();
    }
    check(
      () => _layers(
        body: _layer('Duplicated', identifier: 'A').replaceFirst('%_;', '%_/XMLUID : (B) ; (AI10_ArtUID) ,\n%_;'),
        header: '',
      ),
    ).throws<FormatException>();
  });

  test('refuses insertion between a layer and unresolved trailing metadata', () {
    for (final String suffix in ['/FutureOwner : 1 /Index ;', '%AI8_FutureOwner: 7']) {
      final AiNativeLayers model = _layers(body: '${_layer('Layer')}\n$suffix', header: '');
      check(() => model.insertAfter(after: model.layers.single, nameBytes: [])).throws<UnsupportedError>();
    }
  });

  test('refuses unresolved or conditional metadata inside the copied header', () {
    for (final String body in [
      _layer('Layer').replaceFirst(' Lb', ' Lb\n%AI8_FutureHeader: 7'),
      _layer('Layer', identifier: 'Layer').replaceFirst('%_/ArtDictionary', '%AI17_Begin_Content_if_version_gt:24 4\n%_/ArtDictionary').replaceFirst('%_;', '%_;\n%AI17_End_Versioned_Content'),
      _layer('Layer').replaceFirst('%AI5_BeginLayer', '%AI5_BeginLayer\n%AI8_FutureHeader: 7'),
    ]) {
      final AiNativeLayers model = _layers(body: body, header: '');
      check(model.layers.single.bindingIssue, because: body).isNotNull();
      check(() => model.insertAfter(after: model.layers.single, nameBytes: [])).throws<UnsupportedError>();
    }
  });

  test('enforces output bytes, aggregate tokens and immutable snapshots', () {
    final String body = _layer('Layer', identifier: 'Layer');
    final AiNativeLayers reference = _layers(body: body, header: '');
    final int length = reference.drawing.records.program.bytes.length;
    final AiNativeLayers bytes = _layers(
      body: body,
      header: '',
      limits: AiNativeLimits(maxDecodedBytes: length + 10),
    );
    check(() => bytes.insertAfter(after: bytes.layers.single, nameBytes: [], identifierBytes: latin1.encode('Fresh'))).throws<FormatException>();
    check(() => bytes.insertAfter(after: bytes.layers.single, nameBytes: List.filled(length, 65), identifierBytes: latin1.encode('Fresh'))).throws<AiLimitException>();
    check(() => bytes.insertAfter(after: bytes.layers.single, nameBytes: [], identifierBytes: List.filled(length, 65))).throws<AiLimitException>();
    final List<int> projected = latin1.encode(latin1.decode(reference.drawing.records.program.bytes).replaceAll(RegExp(r'^%_', multiLine: true), '  '));
    final int count = AiPostScript.tokenize(projected).length;
    final AiNativeLayers tokens = _layers(
      body: body,
      header: '',
      limits: AiNativeLimits(maxTokens: count + 1),
    );
    check(() => tokens.insertAfter(after: tokens.layers.single, nameBytes: [], identifierBytes: latin1.encode('Fresh'))).throws<AiLimitException>();
    check(bytes.drawing.records.program.bytes).deepEquals(reference.drawing.records.program.bytes);
  });
}
