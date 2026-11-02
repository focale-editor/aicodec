import 'dart:convert';

import 'package:aicodec/aicodec.dart';
import 'package:checks/checks.dart';
import 'package:test/test.dart';

import 'ai_native_subtree_removal_test.dart' show subtreeRemovalSource;

/// Opens immutable native data under optional original parser limits.
AiNativeDrawing _drawing(String text, {AiNativeLimits limits = const AiNativeLimits()}) => AiNativeDrawing.decode(
  records: AiNativeRecords.decode(
    program: AiProgram.decode(bytes: latin1.encode(text), limits: limits),
  ),
);

/// Selects ordinary parents without confusing them with printable expansions.
List<AiNativeGroup> subtreeCopyGroups(AiNativeDrawing drawing) =>
    drawing.groups.where((group) => group.opening.operator == 'u' && group.paths.any((path) => path.isPrivate)).toList()..sort((first, second) => first.start.compareTo(second.start));

/// Supplies fresh ordinary-object and saved-pair identities using exact handles.
Map<AiNativeItem, List<int>> subtreeArtworkIdentifiers(AiNativeDrawing drawing, List<AiNativeItem> roots, {String prefix = 'copy_'}) {
  final AiNativeObjects objects = AiNativeObjects.decode(drawing: drawing);
  final Set<AiNativeContainer> paired = {
    for (final AiLiveShape shape in drawing.liveShapes.where((shape) => shape.appearanceGroup != null && roots.any((root) => root.start <= shape.start && root.end >= shape.end))) ...[
      shape.dictionary,
      ?shape.appearanceDictionary,
      ...shape.alternativeDictionaries,
    ],
  };
  return {
    for (final AiNativeObject object in objects.objects)
      if (object.identifier != null && !paired.contains(object.dictionary) && roots.any((root) => object.source.start >= root.start && object.source.end <= root.end))
        object.source: latin1.encode('$prefix${latin1.decode(object.identifier!.bytes)}'),
    for (final AiNativeObjectIdentifier identifier in objects.structure.identifiers)
      if (paired.contains(identifier.field.owner.source)) identifier.field.owner.source as AiNativeContainer: latin1.encode('$prefix${latin1.decode(identifier.bytes)}'),
  };
}

/// Reads decoded names across all native metadata owners in source order.
List<String> _identities(AiNativeDrawing drawing) => AiNativeStructure.decode(drawing: drawing).identifiers.map((identifier) => latin1.decode(identifier.bytes)).toList();

/// Supplies a child stroke whose native width comes only from the preceding style.
String subtreeStyleCopySource({bool hidden = false}) => subtreeRemovalSource()
    .replaceFirst('1 w ', '')
    .replaceFirst('0 0 0 1 k /Def', '2 w 0 0 0 1 k /Def')
    .replaceFirst('1 /Visible', '${hidden ? 0 : 1} /Visible')
    .replaceFirst('70 0 m 71 1 L f', '70 0 m 71 1 L S');

/// Copies an exact group selection with fresh identities for all descendants.
AiNativeDrawing _copy(AiNativeDrawing source, List<AiNativeGroup> groups) => source.duplicateGroups(groups: groups, identifiers: subtreeArtworkIdentifiers(source, groups));

