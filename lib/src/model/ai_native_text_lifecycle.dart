part of 'ai_native_text.dart';

/// Host-authored native frame geometry, without composition or printable glyphs.
///
/// [resource] uses the document's compact or named ATE spelling. Area/path frames
/// also require their complete `/Art` confinement payload, including `X=`/`X+`.
/// The host supplies matching geometry in both native coordinate spaces.
final class AiNativeTextFrameDefinition {
  /// Native position, curve and settings; identities are allocated on insertion.
  final PsEngineDictionary resource;

  /// Unpainted drawing-space confinement, absent for ordinary point text.
  final List<int>? confinement;

  /// Native drawing antialiasing choice, copied explicitly during duplication.
  final int? antialiasing;

  /// Optional saved drawing frame angle, supplied with matching native geometry.
  final double? rotationRadians;

  /// Captures immutable native geometry for a new resource and drawing object.
  AiNativeTextFrameDefinition({required this.resource, List<int>? confinement, this.antialiasing = 2, this.rotationRadians})
    : confinement = confinement == null ? null : List.unmodifiable(confinement) {
    if (antialiasing != null && (antialiasing! < 0 || antialiasing! > 9007199254740991) || rotationRadians != null && (!rotationRadians!.isFinite || rotationRadians!.abs() > 9007199254740991)) {
      throw ArgumentError('Invalid text drawing antialiasing or rotation.');
    }
    if (confinement != null && confinement.any((byte) => byte < 0 || byte > 255)) {
      throw ArgumentError('Text confinement requires byte data.');
    }
  }

  /// Creates an ordinary point frame in native ATE coordinates (y down).
  factory AiNativeTextFrameDefinition.point({required double x, required double y, bool named = false}) {
    if (!x.isFinite || !y.isFinite || x.abs() > 9007199254740991 || y.abs() > 9007199254740991) {
      throw ArgumentError('Point text requires finite portable coordinates.');
    }
    return AiNativeTextFrameDefinition(
      resource: PsEngineDictionary(
        values: {
          named ? 'Position' : '0': PsEngineArray(
            values: [
              PsEngineNumber(value: x),
              PsEngineNumber(value: y),
            ],
          ),
          named ? 'Data' : '2': PsEngineDictionary(values: {}),
        },
      ),
    );
  }
}

/// Changes native story/frame ownership atomically with drawing references.
extension AiNativeTextLifecycle on AiNativeTextDocument {
  /// Creates a styled story and its ordered frames at the end of [layer].
  ///
  /// A null layer selects the program root. Existing resources are retained and
  /// new ones appended. The returned story is `stories.last`. Supply composition
  /// and a matching PDF before saving; no glyphs or font metrics are invented.
  /// [appearanceParent] inserts into an empty private wrapper of a qualified
  /// appearance pair; the host must refresh its printing view before saving.
  /// Only unconditional text with qualified local dependencies can be
  /// changed. Unknown reference owners and text appearance expansions reject.
  AiNativeTextDocument createStory({
    required String text,
    required List<AiNativeTextFrameDefinition> frames,
    AiNativeTextStyle? characterStyle,
    AiNativeTextStyle? paragraphStyle,
    AiLayer? layer,
    AiNativeGroup? appearanceParent,
  }) {
    _editableText(text);
    if (frames.isEmpty || frames.length > engine.limits.maxNodes ~/ 8) {
      throw ArgumentError('A new text story requires at least one frame.');
    }
    if (characterStyle != null && !characterStyles.contains(characterStyle) || paragraphStyle != null && !paragraphStyles.contains(paragraphStyle)) {
      throw ArgumentError('Text styles must belong to this snapshot and resource kind.');
    }
    final _TextLifecycle edit = _TextLifecycle(source: this);
    if (appearanceParent != null && frames.length != 1) {
      throw ArgumentError('One private appearance wrapper owns exactly one text frame.');
    }
    if (layer != null && appearanceParent != null) {
      throw ArgumentError('Select a layer or an appearance wrapper, not both.');
    }
    final int position = appearanceParent == null ? edit.insertion(layer) : validateTextAppearanceParent(records: records, parent: appearanceParent);
    final bool named = edit.named;
    final String content = '$text\r';
    final _TextEditBudget budget = _TextEditBudget(remaining: engine.limits.maxNodes ~/ 4);
    if (content.length > (engine.limits.maxStringBytes - 2) ~/ 2) {
      throw const FormatException('New text exceeds the engine string limit.');
    }
    final Map<String, PsEngineValue> model = {named ? 'Text' : '0': PsEngineString.fromText(text: content)};
    for (final (bool paragraph, int? style) in [(false, characterStyle?.index ?? normalCharacterStyleIndex), (true, paragraphStyle?.index ?? normalParagraphStyleIndex)]) {
      if (style == null) {
        throw UnsupportedError('New text requires resolvable character and paragraph styles.');
      }
      final List<PsEngineValue> runs = [];
      int start = 0;
      while (start < content.length) {
        budget.take();
        final int end = paragraph ? _paragraphRunEnd(content, start) : content.length;
        runs.add(
          PsEngineDictionary(
            values: {
              named ? 'RunData' : '0': PsEngineDictionary(values: {named ? (paragraph ? 'ParagraphSheet' : 'StyleSheet') : '0': PsEngineNumber(value: style)}),
              named ? 'Length' : '1': PsEngineNumber(value: end - start),
            },
          ),
        );
        start = end;
      }
      model[named ? (paragraph ? 'ParagraphRun' : 'StyleRun') : (paragraph ? '5' : '6')] = PsEngineDictionary(values: {named ? 'RunArray' : '0': PsEngineArray(values: runs)});
    }
    final List<int> indices = [for (final AiNativeTextFrameDefinition frame in frames) edit.addFrame(frame)];
    edit.storyValues.add(
      PsEngineDictionary(
        values: {
          named ? 'Model' : '0': PsEngineDictionary(values: model),
          named ? 'View' : '1': edit.view(indices),
        },
      ),
    );
    edit.insertObjects(position, stories.length, indices, frames, private: appearanceParent != null);
    return edit.finish();
  }

