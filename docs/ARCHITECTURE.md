# SourceLeaf architecture

SourceLeaf separates deterministic, testable editing rules from the native macOS interface.

## Modules

- `SourceLeafCore`: project discovery, source targets, validation, compilation, persistence, prompts, process execution, and AI providers.
- `SourceLeafApp`: SwiftUI workspace and settings, AppKit/TextKit source editor, PDFKit preview, and user approval flow.

## AI edit contract

1. A source selection or explicit line reference becomes a `SourceTarget` with a path, UTF-16 range, line range, original text, and SHA-256 hash.
2. The context builder separately assembles read-only selection, nearby, section, document, or project context.
3. Providers receive a prompt that labels writable targets and read-only context. They must return the SourceLeaf JSON proposal shape.
4. Returned target IDs are checked against the request. Each replacement is statically inspected for braces, environments, citations, references, and labels.
5. The UI shows a diff. On acceptance, SourceLeaf checks the original target hash again and refuses to overwrite stale text.

Local Codex does not run inside the paper project. It runs from an empty per-project directory in Application Support, uses the existing Codex CLI authentication and configuration, receives its prompt through standard input, and is restricted to read-only/ephemeral execution.

## Storage

- Project source: original project folder.
- Per-project configuration, chat, and AI history: `~/Library/Application Support/SourceLeaf/Projects/<hash>/`.
- Provider workspaces and optional managed engines: `~/Library/Application Support/SourceLeaf/`.
- Generated PDFs and logs: `~/Library/Caches/SourceLeaf/Build/<hash>/`.
- API credentials: macOS Keychain.

No SourceLeaf metadata is added to the paper project unless a future shared-project configuration is explicitly enabled.

## SyncTeX navigation

SourceLeaf parses the compressed SyncTeX index emitted by Tectonic or `latexmk` without requiring a separately installed `synctex` executable. Input tags retain the absolute owning `.tex` path. Forward search maps the active source line to a PDF page and scaled-point coordinate; reverse search maps a command-clicked PDF coordinate to the nearest source record, then validates that the resulting path belongs to the open project before opening it. PDF highlights are in-memory annotations and never modify the generated PDF on disk.
