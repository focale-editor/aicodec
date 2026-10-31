<p align="center">
  <img src="screenshots/overview.png" alt="AiKit package illustration" width="180">
</p>

# AiKit

AiKit reads and writes Adobe Illustrator containers in pure Dart. PdfCore handles
the PDF representation; ZCodec opens compressed native authoring programs.
Source-backed edits preserve unknown records, and typed artwork can be written
as self-contained AI7 PostScript.

## Supported data

- Signature-based detection of PDF and PostScript AI families.
- PDF pages, graphics streams, resources and metadata through PdfCore.
- Native Illustrator private-data blocks collected across pages in numeric order.
- Plain, zlib and Zstandard native programs, including recent CC files without
  usable PDF preview artwork.
- Native nested layers, names, visibility, locking and printing flags.
- Native hierarchical records, typed artboards and bounded ASCII85 resources.
- Source-preserving numeric/string record edits, including artboard renaming.
- Source-preserving layer edits and plain-path geometry replacement.
- CC live-shape associations and atomic translation of native outlines,
  solid/gradient appearances and parameters, including expanded strokes,
  shared style resources and versioned metadata.
- AI7 creation with editable layers, groups, Bézier paths, process colors,
  fills, strokes, dashes and winding rules.
- Exact preservation of legacy source bytes, binary blocks and DOS EPS previews.
- DSC titles, creators, bounding boxes, continuation lines and trailer metadata.
- PostScript numbers, names, strings, arrays, dictionaries, procedures and comments.
- Explicit PDF-interchange export that removes stale Illustrator authoring links.

## Installation

Use the GitHub repository and select PdfCore from its repository:

```yaml
dependencies:
  aikit:
    git: https://github.com/focale-editor/aikit

dependency_overrides:
  pdfcore:
    git: https://github.com/focale-editor/pdfcore
```

Zstandard uses the hosted ZCodec 0.2.6 release. PdfCore is not yet published
on pub.dev, so its Git dependency override is required. To develop AiKit itself,
clone PdfCore into a sibling `PdfCore` directory and copy
[`pubspec_overrides.yaml.example`](pubspec_overrides.yaml.example) to the ignored
`pubspec_overrides.yaml`, then run `dart pub get`.

## Quick start

```dart
import 'dart:convert';
import 'package:aikit/aikit.dart';

final AiDocument document = const AiCodec().decode(latin1.encode(
  '%!PS-Adobe-3.0\n%%Creator: Adobe Illustrator\n'
  '%%BoundingBox: 0 0 100 80\n%%EndComments\n0 0 m 100 80 l S\n%%EOF\n',
));
if (document is AiPostScriptDocument) {
  final List<AiToken> tokens = AiPostScript.tokenize(document.postScriptBytes);
  print('${document.creator}: ${tokens.length} tokens');
}
final AiNativeSource native = AiNativeData.extract(document).single;
final AiProgram program = AiProgram.decode(bytes: native.bytes);
print('${program.layers.length} native layers; ${program.paths.length} paths');
final List<int> preserved = const AiCodec().encode(document);
```

`AiCodec` implements `Codec<AiDocument, List<int>>`, with `AiDecoder` and
`AiEncoder` converters. Direct encoding returns `Uint8List`. See the runnable
[example](example/aikit_example.dart) for native artwork creation, layer editing
and explicit PDF interchange.

## Scope

AI is not one uniform format. A PDF page can be a compatibility warning rather
than the artwork; `AiNativeData.extract` accesses the native program separately.
`AiProgram` interprets a structural subset and reports unhandled operators and
private extensions. It does not execute arbitrary PostScript or provide a renderer.

Modern text/ATE records, plug-ins, effects, meshes, gradient and raster authoring
semantics are preserved but not fully modeled. Live rectangles, ellipses,
polygons, stars and lines support translation with solid and linear/radial
gradient appearances; resizing,
rotation and parameter-driven regeneration remain unfinished. Geometry edits
with unresolved private appearance dependencies are rejected. AI7 creation is an
explicit legacy target, not a reconstruction of CC editing records. Native and
PDF appearances must be synchronized by the caller when saving visual edits.
No Adobe Illustrator reopening validation has been performed.

See [docs/AI.md](docs/AI.md) for editing policies and
[test/corpus/README.md](test/corpus/README.md) for the external corpus. AiKit is an
independent implementation and is not affiliated with or endorsed by Adobe.

## More documentation

- [Illustrator container reference](docs/AI.md)
- [Inspection and PDF interchange example](example/aikit_example.dart)
- [External corpus and validation scope](test/corpus/README.md)
- [Contributing](CONTRIBUTING.md)

## Development

```sh
cp pubspec_overrides.yaml.example pubspec_overrides.yaml
dart pub get
dart format --output=none --set-exit-if-changed .
dart analyze
dart test
dart test --platform node
```

The optional corpus checks extraction, layer renaming and native recompression
on 27 pinned files. Independent zlib/Zstandard decoding checks the resulting
bytes. Eight fixtures also check live-shape translations against a pinned
independent reader and renderer. These checks do not establish complete native
Illustrator compatibility.

---

Built for **[Focale](https://focale-editor.app)**, an advanced local image editor. Discover what these packages make possible in a real creative workflow.