  /// Duplicates a complete story with fresh frame and inline-style identities.
  ///
  /// New drawing references follow the final source frame. Local composition is
  /// invalidated; fonts and shared styles remain shared. The clone is last.
  AiNativeTextDocument duplicateStory({required AiNativeTextStory story}) {
    final _TextLifecycle edit = _TextLifecycle(source: this)..requireStory(story);
    final List<AiNativeTextFrameDefinition> definitions = [for (final int index in story.frameIndices) edit.definition(index)];
    final List<int> indices = [for (final AiNativeTextFrameDefinition definition in definitions) edit.addFrame(definition)];
    final PsEngineDictionary model = _dictionary(_field(story.record, '0', 'Model'));
    edit.storyValues.add(
      PsEngineDictionary(
        values: {
          _textKey(story.record, '0', 'Model'): edit.clone(model),
          _textKey(story.record, '1', 'View'): edit.view(indices),
        },
      ),
    );
    final AiNativeTextObject last = objects.where((object) => object.storyIndex == story.index).last;
    edit.insertObjects(edit.objectEnd(last), stories.length, indices, definitions);
    return edit.finish();
  }

  /// Removes one story, its drawing objects and its exclusively owned frames.
  ///
  /// Remaining story/frame indices and cached frame strikes are remapped.
  /// Typography resources and the separate undo-free snapshot remain unchanged.
  AiNativeTextDocument removeStory({required AiNativeTextStory story}) {
    final _TextLifecycle edit = _TextLifecycle(source: this)..requireStory(story);
    edit.storyValues.removeAt(story.index);
    edit.removeFrames(story.frameIndices.toSet());
    for (final AiNativeTextObject object in objects) {
      if (object.storyIndex == story.index) {
        edit.removeObject(object);
      } else if (object.storyIndex > story.index) {
        edit.reference(object, 'StoryIndex', object.storyIndex - 1);
        edit.invalidateMetadata(object);
      }
    }
    return edit.finish();
  }

  /// Inserts a new linked frame at a story-local [index], preserving model text.
  ///
  /// New drawing artwork follows the story's last existing frame. Recompose the
  /// complete story after changing its flow; all its saved caches are removed.
  AiNativeTextDocument insertFrame({required AiNativeTextStory story, required int index, required AiNativeTextFrameDefinition frame}) {
    final _TextLifecycle edit = _TextLifecycle(source: this)..requireStory(story);
    RangeError.checkValueInInterval(index, 0, story.frameIndices.length, 'index');
    final int resource = edit.addFrame(frame);
    final List<int> indices = [...story.frameIndices]..insert(index, resource);
    edit.storyValues[story.index] = edit.withFrames(story.record, indices);
    for (final AiNativeTextObject object in objects.where((object) => object.storyIndex == story.index)) {
      if (object.frameIndex >= index) {
        edit.reference(object, 'FrameIndex', object.frameIndex + 1);
      }
      edit.invalidateMetadata(object);
    }
    final AiNativeTextObject last = objects.where((object) => object.storyIndex == story.index).last;
    edit.insertObjects(edit.objectEnd(last), story.index, [resource], [frame], firstFrame: index);
    return edit.finish();
  }

  /// Duplicates geometry immediately after its source frame in the same story.
  ///
  /// This extends the linked flow; use [duplicateStory] to duplicate its content.
  AiNativeTextDocument duplicateFrame({required AiNativeTextFrame frame}) {
    final _TextLifecycle edit = _TextLifecycle(source: this);
    final AiNativeTextStory story = edit.owner(frame);
    return insertFrame(story: story, index: story.frameIndices.indexOf(frame.index) + 1, frame: edit.definition(frame.index));
  }

  /// Replaces complete frame geometry while retaining its identity and flow.
  ///
  /// The host supplies matching ATE geometry and drawing confinement. The frame
  /// index and UUID remain stable, and other frame resources are untouched.
  /// Composition and raw-data caches for the owning story are invalidated; call
  /// `withGlyphLayout` or `withComposedText` before a synchronized save.
  AiNativeTextDocument replaceFrame({required AiNativeTextFrame frame, required AiNativeTextFrameDefinition definition}) {
    final _TextLifecycle edit = _TextLifecycle(source: this);
    final AiNativeTextStory story = edit.owner(frame);
    edit.validateFrame(definition);
    final PsEngineDictionary wrapper = _dictionary(edit.frameValues[frame.index]);
    final PsEngineValue? identity = _field(frame.record, '97', 'UUID');
    final Map<String, PsEngineValue> geometry = {...definition.resource.values}
      ..remove('97')
      ..remove('UUID');
    if (identity != null) {
      geometry[edit.named ? 'UUID' : '97'] = identity;
    }
    edit.frameValues[frame.index] = PsEngineDictionary(
      values: {
        ...wrapper.values,
        _textKey(wrapper, '0', 'Resource'): PsEngineDictionary(values: geometry),
      },
    );
    edit.storyValues[story.index] = edit.withFrames(story.record, story.frameIndices);
    final AiNativeTextObject object = edit.objectsByFrame[frame.index]!;
    edit.edits.add(
      AiSourceEdit(
        start: object.record.start,
        end: edit.objectEnd(object),
        bytes: edit
            .objectBytes(story.index, object.frameIndex, definition, private: _textPrivateAt(records.program, object.record.start))
            .skip(_textPrivateAt(records.program, object.record.start) ? 2 : 0)
            .toList(),
      ),
    );
    for (final AiNativeTextObject neighbor in edit.objectsByStory[story.index]!) {
      if (!identical(neighbor, object)) {
        edit.invalidateMetadata(neighbor);
      }
    }
    return edit.finish();
  }

