import 'dart:convert';

import 'package:aikit/aikit.dart';
import 'package:checks/checks.dart';
import 'package:test/test.dart';

import 'ai_native_appearance_artwork_test.dart' show appearanceArtworkSource;
import 'ai_native_appearance_clipping_test.dart' show clippingAppearanceSource;
import 'ai_native_appearance_editing_test.dart' show appearanceAssignment, appearanceEditedGroup, appearanceEditingModel, appearanceEditingSource;
import 'ai_native_appearance_nested_styles_test.dart' show nestedAppearanceSource;

/// Retained registration fields on an ordinary enclosing symbol group.
const String resourceAppearanceRegistration = '''%_/ArtDictionary :
%_0 /Bool (AI13PatternEnableGuides) ,
%_2 /Int (AI13PatternExportType) ,
%_16.2229 48.6687 45.728 15.2427 0 0 /RealMatrix (AI13Pattern9SliceScalingGridKey) ,
%_5 /Int (AI13PatternRegistrationType) ,
%_;
9 () XW
''';

/// Places separate complete pairs in setup and body without changing their data.
String resourceAppearanceSource({String? original, AiNativeArtworkResourceKind kind = .symbol, String registration = resourceAppearanceRegistration}) {
  final String source = original ?? appearanceArtworkSource(metadata: true);
  final int setup = source.indexOf('%%EndSetup');
  final String body = source.substring(setup + '%%EndSetup'.length, source.indexOf('%%Trailer'));
  final String declaration = switch (kind) {
    .pattern => '%AI3_BeginPattern: (Resource)\n(Resource) 0 0 10 10\n$body\nE\n%AI3_EndPattern\n',
    .symbol => '%AI14_BeginSymbol\n(Resource)\n0 A\n0 Xw\n0 Ae\nu\n$body\nU\n$registration%AI10_EndSymbol\n',
    .brush => '%AI8_BeginBrushPattern\n(Resource)\n$body\n%AI8_EndBrushPattern\n',
  };
  return source.replaceRange(setup, setup, declaration);
}

/// Supplies unchanged topology and an explicit host-composed process paint.
AiNativeAppearanceReplacement resourceAppearanceReplacement(AiNativeAppearanceArtwork artwork) => AiNativeAppearanceReplacement(
  artwork: artwork,
  bytes: latin1.encode(appearanceEditedGroup),
  bounds: AiBoundingBox(left: -20, bottom: -30, right: 120, top: 140),
);

