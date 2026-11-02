import 'dart:convert';

import 'package:aicodec/aicodec.dart';
import 'package:checks/checks.dart';
import 'package:test/test.dart';

import 'ai_native_printing_test.dart' show printingFixture;

/// Builds an independent native source with separate setup and drawing regions.
AiNativeDrawing _drawing({String setup = '', String body = '', AiNativeLimits limits = const AiNativeLimits()}) => AiNativeDrawing.decode(
  records: AiNativeRecords.decode(
    program: AiProgram.decode(bytes: latin1.encode('%!PS-Adobe-3.0\n%%EndComments\n$setup\n%%EndSetup\n$body\n%%Trailer\n%%EOF\n'), limits: limits),
  ),
);

/// A source-backed layer header; visibility and locks stay in the native model.
const String _layer = '0 1 0 1 0 0 0 0 0 0 Lb (Hidden locked) Ln';

/// A qualified named style without introducing application rendering code.
const String _style = '/KnownStyle : (Shared) /Name , /SimpleStyle : 0 g /Paint ; /Def ;';

/// Version delimiter used by independently authored synthetic cases.
const String _begin = '%AI17_Begin_Content_if_version_gt:24 4';

/// Explicit old-version branch boundary.
const String _alternate = '%AI17_Alternate_Content';

/// Matching version terminator.
const String _end = '%AI17_End_Versioned_Content';

