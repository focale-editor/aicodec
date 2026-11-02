import 'dart:convert';

import 'package:aicodec/aicodec.dart';
import 'package:checks/checks.dart';
import 'package:test/test.dart';

import 'ai_native_appearance_artwork_test.dart' show appearanceArtworkPair, appearanceArtworkReplacement;
import 'ai_native_appearance_editing_test.dart' show appearanceAssignment, appearanceEditingModel, appearanceEditingSource;
import 'ai_native_appearance_nested_styles_test.dart' show nestedAppearanceOwners, nestedAppearanceSource;
import 'ai_native_printing_test.dart' show printingFixture;

/// Complete native clipping trees with explicitly closed or open mask contours.
String clippingAppearanceAuthoring(String variant) {
  final String mask = '%_3 As\n%_0 0 m 10 0 L 10 10 L ${variant == 'open' ? 'H' : '0 0 L h'} W N\n';
  const String second = '%_3 As\n%_20 0 m 30 0 L 30 10 L 20 0 L h W N\n';
  final String masks = switch (variant) {
    'compound' => '%_*u\n$mask$second%_*U\n',
    'leaves' => '%_*u\n%_u\n%_q\n$mask%_Q\n%_q\n$second%_Q\n%_U\n%_*U\n',
    _ => mask,
  };
  return '''%_0 Ae
%_q
$masks${variant == 'nested' ? '%_q\n$second' : ''}%_3 As
%_1 1 m 9 1 L 9 9 L 1 1 L n
%_/ArtDictionary : (Retained child) /String (AIArtName) , ;
${variant == 'nested' ? '%_Q\n' : ''}%_Q
%_/ArtDictionary : (Clipped owner) /String (AIArtName) , ;''';
}

/// Keeps two complete style users with independent native clipping owners.
String clippingAppearanceSource({String variant = 'closed', bool countedPrinting = false}) {
  final String setup = appearanceEditingSource().split('%%EndSetup').first;
  final String pair = appearanceArtworkPair()
      .replaceFirst('%_0 0 m 10 0 L 10 10 L 0 0 L n', clippingAppearanceAuthoring(variant))
      .replaceFirst('0 0 0 1 k\n', '0 0 0 1 k\n${countedPrinting ? '3 As\n' : ''}');
  return '$setup%%EndSetup\n$pair$pair\n%%Trailer\n%%EOF\n';
}

/// Supplies a complete clipped expansion with retained outgoing process paint.
String clippingAppearancePrinting({bool counted = false}) =>
    '''u
q
${counted ? '3 As\n' : ''}0 0 m 10 0 L 10 10 L 0 0 L h W N
0.7 0.6 0.5 Xa
${counted ? '3 As\n' : ''}1 1 m 9 1 L 9 9 L 1 1 L f
2 J 2 j 9 w 17 M [4 2] 1 d
Q
0 0 0 1 k
U''';

/// Changes the outer style together with one supplied clipped group per user.
AiNativeAppearances clippingAppearanceEdit(AiNativeAppearances model, {bool shared = false, String? printing}) {
  final AiNativeAppearance style = model.styles.first;
  final List<AiNativePaintChange> paints = [
    AiNativePaintChange(assignment: appearanceAssignment(style, 2, .fillColor), values: [0.7, 0.6, 0.5]),
  ];
  final List<AiNativeAppearanceReplacement> artwork = [
    for (final int index in [0, if (shared) 1]) appearanceArtworkReplacement(model, index, bytes: printing ?? clippingAppearancePrinting()),
  ];
  return shared
      ? model.updateShared(appearance: style, paints: paints, artwork: artwork)
      : model.updateSelected(appearance: style, paints: paints, artwork: artwork, nameBytes: latin1.encode('Selected clip'));
}

/// Wraps one selected child style in a local contour-state boundary.
String clippingChildSource({bool compound = false, bool persistent = false}) => nestedAppearanceSource()
    .replaceFirst('%_3 As', '%_q\n%_3 As')
    .replaceFirst('%_0 (Child) XW', '%_0 (Child) XW\n%_Q')
    .replaceFirst('%_20 0 m 30 0 L 30 10 L 20 0 L n', '%_20 0 m 30 0 L 30 10 L 20 0 L ${persistent ? 'f' : 's'}')
    .replaceFirst('%_0 Ae\n%_u', '%_0 Ae\n%_${compound ? '*u' : 'u'}')
    .replaceFirst('%_U\n%_/ArtDictionary : (Outer group)', '%_${compound ? '*U' : 'U'}\n%_/ArtDictionary : (Outer group)');

