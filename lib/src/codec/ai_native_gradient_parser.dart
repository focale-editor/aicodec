part of 'package:aikit/src/model/ai_native_records.dart';

/// Groups gradient commands while preserving unsupported surrounding semantics.
List<AiNativeGradient> _readNativeGradients({required Iterable<AiNativeInstruction> instructions, required List<AiNativePath> paths}) {
  final List<AiNativeGradient> gradients = [];
  AiNativeInstruction? opening;
  AiNativeGradientGeometry? geometry;
  AiNativeInstruction? highlight;
  final List<AiNativeInstruction> matrices = [];
  int pathIndex = 0;
  for (final AiNativeInstruction instruction in instructions) {
    if (!_gradientCommands.contains(instruction.operator)) {
      continue;
    }
    if (instruction.operator == 'Bb') {
      final List<double>? selector = instruction.numbers;
      if (opening != null || selector == null || selector.length > 1 || selector.isNotEmpty && !const {0, 1}.contains(selector.single)) {
        throw const FormatException('Invalid or nested native gradient beginning.');
      }
      opening = instruction;
      continue;
    }
    if (opening == null || instruction.isPrivate != opening.isPrivate) {
      throw const FormatException('Native gradient command has no matching beginning.');
    }
    switch (instruction.operator) {
      case 'Bg':
        if (geometry != null) {
          throw const FormatException('Native gradient has multiple geometry commands.');
        }
        geometry = AiNativeGradientGeometry._(instruction: instruction);
      case 'Bh':
        if (highlight != null || instruction.numbers?.length != 4) {
          throw const FormatException('Invalid native gradient highlight.');
        }
        highlight = instruction;
      case 'Xm' || 'Bm' || 'Bc':
        if (instruction.numbers?.length != 6) {
          throw const FormatException('Invalid native gradient imaging matrix.');
        }
        matrices.add(instruction);
      case 'BB':
        if (geometry == null || instruction.numbers?.length != 1 || !const {0, 1, 2}.contains(instruction.numbers!.single)) {
          throw const FormatException('Invalid native gradient ending.');
        }
        while (pathIndex < paths.length && paths[pathIndex].paint.start <= opening.end) {
          pathIndex++;
        }
        final List<AiNativePath> painted = [];
        while (pathIndex < paths.length && paths[pathIndex].paint.end < instruction.start) {
          final AiNativePath path = paths[pathIndex++];
          if (path.isPrivate != opening.isPrivate) {
            throw const FormatException('Native gradient mixes private and printable paths.');
          }
          painted.add(path);
        }
        gradients.add(
          AiNativeGradient._(
            opening: opening,
            geometry: geometry,
            highlight: highlight,
            imagingMatrices: matrices,
            closing: instruction,
            paths: painted,
          ),
        );
        opening = null;
        geometry = null;
        highlight = null;
        matrices.clear();
    }
  }
  if (opening != null) {
    throw const FormatException('Unterminated native gradient instance.');
  }
  return gradients;
}

/// Gradient commands supported by both legacy and CC instance layouts.
const Set<String> _gradientCommands = {'Bb', 'BB', 'Bg', 'Bh', 'Xm', 'Bm', 'Bc'};

/// Bounded incremental command reader shared by drawing and paint styles.
final class _NativeCommandReader {
  /// Maximum nesting of literal command operands.
  final int maxDepth;

  /// Operand tokens awaiting an executable name.
  final List<AiToken> _operands = [];

  /// Balanced array, dictionary and procedure delimiters.
  final List<AiTokenKind> _delimiters = [];

  /// Representation of the first operand, preventing mixed private commands.
  bool? _private;

  /// Creates a reader constrained by the owning program's resource policy.
  _NativeCommandReader({required this.maxDepth});

  /// Whether no incomplete operand list remains.
  bool get isEmpty => _operands.isEmpty && _delimiters.isEmpty;