/// Covers complete copies, separate state, identity policies and bounded failures.
void main() {
  test('copies paired and ordinary descendants with fresh identities in both alternatives', () {
    final String text = subtreeRemovalSource();
    final AiNativeDrawing source = _drawing(text);
    final AiNativeDrawing result = _copy(source, [subtreeCopyGroups(source).first]);
    check(result.liveShapes).length.equals(3);
    check(result.paths).length.equals(14);
    check(result.groups).length.equals(11);
    check(_identities(result)).deepEquals(['A', 'author', 'older', 'inner', 'outer', 'copy_author', 'copy_older', 'copy_inner', 'copy_outer', 'B', 'B1']);
    check(result.liveShapes[1].parameters.entries.map((field) => field.number)).deepEquals(source.liveShapes.first.parameters.entries.map((field) => field.number));
    check(result.liveShapes[1].style).identicalTo(result.liveShapes.first.style);
    check(result.liveShapes[1].alternativeDictionaries).length.equals(1);
    check(latin1.decode(source.records.program.bytes)).equals(text);
  });

  test('copies nested layers with separate names, layer IDs and paired dictionary IDs', () {
    final AiNativeDrawing source = _drawing(subtreeRemovalSource());
    final AiNativeLayers layers = AiNativeLayers.decode(drawing: source);
    final AiNativeLayers result = layers.duplicate(
      layers: [layers.layers.first],
      identifiers: {layers.layers.first: latin1.encode('copy_A')},
      names: {layers.layers.first: latin1.encode('Copied A')},
      artworkIdentifiers: subtreeArtworkIdentifiers(source, [layers.layers.first]),
    );
    check(result.layers.map((layer) => latin1.decode(layer.nameBytes!))).deepEquals(['A', 'Copied A', 'B', 'B1']);
    check(result.rootCount).equals(3);
    check(result.drawing.liveShapes).length.equals(3);
    check(_identities(result.drawing)).contains('copy_author');
    check(_identities(result.drawing)).contains('copy_older');
    check(result.layers[1].source.begin.numbers!).deepEquals(layers.layers.first.source.begin.numbers!);
  });

  test('copies disjoint groups atomically in source order regardless of request order', () {
    final AiNativeDrawing source = _drawing(subtreeRemovalSource());
    final List<AiNativeGroup> groups = [subtreeCopyGroups(source).first, subtreeCopyGroups(source).last];
    final AiNativeDrawing first = _copy(source, groups);
    final AiNativeDrawing second = _copy(source, groups.reversed.toList());
    check(first.records.program.bytes).deepEquals(second.records.program.bytes);
    check(first.liveShapes).length.equals(4);
    check(first.paths).length.equals(18);
  });

  test('restores distinct inherited public and private flags before the whole copy', () {
    final String text = subtreeRemovalSource().replaceFirst('0 D 0 XR', '0 XR').replaceFirst('0 A 0 Xw', '0 D\n%_1 D\n0 A 0 Xw').replaceFirst('*u', '1 D\n*u');
    final AiNativeDrawing source = _drawing(text);
    final AiNativeGroup group = subtreeCopyGroups(source).first;
    final AiNativeDrawing result = _copy(source, [group]);
    final AiNativeGroup copied = subtreeCopyGroups(result)[2];
    final AiNativeObject owner = AiNativeObjects.decode(drawing: source).forSource(group);
    final String prefix = latin1.decode(result.records.program.bytes.sublist(owner.end, AiNativeObjects.decode(drawing: result).forSource(copied).start));
    check(prefix).contains('0 D');
    check(prefix).contains('%_1 D');
    check(result.liveShapes).length.equals(3);
  });

  test('keeps retained neighbors when a repeated style leaves unknown native paint', () {
    final AiNativeDrawing source = _drawing(subtreeRemovalSource(following: true));
    final AiNativeDrawing result = _copy(source, [subtreeCopyGroups(source).first]);
    check(result.paths.last.geometry.first.numbers!).deepEquals([90.0, 0.0]);
    final AiLiveShape original = source.liveShapes.last;
    final AiLiveShape retained = result.liveShapes.last;
    check(result.records.program.bytes.sublist(retained.start, retained.end)).deepEquals(source.records.program.bytes.sublist(original.start, original.end));
  });

  test('requires dictionary keys for every paired owner including unversioned metadata', () {
    final String text = subtreeRemovalSource().replaceAllMapped(
      RegExp(r'%AI17_Begin_Content_if_version_gt:17 4\n([\s\S]*?)%AI17_Alternate_Content[\s\S]*?%AI17_End_Versioned_Content'),
      (match) => match[1]!,
    );
    final AiNativeDrawing source = _drawing(text);
    final AiNativeGroup group = subtreeCopyGroups(source).first;
    final Map<AiNativeItem, List<int>> identifiers = subtreeArtworkIdentifiers(source, [group]);
    check(identifiers).containsKey(source.liveShapes.first.dictionary);
    check(identifiers).not((value) => value.containsKey(source.liveShapes.first.path!));
    final AiNativeDrawing result = source.duplicateGroups(groups: [group], identifiers: identifiers);
    check(result.liveShapes).length.equals(3);
    check(result.liveShapes[1].alternativeDictionaries).isEmpty();
    check(() => source.duplicateGroups(groups: [group], identifiers: {...identifiers}..remove(source.liveShapes.first.dictionary))).throws<ArgumentError>();
  });

  test('reserves fresh names across ordinary objects, paired alternatives and layers', () {
    final AiNativeDrawing source = _drawing(subtreeRemovalSource());
    final AiNativeGroup group = subtreeCopyGroups(source).first;
    final Map<AiNativeItem, List<int>> identifiers = subtreeArtworkIdentifiers(source, [group]);
    for (final String collision in ['author', 'older', 'A', 'copy_inner']) {
      check(() => source.duplicateGroups(groups: [group], identifiers: {...identifiers, source.liveShapes.first.dictionary: latin1.encode(collision)})).throws<ArgumentError>();
    }
    final AiNativeLayers layers = AiNativeLayers.decode(drawing: source);
    check(
      () => layers.duplicate(layers: [layers.layers.first], identifiers: {layers.layers.first: latin1.encode('copy_author')}, artworkIdentifiers: identifiers),
    ).throws<ArgumentError>();
    check(() => source.duplicateGroups(groups: [group])).throws<ArgumentError>();
    check(() => source.duplicateGroups(groups: [group], identifiers: {...identifiers, source.liveShapes.last.dictionary: latin1.encode('extra')})).throws<ArgumentError>();
  });

  test('rejects repeated saved aliases across native alternatives or ordinary descendants', () {
    for (final String text in [subtreeRemovalSource().replaceFirst('(older)', '(author)'), subtreeRemovalSource().replaceFirst('(inner)', '(author)')]) {
      final AiNativeDrawing source = _drawing(text);
      check(() => _copy(source, [subtreeCopyGroups(source).first])).throws<UnsupportedError>();
      check(latin1.decode(source.records.program.bytes)).equals(text);
    }
  });

  test('rejects unknown inherited flags instead of resetting them to defaults', () {
    final String text = subtreeRemovalSource().replaceFirst('0 D ', '').replaceFirst('*u', '1 D\n*u');
    final AiNativeDrawing source = _drawing(text);
    check(() => _copy(source, [subtreeCopyGroups(source).first])).throws<UnsupportedError>();
    check(latin1.decode(source.records.program.bytes)).equals(text);
  });

  test('uses definite style scalars before later child reads without requiring unknown inputs', () {
    final AiNativeDrawing source = _drawing(subtreeStyleCopySource());
    check(_copy(source, [subtreeCopyGroups(source).first]).liveShapes).length.equals(3);
  });

  test('does not treat hidden style effects as definite assignments for later children', () {
    final AiNativeDrawing source = _drawing(subtreeStyleCopySource(hidden: true));
    check(() => _copy(source, [subtreeCopyGroups(source).first])).throws<UnsupportedError>();
  });

  test('retains unselected opaque data while reserving its saved XML names', () {
    final String text = subtreeRemovalSource().replaceFirst('%%EndSetup', '/Dictionary : /XMLUID : (reserved) ; (Opaque) , ;\n%%EndSetup');
    final AiNativeDrawing source = _drawing(text);
    final AiNativeGroup group = subtreeCopyGroups(source).first;
    final AiNativeDrawing result = _copy(source, [group]);
    check(latin1.decode(result.records.program.bytes)).contains('/Dictionary : /XMLUID : (reserved) ; (Opaque) , ;');
    check(
      () => source.duplicateGroups(
        groups: [group],
        identifiers: {
          ...subtreeArtworkIdentifiers(source, [group]),
          source.liveShapes.first.dictionary: latin1.encode('reserved'),
        },
      ),
    ).throws<ArgumentError>();
  });

  test('rejects partial pairs, unresolved metadata and extra supplied identities', () {
    final AiNativeDrawing source = _drawing(subtreeRemovalSource());
    check(() => source.duplicateGroups(groups: [source.liveShapes.first.appearanceGroup!])).throws<UnsupportedError>();
    for (final String text in [
      subtreeRemovalSource().replaceFirst('1 (Shared) XW', '1 (Missing) XW'),
      subtreeRemovalSource().replaceFirst('70 0 m', '%_17 Future\n70 0 m'),
      subtreeRemovalSource().replaceFirst('70 0 m', '%AI99_Reference: author\n70 0 m'),
    ]) {
      final AiNativeDrawing invalid = _drawing(text);
      check(() => _copy(invalid, [subtreeCopyGroups(invalid).first])).throws<UnsupportedError>();
    }
  });

  test('rejects empty, duplicate, overlapping, foreign and stale group handles', () {
    final AiNativeDrawing source = _drawing(subtreeRemovalSource());
    final List<AiNativeGroup> groups = subtreeCopyGroups(source);
    for (final List<AiNativeGroup> selection in [
      <AiNativeGroup>[],
      [groups.first, groups.first],
      [groups.first, groups[1]],
      [subtreeCopyGroups(_drawing(subtreeRemovalSource())).first],
    ]) {
      check(() => _copy(source, selection)).throws<ArgumentError>();
    }
    final AiNativeDrawing result = _copy(source, [groups.first]);
    check(() => _copy(result, [groups.last])).throws<ArgumentError>();
  });

  test('bounds identities and added state under the original byte and token limits', () {
    final String text = subtreeRemovalSource();
    final AiNativeDrawing source = _drawing(text, limits: AiNativeLimits(maxDecodedBytes: text.length + 20));
    check(() => _copy(source, [subtreeCopyGroups(source).first])).throws<FormatException>();
    check(latin1.decode(source.records.program.bytes)).equals(text);
  });

  test('keeps copies editable without changing original native parameters', () {
    final AiNativeDrawing source = _drawing(subtreeRemovalSource());
    final AiNativeDrawing result = _copy(source, [subtreeCopyGroups(source).first]);
    final AiNativeDrawing changed = result.translateLiveShapes(shapes: [result.liveShapes[1]], deltaX: 2, deltaY: 3);
    check(changed.liveShapes[1].parameters['ai::Rectangle::CenterX']!.number).equals(8002);
    check(changed.liveShapes.first.parameters['ai::Rectangle::CenterX']!.number).equals(8000);
  });

  test('still rejects native transforms under unresolved parent dictionaries', () {
    final String text = subtreeRemovalSource().replaceFirst('/XMLUID : (outer)', '(unknown) /String (ParentAppearance) , /XMLUID : (outer)');
    final AiNativeDrawing source = _drawing(text);
    check(() => source.translateLiveShapes(shapes: [source.liveShapes.first], deltaX: 2, deltaY: 3)).throws<UnsupportedError>();
    check(latin1.decode(source.records.program.bytes)).equals(text);
  });
}
