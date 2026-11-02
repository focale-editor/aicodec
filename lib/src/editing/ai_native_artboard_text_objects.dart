part of 'package:aikit/src/model/ai_native_records.dart';

/// Binds retained drawing text to its selected main or undo-free frame namespace.
Set<AiNativeContainer> _artboardTextObjects(AiNativeLayers layers, List<_ArtboardTextSnapshot> snapshots) {
  final AiNativeDrawing drawing = layers.drawing;
  final Set<AiNativeContainer> privateText = {
    for (final AiNativeGroup group in drawing.groups.where((group) => group.opening.isPrivate))
      if (_readNativeAppearanceLeaf(drawing, group)?.text case final AiNativeContainer text) text,
  };
  final Set<AiNativeContainer> result = {};
  for (final AiNativeContainer record in drawing.records.containers.where((record) => record.type == 'AI11Text')) {
    final int index = _pathOffset(drawing.items, record.start, (item) => item.start);
    if (index == drawing.items.length ||
        !identical(drawing.items[index], record) ||
        drawing.records._projection.isPrivate(record.start) && !privateText.contains(record) ||
        layers.structure.nodeFor(record).versions.isNotEmpty ||
        record.hasBinary ||
        _nativeObjectMetadataComments(drawing, record.start, record.end)) {
      throw UnsupportedError('Retained text requires unconditional ordinary drawing ownership.');
    }
    if (record.entries.map((field) => field.key).toSet().length != record.entries.length ||
        record.entries.any((field) => field.type != null || field.isQualifier || !const {'FreeUndo', 'StoryIndex', 'FrameIndex', 'TextAntialiasing', 'ConfiningPath'}.contains(field.key))) {
      throw UnsupportedError('Retained text has unqualified drawing-reference fields.');
    }
    final int snapshotIndex = _artboardTextRecordIndex(record, 'FreeUndo');
    final int storyIndex = _artboardTextRecordIndex(record, 'StoryIndex');
    final int frameIndex = _artboardTextRecordIndex(record, 'FrameIndex');
    if (snapshotIndex > 1) {
      throw UnsupportedError('Unknown native text snapshot selector.');
    }
    if (snapshotIndex >= snapshots.length || storyIndex >= snapshots[snapshotIndex].stories.length || frameIndex >= snapshots[snapshotIndex].stories[storyIndex].length) {
      throw const FormatException('Native text references an absent snapshot, story or frame.');
    }
    if (record['TextAntialiasing'] != null) {
      _artboardTextRecordIndex(record, 'TextAntialiasing');
    }
    final _ArtboardTextSnapshot snapshot = snapshots[snapshotIndex];
    final int kind = snapshot.frames[snapshot.stories[storyIndex][frameIndex]];
    final AiNativeEntry? confinement = record['ConfiningPath'];
    if (confinement != null) {
      _artboardTextConfinement(AiNativeArt.decode(records: drawing.records, record: _referenceRecord(confinement, 'Art')));
    } else if (kind != 0) {
      throw const FormatException('Retained area/path text has no native confinement.');
    }
    result.add(record);
    final AiNativeItem? following = index + 1 < drawing.items.length ? drawing.items[index + 1] : null;
    if (following case final AiNativeContainer dictionary when dictionary.type == 'ArtDictionary') {
      if (!_sameNativeObjectOwner(layers.structure.nodeFor(record), layers.structure.nodeFor(dictionary)) || _nativeObjectMetadataComments(drawing, record.end, dictionary.end)) {
        throw UnsupportedError('Text metadata crosses its drawing owner.');
      }
      _artboardTextMetadata(dictionary);
      result.add(dictionary);
    }
  }
  return result;
}

/// Requires a single literal integer rather than ignoring extra operands.
int _artboardTextRecordIndex(AiNativeContainer record, String field) {
  final List<double>? values = record[field]?.numbers;
  if (values?.length != 1 || !values!.single.isFinite || values.single < 0 || values.single > 9007199254740991 || values.single != values.single.truncate()) {
    throw const FormatException('Invalid native text drawing index.');
  }
  return values.single.toInt();
}

