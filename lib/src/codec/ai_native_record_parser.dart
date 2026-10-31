part of 'package:aikit/src/model/ai_native_records.dart';

/// Removes native comment prefixes while retaining reversible source offsets.
final class _NativeRecordProjection {
  /// Native tokens whose spans refer to the original program.
  final List<AiToken> tokens;

  /// Original comment intervals expanded into private authoring tokens.
  final List<({int start, int end})> privateLines;

  /// Builds a projection without touching strings, procedures or binary bodies.
  factory _NativeRecordProjection({required AiProgram program}) {
    final List<AiToken> original = AiPostScript.tokenize(program.bytes, maxBytes: program.limits.maxDecodedBytes, maxTokens: program.limits.maxTokens, maxDepth: program.limits.maxDepth);
    final List<int> removed = [];
    final List<({int start, int end})> privateLines = [];
    final BytesBuilder projected = BytesBuilder(copy: false);
    int position = 0;
    bool binary = false;
    for (int index = 0; index < original.length; index++) {
      final AiToken token = original[index];
      if (token.kind == .literalName && _binaryRecordTypes.contains(token.lexeme.substring(1)) && index + 1 < original.length && original[index + 1].lexeme == ':') {
        binary = true;
      }
      if (token.kind != .comment) {
        continue;
      }
      if (binary) {
        if (token.lexeme.trimRight().endsWith('~>')) {
          binary = false;
        }
        continue;
      }
      if (token.lexeme.startsWith('%_')) {
        projected.add(Uint8List.sublistView(program.bytes, position, token.start));
        removed.add(token.start - removed.length * 2);
        privateLines.add((start: token.start + 2, end: token.end));
        position = token.start + 2;
        binary = _binaryOpening.hasMatch(token.lexeme.substring(2));
      }
    }
    projected.add(Uint8List.sublistView(program.bytes, position));

    /// Maps a projected boundary without allocating one index per input byte.
    int sourceOffset(int offset, {bool end = false}) {
      int low = 0;
      int high = removed.length;
      while (low < high) {
        final int middle = (low + high) ~/ 2;
        if (removed[middle] < offset || !end && removed[middle] == offset) {
          low = middle + 1;
        } else {
          high = middle;
        }
      }
      return offset + low * 2;
    }

    final List<AiToken> tokens = AiPostScript.tokenize(projected.takeBytes(), maxBytes: program.limits.maxDecodedBytes, maxTokens: program.limits.maxTokens, maxDepth: program.limits.maxDepth);
    return _NativeRecordProjection._(
      privateLines: privateLines,
      tokens: [
        for (final AiToken token in tokens) AiToken(kind: token.kind, start: sourceOffset(token.start), end: sourceOffset(token.end, end: true), lexeme: token.lexeme),
      ],
    );
  }

  /// Retains the completed projected token stream.
  const _NativeRecordProjection._({required this.tokens, required this.privateLines});

  /// Identifies the representation of a token by its original source position.
  bool isPrivate(int offset) {
    int low = 0;
    int high = privateLines.length;
    while (low < high) {
      final int middle = (low + high) ~/ 2;
      if (privateLines[middle].start <= offset) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    return low > 0 && offset < privateLines[low - 1].end;
  }
}

/// Reads hierarchical delimiters without executing embedded drawing commands.
final class _NativeRecordReader {
  /// Source snapshot and resource policy.
  final AiProgram program;

  /// Projected tokens with original byte spans.
  final List<AiToken> tokens;

  /// Index of the next unread token.
  int position = 0;

  /// Creates a bounded source-backed reader.
  _NativeRecordReader({required this.program}) : tokens = _NativeRecordProjection(program: program).tokens;

  /// Whether the cursor points to a slash-name followed by a native colon.
  bool get _opens => position + 1 < tokens.length && tokens[position].kind == .literalName && tokens[position + 1].lexeme == ':';

