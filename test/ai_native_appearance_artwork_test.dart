import 'dart:convert';

import 'package:aicodec/aicodec.dart';
import 'package:checks/checks.dart';
import 'package:test/test.dart';

import 'ai_native_appearance_editing_test.dart' show appearanceAssignment, appearanceEditedGroup, appearanceEditingModel, appearanceEditingSource, appearancePrinting;

/// Declares every incoming scalar separately from the host-supplied group.
const String appearanceArtworkState = '0 A 0 Xw 1 Ap 0 D 0 XR 0 O 0 R 0 g 0 G 0 J 0 j 1 w 10 M []0 d 0 1 0 0 0 Xy';

/// A CC appearance pair without fabricated live-shape parameters or dictionaries.
String appearanceArtworkPair({bool counted = false, bool metadata = false}) =>
    '''
$appearanceArtworkState
0 Ae
u
${counted ? '3 As' : ''}
0 0 0 1 k
0 0 m 10 0 L 10 10 L 0 0 L f
U
${metadata ? '%_/ArtDictionary : (Printing) /String (AIArtName) , ;' : ''}
0 J 1 w
0 0 Xd
6 () XW
%_${counted ? '3 As ' : ''}0 D
%_0 0 m 10 0 L 10 10 L 0 0 L n
${metadata ? '%_/ArtDictionary : /XMLUID : (author) ; (AI10_ArtUID) , (Native) /String (AIArtName) , (0.5) /String (BBAccumRotation) , ;' : ''}
1 (Shared) XW
''';

/// Keeps real style syntax with two ordinary appearance users in one body.
String appearanceArtworkSource({bool counted = false, bool metadata = false}) {
  final String setup = appearanceEditingSource().split('%%EndSetup').first;
  return '$setup%%EndSetup\n${appearanceArtworkPair(counted: counted, metadata: metadata)}${appearanceArtworkPair(counted: counted)}\n%%Trailer\n%%EOF\n';
}

/// Supplies one explicit derived group without changing native geometry.
AiNativeAppearanceReplacement appearanceArtworkReplacement(AiNativeAppearances model, int index, {String bytes = appearanceEditedGroup}) => AiNativeAppearanceReplacement(
  artwork: model.artworkFor(use: model.uses[index]),
  bytes: latin1.encode(bytes),
  bounds: AiBoundingBox(left: -20, bottom: -30, right: 120, top: 140),
);

/// Changes one existing process fill against exact snapshot handles.
List<AiNativePaintChange> _changes(AiNativeAppearances model) => [
  AiNativePaintChange(assignment: appearanceAssignment(model.styles.first, 2, .fillColor), values: [0.7, 0.6, 0.5]),
];

/// Selects one ordinary user while leaving the shared source definition intact.
AiNativeAppearances _selected(AiNativeAppearances model, {List<AiNativeAppearanceReplacement>? artwork}) => model.updateSelected(
  appearance: model.styles.first,
  paints: _changes(model),
  artwork: artwork ?? [appearanceArtworkReplacement(model, 0)],
  nameBytes: latin1.encode('Selected'),
);

/// Compares complete original native owners rather than normalized geometry.
List<int> _bytes(AiNativeAppearances model, int start, int end) => model.structure.drawing.records.program.bytes.sublist(start, end);