  /// Removes one linked frame and invalidates its story's composition.
  ///
  /// The final frame cannot be removed independently: use [removeStory] to also
  /// remove its content. Remaining global references and cached strikes remap.
  AiNativeTextDocument removeFrame({required AiNativeTextFrame frame}) {
    final _TextLifecycle edit = _TextLifecycle(source: this);
    final AiNativeTextStory story = edit.owner(frame);
    if (story.frameIndices.length == 1) {
      throw ArgumentError('Remove the story explicitly when deleting its final frame.');
    }
    final int local = story.frameIndices.indexOf(frame.index);
    edit.storyValues[story.index] = edit.withFrames(story.record, [...story.frameIndices]..removeAt(local));
    edit.removeFrames({frame.index});
    for (final AiNativeTextObject object in objects.where((object) => object.storyIndex == story.index)) {
      if (object.frameIndex == local) {
        edit.removeObject(object);
      } else {
        if (object.frameIndex > local) {
          edit.reference(object, 'FrameIndex', object.frameIndex - 1);
        }
        edit.invalidateMetadata(object);
      }
    }
    return edit.finish();
  }
}

/// Bounded mutation plan retaining source handles until the atomic commit.
final class _TextLifecycle {
  /// Original immutable text snapshot.
  final AiNativeTextDocument source;

  /// Original root and resource table ownership.
  late final PsEngineDictionary root = _dictionary(source.engine.root);

  /// Existing resource tables; typography resources never change here.
  late final PsEngineDictionary resources = _dictionary(_field(root, '0', 'DocumentResources'));

  /// Native text object namespace.
  late final PsEngineDictionary objects = _dictionary(_field(root, '1', 'DocumentObjects'));

  /// Existing frame resource table, including its optional display order.
  late final PsEngineDictionary frameSet = _optionalDictionary(_field(resources, '8', 'TextFrameSet')) ?? PsEngineDictionary(values: {});

  /// Authored field spelling for new records.
  late final bool named = root.values.containsKey('DocumentResources');

  /// Mutable transaction-local resource wrappers.
  late final List<PsEngineValue> frameValues = [..._array(_field(frameSet, '0', 'Resources'))];

  /// Mutable transaction-local story records.
  late final List<PsEngineValue> storyValues = [for (final AiNativeTextStory story in source.stories) story.record];

  /// Display-list wrappers, when the source supplies an explicit list.
  late final List<PsEngineValue>? display = _field(frameSet, '1', 'DisplayList') == null ? null : [..._array(_field(frameSet, '1', 'DisplayList'))];

  /// Fresh identities shared across all clones in this transaction.
  late final _TextIdentifiers identifiers = _TextIdentifiers(engine: source.engine);

  /// Aggregate allocation budget for cloned model and frame nodes.
  late int remainingNodes = source.engine.limits.maxNodes;

  /// Drawing-side source edits, disjoint from the engine payload.
  final List<AiSourceEdit> edits = [];

  /// Following dictionaries exclusively owned by a text object.
  final Map<AiNativeTextObject, AiNativeContainer> metadata = {};

  /// Direct drawing ownership for each global frame resource.
  final Map<int, AiNativeTextObject> objectsByFrame = {};

  /// Source-ordered drawing objects grouped once for linear batch edits.
  final Map<int, List<AiNativeTextObject>> objectsByStory = {};

  /// Prevents duplicate invalidation when several operations touch an owner.
  final Set<AiNativeTextObject> invalidated = {};

