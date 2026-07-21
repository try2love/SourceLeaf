# 发现与决策

## 需求
- 原生 macOS LaTeX 应用，项目级工作模式，首发中英双语。
- 源码、PDF、Codex、项目导航、编译日志均为独立面板；可关闭、重排、停靠或拖出到独立窗口。
- 用户可通过源码选区、文件行号范围或 PDF 选区指定 AI 修改目标。
- 默认修改范围严格锁定；读取上下文范围可配置为选区、附近、章节、文档、项目或自定义。
- 所有 AI 修改必须先显示 Diff，再接受、拒绝或继续调整。
- 普通 API 无本机文件或工具权限；本机 Codex 也以只读工作区生成结构化补丁。
- 自动保存和自动编译是独立开关；自动编译默认 1.5 秒防抖且可配置。
- 编译缓存、会话、历史、索引与密钥不进入论文项目目录。

## 研究发现
- 本机 Texifier 1.9.33 只暴露基础文档 AppleScript 能力，没有可嵌入侧栏的公开插件接口。
- Codex CLI 与扩展共享 `~/.codex` 状态；`codex exec` 是稳定的非交互接口，`codex app-server` 目前仍标为实验性。
- `codex exec` 可用 `-` 从标准输入读取提示；SourceLeaf 因此不把全文上下文塞进进程参数，并在不含项目源码的应用工作目录中以 `--ephemeral --sandbox read-only` 运行，避免绕过用户选择的上下文范围。
- 本机没有外部 MacTeX/latexmk 命令；Texifier 的内置排版引擎没有独立命令行入口。
- Episteme 使用 Swift Package 构建原生 `.app`，脚本安装到 `~/Applications` 并进行本地签名验证；其仓库未附带可复用许可证，因此 SourceLeaf 全新实现。
- OSI 开源定义要求允许商业使用；禁止商用的软件应称为 source-available。
- PolyForm Noncommercial 允许非商业修改和分发，并明确覆盖个人、教育和公共研究用途。
- Tectonic 官方说明：默认不会启用 shell escape；`--untrusted` 会强制禁用危险能力，而明确启用应使用 `-Z shell-escape`。SourceLeaf 因此在开关关闭时默认传入 `--untrusted`，只有用户主动开启时才传入 shell-escape 参数。

## 技术决策
| 决策 | 理由 |
|------|------|
| Core/App 分层 | 让解析、补丁、编译和 Provider 可单测 |
| `codex exec --json --sandbox read-only` | 使用稳定接口，同时阻止 Codex 直接改文件 |
| 目标内容保存 SHA-256 快照 | 响应期间源码变化时拒绝过期补丁 |
| Tectonic 受管理运行时 + 外部 latexmk | 兼顾一键使用与完整 TeX Live 兼容性 |
| Keychain 保存 API 密钥 | 不在 UserDefaults、项目或日志中暴露密钥 |
| Application Support 保存元数据 | 默认对论文仓库零侵入 |
| Dock zone + SwiftUI value window | 支持面板重排和独立窗口 |

## 遇到的问题
| 问题 | 解决方案 |
|------|---------|
| 当前沙箱不能直接用 apply_patch 写独立仓库 | 使用分类临时编辑镜像并通过批准后的同步命令写入目标 |

