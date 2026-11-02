<p align="center">
  <img src="screenshots/overview.png" alt="AiCodec package illustration" width="180">
</p>

# AiCodec

AiCodec is a pure Dart codec for reading, editing, and writing Adobe Illustrator documents.
It is intended for applications that need to work with Illustrator files
without launching Illustrator. It exposes native layers, paths, text, colors,
images and reusable artwork while preserving source data the application does
not change. Editing is available for the qualified structures described in the
[technical reference](docs/AI.md#supported-data).

It is written in pure Dart, with no Flutter or native rendering dependency.
PdfCore handles the PDF container, ZCodec handles native compression, and PsCore
supplies the Adobe text-engine grammar shared with PsdKit.

## Supported data

- PDF-backed Illustrator containers and legacy PostScript documents.
- Native programs with plain, zlib, or Zstandard envelopes and explicit ownership information.
- Qualified native layers, paths, text, colors, images, and reusable artwork.
- Immutable edits that preserve unrelated source records and reject unsupported dependent changes.
- New native CC documents with host-supplied printing data and compatibility PDF pages.
- Configurable byte, token, and depth limits; preserved data remains distinct from editable data.

## Installation

Add AiCodec to your Dart or Flutter project's `pubspec.yaml`:

```yaml
dependencies:
  aicodec: ^0.1.0
```

Run `dart pub get`, or `flutter pub get` for a Flutter project. Runtime
dependencies, including PdfCore, resolve from pub.dev.

## Reading and writing

Open a document, inspect its native programs, and save it again:

```dart
import 'dart:io';
import 'dart:typed_data';

import 'package:aicodec/aicodec.dart';

final Uint8List input = await File('input.ai').readAsBytes();
final AiDocument document = const AiCodec().decode(input);

for (final AiNativeSource source in AiNativeData.extract(document)) {
  final AiProgram program = AiProgram.decode(bytes: source.bytes);
  print('${program.layers.length} native layers; ${program.paths.length} paths');
  for (final AiLayer layer in program.layers) {
    print(layer.name);
  }
}

final Uint8List output = const AiCodec().encode(document);
await File('output.ai').writeAsBytes(output, flush: true);
```

A file may have several independent native programs, or none. PDF artwork alone
does not establish native editability. PDF-backed files are rewritten through
PdfCore; legacy PostScript documents retain their exact source bytes on encoding.

## Reusable `dart:convert` API

`AiCodec` implements `Codec<AiDocument, List<int>>` for one complete in-memory
document. Its binary type allows composition with standard codecs such as
`base64`, and direct `encode` calls return `Uint8List`. Decoding identifies the
container; writing follows the document model and its preservation contract.

## Common tasks

### Edit and save native content

Most editing helpers return a new immutable snapshot. Select objects from that
snapshot again after each edit; handles from an older program are not interchangeable.

The runnable [layer-renaming example](example/aicodec_example.dart) shows the full
read, edit, save and reopen sequence:

```sh
dart run example/aicodec_example.dart input.ai output.ai "Artwork"
```

A layer rename can retain the existing PDF appearance. For visual edits, the host
supplies matching printing data and a compatibility PDF through
`AiNativeData.replace` or its batch/page-mapping variants. See the
[save contract](docs/AI.md#saving-native-edits-with-host-supplied-representations).

### Work with Illustrator features

| Goal | API |
| --- | --- |
| Inspect native editability and preservation limits | `AiNativeCapabilityReport` |
| Edit layers, groups and object order | `AiNativeLayers` |
| Edit contours, transforms and live shapes | `AiNativeDrawing` |
| Read or edit text, styles and frames | `AiNativeTextDocument`, `AiNativeTextLifecycle` |
| Edit artboards and document settings | `AiNativeArtboards`, `AiNativeDocumentSettings` |
| Edit colors, gradients and palette cells | `AiNativeInks`, `AiNativeGradientResources`, `AiNativeSwatches` |
| Edit ordered appearances and opacity masks | `AiNativeAppearances`, `AiNativeOpacityMask` |
| Edit mesh vertices, handles, paints and topology | `AiNativeMeshes` |
| Read or replace embedded pixels and linked artwork | `AiNativeRasters`, `AiNativePlacements`, `AiNativeDrawing` |
| Author symbols, patterns and brushes | `AiNativeArtworkResources`, `AiNativeSymbols`, `AiNativeBrushes` |
| Edit qualified native effect parameters | `AiNativeEffect`, `AiNativeAppearances` |
| Inspect or update catalog metadata | `AiXmpMetadata` |

Each API has ownership and compatibility limits. The
[technical reference](docs/AI.md) explains the supported operations and the
representations the host must supply.

### Create a new document

`AiNativeDocument.create` builds a native CC document from explicit artboards,
layers and artwork. `AiNativeDocument.createPdf` packages it with the host's
matching PDF pages. No source AI or template is required.

The [new-document example](example/create_document.dart) creates and saves a
small document with native artwork and a separately supplied PDF appearance:

```sh
dart run example/create_document.dart output.ai
```

## Rendering expectations

AiCodec owns editable format data, preservation and serialization. The application
owns tools, glyph shaping, color management, mesh interpolation, effects and
rendering. Native authoring data, printable expansions and the compatibility PDF
must describe the same edited document revision.

A PDF page can contain a compatibility warning instead of the native artwork.
Inspect the native program separately rather than assuming the PDF is a faithful
preview. AiCodec does not render that program or compare the supplied representations.

Focale connects the qualified native workflows and can also retain host-only
effect controls beside developed AI/PDF artwork. Those controls are restored by
Focale, not exposed as equivalent Illustrator-native effects. See the
[Focale integration profile](docs/AI.md#focale-integration).

## Compatibility and limits

AI spans several container and authoring formats. AiCodec prioritizes native CC
data, with additional qualified CS and legacy inspection contracts. Unknown data
is preserved where safe; operations reject dependencies they cannot update
coherently. Preserving data does not make it semantically editable.

Parsing and output use explicit byte, token and depth limits. File access, linked
resource resolution and atomic persistence belong to the application. See the
[safety policies](docs/AI.md#safety-and-platform-behavior) for default ceilings.

Local regressions and independent corpus readers check qualified operations.
Actual Adobe Illustrator reopening, editing and repeated saves remain unverified.
AiCodec is an independent implementation and is not affiliated with or endorsed by
Adobe.

## More documentation

- [Illustrator technical reference](docs/AI.md)
- [Package and host responsibilities](docs/AI.md#package-and-host-responsibilities)
- [Layer editing example](example/aicodec_example.dart)
- [New-document example](example/create_document.dart)
- [External corpus and verification commands](test/corpus/README.md)
- [Contributing](CONTRIBUTING.md)

## Development

```sh
dart pub get
dart format --output=none --set-exit-if-changed .
dart analyze
dart test
dart test --platform node
```

The package uses published dependencies and does not require sibling checkouts
or dependency overrides.

---

Built for **[Focale](https://focale-editor.app)**, an advanced local image editor. Discover what these packages make possible in a real creative workflow.
