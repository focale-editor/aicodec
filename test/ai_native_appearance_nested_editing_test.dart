import 'dart:convert';

import 'package:aicodec/aicodec.dart';
import 'package:checks/checks.dart';
import 'package:test/test.dart';

import 'ai_native_appearance_editing_test.dart' show appearanceEditedGroup, appearanceEditingModel;
import 'ai_native_appearance_nested_styles_test.dart' show nestedAppearanceOwners, nestedAppearanceSource;
import 'ai_native_appearance_state_test.dart' show appearanceStateFill;

/// Explicit original boundaries separating each nested style from its neighbors.
const String nestedStyleReset = '%_0 A 0 Xw 1 Ap 0 D 0 XR 0 O 0 R 0 g 0 G 0 J 0 j 1 w 10 M [] 0 d 0 1 0 0 0 Xy';

/// Keeps two complete group owners with optional inner consumers and scalar resets.
String nestedStyleSource({bool compound = false, bool simple = false, bool localConsumer = false, bool reset = false}) {
  String source = nestedAppearanceSource(compound: compound, simple: simple);
  if (localConsumer) {
    final String definition =
        '''/KnownStyle : (Child) /Name ,
/ActiveStyle : /CompoundFilter : (Chain Style Filter) 0 0 /Filter , 1 /Visible ,
${appearanceStateFill()}
; /Execution ; /Def ;
''';
    source = source
        .replaceRange(source.indexOf('/KnownStyle : (Child)'), source.indexOf('%%EndSetup'), definition)
        .replaceFirst('%_20 0 m 30 0 L 30 10 L 20 0 L n', '%_20 0 m 30 0 L 30 10 L 20 0 L f');
  }
  if (reset) {
    for (final int mode in [0, 1]) {
      source = source.replaceAll('%_$mode (Child) XW', '%_$mode (Child) XW\n$nestedStyleReset');
    }
  }
  return source;
}

/// Supplies one entire printing owner for distinct selected child applications.
AiNativeAppearanceReplacement nestedStyleReplacement(AiNativeAppearances model, int owner, {List<int> children = const [0], bool outer = false}) {
  final AiNativeAppearanceArtwork artwork = model.artworkFor(use: nestedAppearanceOwners(model)[owner]);
  return AiNativeAppearanceReplacement(
    artwork: artwork,
    uses: [if (outer) artwork.use, for (final int child in children) artwork.nestedUses[child]],
    bytes: latin1.encode(appearanceEditedGroup),
    bounds: AiBoundingBox(left: -20, bottom: -30, right: 120, top: 140),
  );
}

/// Changes the explicit first fill without flattening the selected child style.
List<AiNativePaintChange> nestedStylePaints(AiNativeAppearance style) {
  final AiNativePaintStyle paint = style.simplePaint ?? style.parts.firstWhere((part) => part.kind == .fill).paints.single.style;
  final AiNativePaintAssignment assignment = paint.assignments.singleWhere((assignment) => assignment.parameter == .fillColor);
  return [
    AiNativePaintChange(assignment: assignment, values: assignment.numbers!.length == 1 ? [0.8] : [0.7, 0.6, 0.5]),
  ];
}

/// Edits explicit nested uses with one host replacement per enclosing group.
AiNativeAppearances nestedStyleEdit(AiNativeAppearances model, {bool shared = false, bool both = false, int child = 0}) {
  final AiNativeAppearanceArtwork owner = model.artworkFor(use: nestedAppearanceOwners(model).first);
  final AiNativeAppearance style = model.resolve(use: owner.nestedUses[child])!;
  final List<AiNativeAppearanceReplacement> artwork = [
    nestedStyleReplacement(model, 0, children: shared || both ? [0, 1] : [child]),
    if (shared) nestedStyleReplacement(model, 1, children: [0, 1]),
  ];
  return shared
      ? model.updateShared(appearance: style, paints: nestedStylePaints(style), artwork: artwork)
      : model.updateSelected(appearance: style, paints: nestedStylePaints(style), artwork: artwork, nameBytes: latin1.encode('Selected child'));
}

/// Returns complete source ranges for exact snapshot preservation assertions.
List<int> _bytes(AiNativeAppearances model, AiNativeItem owner) => model.structure.drawing.records.program.bytes.sublist(owner.start, owner.end);

