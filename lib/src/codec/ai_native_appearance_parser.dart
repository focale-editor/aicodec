part of 'package:aikit/src/model/ai_native_records.dart';

/// Reads known literal fields while preserving unknown appearance extensions.
AiNativeAppearances _nativeAppearances(AiNativeStructure structure) {
  final AiNativeRecords records = structure.drawing.records;
  final List<AiNativeResourceUse> uses = structure.resourceUses.where((use) => use.kind == .knownStyle).toList();
  final Map<AiNativeStructureResource, List<AiNativeResourceUse>> references = {};
  for (final AiNativeResourceUse use in uses) {
    for (final AiNativeStructureResource candidate in use.candidates) {
      (references[candidate] ??= []).add(use);
    }
  }
  final List<AiNativeAppearance> styles = [];
  for (final AiNativeStructureResource resource in structure.resources.where((resource) => resource.kind == .knownStyle)) {
    final AiNativeContainer owner = resource.definition.source as AiNativeContainer;
    final AiNativeContainer? definition = owner['Def']?.container;
    if (definition == null) {
      throw const FormatException('A named appearance requires one owned definition.');
    }
    final List<AiNativeAppearancePart?> parts = [];
    if (definition.type == 'ActiveStyle') {
      final AiNativeContainer? execution = definition['Execution']?.container;
      if (execution == null) {
        throw const FormatException('An active appearance requires one execution owner.');
      }
      _nativeAppearancePart(records, execution, null, parts);
    }
    styles.add(
      AiNativeAppearance._(
        resource: resource,
        definition: definition,
        parts: parts.cast<AiNativeAppearancePart>().toList(),
        simplePaint: definition.type == 'SimpleStyle' ? AiNativePaintStyle.decode(records: records, record: definition) : null,
        uses: references[resource] ?? [],
      ),
    );
  }
  return AiNativeAppearances._(structure: structure, styles: styles, uses: uses);
}

/// Requires literal bounded integers without coercing floating-point descriptors.
int _nativeAppearanceInteger(AiNativeEntry entry, {required int maximum}) {
  final double? value = entry.number;
  if (entry.type != null || value == null || value < 0 || value > maximum || value != value.truncateToDouble()) {
    throw const FormatException('Invalid native appearance integer field.');
  }
  return value.toInt();
}

/// Reads a native Boolean parameter without inventing a value for absent fields.
bool? _nativeAppearanceBoolean(AiNativeContainer? owner, String key) {
  final AiNativeEntry? field = owner?[key];
  if (field == null) {
    return null;
  }
  if (field.type != 'Bool' || !const {0, 1}.contains(field.number)) {
    throw const FormatException('Invalid native appearance Boolean parameter.');
  }
  return field.number == 1;
}

/// Preserves literal descriptor flags, including future flag values.
AiNativeAppearanceFilter? _nativeAppearanceFilter(AiNativeContainer record) {
  final AiNativeEntry? field = record['Filter'];
  if (field == null) {
    return null;
  }
  final List<AiNativeItem> values = field.items;
  if (field.type != null ||
      values.length != 3 ||
      values.any((value) => value is! AiNativeToken) ||
      !const {AiTokenKind.string, AiTokenKind.hexString}.contains((values.first as AiNativeToken).token.kind)) {
    throw const FormatException('Invalid native appearance filter descriptor.');
  }
  final List<int> flags = [];
  for (final AiNativeToken value in values.skip(1).cast<AiNativeToken>()) {
    final num? number = value.token.number;
    if (number == null || number < 0 || number > 9007199254740991 || number != number.truncateToDouble()) {
      throw const FormatException('Invalid native appearance descriptor flag.');
    }
    flags.add(number.toInt());
  }
  return AiNativeAppearanceFilter._(field: field, flags: flags, nameBytes: aiStringBytes((values.first as AiNativeToken).token));
}

