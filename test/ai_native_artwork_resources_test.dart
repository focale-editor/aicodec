import 'dart:convert';

import 'package:aicodec/aicodec.dart';
import 'package:checks/checks.dart';
import 'package:test/test.dart';

import 'ai_native_appearance_editing_test.dart' show appearanceEditingModel, appearanceEditingSource;
import 'ai_native_artboard_brushes_test.dart' show artboardBrush, artboardBrushRaster;
import 'ai_native_artboard_palette_test.dart' show artboardPaletteGradient;
import 'ai_native_artboard_patterns_test.dart' show artboardPattern;
import 'ai_native_artboard_references_test.dart' show artboardSimpleStyle;
import 'ai_native_artboard_symbols_test.dart' show artboardSymbol;

/// Retains equal names in separate namespaces and two independent body users.
String artworkResourcesSource({String? resources}) => appearanceEditingSource().replaceFirst(
  '%%EndSetup',
  '$artboardPaletteGradient$artboardSimpleStyle${resources ?? '$artboardPattern$artboardSymbol'}%%EndSetup',
);

/// Reads resource ownership against the original global reference snapshot.
AiNativeArtworkResources artworkResourcesModel({String? source, AiNativeLimits limits = const AiNativeLimits()}) =>
    appearanceEditingModel(source: source ?? artworkResourcesSource(), limits: limits).artworkResources;

