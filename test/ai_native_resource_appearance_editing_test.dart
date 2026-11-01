import 'dart:convert';

import 'package:aikit/aikit.dart';
import 'package:checks/checks.dart';
import 'package:test/test.dart';

import 'ai_native_appearance_artwork_test.dart' show appearanceArtworkPair, appearanceArtworkSource;
import 'ai_native_appearance_editing_test.dart' show appearanceAssignment, appearanceEditedGroup, appearanceEditingModel;
import 'ai_native_appearance_nested_styles_test.dart' show nestedAppearanceSource;
import 'ai_native_resource_appearances_test.dart' show resourceAppearanceSource;

/// A literal pattern paint with its saved placement and identity matrix.
String resourcePatternPaint(String name) => '($name) 0 0 1 1 0 0 0 0 0 [1 0 0 1 0 0] p';

/// Gives each dependent style an explicit pattern assignment without composing it.
String resourcePatternStyle(String name, String pattern) => '/KnownStyle : ($name) /Name , /SimpleStyle : ${resourcePatternPaint(pattern)} /Paint ; /Def ;\n';

/// One complete resource definition with explicit outgoing native fill state.
String resourcePattern(String name, String artwork, {bool restore = true}) => '%AI3_BeginPattern: ($name)\n($name) 0 0 10 10\n$artwork${restore ? '%_0 g\n' : ''}E\n%AI3_EndPattern\n';

/// Keeps a resource-to-resource chain and every dependent body expansion explicit.
String resourceAppearanceEditingSource({bool chain = false, bool restore = true}) {
  final String setup = appearanceArtworkSource().split('%%EndSetup').first;
  final String pattern = resourcePattern('Tile', appearanceArtworkPair(), restore: restore);
  final String second = chain ? resourcePattern('Composite', appearanceArtworkPair().replaceAll('(Shared)', '(Pattern paint)')) : '';
  final String body = appearanceArtworkPair().replaceAll('(Shared)', chain ? '(Outer paint)' : '(Pattern paint)');
  return '$setup${resourcePatternStyle('Pattern paint', 'Tile')}${chain ? resourcePatternStyle('Outer paint', 'Composite') : ''}$pattern$second%%EndSetup\n$body$body\n%%Trailer\n%%EOF\n';
}

/// Supplies matching complete groups in their owner's local coordinate system.
AiNativeAppearanceReplacement resourceEditingReplacement(AiNativeAppearances model, AiNativeResourceUse use, {AiBoundingBox? bounds, String bytes = appearanceEditedGroup}) =>
    AiNativeAppearanceReplacement(
      artwork: model.artworkFor(use: use),
      bytes: latin1.encode(bytes),
      bounds: bounds ?? AiBoundingBox(left: -20, bottom: -30, right: 120, top: 140),
    );

/// Changes one source style and supplies all transitive pattern-style expansions.
AiNativeAppearances resourceAppearanceEdit(AiNativeAppearances model, {bool shared = false, List<AiNativeAppearanceReplacement>? dependents}) {
  final AiNativeAppearance style = model.styles.first;
  final List<AiNativePaintChange> paints = [
    AiNativePaintChange(assignment: appearanceAssignment(style, 2, .fillColor), values: [0.7, 0.6, 0.5]),
  ];
  final List<AiNativeAppearanceReplacement> artwork = [resourceEditingReplacement(model, style.uses.single)];
  final List<AiNativeAppearanceReplacement> derived =
      dependents ?? [for (final AiNativeResourceUse use in model.uses.where((use) => !style.uses.contains(use))) resourceEditingReplacement(model, use)];
  return shared
      ? model.updateShared(appearance: style, paints: paints, artwork: artwork, dependents: derived)
      : model.updateSelected(appearance: style, paints: paints, artwork: artwork, dependents: derived, nameBytes: latin1.encode('Selected tile'));
}