  /// Collects roots outside PostScript procedures and embedded documents.
  List<AiNativeContainer> read() {
    final List<AiNativeContainer> roots = [];
    int procedures = 0;
    int embedded = 0;
    for (; position < tokens.length;) {
      final AiToken token = tokens[position];
      if (token.kind == .procedureStart) {
        procedures++;
      } else if (token.kind == .procedureEnd) {
        procedures--;
      } else if (token.kind == .comment && token.lexeme.startsWith('%%BeginDocument')) {
        embedded++;
      } else if (token.kind == .comment && token.lexeme == '%%EndDocument') {
        embedded--;
      }
      if (procedures == 0 && embedded == 0 && _opens) {
        roots.add(_container(0));
      } else {
        position++;
      }
    }
    return roots;
  }

  /// Reads a complete container and all nested children within the depth bound.
  AiNativeContainer _container(int depth) {
    if (depth >= program.limits.maxDepth) {
      throw const AiLimitException(message: 'Illustrator native record nesting exceeds the limit.');
    }
    final AiToken opening = tokens[position];
    final String type = opening.lexeme.substring(1);
    position += 2;
    final List<AiNativeEntry> entries = [];
    final List<AiNativeItem> pending = [];
    final List<AiTokenKind> delimiters = [];
    Uint8List? binary;
    int? binaryStart;
    int? binaryEnd;
    if (_binaryRecordTypes.contains(type)) {
      binary = _binary();
      binaryStart = _binaryStart;
      binaryEnd = tokens[position - 1].end;
    }
    while (position < tokens.length) {
      final AiToken token = tokens[position];
      if (token.kind == .comment || token.kind == .data) {
        position++;
        continue;
      }
      if (delimiters.isEmpty && token.lexeme == ';') {
        if (pending.isNotEmpty) {
          entries.add(_entry(type: type, items: pending));
        }
        position++;
        if (_dictionaryRecordTypes.contains(type)) {
          final Set<String> keys = {};
          for (final AiNativeEntry entry in entries) {
            if (!entry.isQualifier && entry.key != null && !keys.add(entry.key!)) {
              throw const FormatException('Duplicate Illustrator native dictionary key.');
            }
          }
        }
        return AiNativeContainer._(start: opening.start, end: token.end, type: type, entries: entries, binary: binary, binaryStart: binaryStart, binaryEnd: binaryEnd);
      }
      if (delimiters.isEmpty && token.lexeme == ',') {
        if (pending.isEmpty) {
          throw const FormatException('Empty Illustrator native record entry.');
        }
        entries.add(_entry(type: type, items: pending));
        pending.clear();
        position++;
        continue;
      }
      if (delimiters.isEmpty && _opens) {
        pending.add(_container(depth + 1));
        continue;
      }
      if (const {AiTokenKind.arrayStart, AiTokenKind.dictionaryStart, AiTokenKind.procedureStart}.contains(token.kind)) {
        if (depth + delimiters.length + 1 >= program.limits.maxDepth) {
          throw const AiLimitException(message: 'Illustrator native value nesting exceeds the limit.');
        }
        delimiters.add(token.kind);
      } else if (const {AiTokenKind.arrayEnd, AiTokenKind.dictionaryEnd, AiTokenKind.procedureEnd}.contains(token.kind)) {
        final AiTokenKind expected = switch (token.kind) {
          AiTokenKind.arrayEnd => .arrayStart,
          AiTokenKind.dictionaryEnd => .dictionaryStart,
          _ => .procedureStart,
        };
        if (delimiters.isEmpty || delimiters.removeLast() != expected) {
          throw const FormatException('Unbalanced Illustrator native record value.');
        }
      }
      pending.add(AiNativeToken._(token: token));
      position++;
    }
    throw const FormatException('Unterminated Illustrator native record.');
  }

