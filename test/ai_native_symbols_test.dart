import 'dart:convert';

import 'package:aicodec/aicodec.dart';
import 'package:checks/checks.dart';
import 'package:test/test.dart';

import 'ai_native_document_creation_test.dart' show newDocumentPdf, newDocumentRecords, newDocumentSave;

/// Declares a named master without inferring its rendering or registration data.
String symbolInspectionMaster(String name, {String artwork = ''}) => '%AI14_BeginSymbol\n($name)\n$artwork\n%AI10_EndSymbol\n';

/// Observed instance field layout, with a nonsymmetric relative transform.
String symbolInspectionInstance(String name, {String matrix = '2 .25 -.5 -3 17 -29', String extra = ''}) => '/SymbolInstance : ($name) /SymbolRef , $matrix /RTransformMatrix , $extra ;\n';

/// Keeps unrelated document metadata around the selected fixture fragments.
String symbolInspectionSource({String setup = '', String body = ''}) =>
    latin1.decode(newDocumentRecords(blank: true).program.bytes).replaceFirst('%%EndSetup', '$setup%%EndSetup').replaceFirst('%%PageTrailer', '$body%%PageTrailer');

/// Reads original containers and resource handles in one immutable snapshot.
AiNativeArtworkResources symbolInspectionResources(String source, {AiNativeLimits limits = const AiNativeLimits()}) => AiNativeArtworkResources.decode(
  structure: AiNativeStructure.decode(
    drawing: AiNativeDrawing.decode(
      records: AiNativeRecords.decode(
        program: AiProgram.decode(bytes: latin1.encode(source), limits: limits),
      ),
    ),
  ),
);

