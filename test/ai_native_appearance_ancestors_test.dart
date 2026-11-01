import 'dart:convert';

import 'package:aikit/aikit.dart';
import 'package:checks/checks.dart';
import 'package:test/test.dart';

import 'ai_native_appearance_artwork_test.dart' show appearanceArtworkReplacement, appearanceArtworkSource, appearanceArtworkState;
import 'ai_native_appearance_clipping_test.dart' show clippingAppearanceSource;
import 'ai_native_appearance_editing_test.dart' show appearanceAssignment, appearanceEditingModel, appearanceEditingSource;

/// A counted ordinary clipping mask, distinct from both appearance representations.
const String appearanceAncestorMask = '3 As\n-10 -10 m 40 -10 L 40 40 L -10 -10 L h W N\n';

/// Adds retained enclosing masks around complete pairs, leaving their bytes intact.
String appearanceAncestorsSource({String variant = 'ordinary', String tail = ''}) {
  final String source = variant == 'live'
      ? appearanceEditingSource()
      : variant == 'private'
      ? clippingAppearanceSource()
      : appearanceArtworkSource(metadata: true);
  final AiNativeAppearances model = appearanceEditingModel(source: source);
  String result = source;
  for (final AiNativeResourceUse use in model.uses.reversed) {
    final AiNativeAppearanceArtwork owner = model.artworkFor(use: use);
    final String mask = variant == 'compound' ? '*u\n$appearanceAncestorMask$appearanceAncestorMask*U\n' : appearanceAncestorMask;
    result = result.replaceRange(
      owner.start,
      owner.end,
      '$appearanceArtworkState\nq\n$mask${variant == 'nested' ? 'q\n$mask' : ''}${source.substring(owner.start, owner.end)}\n${variant == 'nested' ? 'Q\n' : ''}Q\n'
      '%_/ArtDictionary : (Retained clip) /String (AIArtName) , ;\n$tail',
    );
  }
  return result;
}

/// Changes a nonuniform stroke field whose original state cannot be replayed.
AiNativeAppearances appearanceAncestorsEdit(AiNativeAppearances model, {bool shared = false, bool color = false}) {
  final AiNativeAppearance style = model.styles.first;
  final List<AiNativePaintChange> paints = [
    AiNativePaintChange(assignment: appearanceAssignment(style, color ? 2 : 5, color ? .fillColor : .strokeWidth), values: color ? [0.7, 0.6, 0.5] : [8]),
  ];
  final List<AiNativeAppearanceReplacement> artwork = [
    for (final int index in [0, if (shared) 1]) appearanceArtworkReplacement(model, index),
  ];
  return shared
      ? model.updateShared(appearance: style, paints: paints, artwork: artwork)
      : model.updateSelected(appearance: style, paints: paints, artwork: artwork, nameBytes: latin1.encode('Selected ancestor'));
}

