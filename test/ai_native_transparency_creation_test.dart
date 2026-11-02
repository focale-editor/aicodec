import 'dart:convert';

import 'package:aicodec/aicodec.dart';
import 'package:checks/checks.dart';
import 'package:test/test.dart';

import 'ai_native_appearance_artwork_test.dart' show appearanceArtworkReplacement;
import 'ai_native_appearance_editing_test.dart' show appearanceEditingModel;
import 'ai_native_appearance_graph_test.dart' show retainAppearanceParts;
import 'ai_native_transparency_test.dart' show transparencyPrinting, transparencySource, transparencyValue;

/// Creates an explicit whole-owner blend using the existing part transaction.
AiNativeAppearances createTransparency(AiNativeAppearances model, {bool shared = false, AiNativeAppearancePartKind kind = .blend}) {
  final AiNativeAppearance style = model.styles.single;
  final List<AiNativeAppearancePartChange> parts = [
    AiNativeAppearancePartChange(
      part: style.parts.first,
      children: [
        ...retainAppearanceParts(style, style.parts.first.childIndices.where((index) => style.parts[index].kind != .blend)),
        AiNativeAppearanceChild.create(
          definition: AiNativeAppearancePartDefinition(
            kind: kind,
            transparency: transparencyValue(),
            colors: [
              if (kind != .blend) AiColor(space: .gray, channels: [0.5]),
            ],
          ),
        ),
      ],
    ),
  ];
  final List<AiNativeAppearanceReplacement> artwork = [
    appearanceArtworkReplacement(model, 0, bytes: transparencyPrinting),
    if (shared) appearanceArtworkReplacement(model, 1, bytes: transparencyPrinting),
  ];
  return shared
      ? model.updateShared(appearance: style, parts: parts, artwork: artwork)
      : model.updateSelected(appearance: style, parts: parts, artwork: artwork, nameBytes: latin1.encode('New transparency'));
}

/// Exercises new blend parts without recreating the existing transparency API.
void main() {
  test('creates selected and shared object/group transparency with every explicit flag', () {
    for (final bool grouped in [false, true]) {
      for (final bool shared in [false, true]) {
        final AiNativeAppearances model = appearanceEditingModel(source: transparencySource(grouped: grouped));
        final AiNativeAppearances changed = createTransparency(model, shared: shared);
        final AiNativeAppearancePart blend = changed.styles.last.parts.singleWhere((part) => part.kind == .blend);
        check(blend.paints.single.style.assignments.single.transparency!.operands).deepEquals(transparencyValue().operands);
        check(changed.styles).length.equals(shared ? 1 : 2);
        check(changed.resolve(use: changed.uses.last)).identicalTo(shared ? changed.styles.last : changed.styles.first);
      }
    }
  });

  test('removes a blend part then creates transparency when no blend remains', () {
    final AiNativeAppearances model = appearanceEditingModel(source: transparencySource());
    final AiNativeAppearance style = model.styles.single;
    final AiNativeAppearances removed = model.updateShared(
      appearance: style,
      parts: [
        AiNativeAppearancePartChange(part: style.parts.first, children: retainAppearanceParts(style, style.parts.first.childIndices.where((index) => style.parts[index].kind != .blend))),
      ],
      artwork: [
        appearanceArtworkReplacement(model, 0, bytes: transparencyPrinting),
        appearanceArtworkReplacement(model, 1, bytes: transparencyPrinting),
      ],
    );
    check(removed.styles.single.parts.where((part) => part.kind == .blend)).isEmpty();
    final AiNativeAppearances created = createTransparency(removed);
    check(created.styles.last.parts.singleWhere((part) => part.kind == .blend).paints.single.style.assignments.single.transparency!.operands).deepEquals(transparencyValue().operands);
  });

  test('creates fill and stroke blending without conflating it with whole-object blending', () {
    for (final AiNativeAppearancePartKind kind in [AiNativeAppearancePartKind.fill, AiNativeAppearancePartKind.stroke]) {
      final AiNativeAppearances model = appearanceEditingModel(source: transparencySource());
      final AiNativeAppearances changed = createTransparency(model, kind: kind);
      final AiNativeAppearancePart part = changed.styles.last.parts.last;
      check(part.kind).equals(kind);
      check(part.paints.single.style.assignments.singleWhere((assignment) => assignment.parameter == .transparency).transparency!.operands).deepEquals(transparencyValue().operands);
    }
  });

  test('requires full blend settings and rejects contradictory opacity or unrelated kinds', () {
    check(() => AiNativeAppearancePartDefinition(kind: .blend)).throws<ArgumentError>();
    check(() => AiNativeAppearancePartDefinition(kind: .blend, opacity: 0.5, transparency: transparencyValue())).throws<ArgumentError>();
    check(() => AiNativeAppearancePartDefinition(kind: .stack, transparency: transparencyValue())).throws<ArgumentError>();
    check(
      () => AiNativeAppearancePartDefinition(
        kind: .fill,
        colors: [
          AiColor(space: .gray, channels: [0.5]),
        ],
        opacity: 0.5,
        transparency: transparencyValue(),
      ),
    ).throws<ArgumentError>();
  });
}