## 2026-07-22 首轮真实使用反馈
- 项目导航使用扁平 `List<ProjectFile>`，没有目录节点，因此不可能展开/折叠；图片点击也错误进入 UTF-8 文本读取路径。
- 源码编辑器把 TextKit 容器宽高都设为无限并在每次文本变化时重写整段属性；行号尺只在文本/SwiftUI 更新时重绘，没有监听滚动边界变化。这与“窄栏后部分可见、点击灰块、向上滚动行号消失”的现象吻合。
- 停靠区为空时会从 `HSplitView` 中移除，使拖入空区无目标；面板只有标签头可拖，也没有 VS Code 风格活动栏。
- 浮动窗口通过 `openWindow` 后立即从主布局删除，但窗口关闭事件没有回调恢复面板。
- 主应用包没有声明 `CFBundleLocalizations`，中英文仅位于 SwiftPM 子资源包；标准 `NSOpenPanel` 因此不能可靠跟随应用/系统语言。
- `ProjectPanel` 的大纲行只是静态文本，没有将行号传给源码编辑器；上次项目路径也没有持久化。
- 底部区域被硬编码为最小 150、理想 220 点，确实会喧宾夺主。
- 当前编译器只查找外部 `latexmk/tectonic` 或 Application Support 中的受管理二进制，但安装脚本没有部署引擎。
- `AppModel.openFile` 对所有文件无条件调用 UTF-8 解码，确认图片预览故障属于路由错误；`saveCurrentFileIfNeeded` 也需要限定为文本文件，避免图片被误写。
- `AppModel.report`、AI 验证、历史恢复等路径直接展示 `error.localizedDescription` 或硬编码英文；完整汉化需要一个 UI 错误翻译边界，而不是只补 strings key。
- `DockLayout.show` 在面板已经存在时直接返回，活动栏点击还需要“存在则选中并激活所在区域”的语义，不能只做显示/隐藏。
- SwiftUI 的 value-based `WindowGroup` 没有窗口关闭回调；需要在浮动窗口内容的 `onDisappear` 中将面板放回原停靠区，并记录弹出前区域。
- 安装脚本当前只构建/复制 SourceLeaf 自身；`Info.plist` 仅声明英文开发区且没有 `CFBundleLocalizations`。主包还需要复制 `en.lproj`、`zh-Hans.lproj` 或声明本地化，才能让 AppKit 标准面板按正确语言工作。
- 设置页仍有 `New Provider`、自定义命令占位符等硬编码英文；这些需要纳入本轮 key 完整性检查。
- 全仓扫描确认 Core 层的 Provider、编译器、补丁、钥匙串、进程和验证器错误都以英文字符串暴露；最小侵入方案是在 App 的 `L10n.userMessage(for:)` 按错误类型/枚举映射，验证器消息则新增稳定 code 供 UI 翻译。
- `ValidationIssue` 当前只有自然语言 message，测试也依赖英文片段；要稳定汉化需保留英文调试 message，同时新增结构化 `kind`，UI 按 kind 翻译，测试改断言 kind。
- 当前测试只有 Core 逻辑，无 AppKit 编辑器滚动/颜色和 SwiftUI 窗口生命周期的正确测试 seam；本轮需要抽出纯函数（项目树、行号可见范围、最近项目、面板恢复）做回归测试，并保留人工 GUI 冒烟清单。
- Tectonic 官方 GitHub Releases 显示当前稳定版为 `0.16.9`（2026-04-17），其中包含 macOS 主字体崩溃修复；受管理引擎应固定此版本，而不是在安装时盲目追随 latest。
- Tectonic 官方安装文档确认其可以单一可执行文件运行。SourceLeaf 采用“下载固定官方 release 资产、校验 SHA-256、嵌入 App Resources、签名前执行版本检查”的交付路径，不直接执行远程安装脚本。
- 官方 0.16.9 release API 给出的 macOS 资产与摘要为：Apple Silicon `tectonic-0.16.9-aarch64-apple-darwin.tar.gz` / `edb67c61aba768289f6da441c9e6f523cfaff4f8b2a5708523ef29c543f8e88e`，Intel `tectonic-0.16.9-x86_64-apple-darwin.tar.gz` / `79d8839fa3594bfea9b2bf2ac0a0455bcc4d0de956a5e5c403107e9a72f79e86`。
- Tectonic 0.16.9 仓库根许可证明确为 MIT，并说明其派生组件还涉及多种开放源码许可证；安装包需至少随附其根许可证并在第三方清单标注版本与上游地址。
- 第二轮可见字符串扫描又发现“继续调整”、Diff 兜底名、浮动窗口标题、历史 Provider 名仍为硬编码英文；已全部迁入双语资源。未识别错误不再把系统英文 `localizedDescription` 直接暴露到中文 UI，而显示本地化的错误编号提示。
- 双架构引擎下载脚本不能以运行另一架构二进制作为安装前提（Intel 无法运行 arm64，Apple Silicon 也不应强依赖 Rosetta）；改为用 `file` 校验两个资产，并只运行当前主机架构的 `tectonic --version`。

## 资源
- Codex command reference: https://learn.chatgpt.com/docs/developer-commands.md?surface=cli
- PolyForm Noncommercial 1.0.0: https://polyformproject.org/licenses/noncommercial/1.0.0
- Open Source Definition: https://opensource.org/osd
- Developer Certificate of Origin: https://developercertificate.org/
- Tectonic releases: https://github.com/tectonic-typesetting/tectonic/releases
- Tectonic installation: https://tectonic-typesetting.github.io/book/latest/installation/index.html

## 视觉/浏览器发现
- `TeXloom`、`Syntaxis`、`Scholion` 等候选名称已有活跃产品，最终选择 `SourceLeaf`。

---
*每执行2次查看/浏览器/搜索操作后更新此文件*
