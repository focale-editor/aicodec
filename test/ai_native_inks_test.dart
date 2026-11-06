import 'dart:convert';

import 'package:checks/checks.dart';
import 'package:illustratorkit/illustratorkit.dart';
import 'package:test/test.dart';

import 'ai_native_appearance_editing_test.dart';
import 'ai_native_artboard_brush_descriptors_test.dart' show artboardBrushDescriptor;
import 'ai_native_artboard_brushes_test.dart' show artboardBrush;
import 'ai_native_color_resources_test.dart';
import 'ai_native_color_save_test.dart' show colorSave;
import 'ai_native_objects_test.dart' show objectSource;

/// Opens a complete bounded native snapshot with source-owned ink handles.
AiNativeInks inkModel(String source, {AiNativeLimits limits = const AiNativeLimits()}) => AiNativeInks.decode(
  records: AiNativeRecords.decode(
    program: AiProgram.decode(bytes: latin1.encode(source), limits: limits),
  ),
);

/// An explicit host CMYK alternative, independent of RGB conversion.
AiColor inkCmyk([double value = .2]) => AiColor(space: .cmyk, channels: [value, .3, .4, .5]);

/// An independently supplied RGB alternative for the same ink identity.
AiColor inkRgb() => AiColor(space: .rgb, channels: [.6, .7, .8]);

/// Every named paint spelling, with literal tints deliberately left distinct.
const String inkPaints = '''0 0 0 1 (Ink) 0.25 x
0 0 m 10 0 L f
0 0 0 1 <496e6b> 0.3 0 XX
0 1 m 10 1 L S
0.1 0.2 0.3 (In\\153) 0.4 1 Xx
0 2 m 10 2 L f
0 0 0 1 (Ink) 0.5 XS
0 3 m 10 3 L S
0 0 0 1 0.1 0.2 0.3 (Ink) 0.6 1 Xz
0 4 m 10 4 L f
0 0 0 1 (Other) 0.7 x
0 5 m 10 5 L f''';

/// One named stop whose tint and alpha are separate from its ink alternatives.
AiNativeGradientStop inkStop(double position, double tint) => AiNativeGradientStop(
  color: AiNativeGradientColor(kind: .customCmyk, components: [0, 0, 0, 1], nameBytes: latin1.encode('Ink'), tint: tint),
  position: position,
  opacity: .8,
);

/// Host-composed custom-color ramp with explicit ink-tint samples.
AiNativeGradientRamp inkRamp() => AiNativeGradientRamp(
  kind: .customCmyk,
  channels: [
    for (final double value in [.2, .3, .4, .5, .6]) AiNativeGradientChannel.constant(value: value),
  ],
);

/// A direct mesh declaring two inks without expanding their corner tints.
String inkMesh() => '''/Mesh X!
%_2 /Version X#
%_/Cartesian /Type X#
%_[1 1] /Size X#
%_/Data X#
%_[[0 0 0 1 /DeviceCMYK (Ink) /Separation] [0 1 0 0 /DeviceCMYK (Other) /Separation] 2 /NChannel] /CS X#
%_[0 0] /P X#
%_[-1] /R X#
%_[0.4 0.7 1 0 0 0 0 1 0 0 1] /N X#
%_[0.4 0.7 1 10 0 10 0 1 10 0 1] /N X#
%_[0.4 0.7 1 10 10 10 10 1 10 10 1] /N X#
%_[0.4 0.7 1 0 10 0 10 1 0 10 1] /N X#
%_/E X#
/End X!''';

/// Supplies a full printing revision using exact handles from the ink graph.
List<AiNativeAppearanceReplacement> inkPrinting(AiNativeInks model) => [
  for (final AiNativeAppearanceArtwork owner in model.printingOwners)
    AiNativeAppearanceReplacement(artwork: owner, bytes: latin1.encode(appearanceEditedGroup), bounds: AiBoundingBox(left: -20, bottom: -30, right: 120, top: 140)),
];

/// Inspects values through typed source commands after each global edit.
List<AiNativeNamedColor> _colors(AiNativeInk ink) => ink.paints.map((command) => AiNativeNamedColor.decode(instruction: command)!).toList();

