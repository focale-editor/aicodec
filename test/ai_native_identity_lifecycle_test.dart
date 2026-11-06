import 'dart:convert';

import 'package:checks/checks.dart';
import 'package:illustratorkit/illustratorkit.dart';
import 'package:test/test.dart';

import 'ai_native_artwork_movement_test.dart' show movementLayer, movementPath;
import 'ai_native_objects_test.dart' show objectDictionary, objectSource;

/// Uses identified nested layers, ordinary groups/paths and anonymous metadata.
String get identityLifecycleSource => objectSource(
  '${movementLayer('A', '${movementPath(10)}\n${objectDictionary(identifier: 'path_a', name: 'First')}\n'
      '${movementLayer('A1', '0.7 g u ${movementPath(20)}\n${objectDictionary(identifier: 'path_child')}\n0.4 g 5 w U\n${objectDictionary(identifier: 'group_child', name: 'Pair')}', hidden: true)}')}\n'
  '${movementLayer('B', '0.9 g ${movementPath(30)}\n${objectDictionary(identifier: 'path_b')}')}\n'
  '${movementLayer('C', '${movementPath(40)}\n${objectDictionary(name: 'Retained')}')}',
  setup: '',
).replaceFirst('%%EndComments', '%AI5_NumLayers: 3\n%AI5_OpenViewLayers: 37\n%%EndComments');

/// Decodes independently owned immutable handles and source limits.
AiNativeLayers _model(String source, {AiNativeLimits limits = const AiNativeLimits()}) => AiNativeLayers.decode(
  drawing: AiNativeDrawing.decode(
    records: AiNativeRecords.decode(
      program: AiProgram.decode(bytes: latin1.encode(source), limits: limits),
    ),
  ),
);

/// Exposes source identities without combining different owners with equal names.
List<String> _identities(AiNativeLayers model) => model.structure.identifiers.map((identifier) => latin1.decode(identifier.bytes)).toList();

/// Reserves distinct caller-supplied names for every selected layer identity.
Map<AiNativeLayer, List<int>> layerCopyIdentifiers(AiNativeLayers model) => {model.layers[0]: latin1.encode('Copy_A'), model.layers[1]: latin1.encode('Copy_A1')};

/// Identifies every copied path/group, including the nested hidden layer's art.
Map<AiNativeItem, List<int>> artworkCopyIdentifiers(AiNativeLayers model) => {
  model.drawing.paths[0]: latin1.encode('Copy_path_a'),
  model.drawing.paths[1]: latin1.encode('Copy_path_child'),
  model.drawing.groups.single: latin1.encode('Copy_group_child'),
};

/// Observes consumed paint without sharing the editor's identity or state helpers.
List<List<Object>> _painted(AiNativeDrawing drawing) {
  final Map<String, Object> state = {};
  final List<List<Object>> result = [];
  for (final AiNativeInstruction item in drawing.items.whereType<AiNativeInstruction>()) {
    if (const {'g', 'G', 'A', 'Xw', 'w', 'd', 'O', 'R', 'XR', 'D', 'Ap', 'J', 'j', 'M'}.contains(item.operator)) {
      state[item.operator] = item.operands.map((operand) => operand.lexeme).toList();
    } else if (item.operator == 'm') {
      result.add([item.numbers!.first, Map.of(state)]);
    }
  }
  return result;
}

