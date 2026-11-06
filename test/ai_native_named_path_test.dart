import 'dart:convert';

import 'package:checks/checks.dart';
import 'package:illustratorkit/illustratorkit.dart';
import 'package:test/test.dart';

import 'ai_native_group_creation_test.dart' show groupCreationDrawing;
import 'ai_native_path_creation_test.dart' show pathCreationDefinition, pathCreationSource;

/// Explicit native alternatives with no tint interpretation by the serializer.
AiNativeNamedColor pathInk(AiNativeNamedColorKind kind, {double tint = .25}) => AiNativeNamedColor(
  kind: kind,
  components: kind == .customRgb
      ? [.2, .4, .6]
      : kind == .namedRgb
      ? [.1, .2, .3, .4, .2, .4, .6]
      : [.1, .2, .3, .4],
  nameBytes: latin1.encode('Ink (one)'),
  tint: tint,
);

/// Literal fill/stroke state at each contour in either source interpretation.
List<List<String?>> namedPathStates(AiNativeDrawing drawing, {bool private = true}) {
  String? fill;
  String? stroke;
  final List<List<String?>> states = [];
  for (final AiNativeInstruction command in drawing.items.whereType<AiNativeInstruction>()) {
    if (!private && command.isPrivate) {
      continue;
    }
    final String paint = '${command.operator} ${command.operands.map((value) => value.lexeme).join(' ')}';
    if (const {'g', 'Xa', 'k', 'x', 'Xx', 'Xs', 'Xz'}.contains(command.operator)) {
      fill = paint;
    } else if (const {'G', 'XA', 'K', 'X', 'XX', 'XS', 'XZ'}.contains(command.operator)) {
      stroke = paint;
    } else if (command.operator == 'm') {
      states.add([fill, stroke]);
    }
  }
  return states;
}

/// Checks named authoring, local repainting and outgoing state preservation.
void main() {
  for (final AiNativeNamedColorKind kind in AiNativeNamedColorKind.values) {
    test('creates and replaces ${kind.name} path paints without leaking sibling state', () {
      final AiNativeDrawing source = groupCreationDrawing(pathCreationSource);
      final AiNativePathDefinition base = pathCreationDefinition(filled: false, stroked: false);
      final AiNativePathDefinition definition = AiNativePathDefinition(artwork: base.artwork, bounds: base.bounds, namedFill: pathInk(kind), namedStroke: pathInk(kind, tint: .75));
      final AiNativeDrawing created = source.createPath(definition: definition);
      check(created.paths.length).equals(source.paths.length + 1);
      check(created.paths.last.paint.operator).equals('b');
      for (final bool private in [false, true]) {
        check(namedPathStates(created, private: private).take(source.paths.length)).deepEquals(namedPathStates(source, private: private));
      }
      final AiNativeDrawing replaced = source.replacePathArtwork(
        path: source.paths.first,
        artwork: base.artwork,
        bounds: base.bounds,
        namedFill: definition.namedFill,
        namedStroke: definition.namedStroke,
      );
      check(replaced.paths.first.paint.operator).equals('b');
      for (final bool private in [false, true]) {
        check(namedPathStates(replaced, private: private).skip(1)).deepEquals(namedPathStates(source, private: private).skip(1));
      }
      final List<AiNativeNamedColor> paints = replaced.items
          .whereType<AiNativeInstruction>()
          .map((command) => AiNativeNamedColor.decode(instruction: command))
          .whereType<AiNativeNamedColor>()
          .toList();
      check(paints.map((paint) => paint.kind)).deepEquals([kind, kind]);
      check(paints.map((paint) => paint.tint)).deepEquals([.25, .75]);
      check(paints.every((paint) => latin1.decode(paint.nameBytes) == 'Ink (one)')).isTrue();
      check(latin1.decode(source.records.program.bytes)).equals(pathCreationSource);
    });
  }

  test('rejects conflicting process and named channels instead of selecting one', () {
    final AiNativePathDefinition base = pathCreationDefinition();
    check(() => AiNativePathDefinition(artwork: base.artwork, bounds: base.bounds, namedFill: pathInk(.legacyCmyk))).throws<ArgumentError>();
    check(() => AiNativePathDefinition(artwork: base.artwork, bounds: base.bounds, namedStroke: pathInk(.customRgb))).throws<ArgumentError>();
  });

  test('selects fill stroke and unpainted terminators from the named channels', () {
    final AiNativeDrawing source = groupCreationDrawing(pathCreationSource);
    final AiNativePathDefinition base = pathCreationDefinition(filled: false, stroked: false);
    for (final (bool fill, bool stroke, String operator) in [(true, false, 'f'), (false, true, 's'), (false, false, 'n')]) {
      final AiNativeDrawing result = source.createPath(
        definition: AiNativePathDefinition(artwork: base.artwork, bounds: base.bounds, namedFill: fill ? pathInk(.customRgb) : null, namedStroke: stroke ? pathInk(.legacyCmyk) : null),
      );
      check(result.paths.last.paint.operator).equals(operator);
    }
  });
}
