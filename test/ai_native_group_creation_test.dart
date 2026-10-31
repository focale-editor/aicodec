import 'dart:convert';

import 'package:aikit/aikit.dart';
import 'package:checks/checks.dart';
import 'package:test/test.dart';

import 'ai_native_artwork_movement_test.dart' show movementLayer, movementPath;
import 'ai_native_layer_creation_test.dart' show layerCreationSource, layerDefinition;
import 'ai_native_objects_test.dart' show objectDictionary, objectSource;
import 'ai_native_path_group_movement_test.dart' show mixedPathGroupSource, pathGroupParent;

/// Opens an immutable source under its original parser and output ceilings.
AiNativeDrawing groupCreationDrawing(String source, {AiNativeLimits limits = const AiNativeLimits()}) => AiNativeDrawing.decode(
  records: AiNativeRecords.decode(
    program: AiProgram.decode(bytes: latin1.encode(source), limits: limits),
  ),
);

/// Supplies a visible populated parent and an empty sibling with exact identities.
String get groupCreationSource => objectSource(
  'u\n${movementPath(10)}\nU\n${objectDictionary(identifier: 'Parent')}\nu U\n${objectDictionary(identifier: 'Empty')}\n${movementPath(20)}',
  setup: '',
);

/// Locates the exact new owner independently of shifted source indices.
AiNativeGroup createdGroup(AiNativeDrawing drawing) =>
    AiNativeObjects.decode(drawing: drawing).objects.singleWhere((object) => latin1.decode(object.identifier?.bytes ?? []) == 'Created').source as AiNativeGroup;

/// Requires exactly one insertion and byte-equivalent unrelated source.
void _exact(AiNativeDrawing source, AiNativeDrawing result, int position) {
  final List<int> before = source.records.program.bytes;
  final List<int> after = result.records.program.bytes;
  final int inserted = after.length - before.length;
  check(after.sublist(0, position)).deepEquals(before.sublist(0, position));
  check(after.sublist(position + inserted)).deepEquals(before.sublist(position));
  check(result.paths.length).equals(source.paths.length);
  check(result.groups.length).equals(source.groups.length + 1);
  check(result.records.program.layers.length).equals(source.records.program.layers.length);
  check(result.liveShapes.length).equals(source.liveShapes.length);
}

