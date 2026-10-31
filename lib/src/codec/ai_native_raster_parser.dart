part of 'package:aikit/src/model/ai_native_records.dart';

/// Associates each raster section with one explicit XI command and opaque body.
List<AiNativeRaster> _readNativeRasters(AiNativeRecords records, bool bodyOnly) {
  final List<AiNativeRaster> images = [];
  final _NativeRecordProjection projection = records._projection;
  final _NativeCommandReader reader = _NativeCommandReader(maxDepth: records.program.limits.maxDepth);
  final List<AiNativeInstruction> commands = [];
  AiToken? opening;
  AiToken? data;
  int procedures = 0;
  int embedded = 0;
  for (final AiToken token in projection.tokens) {
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
      commands.clear();
    } else if (token.kind == .comment && token.lexeme == '%AI5_EndRaster') {
      if (opening == null) {
        throw const FormatException('Unmatched Illustrator raster end.');
      }
      reader.finish();
      final List<AiNativeInstruction> operators = commands.where((command) => command.operator == 'XI').toList();
      if (operators.length != 1 || data == null || data.start < operators.single.end || !const {20, 23, 24}.contains(operators.single.operands.length)) {
        throw UnsupportedError('Native raster decoding requires one binary XI image.');
      }
      images.add(
        AiNativeRaster._(
          start: opening.start,
          end: token.end,
          instruction: operators.single,
          commands: commands,
          data: data,
          samples: Uint8List.sublistView(records.program.bytes, data.start, data.end),
        ),
      );
      opening = null;
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
