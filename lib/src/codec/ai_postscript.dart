import 'dart:convert';
import 'dart:typed_data';

import 'package:aicodec/src/model/ai_limit_exception.dart';

part 'ai_raster_data.dart';
part 'ai_placed_preview_data.dart';

/// Syntactic categories in an Illustrator PostScript program.
enum AiTokenKind {
  /// A decimal, exponent or radix number.
  number,

  /// A slash-prefixed literal name.
  literalName,

  /// A name evaluated by the host's PostScript/Illustrator interpreter.
  executableName,

  /// A parenthesized byte string, including its original escapes.
  string,

  /// A hexadecimal byte string.
  hexString,

  /// An ASCII85 byte string.
  ascii85String,

  /// An array opening bracket.
  arrayStart,

  /// An array closing bracket.
  arrayEnd,

  /// A procedure opening brace.
  procedureStart,

  /// A procedure closing brace.
  procedureEnd,

  /// A dictionary opening delimiter.
  dictionaryStart,

  /// A dictionary closing delimiter.
  dictionaryEnd,

  /// A percent comment, including DSC declarations.
  comment,

  /// Opaque bytes protected by a DSC BeginBinary or BeginData declaration.
  data,
}

/// An immutable token with an exact byte span in its original program.
final class AiToken {
  /// Token's syntactic category.
  final AiTokenKind kind;

  /// Inclusive byte offset in the supplied PostScript section.
  final int start;

  /// Exclusive byte offset in the supplied PostScript section.
  final int end;

  /// Exact bytes mapped one-to-one to Latin-1 code points.
  final String lexeme;

  /// Creates a token without assigning drawing semantics to its name.
  const AiToken({required this.kind, required this.start, required this.end, required this.lexeme});

  /// Numeric value for a recognized number, otherwise null.
  num? get number => kind == AiTokenKind.number ? _number(lexeme) : null;
}

