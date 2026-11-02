import 'dart:convert';
import 'dart:typed_data';

import 'package:aicodec/src/codec/ai_native_data.dart';
import 'package:aicodec/src/codec/ai_postscript.dart';
import 'package:aicodec/src/model/ai_document.dart';
import 'package:aicodec/src/model/ai_limit_exception.dart';

part '../editing/ai_native_editor.dart';

/// One source-backed Illustrator instruction, retaining unknown operands.
final class AiInstruction {
  /// Executable Illustrator or PostScript operator name.
  final String operator;

  /// Exact operand tokens, including array and procedure delimiters.
  final List<AiToken> operands;

  /// Operator token, with absolute offsets into the native program.
  final AiToken token;

  /// Creates an immutable instruction view.
  AiInstruction._({required this.operator, required List<AiToken> operands, required this.token}) : operands = List.unmodifiable(operands);

  /// Start of the operands, or the operator for a zero-operand instruction.
  int get start => operands.isEmpty ? token.start : operands.first.start;

  /// Exclusive end of the operator token.
  int get end => token.end;

  /// Numeric operands when every operand is a finite number.
  List<double>? get numbers => operands.every((operand) => operand.number != null) ? List.unmodifiable(operands.map((operand) => operand.number!.toDouble())) : null;
}

/// A native Illustrator layer, including nested and hidden layers.
final class AiLayer {
  /// Begin-layer instruction, whose complete version-specific operands survive.
  final AiInstruction begin;

  /// Optional naming instruction containing original PostScript string bytes.
  final AiInstruction? naming;

  /// End-layer instruction.
  final AiInstruction end;

  /// Begin offset of the parent layer, or null for a top-level layer.
  final int? parentStart;

  /// Instructions owned by this layer before its first child or artwork.
  final List<AiInstruction> header;

  /// Creates a layer tied to one immutable native program snapshot.
  AiLayer._({required this.begin, required this.naming, required this.end, required this.parentStart, required List<AiInstruction> header}) : header = List.unmodifiable(header);

  /// Display name decoded from a byte string; no font encoding is inferred.
  String? get name => naming == null ? null : latin1.decode(aiStringBytes(naming!.operands.single));

  /// Whether Illustrator displays this layer.
  bool get visible => begin.numbers![0] != 0;

  /// Whether objects on this layer are protected from editing.
  bool get locked => begin.numbers![2] == 0;

  /// Whether the layer participates in printing.
  bool get printing => begin.numbers![3] != 0;
}

/// One native path command, including Illustrator smooth/corner distinctions.
final class AiPathSegment {
  /// Original command: m, l/L, c/C, v/V or y/Y.
  final String operator;

  /// Coordinates in the native Illustrator coordinate system.
  final List<double> coordinates;

  /// Creates a finite correctly sized path command.
  AiPathSegment({required this.operator, required List<double> coordinates}) : coordinates = List.unmodifiable(coordinates) {
    final int expected = switch (operator) {
      'm' || 'l' || 'L' => 2,
      'c' || 'C' => 6,
      'v' || 'V' || 'y' || 'Y' => 4,
      _ => throw ArgumentError.value(operator, 'operator', 'Unsupported Illustrator path command'),
    };
    if (coordinates.length != expected || coordinates.any((value) => !value.isFinite)) {
      throw ArgumentError('Invalid Illustrator path coordinates.');
    }
  }
}

/// Source-backed path geometry, retaining its paint operator and metadata.
final class AiPath {
  /// Ordered geometry instructions, preserving corners and curve shorthand.
  final List<AiInstruction> geometry;

  /// The original path-consuming paint instruction.
  final AiInstruction paint;

  /// Begin offset of the containing layer, or null for unlayered artwork.
  final int? layerStart;

  /// Whether this path participates in a compound path.
  final bool compound;

  /// Whether a modern appearance or live shape owns this path's geometry.
  final bool hasDependentAppearance;

  /// Creates a path without flattening its original paint and private metadata.
  AiPath._({required List<AiInstruction> geometry, required this.paint, required this.layerStart, required this.compound, required this.hasDependentAppearance})
    : geometry = List.unmodifiable(geometry);

  /// Exact native segments, independent of the PDF compatibility view.
  List<AiPathSegment> get segments => List.unmodifiable(geometry.map((instruction) => AiPathSegment(operator: instruction.operator, coordinates: instruction.numbers!)));

  /// Whether Illustrator explicitly closes the editable path.
  bool get closed => const {'n', 'f', 's', 'b'}.contains(paint.operator);

  /// Whether the path has a fill, independent of its visibility.
  bool get filled => const {'F', 'f', 'B', 'b'}.contains(paint.operator);

