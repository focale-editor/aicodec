import 'dart:convert';

import 'package:aikit/aikit.dart';
import 'package:checks/checks.dart';
import 'package:test/test.dart';

import 'ai_native_artboard_brush_descriptors_test.dart' show artboardBrushDescriptor;
import 'ai_native_artboard_brushes_test.dart' show artboardBrushRaster;
import 'ai_native_document_creation_test.dart' show newDocumentPdf, newDocumentRecords, newDocumentSave;

/// Explicit local process artwork, independent of document drawing state.
String resourceLifecycleArtwork({double gray = .25, String? identity}) =>
    '''0 A 0 Xw 0 Ae u
%_3 As 0 D 0 XR 0 O $gray g 0 1 0 0 0 Xy
%_0 0 m 12 0 L 12 8 L 0 0 L f
U
${identity == null ? '' : '%_/ArtDictionary : /XMLUID : ($identity) ; (AI10_ArtUID) , ;'}
9 () XW
''';

/// Starts from a complete independently created CC source with a blank host page.
AiNativeArtworkResources resourceLifecycleModel({AiNativeRecords? records}) => AiNativeArtworkResources.decode(
  structure: AiNativeStructure.decode(drawing: AiNativeDrawing.decode(records: records ?? newDocumentRecords(blank: true))),
);

/// Authors one tile or master with its explicitly supplied native representation.
AiNativeArtworkResources resourceLifecycleCreate(AiNativeArtworkResources model, AiNativeArtworkResourceKind kind, {String name = 'Resource', String? artwork, bool listed = true}) => model.create(
  kind: kind,
  nameBytes: latin1.encode(name),
  artworkBytes: latin1.encode(artwork ?? resourceLifecycleArtwork()),
  bounds: kind == .pattern ? AiBoundingBox(left: -2, bottom: -3, right: 18, top: 17) : null,
  addToSymbolList: listed,
);

/// Adds a fixture-owned setup fragment while retaining the current resource handles.
AiNativeArtworkResources _setup(AiNativeArtworkResources model, String extra) {
  final AiProgram program = model.structure.drawing.records.program;
  final int end = latin1.decode(program.bytes).indexOf('%%EndSetup');
  return resourceLifecycleModel(
    records: AiNativeRecords.decode(
      program: AiNativeEditor.apply(
        program: program,
        edits: [AiSourceEdit(start: end, end: end, bytes: latin1.encode(extra))],
      ),
    ),
  );
}

/// Reads exact source slices for preservation assertions.
List<int> _bytes(AiNativeArtworkResources model, int start, int end) => model.structure.drawing.records.program.bytes.sublist(start, end);

/// Qualified direct pattern placement in a local native coordinate basis.
String _patternPaint(String name) => '($name) 0 0 1 1 0 0 0 0 0 [1 0 0 1 0 0] p';

/// Reads literal panel entries independently of the writer's escaping strategy.
List<List<String>> _panels(AiNativeArtworkResources model) {
  final String source = latin1.decode(model.structure.drawing.records.program.bytes);
  return [
    for (final RegExpMatch match in RegExp(r'%AI(?:10|24)_BeginSymbolList[^\n]*\n([\s\S]*?)%AI(?:10|24)_EndSymbolList').allMatches(source))
      [for (final AiToken token in AiPostScript.tokenize(latin1.encode(match[1]!)).where((token) => token.kind == .string)) latin1.decode(aiStringBytes(token))],
  ];
}