  /// Consumes one token and returns a completed command when available.
  AiNativeInstruction? add(AiToken token, {required bool isPrivate}) {
    if (token.kind == .comment) {
      return null;
    }
    if (_private != null && _private != isPrivate) {
      throw const FormatException('Native command mixes printable and private operands.');
    }
    _private = isPrivate;
    if (const {AiTokenKind.arrayStart, AiTokenKind.dictionaryStart, AiTokenKind.procedureStart}.contains(token.kind)) {
      if (_delimiters.length >= maxDepth) {
        throw const FormatException('Native command operand nesting exceeds the limit.');
      }
      _delimiters.add(token.kind);
    } else if (const {AiTokenKind.arrayEnd, AiTokenKind.dictionaryEnd, AiTokenKind.procedureEnd}.contains(token.kind)) {
      final AiTokenKind expected = switch (token.kind) {
        AiTokenKind.arrayEnd => .arrayStart,
        AiTokenKind.dictionaryEnd => .dictionaryStart,
        _ => .procedureStart,
      };
      if (_delimiters.isEmpty || _delimiters.removeLast() != expected) {
        throw const FormatException('Unbalanced native command operands.');
      }
    }
    if (token.kind != .executableName || _delimiters.isNotEmpty) {
      _operands.add(token);
      return null;
    }
    final AiNativeInstruction command = AiNativeInstruction._(token: token, operands: _operands, isPrivate: isPrivate);
    _operands.clear();
    _private = null;
    return command;
  }

  /// Rejects truncated operand lists at a source boundary.
  void finish() {
    if (!isEmpty) {
      throw const FormatException('Unterminated native command operands.');
    }
  }
}

/// Reads isolated Bb/BB syntax, including swatches, patterns and private art.
///
/// Only complete gradient instances are interpreted. Procedures, embedded
/// documents, binary payloads and strings cannot supply executable references.
Iterable<AiNativeGradient> _readGradientInstances(AiNativeRecords records) sync* {
  final List<AiNativeInstruction> commands = [];
  final _NativeCommandReader reader = _NativeCommandReader(maxDepth: records.program.limits.maxDepth);
  int procedure = 0;
  int embedded = 0;
  AiToken? previous;
  int numericOperands = 0;
  for (final AiToken token in records._projection.tokens) {
    if (token.kind == .comment) {
      if (procedure == 0 && token.lexeme.startsWith('%%BeginDocument')) {
        embedded++;
        previous = null;
        numericOperands = 0;
      } else if (procedure == 0 && token.lexeme == '%%EndDocument') {
        embedded--;
      }
      if (embedded != 0 && commands.isNotEmpty) {
        throw UnsupportedError('Embedded artwork interrupts a native gradient instance.');
      }
      continue;
    }
    if (embedded != 0) {
      continue;
    }
    if (token.kind == .procedureStart) {
      procedure++;
      if (commands.isNotEmpty) {
        throw UnsupportedError('Executable procedures inside native gradients require host interpretation.');
      }
    } else if (token.kind == .procedureEnd) {
      procedure--;
    }
    if (procedure != 0) {
      continue;
    }
    if (commands.isEmpty) {
      if (token.kind == .executableName && token.lexeme == 'Bb') {
        if (numericOperands > 1) {
          throw const FormatException('Invalid native gradient selector operands.');
        }
        commands.add(AiNativeInstruction._(token: token, operands: [if (previous?.kind == .number) previous!], isPrivate: records._projection.isPrivate(token.start)));
      } else if (token.kind == .executableName && const {'Bg', 'Bm', 'Bc', 'Bh', 'Xm', 'BB'}.contains(token.lexeme)) {
        throw FormatException('Native gradient command has no matching beginning at ${token.start}.');
      }
    } else {
      final AiNativeInstruction? command = reader.add(token, isPrivate: records._projection.isPrivate(token.start));
      if (command != null && _gradientCommands.contains(command.operator)) {
        commands.add(command);
        if (command.operator == 'BB') {
          yield _readNativeGradients(instructions: commands, paths: []).single;
          commands.clear();
        }
      }
    }
    numericOperands = token.kind == .number ? numericOperands + 1 : 0;
    previous = token;
  }
  if (commands.isNotEmpty || embedded != 0 || procedure != 0) {
    throw const FormatException('Unterminated native gradient instance.');
  }
}
