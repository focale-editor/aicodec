import 'dart:convert';

import 'package:aikit/aikit.dart';
import 'package:checks/checks.dart';
import 'package:test/test.dart';

import 'ai_native_group_creation_test.dart' show groupCreationDrawing;
import 'ai_native_path_creation_test.dart' show createdPath, pathCreationDefinition, pathCreationSource;

/// Captures literal state in either interpretation at each source path.
List<Map<String, List<Object>>> artworkStates(AiNativeDrawing drawing, {required bool native}) {
  final Map<String, List<Object>> current = {};
  final List<Map<String, List<Object>>> result = [];
  for (final AiNativeInstruction item in drawing.items.whereType<AiNativeInstruction>()) {
    if (item.isPrivate && !native) {
      continue;
    }
    final String key = switch (item.operator) {
      'g' || 'Xa' || 'k' => 'fill',
      'G' || 'XA' || 'K' => 'stroke',
      _ => item.operator,
    };
    if (const {'fill', 'stroke', 'A', 'Xw', 'Xy', 'D', 'Ap', 'XR', 'O', 'R', 'J', 'j', 'w', 'M', 'd'}.contains(key)) {
      current[key] = [item.operator, ...item.operands.map((token) => token.number ?? token.lexeme)];
    } else if (item.operator == 'm') {
      result.add(Map.of(current));
    }
  }
  return result;
}

/// Exercises complete appearance changes, identity retention and boundary states.
void main() {
  test('repaints an ordinary path without leaking native or printing state', () {
    final AiNativeDrawing source = groupCreationDrawing(pathCreationSource);
    final AiNativePathDefinition replacement = pathCreationDefinition();
    final AiNativeDrawing changed = source.replacePathArtwork(
      path: source.paths.first,
      artwork: replacement.artwork,
      bounds: replacement.bounds,
      opacity: 0.3,
      hidden: true,
      fillOverprint: true,
      strokeOverprint: true,
    );
    check(changed.paths.length).equals(source.paths.length);
    check(changed.paths.first.paint.operator).equals('b');
    for (final bool native in [false, true]) {
      final List<Map<String, List<Object>>> before = artworkStates(source, native: native);
      final List<Map<String, List<Object>>> after = artworkStates(changed, native: native);
      check(after.first['Xy']!).deepEquals(['Xy', 0, 0.3, 0, 0, 0]);
      check(after.first['Xw']!).deepEquals(['Xw', 1]);
      check(after.first['stroke']!).deepEquals(['XA', 0.6, 0.4, 0.2]);
      check(after.skip(1)).deepEquals(before.skip(1));
    }
    for (int i = 1; i < source.paths.length; i++) {
      check(changed.records.program.bytes.sublist(changed.paths[i].start, changed.paths[i].end)).deepEquals(source.records.program.bytes.sublist(source.paths[i].start, source.paths[i].end));
    }
    check(latin1.decode(source.records.program.bytes)).equals(pathCreationSource);
  });

  test('retains metadata and count conventions across all paint combinations', () {
    final AiNativeDrawing source = groupCreationDrawing(pathCreationSource).createPath(definition: pathCreationDefinition());
    final AiNativePath path = createdPath(source);
    final AiNativeObject object = AiNativeObjects.decode(drawing: source).forSource(path);
    for (final (bool, bool, String) paint in [(false, false, 'n'), (true, false, 'f'), (false, true, 's'), (true, true, 'b')]) {
      final AiNativePathDefinition value = pathCreationDefinition(filled: paint.$1, stroked: paint.$2, space: .cmyk);
      final AiNativeDrawing changed = source.replacePathArtwork(path: path, artwork: value.artwork, bounds: value.bounds);
      final AiNativePath result = createdPath(changed);
      final AiNativeObject retained = AiNativeObjects.decode(drawing: changed).forSource(result);
      check(result.paint.operator).equals(paint.$3);
      check(result.geometry.length).equals(4);
      check(changed.records.program.bytes.sublist(retained.dictionary!.start, retained.dictionary!.end))
          .deepEquals(source.records.program.bytes.sublist(object.dictionary!.start, object.dictionary!.end));
      check(changed.pathTopology(path: result).mask).equals(.none);
    }
  });

  test('rejects an unknown outgoing opacity read by following artwork', () {
    final String text = pathCreationSource.replaceAll(RegExp(r'^(?:%_)?0 0\.[49] 0 0 0 Xy\n', multiLine: true), '');
    final AiNativeDrawing source = groupCreationDrawing(text);
    final AiNativePathDefinition value = pathCreationDefinition();
    check(() => source.replacePathArtwork(path: source.paths.first, artwork: value.artwork, bounds: value.bounds, opacity: 0.3)).throws<UnsupportedError>();
    check(latin1.decode(source.records.program.bytes)).equals(text);
  });

  test('bounds replacement output before returning a new snapshot', () {
    final String text = pathCreationSource;
    final AiNativeDrawing source = groupCreationDrawing(text, limits: AiNativeLimits(maxDecodedBytes: text.length));
    final AiNativePathDefinition value = pathCreationDefinition();
    check(() => source.replacePathArtwork(path: source.paths.first, artwork: value.artwork, bounds: value.bounds)).throws<FormatException>();
    check(latin1.decode(source.records.program.bytes)).equals(text);
  });

  test('rejects foreign handles and invalid complete appearance without mutation', () {
    final AiNativeDrawing source = groupCreationDrawing(pathCreationSource);
    final AiNativePathDefinition value = pathCreationDefinition();
    check(() => source.replacePathArtwork(path: groupCreationDrawing(pathCreationSource).paths.first, artwork: value.artwork, bounds: value.bounds)).throws<ArgumentError>();
    check(() => source.replacePathArtwork(path: source.paths.first, artwork: value.artwork, bounds: value.bounds, opacity: double.nan)).throws<ArgumentError>();
    check(latin1.decode(source.records.program.bytes)).equals(pathCreationSource);
  });
}
