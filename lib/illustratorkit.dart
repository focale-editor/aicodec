/// Portable Adobe Illustrator containers and preserved authoring data.
library;

export 'package:illustratorkit/src/codec/ai_codec.dart';
export 'package:illustratorkit/src/codec/ai_native_data.dart';
export 'package:illustratorkit/src/codec/ai_postscript.dart' show AiPostScript, AiToken, AiTokenKind;
export 'package:illustratorkit/src/model/ai_artwork.dart';
export 'package:illustratorkit/src/model/ai_document.dart';
export 'package:illustratorkit/src/model/ai_host_snapshot.dart';
export 'package:illustratorkit/src/model/ai_limit_exception.dart';
export 'package:illustratorkit/src/model/ai_native_capabilities.dart';
export 'package:illustratorkit/src/model/ai_native_records.dart' hide validateTextAppearanceParent, validateTextLifecycleSource;
export 'package:illustratorkit/src/model/ai_native_text.dart' hide validateTextArtworkReferences;
export 'package:illustratorkit/src/model/ai_program.dart';
export 'package:illustratorkit/src/model/ai_xmp_metadata.dart';
export 'package:pdfcore/pdfcore.dart';
export 'package:pscore/pscore.dart'
    show PsEngineArray, PsEngineBoolean, PsEngineCodec, PsEngineDictionary, PsEngineDocument, PsEngineLimits, PsEngineName, PsEngineNull, PsEngineNumber, PsEngineString, PsEngineToken, PsEngineValue;
