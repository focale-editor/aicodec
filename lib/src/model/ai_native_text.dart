import 'dart:math';

import 'package:aikit/src/model/ai_native_records.dart';
import 'package:pscore/pscore.dart';

part 'ai_native_text_styles.dart';
part 'ai_native_text_layout.dart';
part 'ai_native_text_edit.dart';
part 'ai_native_text_feature_edit.dart';
part 'ai_native_text_changes.dart';

/// The resource table supplying an Illustrator text style.
enum AiNativeTextStyleKind {
  /// Character features, including font, size and OpenType settings.
  character,

  /// Paragraph features, including alignment, spacing and composition.
  paragraph,
}

/// A font reference retaining its complete native identification metadata.
final class AiNativeTextFont {
  /// Index used by character features in this document.
  final int index;

  /// Original resource dictionary, including unknown font attributes.
  final PsEngineDictionary record;

  /// Creates a resource view after validating its dictionary wrapper.
  const AiNativeTextFont._({required this.index, required this.record});

  /// PostScript font name, when present in the native identifier.
  String? get postScriptName => _text(_at(record, [('0', 'Identifier'), ('0', 'Name')]));

  /// Embedded version string, without implying that the font is installed.
  String? get version => _text(_at(record, [('0', 'Identifier'), ('5', 'VersionString')]));
}

/// A named native character or paragraph style, preserving unknown features.
final class AiNativeTextStyle {
  /// Index in its own character or paragraph resource table.
  final int index;

  /// Resource table determining feature and parent field semantics.
  final AiNativeTextStyleKind kind;

  /// Source dictionary retaining identifiers, inheritance and feature values.
  final PsEngineDictionary record;

  /// Creates a source-backed style resource.
  const AiNativeTextStyle._({required this.index, required this.kind, required this.record});

  /// Display name, without the string's UTF-16 byte-order marker.
  String? get name => _text(_field(record, '0', 'Name'));

  /// Explicit features; omitted features continue to inherit natively.
  PsEngineDictionary? get features => _optionalDictionary(_field(record, kind == .character ? '6' : '5', 'Features'));

  /// Explicit parent index when the native resource declares one.
  int? get parentIndex => _optionalIndex(_field(record, kind == .character ? '5' : '6', 'Parent'));
}

/// One native style span measured in UTF-16 code units, including paragraph marks.
final class AiNativeTextRun {
  /// Inclusive UTF-16 code-unit offset in the story's model text.
  final int start;

  /// Number of UTF-16 code units covered by this run.
  final int length;

  /// Style resource index or inline override dictionary.
  final PsEngineValue style;

  /// Original run, including uninterpreted settings.
  final PsEngineDictionary record;

  /// Creates a validated span without splitting surrogate pairs.
  const AiNativeTextRun._({required this.start, required this.length, required this.style, required this.record});

  /// Exclusive UTF-16 code-unit offset.
  int get end => start + length;

  /// Direct style index, or null for an inline override.
  int? get styleIndex => style is PsEngineNumber ? _index(style) : null;

  /// Inline override dictionary when the run does not use a direct style index.
  PsEngineDictionary? get overrides => style is PsEngineDictionary ? style as PsEngineDictionary : null;
}

/// A native text frame retaining geometry, transforms and composition settings.
final class AiNativeTextFrame {
  /// Index in the document's frame resource table.
  final int index;

  /// Complete frame resource; no layout or path data is regenerated implicitly.
  final PsEngineDictionary record;

  /// Creates a source-backed frame view.
  const AiNativeTextFrame._({required this.index, required this.record});

  /// Native frame settings, including any text-on-path attributes.
  PsEngineDictionary? get settings => _optionalDictionary(_field(record, '2', 'Data'));

  /// Native frame category; unknown future numeric values remain in [settings].
  AiNativeTextFrameKind get kind => switch (_optionalIndex(_field(settings, '0', 'Type'))) {
    null || 0 => .point,
    1 => .area,
    2 => .path,
    _ => .unknown,
  };

  /// Explicit canvas-space baseline origin, absent in some older point frames.
  List<double>? get position => _coordinates(_field(record, '0', 'Position'), 2);