/// Covers declaration authoring, references, panel ownership and repeated saving.
void main() {
  for (final AiNativeArtworkResourceKind kind in AiNativeArtworkResourceKind.values) {
    test('creates, revises, saves and removes a complete ${kind.name} declaration', () {
      final AiNativeArtworkResources source = resourceLifecycleModel();
      final List<int> original = [...source.structure.drawing.records.program.bytes];
      final AiNativeArtworkResources first = resourceLifecycleCreate(source, kind, name: 'Resource (é)\\');
      check(first.resources).length.equals(1);
      final AiNativeArtworkResource resource = first.resources.single;
      check(resource.nameBytes).deepEquals(latin1.encode('Resource (é)\\'));
      check(resource.paths).length.equals(1);
      check(resource.paths.single.isPrivate).isTrue();
      check(first.structure.drawing.paths).isEmpty();
      final AiProgram before = source.structure.drawing.records.program;
      final AiProgram after = first.structure.drawing.records.program;
      check(after.bytes.sublist(after.bodyStart)).deepEquals(before.bytes.sublist(before.bodyStart));
      final AiNativeArtworkResources second = first.replaceUnused(
        resource: resource,
        artworkBytes: latin1.encode(resourceLifecycleArtwork(gray: .75)),
        bounds: kind == .pattern ? AiBoundingBox(left: 0, bottom: 0, right: 30, top: 40) : null,
      );
      final AiPdfDocument saved = newDocumentSave(second.structure.drawing.records, newDocumentPdf(blank: true));
      final AiNativeArtworkResources reopened = resourceLifecycleModel(
        records: AiNativeRecords.decode(program: AiProgram.decode(bytes: AiNativeData.extract(saved).single.bytes)),
      );
      check(reopened.resources.single.nameBytes).deepEquals(resource.nameBytes);
      check(_bytes(reopened, reopened.resources.single.start, reopened.resources.single.end)).deepEquals(_bytes(second, second.resources.single.start, second.resources.single.end));
      check(reopened.remove(resources: reopened.resources).resources).isEmpty();
      check(source.structure.drawing.records.program.bytes).deepEquals(original);
      check(() => second.remove(resources: [resource])).throws<ArgumentError>();
    });
  }

  test('keeps equal resource names independent across all three namespaces', () {
    AiNativeArtworkResources model = resourceLifecycleModel();
    for (final AiNativeArtworkResourceKind kind in AiNativeArtworkResourceKind.values) {
      model = resourceLifecycleCreate(model, kind);
    }
    check(model.resources.map((resource) => resource.kind)).deepEquals(AiNativeArtworkResourceKind.values);
    final AiNativeArtworkResources reduced = model.remove(resources: [model.resources.first, model.resources.last]);
    check(reduced.resources.single.kind).equals(AiNativeArtworkResourceKind.symbol);
    check(_panels(reduced)).deepEquals([
      ['Resource'],
    ]);
  });

  test('retains symbol panel order and comments across legacy and current lists', () {
    final AiNativeArtworkResources first = resourceLifecycleCreate(resourceLifecycleModel(), .symbol, name: 'First');
    final AiNativeArtworkResources panels = _setup(first, '%AI10_BeginSymbolList\u0000\n% panel comment\n(First)\n%AI10_EndSymbolList\u0000\n');
    final AiNativeArtworkResources second = resourceLifecycleCreate(panels, .symbol, name: 'Second');
    check(_panels(second)).deepEquals([
      ['First', 'Second'],
      ['First', 'Second'],
    ]);
    final AiNativeArtworkResources removed = second.remove(resources: [second.resources.first]);
    check(latin1.decode(removed.structure.drawing.records.program.bytes)).contains('% panel comment\n\n');
    check(_panels(removed)).deepEquals([
      ['Second'],
      ['Second'],
    ]);
    check(removed.resources.single.nameBytes).deepEquals(latin1.encode('Second'));
    final AiNativeArtworkResources hidden = resourceLifecycleCreate(resourceLifecycleModel(), .symbol, listed: false);
    check(latin1.decode(hidden.structure.drawing.records.program.bytes).contains('SymbolList')).isFalse();
  });

  test('retains existing local identities and rejects newly colliding identities', () {
    final AiNativeArtworkResources source = resourceLifecycleModel();
    final AiNativeArtworkResources first = resourceLifecycleCreate(source, .symbol, artwork: resourceLifecycleArtwork(identity: 'master-path'));
    final AiNativeArtworkResources changed = first.replaceUnused(
      resource: first.resources.single,
      artworkBytes: latin1.encode(resourceLifecycleArtwork(gray: .8, identity: 'master-path')),
    );
    check(changed.resources.single.metadata.single['AI10_ArtUID']!.container!.entries.single.stringBytes!).deepEquals(latin1.encode('master-path'));
    check(
      () => resourceLifecycleCreate(
        first,
        .brush,
        name: 'Other',
        artwork: resourceLifecycleArtwork(identity: 'master-path'),
      ),
    ).throws<ArgumentError>();
    check(() => resourceLifecycleCreate(source, .symbol, artwork: resourceLifecycleArtwork(identity: 'root'))).throws<ArgumentError>();
    check(() => resourceLifecycleCreate(source, .symbol, artwork: resourceLifecycleArtwork(identity: 'invalid id'))).throws<ArgumentError>();
  });

  test('preserves retained declarations and rejects uncertain external identity references', () {
    final AiNativeArtworkResources first = resourceLifecycleCreate(resourceLifecycleModel(), .symbol, artwork: resourceLifecycleArtwork(identity: 'master-path'));
    final List<int> retained = _bytes(first, first.resources.single.start, first.resources.single.end);
    final AiNativeArtworkResources second = resourceLifecycleCreate(first, .brush, name: 'Independent');
    check(_bytes(second, second.resources.first.start, second.resources.first.end)).deepEquals(retained);
    final AiNativeArtworkResources reduced = second.remove(resources: [second.resources.last]);
    check(_bytes(reduced, reduced.resources.single.start, reduced.resources.single.end)).deepEquals(retained);
    final AiNativeArtworkResources uncertain = resourceLifecycleCreate(first, .symbol, name: 'master-path');
    check(() => uncertain.remove(resources: [uncertain.resources.first])).throws<UnsupportedError>();
    check(uncertain.remove(resources: uncertain.resources).resources).isEmpty();
  });

  test('retains resource image samples and requires fresh sample identities', () {
    final String raster = artboardBrushRaster().replaceFirst('(board-0) ;', '(resource-image) ;').replaceFirst('(board-0) /UnicodeString', '(resource-colors) /UnicodeString');
    final AiNativeArtworkResources first = resourceLifecycleCreate(resourceLifecycleModel(), .brush, artwork: raster);
    check(first.resources.single.rasters).length.equals(1);
    final List<int> colors = first.resources.single.rasters.single.colorSamples;
    final AiNativeArtworkResources changed = first.replaceUnused(resource: first.resources.single, artworkBytes: latin1.encode(raster));
    check(changed.resources.single.rasters.single.colorSamples).deepEquals(colors);
    check(() => resourceLifecycleCreate(first, .brush, name: 'Second', artwork: raster.replaceFirst('(resource-image)', '(second-image)'))).throws<ArgumentError>();
    check(changed.remove(resources: changed.resources).resources).isEmpty();
  });

  test('rejects palette and named-style consumers without deleting them', () {
    final AiNativeArtworkResources source = resourceLifecycleCreate(resourceLifecycleModel(), .pattern);
    for (final String consumer in [
      '%AI5_BeginPalette\n0 0 Pb\n${_patternPaint('Resource')} (Cell) Pc\nPB\n%AI5_EndPalette\n',
      '/KnownStyle : (Dependent) /Name , /SimpleStyle : ${_patternPaint('Resource')} /Paint ; /Def ;\n',
    ]) {
      final AiNativeArtworkResources used = _setup(source, consumer);
      final List<int> original = [...used.structure.drawing.records.program.bytes];
      check(() => used.remove(resources: used.resources)).throws<UnsupportedError>();
      check(() => used.replaceUnused(resource: used.resources.single, artworkBytes: [], bounds: used.resources.single.bounds)).throws<UnsupportedError>();
      check(used.structure.drawing.records.program.bytes).deepEquals(original);
    }
  });

  test('retains brush descriptors which reference their separate artwork tiles', () {
    final AiNativeArtworkResources source = resourceLifecycleCreate(resourceLifecycleModel(), .brush);
    final AiNativeArtworkResources used = _setup(source, artboardBrushDescriptor(plugin: 'Adobe ArtOnPath Brush Tool', data: '2 / Resource/ / / / / 0 0/ 0 1 / 1 0 1 0 1 0 0 0 1 1 0 1 25 25 1'));
    check(() => used.remove(resources: used.resources)).throws<UnsupportedError>();
    check(used.resources).length.equals(1);
  });

  test('checks transitive dependencies and deletes a closed unused resource set', () {
    final AiNativeArtworkResources first = resourceLifecycleCreate(resourceLifecycleModel(), .pattern, name: 'Base');
    final AiNativeArtworkResources second = resourceLifecycleCreate(first, .pattern, name: 'Dependent', artwork: '${_patternPaint('Base')} 0 0 m 10 0 L 10 10 L f');
    check(() => second.remove(resources: [second.resources.first])).throws<UnsupportedError>();
    check(second.remove(resources: second.resources).resources).isEmpty();
    check(() => resourceLifecycleCreate(first, .pattern, name: 'Recursive', artwork: _patternPaint('Recursive'))).throws<UnsupportedError>();
    final AiNativeArtworkResources styles = _setup(first, '/KnownStyle : (Dependent style) /Name , /SimpleStyle : ${_patternPaint('Base')} /Paint ; /Def ;\n');
    check(() => styles.replaceUnused(resource: styles.resources.first, artworkBytes: latin1.encode('1 (Dependent style) XW'), bounds: styles.resources.first.bounds)).throws<UnsupportedError>();
    final AiNativeArtworkResources styled = resourceLifecycleCreate(styles, .symbol, name: 'Styled', artwork: resourceLifecycleArtwork().replaceFirst('9 () XW', '1 (Dependent style) XW'));
    check(styled.resources.last.uses.single.resolution).equals(AiNativeResourceResolution.resolved);
    check(styled.remove(resources: [styled.resources.last]).resources).length.equals(1);
    check(() => first.replaceUnused(resource: first.resources.single, artworkBytes: latin1.encode(_patternPaint('Base')), bounds: first.resources.single.bounds)).throws<UnsupportedError>();
  });

  test('rejects opaque dependencies, foreign handles and malformed declaration payloads', () {
    final AiNativeArtworkResources source = resourceLifecycleCreate(resourceLifecycleModel(), .symbol);
    check(() => source.remove(resources: [source.resources.single, source.resources.single])).throws<ArgumentError>();
    check(() => source.remove(resources: [])).throws<ArgumentError>();
    check(() => resourceLifecycleCreate(source, .symbol)).throws<ArgumentError>();
    final AiNativeArtworkResources opaque = _setup(source, '/Opaque : (Resource) /String (FutureReference) , ;\n');
    check(() => opaque.remove(resources: opaque.resources)).throws<UnsupportedError>();
    for (final String artwork in ['u', '3 As 0 0 m 1 1 L f', '%AI14_BeginSymbol\n(Injected)\n%AI10_EndSymbol']) {
      check(() => resourceLifecycleCreate(resourceLifecycleModel(), .symbol, artwork: artwork)).throws<FormatException>();
    }
    check(() => resourceLifecycleCreate(resourceLifecycleModel(), .pattern, artwork: 'future_operator')).throws<UnsupportedError>();
  });

  test('requires portable tile bounds and preserves explicit input byte budgets', () {
    final AiNativeArtworkResources source = resourceLifecycleModel();
    check(() => source.create(kind: .pattern, nameBytes: [65], artworkBytes: [])).throws<ArgumentError>();
    check(() => source.create(kind: .symbol, nameBytes: [65], artworkBytes: [], bounds: AiBoundingBox(left: 0, bottom: 0, right: 10, top: 10))).throws<ArgumentError>();
    check(() => source.create(kind: .symbol, nameBytes: [], artworkBytes: [])).throws<ArgumentError>();
    check(() => source.create(kind: .symbol, nameBytes: [65], artworkBytes: [256])).throws<ArgumentError>();
    final AiNativeRecords original = source.structure.drawing.records;
    final AiNativeRecords bounded = AiNativeRecords.decode(
      program: AiProgram.decode(
        bytes: original.program.bytes,
        limits: AiNativeLimits(maxDecodedBytes: original.program.bytes.length + 10),
      ),
    );
    check(() => resourceLifecycleCreate(resourceLifecycleModel(records: bounded), .symbol)).throws<AiLimitException>();
  });
}
