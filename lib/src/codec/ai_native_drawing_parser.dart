part of 'package:aicodec/src/model/ai_native_records.dart';

/// Collects both private authoring commands and their printable counterparts.
final class _NativeDrawingReader {
  /// Parsed hierarchy and original native snapshot.
  final AiNativeRecords records;

  /// Creates a reader for one immutable native snapshot.
  const _NativeDrawingReader({required this.records});

  /// Parses body commands and records while retaining original byte spans.
  List<AiNativeItem> _items() {
    final AiProgram program = records.program;
    final _NativeRecordProjection projection = records._projection;
    final List<AiNativeContainer> roots = records.roots.where((root) => root.start >= program.bodyStart && root.end <= program.bodyEnd).toList();
    final List<AiNativeItem> items = [];
    final _NativeCommandReader reader = _NativeCommandReader(maxDepth: program.limits.maxDepth);
    // Relative directories are metadata strings, not operands of the following
    // placement terminator. Their section reader checks ownership and framing.
    final Set<AiToken> directories = {};
    if (projection.tokens.any((token) => token.kind == .comment && token.lexeme == '%AI28_BeginPlacedRelativePath')) {
      try {
        directories.addAll(_readNativePlacements(records, true).map((object) => object.relativeDirectory).whereType<AiToken>());
      } on UnsupportedError {
        // Preserve unqualified producer layouts as unresolved drawing syntax.
      }
    }
    int rootIndex = 0;
    int embedded = 0;
    for (final AiToken token in projection.tokens) {
      if (token.start < program.bodyStart || token.start >= program.bodyEnd) {
        continue;
      }
      while (rootIndex < roots.length && token.start >= roots[rootIndex].end) {
        rootIndex++;
      }
      if (rootIndex < roots.length && token.start >= roots[rootIndex].start) {
        if (token.start == roots[rootIndex].start) {
          if (!reader.isEmpty) {
            throw const FormatException('Native record interrupts drawing operands.');
          }
          items.add(roots[rootIndex]);
        }
        continue;
      }
      if (token.kind == .comment) {
        if (token.lexeme.startsWith('%%BeginDocument')) {
          embedded++;
        } else if (token.lexeme == '%%EndDocument') {
          embedded--;
        }
        if (embedded == 0 && token.lexeme.startsWith('%AI17_')) {
          items.add(AiNativeVersionComment._(token: token));
        }
        continue;
      }
      if (embedded != 0 || token.kind == .data) {
        continue;
      }
      if (directories.contains(token)) {
        if (!reader.isEmpty) {
          throw const FormatException('Placed directory interrupts native drawing operands.');
        }
        items.add(AiNativeToken._(token: token));
        continue;
      }
      // XI itself stays unprefixed inside DSC data, even for private operands.
      final AiNativeInstruction? command = reader.add(
        token,
        isPrivate: token.kind == .executableName && token.lexeme == 'XI' ? reader._private ?? projection.isPrivate(token.start) : projection.isPrivate(token.start),
      );
      if (command != null) {
        items.add(command);
      }
    }
    reader.finish();
    if (embedded != 0) {
      throw const FormatException('Unterminated native drawing body.');
    }
    return items;
  }

  /// Builds exact path/group spans, then binds native live-shape representations.
  AiNativeDrawing read() => readItems(_items());