  /// Retains an ASCII85 payload without treating its bytes as native operators.
  Uint8List _binary() {
    if (position + 1 >= tokens.length || tokens[position].lexeme != '/ASCII85Decode' || tokens[position + 1].lexeme != ',') {
      throw const FormatException('Unsupported Illustrator native binary encoding.');
    }
    position += 2;
    _binaryStart = position < tokens.length ? tokens[position].start : null;
    final BytesBuilder encoded = BytesBuilder();
    while (position < tokens.length) {
      final AiToken token = tokens[position++];
      if (token.kind != .comment || !token.lexeme.startsWith('%')) {
        throw const FormatException('Unterminated Illustrator ASCII85 payload.');
      }
      final String data = token.lexeme.substring(1).trimRight();
      encoded.add(latin1.encode(data));
      if (data.endsWith('~>')) {
        return encoded.takeBytes();
      }
      encoded.addByte(10);
    }
    throw const FormatException('Truncated Illustrator ASCII85 payload.');
  }

  /// Start of the most recently read binary payload.
  int? _binaryStart;

  /// Separates typed dictionary values from keys while preserving other syntax.
  AiNativeEntry _entry({required String type, required List<AiNativeItem> items}) {
    final List<AiNativeItem> values = [...items];
    String? key;
    String? dataType;
    AiToken? typeToken;
    final bool dictionary = _dictionaryRecordTypes.contains(type);
    if (values.length == 1 && values.single is AiNativeToken) {
      final String lexeme = (values.single as AiNativeToken).token.lexeme;
      if (const {'/Recorded', '/NotRecorded'}.contains(lexeme)) {
        return AiNativeEntry._(key: lexeme.substring(1), type: null, items: [], isQualifier: true);
      }
    }
    if (type != 'Array' && values.last is AiNativeToken) {
      final AiToken token = (values.last as AiNativeToken).token;
      if (dictionary && (token.kind == .string || token.kind == .hexString)) {
        final List<Uint8List> fragments = [];
        while (values.isNotEmpty && values.last is AiNativeToken) {
          final AiToken fragment = (values.last as AiNativeToken).token;
          if (fragment.kind != .string && fragment.kind != .hexString) {
            break;
          }
          fragments.add(aiStringBytes(fragment));
          values.removeLast();
        }
        key = latin1.decode(fragments.reversed.expand((fragment) => fragment).toList());
      } else if (!dictionary && token.kind == .literalName) {
        key = token.lexeme.substring(1);
        values.removeLast();
      }
    }
    if (dictionary && values.isNotEmpty && values.last is AiNativeToken) {
      final AiToken token = (values.last as AiNativeToken).token;
      if (token.kind == .literalName) {
        typeToken = token;
        dataType = token.lexeme.substring(1);
        values.removeLast();
      }
    }
    if (dictionary && key == null) {
      throw const FormatException('Illustrator native dictionary entry has no string key.');
    }
    final AiNativeEntry result = AiNativeEntry._(key: key, type: dataType, typeToken: typeToken, items: values);
    final int? count = switch (dataType) {
      'Bool' || 'Int' || 'Real' => 1,
      'RealPoint' || 'RealPointRelToROrigin' => 2,
      'RealMatrix' => 6,
      _ => null,
    };
    if (count != null) {
      final List<double>? numbers = result.numbers;
      if (numbers == null ||
          numbers.length != count ||
          numbers.any((value) => !value.isFinite) ||
          dataType == 'Bool' && numbers.single != 0 && numbers.single != 1 ||
          dataType == 'Int' && numbers.single != numbers.single.truncateToDouble()) {
        throw const FormatException('Invalid Illustrator native numeric value.');
      }
    }
    if (const {'String', 'UnicodeString'}.contains(dataType) && result.stringBytes == null) {
      throw FormatException('Invalid Illustrator native string value at byte ${items.first.start}.');
    }
    return result;
  }
}

/// Containers using string keys and explicit scalar type suffixes.
const Set<String> _dictionaryRecordTypes = {'Dictionary', 'ArtDictionary', 'XMLNode'};

/// Containers whose body begins with a comment-prefixed ASCII85 stream.
const Set<String> _binaryRecordTypes = {'Binary', 'AI11TextDocument', 'AI11UndoFreeTextDocument'};

/// Recognizes binary headers before stripping comment markers from their bodies.
final RegExp _binaryOpening = RegExp(r'^\s*/(?:Binary|AI11TextDocument|AI11UndoFreeTextDocument)\s*:');
