import 'dart:convert';

import 'package:checks/checks.dart';
import 'package:illustratorkit/illustratorkit.dart';
import 'package:test/test.dart';

import 'ai_native_document_creation_test.dart' show newDocumentPath, newDocumentPdf, newDocumentRecords, newDocumentSave;

/// Supplies each authored effect with explicit nondefault native parameters.
AiNativeEffect nativeEffect(AiNativeEffectKind kind) => switch (kind) {
  .offset => AiNativeEffect(kind: kind, amount: -2, join: 1, miterLimit: 5),
  .roundCorners => AiNativeEffect(kind: kind, amount: 3),
  .dropShadow => AiNativeEffect(
    kind: kind,
    blur: 2,
    horizontal: 3,
    vertical: -4,
    opacity: .6,
    blendMode: .multiply,
    color: AiColor(space: .rgb, channels: [.2, .3, .4]),
  ),
  .outerGlow => AiNativeEffect(
    kind: kind,
    blur: 4,
    opacity: .7,
    blendMode: .screen,
    color: AiColor(space: .cmyk, channels: [.1, .2, .3, .4]),
  ),
};

/// Creates a whole-owner effect chain without executing any filter.
AiNativeAppearancePartDefinition effectChain(AiNativeEffect effect, {bool visible = true}) => AiNativeAppearancePartDefinition(
  kind: .chain,
  children: [
    if (effect.kind.geometric)
      AiNativeAppearanceChild.create(
        definition: AiNativeAppearancePartDefinition(kind: .nativeEffect, effect: effect, visible: visible),
      ),
    AiNativeAppearanceChild.create(definition: AiNativeAppearancePartDefinition(kind: .conduit)),
    if (!effect.kind.geometric)
      AiNativeAppearanceChild.create(
        definition: AiNativeAppearancePartDefinition(kind: .nativeEffect, effect: effect, visible: visible),
      ),
    AiNativeAppearanceChild.create(
      definition: AiNativeAppearancePartDefinition(
        kind: .blend,
        transparency: AiNativeTransparency(blendMode: .normal, opacity: 1, isolated: false, knockout: .off, alphaIsShape: false),
      ),
    ),
  ],
);

/// Parses serialized source rather than retaining pre-edit handles.
AiNativeAppearances effectModel(AiNativeRecords records) => AiNativeAppearances.decode(
  structure: AiNativeStructure.decode(drawing: AiNativeDrawing.decode(records: records)),
);