  /// Whether the path has a stroke.
  bool get stroked => const {'S', 's', 'B', 'b'}.contains(paint.operator);
}

/// An immutable native authoring program with source-backed structural editing.
///
/// This reads Illustrator's declarative drawing instructions. It does not run
/// arbitrary PostScript procedures, resolve plug-ins or lay out ATE text.
/// Unknown instructions and all setup/private bytes remain in [bytes].
final class AiProgram {
  /// Owned complete authoring bytes, not a regenerated approximation.
  final Uint8List _bytes;

  /// Body instructions outside procedures and opaque binary samples.
  ///
  /// A recognized XI operator inside a raster's DSC block is retained; its pixel
  /// bytes remain opaque and cannot contribute instructions or delimiters.
  final List<AiInstruction> instructions;

  /// Native layers, including empty, locked, hidden and nested layers.
  final List<AiLayer> layers;

  /// Explicit path geometry in the drawing body.
  final List<AiPath> paths;

  /// Inclusive source boundary of the drawing body after header/setup records.
  final int bodyStart;

  /// Exclusive source boundary before the page trailer.
  final int bodyEnd;

  /// Body operator names outside the structural/path interpretation contract.
  final Set<String> unhandledOperators;

  /// Whether comment-based editing alternatives require further interpretation.
  final bool hasPrivateExtensions;

  /// Resource policy retained when making edited copies.
  final AiNativeLimits limits;

  /// Creates a parsed immutable snapshot.
  AiProgram._({
    required this._bytes,
    required List<AiInstruction> instructions,
    required List<AiLayer> layers,
    required List<AiPath> paths,
    required this.bodyStart,
    required this.bodyEnd,
    required Set<String> unhandledOperators,
    required this.hasPrivateExtensions,
    required this.limits,
  }) : instructions = List.unmodifiable(instructions),
       layers = List.unmodifiable(layers),
       paths = List.unmodifiable(paths),
       unhandledOperators = Set.unmodifiable(unhandledOperators);