/// Binds known roles to their complete descriptor, retaining other nodes as opaque.
AiNativeAppearancePartKind _nativeAppearanceKind(AiNativeContainer record, AiNativeAppearanceFilter? filter) {
  if (filter == null || filter.flags.last != 0 || (filter.flags.first == 0 && record['PluginFileName'] != null)) {
    return .opaque;
  }
  final String name = latin1.decode(filter.nameBytes);
  if (record.type == 'CompoundFilter' && filter.flags.first == 0) {
    return switch (name) {
      'Stack Style Filter' => .stack,
      'Chain Style Filter' => .chain,
      _ => .opaque,
    };
  }
  if (record.type != 'BasicFilter') {
    return .opaque;
  }
  if (filter.flags.first == 1) {
    if (name == 'Adobe Calligraphic Brush Tool' && const {'Illustrator.exe', 'CalligraphicBrushTool.aip'}.contains(record['PluginFileName']?.text())) {
      return .calligraphic;
    }
    return name == 'Adobe Stroke Offset' && const {'Illustrator.exe', 'StrokeOffset.aip'}.contains(record['PluginFileName']?.text()) ? .strokeOffset : .effect;
  }
  if (filter.flags.first != 0) {
    return .opaque;
  }
  return switch (name) {
    'Fill Style Filter' => .fill,
    'Stroke Style Filter' => .stroke,
    'Blend Style Filter' => .blend,
    'Conduit Filter' => .conduit,
    _ => .opaque,
  };
}

/// Visits only explicitly owned Part fields within the original depth/node limits.
int _nativeAppearancePart(AiNativeRecords records, AiNativeContainer record, int? parent, List<AiNativeAppearancePart?> parts) {
  if (parts.length >= records.program.limits.maxTokens) {
    throw const AiLimitException(message: 'Native appearance parts exceed the inspection limit.');
  }
  final bool filterRecord = const {'CompoundFilter', 'BasicFilter'}.contains(record.type);
  final AiNativeAppearanceFilter? filter = filterRecord ? _nativeAppearanceFilter(record) : null;
  final AiNativeAppearancePartKind kind = _nativeAppearanceKind(record, filter);
  final AiNativeEntry? visible = filterRecord ? record['Visible'] : null;
  final AiNativeEntry? selector = filterRecord ? record['FillOrStroke'] : null;
  final AiNativeEntry? parameters = filterRecord ? record['Dict'] : null;
  if (parameters != null && (parameters.type != null || parameters.container?.type != 'Dictionary')) {
    throw const FormatException('An appearance parameter field requires an owned dictionary.');
  }
  final AiNativeContainer? dictionary = parameters?.container;
  final List<AiNativeAppearancePaint> paints = [
    for (final AiNativeEntry field in dictionary?.entries ?? <AiNativeEntry>[])
      if (field.container case final AiNativeContainer paint when const {'FillStyle', 'StrokeStyle', 'BlendStyle'}.contains(paint.type))
        AiNativeAppearancePaint._(
          field: field,
          style: AiNativePaintStyle.decode(records: records, record: paint),
        ),
  ];
  final bool? inside = kind == .strokeOffset ? _nativeAppearanceBoolean(dictionary, 'StrokeOffsetInside') : null;
  final int index = parts.length;
  final List<int> children = [];
  parts.add(null);
  if (record.type == 'CompoundFilter') {
    for (final AiNativeEntry field in record.values('Part')) {
      final AiNativeContainer? child = field.container;
      if (field.type != null || child == null) {
        throw const FormatException('An appearance part requires one owned filter record.');
      }
      children.add(_nativeAppearancePart(records, child, index, parts));
    }
  }
  parts[index] = AiNativeAppearancePart._(
    index: index,
    parentIndex: parent,
    childIndices: children,
    record: record,
    kind: kind,
    filter: filter,
    visible: visible == null ? null : _nativeAppearanceInteger(visible, maximum: 1) == 1,
    fillOrStroke: selector == null ? null : _nativeAppearanceInteger(selector, maximum: 9007199254740991),
    parameters: dictionary,
    paints: paints,
    evenOdd: kind == .fill ? _nativeAppearanceBoolean(dictionary, 'UseEvenOdd') : null,
    strokeSettings: const {AiNativeAppearancePartKind.stroke, AiNativeAppearancePartKind.strokeOffset}.contains(kind) ? _nativeAppearanceStrokeSettings(dictionary) : null,
    strokeAlignment: kind == .stroke && dictionary?['StrokeOffsetInside'] == null
        ? .center
        : inside == null
        ? null
        : inside
        ? .inside
        : .outside,
  );
  return index;
}