  /// Native frame matrix `[a, b, c, d, e, f]`, without applying font scaling.
  List<double>? get matrix => _coordinates(_field(settings, '2', 'FrameMatrix'), 6);

  /// Retained canvas-space path coordinates, including native control points.
  List<double>? get pathCoordinates {
    final PsEngineValue? points = _at(record, [('1', 'Bezier'), ('0', 'Points')]);
    if (points == null) {
      return null;
    }
    if (points is! PsEngineArray || points.values.length.isOdd) {
      throw const FormatException('Invalid Illustrator text frame path coordinates.');
    }
    return _coordinates(points, points.values.length);
  }
}

/// An Illustrator story with model text, style spans and retained native layout.
final class AiNativeTextStory {
  /// Index referenced by the drawing's AI11Text records.
  final int index;

  /// Complete story, including unknown model and view fields.
  final PsEngineDictionary record;

  /// Exact text, including the required final carriage-return paragraph mark.
  final String modelText;

  /// Explicit character spans; an absent table inherits the normal style.
  final List<AiNativeTextRun> characterRuns;

  /// Explicit paragraph spans; an absent table inherits the normal style.
  final List<AiNativeTextRun> paragraphRuns;

  /// Ordered frame resource indices used by the retained view.
  final List<int> frameIndices;

  /// Validates text encoding, runs and the native view's frame references.
  factory AiNativeTextStory._({required int index, required PsEngineDictionary record}) {
    final PsEngineDictionary model = _dictionary(_field(record, '0', 'Model'));
    final PsEngineValue? value = _field(model, '0', 'Text');
    if (value is! PsEngineString || value.bytes.length < 2 || !(value.bytes[0] == 254 && value.bytes[1] == 255 || value.bytes[0] == 255 && value.bytes[1] == 254)) {
      throw const FormatException('Illustrator story text requires a UTF-16 byte-order marker.');
    }
    final String text = value.text();
    if (!text.endsWith('\r')) {
      throw const FormatException('Illustrator story text is missing its final paragraph mark.');
    }
    final List<int> frames = [
      for (final PsEngineValue frame in _array(_at(record, [('1', 'View'), ('0', 'Frames')]))) _index(_field(_dictionary(frame), '0', 'Resource')),
    ];
    return AiNativeTextStory._checked(
      index: index,
      record: record,
      modelText: text,
      characterRuns: _runs(model: model, kind: .character, text: text),
      paragraphRuns: _runs(model: model, kind: .paragraph, text: text),
      frameIndices: frames,
    );
  }

  /// Retains validated fields as immutable snapshots.
  AiNativeTextStory._checked({
    required this.index,
    required this.record,
    required this.modelText,
    required List<AiNativeTextRun> characterRuns,
    required List<AiNativeTextRun> paragraphRuns,
    required List<int> frameIndices,
  }) : characterRuns = List.unmodifiable(characterRuns),
       paragraphRuns = List.unmodifiable(paragraphRuns),
       frameIndices = List.unmodifiable(frameIndices);

  /// Editable content without the format's mandatory final paragraph mark.
  String get text => modelText.substring(0, modelText.length - 1);

  /// Retained frames, glyph strikes and layout caches; not an inferred rendering.
  PsEngineDictionary? get view => _optionalDictionary(_field(record, '1', 'View'));

  /// Cached layout hierarchy, including preserved unknown strike types.
  List<AiNativeTextStrike> get strikes => List.unmodifiable([for (final PsEngineValue value in _array(_field(view, '2', 'Strikes'))) AiNativeTextStrike._(record: _dictionary(value))]);
}

/// A drawing object referring to a native story and one of its frames.
final class AiNativeTextObject {
  /// Source drawing record, retaining confinement paths and antialiasing settings.
  final AiNativeContainer record;

  /// Referenced story index.
  final int storyIndex;

  /// Index within the story's ordered frame list, not the global resource table.
  final int frameIndex;

  /// Whether this drawing reference selects the separate undo-free text model.
  final bool usesUndoFreeModel;

  /// Validates integral references without resolving them against the wrong model.
  AiNativeTextObject._({required this.record})
    : storyIndex = _recordIndex(record, 'StoryIndex'),
      frameIndex = _recordIndex(record, 'FrameIndex'),
      usesUndoFreeModel = _recordIndex(record, 'FreeUndo') != 0;
}

