import 'dart:convert';

import 'package:aikit/aikit.dart';
import 'package:checks/checks.dart';
import 'package:test/test.dart';

import 'ai_native_group_creation_test.dart' show groupCreationDrawing;
import 'ai_native_path_artwork_test.dart' show artworkStates;
import 'ai_native_path_creation_test.dart' show createdPath, pathCreationDefinition, pathCreationSource;

/// Explicit values exercise every field without inferring effective defaults.
AiNativeTransparency _value(AiNativeBlendMode mode, AiNativeKnockout knockout) => AiNativeTransparency(blendMode: mode, opacity: .375, isolated: true, knockout: knockout, alphaIsShape: true);

/// Keeps source/native interpretation and printing interpretation independent.
void main() {
  test('creates every native blend and knockout code without converting its tuple', () {
    final AiNativeDrawing source = groupCreationDrawing(pathCreationSource);
    final AiNativePathDefinition template = pathCreationDefinition();
    for (final AiNativeBlendMode mode in AiNativeBlendMode.values) {
      for (final AiNativeKnockout knockout in AiNativeKnockout.values) {
        final AiNativeTransparency value = _value(mode, knockout);
        final AiNativeDrawing result = source.createPath(
          definition: AiNativePathDefinition(
            artwork: template.artwork,
            bounds: template.bounds,
            transparency: value,
            identifierBytes: latin1.encode('Created'),
          ),
        );
        final AiNativePath path = createdPath(result);
        final int index = result.paths.indexOf(path);
        for (final bool native in [false, true]) {
          check(artworkStates(result, native: native)[index]['Xy']!).deepEquals(['Xy', ...value.operands]);
        }
      }
    }
    check(latin1.decode(source.records.program.bytes)).equals(pathCreationSource);
  });

  test('changes complete blending and restores both following interpretations', () {
    final AiNativeDrawing source = groupCreationDrawing(pathCreationSource);
    final AiNativePathDefinition template = pathCreationDefinition();
    final AiNativeTransparency value = _value(.softLight, .inherit);
    final AiNativeDrawing result = source.replacePathArtwork(path: source.paths.first, artwork: template.artwork, bounds: template.bounds, transparency: value);
    for (final bool native in [false, true]) {
      final List<Map<String, List<Object>>> states = artworkStates(result, native: native);
      check(states.first['Xy']!).deepEquals(['Xy', ...value.operands]);
      check(states.skip(1)).deepEquals(artworkStates(source, native: native).skip(1));
    }
    final AiNativeDrawing normal = result.replacePathArtwork(path: result.paths.first, artwork: template.artwork, bounds: template.bounds, opacity: .6);
    check(artworkStates(normal, native: true).first['Xy']!).deepEquals(['Xy', 0, .6, 0, 0, 0]);
  });

  test('rejects competing shorthand and complete transparency inputs', () {
    final AiNativeDrawing source = groupCreationDrawing(pathCreationSource);
    final AiNativePathDefinition template = pathCreationDefinition();
    final AiNativeTransparency value = _value(.multiply, .off);
    check(() => AiNativePathDefinition(artwork: template.artwork, bounds: template.bounds, opacity: .5, transparency: value)).throws<ArgumentError>();
    check(() => source.replacePathArtwork(path: source.paths.first, artwork: template.artwork, bounds: template.bounds, opacity: .5, transparency: value)).throws<ArgumentError>();
    check(latin1.decode(source.records.program.bytes)).equals(pathCreationSource);
  });
}