/// Selects the nested stroke width whose nonuniform source cannot be replayed.
AiNativeAppearances clippingChildEdit(AiNativeAppearances model, {bool persistent = false}) {
  final AiNativeAppearance style = model.styles[1];
  final AiNativeAppearanceArtwork owner = model.artworkFor(use: nestedAppearanceOwners(model).first);
  return model.updateSelected(
    appearance: style,
    paints: [
      AiNativePaintChange(assignment: appearanceAssignment(style, persistent ? 2 : 5, persistent ? .fillColor : .strokeWidth), values: persistent ? [0.7, 0.6, 0.5] : [8]),
    ],
    artwork: [
      AiNativeAppearanceReplacement(
        artwork: owner,
        uses: [owner.nestedUses.first],
        bytes: latin1.encode(clippingAppearancePrinting()),
        bounds: AiBoundingBox(left: -20, bottom: -30, right: 120, top: 140),
      ),
    ],
    nameBytes: latin1.encode('Clipped child'),
  );
}

/// Covers authoritative masks, complete host groups and scoped state differences.
void main() {
  test('exposes immutable private mask contours and their effective clipping owners', () {
    for (final String variant in ['closed', 'open', 'compound', 'leaves', 'nested']) {
      final AiNativeAppearances model = appearanceEditingModel(source: clippingAppearanceSource(variant: variant));
      final AiNativeAppearanceArtwork owner = model.artworkFor(use: model.uses.first);
      check(owner.group!.opening.operator).equals('q');
      check(owner.groupContours.map((path) => path.path)).deepEquals(owner.group!.paths);
      check(owner.groupContours.first.mask).equals(variant == 'open' ? .open : .closed);
      check(owner.groupContours.first.clippingGroup).identicalTo(owner.group);
      check(owner.groupContours.first.pointCount!.numbers!.single).equals(3);
      check(owner.groupContours.clear).throws<UnsupportedError>();
      check(owner.groupContours.first.maskControls.clear).throws<UnsupportedError>();
      check(() => model.structure.drawing.pathTopology(path: owner.groupContours.first.path)).throws<UnsupportedError>();
    }
  });

  test('edits selected and shared clipped groups while retaining every private byte', () {
    for (final String variant in ['closed', 'open', 'compound', 'leaves', 'nested']) {
      final AiNativeAppearances before = appearanceEditingModel(source: clippingAppearanceSource(variant: variant));
      for (final bool shared in [false, true]) {
        final AiNativeAppearances after = clippingAppearanceEdit(before, shared: shared);
        check(after.styles).length.equals(shared ? 1 : 2);
        for (final int index in [0, 1]) {
          final AiNativeAppearanceArtwork oldOwner = before.artworkFor(use: before.uses[index]);
          final AiNativeAppearanceArtwork newOwner = after.artworkFor(use: after.uses[index]);
          check(after.structure.drawing.records.program.bytes.sublist(newOwner.authoring.start, newOwner.authoring.end))
              .deepEquals(before.structure.drawing.records.program.bytes.sublist(oldOwner.authoring.start, oldOwner.authoring.end));
          check(newOwner.groupContours.map((path) => path.mask)).deepEquals(oldOwner.groupContours.map((path) => path.mask));
        }
      }
    }
  });

  test('counts explicit mask closure independently of the uppercase paint operator', () {
    final AiNativeAppearances before = appearanceEditingModel(source: clippingAppearanceSource(countedPrinting: true));
    check(() => clippingAppearanceEdit(before, printing: clippingAppearancePrinting(counted: true))).returnsNormally();
    check(() => clippingAppearanceEdit(before, printing: clippingAppearancePrinting(counted: true).replaceFirst('3 As', '4 As'))).throws<UnsupportedError>();
    check(() => clippingAppearanceEdit(before)).throws<UnsupportedError>();
    final AiNativeAppearances invalid = appearanceEditingModel(source: clippingAppearanceSource().replaceFirst('%_3 As', '%_4 As'));
    check(() => invalid.artworkFor(use: invalid.uses.first)).throws<UnsupportedError>();
  });

  test('restores native contour differences at Q without treating persistent color as scoped', () {
    final AiNativeAppearances before = appearanceEditingModel(source: clippingChildSource());
    final AiNativeAppearances after = clippingChildEdit(before);
    check(after.styles.last.parts[5].paints.single.style.assignments.singleWhere((assignment) => assignment.parameter == .strokeWidth).numbers!).deepEquals([8]);
    check(latin1.decode(after.structure.drawing.records.program.bytes)).not((value) => value.contains('%_2 w'));
    check(() => clippingChildEdit(appearanceEditingModel(source: clippingChildSource(persistent: true)), persistent: true)).throws<UnsupportedError>();
    check(() => clippingChildEdit(appearanceEditingModel(source: clippingChildSource(compound: true)))).throws<UnsupportedError>();
  });

  test('retains uncertainty saved before q despite explicit assignments inside it', () {
    final String source = nestedAppearanceSource()
        .replaceFirst('%_0 (Child) XW', '%_0 (Child) XW\n%_q\n%_9 w\n%_Q')
        .replaceFirst('%_20 0 m 30 0 L 30 10 L 20 0 L n', '%_20 0 m 30 0 L 30 10 L 20 0 L s');
    check(() => clippingChildEdit(appearanceEditingModel(source: source))).throws<UnsupportedError>();
  });

  test('rejects malformed detached mixed and unowned mask controls atomically', () {
    final String source = clippingAppearanceSource();
    for (final String invalid in [
      source.replaceFirst('h W N', 'W N'),
      source.replaceFirst('h W N', 'h 1 W N'),
      source.replaceFirst('h W N', 'h W W N'),
      source.replaceFirst('%_q', '%_u').replaceFirst('%_Q', '%_U'),
      source.replaceFirst('10 0 L 10 10 L', '10 0 L h W 10 10 L'),
      source.replaceFirst('%_3 As', '%_W\n%_3 As'),
    ]) {
      final AiNativeAppearances model = appearanceEditingModel(source: invalid);
      check(() => clippingAppearanceEdit(model)).throws<UnsupportedError>();
      check(latin1.decode(model.structure.drawing.records.program.bytes)).equals(invalid);
    }
  });

  test('rejects mixed compound mask roles and ineffective inner clipping leaves', () {
    for (final String invalid in [
      clippingAppearanceSource(variant: 'compound').replaceFirst('h W N', 'N'),
      clippingAppearanceSource(variant: 'leaves').replaceFirst('%_0 Ae\n%_q', '%_0 Ae\n%_u').replaceFirst('%_Q\n%_/ArtDictionary : (Clipped owner)', '%_U\n%_/ArtDictionary : (Clipped owner)'),
      clippingAppearanceSource(variant: 'leaves').replaceFirst('%_*u\n%_u', '%_*u\n%_q').replaceFirst('%_U\n%_*U', '%_Q\n%_*U'),
    ]) {
      check(() => clippingAppearanceEdit(appearanceEditingModel(source: invalid))).throws<UnsupportedError>();
    }
  });

  test('requires supplied clipping groups to retain persistent paint and scoped contour state', () {
    final AiNativeAppearances model = appearanceEditingModel(source: clippingAppearanceSource());
    final String printing = clippingAppearancePrinting();
    for (final String invalid in [
      printing.replaceFirst('0 0 0 1 k', '0 g'),
      printing.replaceFirst('q', 'u').replaceFirst('Q', 'U'),
      printing.replaceFirst('q', '*u\nq').replaceFirst('Q', 'Q\n*U'),
      printing.replaceFirst('h W N', 'W N'),
    ]) {
      check(() => clippingAppearanceEdit(model, printing: invalid)).throws<UnsupportedError>();
    }
  });

  test('attaches clipped live-shape expansions without widening geometry lifecycle ownership', () {
    final AiNativeDrawing before = printingFixture();
    final AiNativeDrawing after = before.withPrintingGroups(
      replacements: [
        AiNativePrintingGroupReplacement(shape: before.liveShapes.first, bytes: latin1.encode(clippingAppearancePrinting()), bounds: AiBoundingBox(left: -20, bottom: -30, right: 120, top: 140)),
      ],
    );
    check(after.liveShapes.first.isBound).isTrue();
    check(after.liveShapes.first.appearancePaths).length.equals(2);
    check(
      () => after.withPrintingGroups(
        replacements: [
          AiNativePrintingGroupReplacement(shape: after.liveShapes.first, bytes: latin1.encode(clippingAppearancePrinting()), bounds: AiBoundingBox(left: -20, bottom: -30, right: 120, top: 140)),
        ],
      ),
    ).returnsNormally();
    check(() => after.duplicateLiveShapes(shapes: [after.liveShapes.first])).throws<UnsupportedError>();
    final AiNativeAppearances styled = appearanceEditingModel();
    final AiNativeAppearances edited = clippingAppearanceEdit(styled);
    check(edited.artworkFor(use: edited.uses.first).liveShape).isNotNull();
    check(edited.artworkFor(use: edited.uses.first).printingGroup.paths).length.equals(2);
  });

  test('supports repeated clipped edits and preserves bounded immutable sources', () {
    final String source = clippingAppearanceSource();
    final AiNativeAppearances before = appearanceEditingModel(source: source);
    final AiNativeAppearances after = clippingAppearanceEdit(before);
    check(() => clippingAppearanceEdit(after, shared: true)).throws<UnsupportedError>();
    final AiNativeAppearance style = after.styles.last;
    check(
      () => after.updateShared(
        appearance: style,
        paints: [
          AiNativePaintChange(assignment: appearanceAssignment(style, 2, .fillColor), values: [0.4, 0.5, 0.6]),
        ],
        artwork: [appearanceArtworkReplacement(after, 0, bytes: clippingAppearancePrinting())],
      ),
    ).returnsNormally();
    final AiNativeAppearances bounded = appearanceEditingModel(
      source: source,
      limits: AiNativeLimits(maxDecodedBytes: after.structure.drawing.records.program.bytes.length - 1),
    );
    check(() => clippingAppearanceEdit(bounded)).throws<FormatException>();
    check(latin1.decode(bounded.structure.drawing.records.program.bytes)).equals(source);
  });
}