/// A source-backed CC text document decoded through PsCore's shared EngineData.
///
/// Unknown fields and cached glyph layouts remain available in [engine]. Text
/// shaping and synchronization with printable/PDF artwork belong to the host.
final class AiNativeTextDocument {
  /// Native program owning the text container and drawing references.
  final AiNativeRecords records;

  /// The selected AI11TextDocument container; undo-free snapshots remain separate.
  final AiNativeContainer container;

  /// Immutable text-engine syntax with exact bytes and source positions.
  final PsEngineDocument engine;

  /// Fonts in native resource order.
  final List<AiNativeTextFont> fonts;

  /// Named character styles in native resource order.
  final List<AiNativeTextStyle> characterStyles;

  /// Named paragraph styles in native resource order.
  final List<AiNativeTextStyle> paragraphStyles;

  /// Text frames in native resource order.
  final List<AiNativeTextFrame> frames;

  /// Stories in the order referenced by AI11Text drawing objects.
  final List<AiNativeTextStory> stories;

  /// Drawing references, including any unresolved references reported below.
  final List<AiNativeTextObject> objects;

  /// Decodes one selected native text document with explicit resource bounds.
  factory AiNativeTextDocument.decode({required AiNativeRecords records, AiNativeContainer? container, PsEngineLimits limits = const PsEngineLimits()}) {
    final List<AiNativeContainer> candidates = records.containers.where((record) => record.type == 'AI11TextDocument').toList();
    final AiNativeContainer selected = container ?? (candidates.length == 1 ? candidates.single : throw ArgumentError('Select exactly one Illustrator text document.'));
    if (!candidates.contains(selected)) {
      throw ArgumentError('Invalid or foreign Illustrator text document.');
    }
    final PsEngineDocument engine = PsEngineDocument.decode(
      bytes: selected.decodeBinary(maxOutputBytes: limits.maxBytes),
      limits: limits,
    );
    final PsEngineDictionary root = _dictionary(engine.root);
    if (_field(root, '0', 'DocumentResources') == null || _field(root, '1', 'DocumentObjects') == null) {
      throw const FormatException('Missing Illustrator text document resources or objects.');
    }
    final List<PsEngineDictionary> fonts = _resources(root, '1', 'FontSet');
    final List<PsEngineDictionary> characters = _resources(root, '5', 'StyleSheetSet');
    final List<PsEngineDictionary> paragraphs = _resources(root, '6', 'ParagraphSheetSet');
    final List<PsEngineDictionary> frames = _resources(root, '8', 'TextFrameSet');
    final List<PsEngineValue> stories = _array(_at(root, [('1', 'DocumentObjects'), ('1', 'TextObjects')]));
    return AiNativeTextDocument._(
      records: records,
      container: selected,
      engine: engine,
      fonts: [for (int i = 0; i < fonts.length; i++) AiNativeTextFont._(index: i, record: fonts[i])],
      characterStyles: [for (int i = 0; i < characters.length; i++) AiNativeTextStyle._(index: i, kind: .character, record: characters[i])],
      paragraphStyles: [for (int i = 0; i < paragraphs.length; i++) AiNativeTextStyle._(index: i, kind: .paragraph, record: paragraphs[i])],
      frames: [for (int i = 0; i < frames.length; i++) AiNativeTextFrame._(index: i, record: frames[i])],
      stories: [for (int i = 0; i < stories.length; i++) AiNativeTextStory._(index: i, record: _dictionary(stories[i]))],
      objects: [for (final AiNativeContainer record in records.containers.where((record) => record.type == 'AI11Text')) AiNativeTextObject._(record: record)],
    );
  }

