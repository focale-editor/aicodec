part of 'ai_native_text.dart';

/// Moves native frame resources and every referring confinement path together.
extension AiNativeTextFrameEditing on AiNativeTextDocument {
  /// Translates point, area or path frames without recomposing their local text.
  ///
  /// Offsets use drawing points, with y increasing upwards. Existing frame
  /// matrices receive a canvas-space translation; untransformed paths, positions,
  /// styles and local glyph caches stay unchanged. Every main-model drawing
  /// reference to a selected frame has its `/ConfiningPath` translated as well.
  /// Linked frames can be moved separately without changing story order or flow.
  ///
  /// Confinement must be one unpainted path without transforms, plug-ins or live
  /// shape metadata. Multiple main text documents, missing references, unknown
  /// frame types and nonfinite output reject the entire operation. DSC bounds
  /// expand conservatively; artboards remain fixed. The host must regenerate
  /// PDF/printable appearances, effects and previews before a synchronized save.
  AiNativeTextDocument translateFrames({required List<AiNativeTextFrame> frames, required double deltaX, required double deltaY}) {
    if (!deltaX.isFinite ||
        !deltaY.isFinite ||
        frames.isEmpty ||
        frames.toSet().length != frames.length ||
        frames.any((frame) => frame.index >= this.frames.length || !identical(this.frames[frame.index], frame))) {
      throw ArgumentError('Translation requires finite offsets and distinct frames from this snapshot.');
    }
    if (deltaX == 0 && deltaY == 0) {
      return this;
    }
    if (records.containers.where((record) => record.type == 'AI11TextDocument').length != 1) {
      throw UnsupportedError('Frame translation requires an unambiguous main text document.');
    }
    final Map<int, AiNativeTextFrame> selected = {for (final AiNativeTextFrame frame in frames) frame.index: frame};
    final Map<PsEngineValue, PsEngineValue> replacements = {};
    for (final AiNativeTextFrame frame in frames) {
      if (frame.kind == .unknown) {
        throw UnsupportedError('Cannot translate an unknown Illustrator frame type.');
      }
      final List<double> matrix = frame.matrix ?? [1, 0, 0, 1, 0, 0];
      final List<double> translated = [...matrix.take(4), matrix[4] + deltaX, matrix[5] - deltaY];
      if (translated.any((value) => !value.isFinite)) {
        throw ArgumentError('Frame translation exceeds finite matrix coordinates.');
      }
      final PsEngineDictionary settings = frame.settings ?? PsEngineDictionary(values: {});
      final bool named = frame.record.values.containsKey('Data') || (engine.root as PsEngineDictionary).values.containsKey('DocumentResources');
      replacements[frame.record] = PsEngineDictionary(
        values: {
          ...frame.record.values,
          _featureKey(frame.record, '2', 'Data', named): PsEngineDictionary(
            values: {
              ...settings.values,
              _featureKey(settings, '2', 'FrameMatrix', named): PsEngineArray(values: [for (final double value in translated) PsEngineNumber(value: value)]),
            },
          ),
        },
      );
    }
    final List<AiSourceEdit> edits = [];
    final Set<(int, int)> referenced = {};
    for (final AiNativeTextObject object in objects) {
      if (object.usesUndoFreeModel) {
        continue;
      }
      if (object.storyIndex >= stories.length || object.frameIndex >= stories[object.storyIndex].frameIndices.length) {
        throw const FormatException('Invalid Illustrator drawing-to-frame reference.');
      }
      final int index = stories[object.storyIndex].frameIndices[object.frameIndex];
      final AiNativeTextFrame? frame = selected[index];
      if (frame == null) {
        continue;
      }
      referenced.add((object.storyIndex, object.frameIndex));
      final AiNativeEntry? entry = object.record['ConfiningPath'];
      final AiNativeContainer? path = entry?.container;
      if (entry != null && path == null || frame.kind != .point && path == null) {
        throw const FormatException('Native area/path text requires an owned confinement path.');
      }
      if (path != null) {
        edits.addAll(_translateTextConfinement(AiNativeArt.decode(records: records, record: path), deltaX, deltaY));
      }
    }
    final Set<int> used = {};
    for (final AiNativeTextStory story in stories) {
      if (story.frameIndices.any(selected.containsKey)) {
        _knownTextKeys(_dictionary(story.view), {'0', 'Frames', '1', 'RenderedData', '2', 'Strikes'}, 'view');
      }
      for (int index = 0; index < story.frameIndices.length; index++) {
        if (selected.containsKey(story.frameIndices[index])) {
          used.add(story.frameIndices[index]);
          if (!referenced.contains((story.index, index))) {
            throw const FormatException('Selected Illustrator frame has no matching drawing object.');
          }
        }
      }
    }
    if (used.length != selected.length) {
      throw ArgumentError('Selected Illustrator frame is not used by a main text story.');
    }
    edits.addAll(AiNativeEditor.translationBoundsEdits(program: records.program, deltaX: deltaX, deltaY: deltaY));
    final PsEngineDocument translated = engine.replaceValues(replacements: replacements);
    final AiNativeRecords changed = AiNativeRecords.decode(
      program: AiNativeEditor.apply(program: records.program, edits: edits),
    );
    final AiNativeRecords rewritten = changed.replaceBinary(container: changed.containers.singleWhere((record) => record.type == 'AI11TextDocument'), bytes: translated.bytes);
    return AiNativeTextDocument.decode(records: rewritten, limits: engine.limits);
  }
}

