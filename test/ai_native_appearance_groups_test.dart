import 'dart:convert';

import 'package:aikit/aikit.dart';
import 'package:checks/checks.dart';
import 'package:test/test.dart';

import 'ai_native_appearance_artwork_test.dart' show appearanceArtworkPair, appearanceArtworkReplacement;
import 'ai_native_appearance_editing_test.dart' show appearanceAssignment, appearanceEditingModel, appearanceEditingSource;

/// Two authoritative contours with optional nested grouping and saved point counts.
String appearanceGroupAuthoring({bool compound = false, bool counted = true, bool metadata = true}) =>
    '''%_0 Ae
%_${compound ? '*u' : 'u'}
${counted ? '%_3 As\n' : ''}%_0 0 m 10 0 L 10 10 L 0 0 L n
${metadata ? '%_/ArtDictionary : (First contour) /String (AIArtName) , ;\n' : ''}${compound ? '' : '%_1 Ae\n%_u\n'}${counted ? '%_3 As\n' : ''}%_20 0 m 30 0 L 30 10 L 20 0 L n
${compound ? '' : '%_U\n'}${!compound && metadata ? '%_/ArtDictionary : (Nested group) /String (Object name) , ;\n' : ''}%_${compound ? '*U' : 'U'}
${metadata ? '%_/ArtDictionary : (Outer group) /String (AIArtName) , ;' : ''}''';

/// Keeps two complete source pairs without synthesizing live-shape parameters.
String appearanceGroupsSource({bool compound = false, bool counted = true, bool metadata = true, bool mixed = false}) {
  final String setup = appearanceEditingSource().split('%%EndSetup').first;
  final String pair = appearanceArtworkPair().replaceFirst('%_0 0 m 10 0 L 10 10 L 0 0 L n', appearanceGroupAuthoring(compound: compound, counted: counted, metadata: metadata));
  return '$setup%%EndSetup\n$pair${mixed ? appearanceArtworkPair() : pair}\n%%Trailer\n%%EOF\n';
}

/// Changes one selected group-local style using a complete host expansion.
AiNativeAppearances appearanceGroupEdit(AiNativeAppearances model, {bool shared = false}) {
  final AiNativeAppearance style = model.styles.first;
  final List<AiNativePaintChange> paints = [
    AiNativePaintChange(assignment: appearanceAssignment(style, 2, .fillColor), values: [0.7, 0.6, 0.5]),
  ];
  return shared
      ? model.updateShared(appearance: style, paints: paints, artwork: [appearanceArtworkReplacement(model, 0), appearanceArtworkReplacement(model, 1)])
      : model.updateSelected(appearance: style, paints: paints, artwork: [appearanceArtworkReplacement(model, 0)], nameBytes: latin1.encode('Selected group'));
}

/// Returns the complete exact authoring subtree rather than normalized geometry.
List<int> _authoring(AiNativeAppearances model, int index) {
  final AiNativeItem owner = model.artworkFor(use: model.uses[index]).authoring;
  return model.structure.drawing.records.program.bytes.sublist(owner.start, owner.end);
}