  /// Builds the same topology for an already bounded source command interval.
  AiNativeDrawing readItems(List<AiNativeItem> items) {
    final List<AiNativePath> paths = [];
    final List<AiNativeGroup> groups = [];
    final List<AiNativeInstruction> geometry = [];
    final List<_NativeGroupBuilder> stack = [];
    for (final AiNativeItem item in items) {
      if (item is! AiNativeInstruction) {
        if (geometry.isNotEmpty) {
          throw const FormatException('Native record interrupts an unfinished path.');
        }
        continue;
      }
      final String operator = item.operator;
      if (_nativeGeometry.contains(operator)) {
        final List<double>? numbers = item.numbers;
        if (numbers == null || geometry.isEmpty && operator != 'm' || geometry.isNotEmpty && geometry.first.isPrivate != item.isPrivate) {
          throw const FormatException('Invalid native authoring path.');
        }
        try {
          AiPathSegment(operator: operator, coordinates: numbers);
        } on ArgumentError {
          throw const FormatException('Invalid native authoring path coordinates.');
        }
        geometry.add(item);
      } else if (_nativePaint.contains(operator) && geometry.isNotEmpty) {
        if (item.isPrivate != geometry.first.isPrivate || item.operands.isNotEmpty) {
          throw const FormatException('Native path paint disagrees with its geometry.');
        }
        final AiNativePath path = AiNativePath._(geometry: geometry, paint: item, isPrivate: item.isPrivate);
        paths.add(path);
        if (stack.isNotEmpty) {
          stack.last.children.add(path);
        }
        geometry.clear();
      } else if (const {'u', '*u', 'q'}.contains(operator)) {
        if (geometry.isNotEmpty || stack.length >= records.program.limits.maxDepth) {
          throw const FormatException('Invalid or excessively nested native group.');
        }
        stack.add(_NativeGroupBuilder(opening: item));
      } else if (const {'U', '*U', 'Q'}.contains(operator)) {
        if (geometry.isNotEmpty || stack.isEmpty || stack.last.opening.operator.toUpperCase() != operator || stack.last.opening.isPrivate != item.isPrivate) {
          throw const FormatException('Unmatched native group boundary.');
        }
        final _NativeGroupBuilder builder = stack.removeLast();
        final AiNativeGroup group = AiNativeGroup._(opening: builder.opening, closing: item, children: builder.children);
        groups.add(group);
        if (stack.isNotEmpty) {
          stack.last.children.add(group);
        }
      }
    }
    if (geometry.isNotEmpty || stack.isNotEmpty) {
      throw const FormatException('Unterminated native path or group.');
    }
    final List<AiNativeGradient> gradients = _readNativeGradients(instructions: items.whereType<AiNativeInstruction>(), paths: paths);
    return AiNativeDrawing._(
      records: records,
      items: items,
      paths: paths,
      groups: groups,
      gradients: gradients,
      liveShapes: _shapes(items: items, paths: paths, groups: groups, gradients: gradients),
    );
  }

