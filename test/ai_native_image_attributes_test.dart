import 'dart:convert';

import 'package:checks/checks.dart';
import 'package:illustratorkit/illustratorkit.dart';
import 'package:test/test.dart';

import 'ai_native_document_creation_test.dart';
import 'ai_native_image_creation_test.dart';

/// Creates qualified body images with independent names and sample identities.
AiNativeRasters attributedImages() {
  AiNativeDrawing drawing = AiNativeDrawing.decode(records: newDocumentRecords(blank: true));
  drawing = drawing.createRaster(definition: createdImageDefinition(), layer: drawing.records.program.layers.single);
  drawing = drawing.createRaster(
    definition: createdImageDefinition(id: 'image_2', opacity: 0.8),
    layer: drawing.records.program.layers.single,
  );
  return AiNativeRasters.decode(records: drawing.records);
}

/// Replays literal image attributes independently of the attribute transaction.
Map<String, List<double>> imageAttributeState(AiNativeRecords records, int position, {bool native = true}) {
  final Map<String, List<double>> state = {};
  for (final AiNativeInstruction command in AiNativeDrawing.decode(records: records).items.whereType<AiNativeInstruction>()) {
    if (command.end <= position && (native || !command.isPrivate) && const {'A', 'Xw', 'Xy', 'O'}.contains(command.operator)) {
      state[command.operator] = command.numbers!;
    }
  }
  return state;
}

/// Reads the complete source image and attached dictionary as one exact byte span.
List<int> imageAttributeBytes(AiNativeRasters source, AiNativeRaster image) => source.records.program.bytes.sublist(image.start, image.dictionary?.end ?? image.end);