/// Translates one simple confinement without altering its native curve operators.
List<AiSourceEdit> _translateTextConfinement(AiNativeArt art, double deltaX, double deltaY) {
  final List<AiSourceEdit> edits = [];
  bool wrapper = false;
  bool finished = false;
  bool path = false;
  bool consumed = false;
  for (final AiNativeItem item in art.items) {
    if (item is AiNativeContainer) {
      if (!consumed || item.type != 'ArtDictionary' || item.entries.any((entry) => entry.key != 'BBAccumRotation')) {
        throw UnsupportedError('Confinement metadata requires its own geometry editor.');
      }
      continue;
    }
    final AiNativeInstruction command = item as AiNativeInstruction;
    final String operator = command.operator;
    if (operator == 'X=') {
      if (wrapper || finished || command.operands.isNotEmpty) {
        throw const FormatException('Invalid Illustrator confinement wrapper.');
      }
      wrapper = true;
    } else if (operator == 'X+') {
      if (!wrapper || finished || !consumed || command.operands.isNotEmpty) {
        throw const FormatException('Invalid Illustrator confinement terminator.');
      }
      finished = true;
    } else if (!wrapper || finished) {
      throw const FormatException('Illustrator confinement commands lie outside their wrapper.');
    } else if (const {'m', 'l', 'L', 'c', 'C', 'v', 'V', 'y', 'Y'}.contains(operator)) {
      if (consumed || operator == 'm' && path || operator != 'm' && !path) {
        throw UnsupportedError('Frame translation requires one complete confinement path.');
      }
      final List<double>? coordinates = command.numbers;
      if (coordinates == null) {
        throw const FormatException('Invalid Illustrator confinement coordinates.');
      }
      AiPathSegment(operator: operator, coordinates: coordinates);
      path = true;
      for (int index = 0; index < command.operands.length; index++) {
        final AiToken token = command.operands[index];
        final double value = coordinates[index] + (index.isEven ? deltaX : deltaY);
        if (!value.isFinite) {
          throw ArgumentError('Confinement translation exceeds finite coordinates.');
        }
        edits.add(AiSourceEdit(start: token.start, end: token.end, bytes: latin1.encode(value.toString())));
      }
    } else if (operator == 'n' || operator == 'N') {
      if (!path || consumed || command.operands.isNotEmpty) {
        throw const FormatException('Invalid Illustrator confinement path termination.');
      }
      consumed = true;
    } else if (operator == 'h' || operator == 'H') {
      if (!path || consumed || command.operands.isNotEmpty) {
        throw const FormatException('Invalid Illustrator confinement closure.');
      }
    } else if (!_textConfinementState.contains(operator)) {
      throw UnsupportedError('Cannot translate confinement operator $operator.');
    }
  }
  if (!wrapper || !finished || !consumed) {
    throw const FormatException('Incomplete Illustrator confinement path.');
  }
  return edits;
}

/// Nonpositional state retained around an unpainted confinement path.
const Set<String> _textConfinementState = {'Ap', 'As', 'D', 'Xy', 'J', 'j', 'w', 'M', 'd', 'XR', 'O', 'R', 'g', 'G', 'k', 'K', 'Xa', 'XA', 'x', 'X', 'Xx', 'XX', 'Xk', 'XK', 'Xs', 'XS', 'Xz', 'XZ'};