/// Checks exact retained data without making declarations independently editable.
void main() {
  test('binds pattern symbol and brush declarations in source order without conflating names', () {
    final String brush = artboardSymbol.replaceFirst('%AI14_BeginSymbol', '%AI8_BeginBrushPattern').replaceFirst('%AI10_EndSymbol', '%AI8_EndBrushPattern');
    final AiNativeArtworkResources model = artworkResourcesModel(source: artworkResourcesSource(resources: '$artboardPattern$artboardSymbol$brush'));
    check(model.resources.map((resource) => resource.kind)).deepEquals([AiNativeArtworkResourceKind.pattern, AiNativeArtworkResourceKind.symbol, AiNativeArtworkResourceKind.brush]);
    check(model.resources.map((resource) => latin1.decode(resource.nameBytes))).deepEquals(['board-0', 'board-0', 'board-0']);
    check(model.resources.first.bounds!.right).equals(10);
    check(model.resources[1].bounds).isNull();
    for (final AiNativeArtworkResource resource in model.resources) {
      check(resource.paths).isNotEmpty();
      check(resource.groups).isNotEmpty();
      check(resource.metadata).isNotEmpty();
      for (final AiNativeResourceUse use in resource.uses) {
        check(model.forUse(use: use)).identicalTo(resource);
        check(model.structure.resourceUses).contains(use);
      }
    }
    check(model.resources.first.gradients).length.equals(1);
    check(model.resources[1].uses.single.resolution).equals(AiNativeResourceResolution.resolved);
    check(model.forUse(use: model.structure.resourceUses.last)).isNull();
  });

  test('preserves unknown commands fields annotations and complete source intervals', () {
    final String symbol = artboardSymbol
        .replaceFirst('0 A', '%AI99_Unknown: retained\n17 FutureCommand\n%%BeginData: 4\nABCD\n%%EndData\n0 A')
        .replaceFirst('%_(0.4)', '%_(opaque) /String (FutureField) ,\n%_(0.4)');
    final String source = artworkResourcesSource(resources: symbol);
    final AiNativeArtworkResources model = artworkResourcesModel(source: source);
    final AiNativeArtworkResource resource = model.resources.single;
    check(resource.items.whereType<AiNativeInstruction>().where((item) => item.operator == 'FutureCommand').single.numbers!).deepEquals([17]);
    check(resource.tokens.any((token) => token.lexeme == '%AI99_Unknown: retained')).isTrue();
    check(resource.metadata.first['FutureField']!.text()).equals('opaque');
    final AiToken binary = resource.items.whereType<AiNativeToken>().single.token;
    check(binary.kind).equals(AiTokenKind.data);
    check(source.substring(binary.start, binary.end)).equals('ABCD');
    check(latin1.decode(model.structure.drawing.records.program.bytes.sublist(resource.start, resource.end))).equals(symbol.trimRight());
    check(latin1.decode(model.structure.drawing.records.program.bytes)).equals(source);
  });

  test('retains duplicate conditional and unresolved resources without choosing a definition', () {
    const String conditional = '%AI17_Begin_Content_if_version_gt:24 4\n$artboardSymbol%AI17_Alternate_Content\n$artboardSymbol%AI17_End_Versioned_Content\n';
    final AiNativeArtworkResources model = artworkResourcesModel(source: artworkResourcesSource(resources: '$conditional$artboardSymbol').replaceFirst(artboardSimpleStyle, ''));
    check(model.resources).length.equals(3);
    check(model.resources[0].versions.single.branch).equals(AiNativeVersionBranch.newer);
    check(model.resources[1].versions.single.branch).equals(AiNativeVersionBranch.older);
    check(model.resources[2].versions).isEmpty();
    for (final AiNativeArtworkResource resource in model.resources) {
      check(resource.uses.single.resolution).equals(AiNativeResourceResolution.missing);
      check(model.forUse(use: resource.uses.single)).identicalTo(resource);
    }
    final String private = '${artboardSymbol.replaceAll('%_', '').split('\n').where((line) => line.isNotEmpty).map((line) => '%_$line').join('\n')}\n';
    final AiNativeArtworkResource privateResource = artworkResourcesModel(source: artworkResourcesSource(resources: private)).resources.single;
    check(privateResource.isPrivate).isTrue();
    check(privateResource.paths.single.isPrivate).isTrue();
    check(privateResource.uses.single.instruction.isPrivate).isTrue();
  });

  test('ignores wrapper lookalikes in executable procedures strings and embedded documents', () {
    const String fake = '%AI14_BeginSymbol\n(Fake)\n%AI10_EndSymbol\n';
    final String source = artworkResourcesSource(resources: '{\n$fake} pop\n(\n$fake) pop\n%%BeginDocument: embedded\n$fake%%EndDocument\n$artboardSymbol');
    final AiNativeArtworkResources model = artworkResourcesModel(source: source);
    check(model.resources).length.equals(1);
    check(latin1.decode(model.resources.single.nameBytes)).equals('board-0');
    final String procedure = artboardSymbol.replaceFirst('0 A', '{\n%AI17_Begin_Content_if_version_gt:24 4\n0 A\n%AI17_End_Versioned_Content\n} pop\n0 A');
    final AiNativeArtworkResource local = artworkResourcesModel(source: artworkResourcesSource(resources: procedure)).resources.single;
    check(local.items.whereType<AiNativeVersionComment>()).isEmpty();
    check(local.items.whereType<AiNativeInstruction>().where((item) => item.operator == 'pop')).length.equals(1);
  });

  test('retains immutable cached local topology and rejects foreign reference handles', () {
    final AiNativeArtworkResources model = artworkResourcesModel();
    final AiNativeArtworkResource resource = model.resources.first;
    check(resource.items).identicalTo(resource.items);
    check(resource.paths.clear).throws<UnsupportedError>();
    check(resource.groups.clear).throws<UnsupportedError>();
    check(resource.tokens.clear).throws<UnsupportedError>();
    check(resource.metadata.clear).throws<UnsupportedError>();
    check(resource.uses.clear).throws<UnsupportedError>();
    check(model.resources.clear).throws<UnsupportedError>();
    check(() => resource.nameBytes[0] = 0).throws<UnsupportedError>();
    check(() => model.forUse(use: artworkResourcesModel().resources.first.uses.single)).throws<ArgumentError>();
    check(() => model.structure.drawing.duplicatePaths(paths: [resource.paths.first])).throws<ArgumentError>();
  });

  test('rejects incomplete overlapping mismatched and malformed declaration headers', () {
    for (final String resource in [
      artboardSymbol.replaceFirst('%AI10_EndSymbol', ''),
      artboardSymbol.replaceFirst('%AI10_EndSymbol', '%AI3_EndPattern'),
      artboardSymbol.replaceFirst('(board-0)\n', '/board-0\n'),
      artboardSymbol.replaceFirst('(board-0)\n', '(board-0)\n%AI14_BeginSymbol\n(nested)\n'),
      artboardPattern.replaceFirst('BeginPattern: (board-0)', 'BeginPattern: (different)'),
      artboardPattern.replaceFirst('(board-0) 0 0 10 10', '(board-0) 0 0 0 10'),
      artboardPattern.replaceFirst('(board-0) 0 0 10 10', '(board-0) 0 0 1e100 10'),
      artboardPattern.replaceFirst('\nE\n', '\n'),
    ]) {
      check(() => artworkResourcesModel(source: artworkResourcesSource(resources: resource))).throws<FormatException>();
    }
  });

  test('keeps empty resources and original byte token and topology limits', () {
    const String empty = '%AI14_BeginSymbol\n()\n%AI10_EndSymbol\n%AI3_BeginPattern: ()\n() 0 0 1 1 E\n%AI3_EndPattern\n';
    final AiNativeArtworkResources model = artworkResourcesModel(source: artworkResourcesSource(resources: empty));
    check(model.resources).length.equals(2);
    check(model.resources.every((resource) => resource.paths.isEmpty && resource.items.isEmpty)).isTrue();
    final String source = artworkResourcesSource();
    check(
      () => artworkResourcesModel(
        source: source,
        limits: AiNativeLimits(maxDecodedBytes: source.length - 1),
      ),
    ).throws<FormatException>();
    check(() => artworkResourcesModel(source: source, limits: const AiNativeLimits(maxTokens: 50))).throws<FormatException>();
  });

  test('keeps image samples opaque even when they contain declaration and metadata syntax', () {
    final List<int> pixels = latin1.encode('%AI8_EndBrushPattern\n%AI14_BeginSymbol\n(fake)\n%%EndData\n/ArtDictionary : ;');
    for (final bool private in [false, true]) {
      final String image = artboardBrushRaster(components: 1, colors: pixels, alphaSamples: pixels, private: private);
      final AiNativeArtworkResources model = artworkResourcesModel(
        source: artworkResourcesSource(resources: artboardBrush(art: image)),
      );
      final AiNativeArtworkResource resource = model.resources.single;
      check(resource.kind).equals(AiNativeArtworkResourceKind.brush);
      check(resource.rasters).length.equals(1);
      check(resource.rasters.single.colorSamples).deepEquals(pixels);
      check(resource.rasters.single.alphaSamples).isNotNull().deepEquals(pixels);
      check(resource.items.whereType<AiNativeRaster>().single).identicalTo(resource.rasters.single);
      check(resource.tokens.where((token) => token.kind == .data)).length.equals(1);
      check(resource.rasters.clear).throws<UnsupportedError>();
    }
  });
}
