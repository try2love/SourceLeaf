<h1 align="center">SourceLeaf</h1>

<p align="center">
  A native macOS workspace for writing LaTeX, reviewing PDFs, and applying AI-assisted revisions under explicit user control.
</p>

<p align="center">
  <strong>English</strong> · <a href="README.zh-CN.md">简体中文</a>
</p>

<p align="center">
  <a href="https://swift.org"><img alt="Swift 6" src="https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white"></a>
  <img alt="macOS 14+" src="https://img.shields.io/badge/macOS-14%2B-0A84FF?logo=apple&logoColor=white">
  <img alt="Universal" src="https://img.shields.io/badge/Universal-arm64%20%7C%20x86__64-555555">
  <a href="https://github.com/try2love/SourceLeaf/releases"><img alt="Version 0.3.25" src="https://img.shields.io/badge/version-0.3.25-2ea44f"></a>
  <a href="LICENSE"><img alt="PolyForm Noncommercial 1.0.0" src="https://img.shields.io/badge/license-PolyForm%20Noncommercial-blueviolet"></a>
</p>

<p align="center">
  <a href="#why-sourceleaf">Why SourceLeaf</a> ·
  <a href="#features">Features</a> ·
  <a href="#installation">Installation</a> ·
  <a href="#quick-start">Quick Start</a> ·
  <a href="#controlled-ai-workflow">AI Workflow</a> ·
  <a href="#architecture">Architecture</a> ·
  <a href="#development">Development</a>
</p>

SourceLeaf brings the core academic writing loop into one native workspace: edit LaTeX, inspect the compiled PDF, navigate with SyncTeX, and ask a local Codex CLI or configured API provider for revisions. AI output remains a proposal until the user reviews a visible diff and explicitly accepts it.

> [!IMPORTANT]
> SourceLeaf is currently a product-tested preview for macOS 14 and newer. It is source-available for noncommercial use and is not yet distributed through the Mac App Store or as a notarized binary release.

## Why SourceLeaf

Most AI writing integrations either receive too much project access or return text that must be copied back manually. SourceLeaf uses a narrower contract:

- the writable target is an explicit selection, line range, or confirmed SyncTeX mapping;
- additional chapter, document, or project context is read-only;
- every proposal is statically inspected and shown as a diff;
- candidate LaTeX is trial-compiled in an isolated project copy before acceptance;
- stale targets are rejected instead of silently overwriting newer edits.

The rest of the application follows the same local-first boundary. Project metadata stays outside the paper folder, API keys stay in macOS Keychain, and the local Codex provider reuses the Codex CLI already installed and signed in on the Mac.

## Features

### LaTeX workspace

- **Native source editor** with Overleaf-style semantic colors, native live selections, stable rapid typing and caret ownership, fixed line numbers, line wrapping, opaque system Find/Replace, light/dark/system themes, and persistent font preferences.
- **Project navigation** with full-row folder disclosure, dedicated multipage project-PDF routing, centered and pannable image preview, and a recursively collapsible document outline that jumps to the owning source location.
- **LaTeX editing tools** with Find/Replace, toggleable styles, common shortcuts, heading levels, font sizes, formulas, tables, figures, lists, citations, references, labels, and URLs.
- **Explicit saving** with dirty-state feedback, toolbar actions, and `⌘S`.

### Compilation and PDF

- **Managed Tectonic 0.16.9** bundled by the installer for both Apple Silicon and Intel Macs.
- **External toolchain support** for `latexmk` and broader TeX Live compatibility.
- **Fast unchanged-project reuse**, automatic restoration of the last successful PDF after relaunch, live compilation phases, structured build-log summaries, and manual cache cleanup.
- **Forward and reverse SyncTeX** between source lines and PDF positions without modifying the generated PDF.
- **Continuous vertical PDF reading** with thumbnails, 0.1×–8× zoom, Control-wheel zoom, compact navigation, auto-build control, and Save PDF As; image previews use the same zoom range.

### Reviewable AI assistance

- **Local Codex CLI first**: reuse the Mac's existing Codex login and configuration without copying `auth.json`.
- **Configurable providers**: local Codex, restricted headless CodeBuddy, and HTTP API profiles with model and supported reasoning controls.
- **Verifiable connectivity**: an explicit `hello` health check drives the unknown/checking/connected/failed status indicator.
- **Selectable context scope**: none, selection only, nearby text, section, full document, project, or custom files; no-target requests use a normal plain-text conversation protocol.
- **Diff before write**: inspect warnings and original/proposed text before accepting or rejecting a change.
- **Prompt library**: a compact Quick Prompt menu plus built-in and user-managed prompts; long bilingual templates use a full-height language-focused editor.
- **Conversation sessions** with create, rename, switch, editable/copyable timestamped messages, message-specific regenerate/stop controls, configurable send keys, a user-defined system prompt, and a collapsible real provider-activity stream.
- **History through review**: accepted diffs remain visible without action buttons, and restoring an earlier change returns through a full original/updated diff workflow instead of overwriting source silently.

### Flexible native interface

- Source, PDF, conversation, project navigation, and logs can be shown, hidden, rearranged, docked, or detached.
- The conversation composer can be resized vertically and remembers its height.
- Interface text size continuously scales actual semantic UI fonts independently from the source editor font, including layouts used on external displays.
- Main dock dividers provide a wider drag target, and clickable controls expose localized hover help including state where applicable.
- Detached panels return to the main workspace when their windows close.
- Interface language can switch immediately between English, Simplified Chinese, and Follow System.
- The most recent project and source file reopen automatically.

## Installation

### Requirements

