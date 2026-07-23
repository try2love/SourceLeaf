<h1 align="center">SourceLeaf</h1>

<p align="center">
  一个用于编写 LaTeX、审阅 PDF，并在用户明确控制下应用 AI 修改建议的原生 macOS 工作区。
</p>

<p align="center">
  <a href="README.md">English</a> · <strong>简体中文</strong>
</p>

<p align="center">
  <a href="https://swift.org"><img alt="Swift 6" src="https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white"></a>
  <img alt="macOS 14+" src="https://img.shields.io/badge/macOS-14%2B-0A84FF?logo=apple&logoColor=white">
  <img alt="Universal" src="https://img.shields.io/badge/Universal-arm64%20%7C%20x86__64-555555">
  <a href="https://github.com/try2love/SourceLeaf/releases"><img alt="版本 0.3.24" src="https://img.shields.io/badge/version-0.3.24-2ea44f"></a>
  <a href="LICENSE"><img alt="PolyForm Noncommercial 1.0.0" src="https://img.shields.io/badge/license-PolyForm%20Noncommercial-blueviolet"></a>
</p>

<p align="center">
  <a href="#为什么选择-sourceleaf">项目理念</a> ·
  <a href="#主要功能">主要功能</a> ·
  <a href="#安装">安装</a> ·
  <a href="#快速开始">快速开始</a> ·
  <a href="#受控-ai-修改流程">AI 修改流程</a> ·
  <a href="#架构">架构</a> ·
  <a href="#开发">开发</a>
</p>

SourceLeaf 将学术写作的核心流程放在同一个原生工作区中：编辑 LaTeX、查看编译后的 PDF、使用 SyncTeX 双向定位，并让本机 Codex CLI 或配置好的 API Provider 提供修改建议。AI 输出始终只是建议，只有用户查看可见 Diff 并明确接受后才会写入源码。

> [!IMPORTANT]
> SourceLeaf 当前是面向 macOS 14 及以上系统的产品级预览版本。本项目仅以非商业用途“源码可用”的形式发布，尚未进入 Mac App Store，也暂未提供经过公证的二进制发行包。

## 为什么选择 SourceLeaf

许多 AI 写作集成会获得过大的项目访问范围，或只返回需要手工复制的文本。SourceLeaf 使用更严格的修改契约：

- 可写目标必须是明确选区、指定行号范围或经确认的 SyncTeX 映射；
- 章节、全文或项目级内容只能作为只读上下文；
- 每项建议都要经过静态检查并以 Diff 展示；
- 候选 LaTeX 会先在隔离的项目副本中试编译；
- 原文发生变化时拒绝写入，避免覆盖用户的新修改。

应用的其余部分也遵循本地优先边界：项目元数据保存在论文文件夹之外，API 密钥保存在 macOS 钥匙串，本机 Codex Provider 复用这台 Mac 已安装并登录的 Codex CLI。

## 主要功能

### LaTeX 工作区

- **原生源码编辑器**：接近 Overleaf 的语义配色、原生实时选区、稳定的连续输入与光标所有权、固定行号、自动换行、不透明系统查找替换、系统/浅色/深色主题，以及可持久化的字体设置。
- **项目导航**：文件夹整行折叠、项目 PDF 专用多页预览、居中且可拖动的图片预览，以及可逐级折叠并跳转到源码位置的跨文件文档结构。
- **LaTeX 编辑工具**：支持查找替换、可切换文字样式、常用快捷键、标题等级、字号、公式、表格、图片、列表、引用、交叉引用、标签和网址。
- **明确保存能力**：未保存状态提示、工具栏操作和 `⌘S`。

### 编译与 PDF

- 安装程序自动内置 Apple Silicon 与 Intel 双架构 **Tectonic 0.16.9**。
- 支持外部 `latexmk` 和更完整的 TeX Live 工具链。
- 支持无修改快速复用、重启后自动恢复上次成功 PDF、实时编译阶段、结构化日志摘要和手动清理缓存。
- 支持源码与 PDF 之间的 SyncTeX 双向定位，不修改磁盘上的生成 PDF。
- PDF 默认纵向连续阅读，支持缩略图、0.1×–8× 缩放、Control+滚轮缩放、紧凑导航、自动编译控制和 PDF 另存为；图片预览使用相同缩放范围。