  /// Validates the complete reference namespace before scheduling any mutation.
  _TextLifecycle({required this.source}) {
    if (source.records.containers.where((record) => record.type == 'AI11TextDocument').length != 1 || source.referenceIssues.isNotEmpty) {
      throw UnsupportedError('Text lifecycle requires one resolved main-model namespace.');
    }
    _knownTextKeys(root, {'0', 'DocumentResources', '1', 'DocumentObjects', '98'}, 'document');
    _knownTextKeys(resources, {
      '1',
      'FontSet',
      '2',
      'MojiKumiCodeToClassSet',
      '3',
      'MojiKumiTableSet',
      '4',
      'KinsokuSet',
      '5',
      'StyleSheetSet',
      '6',
      'ParagraphSheetSet',
      '8',
      'TextFrameSet',
      '9',
      'ListStyleSet',
    }, 'resource namespace');
    if (root['98'] case final PsEngineValue value) {
      final PsEngineDictionary version = _dictionary(value);
      _knownTextKeys(version, {'0'}, 'version');
      if (!{7, 9}.contains(_index(version['0']))) {
        throw UnsupportedError('Text lifecycle requires the qualified ATE 7/9 profile.');
      }
    }
    _knownTextKeys(objects, {'0', 'DocumentSettings', '1', 'TextObjects', '2', 'NormalStyleSheet', '3', 'NormalParagraphSheet'}, 'document objects');
    _knownTextKeys(frameSet, {'0', 'Resources', '1', 'DisplayList'}, 'frame table');
    final Set<int> used = {};
    for (final AiNativeTextStory story in source.stories) {
      _knownTextKeys(story.record, {'0', 'Model', '1', 'View'}, 'story');
      final PsEngineDictionary model = _dictionary(_field(story.record, '0', 'Model'));
      _knownTextKeys(model, {'0', 'Text', '5', 'ParagraphRun', '6', 'StyleRun', '10', 'StorySheet', 'KernRun', 'AlternateGlyphRun', 'HyperlinkRun'}, 'model');
      for (final String name in ['KernRun', 'AlternateGlyphRun', 'HyperlinkRun']) {
        if (model[name] case final PsEngineValue table) {
          _emptyAuxiliaryRuns(_dictionary(table), story.modelText);
        }
      }
      _knownTextKeys(_dictionary(story.view), {'0', 'Frames', '1', 'RenderedData', '2', 'Strikes'}, 'view');
      if (story.frameIndices.isEmpty || story.frameIndices.any((index) => !used.add(index))) {
        throw UnsupportedError('Each story requires distinct, exclusively owned frame resources.');
      }
      for (final PsEngineValue reference in _array(_field(story.view, '0', 'Frames'))) {
        _knownTextKeys(_dictionary(reference), {'0', 'Resource'}, 'frame reference');
      }
    }
    if (used.length != source.frames.length) {
      throw UnsupportedError('Text lifecycle cannot remap orphan frame resources.');
    }
    for (final PsEngineValue wrapper in frameValues) {
      _knownTextKeys(_dictionary(wrapper), {'0', 'Resource'}, 'frame wrapper');
      _validateTextFrame(_dictionary(_field(_dictionary(wrapper), '0', 'Resource')));
    }
    for (final PsEngineValue wrapper in display ?? []) {
      _knownTextKeys(_dictionary(wrapper), {'0', 'Resource'}, 'frame display entry');
      if (_index(_field(_dictionary(wrapper), '0', 'Resource')) >= frameValues.length) {
        throw const FormatException('Text frame display reference is out of range.');
      }
    }
    _drawing();
  }

  /// Checks identity rather than accepting a stale index from another snapshot.
  void requireStory(AiNativeTextStory story) {
    if (!source.stories.contains(story)) {
      throw ArgumentError('Invalid or foreign Illustrator text story.');
    }
  }

  /// Resolves the unique source story owning a selected frame.
  AiNativeTextStory owner(AiNativeTextFrame frame) {
    if (!source.frames.contains(frame)) {
      throw ArgumentError('Invalid or foreign Illustrator text frame.');
    }
    return source.stories.singleWhere((story) => story.frameIndices.contains(frame.index));
  }

  /// Requires exclusive text references under qualified native ancestors.
  void _drawing() {
    final AiNativeDrawing drawing = AiNativeDrawing.decode(records: source.records);
    final AiNativeStructure structure = AiNativeStructure.decode(drawing: drawing);
    final Set<(int, int)> seen = {};
    final Map<AiNativeItem, int> offsets = {for (final (int index, AiNativeItem item) in drawing.items.indexed) item: index};
    for (final AiNativeTextObject object in source.objects) {
      final AiNativeStructureNode node = structure.nodeFor(object.record);
      if (node.versions.isNotEmpty || !offsets.containsKey(object.record)) {
        throw UnsupportedError('Text lifecycle requires unconditional ordinary drawing records.');
      }
      if (!seen.add((object.storyIndex, object.frameIndex))) {
        throw UnsupportedError('A text frame must have exactly one drawing reference.');
      }
      final AiNativeContainer record = object.record;
      if (record.hasBinary ||
          record.notRecorded ||
          record.entries.map((field) => field.key).toSet().length != record.entries.length ||
          record.entries.any((field) => field.type != null || field.isQualifier || !{'FreeUndo', 'StoryIndex', 'FrameIndex', 'TextAntialiasing', 'ConfiningPath'}.contains(field.key))) {
        throw UnsupportedError('Unqualified text drawing fields.');
      }
      for (final String key in ['FreeUndo', 'StoryIndex', 'FrameIndex', if (record['TextAntialiasing'] != null) 'TextAntialiasing']) {
        if (record[key]?.numbers?.length != 1) {
          throw const FormatException('Text drawing references require one literal integer.');
        }
        _recordIndex(record, key);
      }
      final int index = offsets[record]!;
      final AiNativeItem? following = index + 1 < drawing.items.length ? drawing.items[index + 1] : null;
      if (following case final AiNativeContainer dictionary when dictionary.type == 'ArtDictionary') {
        if (dictionary.hasBinary ||
            dictionary.entries.any(
              (field) => !{'BBAccumRotation', 'AI24 TextStoryRawDataUUID'}.contains(field.key) || !{'String', 'UnicodeString'}.contains(field.type) || field.stringBytes == null,
            )) {
          throw UnsupportedError('Text identities, effects or unknown auxiliary metadata require their own lifecycle contract.');
        }
        final String? angle = dictionary['BBAccumRotation']?.text();
        if (angle != null && (double.tryParse(angle) == null || !double.parse(angle).isFinite)) {
          throw const FormatException('Invalid text frame rotation.');
        }
        metadata[object] = dictionary;
      }
      final AiNativeTextFrame frame = source.frames[source.stories[object.storyIndex].frameIndices[object.frameIndex]];
      objectsByFrame[frame.index] = object;
      (objectsByStory[object.storyIndex] ??= []).add(object);
      final AiNativeContainer? path = record['ConfiningPath']?.container;
      if (record['ConfiningPath'] != null && path?.type != 'Art' || frame.kind != .point && path == null) {
        throw const FormatException('Area/path frames require an owned confinement.');
      }
      if (path != null) {
        _translateTextConfinement(AiNativeArt.decode(records: source.records, record: path), 0, 0);
      }
    }
    if (seen.length != source.frames.length) {
      throw const FormatException('Every text frame requires exactly one drawing object.');
    }
    final List<({int start, int end})> retainedImages = validateTextLifecycleSource(
      records: source.records,
      textRecords: {source.container, ...source.objects.map((object) => object.record), ...metadata.values},
    );
    final Set<int> ownerAttachments = {
      for (final AiNativeLayer layer in AiNativeLayers.decode(drawing: drawing).layers)
        if (layer.bindingIssue == null && layer.expansion != null) layer.expansion!.start,
      for (final AiNativeObject object in AiNativeObjects.decode(drawing: drawing).objects)
        if (object.source is AiNativeGroup && object.bindingIssue == null)
          for (final AiNativeInstruction command in [?object.expansion, ?object.styleApplication]) command.start,
    };
    for (final AiNativeInstruction command in drawing.items.whereType<AiNativeInstruction>()) {
      if (retainedImages.any((image) => command.start >= image.start && command.end <= image.end) || ownerAttachments.contains(command.start)) {
        continue;
      }
      if (!{
            ..._textConfinementState,
            'm',
            'l',
            'L',
            'c',
            'C',
            'v',
            'V',
            'y',
            'Y',
            'h',
            'H',
            'n',
            'N',
            'f',
            'F',
            's',
            'S',
            'b',
            'B',
            'u',
            'U',
            'Lb',
            'Ln',
            'LB',
            'AE',
            'A',
            'Xw',
          }.contains(command.operator) ||
          command.isPrivate && !{..._textConfinementState, 'A', 'Xw'}.contains(command.operator) ||
          {'AE', 'A', 'Xw'}.contains(command.operator) && (command.numbers?.length != 1 || !const {0, 1}.contains(command.numbers!.single))) {
        throw UnsupportedError('Text lifecycle cannot retain unresolved appearance or legacy text dependencies.');
      }
    }
  }