/// Checks local ownership without granting body mutation or instance coverage.
void main() {
  test('binds resource pairs to local geometry while retaining original global uses', () {
    for (final AiNativeArtworkResourceKind kind in AiNativeArtworkResourceKind.values) {
      final String source = resourceAppearanceSource(kind: kind);
      final AiNativeAppearances model = appearanceEditingModel(source: source);
      final AiNativeArtworkResource resource = model.artworkResources.resources.single;
      check(model.uses).length.equals(4);
      for (final AiNativeResourceUse use in resource.uses) {
        final AiNativeAppearanceArtwork artwork = model.artworkFor(use: use);
        check(artwork.resource).identicalTo(resource);
        check(artwork.use).identicalTo(use);
        check(model.resolve(use: artwork.use)).identicalTo(model.styles.single);
        check(resource.paths).contains(artwork.path!);
        check(resource.groups).contains(artwork.printingGroup);
        check(model.structure.drawing.paths.contains(artwork.path)).isFalse();
        check(artwork.start).isGreaterOrEqual(resource.artworkStart);
        check(artwork.end).isLessOrEqual(resource.artworkEnd);
      }
      check(model.artworkFor(use: model.uses.last).resource).isNull();
      check(latin1.decode(model.structure.drawing.records.program.bytes)).equals(source);
    }
  });

  test('binds nested style handles and private clipping topology within resources', () {
    for (final String original in [nestedAppearanceSource(), nestedAppearanceSource(compound: true), clippingAppearanceSource(variant: 'compound')]) {
      final AiNativeAppearances model = appearanceEditingModel(source: resourceAppearanceSource(original: original));
      final AiNativeArtworkResource resource = model.artworkResources.resources.single;
      for (final AiNativeResourceUse use in resource.uses.where((use) => !use.instruction.isPrivate)) {
        final AiNativeAppearanceArtwork artwork = model.artworkFor(use: use);
        check(artwork.group).isNotNull();
        check(artwork.groupContours).isNotEmpty();
        check(artwork.groupContours.clear).throws<UnsupportedError>();
        check(artwork.nestedUses.clear).throws<UnsupportedError>();
        for (final AiNativeResourceUse nested in artwork.nestedUses) {
          check(model.uses).contains(nested);
          check(resource.uses).contains(nested);
          check(resource.paths.contains(artwork.authoringFor(use: nested)) || resource.groups.contains(artwork.authoringFor(use: nested))).isTrue();
          check(() => model.artworkFor(use: nested)).throws<UnsupportedError>();
        }
      }
    }
  });

  test('retains resource live-shape pairs without promoting their geometry to the body', () {
    final AiNativeAppearances model = appearanceEditingModel(source: resourceAppearanceSource(original: appearanceEditingSource()));
    final AiNativeArtworkResource resource = model.artworkResources.resources.single;
    for (final AiNativeResourceUse use in resource.uses) {
      final AiNativeAppearanceArtwork artwork = model.artworkFor(use: use);
      check(artwork.liveShape).isNotNull();
      check(artwork.liveShape!.isBound).isTrue();
      check(model.structure.drawing.liveShapes.contains(artwork.liveShape)).isFalse();
      check(() => model.structure.drawing.duplicatePaths(paths: [artwork.path!])).throws<ArgumentError>();
    }
  });

  test('refuses foreign uses and preserves independent declarations with equal names', () {
    final String source = resourceAppearanceSource();
    final AiNativeAppearances before = appearanceEditingModel(source: source);
    check(() => before.artworkFor(use: appearanceEditingModel(source: source).uses.first)).throws<ArgumentError>();
    final AiNativeArtworkResource first = before.artworkResources.resources.single;
    final String declaration = source.substring(first.start, first.end);
    final AiNativeAppearances model = appearanceEditingModel(source: source.replaceFirst('%%EndSetup', '$declaration\n%%EndSetup'));
    for (final AiNativeArtworkResource resource in model.artworkResources.resources) {
      check(model.artworkFor(use: resource.uses.first).resource).identicalTo(resource);
    }
    check(model.uses).length.equals(6);
  });

  test('rejects conditional resource uses unresolved metadata and parent effects', () {
    final String source = resourceAppearanceSource();
    final AiNativeArtworkResource resource = appearanceEditingModel(source: source).artworkResources.resources.single;
    for (final String text in [
      source.replaceRange(resource.start, resource.end, '%AI17_Begin_Content_if_version_gt:24 4\n${source.substring(resource.start, resource.end)}\n%AI17_End_Versioned_Content'),
      source.replaceFirst('(AI13PatternEnableGuides)', '(UnknownRegistration)'),
      source.replaceFirst('%_2 /Int', '%_0.5 /Real (UnknownEffect) ,\n%_2 /Int'),
      source.replaceFirst('9 () XW', '9 (Unknown) XW'),
      source.replaceFirst('(Printing) /String (AIArtName)', '(Opaque) /String (UnknownCache)'),
      source.replaceFirst('0 Ae\nu', '%_0 Ae\nu'),
    ]) {
      final AiNativeAppearances model = appearanceEditingModel(source: text);
      check(() => model.artworkFor(use: model.uses.first)).throws<UnsupportedError>();
      check(latin1.decode(model.structure.drawing.records.program.bytes)).equals(text);
    }
  });

  test('rejects pairs split across declarations and never borrows body artwork', () {
    final String source = resourceAppearanceSource(registration: '');
    final int boundary = source.indexOf('6 () XW');
    final String split = source.replaceRange(boundary, boundary, 'U\n%AI10_EndSymbol\n%AI14_BeginSymbol\n(Other)\nu\n');
    final AiNativeAppearances model = appearanceEditingModel(source: split);
    check(() => model.artworkFor(use: model.uses.first)).throws<UnsupportedError>();
    check(model.artworkFor(use: model.uses.last).resource).isNull();
  });

  test('requires a separate instance-coverage contract before resource mutation', () {
    final String source = resourceAppearanceSource();
    final AiNativeAppearances model = appearanceEditingModel(source: source);
    final List<AiNativePaintChange> paints = [
      AiNativePaintChange(assignment: appearanceAssignment(model.styles.first, 2, .fillColor), values: [0.7, 0.6, 0.5]),
    ];
    check(
      () => model.updateSelected(
        appearance: model.styles.first,
        paints: paints,
        artwork: [resourceAppearanceReplacement(model.artworkFor(use: model.uses.first))],
        nameBytes: latin1.encode('Selected'),
      ),
    ).throws<UnsupportedError>();
    check(
      () => model.updateShared(
        appearance: model.styles.first,
        paints: paints,
        artwork: model.uses.map((use) => resourceAppearanceReplacement(model.artworkFor(use: use))).toList(),
      ),
    ).throws<UnsupportedError>();
    final AiNativeAppearances updated = model.updateSelected(
      appearance: model.styles.first,
      paints: paints,
      artwork: [resourceAppearanceReplacement(model.artworkFor(use: model.uses.last))],
      nameBytes: latin1.encode('Body selection'),
    );
    final AiNativeArtworkResource before = model.artworkResources.resources.single;
    final AiNativeArtworkResource after = updated.artworkResources.resources.single;
    check(updated.structure.drawing.records.program.bytes.sublist(after.start, after.end)).deepEquals(model.structure.drawing.records.program.bytes.sublist(before.start, before.end));
    check(latin1.decode(model.structure.drawing.records.program.bytes)).equals(source);
    final AiNativeAppearances opaque = appearanceEditingModel(source: source.replaceFirst('6 () XW', '7 N\n6 () XW'));
    check(() => opaque.artworkFor(use: opaque.uses.first)).throws<FormatException>();
    check(
      () => opaque.updateSelected(
        appearance: opaque.styles.first,
        paints: [
          AiNativePaintChange(assignment: appearanceAssignment(opaque.styles.first, 2, .fillColor), values: [0.7, 0.6, 0.5]),
        ],
        artwork: [resourceAppearanceReplacement(opaque.artworkFor(use: opaque.uses.last))],
        nameBytes: latin1.encode('Body only'),
      ),
    ).returnsNormally();
  });
}