### 可审阅的 AI 辅助

- **本机 Codex CLI 优先**：复用当前 Mac 的 Codex 登录和配置，不复制 `auth.json`。
- **可配置 Provider**：支持本机 Codex、受限无头 CodeBuddy 和 HTTP API，可选择模型与 Provider 支持的思考深度。
- **可验证连接**：显式发送 `hello` 健康检查，驱动未检测/检测中/已连接/失败状态。
- **可选择上下文范围**：无、仅选区、附近内容、当前章节、全文、整个项目或自定义文件；没有修改目标时自动使用普通纯文本对话协议。
- **写入前审阅 Diff**：先检查警告、试编译结果与原文/建议，再选择接受或拒绝。
- **提示词库**：包含紧凑的快捷 Prompt 菜单，支持内置和个人提示词的新增、复制、编辑、启停与删除；长中英文模板使用单语言大编辑区。
- **完整会话管理**：支持新建、重命名和切换会话；消息可选择、复制、修改、针对指定回答重新生成并显示时间；支持终止回答、自定义发送键、系统提示词和可折叠的真实 Provider 活动流。
- **安全历史恢复**：已接受 Diff 会保留为只读记录；历史恢复同样经过完整原文/修改后 Diff 审阅，不会静默覆盖源码。

### 灵活的原生界面

- 源码、PDF、对话、项目导航和日志面板均可显示、隐藏、重新排列、停靠或独立浮动。
- 对话输入区可纵向拖动调整，并记住用户设置的高度。
- 界面文字大小会连续缩放实际语义字体，并独立于源码字体，适配外接显示器。
- 主工作区分隔条具有更宽的拖动命中区；可点击控件提供本地化悬停说明，并在适用时显示当前状态。
- 关闭独立面板窗口后，对应面板会回到主工作区。
- 界面语言可在 English、简体中文和跟随系统之间即时切换。
- 自动恢复上次打开的项目和源码文件。

## 安装

### 环境要求