  /// Selects an actual layer boundary rather than accepting arbitrary byte offsets.
  int insertion(AiLayer? layer) {
    if (layer != null && !source.records.program.layers.contains(layer)) {
      throw ArgumentError('Invalid or foreign insertion layer.');
    }
    return layer?.end.start ?? source.records.program.bodyEnd;
  }

  /// Returns a source object's complete owned interval including metadata.
  int objectEnd(AiNativeTextObject object) => metadata[object]?.end ?? object.record.end;

  /// Captures a frame's model and confinement without copying drawing identities.
  AiNativeTextFrameDefinition definition(int index) {
    final AiNativeTextObject object = objectsByFrame[index]!;
    final AiNativeContainer? path = object.record['ConfiningPath']?.container;
    final AiNativeEntry? angle = metadata[object]?['BBAccumRotation'];
    final AiNativeArt? art = path == null ? null : AiNativeArt.decode(records: source.records, record: path);
    return AiNativeTextFrameDefinition(
      resource: source.frames[index].record,
      confinement: art == null ? null : source.records.program.bytes.sublist(art.items.first.start, art.items.last.end),
      antialiasing: object.record['TextAntialiasing'] == null ? null : _recordIndex(object.record, 'TextAntialiasing'),
      rotationRadians: angle == null ? null : double.parse(angle.text()!),
    );
  }

  /// Clones known native data while renewing every local UUID.
  PsEngineValue clone(PsEngineValue value) {
    if (--remainingNodes < 0) {
      throw const FormatException('Text lifecycle exceeds the aggregate node limit.');
    }
    return switch (value) {
      PsEngineDictionary(:final values) => PsEngineDictionary(
        values: {
          for (final MapEntry<String, PsEngineValue> entry in values.entries)
            entry.key: entry.key == '97' || entry.key == 'UUID' ? PsEngineString(bytes: identifiers.next().codeUnits) : clone(entry.value),
        },
      ),
      PsEngineArray(:final values) => PsEngineArray(values: values.map(clone).toList()),
      _ => value,
    };
  }

  /// Validates both native representations before allocating or replacing data.
  void validateFrame(AiNativeTextFrameDefinition definition) {
    if (definition.confinement != null && definition.confinement!.length > source.records.program.limits.maxDecodedBytes) {
      throw const FormatException('Text confinement exceeds native limits.');
    }
    PsEngineCodec.encode(value: definition.resource, limits: source.engine.limits);
    _validateTextFrame(definition.resource);
    if (definition.confinement case final List<int> bytes) {
      final AiProgram fragment = AiProgram.decode(
        bytes: [...latin1.encode('%!PS-Adobe-3.0\n%%EndSetup\n/Art : '), ...bytes, ...latin1.encode(' ;\n%%Trailer\n%%EOF\n')],
        limits: source.records.program.limits,
      );
      final AiNativeRecords parsed = AiNativeRecords.decode(program: fragment);
      final AiNativeDrawing drawing = AiNativeDrawing.decode(records: parsed);
      if (parsed.roots.length != 1 || parsed.roots.single.type != 'Art' || drawing.items.length != 1) {
        throw const FormatException('Confinement must contain exactly one Art payload.');
      }
      _translateTextConfinement(AiNativeArt.decode(records: parsed, record: parsed.roots.single), 0, 0);
    }
    final AiNativeTextFrame frame = AiNativeTextFrame._(index: 0, record: definition.resource);
    if (frame.kind != .point && definition.confinement == null) {
      throw const FormatException('Area and path frames require a complete drawing confinement.');
    }
  }