/// Covers native child selection, enclosing printing coverage and local dependencies.
void main() {
  test('binds each nested use to its exact native path or group', () {
    final AiNativeAppearances model = appearanceEditingModel(source: nestedStyleSource());
    final AiNativeAppearanceArtwork artwork = model.artworkFor(use: nestedAppearanceOwners(model).first);
    check(artwork.authoringFor(use: artwork.use)).identicalTo(artwork.authoring);
    check(artwork.authoringFor(use: artwork.nestedUses.first)).isA<AiNativePath>();
    check(artwork.authoringFor(use: artwork.nestedUses.last)).isA<AiNativeGroup>();
    check(() => artwork.authoringFor(use: nestedAppearanceOwners(model).last)).throws<ArgumentError>();
  });

  test('isolates a mode-zero path or mode-one group while retaining outer styles and neighbors', () {
    for (final int child in [0, 1]) {
      final AiNativeAppearances before = appearanceEditingModel(source: nestedStyleSource());
      final AiNativeAppearances after = nestedStyleEdit(before, child: child);
      final AiNativeAppearanceArtwork original = before.artworkFor(use: nestedAppearanceOwners(before).first);
      final AiNativeAppearanceArtwork changed = after.artworkFor(use: nestedAppearanceOwners(after).first);
      check(after.styles).length.equals(3);
      check(after.resolve(use: changed.use)).identicalTo(after.styles.first);
      check(after.resolve(use: changed.nestedUses[child])).identicalTo(after.styles.last);
      check(after.resolve(use: changed.nestedUses[1 - child])).identicalTo(after.styles[1]);
      for (final int index in [0, 1]) {
        check(_bytes(after, after.styles[index].resource.definition.source as AiNativeContainer)).deepEquals(_bytes(before, before.styles[index].resource.definition.source as AiNativeContainer));
      }
      check(_bytes(after, changed.authoringFor(use: changed.nestedUses[child]))).deepEquals(_bytes(before, original.authoringFor(use: original.nestedUses[child])));
      final AiNativeAppearanceArtwork oldNeighbor = before.artworkFor(use: nestedAppearanceOwners(before).last);
      final AiNativeAppearanceArtwork newNeighbor = after.artworkFor(use: nestedAppearanceOwners(after).last);
      check(after.structure.drawing.records.program.bytes.sublist(newNeighbor.start, newNeighbor.end))
          .deepEquals(before.structure.drawing.records.program.bytes.sublist(oldNeighbor.start, oldNeighbor.end));
    }
  });

  test('coalesces selected child applications and covers every shared group once', () {
    for (final bool compound in [false, true]) {
      for (final bool simple in [false, true]) {
        final AiNativeAppearances before = appearanceEditingModel(
          source: nestedStyleSource(compound: compound, simple: simple),
        );
        final AiNativeAppearances selected = nestedStyleEdit(before, both: true);
        final AiNativeAppearances shared = nestedStyleEdit(before, shared: true);
        check(selected.styles.last.uses).length.equals(2);
        check(shared.styles).length.equals(2);
        check(shared.styles[1].uses).length.equals(4);
        check(shared.uses.map((use) => latin1.decode(use.nameBytes))).deepEquals(before.uses.map((use) => latin1.decode(use.nameBytes)));
        check(_bytes(shared, shared.styles.first.resource.definition.source as AiNativeContainer)).deepEquals(_bytes(before, before.styles.first.resource.definition.source as AiNativeContainer));
      }
    }
  });

  test('restores explicit native state immediately after a selected child before its sibling consumes it', () {
    final AiNativeAppearances before = appearanceEditingModel(source: nestedStyleSource(localConsumer: true));
    final AiNativeAppearances after = nestedStyleEdit(before);
    final AiNativeAppearanceArtwork artwork = after.artworkFor(use: nestedAppearanceOwners(after).first);
    final String text = latin1.decode(after.structure.drawing.records.program.bytes);
    check(text.substring(artwork.nestedUses.first.instruction.end)).startsWith('\n%_0.1 0.2 0.3 Xa\n');
    check(_bytes(after, artwork.authoringFor(use: artwork.nestedUses.last))).deepEquals(
      _bytes(before, before.artworkFor(use: nestedAppearanceOwners(before).first).authoringFor(use: before.uses[1])),
    );
    check(artwork.group!.paths.last.paint.operator).equals('f');
    check(text).not((value) => value.contains('\n0.1 0.2 0.3 Xa\n'));
  });

  test('rejects unprovable changes consumed inside the same supplied owner', () {
    final String text = nestedStyleSource().replaceFirst('%_20 0 m 30 0 L 30 10 L 20 0 L n', '%_20 0 m 30 0 L 30 10 L 20 0 L f');
    final AiNativeAppearances before = appearanceEditingModel(source: text);
    check(() => nestedStyleEdit(before)).throws<UnsupportedError>();
    check(latin1.decode(before.structure.drawing.records.program.bytes)).equals(text);
    check(() => nestedStyleEdit(appearanceEditingModel(source: text.replaceFirst('%_1 Ae', '%_0 g\n%_1 Ae')))).returnsNormally();
  });

  test('shares the native part lifecycle with child owners while retaining explicit source boundaries', () {
    final AiNativeAppearances before = appearanceEditingModel(source: nestedStyleSource(reset: true));
    final AiNativeAppearance child = before.styles[1];
    final AiNativeAppearancePart stack = child.parts[1];
    final AiNativeAppearances after = before.updateSelected(
      appearance: child,
      parts: [
        AiNativeAppearancePartChange(
          part: stack,
          children: [
            AiNativeAppearanceChild.create(
              definition: AiNativeAppearancePartDefinition(
                kind: .fill,
                colors: [
                  AiColor(space: .rgb, channels: [0, 1, 1]),
                ],
              ),
            ),
            for (final int index in stack.childIndices) AiNativeAppearanceChild.retain(part: child.parts[index]),
          ],
        ),
      ],
      artwork: [nestedStyleReplacement(before, 0)],
      nameBytes: latin1.encode('Child with added fill'),
    );
    check(after.styles.last.parts).length.equals(child.parts.length + 1);
    check(after.styles.last.uses).length.equals(1);
    check(after.styles[1].parts).length.equals(child.parts.length);
    check(latin1.decode(after.structure.drawing.records.program.bytes).split(nestedStyleReset)).length.equals(5);
  });

  test('covers outer and child uses of one shared definition without losing either selection', () {
    final AiNativeAppearances before = appearanceEditingModel(source: nestedStyleSource(reset: true).replaceAll('%_0 (Child) XW', '%_0 (Shared) XW'));
    final AiNativeAppearances after = before.updateShared(
      appearance: before.styles.first,
      paints: nestedStylePaints(before.styles.first),
      artwork: [
        for (final int index in [0, 1]) nestedStyleReplacement(before, index, outer: true),
      ],
    );
    check(after.styles.first.uses).length.equals(4);
    check(after.styles[1].uses).length.equals(2);
  });

  test('requires nonempty immutable owned selections and distinct printing replacements', () {
    final AiNativeAppearances model = appearanceEditingModel(source: nestedStyleSource());
    final AiNativeAppearanceArtwork owner = model.artworkFor(use: nestedAppearanceOwners(model).first);
    final List<AiNativeResourceUse> uses = [owner.nestedUses.first];
    final AiNativeAppearanceReplacement replacement = AiNativeAppearanceReplacement(
      artwork: owner,
      uses: uses,
      bytes: latin1.encode(appearanceEditedGroup),
      bounds: AiBoundingBox(left: 0, bottom: 0, right: 100, top: 100),
    );
    uses.clear();
    check(replacement.uses).length.equals(1);
    check(replacement.uses.clear).throws<UnsupportedError>();
    for (final List<AiNativeResourceUse> invalid in [
      [],
      [owner.nestedUses.first, owner.nestedUses.first],
      [nestedAppearanceOwners(model).last],
    ]) {
      check(() => AiNativeAppearanceReplacement(artwork: owner, uses: invalid, bytes: [], bounds: replacement.bounds)).throws<ArgumentError>();
    }
    check(() => model.updateShared(appearance: model.styles[1], paints: nestedStylePaints(model.styles[1]), artwork: [replacement])).throws<UnsupportedError>();
    check(
      () => model.updateSelected(
        appearance: model.styles[1],
        paints: nestedStylePaints(model.styles[1]),
        artwork: [
          replacement,
          nestedStyleReplacement(model, 0, children: [1]),
        ],
        nameBytes: [65],
      ),
    ).throws<ArgumentError>();
    check(() => model.updateSelected(appearance: model.styles[1], paints: nestedStylePaints(model.styles[1]), artwork: [nestedStyleReplacement(model, 0, outer: true)], nameBytes: [65]))
        .throws<UnsupportedError>();
  });

  test('rejects stale nested selections and bounds the combined serialized transaction', () {
    final AiNativeAppearances before = appearanceEditingModel(source: nestedStyleSource());
    final AiNativeAppearanceReplacement stale = nestedStyleReplacement(before, 0);
    final AiNativeAppearances after = nestedStyleEdit(before);
    check(() => after.updateSelected(appearance: after.styles.last, paints: nestedStylePaints(after.styles.last), artwork: [stale], nameBytes: [66])).throws<ArgumentError>();
    final AiNativeAppearances bounded = appearanceEditingModel(
      source: nestedStyleSource(),
      limits: AiNativeLimits(maxDecodedBytes: after.structure.drawing.records.program.bytes.length - 1),
    );
    check(() => nestedStyleEdit(bounded)).throws<FormatException>();
  });
}