/// Covers shared and selected ordinary users, metadata and dependency boundaries.
void main() {
  test('binds and edits ordinary appearance pairs without live-shape metadata', () {
    final AiNativeAppearances model = appearanceEditingModel(source: appearanceArtworkSource());
    final AiNativeAppearanceArtwork before = model.artworkFor(use: model.uses.first);
    check(before.liveShape).isNull();
    check(before.dictionary).isNull();
    check(before.printingDictionary).isNull();
    check(before.path!.isPrivate).isTrue();
    final AiNativeAppearances changed = _selected(model);
    final AiNativeAppearanceArtwork after = changed.artworkFor(use: changed.uses.first);
    check(changed.structure.drawing.liveShapes).isEmpty();
    check(changed.styles).length.equals(2);
    check(changed.resolve(use: changed.uses.first)).identicalTo(changed.styles.last);
    check(changed.resolve(use: changed.uses.last)).identicalTo(changed.styles.first);
    check(_bytes(changed, after.path!.start, after.path!.end)).deepEquals(_bytes(model, before.path!.start, before.path!.end));
    check(_bytes(changed, after.printingGroup.start, after.printingGroup.end)).deepEquals(latin1.encode(appearanceEditedGroup));
    final AiNativeAppearanceArtwork oldNeighbor = model.artworkFor(use: model.uses.last);
    final AiNativeAppearanceArtwork newNeighbor = changed.artworkFor(use: changed.uses.last);
    check(_bytes(changed, newNeighbor.start, newNeighbor.end)).deepEquals(_bytes(model, oldNeighbor.start, oldNeighbor.end));
    check(latin1.decode(model.structure.drawing.records.program.bytes)).equals(appearanceArtworkSource());
  });

  test('retains optional labels, identities, rotations and exact metadata bytes', () {
    final AiNativeAppearances model = appearanceEditingModel(source: appearanceArtworkSource(metadata: true));
    final AiNativeAppearances changed = _selected(model);
    final AiNativeAppearanceArtwork before = model.artworkFor(use: model.uses.first);
    final AiNativeAppearanceArtwork after = changed.artworkFor(use: changed.uses.first);
    check(_bytes(changed, after.dictionary!.start, after.dictionary!.end)).deepEquals(_bytes(model, before.dictionary!.start, before.dictionary!.end));
    check(_bytes(changed, after.printingDictionary!.start, after.printingDictionary!.end)).deepEquals(_bytes(model, before.printingDictionary!.start, before.printingDictionary!.end));
    check(changed.structure.identifiers.map((identifier) => latin1.decode(identifier.bytes))).deepEquals(['author']);
  });

  test('requires every shared owner, including mixed live-shape and ordinary users', () {
    final String live = appearanceEditingSource();
    final AiNativeAppearances model = appearanceEditingModel(source: live.replaceFirst('%%Trailer', '${appearanceArtworkPair()}\n%%Trailer'));
    check(model.uses).length.equals(3);
    check(
      () => model.updateShared(appearance: model.styles.first, paints: _changes(model), printing: [appearancePrinting(model, 0), appearancePrinting(model, 1)]),
    ).throws<UnsupportedError>();
    final AiNativeAppearances changed = model.updateShared(
      appearance: model.styles.first,
      paints: _changes(model),
      printing: [appearancePrinting(model, 0), appearancePrinting(model, 1)],
      artwork: [appearanceArtworkReplacement(model, 2)],
    );
    check(changed.styles).length.equals(1);
    check(changed.uses).length.equals(3);
    check(changed.structure.drawing.liveShapes.every((shape) => shape.isBound)).isTrue();
    for (final AiNativeResourceUse use in changed.uses) {
      final AiNativeAppearanceArtwork owner = changed.artworkFor(use: use);
      check(_bytes(changed, owner.printingGroup.start, owner.printingGroup.end)).deepEquals(latin1.encode(appearanceEditedGroup));
    }
  });

  test('checks following ordinary users before consuming changed inherited state', () {
    final String source = appearanceArtworkSource();
    final String affected = source
        .replaceRange(source.lastIndexOf(appearanceArtworkState), source.lastIndexOf(appearanceArtworkState) + appearanceArtworkState.length, '')
        .replaceAll('0 0 0 1 k\n', '');
    final AiNativeAppearances model = appearanceEditingModel(source: affected);
    const String group = 'u\n0 0 m 10 0 L 10 10 L f\nU';
    check(() => _selected(model, artwork: [appearanceArtworkReplacement(model, 0, bytes: group)])).throws<UnsupportedError>();
    check(latin1.decode(model.structure.drawing.records.program.bytes)).equals(affected);
  });

  test('qualifies following independent contours after an ordinary appearance boundary', () {
    final String source = appearanceArtworkSource().replaceFirst('1 (Shared) XW', '1 (Shared) XW\n0 0 0 1 k\n20 0 m 30 0 L 30 10 L f');
    final AiNativeAppearances model = appearanceEditingModel(source: source);
    final AiNativeAppearances changed = _selected(model);
    check(changed.structure.drawing.paths).length.equals(model.structure.drawing.paths.length);
    check(latin1.decode(changed.structure.drawing.records.program.bytes)).contains('20 0 m 30 0 L 30 10 L f');
    final AiNativeAppearances opaque = appearanceEditingModel(source: source.replaceFirst('1 (Shared) XW', '1 (Shared) XW\n1 FutureState'));
    check(() => _selected(opaque)).throws<UnsupportedError>();
    final AiNativeAppearances shared = model.updateShared(
      appearance: model.styles.first,
      paints: _changes(model),
      artwork: [appearanceArtworkReplacement(model, 0), appearanceArtworkReplacement(model, 1)],
    );
    check(shared.styles).length.equals(1);
  });

  test('rejects stale, duplicate, foreign and mixed duplicate owner selections', () {
    final AiNativeAppearances model = appearanceEditingModel(source: appearanceArtworkSource());
    final AiNativeAppearanceReplacement first = appearanceArtworkReplacement(model, 0);
    check(() => _selected(model, artwork: [first, appearanceArtworkReplacement(model, 0)])).throws<ArgumentError>();
    check(() => _selected(appearanceEditingModel(source: appearanceArtworkSource()), artwork: [first])).throws<ArgumentError>();
    check(() => _selected(_selected(model), artwork: [first])).throws<ArgumentError>();
    check(() => model.artworkFor(use: appearanceEditingModel(source: appearanceArtworkSource()).uses.first)).throws<ArgumentError>();
    final AiNativeAppearances live = appearanceEditingModel();
    check(
      () => live.updateSelected(
        appearance: live.styles.first,
        paints: _changes(live),
        printing: [appearancePrinting(live, 0)],
        artwork: [appearanceArtworkReplacement(live, 0)],
        nameBytes: [65],
      ),
    ).throws<ArgumentError>();
  });

  test('retains counted and uncounted producer conventions with exact private paths', () {
    final AiNativeAppearances model = appearanceEditingModel(source: appearanceArtworkSource(counted: true));
    check(() => _selected(model)).throws<UnsupportedError>();
    final AiNativeAppearances changed = _selected(
      model,
      artwork: [appearanceArtworkReplacement(model, 0, bytes: appearanceEditedGroup.replaceFirst('0 0 m 10 0 L 10 10 L f', '3 As\n0 0 m 10 0 L 10 10 L 0 0 L f'))],
    );
    check(changed.uses).length.equals(2);
  });

  test('rejects unresolved metadata, nested owners, boundary names and private paint', () {
    final String source = appearanceArtworkSource();
    for (final String invalid in [
      source.replaceFirst('1 (Shared) XW', '%_/ArtDictionary : 1 /Int (Future) , ;\n1 (Shared) XW'),
      source.replaceFirst('1 (Shared) XW', '%_/ArtDictionary : (NaN) /String (BBAccumRotation) , ;\n1 (Shared) XW'),
      source.replaceFirst('6 () XW', '6 (Unknown) XW'),
      source.replaceFirst('1 (Shared) XW', '0 (Shared) XW'),
      source.replaceFirst('6 () XW', '%_6 () XW'),
      source.replaceFirst('0 0 L n', '0 0 L f'),
      source.replaceFirst('6 () XW', 'u\n6 () XW').replaceFirst('1 (Shared) XW', '1 (Shared) XW\nU'),
      source.replaceFirst('%_0 D', '%AI99_Unknown\n%_0 D'),
      source.replaceFirst('0 0 m 10 0 L 10 10 L 0 0 L n', '0 0 m 1 g 10 0 L 10 10 L 0 0 L n'),
      source.replaceFirst('6 () XW', '6 () XW\n%_9 As'),
    ]) {
      final AiNativeAppearances model = appearanceEditingModel(source: invalid);
      check(() => model.artworkFor(use: model.uses.first)).throws<UnsupportedError>();
      check(latin1.decode(model.structure.drawing.records.program.bytes)).equals(invalid);
    }
  });

  test('rejects complete conditional pairs and split version boundaries', () {
    for (final String body in [
      '%AI17_Begin_Content_if_version_gt:17 4\n${appearanceArtworkPair()}%AI17_End_Versioned_Content\n',
      appearanceArtworkPair().replaceFirst('6 () XW', '%AI17_Begin_Content_if_version_gt:17 4\n6 () XW').replaceFirst('1 (Shared) XW', '1 (Shared) XW\n%AI17_End_Versioned_Content'),
    ]) {
      final AiNativeAppearances model = appearanceEditingModel(source: '${appearanceEditingSource().split('%%EndSetup').first}%%EndSetup\n$body\n%%Trailer\n%%EOF\n');
      check(() => model.artworkFor(use: model.uses.first)).throws<UnsupportedError>();
    }
  });

  test('freezes supplied bytes and validates printing state, bytes, bounds and limits', () {
    final AiNativeAppearances model = appearanceEditingModel(source: appearanceArtworkSource());
    final List<int> bytes = latin1.encode(appearanceEditedGroup);
    final AiNativeAppearanceReplacement replacement = AiNativeAppearanceReplacement(
      artwork: model.artworkFor(use: model.uses.first),
      bytes: bytes,
      bounds: AiBoundingBox(left: 0, bottom: 0, right: 10, top: 10),
    );
    bytes[0] = 0;
    check(replacement.bytes.first).equals(117);
    check(() => replacement.bytes[0] = 0).throws<UnsupportedError>();
    check(() => AiNativeAppearanceReplacement(artwork: replacement.artwork, bytes: [256], bounds: replacement.bounds)).throws<ArgumentError>();
    check(() => AiNativeAppearanceReplacement(artwork: replacement.artwork, bytes: [], bounds: AiBoundingBox(left: 0, bottom: 0, right: 1e16, top: 10))).throws<ArgumentError>();
    check(() => _selected(model, artwork: [appearanceArtworkReplacement(model, 0, bytes: appearanceEditedGroup.replaceFirst('0 0 0 1 k', '0 g'))])).throws<UnsupportedError>();
    final AiNativeAppearances bounded = appearanceEditingModel(source: appearanceArtworkSource(), limits: const AiNativeLimits(maxDecodedBytes: 10000));
    check(() => _selected(bounded, artwork: [appearanceArtworkReplacement(bounded, 0, bytes: 'u\n${' ' * 11000}U')])).throws<AiLimitException>();
  });
}