/// Preserves direct text identities, names and rotation without changing their use.
void _artboardTextMetadata(AiNativeContainer record, {bool confinement = false}) {
  if (record.hasBinary || record.notRecorded) {
    throw UnsupportedError('Retained text metadata requires ordinary literal fields.');
  }
  _referenceFields(
    record,
    {
      'String': {
        'BBAccumRotation',
        if (!confinement) ...['AIArtName', 'Object name', 'AI24 TextStoryRawDataUUID'],
      },
    },
    nested: {
      if (!confinement) 'AI10_ArtUID': (field) => _referenceRecord(field, 'XMLUID'),
    },
  );
  for (final AiNativeEntry field in record.entries.where((field) => field.key != 'AI10_ArtUID')) {
    if (field.stringBytes == null) {
      throw const FormatException('Retained text metadata requires literal strings.');
    }
    if (field.key == 'BBAccumRotation') {
      final double? angle = double.tryParse(latin1.decode(field.stringBytes!));
      if (field.type != 'String' || angle == null || !angle.isFinite || angle.abs() > 9007199254740991) {
        throw const FormatException('Invalid retained text rotation.');
      }
    }
  }
}

/// Qualifies an unchanged unpainted curve without executing confinement artwork.
void _artboardTextConfinement(AiNativeArt art) {
  final List<AiNativeInstruction> geometry = [];
  AiNativeInstruction? count;
  bool opened = false;
  bool finished = false;
  bool consumed = false;
  bool? closure;
  for (final AiNativeItem item in art.items) {
    if (item is AiNativeContainer) {
      if (!consumed || finished || item.type != 'ArtDictionary') {
        throw UnsupportedError('Retained text confinement has unqualified nested artwork.');
      }
      _artboardTextMetadata(item, confinement: true);
      continue;
    }
    final AiNativeInstruction command = item as AiNativeInstruction;
    final String operator = command.operator;
    if (command.isPrivate) {
      throw UnsupportedError('Retained text confinement requires ordinary geometry.');
    }
    if (operator == 'X=') {
      if (opened || command.operands.isNotEmpty) {
        throw const FormatException('Invalid retained text confinement opener.');
      }
      opened = true;
    } else if (!opened || finished) {
      throw const FormatException('Retained text confinement lies outside its wrapper.');
    } else if (operator == 'X+') {
      if (!consumed || command.operands.isNotEmpty) {
        throw const FormatException('Invalid retained text confinement terminator.');
      }
      finished = true;
    } else if (_nativeGeometry.contains(operator)) {
      if (consumed || closure != null || (operator == 'm') != geometry.isEmpty || command.numbers == null || command.numbers!.any((value) => value.abs() > 9007199254740991)) {
        throw UnsupportedError('Retained text confinement requires one portable contiguous curve.');
      }
      try {
        AiPathSegment(operator: operator, coordinates: command.numbers!);
      } on ArgumentError {
        throw const FormatException('Invalid retained text confinement geometry.');
      }
      geometry.add(command);
    } else if (operator == 'h' || operator == 'H') {
      if (geometry.isEmpty || consumed || closure != null || command.operands.isNotEmpty) {
        throw const FormatException('Invalid retained text confinement closure.');
      }
      closure = operator == 'h';
    } else if (operator == 'n' || operator == 'N') {
      if (geometry.isEmpty || consumed || command.operands.isNotEmpty) {
        throw const FormatException('Invalid retained text confinement paint boundary.');
      }
      final bool closed = operator == 'n' || closure == true;
      if (count != null) {
        final List<double> first = geometry.first.numbers!;
        final List<double> last = geometry.last.numbers!;
        if (count.numbers!.single != geometry.length - (closed ? 1 : 0) || closed && (first[0] != last[last.length - 2] || first[1] != last.last)) {
          throw const FormatException('Retained text confinement has an inconsistent point count.');
        }
      }
      consumed = true;
    } else if (geometry.isNotEmpty) {
      throw UnsupportedError('Retained text confinement has interleaved state or unsupported painting.');
    } else if (operator == 'As') {
      if (count != null || command.numbers?.length != 1 || command.numbers!.single < 0 || command.numbers!.single != command.numbers!.single.truncate()) {
        throw const FormatException('Invalid retained text confinement point count.');
      }
      count = command;
    } else if (_nativeArtworkStateKey(command) == null) {
      throw UnsupportedError('Retained text confinement has no dependency contract for $operator.');
    }
  }
  if (!opened || !finished || !consumed) {
    throw const FormatException('Incomplete retained text confinement.');
  }
}
