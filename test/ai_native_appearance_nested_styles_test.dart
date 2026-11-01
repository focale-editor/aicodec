import 'dart:convert';

import 'package:aikit/aikit.dart';
import 'package:checks/checks.dart';
import 'package:test/test.dart';

import 'ai_native_appearance_artwork_test.dart' show appearanceArtworkReplacement;
import 'ai_native_appearance_editing_test.dart' show appearanceAssignment, appearanceEditingModel;
import 'ai_native_appearance_groups_test.dart' show appearanceGroupsSource;

/// Adds private named styles on a path and nested group without replacing them.
String nestedAppearanceSource({bool compound = false, bool simple = false}) {
  final String source = appearanceGroupsSource(compound: compound);
  final String definition = simple
      ? '/KnownStyle : (Child) /Name , /SimpleStyle : 0 g /Paint ; /Def ;\n'
      : source.substring(source.indexOf('/KnownStyle'), source.indexOf('%%EndSetup')).replaceAll('(Shared)', '(Child)');
  return source
      .replaceFirst('%%EndSetup', '$definition%%EndSetup')
      .replaceAll('(First contour) /String (AIArtName) , ;', '(First contour) /String (AIArtName) , ;\n%_0 (Child) XW')
      .replaceAll(
        compound ? '%_20 0 m 30 0 L 30 10 L 20 0 L n' : '(Nested group) /String (Object name) , ;',
        '${compound ? '%_20 0 m 30 0 L 30 10 L 20 0 L n' : '(Nested group) /String (Object name) , ;'}\n%_1 (Child) XW',
      );
}

/// Selects complete outer owners while keeping private child references distinct.
List<AiNativeResourceUse> nestedAppearanceOwners(AiNativeAppearances model) => model.uses.where((use) => !use.instruction.isPrivate).toList();

/// Supplies one complete outer expansion for an explicitly chosen body user.
AiNativeAppearanceReplacement nestedAppearanceReplacement(AiNativeAppearances model, int index) => appearanceArtworkReplacement(model, model.uses.indexOf(nestedAppearanceOwners(model)[index]));

/// Changes only the outer shared or isolated native appearance.
AiNativeAppearances nestedAppearanceEdit(AiNativeAppearances model, {bool shared = false}) {
  final List<AiNativePaintChange> paints = [
    AiNativePaintChange(assignment: appearanceAssignment(model.styles.first, 2, .fillColor), values: [0.7, 0.6, 0.5]),
  ];
  final List<AiNativeAppearanceReplacement> artwork = [nestedAppearanceReplacement(model, 0), if (shared) nestedAppearanceReplacement(model, 1)];
  return shared
      ? model.updateShared(appearance: model.styles.first, paints: paints, artwork: artwork)
      : model.updateSelected(appearance: model.styles.first, paints: paints, artwork: artwork, nameBytes: latin1.encode('Selected outer'));
}

/// Reads exact source bytes from an immutable owning snapshot.
List<int> _bytes(AiNativeAppearances model, AiNativeItem owner) => model.structure.drawing.records.program.bytes.sublist(owner.start, owner.end);

