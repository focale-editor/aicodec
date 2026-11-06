import 'package:checks/checks.dart';
import 'package:illustratorkit/illustratorkit.dart';
import 'package:test/test.dart';

import 'ai_native_document_creation_test.dart' show newDocumentRecords;
import 'ai_native_image_attributes_test.dart' show imageAttributeState;
import 'ai_native_image_creation_test.dart' show createdImageDefinition;
import 'ai_native_mixed_group_artwork_test.dart' show mixedGroup, mixedGroupArtwork;
import 'ai_native_path_artwork_test.dart' show artworkStates;

/// Identifies the same ordinary group independently of source offset changes.
AiNativeGroup _group(AiNativeDrawing drawing) => mixedGroup(AiNativeLayers.decode(drawing: drawing), 'outer');

/// Keeps group flags distinct from those consumed by their actual children.
void main() {
  test('changes group visibility and lock without changing descendant or following flags', () {
    final AiNativeLayers initial = mixedGroupArtwork();
    final AiNativeLayers model = initial.moveArtwork(artwork: initial.rasters.images.single, group: mixedGroup(initial, 'outer'), inheritParentFlags: true);
    final AiNativeDrawing source = model.drawing;
    final AiNativeDrawing changed = source.updateGroupAttributes(group: _group(source), hidden: true, locked: true);
    for (final bool native in [false, true]) {
      final Map<String, List<double>> group = imageAttributeState(changed.records, _group(changed).start, native: native);
      check(group['A']!).deepEquals([1]);
      check(group['Xw']!).deepEquals([1]);
      check(artworkStates(changed, native: native)).deepEquals(artworkStates(source, native: native));
      final AiNativeRaster image = AiNativeRasters.decode(records: changed.records).images.single;
      check(imageAttributeState(changed.records, image.start, native: native)).deepEquals(imageAttributeState(source.records, model.rasters.images.single.start, native: native));
      check(imageAttributeState(changed.records, changed.records.program.bodyEnd, native: native)).deepEquals(imageAttributeState(source.records, source.records.program.bodyEnd, native: native));
    }
    final AiNativeObjects objects = AiNativeObjects.decode(drawing: changed);
    check(objects.forSource(_group(changed)).identifier!.bytes).deepEquals('outer'.codeUnits);
    check(changed.updateGroupAttributes(group: _group(changed), hidden: true, locked: true)).identicalTo(changed);
    final AiNativeDrawing visible = changed.updateGroupAttributes(group: _group(changed), hidden: false);
    final Map<String, List<double>> state = imageAttributeState(visible.records, _group(visible).start);
    check(state['Xw']!).deepEquals([0]);
    check(state['A']!).deepEquals([1]);
  });

  test('restores distinct native and printing inputs immediately inside an empty group', () {
    final AiNativeDrawing initial = mixedGroupArtwork().drawing;
    final AiNativeGroup original = _group(initial);
    final AiProgram program = AiNativeEditor.apply(
      program: initial.records.program,
      edits: [AiSourceEdit(start: original.start, end: original.start, bytes: '0 A\n0 Xw\n%_1 A\n%_1 Xw\n'.codeUnits)],
    );
    final AiNativeDrawing source = AiNativeDrawing.decode(records: AiNativeRecords.decode(program: program));
    final AiNativeDrawing changed = source.updateGroupAttributes(group: _group(source), hidden: false, locked: false);
    for (final bool native in [false, true]) {
      final Map<String, List<double>> selected = imageAttributeState(changed.records, _group(changed).start, native: native);
      check(selected['A']!).deepEquals([0]);
      check(selected['Xw']!).deepEquals([0]);
      final Map<String, List<double>> child = imageAttributeState(changed.records, _group(changed).closing.start, native: native);
      check(child['A']!).deepEquals([if (native) 1 else 0]);
      check(child['Xw']!).deepEquals([if (native) 1 else 0]);
      check(imageAttributeState(changed.records, changed.records.program.bodyEnd, native: native)).deepEquals(imageAttributeState(source.records, source.records.program.bodyEnd, native: native));
    }
  });

  test('creates explicitly hidden locked groups without imposing those flags on new children', () {
    final AiNativeDrawing initial = AiNativeDrawing.decode(records: newDocumentRecords(blank: true));
    final AiNativeDrawing grouped = initial.createGroup(layer: initial.records.program.layers.single, identifierBytes: 'outer'.codeUnits, hidden: true, locked: true);
    final AiNativeDrawing drawing = grouped.createRaster(definition: createdImageDefinition(), parent: _group(grouped));
    final AiNativeRaster image = AiNativeRasters.decode(records: drawing.records).images.single;
    for (final bool native in [false, true]) {
      final Map<String, List<double>> group = imageAttributeState(drawing.records, _group(drawing).start, native: native);
      final Map<String, List<double>> child = imageAttributeState(drawing.records, image.start, native: native);
      check(group['A']!).deepEquals([1]);
      check(group['Xw']!).deepEquals([1]);
      check(child['A']!).deepEquals([0]);
      check(child['Xw']!).deepEquals([0]);
    }
    check(image.alphaSamples!).deepEquals([255, 128]);
  });

  test('rejects stale groups and unknown inputs without changing source bytes', () {
    final AiNativeDrawing source = mixedGroupArtwork().drawing;
    final List<int> original = List.of(source.records.program.bytes);
    check(() => source.updateGroupAttributes(group: _group(mixedGroupArtwork().drawing), hidden: true)).throws<ArgumentError>();
    for (final String opaque in ['opaqueCommand\n', '0 1 A\n', '%AI99_UnknownGroupFlags\n']) {
      final AiProgram program = AiNativeEditor.apply(
        program: source.records.program,
        edits: [AiSourceEdit(start: _group(source).start, end: _group(source).start, bytes: opaque.codeUnits)],
      );
      final AiNativeDrawing unknown = AiNativeDrawing.decode(records: AiNativeRecords.decode(program: program));
      if (opaque == '0 1 A\n') {
        check(() => unknown.updateGroupAttributes(group: _group(unknown), hidden: true, locked: false)).throws<FormatException>();
      } else {
        check(() => unknown.updateGroupAttributes(group: _group(unknown), hidden: true, locked: false)).throws<UnsupportedError>();
      }
      check(unknown.records.program.bytes).deepEquals(program.bytes);
    }
    check(source.records.program.bytes).deepEquals(original);
  });
}