/// Covers cross-family identity allocation and whole-scope deletion qualification.
void main() {
  test('copies layer and artwork identities together with names, state and ownership', () {
    final AiNativeLayers source = _model(identityLifecycleSource);
    final Map<AiNativeLayer, List<int>> layerIds = layerCopyIdentifiers(source);
    final Map<AiNativeItem, List<int>> artworkIds = artworkCopyIdentifiers(source);
    final AiNativeLayers result = source.duplicate(layers: [source.layers.first], identifiers: layerIds, artworkIdentifiers: artworkIds, discardViewState: true);
    layerIds.values.first[0] = 120;
    artworkIds.clear();
    check(_identities(result)).deepEquals(['A', 'path_a', 'A1', 'path_child', 'group_child', 'Copy_A', 'Copy_path_a', 'Copy_A1', 'Copy_path_child', 'Copy_group_child', 'B', 'path_b', 'C']);
    check(result.declaredRootCount).equals(4);
    check(result.viewComments).isEmpty();
    check(result.layers[3].parentIndex).equals(2);
    check(result.layers[3].source.visible).isFalse();
    check(result.drawing.groups).length.equals(2);
    check(_painted(result.drawing)).deepEquals([..._painted(source.drawing).take(2), ..._painted(source.drawing)]);
    check(AiNativeObjects.decode(drawing: result.drawing).forSource(result.drawing.paths[2]).names.single.stringBytes!).deepEquals(latin1.encode('First'));
    check(latin1.decode(source.drawing.records.program.bytes)).equals(identityLifecycleSource);
  });

  test('reserves one namespace for copied layers and all artwork descendants', () {
    final AiNativeLayers source = _model(identityLifecycleSource);
    for (final String collision in ['Copy_A', 'Copy_A1', 'A', 'B', 'path_b', 'Copy_path_a']) {
      final Map<AiNativeItem, List<int>> identifiers = artworkCopyIdentifiers(source);
      identifiers[source.drawing.groups.single] = latin1.encode(collision);
      check(() => source.duplicate(layers: [source.layers.first], identifiers: layerCopyIdentifiers(source), artworkIdentifiers: identifiers, discardViewState: true)).throws<ArgumentError>();
    }
    final Map<AiNativeLayer, List<int>> layerIds = layerCopyIdentifiers(source);
    layerIds[source.layers[0]] = latin1.encode('path_b');
    check(() => source.duplicate(layers: [source.layers.first], identifiers: layerIds, artworkIdentifiers: artworkCopyIdentifiers(source), discardViewState: true)).throws<ArgumentError>();
    check(latin1.decode(source.drawing.records.program.bytes)).equals(identityLifecycleSource);
  });

  test('requires exactly selected artwork handles and valid fresh identity bytes', () {
    final AiNativeLayers source = _model(identityLifecycleSource);
    final Map<AiNativeItem, List<int>> complete = artworkCopyIdentifiers(source);
    final AiNativeObject wrapper = AiNativeObjects.decode(drawing: source.drawing).forSource(source.drawing.paths.first);
    for (final Map<AiNativeItem, List<int>> identifiers in [
      <AiNativeItem, List<int>>{},
      {...complete}..remove(source.drawing.groups.single),
      {...complete, source.drawing.paths.last: latin1.encode('extra')},
      {...complete, _model(identityLifecycleSource).drawing.paths.first: latin1.encode('foreign')},
      {...complete, wrapper: latin1.encode('wrapper')},
      {...complete, source.drawing.paths.first: latin1.encode('not valid')},
      {
        ...complete,
        source.drawing.paths.first: [256],
      },
    ]) {
      check(() => source.duplicate(layers: [source.layers.first], identifiers: layerCopyIdentifiers(source), artworkIdentifiers: identifiers, discardViewState: true)).throws<ArgumentError>();
    }
    final AiNativeLayers copied = source.duplicate(layers: [source.layers.first], identifiers: layerCopyIdentifiers(source), artworkIdentifiers: complete, discardViewState: true);
    check(() => copied.duplicate(layers: [source.layers.first], identifiers: layerCopyIdentifiers(source), artworkIdentifiers: complete)).throws<ArgumentError>();
  });

  test('copies identified children of anonymous layers without inventing layer IDs', () {
    final AiNativeLayers source = _model(
      objectSource('1 1 1 1 0 0 0 79 128 255 Lb\n${movementPath(10)}\n${objectDictionary(identifier: 'child')}\nLB', setup: '/Dictionary : (child) /String (UnknownReference) , ;'),
    );
    final AiNativeLayers result = source.duplicate(layers: source.layers, artworkIdentifiers: {source.drawing.paths.single: latin1.encode('copy')});
    check(result.layers.every((layer) => layer.identifier == null)).isTrue();
    check(_identities(result)).deepEquals(['child', 'copy']);
    check(latin1.decode(result.drawing.records.program.bytes)).contains('/Dictionary : (child) /String (UnknownReference) , ;');
    check(() => source.duplicate(layers: source.layers)).throws<ArgumentError>();
    check(() => source.remove(layers: source.layers)).throws<UnsupportedError>();
  });

  test('deletes identified paths only within a completely qualified reference scope', () {
    final AiNativeLayers source = _model(identityLifecycleSource);
    final AiNativeDrawing result = source.drawing.removePaths(paths: [source.drawing.paths[0], source.drawing.paths[1]]);
    final AiNativeLayers layers = AiNativeLayers.decode(drawing: result);
    check(_identities(layers)).deepEquals(['A', 'A1', 'group_child', 'B', 'path_b', 'C']);
    check(result.groups.single.paths).isEmpty();
    check(_painted(result)).deepEquals(_painted(source.drawing).skip(2).toList());
    check(layers.viewComments.map((token) => token.lexeme)).deepEquals(source.viewComments.map((token) => token.lexeme));
    check(layers.declaredRootCount).equals(3);
  });

  test('deletes identified groups and their descendants while retaining outgoing state', () {
    final AiNativeLayers source = _model(identityLifecycleSource);
    final AiNativeDrawing result = source.drawing.removeGroups(groups: source.drawing.groups);
    check(_identities(AiNativeLayers.decode(drawing: result))).deepEquals(['A', 'path_a', 'A1', 'B', 'path_b', 'C']);
    check(result.groups).isEmpty();
    check(_painted(result)).deepEquals([_painted(source.drawing)[0], ..._painted(source.drawing).skip(2)]);
    final AiNativeLayers anonymousParent = _model(objectSource('u ${movementPath(10)}\n${objectDictionary(identifier: 'child')}\nU', setup: ''));
    check(anonymousParent.drawing.removeGroups(groups: anonymousParent.drawing.groups).paths).isEmpty();
  });

  test('removes complete layer subtrees with child identities and updates root declarations', () {
    final AiNativeLayers source = _model(identityLifecycleSource);
    final AiNativeLayers result = source.remove(layers: [source.layers.first], discardViewState: true);
    check(_identities(result)).deepEquals(['B', 'path_b', 'C']);
    check(result.declaredRootCount).equals(2);
    check(result.viewComments).isEmpty();
    check(_painted(result.drawing)).deepEquals(_painted(source.drawing).skip(2).toList());
    check(result.drawing.groups).isEmpty();
    final AiNativeLayers empty = source.remove(layers: source.layers.where((layer) => layer.parentIndex == null).toList(), discardViewState: true);
    check(empty.layers).isEmpty();
    check(empty.structure.identifiers).isEmpty();
    check(empty.declaredRootCount).equals(0);
    final AiNativeLayers anonymous = _model(objectSource('1 1 1 1 0 0 0 79 128 255 Lb\n${movementPath(10)}\n${objectDictionary(identifier: 'child')}\nLB', setup: ''));
    check(anonymous.remove(layers: anonymous.layers).drawing.paths).isEmpty();
  });

  test('refuses missing or opaque reference ownership in setup, body and trailer', () {
    for (final String input in [
      identityLifecycleSource.replaceFirst('%%EndSetup', '/Dictionary : (path_a) /String (Reference) , ;\n%%EndSetup'),
      identityLifecycleSource.replaceFirst('%%EndSetup', '/Document : /Dictionary : (path_a) /String (FutureReference) , ; /Recorded , ;\n%%EndSetup'),
      identityLifecycleSource.replaceFirst('%%EndSetup', '/Reference { <706174685f61> } def\n%%EndSetup'),
      identityLifecycleSource.replaceFirst('%%Trailer', '19 FutureOperator\n%%Trailer'),
      identityLifecycleSource.replaceFirst('%%EOF', '%AI99_Ref: path_a\n%%EOF'),
      identityLifecycleSource.replaceFirst('%%EOF', '%%FutureRef: path_a\n%%EOF'),
      identityLifecycleSource.replaceFirst('(Retained) /String (AIArtName)', '(path_a) /String (UnknownReference)'),
    ]) {
      final AiNativeLayers source = _model(input);
      check(() => source.drawing.removePaths(paths: [source.drawing.paths.first])).throws<UnsupportedError>();
      check(() => source.drawing.removeGroups(groups: source.drawing.groups)).throws<UnsupportedError>();
      check(() => source.remove(layers: [source.layers.first], discardViewState: true)).throws<UnsupportedError>();
      check(latin1.decode(source.drawing.records.program.bytes)).equals(input);
    }
  });

  test('refuses duplicate selected identities across artwork and layer namespaces', () {
    for (final String repeated in ['path_b', 'B', 'group_child']) {
      final String input = identityLifecycleSource.replaceFirst('(path_a) ;', '($repeated) ;');
      final AiNativeLayers source = _model(input);
      check(() => source.drawing.removePaths(paths: [source.drawing.paths.first])).throws<UnsupportedError>();
      check(() => source.remove(layers: [source.layers.first], discardViewState: true)).throws<UnsupportedError>();
    }
    final AiNativeLayers source = _model(identityLifecycleSource.replaceFirst('(path_child) ;', '(group_child) ;'));
    check(() => source.drawing.removeGroups(groups: source.drawing.groups)).throws<UnsupportedError>();
  });

  test('keeps unidentified deletion local even when unrelated reference owners remain', () {
    final AiNativeLayers source = _model(identityLifecycleSource.replaceFirst('%%EndSetup', '/Dictionary : (path_a) /String (UnknownReference) , ;\n%%EndSetup'));
    final AiNativeDrawing result = source.drawing.removePaths(paths: [source.drawing.paths.last]);
    check(result.paths).length.equals(3);
    check(latin1.decode(result.records.program.bytes)).contains('(path_a) /String (UnknownReference)');
    check(latin1.decode(result.records.program.bytes).contains('(Retained)')).isFalse();
  });

  test('bounds aggregate escaped IDs across layer and artwork copies', () {
    final AiNativeLayers source = _model(identityLifecycleSource);
    final int budget = source.drawing.records.program.bytes.length;
    final AiNativeLayers limited = _model(identityLifecycleSource, limits: AiNativeLimits(maxDecodedBytes: budget));
    final Map<AiNativeLayer, List<int>> layerIds = layerCopyIdentifiers(limited);
    layerIds[limited.layers.first] = List.filled(budget ~/ 5, 65);
    final Map<AiNativeItem, List<int>> artworkIds = artworkCopyIdentifiers(limited);
    artworkIds[limited.drawing.paths.first] = List.filled(budget ~/ 5, 66);
    check(() => limited.duplicate(layers: [limited.layers.first], identifiers: layerIds, artworkIdentifiers: artworkIds, discardViewState: true)).throws<AiLimitException>();
    check(() => limited.duplicate(layers: [limited.layers.first], identifiers: layerCopyIdentifiers(limited), artworkIdentifiers: artworkCopyIdentifiers(limited), discardViewState: true))
        .throws<FormatException>();
    check(latin1.decode(limited.drawing.records.program.bytes)).equals(identityLifecycleSource);
    final String projected = identityLifecycleSource.replaceAll(RegExp(r'^%_', multiLine: true), '  ');
    final AiNativeLayers tokens = _model(identityLifecycleSource, limits: AiNativeLimits(maxTokens: AiPostScript.tokenize(latin1.encode(projected)).length + 1));
    check(() => tokens.duplicate(layers: [tokens.layers.first], identifiers: layerCopyIdentifiers(tokens), artworkIdentifiers: artworkCopyIdentifiers(tokens), discardViewState: true))
        .throws<AiLimitException>();
  });
}
