part of 'package:aicodec/src/model/ai_native_records.dart';

/// Reads saved stroke options while keeping absent and future fields distinct.
AiNativeStrokeSettings? _nativeAppearanceStrokeSettings(AiNativeContainer? parameters) {
  final AiNativeEntry? field = parameters?['kAIBeautifulStrokesParamsDictKey'];
  if (field == null) {
    return null;
  }
  if (field.type != null || field.container?.type != 'Dictionary') {
    throw const FormatException('Advanced stroke settings require one owned dictionary.');
  }
  final AiNativeContainer record = field.container!;
  final AiNativeEntry? version = record['BSAdvStrokeDictionaryVersion'];
  final double? number = version?.number;
  if (version != null && (version.type != 'Int' || number == null || number < 0 || number > 9007199254740991 || number != number.truncateToDouble())) {
    throw const FormatException('Advanced stroke settings require a portable integer version.');
  }
  return AiNativeStrokeSettings._(record: record, version: number?.toInt(), adjustDashes: _nativeAppearanceBoolean(record, 'BSDashAdj'));
}

/// Qualifies the observed version-one scalar layout without executing its effect.
void _nativeAppearanceStrokeDictionary(AiNativeEntry field) {
  final AiNativeContainer record = _referenceRecord(field, 'Dictionary');
  _referenceFields(record, {
    'Int': {'BSAdvStrokeDictionaryVersion'},
    'Bool': {'BSDashAdj'},
  }, notRecorded: true);
  if (record['BSAdvStrokeDictionaryVersion']?.number != 1 || !const {0, 1}.contains(record['BSDashAdj']?.number)) {
    throw UnsupportedError('Advanced stroke editing requires version one and an explicit dash-adjustment flag.');
  }
}
