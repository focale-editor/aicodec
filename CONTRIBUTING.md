# Contributing to AiKit

Thanks for helping improve AiKit. Bug reports, focused fixes, documentation improvements, and well-scoped features are welcome.

## Before you start

- Search [existing issues](https://github.com/focale-editor/aikit/issues) before opening a new one.
- Include a minimal reproduction, the Dart SDK version, and the Illustrator version and PDF-compatibility setting involved.
- Share sample files only when their license and contents permit it. Do not include secrets, private artwork, or personal data in a public report.

## Development setup

Use a Dart SDK compatible with [`pubspec.yaml`](pubspec.yaml). Fork the repository, then run:

```sh
git clone https://github.com/YOUR_ACCOUNT/aikit.git
cd aikit
dart pub get
```

Create a focused branch from `main`:

```sh
git switch main
git pull --ff-only
git switch -c fix/short-description
```

PdfCore and the other runtime dependencies resolve from pub.dev. The checkout
does not require a dependency override or sibling directory.

Follow [`AGENTS.md`](AGENTS.md) and keep each change focused on one fix or feature.

## Making changes

- Keep each pull request focused on one fix or feature.
- Do not bump the package version or edit the changelog unless a maintainer asks you to.
- Keep format models independent of Flutter, native libraries, and Focale. Native authoring records belong in AiKit; rendering and synchronization with the host's scene belong to the application adapter.
- Document public and private APIs, preserve caller-owned values, and add regression tests for parser, editing or writer changes.
- Base compatibility changes on specifications and real files. Preserve opaque data when safe; reject transformations that would silently lose unsupported content.
- Update the [technical reference](docs/AI.md), examples, and README when support or public behavior changes.

Keep legacy PostScript byte preservation separate from PDF interchange edits. Never execute PostScript. Preserve private blocks when the graph is coherent, and remove stale native authoring links for explicit PDF interchange. QPDF/Poppler checks do not establish native Illustrator reopening or editability.

External corpora stay outside the published package and Git history. Pin source revisions, sizes, SHA-256 values, and provenance in the manifest. Do not assume that a repository's code license covers every embedded artwork.

## Quality checks

Before opening a pull request, run:

```sh
dart format --output=none --set-exit-if-changed .
dart analyze
dart test
dart test --platform node
```

Add the relevant [corpus checks](test/corpus/README.md) for format changes. A decode/write/read test alone is not independent interoperability evidence. State the external tool versions and untested features. Ordinary unit tests run offline; corpus downloading is explicit.

The package illustration is maintained as `screenshots/overview.svg`. After changing it, regenerate the README and pub.dev PNG with librsvg:

```sh
rsvg-convert -w 512 -h 512 -o screenshots/overview.png screenshots/overview.svg
```

## Local configuration and publication

The local `.env` uses `GITHUB_PAT` for the release tooling. Keep its value local;
`.gitignore` and `.pubignore` exclude environment files and dependency overrides.
Ordinary analysis and tests do not require release credentials.

The package archive retains the library, examples, illustration, and applicable
license notices. Development documentation, tests, downloaded corpora, generated
validation output, and local configuration are excluded by `.pubignore`.

Run `dart pub publish --dry-run` from a clean checkout before a release to verify
the archive and hosted dependency constraints.

## Pull requests

Explain the problem and solution, link a related issue when applicable, and describe the checks and platforms exercised. Call out compatibility, performance, licensing, or migration implications. If a check cannot run in your environment, explain why.

Use Conventional Commits for commit messages and pull request titles, with a
capital after the scope and a final period, for example
`feat(text): Added native text feature editing.` Keep review follow-up changes on
the same branch. Routine validation does not include package publication or a
release-version change.