- macOS 14 Sonoma 或更高版本
- Xcode 16 或更高版本，包括命令行工具
- 首次安装时需要联网下载固定版本的 Tectonic 二进制文件
- 可选：[Codex CLI](https://github.com/openai/codex)，用于本机 Codex Provider
- 可选：[CodeBuddy CLI](https://www.codebuddy.ai/docs/cli/overview)，用于受限的本机 CodeBuddy Provider
- 可选：MacTeX、TinyTeX 或其他 `latexmk` 工具链，用于超出 Tectonic 兼容范围的宏包

### 构建并安装

```bash
git clone https://github.com/try2love/SourceLeaf.git
cd SourceLeaf
scripts/install.sh
```

安装脚本会：

1. 下载官方 Tectonic 0.16.9 的 `arm64` 与 `x86_64` 二进制文件；
2. 校验固定的 SHA-256；
3. 构建并 ad-hoc 签名 Universal SourceLeaf 应用；
4. 安装到 `~/Applications/SourceLeaf.app`；
5. 将旧版本保存在分类明确的 `临时文件/安装备份` 目录中。

安装完成后运行：

```bash
open "$HOME/Applications/SourceLeaf.app"
```

下载文件和中间构建产物都保存在仓库中已忽略的 `临时文件` 目录，不会写入 LaTeX 项目或 Git 提交。

## 快速开始

1. 启动 SourceLeaf，选择一个 LaTeX 项目文件夹。
2. 打开主 `.tex` 文件，通过工具栏按钮进行编译。
3. 根据当前任务调整源码、PDF、项目和对话面板的位置。
4. 选择源码、指定明确行号范围，或使用经确认的 PDF 到源码映射。
5. 将目标附加到对话，选择上下文范围并描述修改要求。
6. 检查警告、试编译结果和 Diff，然后选择接受、拒绝或继续调整。

普通 LaTeX 编辑时可以完全关闭对话面板和选区操作入口；选区浮动按钮也可以在设置中关闭。

## 受控 AI 修改流程

```text
明确的源码目标
      ↓
只读上下文范围
      ↓
Provider 修改建议
      ↓
目标与 LaTeX 静态验证
      ↓
隔离副本试编译
      ↓
可见 Diff 与用户决定
      ↓
原子写入或拒绝
```

SourceLeaf 会记录目标原文及其哈希。如果生成建议期间源码已经变化，应用会拒绝接受旧建议，用户需要重新创建目标。

本机 Codex 在 Application Support 下不包含论文源码的工作区中运行，并使用临时、只读执行模式。CodeBuddy 也以无头模式运行于不含源码的工作区，并禁用文件、命令、搜索和网络工具。HTTP Provider 只能接收组装后的目标和所选上下文，不会通过 SourceLeaf 获得文件系统或工具权限。

## 数据与隐私

| 数据 | 默认位置 |
| --- | --- |
| LaTeX 源码与素材 | 原始项目文件夹 |
| 项目状态、对话、历史与 Provider 工作区 | `~/Library/Application Support/SourceLeaf/` |
| PDF、日志和可清理构建产物 | `~/Library/Caches/SourceLeaf/` |
| API 密钥 | macOS 钥匙串 |

SourceLeaf 不会向论文项目添加元数据。开发和测试时可以隔离应用数据：

```bash
SOURCELEAF_SUPPORT_DIRECTORY="$PWD/临时文件/开发/ApplicationSupport" \
SOURCELEAF_CACHE_DIRECTORY="$PWD/临时文件/开发/Caches" \
swift run SourceLeaf
```

## 架构

SourceLeaf 将确定性编辑/编译规则与原生界面分离：

```text
Sources/
├── SourceLeafCore/       # 项目索引、修改目标、验证、Provider、
│                        # 编译、SyncTeX、持久化与提示词
└── SourceLeafApp/        # SwiftUI 工作区与设置、AppKit/TextKit 编辑器、
                         # PDFKit 预览、对话和审批流程

Tests/
├── SourceLeafCoreTests/  # 确定性单元测试与真实项目检查
└── SourceLeafAppTests/   # AppKit、PDFKit、行为、边界与视觉检查
```

源码目标契约、存储边界和 SyncTeX 设计详见 [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)。

## 开发

运行完整测试：

```bash
swift test
```

通过 SwiftPM 运行应用：

```bash
swift run SourceLeaf
```

构建本地 Universal 应用包：

```bash
scripts/build-app-bundle.sh
```

常用构建覆盖变量包括 `SOURCELEAF_TEMP_ROOT`、`SOURCELEAF_APP_OUTPUT`、`SOURCELEAF_INSTALL_ROOT`、`SOURCELEAF_ARCHS` 和 `SOURCELEAF_SKIP_MANAGED_ENGINE=1`。

## 当前限制

- SourceLeaf 仅支持 macOS，并依赖 SwiftUI、AppKit/TextKit、PDFKit 和 Quick Look。
- 当前通过源码安装脚本和 ad-hoc 签名分发，尚未发布经过公证的下载包。
- 默认安装路径由 Tectonic 支持，但部分项目仍需要完整 TeX Live/`latexmk` 工具链。
- 任意自定义 CLI Profile 在安全命令契约完成前仍保持禁用。WorkBuddy 官方公开产品文档目前没有提供可验证的无头 CLI 或 API 契约，因此本项目不宣称已支持。
- 云同步、多人共享编辑和协作功能不在当前范围内。

## 参与贡献

欢迎提交符合项目非商业许可证和本地优先安全边界的贡献。请先阅读 [CONTRIBUTING.md](CONTRIBUTING.md)，使用 [Developer Certificate of Origin](DCO.txt) 签署提交，并运行：

```bash
swift test
swift build -c release
```

请勿提交 API 密钥、个人路径、论文内容、对话历史或生成的构建产物。

## 许可证

SourceLeaf 依据 [PolyForm Noncommercial License 1.0.0](LICENSE)，以**仅限非商业用途的源码可用软件**形式发布，不授权商业使用。

第三方组件和可选外部工具遵循其各自许可证，详见 [THIRD_PARTY_LICENSES.md](THIRD_PARTY_LICENSES.md) 与 [NOTICE](NOTICE)。

SourceLeaf 是独立项目，与 OpenAI、Apple、Tectonic 项目或 Texifier 开发者不存在隶属或官方认可关系。