  /// Appends a validated frame with a new identity and optional display entry.
  int addFrame(AiNativeTextFrameDefinition definition) {
    validateFrame(definition);
    final int index = frameValues.length;
    final PsEngineDictionary resource = clone(definition.resource) as PsEngineDictionary;
    frameValues.add(
      PsEngineDictionary(
        values: {
          named ? 'Resource' : '0': PsEngineDictionary(
            values: {
              ...resource.values,
              _featureKey(resource, '97', 'UUID', named): PsEngineString(bytes: identifiers.next().codeUnits),
            },
          ),
        },
      ),
    );
    display?.add(PsEngineDictionary(values: {named ? 'Resource' : '0': PsEngineNumber(value: index)}));
    return index;
  }

  /// Builds a frame list with no stale composed or rendered data.
  PsEngineDictionary view(List<int> indices) => PsEngineDictionary(
    values: {
      named ? 'Frames' : '0': PsEngineArray(
        values: [
          for (final int index in indices) PsEngineDictionary(values: {named ? 'Resource' : '0': PsEngineNumber(value: index)}),
        ],
      ),
    },
  );

  /// Retains model text and invalidates the layout after a flow change.
  PsEngineDictionary withFrames(PsEngineDictionary story, List<int> indices) => PsEngineDictionary(values: {...story.values, _textKey(story, '1', 'View'): view(indices)});

  /// Inserts ordinary drawing objects; the final parser validates supplied Art.
  void insertObjects(int position, int story, List<int> indices, List<AiNativeTextFrameDefinition> definitions, {int firstFrame = 0, bool private = false}) {
    final List<int> bytes = [10];
    if (private) {
      bytes.addAll(ascii.encode('%_0 A\n%_0 Xw\n%_0 Ap\n%_0 D\n%_0 XR\n%_0 O\n%_0 R\n%_0 1 0 0 0 Xy\n'));
    }
    for (int index = 0; index < indices.length; index++) {
      final List<int> object = objectBytes(story, firstFrame + index, definitions[index], private: private);
      if (bytes.length + object.length > source.records.program.limits.maxDecodedBytes) {
        throw const FormatException('Text drawing insertion exceeds the aggregate output limit.');
      }
      bytes.addAll(object);
    }
    if (private) {
      bytes.addAll(ascii.encode('%_'));
    }
    edits.add(AiSourceEdit(start: position, end: position, bytes: bytes));
  }

  /// Serializes one explicit drawing owner without carrying stale cache metadata.
  List<int> objectBytes(int story, int frame, AiNativeTextFrameDefinition definition, {bool private = false}) {
    final StringBuffer text = StringBuffer('/AI11Text : 0 /FreeUndo , $story /StoryIndex , $frame /FrameIndex ,');
    if (definition.antialiasing case final int antialiasing) {
      text.write(' $antialiasing /TextAntialiasing ,');
    }
    if (definition.confinement case final List<int> bytes) {
      if (text.length + bytes.length > source.records.program.limits.maxDecodedBytes - 128) {
        throw const FormatException('Text drawing insertion exceeds the aggregate output limit.');
      }
      text.write('\n/Art : ${latin1.decode(bytes)} ; /ConfiningPath ,');
    }
    text.write(' ;\n');
    if (definition.rotationRadians case final double angle) {
      text.write('%_/ArtDictionary :\n%_($angle) /String (BBAccumRotation) ,\n%_;\n');
    }
    return latin1.encode(private ? text.toString().split('\n').map((line) => line.isEmpty || line.startsWith('%_') ? line : '%_$line').join('\n') : text.toString());
  }

  /// Updates one already validated drawing reference.
  void reference(AiNativeTextObject object, String key, int value) {
    final AiNativeItem item = object.record[key]!.items.single;
    edits.add(AiSourceEdit(start: item.start, end: item.end, bytes: '$value'.codeUnits));
  }

  /// Removes cached raw-data identity while preserving qualified frame rotation.
  void invalidateMetadata(AiNativeTextObject object) {
    final AiNativeContainer? dictionary = metadata[object];
    if (dictionary == null || dictionary['AI24 TextStoryRawDataUUID'] == null || !invalidated.add(object)) {
      return;
    }
    final String? angle = dictionary['BBAccumRotation']?.text();
    final List<int> replacement = angle == null ? [] : latin1.encode('/ArtDictionary : (${double.parse(angle)}) /String (BBAccumRotation) , ;');
    edits.add(AiSourceEdit(start: dictionary.start, end: dictionary.end, bytes: replacement));
  }

  /// Deletes the entire owned object, including any raw-data cache identifier.
  void removeObject(AiNativeTextObject object) {
    final AiNativeContainer? dictionary = metadata[object];
    if (dictionary != null && invalidated.remove(object)) {
      edits.removeWhere((edit) => edit.start == dictionary.start && edit.end == dictionary.end);
    }
    edits.add(AiSourceEdit(start: object.record.start, end: objectEnd(object), bytes: []));
  }