/// Checks sibling-free grouping, ownership, metadata and atomic refusal.
void main() {
  test('creates the first root group with an explicit name and fresh identity', () {
    final AiNativeDrawing source = groupCreationDrawing(objectSource('', setup: ''));
    final List<int> name = latin1.encode('R\u00e9sum\u00e9 (group)');
    final List<int> identity = latin1.encode('Created');
    final AiNativeDrawing result = source.createGroup(nameBytes: name, identifierBytes: identity);
    name[0] = 0;
    identity[0] = 0;
    final AiNativeGroup group = createdGroup(result);
    final AiNativeObjects objects = AiNativeObjects.decode(drawing: result);
    check(group.children).isEmpty();
    check(objects.forSource(group).names.single.stringBytes!).deepEquals(latin1.encode('R\u00e9sum\u00e9 (group)'));
    check(objects.structure.parentOf(objects.structure.nodeFor(group))).isNull();
    _exact(source, result, source.records.program.bodyEnd);
    final AiNativeDrawing copied = result.duplicateGroups(groups: [group], identifiers: {group: latin1.encode('Copied')});
    final AiNativeDrawing removed = copied.removeGroups(groups: copied.groups);
    check(removed.groups).isEmpty();
    check(removed.createGroup(identifierBytes: latin1.encode('Created')).groups).length.equals(1);
  });

  test('appends last children inside empty and populated ordinary parents', () {
    final AiNativeDrawing source = groupCreationDrawing(groupCreationSource);
    for (final AiNativeGroup parent in source.groups) {
      final AiNativeDrawing result = source.createGroup(parent: parent, identifierBytes: latin1.encode('Created'));
      final AiNativeGroup group = createdGroup(result);
      final AiNativeStructure structure = AiNativeStructure.decode(drawing: result);
      final AiNativeGroup changedParent = structure.parentOf(structure.nodeFor(group))!.source as AiNativeGroup;
      check(changedParent.children.last).identicalTo(group);
      _exact(source, result, parent.closing.start);
    }
  });

  test('creates groups inside freshly authored and hidden layers without changing views', () {
    final AiNativeLayers initial = AiNativeLayers.decode(drawing: groupCreationDrawing(layerCreationSource()));
    final AiNativeLayers fresh = initial.create(definition: layerDefinition());
    final AiNativeDrawing first = fresh.drawing.createGroup(layer: fresh.layers.single.source);
    check(first.groups.single.children).isEmpty();
    _exact(fresh.drawing, first, fresh.layers.single.source.end.start);
    final AiNativeDrawing source = groupCreationDrawing(layerCreationSource(body: movementLayer('Hidden', '', hidden: true), count: 1, views: true));
    final AiNativeDrawing result = source.createGroup(layer: source.records.program.layers.single);
    _exact(source, result, source.records.program.layers.single.end.start);
    final AiNativeLayers after = AiNativeLayers.decode(drawing: result);
    check(after.declaredRootCount).equals(1);
    check(after.viewComments.map((token) => token.lexeme)).deepEquals(AiNativeLayers.decode(drawing: source).viewComments.map((token) => token.lexeme).toList());
  });

  test('retains complete CC siblings, their metadata alternatives and both states', () {
    final AiNativeDrawing source = groupCreationDrawing(mixedPathGroupSource());
    final AiNativeGroup parent = pathGroupParent(source, 'outer_0');
    final AiNativeDrawing result = source.createGroup(parent: parent, identifierBytes: latin1.encode('Created'), inheritParentFlags: true);
    _exact(source, result, parent.closing.start);
    for (final (int, AiLiveShape) entry in source.liveShapes.indexed) {
      final AiLiveShape changed = result.liveShapes[entry.$1];
      check(result.records.program.bytes.sublist(changed.start, changed.end)).deepEquals(source.records.program.bytes.sublist(entry.$2.start, entry.$2.end));
    }
  });

  test('requires explicit inheritance of current unknown or non-neutral flags', () {
    for (final String text in [objectSource('1 A\n%_1 Xw\nu U', setup: ''), objectSource('', setup: '').replaceFirst('0 A 0 Xw', '')]) {
      final AiNativeDrawing source = groupCreationDrawing(text);
      check(source.createGroup).throws<UnsupportedError>();
      final AiNativeDrawing result = source.createGroup(inheritParentFlags: true);
      _exact(source, result, source.records.program.bodyEnd);
    }
  });

  test('retains anonymous owners, escaped names and original line endings', () {
    final AiNativeDrawing source = groupCreationDrawing(objectSource('', setup: '').replaceAll('\n', '\r\n'));
    final AiNativeDrawing anonymous = source.createGroup();
    check(AiNativeObjects.decode(drawing: anonymous).forSource(anonymous.groups.single).dictionary).isNull();
    final AiNativeDrawing named = source.createGroup(nameBytes: [0, 10, 13, 40, 92, 255]);
    check(AiNativeObjects.decode(drawing: named).forSource(named.groups.single).names.single.stringBytes!).deepEquals([0, 10, 13, 40, 92, 255]);
    check(latin1.decode(named.records.program.bytes).replaceAll('\r\n', '')).not((value) => value.contains('\n'));
    _exact(source, named, source.records.program.bodyEnd);
  });

  test('rejects stale, foreign, conflicting and non-authoring parent handles', () {
    final AiNativeDrawing source = groupCreationDrawing(groupCreationSource);
    check(() => source.createGroup(parent: groupCreationDrawing(groupCreationSource).groups.first)).throws<ArgumentError>();
    final AiNativeDrawing changed = source.createGroup();
    check(() => changed.createGroup(parent: source.groups.first)).throws<ArgumentError>();
    final AiNativeDrawing layered = groupCreationDrawing(layerCreationSource(body: movementLayer('Layer', 'u U'), count: 1));
    check(() => layered.createGroup(parent: layered.groups.single, layer: layered.records.program.layers.single)).throws<ArgumentError>();
    check(() => source.createGroup(layer: layered.records.program.layers.single)).throws<ArgumentError>();
    for (final String body in ['*u *U', 'q Q', '%_u\n%_U', 'u U\n${objectDictionary(extra: '(unknown) /String (Future) ,')}']) {
      final AiNativeDrawing unsupported = groupCreationDrawing(objectSource(body));
      check(() => unsupported.createGroup(parent: unsupported.groups.single, inheritParentFlags: true)).throws<UnsupportedError>();
    }
    final AiNativeDrawing paired = groupCreationDrawing(mixedPathGroupSource());
    check(() => paired.createGroup(parent: paired.liveShapes.first.appearanceGroup, inheritParentFlags: true)).throws<UnsupportedError>();
  });

  test('refuses unresolved prefixes, captured identities and exceeded original limits', () {
    final AiNativeDrawing source = groupCreationDrawing(groupCreationSource);
    check(() => source.createGroup(nameBytes: [-1])).throws<ArgumentError>();
    check(() => source.createGroup(identifierBytes: [])).throws<ArgumentError>();
    check(() => source.createGroup(identifierBytes: latin1.encode('Parent'))).throws<ArgumentError>();
    final AiNativeDrawing referenced = groupCreationDrawing(objectSource('', setup: '/Dictionary : /XMLUID : (Captured) ; (Future) , ;'));
    check(() => referenced.createGroup(identifierBytes: latin1.encode('Captured'))).throws<ArgumentError>();
    for (final String body in ['3 As', '1 Ae', '17 FuturePaint', '%AI3_Note: (unowned)']) {
      final AiNativeDrawing unsupported = groupCreationDrawing(objectSource(body, setup: ''));
      check(() => unsupported.createGroup(inheritParentFlags: true)).throws<UnsupportedError>();
    }
    final String text = objectSource('', setup: '');
    final AiNativeDrawing bounded = groupCreationDrawing(text, limits: AiNativeLimits(maxDecodedBytes: text.length));
    check(bounded.createGroup).throws<FormatException>();
    check(latin1.decode(bounded.records.program.bytes)).equals(text);
  });
}