/// Checks literal ownership, state isolation and atomic failures across saves.
void main() {
  for (final AiNativeEffectKind kind in AiNativeEffectKind.values) {
    test('authors edits disables and saves ${kind.name} with complete printing', () {
      final AiNativeEffect effect = nativeEffect(kind);
      AiNativeAppearances model = effectModel(newDocumentRecords(blank: true)).createStyle(nameBytes: ascii.encode('Effect'), execution: effectChain(effect));
      final AiNativePathDefinition source = newDocumentPath(0);
      model = model.createPathArtwork(
        definition: AiNativePathDefinition(
          artwork: AiArtworkPath(segments: source.artwork.segments, closed: true),
          bounds: source.bounds,
        ),
        styleNameBytes: ascii.encode('Effect'),
        printingBytes: ascii.encode('u 1 0 0 Xa 10 10 m 30 10 L 30 30 L f U'),
        layer: model.structure.drawing.records.program.layers.single,
      );
      final AiNativeAppearancePart part = model.styles.single.parts.singleWhere((part) => part.kind == .nativeEffect);
      check(part.effect!.realParameters).deepEquals(effect.realParameters);
      final AiNativeAppearanceArtwork owner = model.artworkFor(use: model.uses.single);
      final AiNativeAppearanceState state = model.statesAfterArtwork(artwork: [owner])[owner]!;
      check(effect.color != null && state.native['fill']?.numbers?.toString() == effect.color!.channels.toString()).isFalse();
      final AiPdfDocument saved = newDocumentSave(model.structure.drawing.records, newDocumentPdf(blank: true));
      final AiNativeAppearances reopened = effectModel(AiNativeRecords.decode(program: AiProgram.decode(bytes: AiNativeData.extract(saved).single.bytes)));
      check(reopened.styles.single.parts.singleWhere((part) => part.kind == .nativeEffect).effect!.integerParameters).deepEquals(effect.integerParameters);
      final AiNativeAppearances disabled = reopened.createStyle(nameBytes: ascii.encode('Disabled'), execution: effectChain(effect, visible: false));
      final AiNativeAppearanceArtwork current = disabled.artworkFor(use: disabled.uses.single);
      final AiNativeAppearances changed = disabled.applyStyle(
        appearance: disabled.styles.last,
        artwork: [AiNativeAppearanceReplacement(artwork: current, bytes: ascii.encode('u 1 0 0 Xa 10 10 m 30 10 L 30 30 L f U'), bounds: source.bounds)],
      );
      check(changed.resolve(use: changed.uses.single)!.parts.singleWhere((part) => part.kind == .nativeEffect).visible).equals(false);
      check(changed.artworkFor(use: changed.uses.single).path).isNotNull();
    });
  }
  test('rejects fractional joins unknown fields and incompatible definitions', () {
    final AiNativeAppearances model = effectModel(newDocumentRecords(blank: true)).createStyle(nameBytes: [65], execution: effectChain(nativeEffect(.offset)));
    final String source = latin1.decode(model.structure.drawing.records.program.bytes);
    for (final String changed in [source.replaceFirst('1 /Int (jntp)', '1.5 /Int (jntp)'), source.replaceFirst(RegExp(r'-2(?:\.0)? /Real \(ofst\)'), '-2 /Real (ofst), 1 /Real (Unknown)')]) {
      check(changed == source).isFalse();

      /// Reads modified syntax through a fresh immutable snapshot.
      AiNativeEffect? read() =>
          effectModel(AiNativeRecords.decode(program: AiProgram.decode(bytes: latin1.encode(changed)))).styles.single.parts.singleWhere((part) => part.kind == .nativeEffect).effect;
      if (changed.contains('(Unknown)')) {
        check(read).throws<UnsupportedError>();
      } else {
        check(read).throws<FormatException>();
      }
    }
    check(
      () => AiNativeEffect(
        kind: .outerGlow,
        blur: -1,
        color: AiColor(space: .gray, channels: [0]),
      ),
    ).throws<ArgumentError>();
    check(() => AiNativeAppearancePartDefinition(kind: .conduit, effect: nativeEffect(.offset))).throws<ArgumentError>();
  });
  test('rejects missing or repeated effect-local color state', () {
    final AiNativeAppearances model = effectModel(newDocumentRecords(blank: true)).createStyle(nameBytes: [65], execution: effectChain(nativeEffect(.dropShadow)));
    final String source = latin1.decode(model.structure.drawing.records.program.bytes);
    for (final String replacement in ['', '0 1 0 0 0 Xy 0 1 0 0 0 Xy', '0 .5 0 0 0 Xy']) {
      final String changed = source.replaceFirst('0 1 0 0 0 Xy', replacement);
      final AiNativeAppearances parsed = effectModel(AiNativeRecords.decode(program: AiProgram.decode(bytes: latin1.encode(changed))));
      check(() => parsed.styles.single.parts.singleWhere((part) => part.kind == .nativeEffect).effect).throws<UnsupportedError>();
    }
    final String changed = source.replaceFirst('/FillStyle : 0 O', '/FillStyle :');
    final AiNativeAppearances parsed = effectModel(AiNativeRecords.decode(program: AiProgram.decode(bytes: latin1.encode(changed))));
    check(() => parsed.styles.single.parts.singleWhere((part) => part.kind == .nativeEffect).effect).throws<UnsupportedError>();
    final String alternate = source.replaceFirst(RegExp(r'50(?:\.0)? /Real \(dark\)'), '25 /Real (dark)');
    check(alternate == source).isFalse();
    final AiNativeAppearances darkness = effectModel(AiNativeRecords.decode(program: AiProgram.decode(bytes: latin1.encode(alternate))));
    check(() => darkness.styles.single.parts.singleWhere((part) => part.kind == .nativeEffect).effect).throws<UnsupportedError>();
  });
}