/// Bounded PostScript tokenization without executing procedures or operators.
///
/// Tokens expose source spans for targeted edits. Illustrator drawing operators
/// remain executable names; evaluating them is a host responsibility. Comments,
/// prologs, procedures and unknown names are retained rather than discarded.
abstract final class AiPostScript {
  /// Tokenizes a complete legacy or extracted Illustrator PostScript section.
  static List<AiToken> tokenize(List<int> input, {int maxBytes = 128 * 1024 * 1024, int maxTokens = 1000000, int maxDepth = 128}) {
    if (maxBytes <= 0 || maxTokens <= 0 || maxDepth <= 0) {
      throw ArgumentError('PostScript limits must be positive.');
    }
    if (input.length > maxBytes) {
      throw const AiLimitException(message: 'PostScript exceeds the byte limit.');
    }
    if (input.any((byte) => byte < 0 || byte > 255)) {
      throw const FormatException('Input contains values outside the byte range.');
    }
    final Uint8List bytes = Uint8List.fromList(input);
    final List<AiToken> tokens = [];
    int procedureDepth = 0;
    int position = 0;
    bool raster = false;

    /// Adds a copied token without retaining mutable source memory.
    void add(AiTokenKind kind, int start, int end) {
      if (tokens.length >= maxTokens) {
        throw const AiLimitException(message: 'PostScript exceeds the token limit.');
      }
      tokens.add(AiToken(kind: kind, start: start, end: end, lexeme: latin1.decode(Uint8List.sublistView(bytes, start, end))));
    }

    /// Advances over a single physical line ending.
    void newline() {
      if (position < bytes.length && bytes[position++] == 13 && position < bytes.length && bytes[position] == 10) {
        position++;
      }
    }

    while (position < bytes.length) {
      final int start = position;
      final int byte = bytes[position++];
      if (_space(byte)) {
        continue;
      }
      if (byte == 37) {
        while (position < bytes.length && bytes[position] != 10 && bytes[position] != 13) {
          position++;
        }
        add(AiTokenKind.comment, start, position);
        final String line = tokens.last.lexeme;
        if (procedureDepth == 0 && const {'%AI26_BeginPlacedObjectPreview', '%_%AI26_BeginPlacedObjectPreview'}.contains(line)) {
          newline();
          final int previewStart = position;
          final AiPlacedPreviewData preview = readAiPlacedPreview(bytes: bytes, start: previewStart, privateData: line.startsWith('%_'));
          add(AiTokenKind.data, previewStart, preview.end);
          position = preview.end;
          continue;
        }
        if (procedureDepth == 0 && const {'%AI5_BeginRaster', '%_%AI5_BeginRaster'}.contains(line)) {
          raster = true;
        } else if (const {'%AI5_EndRaster', '%_%AI5_EndRaster'}.contains(line)) {
          raster = false;
        }
        final bool privateData = raster && line.startsWith('%_%%BeginData:');
        if (line.startsWith('%%BeginBinary:') || line.startsWith('%%BeginData:') || privateData) {
          final List<String> fields = line.substring(line.indexOf(':') + 1).trim().split(RegExp(r'\s+'));
          final int? count = int.tryParse(fields.first);
          if (count == null || count < 0 || count > bytes.length) {
            throw const FormatException('Invalid PostScript data count.');
          }
          newline();
          final int dataStart = position;
          if (raster && procedureDepth == 0 && (line.startsWith('%%BeginData:') || privateData) && fields.last.toLowerCase() != 'lines') {
            final ({int samples, int end})? image = readAiRasterData(bytes: bytes, start: dataStart, declared: count, tokens: tokens, privateData: privateData);
            if (image != null) {
              if (!privateData) {
                add(AiTokenKind.executableName, dataStart, dataStart + 2);
              }
              add(AiTokenKind.data, privateData ? dataStart : image.samples, image.end);
              position = image.end;
              continue;
            }
          }
          if (fields.last.toLowerCase() == 'lines') {
            for (int index = 0; index < count; index++) {
              if (position >= bytes.length) {
                throw const FormatException('Truncated PostScript data lines.');
              }
              while (position < bytes.length && bytes[position] != 10 && bytes[position] != 13) {
                position++;
              }
              newline();
            }
          } else {
            if (position + count > bytes.length) {
              throw const FormatException('Truncated PostScript binary data.');
            }
            position += count;
          }
          add(AiTokenKind.data, dataStart, position);
        }
        continue;
      }
      if (byte == 40) {
        int depth = 1;
        while (position < bytes.length && depth > 0) {
          final int next = bytes[position++];
          if (next == 92 && position < bytes.length) {
            position++;
          } else if (next == 40) {
            if (++depth > maxDepth) {
              throw const AiLimitException(message: 'PostScript string nesting exceeds the limit.');
            }
          } else if (next == 41) {
            depth--;
          }
        }
        if (depth != 0) {
          throw const FormatException('Unterminated PostScript string.');
        }
        add(AiTokenKind.string, start, position);
        continue;
      }
      if (byte == 60 && (position >= bytes.length || bytes[position] != 60)) {
        final bool ascii85 = position < bytes.length && bytes[position] == 126;
        if (ascii85) {
          position++;
        }
        bool ended = false;
        while (position < bytes.length) {
          final int next = bytes[position++];
          if ((!ascii85 && next == 62) || (ascii85 && next == 126 && position < bytes.length && bytes[position] == 62)) {
            if (ascii85) {
              position++;
            }
            ended = true;
            break;
          }
          if (!ascii85 && !_space(next) && !((next >= 48 && next <= 57) || (next >= 65 && next <= 70) || (next >= 97 && next <= 102))) {
            throw const FormatException('Invalid PostScript hexadecimal string.');
          }
        }
        if (!ended) {
          throw const FormatException('Unterminated PostScript encoded string.');
        }
        add(ascii85 ? AiTokenKind.ascii85String : AiTokenKind.hexString, start, position);
        continue;
      }
      if ([91, 123, 60].contains(byte)) {
        if (byte == 60) {
          position++;
        }
        // Arrays and dictionaries are runtime operators in PostScript; they
        // can deliberately cross procedure boundaries in Illustrator prologs.
        if (byte == 123 && ++procedureDepth > maxDepth) {
          throw const AiLimitException(message: 'PostScript nesting exceeds the limit.');
        }
        add(
          switch (byte) {
            91 => AiTokenKind.arrayStart,
            123 => AiTokenKind.procedureStart,
            _ => AiTokenKind.dictionaryStart,
          },
          start,
          position,
        );
        continue;
      }
      if ([93, 125, 62].contains(byte)) {
        if (byte == 62) {
          if (position >= bytes.length || bytes[position++] != 62) {
            throw const FormatException('Invalid PostScript dictionary delimiter.');
          }
        }
        if (byte == 125 && --procedureDepth < 0) {
          throw const FormatException('Unmatched PostScript procedure delimiter.');
        }
        add(
          switch (byte) {
            93 => AiTokenKind.arrayEnd,
            125 => AiTokenKind.procedureEnd,
            _ => AiTokenKind.dictionaryEnd,
          },
          start,
          position,
        );
        continue;
      }
      if (byte == 41) {
        throw const FormatException('Unmatched PostScript string delimiter.');
      }
      if (byte == 47 && position < bytes.length && const [91, 93].contains(bytes[position])) {
        position++;
        add(AiTokenKind.literalName, start, position);
        continue;
      }
      // A second slash is an immediate name lookup, retained as a name token.
      if (byte == 47 && position < bytes.length && bytes[position] == 47) {
        position++;
      }
      while (position < bytes.length && !_space(bytes[position]) && !const [40, 41, 60, 62, 91, 93, 123, 125, 47, 37].contains(bytes[position])) {
        position++;
      }
      final String lexeme = latin1.decode(Uint8List.sublistView(bytes, start, position));
      add(
        byte == 47
            ? AiTokenKind.literalName
            : _number(lexeme) != null
            ? AiTokenKind.number
            : AiTokenKind.executableName,
        start,
        position,
      );
    }
    if (procedureDepth != 0) {
      throw const FormatException('Unterminated PostScript procedure.');
    }
    return List.unmodifiable(tokens);
  }
}

/// Recognizes whitespace according to PostScript lexical conventions.
bool _space(int byte) => const [0, 9, 10, 12, 13, 32].contains(byte);

/// Parses finite PostScript decimal, exponent and radix number syntax.
num? _number(String source) {
  final RegExpMatch? radix = RegExp(r'^(\d+)#([0-9A-Za-z]+)$').firstMatch(source);
  if (radix != null) {
    final int? base = int.tryParse(radix[1]!);
    if (base == null || base < 2 || base > 36) {
      return null;
    }
    final int? value = int.tryParse(radix[2]!, radix: base);
    return value != null && value.abs() <= 9007199254740991 ? value : null;
  }
  if (!RegExp(r'^[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?$').hasMatch(source)) {
    return null;
  }
  final num? value = num.tryParse(source);
  return value != null && value.isFinite && value.abs() <= 9007199254740991 ? value : null;
}