- macOS 14 Sonoma or newer
- Xcode 16 or newer, including the command-line tools
- Internet access on the first installation to download the pinned Tectonic binaries
- Optional: [Codex CLI](https://github.com/openai/codex) for the local Codex provider
- Optional: [CodeBuddy CLI](https://www.codebuddy.ai/docs/cli/overview) for the restricted local CodeBuddy provider
- Optional: MacTeX, TinyTeX, or another `latexmk` toolchain for packages outside Tectonic's compatibility envelope

### Build and install

```bash
git clone https://github.com/try2love/SourceLeaf.git
cd SourceLeaf
scripts/install.sh
```

The installer:

1. downloads the official Tectonic 0.16.9 binaries for `arm64` and `x86_64`;
2. verifies their pinned SHA-256 checksums;
3. builds and ad-hoc signs a Universal SourceLeaf application;
4. installs it to `~/Applications/SourceLeaf.app`;
5. preserves the previous installation under the categorized `临时文件/安装备份` directory.

Open the installed application with:

```bash
open "$HOME/Applications/SourceLeaf.app"
```

Build downloads and intermediate artifacts remain under the repository's ignored `临时文件` directory. They are not added to LaTeX projects or Git commits.

## Quick Start

1. Launch SourceLeaf and choose a LaTeX project folder.
2. Open the main `.tex` file and compile it with the toolbar button.
3. Arrange the source, PDF, project, and conversation panels for the current task.
4. Select source text, reference an explicit line range, or use a confirmed PDF-to-source mapping.
5. Attach the target to the conversation, choose a context scope, and describe the desired revision.
6. Review the warnings, trial-build result, and diff; then accept, reject, or continue refining.

For ordinary LaTeX editing, the conversation panel and selection action can remain closed. The floating selection button can also be disabled in Settings.

## Controlled AI Workflow

```text
Explicit source target
        ↓
Read-only context scope
        ↓
Provider proposal
        ↓
Target and LaTeX validation
        ↓
Isolated trial compilation
        ↓
Visible diff and user decision
        ↓
Atomic write or rejection
```

SourceLeaf records the target's original text and hash. If the source changes while a proposal is being generated, acceptance is refused and the user must create a fresh target.

Local Codex runs from a source-free workspace in Application Support with ephemeral, read-only execution. CodeBuddy also runs headlessly from a source-free workspace with file, command, search, and web tools disabled. HTTP providers receive only the assembled target and selected context and have no filesystem or tool access through SourceLeaf.

## Data and Privacy

| Data | Default location |
| --- | --- |
| LaTeX source and assets | Original project folder |
| Per-project state, chat, history, provider workspaces | `~/Library/Application Support/SourceLeaf/` |
| Generated PDFs, logs, and disposable build output | `~/Library/Caches/SourceLeaf/` |
| API credentials | macOS Keychain |

SourceLeaf does not add metadata to the paper project. Development and tests can isolate application data with:

```bash
SOURCELEAF_SUPPORT_DIRECTORY="$PWD/临时文件/开发/ApplicationSupport" \
SOURCELEAF_CACHE_DIRECTORY="$PWD/临时文件/开发/Caches" \
swift run SourceLeaf
```

## Architecture

SourceLeaf separates deterministic editing and compilation rules from the native interface:

```text
Sources/
├── SourceLeafCore/       # project indexing, targets, validation, providers,
│                        # compilation, SyncTeX, persistence, and prompts
└── SourceLeafApp/        # SwiftUI workspace and settings, AppKit/TextKit editor,
                         # PDFKit preview, conversation, and approval flow

Tests/
├── SourceLeafCoreTests/  # deterministic unit and real-project checks
└── SourceLeafAppTests/   # AppKit, PDFKit, behavior, boundary, and visual checks
```

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the source-target contract, storage boundaries, and SyncTeX design.

## Development

Run the complete test suite:

```bash
swift test
```

Run the application from SwiftPM:

```bash
swift run SourceLeaf
```

Build a local Universal application bundle:

```bash
scripts/build-app-bundle.sh
```

Useful build overrides include `SOURCELEAF_TEMP_ROOT`, `SOURCELEAF_APP_OUTPUT`, `SOURCELEAF_INSTALL_ROOT`, `SOURCELEAF_ARCHS`, and `SOURCELEAF_SKIP_MANAGED_ENGINE=1`.

## Current Limitations

- SourceLeaf is macOS-only and depends on SwiftUI, AppKit/TextKit, PDFKit, and Quick Look.
- The current distribution path is a source-based installer with ad-hoc signing; notarized downloads are not published yet.
- Tectonic covers the default installation path, but some projects still require a full TeX Live/`latexmk` toolchain.
- Arbitrary custom CLI profiles remain disabled until a safe command contract is implemented. WorkBuddy is not advertised as supported because its public product documentation does not currently expose a verifiable headless CLI or API contract.
- Cloud sync, shared editing, and multi-user collaboration are outside the current scope.

## Contributing

Contributions are welcome when they remain compatible with the project's noncommercial license and local-first safety boundary. Please read [CONTRIBUTING.md](CONTRIBUTING.md), sign commits with the [Developer Certificate of Origin](DCO.txt), and run:

```bash
swift test
swift build -c release
```

Do not commit API keys, personal paths, paper content, chat histories, or generated build artifacts.

## License

SourceLeaf is **source-available for noncommercial use** under the [PolyForm Noncommercial License 1.0.0](LICENSE). Commercial use is not granted.

Third-party components and optional external tools remain under their respective licenses. See [THIRD_PARTY_LICENSES.md](THIRD_PARTY_LICENSES.md) and [NOTICE](NOTICE).

SourceLeaf is an independent project and is not affiliated with or endorsed by OpenAI, Apple, the Tectonic project, or the developers of Texifier.
