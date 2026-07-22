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

## 2026-07-22 产品级验收发现
- 真实论文根目录的有效素材规模并不大：`MutedRAG.tex` 799 行、`reference.bib` 488 行，正文引用 11 张 PNG，另有 5 张作者 JPG；项目总体 1.6GB 的体积主要来自与本轮 UI 冒烟无关的更深层内容，因此应复制“主文档 + Bib + figures”而不是盲目复制整个目录。
- `MutedRAG.tex` 使用 `acmart`、算法、子图、表格、颜色和图像宏，包含多层 section/subsection、参考文献与作者照片，是比最小 article 更能证明 SourceLeaf 项目树、图片预览、大纲和真实编译能力的代表性样本。
- 图像覆盖大尺寸 RGB/RGBA PNG、嵌套 `figures/author/*.jpg` 和不同宽高比，可同时测试目录展开、图片路由、Quick Look 缩放和内存合理性。
- Tectonic 0.16.9 的传统 CLI 支持显式 `--bundle`、`--only-cached`、SyncTeX 和输出目录，但没有直接暴露缓存目录参数；V2 `show user-cache-dir` 可以报告默认缓存位置。真实回归要么使用本轮已分类保存的本地 bundle/cache，要么在完成后再次把默认缓存移回“临时文件”。
- 进一步检查官方二进制字符串确认 Tectonic 支持 `TECTONIC_CACHE_DIR`。这比移动 `~/Library/Caches` 或把内部 data/index 误当 bundle 更可靠，也能确保真实项目编译产生的所有资源缓存留在 `临时文件/引擎缓存`。
- 安装版内置 Tectonic 已完整编译真实 `MutedRAG.tex`：输出 24 页 Letter PDF（3,590,135 bytes）、155KB SyncTeX 和 BibTeX 日志，说明 `acmart`、参考文献、PNG/JPG、复杂数学字体和多轮重编译链路均可用。
- 首次复杂编译的日志会被大量字体请求与中继重试淹没；SourceLeaf 当前把整个原始日志平铺在底部，不足以区分“正在准备资源”“论文警告”“真正错误”。合理的产品行为应增加阶段化状态、错误/警告摘要和可展开原始日志。
- 24 页 PDF 联系表及第 5、12、20、24 页原尺寸抽查均正常：无空白页、黑块、缺图、裁切、字体乱码或表格重叠；overview 图、六联参数图、Discussion 正文、参考文献和 5 张作者照片均正确渲染。真实编译成功证据足够强。
- PDF 自身存在论文级 overfull/underfull 警告和个别 JPEG DPI 元数据不一致，但视觉抽查未见由 SourceLeaf/Tectonic 引入的版式破坏；这些应在 App 中归入“警告”而不是“编译失败”。
- 代码审查发现 `ProcessRunner` 直到进程结束才把 stdout/stderr 一次性交给 `AppModel`；复杂论文首次编译期间，用户只能看到无文本进度的 spinner，无法知道是在下载宏包、运行 TeX、跑 BibTeX 还是卡住。这与真实编译中数十秒中继重试结合后，属于明确的人类友好性缺陷。
- 编译运行时工具栏按钮被禁用，当前没有“停止编译”入口；`CompilerService` 与 `ProcessRunner` 已具备取消基础，但 UI 没有暴露。应改为编译中显示停止按钮，并保证取消后状态一致。
- 编译日志面板当前只有整段等宽文本与复制按钮，没有警告/错误/资源下载摘要。应抽出纯函数日志分析器，增加可测试的统计和当前阶段，原始日志仍保留用于诊断。
- `openProject` 切换项目时没有先清空 `selectedFile/sourceText/selectedImageFile`；如果上一项目正在显示源码而新项目的最近文件为图片，旧项目源码状态可能残留。需要项目切换状态回归测试或显式重置边界。
- 编辑器开启了水平滚动条，但 TextKit 容器同时启用随宽度换行且禁止水平 resize，因此水平滚动条没有实际意义，会制造视觉噪声。
- 新建立的真实 `WorkspaceView` 离屏浅/深色截图直接复现了用户最关键的缺陷：源码区行号与 799 行布局存在，但 LaTeX 字符完全没有绘制。此前“设置 textColor + 修正无限容器”的证据不足，不能视为问题已解决。
- 源码空白的高概率根因进一步收敛为 AppKit 几何初始化：手工创建零 frame `NSScrollView`，再用其当时为零的 `contentSize` 初始化 `NSTextView` 和 text container；后续 Auto Layout 扩大外层时，文档视图/容器没有可靠得到有效宽度。应采用 AppKit 标准 `NSTextView.scrollableTextView()` 或显式布局同步，并用截图像素/实际 NSTextView 绘制做回归门槛。
- 真实工作区截图还解释了用户所谓“PDF 分成两个区域”：`PDFView.displayMode = .singlePageContinuous` 会在同一面板上下呈现连续页面及页间分隔；离屏时页面内容没绘制，只剩两块白纸，更显得像两个区域。默认改为单页模式并提供页码/前后页控制更符合其明确预期。
- 视觉层级整体方向正确（44pt 活动栏、项目树、源码、PDF、紧凑底栏），但仍有明显粗糙点：项目树与大纲之间出现纯黑分隔带；浅色模式大纲标题疑似未绘制；英文标签在中文目标截图中仍显示 Project/Build Log/Compile/Build succeeded，说明 L10n 静态 Bundle 仍读取全局设置而非注入的模型语言，动态汉化边界需继续改进。
- 源码编辑器专用像素截图证明标准滚动 `NSTextView` 已能在 820×780 可见区域真实绘制 799 行论文的首屏字符；整窗离屏截图仍不含嵌套 AppKit 文本/PDF 内容，这是 `NSHostingView.cacheDisplay` 对异步/子 AppKit 视图的离屏捕获限制，不能再用整窗图单独判定源码是否绘制。后续以“实际 NSTextView 几何 + 专用像素截图 + 安装版人工冒烟”三重证据验收。
- `PDFView` 已从 `.singlePageContinuous` 改为 `.singlePage`，并接入页数状态与前后页控制；真实 24 页文档截图显示工具栏为 1/24 且只保留一张纸面区域，用户反馈的“双区域”根因已消除。
- 项目/大纲分界已改为 28pt 语义标题栏并限制大纲默认高度；黑色粗分隔带消失，文件树继续保留目录折叠层级。双语资源当前各 170 个 key 且集合完全一致，可见字符串扫描只剩品牌名、语言自称、秒单位和命令示例等无需翻译项。
- 多文件边界论文（根文档、两层 `sections/`、Bib、嵌套 PNG）已由内置 Tectonic 完整编译，生成 417KB PDF、SyncTeX 和 BibTeX 日志；故意缺右括号的项目稳定退出 1 并产出明确 `File ended while scanning use of \\textbf` 错误日志。
- 边界测试揭示原大纲只属于当前文件，无法完成多文件 Overleaf 式跳转。`DocumentOutlineItem` 现携带 `relativePath`，App 打开项目时构建项目级结构、编辑时只增量更新活动文件；点击 `sections/deep/details.tex` 的小节会先切换文件再定位对应 UTF-16 行位置，避免每次按键重扫整个项目。
- “没有 `\\documentclass`”的项目原先会错误把第一个 `.tex` 猜成主文档；现在仍可打开 notes.tex 阅读，但不会虚构 root document，点击编译会立即显示本地化的“选择主文档”提示。JPG/SVG 图片项目和非 UTF-8 `.tex` 也已覆盖：前者路由到预览，后者不显示旧项目文本且安全报错。
- 运行时汉化的真正缺陷不是缺 key，而是 `Bundle.module.path(forResource: "zh-Hans", ofType: "lproj")` 在 SwiftPM 资源包中返回不到目标目录，导致所有显式中文选择静默回退英文。改为按 `localization:` 定位 `Localizable.strings` 后，项目、编译、日志、成功状态和引擎错误五个代表性界面均通过中文精确值测试，最新真实工作区截图也已全中文。
- 项目图片预览不仅通过类型识别：真实 `vector.svg` 已进入 `QLPreviewView.previewItem`。行号尺测试也从不可靠的 `needsDisplay` 中间标志改为“滚动通知计数 + 实际可见字符范围”，确认从第 500 行向上跳到第 40 行时通知发生且可见行回到 80 以内。
- 二次启动体验现有直接回归：自定义提示词的中英文名称、正文与启停状态跨 AppModel 持久化；最近项目及两层嵌套源码恢复；浮动 PDF 面板关闭后回到原 trailing 区。三者均通过，覆盖用户最容易在长期使用中感知的状态丢失风险。
- 本机没有独立 `synctex` 命令，但 Tectonic 生成的 `.synctex.gz` 包含完整 Input tag、页码、源码行和 scaled-point 坐标；因此 SourceLeaf 内置解析器即可实现双向定位，不需要用户再安装 MacTeX。真实多文件索引已完成 `sections/deep/details.tex:1 → PDF 第 1 页坐标 → 同文件第 1 行` 往返。
- 反向定位只接受打开项目根目录内且已被项目索引识别的路径，避免 SyncTeX 中异常 Input 路径触发任意文件打开；源码正向定位会切换 PDF 单页并添加仅存在于内存的橙色圆形 annotation，不写回 PDF 文件。
- 1024×700 压力截图发现 PDF 内重复“立即编译”文字会截断；改为具备中文 tooltip/无障碍标签的播放或停止图标后，页码、SyncTeX 图标和成功状态在紧凑宽度均完整显示。1728×1050 宽屏仍保持三栏比例和 82pt 紧凑日志层级。
- Codex 核心面板快照最初暴露两项可读性风险：动态气泡颜色在浅/深离屏组合中可能吞掉助手文字，`Text.textSelection` 的 AppKit 选择层会在深色用户气泡中只留下标点。现改为显式浅/深背景与前景、右键复制消息，并为输入框增加本地化 placeholder；复核图中两类消息、选区胶囊、Diff、静态检查与操作按钮均清晰。
- 0.3.0 新增构建时生成的原生 `.icns`：蓝绿渐变底、源码花括号、文稿与叶片意象；16–1024px iconset 经 `iconutil` 生成 782KB 有效 ICNS，并通过 Info.plist/签名打包检查。

---
*每执行2次查看/浏览器/搜索操作后更新此文件*