/// Checks complete transactions rather than treating a bound resource as editable.
void main() {
  test('edits a used pattern only with every dependent printing owner', () {
    final String source = resourceAppearanceEditingSource();
    final AiNativeAppearances model = appearanceEditingModel(source: source);
    check(() => resourceAppearanceEdit(model, dependents: [])).throws<UnsupportedError>();
    check(() => resourceAppearanceEdit(model, dependents: [resourceEditingReplacement(model, model.uses.last)])).throws<UnsupportedError>();
    for (final bool shared in [false, true]) {
      final AiNativeAppearances changed = resourceAppearanceEdit(model, shared: shared);
      check(changed.styles).length.equals(shared ? 2 : 3);
      check(changed.uses.map((use) => latin1.decode(use.nameBytes))).deepEquals([if (shared) 'Shared' else 'Selected tile', 'Pattern paint', 'Pattern paint']);
      for (final AiNativeResourceUse use in changed.uses) {
        final AiNativeAppearanceArtwork artwork = changed.artworkFor(use: use);
        check(changed.structure.drawing.records.program.bytes.sublist(artwork.printingGroup.start, artwork.printingGroup.end)).deepEquals(latin1.encode(appearanceEditedGroup));
      }
      final AiNativeContainer before = model.styles[1].resource.definition.source as AiNativeContainer;
      final AiNativeContainer after = changed.styles[shared ? 1 : 2].resource.definition.source as AiNativeContainer;
      check(changed.structure.drawing.records.program.bytes.sublist(after.start, after.end)).deepEquals(model.structure.drawing.records.program.bytes.sublist(before.start, before.end));
    }
    check(latin1.decode(model.structure.drawing.records.program.bytes)).equals(source);
  });

  test('requires transitive resource and body expansions in one transaction', () {
    final AiNativeAppearances model = appearanceEditingModel(source: resourceAppearanceEditingSource(chain: true));
    check(() => resourceAppearanceEdit(model, dependents: [resourceEditingReplacement(model, model.uses[1])])).throws<UnsupportedError>();
    final AiNativeAppearances changed = resourceAppearanceEdit(model);
    check(changed.uses).length.equals(4);
    check(changed.artworkResources.resources).length.equals(2);
    check(changed.uses.map((use) => latin1.decode(use.nameBytes))).deepEquals(['Selected tile', 'Pattern paint', 'Outer paint', 'Outer paint']);
  });

  test('covers dependent child uses once per complete printing owner', () {
    final String source = nestedAppearanceSource(simple: true)
        .replaceFirst('/KnownStyle : (Child) /Name , /SimpleStyle : 0 g /Paint ; /Def ;', resourcePatternStyle('Child', 'Tile'))
        .replaceFirst('%%EndSetup', '${resourcePattern('Tile', appearanceArtworkPair())}%%EndSetup');
    final AiNativeAppearances model = appearanceEditingModel(source: source);
    final AiNativeAppearance style = model.styles.first;
    final List<AiNativeAppearanceArtwork> body = style.uses.skip(1).map((use) => model.artworkFor(use: use)).toList();
    final List<AiNativePaintChange> paints = [
      AiNativePaintChange(assignment: appearanceAssignment(style, 2, .fillColor), values: [0.7, 0.6, 0.5]),
    ];

    /// Supplies child selections through their existing enclosing expansion.
    AiNativeAppearances edit({required bool complete}) => model.updateSelected(
      appearance: style,
      paints: paints,
      artwork: [resourceEditingReplacement(model, style.uses.first)],
      dependents: [
        for (final AiNativeAppearanceArtwork owner in body)
          AiNativeAppearanceReplacement(
            artwork: owner,
            bytes: latin1.encode(appearanceEditedGroup),
            bounds: AiBoundingBox(left: -20, bottom: -30, right: 120, top: 140),
            uses: complete ? owner.nestedUses : [owner.nestedUses.first],
          ),
      ],
      nameBytes: latin1.encode('Nested dependents'),
    );

    check(() => edit(complete: false)).throws<UnsupportedError>();
    final AiNativeAppearances selected = edit(complete: true);
    check(selected.styles.singleWhere((style) => latin1.decode(style.resource.nameBytes) == 'Child').uses).length.equals(4);
    check(selected.resolve(use: selected.uses.last)!.resource.nameBytes).deepEquals(latin1.encode('Shared'));
    final AiNativeAppearances shared = model.updateShared(
      appearance: style,
      paints: paints,
      artwork: [for (final AiNativeResourceUse use in style.uses) resourceEditingReplacement(model, use)],
    );
    check(shared.styles).length.equals(2);
    check(shared.uses).length.equals(7);
  });

  test('rejects unresolved outgoing resource state even without a following body consumer', () {
    final String source = resourceAppearanceEditingSource(restore: false);
    final AiNativeAppearances model = appearanceEditingModel(source: source);
    check(() => resourceAppearanceEdit(model)).throws<UnsupportedError>();
    check(latin1.decode(model.structure.drawing.records.program.bytes)).equals(source);
  });

  test('rejects foreign duplicate and unrelated dependent selections atomically', () {
    final String source = resourceAppearanceEditingSource();
    final AiNativeAppearances model = appearanceEditingModel(source: source);
    final AiNativeAppearances foreign = appearanceEditingModel(source: source);
    for (final List<AiNativeAppearanceReplacement> dependents in [
      [resourceEditingReplacement(foreign, foreign.uses.last)],
      [resourceEditingReplacement(model, model.uses.last), resourceEditingReplacement(model, model.uses.last)],
      [resourceEditingReplacement(model, model.uses.first)],
    ]) {
      check(() => resourceAppearanceEdit(model, dependents: dependents)).throws<ArgumentError>();
    }
    check(latin1.decode(model.structure.drawing.records.program.bytes)).equals(source);
  });

  test('preserves outgoing printing state for every dependent expansion', () {
    final AiNativeAppearances model = appearanceEditingModel(source: resourceAppearanceEditingSource());
    check(
      () => resourceAppearanceEdit(
        model,
        dependents: [
          resourceEditingReplacement(model, model.uses[1]),
          resourceEditingReplacement(model, model.uses[2], bytes: appearanceEditedGroup.replaceFirst('0 0 0 1 k', '0 0 1 0 k')),
        ],
      ),
    ).throws<UnsupportedError>();
  });

  test('rejects recursive pattern composition and direct unowned pattern consumers', () {
    final String source = resourceAppearanceEditingSource();
    for (final String content in [
      appearanceArtworkPair().replaceAll('(Shared)', '(Pattern paint)'),
      '${resourcePatternPaint('Tile')}\n0 0 m 10 0 L 10 10 L f\n',
    ]) {
      final AiNativeAppearances model = appearanceEditingModel(source: source.replaceFirst('%_0 g\nE', '$content%_0 g\nE'));
      check(() => resourceAppearanceEdit(model)).throws<UnsupportedError>();
    }
  });

  test('requires uniquely resolved unconditional patterns and qualified whole-source dependencies', () {
    final String source = resourceAppearanceEditingSource();
    for (final String text in [
      source.replaceFirst(resourcePatternPaint('Tile'), resourcePatternPaint('Missing')),
      source.replaceFirst('%%EndSetup', '${resourcePattern('Tile', '')}%%EndSetup'),
      source.replaceFirst('%%EndSetup', '/FutureDependency : (Tile) /Reference ;\n%%EndSetup'),
      source.replaceFirst('%AI3_BeginPattern:', '%AI17_Begin_Content_if_version_gt:24 4\n%AI3_BeginPattern:').replaceFirst('%AI3_EndPattern', '%AI3_EndPattern\n%AI17_End_Versioned_Content'),
    ]) {
      final AiNativeAppearances model = appearanceEditingModel(source: text);
      check(() => resourceAppearanceEdit(model)).throws<UnsupportedError>();
      check(latin1.decode(model.structure.drawing.records.program.bytes)).equals(text);
    }
  });

  test('preserves resource printing point counts and refuses malformed local counts', () {
    final String source = resourceAppearanceEditingSource().replaceFirst(appearanceArtworkPair(), appearanceArtworkPair(counted: true));
    final AiNativeAppearances model = appearanceEditingModel(source: source);
    final String counted = appearanceEditedGroup.replaceFirst('u\n', 'u\n3 As\n').replaceFirst('10 10 L f', '10 10 L 0 0 L f');
    final AiNativeAppearances changed = model.updateSelected(
      appearance: model.styles.first,
      paints: [
        AiNativePaintChange(assignment: appearanceAssignment(model.styles.first, 2, .fillColor), values: [0.7, 0.6, 0.5]),
      ],
      artwork: [resourceEditingReplacement(model, model.uses.first, bytes: counted)],
      dependents: [for (final AiNativeResourceUse use in model.uses.skip(1)) resourceEditingReplacement(model, use)],
      nameBytes: latin1.encode('Counted tile'),
    );
    check(latin1.decode(changed.structure.drawing.records.program.bytes)).contains('u\n3 As\n0.7 0.6 0.5 Xa');
    final AiNativeAppearances malformed = appearanceEditingModel(source: source.replaceFirst('3 As', '4 As'));
    check(() => malformed.artworkFor(use: malformed.uses.first)).throws<UnsupportedError>();
    check(() => resourceAppearanceEdit(model)).throws<UnsupportedError>();
  });

  test('rebinds resource and dependent handles after repeated edits and bounds output growth', () {
    final String source = resourceAppearanceEditingSource();
    final AiNativeAppearances first = resourceAppearanceEdit(appearanceEditingModel(source: source));
    final AiNativeAppearance style = first.resolve(use: first.uses.first)!;
    final AiNativeAppearances second = first.updateSelected(
      appearance: style,
      paints: [
        AiNativePaintChange(assignment: appearanceAssignment(style, 2, .fillColor), values: [0.7, 0.6, 0.5]),
      ],
      artwork: [resourceEditingReplacement(first, first.uses.first)],
      dependents: [for (final AiNativeResourceUse use in first.uses.skip(1)) resourceEditingReplacement(first, use)],
      nameBytes: latin1.encode('Second tile'),
    );
    check(second.styles).length.equals(4);
    check(second.uses.map((use) => latin1.decode(use.nameBytes))).deepEquals(['Second tile', 'Pattern paint', 'Pattern paint']);
    final AiNativeAppearances bounded = appearanceEditingModel(
      source: source,
      limits: AiNativeLimits(maxDecodedBytes: source.length),
    );
    check(() => resourceAppearanceEdit(bounded)).throws<FormatException>();
    check(latin1.decode(bounded.structure.drawing.records.program.bytes)).equals(source);
  });

  test('keeps resource-local bounds separate from dependent document ink bounds', () {
    final AiNativeAppearances model = appearanceEditingModel(source: resourceAppearanceEditingSource());
    final AiNativeAppearances changed = model.updateSelected(
      appearance: model.styles.first,
      paints: [
        AiNativePaintChange(assignment: appearanceAssignment(model.styles.first, 2, .fillColor), values: [0.7, 0.6, 0.5]),
      ],
      artwork: [resourceEditingReplacement(model, model.uses.first, bounds: AiBoundingBox(left: -100000, bottom: -100000, right: 100000, top: 100000))],
      dependents: [for (final AiNativeResourceUse use in model.uses.skip(1)) resourceEditingReplacement(model, use)],
      nameBytes: latin1.encode('Local bounds'),
    );
    check(latin1.decode(changed.structure.drawing.records.program.bytes)).contains('%%BoundingBox: -20 -30 120 140');
    final AiBoundingBox tile = changed.artworkResources.resources.single.bounds!;
    check([tile.left, tile.bottom, tile.right, tile.top]).deepEquals([0, 0, 10, 10]);
  });

  test('edits unreferenced pattern symbol and brush artwork without inventing dependents', () {
    for (final AiNativeArtworkResourceKind kind in AiNativeArtworkResourceKind.values) {
      final AiNativeAppearances model = appearanceEditingModel(
        source: resourceAppearanceSource(kind: kind, original: appearanceArtworkSource()),
      );
      final List<AiNativePaintChange> paints = [
        AiNativePaintChange(assignment: appearanceAssignment(model.styles.first, 2, .fillColor), values: [0.7, 0.6, 0.5]),
      ];
      final AiNativeAppearances changed = model.updateSelected(
        appearance: model.styles.first,
        paints: paints,
        artwork: [resourceEditingReplacement(model, model.uses.first)],
        nameBytes: latin1.encode('Resource selection'),
      );
      check(latin1.decode(changed.uses.first.nameBytes)).equals('Resource selection');
      check(changed.artworkResources.resources.single.kind).equals(kind);
      check(latin1.decode(changed.structure.drawing.records.program.bytes)).contains('%%BoundingBox: 0 0 100 100');
      check(
        () => model.updateSelected(
          appearance: model.styles.first,
          paints: paints,
          artwork: [resourceEditingReplacement(model, model.uses.first)],
          dependents: [resourceEditingReplacement(model, model.uses.last)],
          nameBytes: latin1.encode('Unrelated coverage'),
        ),
      ).throws<ArgumentError>();
    }
  });

  test('rejects changes to artwork referenced by qualified art and pattern brush descriptors', () {
    for (final String plugin in ['Adobe ArtOnPath Brush Tool', 'Adobe PatternOnPath Brush Tool']) {
      final String descriptor = '%AI8_BeginPluginObject\n($plugin) (Connected brush)\n(2 / Resource / / / / / 0 0 / 0 0 / 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0) .\n%AI8_EndPluginObject\n';
      final String source = resourceAppearanceSource(kind: .brush, original: appearanceArtworkSource()).replaceFirst('%%EndSetup', '$descriptor%%EndSetup');
      final AiNativeAppearances model = appearanceEditingModel(source: source);
      check(
        () => model.updateSelected(
          appearance: model.styles.first,
          paints: [
            AiNativePaintChange(assignment: appearanceAssignment(model.styles.first, 2, .fillColor), values: [0.7, 0.6, 0.5]),
          ],
          artwork: [resourceEditingReplacement(model, model.uses.first)],
          nameBytes: latin1.encode('Connected resource'),
        ),
      ).throws<UnsupportedError>().has((error) => error.message, 'message').equals('Changed brush artwork requires a qualified dependent brush expansion contract.');
      check(latin1.decode(model.structure.drawing.records.program.bytes)).equals(source);
    }
  });
}
