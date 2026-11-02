part of 'package:aikit/src/model/ai_native_records.dart';

/// Associates each raster section with one explicit XI command and opaque body.
List<AiNativeRaster> _readNativeRasters(AiNativeRecords records, bool bodyOnly, {int? start, int? end}) {
  final List<AiNativeRaster> images = [];
  final _NativeRecordProjection projection = records._projection;
  final _NativeCommandReader reader = _NativeCommandReader(maxDepth: records.program.limits.maxDepth);
  final List<AiNativeInstruction> commands = [];
  final Map<int, AiNativeContainer> dictionaries = {
    for (final AiNativeContainer container in records.containers)
      if (container.type == 'ArtDictionary') container.start: container,
  };
  AiToken? opening;
  AiToken? data;
  AiToken? declaration;
  int procedures = 0;
  int embedded = 0;
  for (final (int, AiToken) item in projection.tokens.indexed) {
    final AiToken token = item.$2;
    if (start != null && token.start < start || end != null && token.start >= end) {
      continue;
    }
    if (bodyOnly && (token.start < records.program.bodyStart || token.start >= records.program.bodyEnd)) {
      continue;
    }
    if (token.kind == .procedureStart) {
      procedures++;
    } else if (token.kind == .procedureEnd) {
      procedures--;
    } else if (token.kind == .comment && token.lexeme.startsWith('%%BeginDocument')) {
      embedded++;
    } else if (token.kind == .comment && token.lexeme == '%%EndDocument') {
      embedded--;
    }
    if (procedures != 0 || embedded != 0) {
      continue;
    }
    if (token.kind == .comment && token.lexeme == '%AI5_BeginRaster') {
      if (opening != null) {
        throw const FormatException('Nested Illustrator raster section.');
      }
      opening = token;
      data = null;
      declaration = null;
      commands.clear();
    } else if (token.kind == .comment && token.lexeme == '%AI5_EndRaster') {
      if (opening == null) {
        throw const FormatException('Unmatched Illustrator raster end.');
      }
      reader.finish();
      final List<AiNativeInstruction> operators = commands.where((command) => command.operator == 'XI').toList();
      if (operators.length != 1 ||
          data == null ||
          declaration == null ||
          declaration.end >= operators.single.token.start ||
          data.start < operators.single.end ||
          !const {20, 23, 24}.contains(operators.single.operands.length)) {
        throw UnsupportedError('Native raster decoding requires one binary XI image.');
      }
      images.add(
        AiNativeRaster._(
          start: opening.start,
          end: token.end,
          instruction: operators.single,
          commands: commands,
          data: data,
          declaration: declaration,
          dictionary: _attachedArtDictionary(projection, item.$1 + 1, dictionaries, operators.single.isPrivate),
          samples: Uint8List.sublistView(records.program.bytes, data.start, data.end),
        ),
      );
      opening = null;
    } else if (opening != null && token.kind == .comment && token.lexeme.startsWith('%%BeginData:')) {
      if (declaration != null) {
        throw const FormatException('Repeated native raster data declaration.');
      }
      declaration = token;
    } else if (opening != null && token.kind == .data) {
      if (data != null || commands.lastOrNull?.operator != 'XI') {
        throw const FormatException('Unexpected native raster data block.');
      }
      data = token;
    } else if (opening != null && token.kind != .comment) {
      final AiNativeInstruction? command;
      try {
        // The binary invocation inherits its header's private representation.
        command = reader.add(token, isPrivate: token.kind == .executableName && token.lexeme == 'XI' ? reader._private ?? projection.isPrivate(token.start) : projection.isPrivate(token.start));
      } on FormatException catch (error) {
        throw FormatException(error.message, null, token.start);
      }
      if (command != null) {
        commands.add(command);
      }
    }
  }
  if (opening != null) {
    throw const FormatException('Unterminated Illustrator raster section.');
  }
  return images;
}

/// Attaches only the immediately following dictionary, optionally after bare N.
AiNativeContainer? _attachedArtDictionary(_NativeRecordProjection projection, int position, Map<int, AiNativeContainer> dictionaries, bool private) {
  bool consumed = false;
  for (int index = position; index < projection.tokens.length; index++) {
    final AiToken token = projection.tokens[index];
    if (token.kind == .comment) {
      if (token.lexeme.startsWith('%%') || token.lexeme.startsWith('%AI')) {
        return null;
      }
      continue;
    }
    if (!consumed && token.kind == .executableName && token.lexeme == 'N' && projection.isPrivate(token.start) == private) {
      consumed = true;
      continue;
    }
    return dictionaries[token.start];
  }
  return null;
}