  /// Compacts resources and remaps known references, including retained strikes.
  void removeFrames(Set<int> removed) {
    final Map<int, int> map = {};
    for (int index = 0; index < frameValues.length; index++) {
      if (!removed.contains(index)) {
        map[index] = map.length;
      }
    }
    for (final AiNativeTextStory story in source.stories) {
      if (story.frameIndices.any((index) => map[index] != null && map[index] != index)) {
        objectsByStory[story.index]!.forEach(invalidateMetadata);
      }
    }
    final List<PsEngineValue> retained = [for (final MapEntry<int, int> entry in map.entries) frameValues[entry.key]];
    frameValues
      ..clear()
      ..addAll(retained);
    if (display != null) {
      final List<PsEngineValue> retainedDisplay = [
        for (final PsEngineValue value in display!)
          if (map[_index(_field(_dictionary(value), '0', 'Resource'))] case final int next) PsEngineDictionary(values: {named ? 'Resource' : '0': PsEngineNumber(value: next)}),
      ];
      display!
        ..clear()
        ..addAll(retainedDisplay);
    }
    for (int index = 0; index < storyValues.length; index++) {
      final PsEngineDictionary story = _dictionary(storyValues[index]);
      final PsEngineDictionary current = _dictionary(_field(story, '1', 'View'));
      final List<int> indices = [for (final PsEngineValue value in _array(_field(current, '0', 'Frames'))) map[_index(_field(_dictionary(value), '0', 'Resource'))]!];
      final Map<String, PsEngineValue> values = {...current.values, _textKey(current, '0', 'Frames'): _field(view(indices), '0', 'Frames')!};
      if (_field(current, '2', 'Strikes') case final PsEngineValue strikes) {
        values[_textKey(current, '2', 'Strikes')] = _remapTextStrikes(strikes, map);
      }
      if (indices.indexed.any((entry) => entry.$2 != _index(_field(_dictionary(_array(_field(current, '0', 'Frames'))[entry.$1]), '0', 'Resource'))) && _field(current, '1', 'RenderedData') != null) {
        throw UnsupportedError('Remapping frames with rendered-data caches requires host recomposition first.');
      }
      storyValues[index] = PsEngineDictionary(
        values: {
          ...story.values,
          _textKey(story, '1', 'View'): PsEngineDictionary(values: values),
        },
      );
    }
  }

  /// Applies bounded engine and drawing edits, then verifies the resulting graph.
  AiNativeTextDocument finish() {
    final PsEngineDictionary changedFrames = PsEngineDictionary(
      values: {
        ...frameSet.values,
        _featureKey(frameSet, '0', 'Resources', named): PsEngineArray(values: frameValues),
        if (display != null) _featureKey(frameSet, '1', 'DisplayList', named): PsEngineArray(values: display!),
      },
    );
    final PsEngineDocument engine = source.engine.replaceValues(
      replacements: {
        resources: PsEngineDictionary(values: {...resources.values, _featureKey(resources, '8', 'TextFrameSet', named): changedFrames}),
        objects: PsEngineDictionary(
          values: {
            ...objects.values,
            _featureKey(objects, '1', 'TextObjects', named): PsEngineArray(values: storyValues),
          },
        ),
      },
    );
    final AiNativeRecords drawing = AiNativeRecords.decode(
      program: AiNativeEditor.apply(program: source.records.program, edits: edits),
    );
    final AiNativeRecords changed = drawing.replaceBinary(container: drawing.containers.singleWhere((record) => record.type == 'AI11TextDocument'), bytes: engine.bytes);
    final AiNativeTextDocument result = AiNativeTextDocument.decode(records: changed, limits: source.engine.limits);
    _TextLifecycle(source: result);
    return result;
  }
}

/// Internal reference bridge for artwork edits beside isolated text stories.
///
/// Excluded from the package facade. The complete lifecycle qualification rejects
/// auxiliary cross-reference runs and unresolved appearance/resource dependencies.
Set<AiNativeContainer> validateTextArtworkReferences(AiNativeRecords records) {
  if (!records.roots.any((record) => record.type == 'AI11TextDocument')) {
    return {};
  }
  final AiNativeTextDocument text = AiNativeTextDocument.decode(records: records);
  final _TextLifecycle edit = _TextLifecycle(source: text);
  for (final AiNativeTextStory story in text.stories) {
    for (final AiNativeStyledTextRange range in text.styledRanges(story: story)) {
      for (final PsEngineDictionary layer in range.characterStyle.layers) {
        _knownTextKeys(layer, {'0', '1', '4', '5', '6', '7', '8', '9', '10', '18', '20', '53', '56', '57', '58', '59', '60', '77', '78', '80', '89', '90'}, 'independent text character features');
      }
      for (final PsEngineDictionary layer in range.paragraphStyle.layers) {
        _knownTextKeys(layer, {'0', '1', '2', '3', '4', '5', '7', '9'}, 'independent text paragraph features');
      }
      for (final AiNativeTextPaint? paint in [range.characterStyle.fillPaint, range.characterStyle.strokePaint, range.characterStyle.backgroundPaint]) {
        if (paint != null && paint.color == null) {
          throw UnsupportedError('Artwork reference deletion requires independent process text paints.');
        }
      }
    }
  }
  return {...text.objects.map((object) => object.record), ...edit.metadata.values};
}