  /// Owns immutable resource lists after decoding the selected source snapshot.
  AiNativeTextDocument._({
    required this.records,
    required this.container,
    required this.engine,
    required List<AiNativeTextFont> fonts,
    required List<AiNativeTextStyle> characterStyles,
    required List<AiNativeTextStyle> paragraphStyles,
    required List<AiNativeTextFrame> frames,
    required List<AiNativeTextStory> stories,
    required List<AiNativeTextObject> objects,
  }) : fonts = List.unmodifiable(fonts),
       characterStyles = List.unmodifiable(characterStyles),
       paragraphStyles = List.unmodifiable(paragraphStyles),
       frames = List.unmodifiable(frames),
       stories = List.unmodifiable(stories),
       objects = List.unmodifiable(objects);

  /// Unresolved story, frame and style references, without discarding source data.
  List<String> get referenceIssues {
    final List<String> issues = [];
    for (final AiNativeTextStyle style in [...characterStyles, ...paragraphStyles]) {
      try {
        final List<PsEngineDictionary> layers = _styleLayers(
          kind: style.kind,
          selection: PsEngineNumber(value: style.index),
        );
        if (style.kind == .character) {
          AiNativeCharacterStyle._(layers: layers, fonts: fonts).font;
        }
      } on FormatException catch (error) {
        issues.add('${style.kind.name} style ${style.index}: ${error.message}');
      }
    }
    for (final AiNativeTextStory story in stories) {
      for (final int frame in story.frameIndices) {
        if (frame >= frames.length) {
          issues.add('Story ${story.index} references missing frame $frame.');
        }
      }
      try {
        for (final AiNativeStyledTextRange range in styledRanges(story: story)) {
          range.characterStyle.font;
        }
      } on FormatException catch (error) {
        issues.add('Story ${story.index}: ${error.message}');
      }
      for (final (List<AiNativeTextRun> runs, List<AiNativeTextStyle> styles, String parentKey) in [(story.characterRuns, characterStyles, '5'), (story.paragraphRuns, paragraphStyles, '6')]) {
        for (final AiNativeTextRun run in runs) {
          final int? index = run.styleIndex ?? _optionalIndex(_field(run.overrides, parentKey, 'Parent'));
          if (index != null && index >= styles.length) {
            issues.add('Story ${story.index} references missing text style $index.');
          }
        }
      }
    }
    for (final AiNativeTextObject object in objects) {
      if (object.usesUndoFreeModel) {
        issues.add('Text object at ${object.record.start} selects the separate undo-free model.');
      } else if (object.storyIndex >= stories.length || object.frameIndex >= stories[object.storyIndex].frameIndices.length) {
        issues.add('Text object at ${object.record.start} references a missing story or frame.');
      }
    }
    return List.unmodifiable(issues);
  }

  /// Renames a style without changing its features, identifiers or text layout.
  ///
  /// Only the selected name and its enclosing ASCII85 payload are rewritten.
  /// Other native records, including the separate undo-free document, are kept.
  AiNativeTextDocument renameStyle({required AiNativeTextStyle style, required String name}) {
    final PsEngineValue? previous = _field(style.record, '0', 'Name');
    if (!characterStyles.contains(style) && !paragraphStyles.contains(style) || previous is! PsEngineString) {
      throw ArgumentError('Invalid or foreign Illustrator text style.');
    }
    final PsEngineDocument edited = engine.replaceValues(replacements: {previous: PsEngineString.fromText(text: name)});
    return _withEngine(edited);
  }

  /// Replaces the selected payload while retaining all other native records.
  AiNativeTextDocument _withEngine(PsEngineDocument edited) {
    final int selectedIndex = records.containers.where((record) => record.type == 'AI11TextDocument').toList().indexOf(container);
    final AiNativeRecords changed = records.replaceBinary(container: container, bytes: edited.bytes);
    return AiNativeTextDocument.decode(records: changed, container: changed.containers.where((record) => record.type == 'AI11TextDocument').elementAt(selectedIndex), limits: engine.limits);
  }
}

/// Looks up equivalent compact or named fields without discarding either syntax.
PsEngineValue? _field(PsEngineDictionary? record, String compact, String name) {
  if (record == null) {
    return null;
  }
  if (compact != name && record.values.containsKey(compact) && record.values.containsKey(name)) {
    throw FormatException('Ambiguous Illustrator text field $name.');
  }
  return record[compact] ?? record[name];
}