/// Covers grouped ownership, retained descendants and atomic dependency checks.
void main() {
  test('binds immutable nested groups and exposes every owned dictionary', () {
    final AiNativeAppearances model = appearanceEditingModel(source: appearanceGroupsSource());
    final AiNativeAppearanceArtwork artwork = model.artworkFor(use: model.uses.first);
    check(artwork.path).isNull();
    check(artwork.group).isNotNull();
    check(artwork.authoring).identicalTo(artwork.group!);
    check(artwork.group!.paths).length.equals(2);
    check(artwork.group!.children.whereType<AiNativeGroup>()).length.equals(1);
    check(artwork.liveShape).isNull();
    check(artwork.metadata).length.equals(3);
    check(artwork.metadata.last).identicalTo(artwork.dictionary!);
    check(artwork.metadata.clear).throws<UnsupportedError>();
  });

  test('isolates grouped users while retaining all private descendants and neighbors', () {
    for (final bool counted in [false, true]) {
      final String text = appearanceGroupsSource(counted: counted);
      final AiNativeAppearances before = appearanceEditingModel(source: text);
      final AiNativeAppearances after = appearanceGroupEdit(before);
      check(after.styles).length.equals(2);
      for (final int index in [0, 1]) {
        check(_authoring(after, index)).deepEquals(_authoring(before, index));
      }
      check(after.structure.drawing.liveShapes).isEmpty();
      check(after.resolve(use: after.uses.last)).identicalTo(after.styles.first);
      check(latin1.decode(before.structure.drawing.records.program.bytes)).equals(text);
    }
  });

  test('updates shared ordinary compound and mixed single-contour users atomically', () {
    for (final String text in [appearanceGroupsSource(), appearanceGroupsSource(compound: true), appearanceGroupsSource(mixed: true)]) {
      final AiNativeAppearances before = appearanceEditingModel(source: text);
      final AiNativeAppearances after = appearanceGroupEdit(before, shared: true);
      check(after.styles).length.equals(1);
      check(after.styles.single.uses).length.equals(2);
      for (final int index in [0, 1]) {
        check(_authoring(after, index)).deepEquals(_authoring(before, index));
      }
      check(
        () => before.updateShared(
          appearance: before.styles.first,
          paints: [
            AiNativePaintChange(assignment: appearanceAssignment(before.styles.first, 2, .fillColor), values: [0.7, 0.6, 0.5]),
          ],
          artwork: [appearanceArtworkReplacement(before, 0)],
        ),
      ).throws<UnsupportedError>();
    }
  });

  test('preserves nested identities and permits a second edit of the selected group', () {
    final String text = appearanceGroupsSource().replaceFirst('(First contour) /String (AIArtName)', '(First contour) /String (AIArtName) , /XMLUID : (child-1) ; (AI10_ArtUID)');
    final AiNativeAppearances before = appearanceEditingModel(source: text);
    final AiNativeAppearances changed = appearanceGroupEdit(before);
    final AiNativeAppearances next = changed.updateSelected(
      appearance: changed.styles.last,
      paints: [
        AiNativePaintChange(assignment: appearanceAssignment(changed.styles.last, 2, .fillColor), values: [0.4, 0.3, 0.2]),
      ],
      artwork: [appearanceArtworkReplacement(changed, 0)],
      nameBytes: latin1.encode('Another group'),
    );
    check(next.styles).length.equals(3);
    check(next.structure.identifiers.map((identifier) => latin1.decode(identifier.bytes))).deepEquals(['child-1']);
    check(_authoring(next, 0)).deepEquals(_authoring(before, 0));
  });

  test('rejects unqualified inner owners instead of treating all private bytes as inert', () {
    final String source = appearanceGroupsSource();
    for (final String text in [
      source.replaceFirst('%_0 0 m 10 0 L 10 10 L 0 0 L n', '0 0 m 10 0 L 10 10 L 0 0 L n'),
      source.replaceFirst('(AIArtName)', '(UnknownOwner)'),
      source.replaceFirst('%_3 As', '%_4 As'),
      source.replaceFirst('%_3 As', '%_3 As\n%_3 As'),
      source.replaceFirst('%_3 As', '%_17 FutureState\n%_3 As'),
      source.replaceFirst('%_1 Ae\n%_u', '%_1 Ae\n%_0 g\n%_u'),
      source.replaceFirst('%_3 As', '%_1 (Shared) XW\n%_3 As'),
      source.replaceFirst('%_3 As', '%_2 0 Xd\n%_3 As'),
      source.replaceFirst('%_0 0 m 10 0 L', '%_0 0 m 1 g 10 0 L'),
      source.replaceFirst('%_0 Ae\n%_u', '%_3 As\n%_0 Ae\n%_u'),
    ]) {
      final AiNativeAppearances model = appearanceEditingModel(source: text);
      check(() => model.artworkFor(use: model.uses.first)).throws<UnsupportedError>();
      check(latin1.decode(model.structure.drawing.records.program.bytes)).equals(text);
    }
    check(() => appearanceEditingModel(source: source.replaceFirst('%_0 0 m 10 0 L', '%_0 0 m 9007199254740992 0 L'))).throws<FormatException>();
  });

  test('rejects mixed boundaries conditional owners and detached metadata', () {
    final String source = appearanceGroupsSource();
    for (final String text in [
      source.replaceFirst('%_3 As', '%_/ArtDictionary : (detached) /String (AIArtName) , ;\n%_3 As'),
      source.replaceFirst('%_3 As', '%AI17_Begin_Content_if_version_gt:24 4\n%_3 As').replaceFirst('%_U', '%AI17_End_Versioned_Content\n%_U'),
    ]) {
      check(() {
        final AiNativeAppearances model = appearanceEditingModel(source: text);
        model.artworkFor(use: model.uses.first);
      }).throws<UnsupportedError>();
    }
    check(() => appearanceEditingModel(source: source.replaceFirst('%_u', 'u'))).throws<FormatException>();
  });

  test('retains following grouped state checks and source limits', () {
    final String text = appearanceGroupsSource();
    final AiNativeAppearances source = appearanceEditingModel(source: text);
    final int size = appearanceGroupEdit(source).structure.drawing.records.program.bytes.length;
    final AiNativeAppearances bounded = appearanceEditingModel(
      source: text,
      limits: AiNativeLimits(maxDecodedBytes: size - 1),
    );
    check(() => appearanceGroupEdit(bounded)).throws<FormatException>();
    check(latin1.decode(bounded.structure.drawing.records.program.bytes)).equals(text);
    final AiNativeAppearances foreign = appearanceEditingModel(source: text);
    check(
      () => source.updateSelected(
        appearance: source.styles.first,
        paints: [
          AiNativePaintChange(assignment: appearanceAssignment(source.styles.first, 2, .fillColor), values: [0.7, 0.6, 0.5]),
        ],
        artwork: [appearanceArtworkReplacement(foreign, 0)],
        nameBytes: [65],
      ),
    ).throws<ArgumentError>();
  });
}