  /// Associates direct fills and XW-delimited alternate geometry by adjacency.
  List<AiLiveShape> _shapes({required List<AiNativeItem> items, required List<AiNativePath> paths, required List<AiNativeGroup> groups, required List<AiNativeGradient> gradients}) {
    final Map<int, AiNativePath> pathEnds = {
      for (final AiNativePath path in paths) path.end: path,
      for (final AiNativeGradient gradient in gradients.where((gradient) => gradient.paths.length == 1)) gradient.end: gradient.paths.single,
    };
    final Map<int, AiNativeGroup> groupEnds = {for (final AiNativeGroup group in groups) group.end: group};
    final Map<String, AiNativeContainer> styles = {};
    final Set<String> ambiguousStyles = {};
    for (final AiNativeContainer root in records.roots.where((root) => root.type == 'KnownStyle')) {
      final String? name = root['Name']?.text();
      if (name != null) {
        if (styles.containsKey(name)) {
          ambiguousStyles.add(name);
        }
        styles[name] = root;
      }
    }
    final List<AiLiveShape> result = [];
    final Set<AiNativeContainer> alternatives = {};
    int alternate = -1;
    for (int index = 0; index < items.length; index++) {
      final AiNativeItem item = items[index];
      if (_marker(item, 6)) {
        alternate = index;
      }
      if (item is! AiNativeContainer || item.type != 'ArtDictionary' || alternatives.contains(item)) {
        continue;
      }
      final AiNativeContainer? definition = item['ai::LiveShape']?.container;
      if (definition == null || definition.notRecorded) {
        continue;
      }
      final String? handler = definition['ai::LiveShape::HandlerName']?.text();
      final AiNativeContainer? parameters = definition['ai::LiveShape::Params']?.container;
      if (handler == null || parameters == null) {
        throw const FormatException('Incomplete native live-shape definition.');
      }
      final bool versioned =
          index > 0 && items[index - 1] is AiNativeVersionComment && RegExp(r'^%AI17_Begin_Content_if_version_gt:\s*\d+\s+\d+$').hasMatch((items[index - 1] as AiNativeVersionComment).token.lexeme);
      final int preceding = index - (versioned ? 2 : 1);
      final AiNativePath? path = preceding >= 0 ? pathEnds[items[preceding].end] : null;
      final List<AiNativeContainer> alternativeDictionaries = [];
      int following = index + 1;
      if (versioned &&
          following + 2 < items.length &&
          _versionComment(items[following], '%AI17_Alternate_Content') &&
          items[following + 1] is AiNativeContainer &&
          (items[following + 1] as AiNativeContainer).type == 'ArtDictionary' &&
          _versionComment(items[following + 2], '%AI17_End_Versioned_Content')) {
        alternativeDictionaries.add(items[following + 1] as AiNativeContainer);
        alternatives.addAll(alternativeDictionaries);
        following += 3;
      }
      final List<AiNativePath> appearance = [];
      AiNativeContainer? appearanceDictionary;
      AiNativeGroup? appearanceGroup;
      String? styleName;
      String? issue;
      int start = path?.start ?? item.start;
      int end = item.end;
      if (path == null) {
        issue = 'The authoritative dictionary has no adjacent path.';
      } else if (!path.isPrivate) {
        appearance.add(path);
      } else if (alternate < 0 || items[alternate].start >= path.start || following >= items.length || !_marker(items[following], 1)) {
        issue = 'The private path has no complete XW appearance binding.';
      } else {
        final AiNativeInstruction styleMarker = items[following] as AiNativeInstruction;
        styleName = latin1.decode(aiStringBytes(styleMarker.operands[1]));
        end = styleMarker.end;
        int previous = alternate - 1;
        while (previous >= 0 && items[previous] is AiNativeInstruction && const {'Xd', 'Xy'}.contains((items[previous] as AiNativeInstruction).operator)) {
          previous--;
        }
        if (previous >= 1 && items[previous] is AiNativeContainer) {
          final AiNativeContainer candidate = items[previous] as AiNativeContainer;
          final AiNativeContainer? previousDefinition = candidate['ai::LiveShape']?.container;
          if (candidate.type == 'ArtDictionary' && previousDefinition?.notRecorded == true && previousDefinition?['ai::LiveShape::HandlerName']?.text() == handler) {
            appearanceDictionary = candidate;
            appearanceGroup = groupEnds[items[previous - 1].end];
            if (appearanceGroup != null && !appearanceGroup.opening.isPrivate) {
              appearance.addAll(appearanceGroup.paths);
              start = appearanceGroup.start;
            }
          }
        }
        if (paths.where((candidate) => candidate.start > items[alternate].end && candidate.end <= path.end).length != 1) {
          issue = 'The XW appearance binding contains multiple authoring paths.';
        } else if (appearance.isEmpty || appearance.any((path) => path.isPrivate)) {
          issue = 'The compatibility expansion has no matching printable group.';
        } else if (!styles.containsKey(styleName)) {
          issue = 'The referenced native appearance style is missing.';
        } else if (ambiguousStyles.contains(styleName)) {
          issue = 'The referenced native appearance style has ambiguous declarations.';
        }
        alternate = -1;
      }
      result.add(
        AiLiveShape._(
          dictionary: item,
          definition: definition,
          parameters: parameters,
          handler: handler,
          path: path,
          appearancePaths: appearance,
          appearanceDictionary: appearanceDictionary,
          alternativeDictionaries: alternativeDictionaries,
          appearanceGroup: appearanceGroup,
          styleName: styleName,
          style: styleName == null || ambiguousStyles.contains(styleName) ? null : styles[styleName],
          start: start,
          end: end,
          bindingIssue: issue,
        ),
      );
    }
    return result;
  }
}

/// Mutable group construction state, never exposed as a document snapshot.
final class _NativeGroupBuilder {
  /// Original group opening instruction.
  final AiNativeInstruction opening;

  /// Completed direct child nodes.
  final List<AiNativeItem> children = [];

  /// Starts a bounded group at its original byte position.
  _NativeGroupBuilder({required this.opening});
}

/// Native path commands with explicit coordinate operands.
const Set<String> _nativeGeometry = {'m', 'l', 'L', 'c', 'C', 'v', 'V', 'y', 'Y'};

/// Native path consumption commands.
const Set<String> _nativePaint = {'N', 'n', 'F', 'f', 'S', 's', 'B', 'b'};

/// Recognizes exact XW alternate-path and known-style markers.
bool _marker(AiNativeItem item, int mode) =>
    item is AiNativeInstruction &&
    item.operator == 'XW' &&
    item.operands.length == 2 &&
    item.operands[0].number == mode &&
    const {AiTokenKind.string, AiTokenKind.hexString}.contains(item.operands[1].kind);

/// Matches a structural version comment without consuming unrelated metadata.
bool _versionComment(AiNativeItem item, String text) => item is AiNativeVersionComment && item.token.lexeme == text;
