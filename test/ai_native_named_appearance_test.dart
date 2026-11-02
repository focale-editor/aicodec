import 'dart:convert';

import 'package:aicodec/aicodec.dart';
import 'package:checks/checks.dart';
import 'package:test/test.dart';

import 'ai_native_appearance_artwork_test.dart' show appearanceArtworkReplacement;
import 'ai_native_appearance_editing_test.dart' show appearanceEditingModel;
import 'ai_native_appearance_groups_test.dart' show appearanceGroupsSource;
import 'ai_native_inks_test.dart' show inkCmyk, inkModel, inkPrinting;
import 'ai_native_opacity_masks_test.dart' show opacityMaskSource;

/// Exact named alternatives, including a legacy non-UTF8 byte identity.
AiNativeNamedColor _ink(AiNativeNamedColorKind kind) => AiNativeNamedColor(
  kind: kind,
  components: kind == .customRgb
      ? [.2, .4, .6]
      : kind == .namedRgb
      ? [.1, .2, .3, .4, .2, .4, .6]
      : [.1, .2, .3, .4],
  nameBytes: [67, 97, 102, 233],
  tint: .3,
);

/// Reads effective literal colors at a contour independently of the edit helpers.
Map<String, List<String>> _colors(AiNativeAppearances model, AiNativePath path) {
  final Map<String, List<String>> result = {};
  for (final AiNativeInstruction command in model.structure.drawing.items.whereType<AiNativeInstruction>()) {
    if (command.start >= path.start) {
      break;
    }
    final String? channel = switch (command.operator) {
      'g' || 'k' || 'Xa' || 'x' || 'Xx' || 'Xs' || 'Xz' => 'fill',
      'G' || 'K' || 'XA' || 'X' || 'XX' || 'XS' || 'XZ' => 'stroke',
      _ => null,
    };
    if (channel != null) {
      result[channel] = [command.operator, ...command.operands.map((token) => token.lexeme)];
    }
  }
  return result;
}

/// Authored private paints keep named semantics and following source state.
void main() {
  for (final AiNativeNamedColorKind kind in AiNativeNamedColorKind.values) {
    test('authors ${kind.name} fill and stroke appearance parts', () {
      final AiNativeAppearances source = appearanceEditingModel();
      final AiNativeNamedColor ink = _ink(kind);
      final AiNativeAppearances result = source.createStyle(
        nameBytes: ascii.encode('Named'),
        execution: AiNativeAppearancePartDefinition(
          kind: .stack,
          children: [
            for (final AiNativeAppearancePartKind role in [AiNativeAppearancePartKind.fill, AiNativeAppearancePartKind.stroke])
              AiNativeAppearanceChild.create(
                definition: AiNativeAppearancePartDefinition(kind: role, namedColor: ink),
              ),
          ],
        ),
      );
      final List<AiNativeNamedColor> colors = [
        for (final AiNativeAppearancePart part in result.styles.last.parts)
          for (final AiNativeAppearancePaint paint in part.paints)
            for (final AiNativePaintAssignment assignment in paint.style.assignments)
              if (assignment.namedColor != null) assignment.namedColor!,
      ];
      check(colors).length.equals(2);
      for (final AiNativeNamedColor color in colors) {
        check(color.kind).equals(kind);
        check(color.components).deepEquals(ink.components);
        check(color.nameBytes).deepEquals(ink.nameBytes);
        check(color.tint).equals(.3);
      }
      check(source.styles).length.equals(1);
    });
  }

  test('globally redefines mask Art colors through original source positions', () {
    final String source = opacityMaskSource().replaceFirst('0.3 g', '0 0 0 1 (Mask ink) 0.4 x');
    final AiNativeInks model = inkModel(source);
    check(model.inks).length.equals(1);
    check(model.inks.single.paints).length.equals(1);
    final AiNativeInks revised = model.redefine(ink: model.inks.single, cmyk: inkCmyk(), artwork: inkPrinting(model));
    final AiNativeNamedColor color = AiNativeNamedColor.decode(instruction: revised.inks.single.paints.single)!;
    check(color.components).deepEquals(inkCmyk().channels);
    check(color.tint).equals(.4);
    check(latin1.decode(revised.printingOwners.first.opacityMasks.single.artworkBytes)).contains('0.2 0.3 0.4 0.5 (Mask ink) 0.4 x');
    check(latin1.decode(model.records.program.bytes)).equals(source);
    final AiNativeInks unknown = inkModel(source.replaceFirst('0.4 x', '0.4 x 9 UnknownMaskPaint'));
    check(unknown.inks).isEmpty();
  });

  test('rejects conflicting named and process paint inputs', () {
    final AiNativeNamedColor ink = _ink(.legacyCmyk);
    check(
      () => AiNativeAppearancePartDefinition(
        kind: .fill,
        namedColor: ink,
        colors: [
          AiColor(space: .gray, channels: [.5]),
        ],
      ),
    ).throws<ArgumentError>();
    check(() => AiNativeAppearancePartDefinition(kind: .conduit, namedColor: ink)).throws<ArgumentError>();
    check(() => AiNativeAppearancePartDefinition(kind: .fill)).throws<ArgumentError>();
  });

  test('replaces named private fill and stroke while restoring a following child', () {
    final AiNativeAppearances source = appearanceEditingModel(source: appearanceGroupsSource());
    final AiNativeAppearanceArtwork owner = source.artworkFor(use: source.uses.first);
    final AiNativeNamedColor ink = _ink(.legacyCmyk);
    final AiNativeAppearances result = source.replaceArtworkPaths(
      changes: [
        AiNativeAppearancePathChange(
          path: owner.group!.paths.first,
          artwork: AiArtworkPath(segments: owner.group!.paths.first.segments, closed: true),
          namedFill: ink,
          namedStroke: ink,
        ),
      ],
      artwork: [appearanceArtworkReplacement(source, 0)],
    );
    final AiNativeAppearanceArtwork updated = result.artworkFor(use: result.uses.first);
    check(_colors(result, updated.group!.paths.last)).deepEquals(_colors(source, owner.group!.paths.last));
    check(updated.group!.paths.first.paint.operator).equals('b');
    final List<AiNativeNamedColor> colors = [
      for (final AiNativeInstruction instruction in result.structure.drawing.items.whereType<AiNativeInstruction>())
        if (AiNativeNamedColor.decode(instruction: instruction) case final AiNativeNamedColor named) named,
    ];
    check(colors).length.equals(2);
    check(colors.map((value) => value.tint)).deepEquals([.3, .3]);
    check(updated.group!.paths.last.segments.map((segment) => segment.coordinates)).deepEquals(owner.group!.paths.last.segments.map((segment) => segment.coordinates));
    final AiNativeInk resource = AiNativeInks.decode(records: result.structure.drawing.records).inks.single;
    check(resource.nameBytes).deepEquals(ink.nameBytes);
    check(resource.paints).length.equals(2);
  });
}