/// Qualifies geometry fields whose indices are local to a single text frame.
void _validateTextFrame(PsEngineDictionary record) {
  _knownTextKeys(record, {'0', 'Position', '1', 'Bezier', '2', 'Data', '97', 'UUID'}, 'frame');
  _text(_field(record, '97', 'UUID'));
  final AiNativeTextFrame frame = AiNativeTextFrame._(index: 0, record: record);
  if (frame.kind == .unknown || frame.position == null && frame.pathCoordinates == null || frame.pathCoordinates?.isEmpty == true || frame.kind != .point && frame.pathCoordinates == null) {
    throw UnsupportedError('New text frames require known explicit geometry.');
  }
  if (frame.settings case final PsEngineDictionary settings) {
    _knownTextKeys(settings, {
      '0',
      'Type',
      '1',
      'LineOrientation',
      '2',
      'FrameMatrix',
      '3',
      'RowCount',
      '4',
      'ColumnCount',
      '5',
      'RowMajorOrder',
      '6',
      'TextOnPathTRange',
      '7',
      'RowGutter',
      '8',
      'ColumnGutter',
      '9',
      'Spacing',
      '10',
      'FirstBaseline',
      '11',
      'PathData',
      '13',
      'VerticalAlignment',
    }, 'frame settings');
  }
  final PsEngineDictionary settings = frame.settings ?? PsEngineDictionary(values: {});
  for (final (String compact, String name) in [
    ('0', 'Type'),
    ('1', 'LineOrientation'),
    ('3', 'RowCount'),
    ('4', 'ColumnCount'),
    ('7', 'RowGutter'),
    ('8', 'ColumnGutter'),
    ('9', 'Spacing'),
    ('13', 'VerticalAlignment'),
  ]) {
    final PsEngineValue? value = _field(settings, compact, name);
    if (value != null && (value is! PsEngineNumber || !value.value.isFinite || value.value.abs() > 9007199254740991)) {
      throw const FormatException('Invalid native text frame setting.');
    }
  }
  final PsEngineValue? rowOrder = _field(settings, '5', 'RowMajorOrder');
  if (rowOrder != null && rowOrder is! PsEngineBoolean) {
    throw const FormatException('Invalid native text row order.');
  }
  _coordinates(_field(settings, '6', 'TextOnPathTRange'), 2);
  for (final (String compact, String name) in [('10', 'FirstBaseline'), ('11', 'PathData')]) {
    if (_field(settings, compact, name) case final PsEngineValue value) {
      final PsEngineDictionary local = _dictionary(value);
      _knownTextKeys(local, compact == '10' ? {'0', 'Flag', '1', 'Min'} : {'0', 'Flip', '1', 'Effect', '2', 'Alignment', '4', '18', 'Spacing', '6', '7'}, 'frame settings');
      if (local.values.values.any((value) => value is! PsEngineNumber && value is! PsEngineBoolean || value is PsEngineNumber && (!value.value.isFinite || value.value.abs() > 9007199254740991))) {
        throw const FormatException('Invalid local text frame setting.');
      }
    }
  }
  if (_field(record, '1', 'Bezier') case final PsEngineValue bezier) {
    _knownTextKeys(_dictionary(bezier), {'0', 'Points'}, 'frame curve');
  }
  for (final List<double> values in [?frame.position, ?frame.matrix, ?frame.pathCoordinates]) {
    if (values.any((value) => value.abs() > 9007199254740991)) {
      throw const FormatException('Text geometry exceeds portable coordinates.');
    }
  }
}

/// Changes only known frame references in a retained bounded layout hierarchy.
PsEngineValue _remapTextStrikes(PsEngineValue value, Map<int, int> frames) {
  if (value is PsEngineArray) {
    return PsEngineArray(values: value.values.map((value) => _remapTextStrikes(value, frames)).toList());
  }
  final PsEngineDictionary node = _dictionary(value);
  final AiNativeTextStrike strike = AiNativeTextStrike._(record: node);
  if (strike.kind == .unknown) {
    throw UnsupportedError('Cannot remap an unknown text layout node.');
  }
  _knownTextKeys(node, _textStrikeFields(strike.kind), 'retained layout node');
  final Map<String, PsEngineValue> values = {...node.values};
  if (strike.kind == .frame) {
    final int? next = frames[strike.frameIndex];
    if (next == null) {
      throw const FormatException('A retained strike refers to a removed frame.');
    }
    values[_textKey(node, '10', 'Frame')] = PsEngineNumber(value: next);
  }
  if (_field(node, '6', 'Children') case final PsEngineValue children) {
    values[_textKey(node, '6', 'Children')] = _remapTextStrikes(children, frames);
  }
  return PsEngineDictionary(values: values);
}

/// Rejects private authoring records that have no owned printable counterpart.
bool _textPrivateAt(AiProgram program, int offset) {
  int start = offset;
  while (start > 0 && program.bytes[start - 1] != 10 && program.bytes[start - 1] != 13) {
    start--;
  }
  return latin1.decode(program.bytes.sublist(start, offset)).trimLeft().startsWith('%_');
}

/// Known cached-node fields; unknown fields may contain additional frame links.
Set<String> _textStrikeFields(AiNativeTextStrikeKind kind) => {
  '99',
  'StreamTag',
  '0',
  'Transform',
  '1',
  'Bounds',
  '6',
  'Children',
  ...switch (kind) {
    .story || .rowColumn => {'5', 'Procession'},
    .frame => {'5', 'Procession', '10', 'Frame'},
    .line => {'10', '14', 'SelectionAscent', '15', 'SelectionDescent'},
    .segment => {'15', 'Mapping', '17', 'WordReorder', '20', 'FirstCharacterIndexInSegment'},
    .glyphs => {'5', 'Glyphs', '8', 'VisualBounds', '9', '10', 'ShadowStylesRun', '11', '12', 'SelectionAscent', '13', 'SelectionDescent', '20', '24'},
    .unknown => <String>{},
  },
};