  /// Reads a native program extracted from a CC, earlier PDF, or legacy AI file.
  factory AiProgram.decode({required List<int> bytes, AiNativeLimits limits = const AiNativeLimits()}) {
    limits.validate();
    final List<AiToken> tokens = AiPostScript.tokenize(bytes, maxBytes: limits.maxDecodedBytes, maxTokens: limits.maxTokens, maxDepth: limits.maxDepth);
    if (tokens.isEmpty || !tokens.first.lexeme.startsWith('%!PS-Adobe-')) {
      throw const FormatException('Expected an Illustrator authoring program.');
    }
    int bodyStart = tokens.first.end;
    int bodyEnd = bytes.length;
    int procedureDepth = 0;
    int embeddedDepth = 0;
    for (final AiToken token in tokens) {
      if (token.kind == .procedureStart) {
        procedureDepth++;
      } else if (token.kind == .procedureEnd) {
        procedureDepth--;
      }
      if (token.kind != .comment || procedureDepth != 0) {
        continue;
      }
      if (token.lexeme.startsWith('%%BeginDocument')) {
        embeddedDepth++;
      } else if (token.lexeme == '%%EndDocument') {
        embeddedDepth--;
      }
      if (embeddedDepth != 0) {
        continue;
      }
      if (const {'%%EndComments', '%%EndProlog', '%%EndSetup'}.contains(token.lexeme)) {
        bodyStart = token.end;
      }
      if (const {'%%PageTrailer', '%%Trailer', '%%EOF'}.contains(token.lexeme)) {
        bodyEnd = token.start;
        break;
      }
    }
    final List<AiInstruction> instructions = [];
    final List<AiToken> operands = [];
    final List<AiTokenKind> delimiters = [];
    bool privateExtensions = false;
    embeddedDepth = 0;
    for (final AiToken token in tokens) {
      if (token.start < bodyStart || token.start >= bodyEnd) {
        continue;
      }
      if (token.kind == .comment) {
        privateExtensions |= token.lexeme.startsWith('%_') || token.lexeme.startsWith('%AI17_');
        if (token.lexeme.startsWith('%%BeginDocument')) {
          embeddedDepth++;
        } else if (token.lexeme == '%%EndDocument') {
          embeddedDepth--;
        }
        continue;
      }
      if (embeddedDepth != 0 || token.kind == .data) {
        continue;
      }
      if (const {AiTokenKind.arrayStart, AiTokenKind.dictionaryStart, AiTokenKind.procedureStart}.contains(token.kind)) {
        if (delimiters.length >= limits.maxDepth) {
          throw const AiLimitException(message: 'Illustrator operand nesting exceeds the limit.');
        }
        delimiters.add(token.kind);
      } else if (const {AiTokenKind.arrayEnd, AiTokenKind.dictionaryEnd, AiTokenKind.procedureEnd}.contains(token.kind)) {
        final AiTokenKind expected = switch (token.kind) {
          AiTokenKind.arrayEnd => .arrayStart,
          AiTokenKind.dictionaryEnd => .dictionaryStart,
          _ => .procedureStart,
        };
        if (delimiters.isEmpty || delimiters.removeLast() != expected) {
          throw const FormatException('Dynamic or unbalanced Illustrator operands are not editable.');
        }
      }
      if (token.kind == .executableName && delimiters.isEmpty) {
        instructions.add(AiInstruction._(operator: token.lexeme, operands: operands, token: token));
        operands.clear();
      } else {
        operands.add(token);
      }
    }
    if (delimiters.isNotEmpty || embeddedDepth != 0 || operands.isNotEmpty) {
      throw const FormatException('Unterminated Illustrator drawing operands.');
    }
    final List<AiLayer> layers = [];
    final List<_LayerBuilder> layerStack = [];
    final List<AiPath> paths = [];
    final List<String> groups = [];
    final List<AiInstruction> geometry = [];
    final Set<String> unhandled = {};
    bool dependent = false;
    for (int index = 0; index < instructions.length; index++) {
      final AiInstruction instruction = instructions[index];
      final String operator = instruction.operator;
      if (operator == 'Lb') {
        final List<double>? values = instruction.numbers;
        if (values == null || values.length < 10 || values.take(6).any((value) => value != 0 && value != 1)) {
          throw const FormatException('Invalid Illustrator layer attributes.');
        }
        if (layerStack.length >= limits.maxDepth) {
          throw const AiLimitException(message: 'Illustrator layer nesting exceeds the limit.');
        }
        if (layerStack.isNotEmpty) {
          layerStack.last.inHeader = false;
        }
        layerStack.add(_LayerBuilder(begin: instruction, parent: layerStack.isEmpty ? null : layerStack.last.begin.start));
      } else if (operator == 'Ln') {
        if (layerStack.isEmpty || instruction.operands.length != 1 || instruction.operands.single.kind != .string && instruction.operands.single.kind != .hexString) {
          throw const FormatException('Invalid Illustrator layer name.');
        }
        layerStack.last.naming = instruction;
      } else if (operator == 'LB') {
        if (layerStack.isEmpty) {
          throw const FormatException('Unmatched Illustrator layer end.');
        }
        final _LayerBuilder layer = layerStack.removeLast();
        layers.add(AiLayer._(begin: layer.begin, naming: layer.naming, end: instruction, parentStart: layer.parent, header: layer.header));
      } else if (const {'u', '*u', 'q'}.contains(operator)) {
        if (layerStack.isNotEmpty) {
          layerStack.last.inHeader = false;
        }
        if (groups.length >= limits.maxDepth) {
          throw const AiLimitException(message: 'Illustrator group nesting exceeds the limit.');
        }
        groups.add(operator);
      } else if (const {'U', '*U', 'Q'}.contains(operator)) {
        if (groups.isEmpty || groups.removeLast().toUpperCase() != operator) {
          throw const FormatException('Unmatched Illustrator group end.');
        }
      } else if (_geometryOperators.contains(operator)) {
        final List<double>? values = instruction.numbers;
        if (values == null || geometry.isEmpty && operator != 'm') {
          throw const FormatException('Invalid Illustrator path geometry.');
        }
        try {
          AiPathSegment(operator: operator, coordinates: values);
        } on ArgumentError {
          throw const FormatException('Invalid Illustrator path coordinates.');
        }
        geometry.add(instruction);
        if (layerStack.isNotEmpty) {
          layerStack.last.inHeader = false;
        }
      } else if (_paintOperators.contains(operator)) {
        if (geometry.isEmpty) {
          unhandled.add(operator);
          continue;
        }
        final int following = index + 1 < instructions.length ? instructions[index + 1].start : bodyEnd;
        final String metadata = latin1.decode(bytes.sublist(instruction.end, following));
        paths.add(
          AiPath._(
            geometry: geometry,
            paint: instruction,
            layerStart: layerStack.isEmpty ? null : layerStack.last.begin.start,
            compound: groups.contains('*u'),
            hasDependentAppearance: dependent || metadata.contains('ai::LiveShape') || metadata.contains('AI11Text'),
          ),
        );
        geometry.clear();
        dependent = false;
      } else if (!_attributeOperators.contains(operator)) {
        unhandled.add(operator);
        if (const {'Bb', 'Bg', 'Bm', 'X=', 'XW', 'XI', 'XF', 'XG', ':'}.contains(operator)) {
          dependent = true;
        }
      }
      if (const {'Bb', 'Bg', 'Bm'}.contains(operator)) {
        dependent = true;
      }
      if (const {'Ae', 'Ap', 'As', ':'}.contains(operator) && layerStack.isNotEmpty) {
        layerStack.last.inHeader = false;
      }
      if (layerStack.isNotEmpty && layerStack.last.inHeader && operator != 'Lb' && operator != 'Ln') {
        layerStack.last.header.add(instruction);
      }
    }
    if (layerStack.isNotEmpty || groups.isNotEmpty || geometry.isNotEmpty) {
      throw const FormatException('Unterminated Illustrator artwork container or path.');
    }
    layers.sort((first, second) => first.begin.start.compareTo(second.begin.start));
    return AiProgram._(
      bytes: Uint8List.fromList(bytes),
      instructions: instructions,
      layers: layers,
      paths: paths,
      bodyStart: bodyStart,
      bodyEnd: bodyEnd,
      unhandledOperators: unhandled,
      hasPrivateExtensions: privateExtensions,
      limits: limits,
    );
  }

