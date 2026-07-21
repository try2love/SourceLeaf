# SourceLeaf

SourceLeaf is a native macOS LaTeX workspace that keeps source editing, PDF preview, compilation, and AI-assisted revision in one user-controlled interface.

SourceLeaf 是一个原生 macOS LaTeX 工作区，将源码编辑、PDF 预览、编译和受控 AI 修改整合在同一个界面中。

## Design principles / 设计原则

- AI edits are suggestions until the user accepts a visible diff.
- An explicit source selection, line range, or confirmed SyncTeX mapping defines every writable target.
- Local Codex reuses the user's existing CLI login; API credentials stay in macOS Keychain.
- Project files stay clean: chats, layouts, indexes, histories, and build artifacts live in Application Support or caches.
- Panels can be opened, closed, rearranged, docked, or detached into separate windows.

## Requirements / 环境要求

- macOS 14 Sonoma or newer
- Xcode 16 or newer for source builds
- Optional: Codex CLI for the local Codex provider
- Optional: MacTeX/TinyTeX for full `latexmk` compatibility

## Build and install / 构建与安装

```bash
scripts/install.sh
```

The script builds a release app, verifies its signature, and installs it to `~/Applications/SourceLeaf.app` by default.

开发构建：

```bash
swift test
swift run SourceLeaf
```

## Current status / 当前状态

The current `0.1.0` build is a functional technical preview. Its central workflow is available now:

1. Open a LaTeX project folder and select text in a `.tex` file.
2. Attach that selection with the floating button, context command, or `⌥⌘K`.
3. Choose the readable context scope and send an instruction to local Codex or a configured API.
4. Review static LaTeX warnings and the original/proposed text side by side.
5. Accept, reject, or continue adjusting. Source is written only after acceptance, and stale targets are refused.

已经可用的核心流程是：打开 LaTeX 项目、选中源码、附加为严格可写目标、选择上下文范围、让本机 Codex 或 API 生成建议、审阅 Diff 后再决定是否写入。

Still in development: SyncTeX source/PDF navigation, trial compilation before accepting a proposal, one-click history restoration, managed Tectonic download UI, and the safety review for custom CLI providers. External `latexmk` or `tectonic` already works when installed.

仍在开发：SyncTeX 双向定位、接受前候选编译、历史一键恢复、受管理 Tectonic 下载界面，以及自定义 CLI 的安全校验。若系统已有 `latexmk` 或 `tectonic`，当前版本已经可以调用。

## Privacy boundary / 隐私边界

- Local Codex runs in a source-free app workspace with `--ephemeral --sandbox read-only`; it receives only the context assembled by SourceLeaf.
- API providers receive the same explicit targets and selected read-only context, with no filesystem or tool access.
- API keys are stored in macOS Keychain. SourceLeaf never reads or copies Codex `auth.json`.
- Chat, layout, AI history, and generated files live outside the paper project by default.

## License / 许可证

SourceLeaf is source-available under the PolyForm Noncommercial License 1.0.0. Commercial use is not granted. See `LICENSE` and `NOTICE`.

SourceLeaf 采用 PolyForm Noncommercial 1.0.0 源码可用许可证，不授权商业使用。详见 `LICENSE` 与 `NOTICE`。