/// Verifies selected state, preservation, no-ops and unsafe-owner rejection.
void main() {
  test('edits selected image attributes while retaining pixels identities and neighbors', () {
    final AiNativeRasters source = attributedImages();
    final AiNativeRaster selected = source.images.first;
    final AiNativeRasters changed = source.updateAttributes(image: selected, opacity: 0.25, hidden: true, locked: true, overprint: true, nameBytes: utf8.encode('Été'));
    check(imageAttributeState(changed.records, changed.images.first.start)).deepEquals({
      'A': [1],
      'Xw': [1],
      'Xy': [0, 0.25, 0, 0, 0],
      'O': [1],
    });
    check(imageAttributeBytes(changed, changed.images.last)).deepEquals(imageAttributeBytes(source, source.images.last));
    check(imageAttributeState(changed.records, changed.images.last.start)).deepEquals(imageAttributeState(source.records, source.images.last.start));
    check(imageAttributeState(changed.records, changed.records.program.bodyEnd)).deepEquals(imageAttributeState(source.records, source.records.program.bodyEnd));
    check(changed.images.first.colorSamples).deepEquals(selected.colorSamples);
    check(changed.images.first.alphaSamples!).deepEquals(selected.alphaSamples!);
    for (final String field in ['AI10_ArtUID', 'AI24 ImageRawDataUUID', 'AI24 ImageAlphaRawDataUUID']) {
      final AiNativeEntry before = selected.dictionary![field]!;
      final AiNativeEntry after = changed.images.first.dictionary![field]!;
      check(after.container?.entries.single.text() ?? after.text()).equals(before.container?.entries.single.text() ?? before.text());
    }
    check(changed.images.first.dictionary!['AIArtName']!.text(encoding: utf8)).equals('Été');
    check(changed.updateAttributes(image: changed.images.first, opacity: 0.25, hidden: true, locked: true, overprint: true, nameBytes: utf8.encode('Été'))).identicalTo(changed);
  });

  test('restores separate native and printing opacity without changing blend flags', () {
    final AiNativeRasters original = attributedImages();
    final AiProgram program = AiNativeEditor.apply(
      program: original.records.program,
      edits: [AiSourceEdit(start: original.images.first.start, end: original.images.first.start, bytes: '2 0.5 0 1 0 Xy\n%_3 0.2 1 2 1 Xy\n'.codeUnits)],
    );
    final AiNativeRasters source = AiNativeRasters.decode(records: AiNativeRecords.decode(program: program));
    final AiNativeRasters changed = source.updateAttributes(image: source.images.first, opacity: 0.4);
    for (final bool native in [true, false]) {
      check(imageAttributeState(changed.records, changed.images.first.start, native: native)['Xy']!).deepEquals(native ? [3, 0.4, 1, 2, 1] : [2, 0.4, 0, 1, 0]);
      final int suffixEnd = AiNativeDrawing.decode(records: changed.records).items
          .whereType<AiNativeInstruction>()
          .where((command) => command.start >= changed.images.first.dictionary!.end && command.operator == 'Xy')
          .take(2)
          .last
          .end;
      check(imageAttributeState(changed.records, suffixEnd, native: native)['Xy']!).deepEquals(native ? [3, 0.2, 1, 2, 1] : [2, 0.5, 0, 1, 0]);
    }
  });

  test('creates missing names and preserves explicit Unicode on repeated edits', () {
    final AiNativeDrawing initial = AiNativeDrawing.decode(records: newDocumentRecords(blank: true));
    final AiNativeDrawing drawing = initial.createRaster(
      definition: AiNativeRasterDefinition(samples: createdImageSamples(), matrix: [1, 0, 0, 1, 0, 0]),
      layer: initial.records.program.layers.single,
    );
    final AiNativeRasters source = AiNativeRasters.decode(records: drawing.records);
    final AiNativeRasters named = source.updateAttributes(image: source.images.single, nameBytes: [0, 201, 0, 116, 0, 233], unicodeName: true);
    check(named.images.single.dictionary!['AIArtName']!.type).equals('UnicodeString');
    check(named.images.single.dictionary!['AIArtName']!.stringBytes!).deepEquals([0, 201, 0, 116, 0, 233]);
    check(named.updateAttributes(image: named.images.single, nameBytes: [0, 201, 0, 116, 0, 233], unicodeName: true)).identicalTo(named);
    check(() => source.updateAttributes(image: source.images.single, nameBytes: [0], unicodeName: true)).throws<ArgumentError>();
  });

  test('rejects stale handles unknown state and unqualified native dependencies', () {
    final AiNativeRasters original = attributedImages();
    check(() => original.updateAttributes(image: attributedImages().images.first, hidden: true)).throws<ArgumentError>();
    check(() => original.updateAttributes(image: original.images.first, opacity: double.nan)).throws<ArgumentError>();
    for (final String prefix in ['opaqueCommand\n', '0 0 0 0 0 0 Xy\n', '%AI99_UnknownCache\n']) {
      final AiProgram program = AiNativeEditor.apply(
        program: original.records.program,
        edits: [AiSourceEdit(start: original.images.first.start, end: original.images.first.start, bytes: prefix.codeUnits)],
      );
      final AiNativeRasters source = AiNativeRasters.decode(records: AiNativeRecords.decode(program: program));
      check(() => source.updateAttributes(image: source.images.first, opacity: 0.4)).throws<UnsupportedError>();
      check(source.records.program.bytes).deepEquals(program.bytes);
    }
  });

  test('adds image metadata after its optional bare terminator without inventing identities', () {
    final AiNativeRasters original = attributedImages();
    final AiNativeContainer dictionary = original.images.first.dictionary!;
    final AiProgram program = AiNativeEditor.apply(
      program: original.records.program,
      edits: [AiSourceEdit(start: dictionary.start, end: dictionary.end, bytes: [])],
    );
    final AiNativeRasters source = AiNativeRasters.decode(records: AiNativeRecords.decode(program: program));
    check(source.images.first.dictionary).isNull();
    final AiNativeRasters changed = source.updateAttributes(image: source.images.first, nameBytes: 'Picture'.codeUnits, opacity: 0.3);
    check(changed.images.first.dictionary!.entries.length).equals(1);
    check(changed.images.first.dictionary!['AIArtName']!.text()).equals('Picture');
    check(changed.images.first.colorSamples).deepEquals(source.images.first.colorSamples);
    check(changed.images.first.alphaSamples!).deepEquals(source.images.first.alphaSamples!);
    check(imageAttributeState(changed.records, changed.images.first.start)['Xy']!).deepEquals([0, 0.3, 0, 0, 0]);
  });
}