  /// Exact native authoring bytes, including all unhandled instructions.
  Uint8List get bytes => _bytes.asUnmodifiableView();

  /// Whether all body operators belong to the structural interpretation subset.
  ///
  /// This does not assert renderability: setup resources and private extensions
  /// may have semantics outside this model.
  bool get hasUnhandledBodyOperators => unhandledOperators.isNotEmpty;
}

/// Mutable assembly state used only while constructing an immutable layer.
final class _LayerBuilder {
  /// Original opening instruction.
  final AiInstruction begin;

  /// Source identity of the parent layer.
  final int? parent;

  /// Naming instruction encountered in the layer header.
  AiInstruction? naming;

  /// Header-owned flags before artwork or nested layers.
  final List<AiInstruction> header = [];

  /// Whether subsequent instructions are still in this layer's header.
  bool inHeader = true;

  /// Starts a layer before its name and contents have been read.
  _LayerBuilder({required this.begin, required this.parent});
}

/// Native path construction commands, preserving corner flags.
const Set<String> _geometryOperators = {'m', 'l', 'L', 'c', 'C', 'v', 'V', 'y', 'Y'};

/// Native path consumption commands, including unpainted editable paths.
const Set<String> _paintOperators = {'N', 'n', 'F', 'f', 'S', 's', 'B', 'b'};

/// Recognized source attributes retained without claiming complete rendering.
const Set<String> _attributeOperators = {
  'A',
  'D',
  'O',
  'R',
  'J',
  'j',
  'w',
  'M',
  'd',
  'XR',
  'g',
  'G',
  'k',
  'K',
  'Xa',
  'XA',
  'x',
  'X',
  'Xx',
  'XX',
  'Xy',
  'Xw',
  'AE',
  'Ae',
  'Ap',
  'As',
  'Xd',
  'Bb',
  'BB',
  'Bg',
  'Bc',
  'Bm',
  'Xm',
};

/// Decodes PostScript byte strings without applying a guessed text encoding.
Uint8List aiStringBytes(AiToken token) {
  if (token.kind == .hexString) {
    final String digits = token.lexeme.substring(1, token.lexeme.length - 1).replaceAll(RegExp(r'\s'), '');
    final String padded = digits.length.isOdd ? '${digits}0' : digits;
    return Uint8List.fromList([for (int index = 0; index < padded.length; index += 2) int.parse(padded.substring(index, index + 2), radix: 16)]);
  }
  if (token.kind != .string) {
    throw ArgumentError('Expected a PostScript string token.');
  }
  final List<int> source = token.lexeme.codeUnits;
  final BytesBuilder output = BytesBuilder();
  for (int index = 1; index < source.length - 1; index++) {
    final int byte = source[index];
    if (byte == 92) {
      final int escaped = source[++index];
      if (escaped >= 48 && escaped <= 55) {
        int value = escaped - 48;
        int count = 1;
        while (count < 3 && index + 1 < source.length - 1 && source[index + 1] >= 48 && source[index + 1] <= 55) {
          value = value * 8 + source[++index] - 48;
          count++;
        }
        output.addByte(value & 255);
      } else if (escaped == 13 || escaped == 10) {
        if (escaped == 13 && source[index + 1] == 10) {
          index++;
        }
      } else {
        output.addByte(switch (escaped) {
          110 => 10,
          114 => 13,
          116 => 9,
          98 => 8,
          102 => 12,
          _ => escaped,
        });
      }
    } else {
      output.addByte(byte == 13 ? 10 : byte);
      if (byte == 13 && source[index + 1] == 10) {
        index++;
      }
    }
  }
  return output.takeBytes();
}