/// Looks up a format-specific path using compact/named key pairs.
PsEngineValue? _at(PsEngineValue? value, List<(String, String)> keys) {
  PsEngineValue? current = value;
  for (final (String compact, String name) in keys) {
    current = _field(_optionalDictionary(current), compact, name);
  }
  return current;
}

/// Requires the dictionary shape used by an identified native structure.
PsEngineDictionary _dictionary(PsEngineValue? value) => value is PsEngineDictionary ? value : throw const FormatException('Expected Illustrator text-engine dictionary.');

/// Reads an optional dictionary, rejecting a present value with the wrong type.
PsEngineDictionary? _optionalDictionary(PsEngineValue? value) => value == null ? null : _dictionary(value);

/// Reads an optional array without inventing entries for an absent table.
List<PsEngineValue> _array(PsEngineValue? value) => switch (value) {
  null => const [],
  PsEngineArray(:final values) => values,
  _ => throw const FormatException('Expected Illustrator text-engine array.'),
};

/// Returns the source resource dictionaries while retaining their wrapper records.
List<PsEngineDictionary> _resources(PsEngineDictionary root, String key, String name) => [
  for (final PsEngineValue entry in _array(_at(root, [('0', 'DocumentResources'), (key, name), ('0', 'Resources')]))) _dictionary(_field(_dictionary(entry), '0', 'Resource')),
];

/// Decodes a present engine string without coercing another value type.
String? _text(PsEngineValue? value) => switch (value) {
  null => null,
  PsEngineString() => value.text(),
  _ => throw const FormatException('Expected Illustrator text-engine string.'),
};

/// Reads a nonnegative portable integer reference or length.
int _index(PsEngineValue? value) {
  if (value is! PsEngineNumber || value.value < 0 || value.value > 9007199254740991 || value.value != value.value.truncateToDouble()) {
    throw const FormatException('Invalid Illustrator text-engine index or length.');
  }
  return value.value.toInt();
}

/// Reads an optional native index.
int? _optionalIndex(PsEngineValue? value) => value == null ? null : _index(value);

/// Reads one required scalar index from the drawing-side text object.
int _recordIndex(AiNativeContainer record, String key) {
  final double? value = record[key]?.number;
  if (value == null || value < 0 || value > 9007199254740991 || value != value.truncateToDouble()) {
    throw const FormatException('Invalid Illustrator text drawing reference.');
  }
  return value.toInt();
}

/// Validates complete UTF-16 run coverage without cutting a surrogate pair.
List<AiNativeTextRun> _runs({required PsEngineDictionary model, required AiNativeTextStyleKind kind, required String text}) {
  final PsEngineValue? table = _field(model, kind == .character ? '6' : '5', kind == .character ? 'StyleRun' : 'ParagraphRun');
  if (table == null) {
    return const [];
  }
  final PsEngineValue? array = _field(_dictionary(table), '0', 'RunArray');
  if (array is! PsEngineArray) {
    throw const FormatException('Missing Illustrator text run array.');
  }
  final List<AiNativeTextRun> runs = [];
  int start = 0;
  for (final PsEngineValue value in array.values) {
    final PsEngineDictionary record = _dictionary(value);
    final int length = _index(_field(record, '1', 'Length'));
    final PsEngineValue? style = _at(record, [('0', 'RunData'), ('0', kind == .character ? 'StyleSheet' : 'ParagraphSheet')]);
    if (length == 0 || length > text.length - start || style == null || style is! PsEngineDictionary && style is! PsEngineNumber) {
      throw const FormatException('Invalid Illustrator text style run.');
    }
    final int end = start + length;
    if (end < text.length && text.codeUnitAt(end - 1) >= 0xd800 && text.codeUnitAt(end - 1) <= 0xdbff && text.codeUnitAt(end) >= 0xdc00 && text.codeUnitAt(end) <= 0xdfff) {
      throw const FormatException('Illustrator text style run splits a UTF-16 surrogate pair.');
    }
    if (style is PsEngineNumber) {
      _index(style);
    }
    runs.add(AiNativeTextRun._(start: start, length: length, style: style, record: record));
    start = end;
  }
  if (start != text.length) {
    throw const FormatException('Illustrator text style runs do not cover the story.');
  }
  return List.unmodifiable(runs);
}