/// Checks parent ownership, scoped dependencies and independent lifecycle limits.
void main() {
  test('edits ordinary live and private-group pairs under retained clipping ancestors', () {
    for (final String variant in ['ordinary', 'live', 'private', 'nested', 'compound']) {
      final String source = appearanceAncestorsSource(variant: variant, tail: '50 0 m 60 0 L 60 10 L s\n');
      final AiNativeAppearances before = appearanceEditingModel(source: source);
      for (final bool shared in [false, true]) {
        final AiNativeAppearances after = appearanceAncestorsEdit(before, shared: shared);
        check(after.styles).length.equals(shared ? 1 : 2);
        check(after.uses).length.equals(2);
        for (final int index in [0, 1]) {
          final AiNativeAppearanceArtwork oldOwner = before.artworkFor(use: before.uses[index]);
          final AiNativeAppearanceArtwork newOwner = after.artworkFor(use: after.uses[index]);
          check(after.structure.drawing.records.program.bytes.sublist(newOwner.authoring.start, newOwner.authoring.end))
              .deepEquals(before.structure.drawing.records.program.bytes.sublist(oldOwner.authoring.start, oldOwner.authoring.end));
        }
        check(latin1.decode(after.structure.drawing.records.program.bytes)).not((value) => value.contains('%_2 w'));
      }
      check(latin1.decode(before.structure.drawing.records.program.bytes)).equals(source);
    }
  });

  test('keeps persistent fill differences visible after the outer Q', () {
    final AiNativeAppearances before = appearanceEditingModel(source: appearanceAncestorsSource(tail: '50 0 m 60 0 L 60 10 L f\n'));
    check(() => appearanceAncestorsEdit(before, color: true)).throws<UnsupportedError>();
  });

  test('restores saved uncertainty even when an inner assignment clears current differences', () {
    final String source = appearanceAncestorsSource().replaceFirst('1 (Shared) XW', '1 (Shared) XW\nq\n9 w\nQ\n50 0 m 60 0 L 60 10 L s');
    check(() => appearanceAncestorsEdit(appearanceEditingModel(source: source))).throws<UnsupportedError>();
  });

  test('tracks intervening scopes opened with equal state before a later shared use', () {
    final String source = appearanceAncestorsSource(variant: 'nested', tail: 'q\n7 w\nQ\n50 0 m 60 0 L 60 10 L s\n');
    check(() => appearanceAncestorsEdit(appearanceEditingModel(source: source), shared: true)).returnsNormally();
  });

  test('does not authorize geometry lifecycle inside appearance clipping parents', () {
    final AiNativeAppearances before = appearanceEditingModel(source: appearanceAncestorsSource(variant: 'live'));
    final AiNativeDrawing drawing = before.structure.drawing;
    check(() => drawing.duplicateLiveShapes(shapes: [drawing.liveShapes.first])).throws<UnsupportedError>();
    check(() => drawing.removeLiveShapes(shapes: [drawing.liveShapes.first])).throws<UnsupportedError>();
  });

  test('rejects private compound malformed and effect-owning enclosing scopes', () {
    final String source = appearanceAncestorsSource();
    for (final String invalid in [
      source.replaceFirst('\nq\n', '\n1 q\n'),
      source.replaceFirst('\nq\n', '\n%_q\n').replaceFirst('\nQ\n', '\n%_Q\n'),
      source.replaceFirst('\nq\n', '\n*u\n').replaceFirst('\nQ\n', '\n*U\n'),
      source.replaceFirst('(Retained clip) /String (AIArtName)', '1 /Int (UnknownEffect)'),
      source.replaceFirst('(Retained clip) /String (AIArtName) , ;', '(Retained clip) /String (AIArtName) , ;\n1 (Shared) XW'),
    ]) {
      final AiNativeAppearances model = appearanceEditingModel(source: invalid);
      check(() => appearanceAncestorsEdit(model)).throws<UnsupportedError>();
      check(latin1.decode(model.structure.drawing.records.program.bytes)).equals(invalid);
    }
  });

  test('checks whole-source masks and opaque references for shared changes', () {
    final String source = appearanceAncestorsSource(variant: 'compound');
    for (final String invalid in [
      source.replaceFirst('h W N', 'W N'),
      source.replaceFirst('h W N', 'N').replaceFirst('3 As\n', ''),
      source.replaceFirst('3 As', '4 As'),
      source.replaceFirst('%%Trailer', '17 FutureReference\n%%Trailer'),
    ]) {
      final AiNativeAppearances model = appearanceEditingModel(source: invalid);
      if (invalid.contains('4 As')) {
        check(() => appearanceAncestorsEdit(model, shared: true)).throws<FormatException>();
      } else {
        check(() => appearanceAncestorsEdit(model, shared: true)).throws<UnsupportedError>();
      }
    }
  });

  test('rebinds saved owners and enforces output limits for enclosing clips', () {
    final String source = appearanceAncestorsSource();
    final AiNativeAppearances before = appearanceEditingModel(source: source);
    final AiNativeAppearances after = appearanceAncestorsEdit(before, shared: true);
    check(() => appearanceAncestorsEdit(after, shared: true)).returnsNormally();
    final AiNativeAppearances bounded = appearanceEditingModel(
      source: source,
      limits: AiNativeLimits(maxDecodedBytes: after.structure.drawing.records.program.bytes.length - 1),
    );
    check(() => appearanceAncestorsEdit(bounded, shared: true)).throws<FormatException>();
    check(latin1.decode(bounded.structure.drawing.records.program.bytes)).equals(source);
  });
}
