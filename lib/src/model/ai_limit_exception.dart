/// Reports an inspection stopped by a resource ceiling, not malformed syntax.
final class AiLimitException extends FormatException {
  /// Creates a bounded-processing diagnostic at an optional source byte.
  const AiLimitException({required String message, int? offset}) : super(message, null, offset);
}