/// Verifies exact references independently of body printing and host coordinates.
void main() {
  test('resolves exact symbol names without conflating pattern and brush namespaces', () {
    final String source = symbolInspectionSource(
      setup: '${symbolInspectionMaster('Tile')}%AI3_BeginPattern: (Tile)\n(Tile) 0 0 10 10 E\n%AI3_EndPattern\n%AI8_BeginBrushPattern\n(Tile)\n%AI8_EndBrushPattern\n',
      body: '${symbolInspectionInstance('Tile')}${symbolInspectionInstance('Missing')}',
    );
    final AiNativeArtworkResources resources = symbolInspectionResources(source);
    final AiNativeSymbols symbols = AiNativeSymbols.decode(artworkResources: resources);
    check(symbols.instances).length.equals(2);
    final AiNativeSymbolInstance instance = symbols.instances.first;
    check(instance.nameBytes!).deepEquals(latin1.encode('Tile'));
    check(instance.relativeTransform!).deepEquals([2, .25, -.5, -3, 17, -29]);
    check(instance.definition).identicalTo(resources.resources.first);
    check(instance.resolution).equals(AiNativeResourceResolution.resolved);
    check(instance.resource).isNull();
    check(instance.otherEntries).isEmpty();
    check(symbols.instancesOf(definition: resources.resources.first)).deepEquals([instance]);
    check(symbols.instances.last.resolution).equals(AiNativeResourceResolution.missing);
    check(symbols.instances.last.definition).isNull();
    check(latin1.decode(resources.structure.drawing.records.program.bytes)).equals(source);
  });

  test('retains raw non-UTF8 escaped names and the producer relative matrix', () {
    const String name = r'\377 A\(B\)\\';
    final AiNativeSymbols symbols = AiNativeSymbols.decode(
      artworkResources: symbolInspectionResources(
        symbolInspectionSource(
          setup: symbolInspectionMaster(name),
          body: symbolInspectionInstance(name, matrix: '.992005268671039 0 0 -.992005268671039 -1334.36214821856 633.884563162312'),
        ),
      ),
    );
    check(symbols.instances.single.nameBytes!).deepEquals([255, 32, 65, 40, 66, 41, 92]);
    check(symbols.instances.single.relativeTransform!).deepEquals([.992005268671039, 0, 0, -.992005268671039, -1334.36214821856, 633.884563162312]);
    check(symbols.instances.single.definition).isNotNull();
  });

  test('distinguishes duplicate missing conditional and same-branch declarations', () {
    final AiNativeSymbols repeated = AiNativeSymbols.decode(
      artworkResources: symbolInspectionResources(symbolInspectionSource(setup: '${symbolInspectionMaster('S')}${symbolInspectionMaster('S')}', body: symbolInspectionInstance('S'))),
    );
    check(repeated.instances.single.resolution).equals(AiNativeResourceResolution.ambiguous);
    check(repeated.instances.single.definition).isNull();
    check(repeated.instances.single.candidates).length.equals(2);
    final String setup =
        '%AI17_Begin_Content_if_version_gt:24 4\n${symbolInspectionMaster('S')}${symbolInspectionInstance('S')}%AI17_Alternate_Content\n${symbolInspectionMaster('S')}${symbolInspectionInstance('S')}%AI17_End_Versioned_Content\n';
    final AiNativeSymbols branches = AiNativeSymbols.decode(
      artworkResources: symbolInspectionResources(symbolInspectionSource(setup: setup, body: symbolInspectionInstance('S'))),
    );
    check(branches.instances).length.equals(3);
    for (final int index in [0, 1]) {
      check(branches.instances[index].resolution).equals(AiNativeResourceResolution.resolved);
      check(branches.instances[index].definition).identicalTo(branches.artworkResources.resources[index]);
    }
    check(branches.instances[0].node.versions.single.branch).equals(AiNativeVersionBranch.newer);
    check(branches.instances[1].node.versions.single.branch).equals(AiNativeVersionBranch.older);
    check(branches.instances.last.resolution).equals(AiNativeResourceResolution.conditional);
    check(branches.instances.last.candidates).length.equals(2);
  });

  test('retains resource-local links and opaque fields without granting editable ownership', () {
    final String body = symbolInspectionInstance('S', extra: '/Dictionary : 17 /Int (opaque) , ; /Future , /NotRecorded ,');
    final String source = symbolInspectionSource(
      setup: '${symbolInspectionMaster('S')}${symbolInspectionMaster('Container', artwork: body)}',
      body: body,
    );
    final AiNativeArtworkResources resources = symbolInspectionResources(source);
    final AiNativeSymbols symbols = AiNativeSymbols.decode(artworkResources: resources);
    check(symbols.instances).length.equals(2);
    check(symbols.referencesIn(resource: resources.resources.last)).deepEquals([symbols.instances.first]);
    check(symbols.instances.first.resource).identicalTo(resources.resources.last);
    check(symbols.instancesOf(definition: resources.resources.first)).length.equals(2);
    check(symbols.instances.first.otherEntries.map((entry) => entry.key)).deepEquals(['Future', 'NotRecorded']);
    check(symbols.instances.first.record.notRecorded).isTrue();
    final AiPdfDocument saved = newDocumentSave(resources.structure.drawing.records, newDocumentPdf(blank: true));
    check(AiNativeData.extract(saved).single.bytes).deepEquals(latin1.encode(source));
  });

  test('keeps malformed and repeated fields visible instead of choosing or defaulting', () {
    for (final String reference in ['', '() /SymbolRef ,', '(A) (B) /SymbolRef ,', '(A) /SymbolRef , (A) /SymbolRef ,', '/Computed /SymbolRef ,']) {
      final AiNativeSymbols symbols = AiNativeSymbols.decode(
        artworkResources: symbolInspectionResources(symbolInspectionSource(body: '/SymbolInstance : $reference 1 0 0 1 0 0 /RTransformMatrix ;\n')),
      );
      check(symbols.instances).length.equals(1);
      check(symbols.instances.single.nameBytes).isNull();
      check(symbols.instances.single.resolution).isNull();
      check(symbols.instances.single.relativeTransform!).deepEquals([1, 0, 0, 1, 0, 0]);
    }
    for (final String matrix in [
      '',
      '1 0 0 1 0 /RTransformMatrix ,',
      '1 0 0 1 0 0 9 /RTransformMatrix ,',
      '(matrix) /RTransformMatrix ,',
      '1 0 0 1 0 0 /Matrix ,',
      '1 0 0 1 0 0 /RTransformMatrix , 1 0 0 1 0 0 /RTransformMatrix ,',
    ]) {
      final AiNativeSymbols symbols = AiNativeSymbols.decode(
        artworkResources: symbolInspectionResources(symbolInspectionSource(setup: symbolInspectionMaster('S'), body: '/SymbolInstance : (S) /SymbolRef , $matrix ;\n')),
      );
      check(symbols.instances.single.relativeTransform).isNull();
      check(symbols.instances.single.definition).isNotNull();
    }
  });

  test('ignores lookalikes inside strings procedures comments and embedded documents', () {
    final String instance = symbolInspectionInstance('Fake');
    final AiNativeSymbols symbols = AiNativeSymbols.decode(
      artworkResources: symbolInspectionResources(
        symbolInspectionSource(body: '($instance) pop\n{$instance} pop\n%%BeginDocument: embedded\n$instance%%EndDocument\n% /SymbolInstance : ;\n${symbolInspectionInstance('Real')}'),
      ),
    );
    check(symbols.instances).length.equals(1);
    check(symbols.instances.single.nameBytes!).deepEquals(latin1.encode('Real'));
  });

  test('freezes source associations and rejects stale or wrong-namespace lookup handles', () {
    final String source = symbolInspectionSource(setup: symbolInspectionMaster('S'), body: symbolInspectionInstance('S'));
    final AiNativeArtworkResources resources = symbolInspectionResources(source);
    final AiNativeSymbols symbols = AiNativeSymbols.decode(artworkResources: resources);
    final AiNativeSymbolInstance instance = symbols.instances.single;
    check(symbols.instances.clear).throws<UnsupportedError>();
    check(instance.relativeTransform!.clear).throws<UnsupportedError>();
    check(() => instance.nameBytes![0] = 1).throws<UnsupportedError>();
    check(instance.candidates.clear).throws<UnsupportedError>();
    check(instance.otherEntries.clear).throws<UnsupportedError>();
    check(() => symbols.instancesOf(definition: symbolInspectionResources(source).resources.single)).throws<ArgumentError>();
    check(() => symbols.referencesIn(resource: symbolInspectionResources(source).resources.single)).throws<ArgumentError>();
  });

  test('bounds repeated name association work independently of lexical byte size', () {
    final String source = symbolInspectionSource(setup: List.filled(80, symbolInspectionMaster('S')).join(), body: List.filled(80, symbolInspectionInstance('S')).join());
    final AiNativeArtworkResources resources = symbolInspectionResources(source, limits: const AiNativeLimits(maxTokens: 5000));
    check(() => AiNativeSymbols.decode(artworkResources: resources)).throws<AiLimitException>();
  });
}