/// Exercises source identities, branch ownership and reference resolution.
void main() {
  test('indexes nested source owners, opaque siblings and hidden locked layers', () {
    final AiNativeDrawing drawing = _drawing(body: '$_layer\nu\n0 g\n0 0 m 10 10 L S\n/FutureRecord : /Dictionary : 7 /Int (Data) , ; /Payload ;\n17 FuturePaint\nU\nLB');
    final List<int> original = drawing.records.program.bytes.toList();
    final AiNativeStructure structure = AiNativeStructure.decode(drawing: drawing);
    final AiNativeStructureNode layer = structure.nodeFor(drawing.records.program.layers.single);
    final AiNativeStructureNode group = structure.nodeFor(drawing.groups.single);
    final AiNativeStructureNode path = structure.nodeFor(drawing.paths.single);
    check(structure.parentOf(group)).identicalTo(layer);
    check(structure.parentOf(path)).identicalTo(group);
    check(drawing.records.program.layers.single.visible).isFalse();
    check(drawing.records.program.layers.single.locked).isTrue();
    check(structure.childrenOf(group).map((node) => node.kind))
        .deepEquals([AiNativeStructureKind.instruction, AiNativeStructureKind.path, AiNativeStructureKind.record, AiNativeStructureKind.instruction]);
    final AiNativeContainer record = drawing.records.roots.single;
    check(structure.parentOf(structure.nodeFor(record['Payload']!.container!))).identicalTo(structure.nodeFor(record));
    check(drawing.records.program.bytes).deepEquals(original);
    check(structure.nodes.clear).throws<UnsupportedError>();
    check(group.childIndices.clear).throws<UnsupportedError>();
    check(structure.childrenOf(group).clear).throws<UnsupportedError>();
    final AiNativeStructure second = AiNativeStructure.decode(drawing: _drawing(body: '0 0 m 10 10 L S'));
    check(() => structure.nodeFor(second.drawing.paths.single)).throws<ArgumentError>();
    check(() => structure.parentOf(second.nodes.first)).throws<ArgumentError>();
  });

  test('keeps authoring and printing identities distinct while sharing style uses', () {
    final AiNativeDrawing drawing = printingFixture();
    final AiNativeStructure structure = AiNativeStructure.decode(drawing: drawing);
    check(structure.shapes).length.equals(2);
    final AiNativeShapeOwnership shape = structure.shapes.first;
    check(shape.dictionary.source).identicalTo(drawing.liveShapes.first.dictionary);
    check(shape.path!.source).identicalTo(drawing.liveShapes.first.path!);
    check(shape.printingPaths).length.equals(3);
    check(shape.printingGroup!.source).identicalTo(drawing.liveShapes.first.appearanceGroup!);
    check(shape.printingPaths.contains(shape.path)).isFalse();
    final AiNativeStructureResource shared = structure.resources.single;
    check(structure.usesOf(shared)).length.equals(2);
    check(structure.resourceUses.map((use) => use.resolution)).every((value) => value.equals(AiNativeResourceResolution.resolved));
    check(() => shared.nameBytes[0] = 0).throws<UnsupportedError>();
    check(shape.printingPaths.clear).throws<UnsupportedError>();
    check(() => structure.usesOf(AiNativeStructure.decode(drawing: printingFixture()).resources.single)).throws<ArgumentError>();
  });

  test('retains record entry order and saved identifiers without merging owners', () {
    const String artboard =
        '/Document : /Dictionary : /Array : /Dictionary : (Board) /String (Name) , (same) /String (ArtboardUUID) , 0 10 /RealPointRelToROrigin (PositionPoint1) , 10 0 /RealPointRelToROrigin (PositionPoint2) , ; , ; (ArtboardArray) , ; /Recorded ;';
    const String art = '/ArtDictionary : /XMLUID : (same) ; (AI10_ArtUID) , ;';
    final AiNativeDrawing drawing = _drawing(setup: artboard, body: '$art\n$art\n/FutureObject : 1 /Part , 2 /Part ;');
    final AiNativeStructure structure = AiNativeStructure.decode(drawing: drawing);
    check(structure.identifiers.map((value) => value.kind)).deepEquals([AiNativeIdentifierKind.artboard, AiNativeIdentifierKind.xmlArt, AiNativeIdentifierKind.xmlArt]);
    check(structure.identifiers.map((value) => latin1.decode(value.bytes))).every((value) => value.equals('same'));
    check(structure.identifiers.map((value) => value.field.owner).toSet()).length.equals(3);
    final AiNativeContainer record = drawing.records.roots.last;
    final AiNativeEntry entry = record.values('Part').last;
    check(structure.entryFor(entry).index).equals(1);
    check(structure.entryFor(entry).owner).identicalTo(structure.nodeFor(record));
    check(structure.entries.map((field) => field.entry).toList()).deepEquals(drawing.records.containers.expand((record) => record.entries).toList());
    check(structure.entries.clear).throws<UnsupportedError>();
    check(structure.identifiers.clear).throws<UnsupportedError>();
    check(() => structure.identifiers.first.bytes[0] = 0).throws<UnsupportedError>();
    check(() => structure.entryFor(_drawing(body: art).records.roots.single.entries.first)).throws<ArgumentError>();
    for (final String value in ['(invalid) /String', '/XMLUID : 3 ;', '/XMLUID : (one) , (two) ;']) {
      check(() => AiNativeStructure.decode(drawing: _drawing(body: '/ArtDictionary : $value (AI10_ArtUID) , ;'))).throws<FormatException>();
    }
  });

  test('retains nested version branches and empty newer-only additions', () {
    final AiNativeDrawing drawing = _drawing(body: '$_begin\n/Future : 1 /Data ;\n$_begin\n0 0 m N\n$_end\n$_alternate\n/Future : 2 /Data ;\n$_end\n$_begin\n$_end');
    final AiNativeStructure structure = AiNativeStructure.decode(drawing: drawing);
    check(structure.versions.blocks).length.equals(3);
    final AiNativeVersionBlock outer = structure.versions.blocks.first;
    check(outer.major).equals(24);
    check(outer.minor).equals(4);
    check(outer.family).equals('AI17');
    check(structure.versions.blocks[1].olderRange).isNull();
    final AiNativeStructureNode path = structure.nodeFor(drawing.paths.single);
    check(path.versions.map((item) => item.branch)).deepEquals([AiNativeVersionBranch.newer, AiNativeVersionBranch.newer]);
    check(structure.nodeFor(drawing.records.roots.last).versions.single.branch).equals(AiNativeVersionBranch.older);
    check(structure.versions.memberships(start: path.start, end: path.end).map((item) => item.block)).deepEquals(path.versions.map((item) => item.block));
    check(() => structure.versions.memberships(start: outer.opening.end, end: outer.closing.start)).throws<UnsupportedError>();
    check(() => structure.versions.memberships(start: -1, end: 2)).throws<ArgumentError>();
    check(structure.versions.blocks.clear).throws<UnsupportedError>();
    check(path.versions.clear).throws<UnsupportedError>();
  });

  test('does not read version markers from strings, procedures or embedded documents', () {
    final AiNativeDrawing drawing = _drawing(
      setup: '/ignored {\n$_begin\n} def\n%%BeginDocument: nested.eps\n$_alternate\n%%EndDocument',
      body: '($_begin) FutureString',
    );
    check(AiNativeVersions.decode(records: drawing.records).blocks).isEmpty();
    for (final String body in [_alternate, _end, _begin, '$_begin\n$_alternate\n$_alternate\n$_end', '$_begin\n%AI18_End_Versioned_Content', '%AI17_Begin_Content_if_version_gt:1 x\n$_end']) {
      check(() => AiNativeVersions.decode(records: _drawing(body: body).records)).throws<FormatException>();
    }
    check(
      () => AiNativeVersions.decode(
        records: _drawing(body: '$_begin\n$_begin\n$_end\n$_end', limits: const AiNativeLimits(maxDepth: 1)).records,
      ),
    ).throws<AiLimitException>();
  });

  test('resolves same-branch resources without choosing an unconditional version', () {
    final AiNativeDrawing drawing = _drawing(
      setup: '$_begin\n$_style\n/Art : 1 (Shared) XW ;\n$_alternate\n$_style\n/Art : 1 (Shared) XW ;\n$_end',
      body: '1 (Shared) XW\n1 (Missing) XW',
    );
    final AiNativeStructure structure = AiNativeStructure.decode(drawing: drawing);
    check(structure.resources).length.equals(2);
    check(structure.resourceUses.map((use) => use.resolution)).deepEquals([
      AiNativeResourceResolution.resolved,
      AiNativeResourceResolution.resolved,
      AiNativeResourceResolution.conditional,
      AiNativeResourceResolution.missing,
    ]);
    check(structure.resourceUses[0].candidates.single).identicalTo(structure.resources[0]);
    check(structure.resourceUses[1].candidates.single).identicalTo(structure.resources[1]);
    check(structure.resourceUses[2].candidates).length.equals(2);
    check(structure.usesOf(structure.resources.first)).length.equals(2);
    check(structure.resourceUses[0].owner!.source).isA<AiNativeContainer>().has((record) => record.type, 'type').equals('Art');
  });

  test('resolves mode-zero style assignments and excludes unnamed applications', () {
    final AiNativeDrawing drawing = _drawing(
      setup: '$_begin\n$_style\n/Art : 0 (Shared) XW ;\n$_end',
      body: '0 (Shared) XW\n%_0 (Missing) XW\n0 () XW\n1 () XW',
    );
    final AiNativeStructure structure = AiNativeStructure.decode(drawing: drawing);
    check(structure.resourceUses.map((use) => use.resolution)).deepEquals([
      AiNativeResourceResolution.resolved,
      AiNativeResourceResolution.conditional,
      AiNativeResourceResolution.missing,
    ]);
    check(structure.usesOf(structure.resources.single)).length.equals(2);
    check(structure.resourceUses.last.instruction.isPrivate).isTrue();
    check(() => AiNativeStructure.decode(drawing: _drawing(body: '0 /Shared XW'))).throws<FormatException>();
  });

  test('retains duplicate names and refuses dependent live-shape edits', () {
    final AiNativeDrawing source = printingFixture();
    final AiNativeContainer style = source.records.roots.singleWhere((record) => record.type == 'KnownStyle');
    final AiProgram program = AiNativeEditor.apply(
      program: source.records.program,
      edits: [AiSourceEdit(start: style.end, end: style.end, bytes: source.records.program.bytes.sublist(style.start, style.end))],
    );
    final AiNativeDrawing drawing = AiNativeDrawing.decode(records: AiNativeRecords.decode(program: program));
    check(drawing.liveShapes.map((shape) => shape.isBound)).every((value) => value.isFalse());
    check(drawing.liveShapes.first.style).isNull();
    final AiNativeStructure structure = AiNativeStructure.decode(drawing: drawing);
    check(structure.resourceUses.map((use) => use.resolution)).every((value) => value.equals(AiNativeResourceResolution.ambiguous));
    check(() => drawing.translateLiveShapes(shapes: drawing.liveShapes, deltaX: 1, deltaY: 1)).throws<UnsupportedError>();
  });

  test('keeps an internally conditional declaration separate from its record owner', () {
    final AiNativeStructure structure = AiNativeStructure.decode(
      drawing: _drawing(setup: '/KnownStyle :\n$_begin\n(Shared) /Name ,\n$_end\n/SimpleStyle : 0 g /Paint ; /Def ;', body: '1 (Shared) XW'),
    );
    check(structure.resources.single.definition.versions).isEmpty();
    check(structure.resources.single.versions.single.branch).equals(AiNativeVersionBranch.newer);
    check(structure.resourceUses.single.resolution).equals(AiNativeResourceResolution.conditional);
    check(structure.resources.single.versions.clear).throws<UnsupportedError>();
    check(
      () => AiNativeStructure.decode(drawing: _drawing(setup: '/KnownStyle : (Shared)\n$_begin\n(suffix)\n$_end\n/Name , /SimpleStyle : 0 g /Paint ; /Def ;')),
    ).throws<UnsupportedError>();
  });

  test('indexes gradient declarations and uses inside art and appearance records', () {
    const String definition = '%AI5_BeginGradient: (Ink)\n(Ink) 0 2 Bd\n[\n%_1 0 50 100 Bs\n%_0 0 50 0 Bs\nBD\n%AI5_EndGradient';
    const String instance = 'Bb\n1 (Ink) 0 0 0 100 1 0 0 1 0 0 Bg\n0 BB';
    final AiNativeStructure structure = AiNativeStructure.decode(
      drawing: _drawing(setup: '$definition\n/Art : $instance ;\n/FillStyle : $instance /Def ;', body: instance),
    );
    check(structure.resources.single.kind).equals(AiNativeStructureResourceKind.gradient);
    check(structure.usesOf(structure.resources.single)).length.equals(3);
    check(structure.resourceUses.map((use) => use.resolution)).every((value) => value.equals(AiNativeResourceResolution.resolved));
    check((structure.resourceUses[0].owner!.source as AiNativeContainer).type).equals('Art');
    check((structure.resourceUses[1].owner!.source as AiNativeContainer).type).equals('FillStyle');
    check(structure.resourceUses[2].owner!.kind).equals(AiNativeStructureKind.instruction);
    final AiNativeStructure duplicate = AiNativeStructure.decode(
      drawing: _drawing(setup: '$definition\n$definition', body: instance),
    );
    check(duplicate.resourceUses.single.resolution).equals(AiNativeResourceResolution.ambiguous);
    final AiNativeStructure missing = AiNativeStructure.decode(drawing: _drawing(body: instance));
    check(missing.resourceUses.single.resolution).equals(AiNativeResourceResolution.missing);
  });

  test('rejects reference operands split across version blocks', () {
    final AiNativeDrawing drawing = _drawing(setup: '$_style\n/Art : 1\n$_begin\n(Shared)\n$_end\nXW ;');
    check(() => AiNativeStructure.decode(drawing: drawing)).throws<UnsupportedError>();
  });

  test('counts setup symbol and pattern uses without interpreting opaque artwork', () {
    final AiNativeStructure structure = AiNativeStructure.decode(
      drawing: _drawing(
        setup: '''$_style
%AI3_BeginPattern: (Pattern)
/ignored { 1 (Procedure) XW } def
(1 (String) XW) FutureString
/FutureObject : 1 (Opaque) XW /Data ;
%%BeginDocument: nested.eps
1 (Embedded) XW
%%EndDocument
1 (Shared) XW
/Art : 1 (Shared) XW ;
%AI3_EndPattern
%AI14_BeginSymbol
1 (Missing) XW
%AI10_EndSymbol''',
      ),
    );
    check(structure.resourceUses.map((use) => latin1.decode(use.nameBytes))).deepEquals(['Shared', 'Shared', 'Missing']);
    check(structure.resourceUses.first.owner).isNull();
    check((structure.resourceUses[1].owner!.source as AiNativeContainer).type).equals('Art');
    check(structure.usesOf(structure.resources.single)).length.equals(2);
    for (final String setup in ['%AI14_BeginSymbol', '%AI3_EndPattern', '%AI14_BeginSymbol\n%AI3_EndPattern']) {
      check(() => AiNativeStructure.decode(drawing: _drawing(setup: setup))).throws<FormatException>();
    }
    check(() => AiNativeStructure.decode(drawing: _drawing(setup: '%AI14_BeginSymbol\n%_1\n(Shared) XW\n%AI10_EndSymbol'))).throws<FormatException>();
  });

  test('rejects crossing owners and bounds combined nesting and association work', () {
    check(() => AiNativeStructure.decode(drawing: _drawing(body: '$_layer\nu\nLB\n0 0 m N\nU'))).throws<UnsupportedError>();
    check(
      () => AiNativeStructure.decode(
        drawing: _drawing(body: '$_layer\n$_layer\nu U\nLB LB', limits: const AiNativeLimits(maxDepth: 2)),
      ),
    ).throws<AiLimitException>();
    final AiNativeDrawing excessive = _drawing(
      setup: '$_style\n${List.filled(50, '$_begin\n$_end').join('\n')}',
      body: List.filled(40, '1 (Shared) XW').join('\n'),
      limits: const AiNativeLimits(maxTokens: 600),
    );
    check(() => AiNativeStructure.decode(drawing: excessive)).throws<AiLimitException>();
  });
}
