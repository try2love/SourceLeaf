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
- Optional: MacTeX/TinyTeX for full `latexmk` compatibility; the default Tectonic engine is bundled automatically

## Build and install / 构建与安装

```bash
scripts/install.sh
```

The script downloads the pinned official Tectonic 0.16.9 binaries for Apple Silicon and Intel, verifies their SHA-256 checksums, embeds them in the app, builds a universal release, verifies its signature, and installs it to `~/Applications/SourceLeaf.app` by default. Downloads and build artifacts stay under the categorized `临时文件` directory.

该脚本会下载固定版本的 Tectonic 0.16.9 官方 Apple Silicon 与 Intel 二进制，校验 SHA-256 后随 App 一起打包；随后构建 Universal Release、验证签名，并默认安装到 `~/Applications/SourceLeaf.app`。下载与构建产物全部保存在分类后的 `临时文件` 目录中。

开发构建：

```bash
swift test
swift run SourceLeaf
```

## Current status / 当前状态

The current `0.2.0` build is a functional technical preview. Its central workflow is available now:

1. Open a LaTeX project folder and select text in a `.tex` file.
2. Attach that selection with the floating button, context command, or `⌥⌘K`.
3. Choose the readable context scope and send an instruction to local Codex or a configured API.
4. Review static LaTeX warnings and the original/proposed text side by side.
5. Accept, reject, or continue adjusting. Source is written only after acceptance, and stale targets are refused.

已经可用的核心流程是：打开 LaTeX 项目、选中源码、附加为严格可写目标、选择上下文范围、让本机 Codex 或 API 生成建议、审阅 Diff 后再决定是否写入。

Before acceptance, SourceLeaf now compiles the proposal in an isolated temporary project copy by default. A failed candidate leaves the real source untouched; the user can inspect the build log or explicitly force acceptance. History restoration is routed back through the same reviewable diff instead of silently overwriting source.

Still in development: SyncTeX source/PDF navigation and the safety review for custom CLI providers. A managed Tectonic engine is bundled by the installer; external `latexmk` remains supported for broader TeX Live compatibility.

接受修改前，SourceLeaf 现在默认在隔离的临时项目副本中试编译。失败时真实源码保持不变；用户可以检查日志，也可以明确选择强制接受。历史恢复同样会先回到 Diff 审阅，不会静默覆盖源码。

仍在开发：SyncTeX 双向定位和自定义 CLI 的安全校验。安装脚本会自动打包受管理 Tectonic；系统已有 `latexmk` 时仍可用于更完整的 TeX Live 兼容性。

## Privacy boundary / 隐私边界

- Local Codex runs in a source-free app workspace with `--ephemeral --sandbox read-only`; it receives only the context assembled by SourceLeaf.
- API providers receive the same explicit targets and selected read-only context, with no filesystem or tool access.
- API keys are stored in macOS Keychain. SourceLeaf never reads or copies Codex `auth.json`.
- Chat, layout, AI history, and generated files live outside the paper project by default.

## Language and prompts / 语言与提示词

The General settings page can switch the interface immediately between Follow System, English, and Simplified Chinese. Localization keys are checked in the test suite so the two translations stay aligned.

The Prompts page supports creating, duplicating, editing, enabling/disabling, and deleting personal prompts. Versioned built-in prompts are read-only; duplicate one to personalize it. Personal prompts are stored globally in SourceLeaf Application Support and never inside the paper project.

“通用”设置可在“跟随系统、English、简体中文”之间即时切换。提示词页支持新增、复制、修改、启用/停用和删除个性化提示词；内置提示词保持只读，复制后即可编辑。自定义提示词保存在 SourceLeaf 的 Application Support 中，不会写入论文目录。

## License / 许可证

SourceLeaf is source-available under the PolyForm Noncommercial License 1.0.0. Commercial use is not granted. See `LICENSE` and `NOTICE`.

SourceLeaf 采用 PolyForm Noncommercial 1.0.0 源码可用许可证，不授权商业使用。详见 `LICENSE` 与 `NOTICE`。