/// Checks global reference coverage, supplied representations and atomic rejection.
void main() {
  test('redefines every named paint layout without altering tints names or unrelated ink', () {
    final String source = objectSource(inkPaints, setup: '');
    final AiNativeInks model = inkModel(source);
    final AiNativeInks changed = model.redefine(ink: model.inks.first, cmyk: inkCmyk(), rgb: inkRgb());
    final List<AiNativeNamedColor> colors = _colors(changed.inks.first);
    check(colors.map((color) => color.tint)).deepEquals([.25, .3, .4, .5, .6]);
    check(colors.map((color) => color.components)).deepEquals([
      inkCmyk().channels,
      inkCmyk().channels,
      inkRgb().channels,
      inkCmyk().channels,
      [...inkCmyk().channels, ...inkRgb().channels],
    ]);
    check(latin1.decode(changed.records.program.bytes)).contains('0 0 0 1 (Other) 0.7 x');
    check(latin1.decode(changed.records.program.bytes)).contains('(In\\153) 0.4 1 Xx');
    check(latin1.decode(model.records.program.bytes)).equals(source);
  });

  test('updates palette and ordinary artwork together while retaining display names', () {
    const String palette = '%AI5_BeginPalette\n0 0 Pb\n0 0 0 1 (Ink) 1 Xs\n(Ink) Pc\nPB\n%AI5_EndPalette';
    final AiNativeInks model = inkModel(objectSource(inkPaints, setup: palette));
    final AiNativeInks changed = model.redefine(ink: model.inks.first, cmyk: inkCmyk(), rgb: inkRgb());
    final AiNativeSwatch cell = AiNativeSwatches.decode(records: changed.records).palettes.single.swatches.single;
    check(cell.nameBytes!).deepEquals(latin1.encode('Ink'));
    check(cell.namedColor!.components).deepEquals(inkCmyk().channels);
    check(cell.namedColor!.tint).equals(1);
    check(changed.inks.first.paints).length.equals(6);
  });

  test('requires all alternatives and rejects foreign handles without mutation', () {
    final AiNativeInks model = inkModel(objectSource(inkPaints, setup: ''));
    check(() => model.redefine(ink: model.inks.first, cmyk: inkCmyk())).throws<ArgumentError>();
    check(() => model.redefine(ink: model.inks.first, cmyk: inkRgb(), rgb: inkRgb())).throws<ArgumentError>();
    check(
      () => model.redefine(
        ink: inkModel(objectSource(inkPaints, setup: '')).inks.first,
        cmyk: inkCmyk(),
        rgb: inkRgb(),
      ),
    ).throws<ArgumentError>();
    check(_colors(model.inks.first).first.components).deepEquals([0.0, 0.0, 0.0, 1.0]);
  });

  test('changes every gradient bank and both stop representations using explicit ramps', () {
    final AiNativeGradientResources resources = colorResources(setup: '0 Bn\n0 Bn', body: inkPaints).create(
      nameBytes: latin1.encode('Gradient'),
      radial: false,
      stops: [inkStop(0, .2), inkStop(100, .9)],
      ramps: [inkRamp()],
    );
    final AiNativeInks model = AiNativeInks.decode(records: resources.records);
    final AiNativeInk ink = model.inks.first;
    check(ink.gradients).length.equals(2);
    check(() => model.redefine(ink: ink, cmyk: inkCmyk(), rgb: inkRgb())).throws<ArgumentError>();
    final AiNativeInks changed = model.redefine(
      ink: ink,
      cmyk: inkCmyk(),
      rgb: inkRgb(),
      ramps: {
        ink.gradients.first: [inkRamp()],
      },
    );
    for (final AiNativeGradientDefinition definition in changed.inks.first.gradients) {
      for (final AiNativeGradientStop stop in [...definition.stops, ...definition.fallbackStops]) {
        check(stop.color.components).deepEquals(inkCmyk().channels);
        check(stop.opacity).equals(.8);
      }
      check(definition.stops.map((stop) => stop.color.tint)).deepEquals([.9, .2]);
      check(definition.ramps.single.channels.map((channel) => channel.constant)).deepEquals([.2, .3, .4, .5, .6]);
    }
    check(
      () => model.redefine(
        ink: ink,
        cmyk: inkCmyk(),
        rgb: inkRgb(),
        ramps: {
          ink.gradients[0]: [inkRamp()],
          ink.gradients[1]: [inkRamp()],
        },
      ),
    ).throws<ArgumentError>();
  });

  test('changes mesh declarations and all same-name paints without altering vertex tints', () {
    final AiNativeInks model = inkModel(objectSource('${inkMesh()}\n$inkPaints', setup: ''));
    final AiNativeInks changed = model.redefine(ink: model.inks.first, cmyk: inkCmyk(), rgb: inkRgb());
    final AiNativeMesh mesh = changed.inks.first.meshes.single;
    final AiNativeMeshNode corner = mesh.vertices.first.corners.first;
    check(corner.color).deepEquals([.4, .7]);
    check(corner.colorSpace!.inks.first.components).deepEquals(inkCmyk().channels);
    check(corner.colorSpace!.inks.last.components).deepEquals([0.0, 1.0, 0.0, 0.0]);
    check(mesh.vertices.map((vertex) => vertex.position)).deepEquals(model.inks.first.meshes.single.vertices.map((vertex) => vertex.position));
    check(latin1.decode(changed.records.program.bytes)).contains('%_[0.4 0.7 1 10 10 10 10 1 10 10 1] /N X#');
  });

  test('supports literal RGB and gray mesh alternatives without color conversion', () {
    for (final (String device, String channels, AiColor color) in [
      ('DeviceRGB', '0 0 1', inkRgb()),
      ('DeviceGray', '0.25', AiColor(space: .gray, channels: [.8])),
    ]) {
      final String mesh = inkMesh()
          .replaceFirst('[[0 0 0 1 /DeviceCMYK (Ink) /Separation] [0 1 0 0 /DeviceCMYK (Other) /Separation] 2 /NChannel]', '[$channels /$device (Ink) /Separation]')
          .replaceAll('0.4 0.7 1', '0.7 1');
      final AiNativeInks model = inkModel(objectSource(mesh, setup: ''));
      final AiNativeInks changed = model.redefine(ink: model.inks.single, rgb: device == 'DeviceRGB' ? color : null, gray: device == 'DeviceGray' ? color : null);
      check(changed.inks.single.meshes.single.vertices.first.corners.first.colorSpace!.inks.single.components).deepEquals(color.channels);
      check(changed.inks.single.meshes.single.vertices.first.corners.first.color).deepEquals([.7]);
    }
  });

  test('requires complete shared appearance printing and retains native identities', () {
    final String source = appearanceEditingSource()
        .replaceFirst('0.2 0.3 0.4 Xa', '0 0 0 1 (Ink) 0.5 Xs')
        .replaceFirst('%AI17_Begin_Content_if_version_gt:17 4\n%_/ArtDictionary :', '%AI17_Begin_Content_if_version_gt:17 4\n%_/ArtDictionary :\n%_/XMLUID : (ink_author) ; (AI10_ArtUID) ,');
    final AiNativeInks model = inkModel(source);
    check(model.printingOwners).length.equals(2);
    check(() => model.redefine(ink: model.inks.single, cmyk: inkCmyk())).throws<ArgumentError>();
    check(() => model.redefine(ink: model.inks.single, cmyk: inkCmyk(), artwork: inkPrinting(model).take(1).toList())).throws<ArgumentError>();
    final AiNativeInks changed = model.redefine(ink: model.inks.single, cmyk: inkCmyk(), artwork: inkPrinting(model));
    check(_colors(changed.inks.single).single.components).deepEquals(inkCmyk().channels);
    check(changed.appearances.styles).length.equals(1);
    check(changed.appearances.styles.single.uses).length.equals(2);
    for (final AiNativeAppearanceArtwork owner in changed.printingOwners) {
      check(changed.records.program.bytes.sublist(owner.printingGroup.start, owner.printingGroup.end)).deepEquals(latin1.encode(appearanceEditedGroup));
    }
    final List<List<int>> beforeIds = model.appearances.structure.identifiers.map((identifier) => identifier.bytes).toList();
    check(beforeIds).deepEquals([latin1.encode('ink_author')]);
    check(changed.appearances.structure.identifiers.map((identifier) => identifier.bytes)).deepEquals(beforeIds);
    check(changed.appearances.structure.drawing.liveShapes.map((shape) => shape.path!.geometry.map((command) => command.numbers).toList())).deepEquals(
      model.appearances.structure.drawing.liveShapes.map((shape) => shape.path!.geometry.map((command) => command.numbers).toList()),
    );
  });

  test('updates DSC alternatives and continuation records while retaining unrelated headers', () {
    final String source = objectSource(inkPaints, setup: '').replaceFirst('%%EndComments', '''%%DocumentCustomColors: (Other) (Ink)
%%CMYKCustomColor: 0 1 0 0 (Other)
%%+ 0 0 0 1 (Ink)
%%RGBCustomColor: 0.1 0.2 0.3 (Ink)
%%EndComments''');
    final AiNativeInks model = inkModel(source);
    final AiNativeInks changed = model.redefine(ink: model.inks.first, cmyk: inkCmyk(), rgb: inkRgb());
    final String bytes = latin1.decode(changed.records.program.bytes);
    check(bytes).contains('%%CMYKCustomColor: 0 1 0 0 (Other)');
    check(bytes).contains('%%+ 0.2 0.3 0.4 0.5 (Ink)');
    check(bytes).contains('%%RGBCustomColor: 0.6 0.7 0.8 (Ink)');
    check(bytes).contains('%%DocumentCustomColors: (Other) (Ink)');
  });

  test('rejects unknown same-name references and malformed DSC instead of partial recoloring', () {
    for (final String source in [
      objectSource(inkPaints, setup: '/Dictionary : (Ink) /String (FutureInkReference) , ;'),
      objectSource('$inkPaints\n(Ink) pop', setup: ''),
      objectSource(inkPaints, setup: '').replaceFirst('%%EndComments', '%%CMYKCustomColor: (unknown expression)\n%%EndComments'),
    ]) {
      final AiNativeInks model = inkModel(source);
      check(() => model.redefine(ink: model.inks.first, cmyk: inkCmyk(), rgb: inkRgb())).throws<UnsupportedError>();
      check(latin1.decode(model.records.program.bytes)).equals(source);
    }
  });

  test('retains unchanged numeric spelling and bounds output expansion', () {
    final String source = objectSource('0e0 0 0 1.0 (Ink) 5e-1 x\n0 0 m 10 0 L f', setup: '');
    final AiNativeInks model = inkModel(source);
    final AiNativeInks same = model.redefine(
      ink: model.inks.single,
      cmyk: AiColor(space: .cmyk, channels: [0, 0, 0, 1]),
    );
    check(same.records.program.bytes).deepEquals(model.records.program.bytes);
    final AiNativeInks bounded = inkModel(source, limits: AiNativeLimits(maxDecodedBytes: latin1.encode(source).length));
    check(() => bounded.redefine(ink: bounded.inks.single, cmyk: inkCmyk())).throws<FormatException>();
    check(bounded.records.program.bytes).deepEquals(model.records.program.bytes);
  });

  test('rejects misplaced DSC ink declarations without rewriting source comments', () {
    const String comment = '%%CMYKCustomColor: 0 0 0 1 (Ink)';
    final AiNativeInks model = inkModel(objectSource('$inkPaints\n$comment', setup: ''));
    check(() => model.redefine(ink: model.inks.first, cmyk: inkCmyk(), rgb: inkRgb())).throws<UnsupportedError>();
    check(latin1.decode(model.records.program.bytes)).contains(comment);
  });

  test('requires consistent duplicate gradient banks before a global change', () {
    final AiNativeGradientResources resources = colorResources(setup: '0 Bn\n0 Bn').create(
      nameBytes: latin1.encode('Gradient'),
      radial: false,
      stops: [inkStop(0, .2), inkStop(100, .9)],
      ramps: [inkRamp()],
    );
    final String source = latin1.decode(resources.records.program.bytes);
    final AiNativeInks model = inkModel(source.replaceFirst('0.9 3', '0.6 3'));
    final AiNativeInk ink = model.inks.single;
    // Alter both paired stop copies in only one bank to retain local validity.
    final int second = source.indexOf('%AI5_BeginGradient:', source.indexOf('%AI5_BeginGradient:') + 1);
    final AiNativeInks inconsistent = inkModel(source.substring(0, second).replaceAll('0.9 3', '0.6 3') + source.substring(second));
    check(
      () => inconsistent.redefine(
        ink: inconsistent.inks.single,
        cmyk: inkCmyk(),
        ramps: {
          inconsistent.inks.single.gradients.first: [inkRamp()],
        },
      ),
    ).throws<UnsupportedError>();
    check(
      () => inconsistent.redefine(
        ink: ink,
        cmyk: inkCmyk(),
        ramps: {
          ink.gradients.first: [inkRamp()],
        },
      ),
    ).throws<ArgumentError>();
  });

  test('rejects mismatched ink names between authoritative and compatibility stops', () {
    final AiNativeGradientResources resources = colorResources(setup: '').create(
      nameBytes: latin1.encode('Gradient'),
      radial: false,
      stops: [inkStop(0, .2), inkStop(100, .9)],
      ramps: [inkRamp()],
    );
    final String source = latin1.decode(resources.records.program.bytes).replaceFirst(r'(\111\156\153)', '(Other)');
    final AiNativeInks model = inkModel(source);
    final AiNativeInk ink = model.inks.singleWhere((ink) => latin1.decode(ink.nameBytes) == 'Ink');
    check(
      () => model.redefine(
        ink: ink,
        cmyk: inkCmyk(),
        ramps: {
          ink.gradients.first: [inkRamp()],
        },
      ),
    ).throws<UnsupportedError>();
    check(latin1.decode(model.records.program.bytes)).equals(source);
  });

  test('rejects referenced brush recoloring while allowing an unused native tile', () {
    final String tile = artboardBrush(art: '0 0 0 1 (Ink) 0.5 Xs 0 0 m 10 0 L 10 10 L f');
    final AiNativeInks unused = inkModel(objectSource('0 0 m 10 0 L S', setup: tile));
    final AiNativeInks changed = unused.redefine(ink: unused.inks.single, cmyk: inkCmyk());
    check(_colors(changed.inks.single).single.components).deepEquals(inkCmyk().channels);
    final String descriptor = artboardBrushDescriptor(plugin: 'Adobe ArtOnPath Brush Tool', data: '2 / board-0/ / / / / 0 0/ 0 1 / 1 0 1 0 1 0 0 0 1 1 0 1 25 25 1');
    final AiNativeInks used = inkModel(objectSource('0 0 m 10 0 L S', setup: '$tile$descriptor'));
    check(() => used.redefine(ink: used.inks.single, cmyk: inkCmyk())).throws<UnsupportedError>();
    check(_colors(used.inks.single).single.components).deepEquals([0.0, 0.0, 0.0, 1.0]);
  });

  test('follows an ink through a pattern used by a referenced brush', () {
    const String pattern = '%AI3_BeginPattern: (Tile)\n(Tile) 0 0 10 10\n0 0 0 1 (Ink) 0.5 Xs 0 0 m 10 0 L 10 10 L f\nE\n%AI3_EndPattern\n';
    final String tile = artboardBrush(art: '(Tile) 3 -5 0.5 2 35 1 45 12 7 [1 0.2 0.3 1 40 70] p 0 0 m 10 0 L 10 10 L f');
    final AiNativeInks unused = inkModel(objectSource('0 0 m 10 0 L S', setup: '$pattern$tile'));
    check(_colors(unused.redefine(ink: unused.inks.single, cmyk: inkCmyk()).inks.single).single.components).deepEquals(inkCmyk().channels);
    final String descriptor = artboardBrushDescriptor(plugin: 'Adobe ArtOnPath Brush Tool', data: '2 / board-0/ / / / / 0 0/ 0 1 / 1 0 1 0 1 0 0 0 1 1 0 1 25 25 1');
    final AiNativeInks used = inkModel(objectSource('0 0 m 10 0 L S', setup: '$pattern$tile$descriptor'));
    check(() => used.redefine(ink: used.inks.single, cmyk: inkCmyk())).throws<UnsupportedError>().has((error) => error.toString(), 'reason').contains('instance-cache');
    check(_colors(used.inks.single).single.components).deepEquals([0.0, 0.0, 0.0, 1.0]);
  });

  test('reopens a complete compressed save and applies a second global revision', () {
    final AiNativeInks model = inkModel(appearanceEditingSource().replaceFirst('0.2 0.3 0.4 Xa', '0 0 0 1 (Ink) 0.5 Xs'));
    final AiNativeInks first = model.redefine(ink: model.inks.single, cmyk: inkCmyk(), artwork: inkPrinting(model));
    final AiPdfDocument saved = colorSave(first.records, pdfCommands: 'q 0.2 0.3 0.4 0.5 k 0 0 10 10 re f Q');
    final AiNativeInks reopened = AiNativeInks.decode(
      records: AiNativeRecords.decode(program: AiProgram.decode(bytes: AiNativeData.extract(saved).single.bytes)),
    );
    final AiNativeInks second = reopened.redefine(ink: reopened.inks.single, cmyk: inkCmyk(.9), artwork: inkPrinting(reopened));
    final AiPdfDocument twice = colorSave(second.records, pdfCommands: 'q 0.9 0.3 0.4 0.5 k 0 0 10 10 re f Q');
    final AiNativeInks result = AiNativeInks.decode(
      records: AiNativeRecords.decode(program: AiProgram.decode(bytes: AiNativeData.extract(twice).single.bytes)),
    );
    check(_colors(result.inks.single).single.components).deepEquals([.9, .3, .4, .5]);
    check(result.inks.single.nameBytes).deepEquals(latin1.encode('Ink'));
    for (final PdfPage page in twice.pdf.pages) {
      check(latin1.decode(twice.pdf.pageContent(page))).equals('q 0.9 0.3 0.4 0.5 k 0 0 10 10 re f Q');
    }
  });
}
