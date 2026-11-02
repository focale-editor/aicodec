import 'dart:convert';

import 'package:aicodec/aicodec.dart';
import 'package:checks/checks.dart';
import 'package:test/test.dart';

import 'ai_native_artwork_movement_test.dart' show movementPath;
import 'ai_native_identity_lifecycle_test.dart' show artworkCopyIdentifiers, identityLifecycleSource, layerCopyIdentifiers;
import 'ai_native_objects_test.dart' show objectSource;

/// Keeps unknown identity owners distinct from the selected editable objects.
String identityReservationSource(String setup) => identityLifecycleSource.replaceFirst('%%EndSetup', '$setup\n%%EndSetup');

/// Decodes the complete source, including private and versioned setup records.
AiNativeLayers _model(String source) => AiNativeLayers.decode(
  drawing: AiNativeDrawing.decode(
    records: AiNativeRecords.decode(program: AiProgram.decode(bytes: latin1.encode(source))),
  ),
);

/// Reads all native XML wrappers, including those outside recognized artwork.
List<String> _identifiers(AiNativeLayers model) => model.drawing.records.containers.where((record) => record.type == 'XMLUID').map((record) => record.entries.single.text()!).toList();

/// Qualifies namespace reservation without guessing the semantics of references.
void main() {
  test('reserves XML wrappers outside artwork dictionaries for path copies', () {
    for (final String setup in [
      '/XMLUID : (reserved) ;',
      '/Dictionary : /XMLUID : (reserved) ; (Unrecognized) , ;',
      '/Document : /Dictionary : /XMLUID : (reserved) ; (FutureReference) , ; /Recorded , ;',
      '%_/Dictionary : /XMLUID : (reserved) ; (PrivateReference) , ;',
    ]) {
      final String input = identityReservationSource(setup);
      final AiNativeLayers model = _model(input);
      check(() => model.drawing.duplicatePaths(paths: [model.drawing.paths.first], identifiers: {model.drawing.paths.first: latin1.encode('reserved')})).throws<ArgumentError>();
      check(latin1.decode(model.drawing.records.program.bytes)).equals(input);
    }
  });

  test('shares reservations across group, layer and empty-layer allocation', () {
    final AiNativeLayers model = _model(identityReservationSource('/Dictionary : /XMLUID : (reserved) ; (UnknownOwner) , ;'));
    final Map<AiNativeItem, List<int>> groupIds = {
      model.drawing.groups.single: latin1.encode('reserved'),
      model.drawing.paths[1]: latin1.encode('fresh_child'),
    };
    check(() => model.drawing.duplicateGroups(groups: model.drawing.groups, identifiers: groupIds)).throws<ArgumentError>();
    final Map<AiNativeLayer, List<int>> layerIds = layerCopyIdentifiers(model);
    layerIds[model.layers.first] = latin1.encode('reserved');
    check(() => model.duplicate(layers: [model.layers.first], identifiers: layerIds, artworkIdentifiers: artworkCopyIdentifiers(model), discardViewState: true)).throws<ArgumentError>();
    check(() => model.insertAfter(after: model.layers.first, nameBytes: latin1.encode('New layer'), identifierBytes: latin1.encode('reserved'), discardViewState: true)).throws<ArgumentError>();
  });

  test('reserves both saved branches and decoded escaped or hexadecimal names', () {
    const String setup =
        '%AI17_Begin_Content_if_version_gt:24 4\n'
        '/Dictionary : /XMLUID : (reserved_older) ; (OldOwner) , ;\n'
        '%AI17_Alternate_Content\n'
        '/Dictionary : /XMLUID : <72657365727665645f6e65776572> ; (NewOwner) , ;\n'
        '%AI17_End_Versioned_Content\n'
        r'/XMLUID : (reserved\137escaped) ;';
    final AiNativeLayers model = _model(identityReservationSource(setup));
    for (final String name in ['reserved_older', 'reserved_newer', 'reserved_escaped']) {
      check(() => model.drawing.duplicatePaths(paths: [model.drawing.paths.first], identifiers: {model.drawing.paths.first: latin1.encode(name)})).throws<ArgumentError>();
    }
  });

  test('preserves unknown owners and repeated reservations when allocating fresh IDs', () {
    const String setup = '/Dictionary : /XMLUID : (reserved) ; (First) , /XMLUID : (reserved) ; (Second) , ;';
    final AiNativeLayers model = _model(identityReservationSource(setup));
    final AiNativeLayers copied = model.duplicate(layers: [model.layers.first], identifiers: layerCopyIdentifiers(model), artworkIdentifiers: artworkCopyIdentifiers(model), discardViewState: true);
    check(_identifiers(copied).where((value) => value == 'reserved')).length.equals(2);
    check(latin1.decode(copied.drawing.records.program.bytes)).contains(setup);
    check(_identifiers(copied)).contains('Copy_path_child');
    check(() => copied.insertAfter(after: copied.layers.first, nameBytes: [], identifierBytes: latin1.encode('reserved'))).throws<ArgumentError>();
    check(() => copied.insertAfter(after: copied.layers.first, nameBytes: [], identifierBytes: latin1.encode('Copy_path_child'))).throws<ArgumentError>();
  });

  test('refuses new identities when an XML wrapper has an unresolved value shape', () {
    for (final String value in ['', '(first) (second)', '19', '/Array : (value) , ;', '(value) /Named', '(first) , (second)', '/NotRecorded']) {
      final String input = identityReservationSource('/Dictionary : /XMLUID : $value ; (Unresolved) , ;');
      final AiNativeLayers model = _model(input);
      check(() => model.drawing.duplicatePaths(paths: [model.drawing.paths.first], identifiers: {model.drawing.paths.first: latin1.encode('fresh')})).throws<UnsupportedError>();
      check(latin1.decode(model.drawing.records.program.bytes)).equals(input);
    }
  });

  test('does not require a new identity namespace for anonymous copies', () {
    final AiNativeLayers model = _model(objectSource('1 1 1 1 0 0 0 79 128 255 Lb\nu\n${movementPath(10)}\nU\nLB', setup: '/XMLUID : 19 ;'));
    check(model.drawing.duplicatePaths(paths: model.drawing.paths).paths).length.equals(2);
    check(model.drawing.duplicateGroups(groups: model.drawing.groups).groups).length.equals(2);
    check(model.duplicate(layers: model.layers).layers).length.equals(2);
    check(model.insertAfter(after: model.layers.single, nameBytes: []).layers).length.equals(2);
  });

  test('does not reserve ordinary names or embedded-document XML identities', () {
    const String setup =
        '/Dictionary : (fresh) /String (Name) , ;\n'
        '%%BeginDocument: embedded.ai\n/XMLUID : (fresh) ;\n%%EndDocument';
    final AiNativeLayers model = _model(identityReservationSource(setup));
    final AiNativeDrawing copied = model.drawing.duplicatePaths(paths: [model.drawing.paths.first], identifiers: {model.drawing.paths.first: latin1.encode('fresh')});
    check(latin1.decode(copied.records.program.bytes)).contains(setup);
    check(copied.paths).length.equals(model.drawing.paths.length + 1);
  });
}