/// Checks retained nested ownership, independent names and inherited dependencies.
void main() {
  test('exposes ordered immutable nested style applications with direct path and group owners', () {
    final AiNativeAppearances model = appearanceEditingModel(source: nestedAppearanceSource());
    final AiNativeAppearanceArtwork artwork = model.artworkFor(use: nestedAppearanceOwners(model).first);
    check(model.uses).length.equals(6);
    check(artwork.nestedUses.map((use) => use.instruction.operands.first.number)).deepEquals([0, 1]);
    check(artwork.nestedUses.every((use) => use.instruction.isPrivate && identical(model.resolve(use: use), model.styles[1]))).isTrue();
    check(artwork.nestedUses.clear).throws<UnsupportedError>();
    check(artwork.metadata).length.equals(3);
    check(() => model.artworkFor(use: artwork.nestedUses.first)).throws<UnsupportedError>();
  });

  test('retains complete nested definitions and authoring trees in selected and shared edits', () {
    for (final bool compound in [false, true]) {
      for (final bool simple in [false, true]) {
        final AiNativeAppearances before = appearanceEditingModel(
          source: nestedAppearanceSource(compound: compound, simple: simple),
        );
        for (final bool shared in [false, true]) {
          final AiNativeAppearances after = nestedAppearanceEdit(before, shared: shared);
          check(after.styles).length.equals(shared ? 2 : 3);
          check(after.uses).length.equals(6);
          final AiNativeAppearance child = after.styles.singleWhere((style) => latin1.decode(style.resource.nameBytes) == 'Child');
          check(_bytes(after, child.resource.definition.source as AiNativeContainer)).deepEquals(_bytes(before, before.styles[1].resource.definition.source as AiNativeContainer));
          for (final int index in [0, 1]) {
            final AiNativeAppearanceArtwork original = before.artworkFor(use: nestedAppearanceOwners(before)[index]);
            final AiNativeAppearanceArtwork changed = after.artworkFor(use: nestedAppearanceOwners(after)[index]);
            check(_bytes(after, changed.authoring)).deepEquals(_bytes(before, original.authoring));
            check(changed.nestedUses.map((use) => latin1.decode(use.nameBytes))).deepEquals(['Child', 'Child']);
          }
        }
      }
    }
  });

  test('checks mode-zero and mode-one inherited state inside following private groups', () {
    for (final int mode in [0, 1]) {
      final String source = nestedAppearanceSource(simple: true).replaceAll('%_0 (Child) XW', '%_$mode (Child) XW');
      final int reset = source.lastIndexOf('0 G');
      final String inherited = source.replaceRange(reset, reset + 3, '');

      /// Changes a stroke color that the nested simple style would inherit.
      AiNativeAppearances edit(AiNativeAppearances model) => model.updateSelected(
        appearance: model.styles.first,
        paints: [
          AiNativePaintChange(assignment: appearanceAssignment(model.styles.first, 5, .strokeColor), values: [0.1, 0.2, 0.3, 0.4]),
        ],
        artwork: [nestedAppearanceReplacement(model, 0)],
        nameBytes: latin1.encode('Selected stroke'),
      );

      final AiNativeAppearances before = appearanceEditingModel(source: inherited);
      check(() => edit(before)).throws<UnsupportedError>();
      check(latin1.decode(before.structure.drawing.records.program.bytes)).equals(inherited);
      final String explicit = inherited.replaceAll('%_$mode (Child) XW', '%_0 G\n%_$mode (Child) XW');
      // An assignment between the contour and its use would detach ownership.
      check(() => edit(appearanceEditingModel(source: explicit))).throws<UnsupportedError>();
      final String restored = inherited.replaceAll('%_3 As', '%_0 G\n%_3 As');
      check(() => edit(appearanceEditingModel(source: restored))).returnsNormally();
    }
  });

  test('refuses unresolved conditional ambiguous and unsupported nested definitions', () {
    final String source = nestedAppearanceSource();
    final String child = source.substring(source.indexOf('/KnownStyle : (Child)'), source.indexOf('%%EndSetup'));
    for (final String text in [
      source.replaceFirst('%_0 (Child)', '%_0 (Missing)'),
      source.replaceFirst('%%EndSetup', '$child%%EndSetup'),
      source.replaceFirst(child, '%AI17_Begin_Content_if_version_gt:24 4\n$child%AI17_End_Versioned_Content\n'),
      source.replaceFirst(child, child.replaceFirst('(Fill Style Filter)', '(Unknown Filter)')),
      source.replaceFirst(child, child.replaceFirst('0.2 0.3 0.4 Xa', '42 FuturePaint')),
    ]) {
      final AiNativeAppearances model = appearanceEditingModel(source: text);
      check(() => model.artworkFor(use: nestedAppearanceOwners(model).first)).throws<UnsupportedError>();
      check(latin1.decode(model.structure.drawing.records.program.bytes)).equals(text);
    }
  });

  test('rejects detached repeated mixed and unnamed inner applications', () {
    final String source = nestedAppearanceSource();
    for (final String text in [
      source.replaceFirst('%_0 (Child) XW', '%_0 G\n%_0 (Child) XW'),
      source.replaceFirst('%_0 (Child) XW', '%_0 (Child) XW\n%_1 (Child) XW'),
      source.replaceFirst('%_0 (Child) XW', '0 (Child) XW'),
      source.replaceFirst('%_0 (Child) XW', '%_6 (Child) XW'),
      source.replaceFirst('%_0 (Child) XW', '%_0 () XW'),
      source.replaceFirst('%_3 As', '%_0 (Child) XW\n%_3 As'),
      source.replaceFirst('%_0 (Child) XW', '%_3 As\n%_0 (Child) XW'),
    ]) {
      final AiNativeAppearances model = appearanceEditingModel(source: text);
      check(() => model.artworkFor(use: nestedAppearanceOwners(model).last)).returnsNormally();
      check(() => model.artworkFor(use: nestedAppearanceOwners(model).first)).throws<UnsupportedError>();
    }
  });

  test('does not count retained child references as supplied shared printing coverage', () {
    final String source = nestedAppearanceSource().replaceAll('%_0 (Child) XW', '%_0 (Shared) XW');
    final AiNativeAppearances before = appearanceEditingModel(source: source);
    check(() => nestedAppearanceEdit(before)).returnsNormally();
    check(() => nestedAppearanceEdit(before, shared: true)).throws<UnsupportedError>();
    check(latin1.decode(before.structure.drawing.records.program.bytes)).equals(source);
  });

  test('rebinds retained uses after repeated edits and preserves bounded snapshots', () {
    final AiNativeAppearances before = appearanceEditingModel(source: nestedAppearanceSource());
    final AiNativeAppearances after = nestedAppearanceEdit(before);
    final AiNativeAppearance selected = after.resolve(use: nestedAppearanceOwners(after).first)!;
    final AiNativeAppearances next = after.updateSelected(
      appearance: selected,
      paints: [
        AiNativePaintChange(assignment: appearanceAssignment(selected, 2, .fillColor), values: [0.3, 0.2, 0.1]),
      ],
      artwork: [nestedAppearanceReplacement(after, 0)],
      nameBytes: latin1.encode('Another outer'),
    );
    check(next.styles).length.equals(4);
    check(next.artworkFor(use: nestedAppearanceOwners(next).first).nestedUses).length.equals(2);
    final AiNativeAppearances bounded = appearanceEditingModel(
      source: nestedAppearanceSource(),
      limits: AiNativeLimits(maxDecodedBytes: after.structure.drawing.records.program.bytes.length - 1),
    );
    check(() => nestedAppearanceEdit(bounded)).throws<FormatException>();
  });
}
