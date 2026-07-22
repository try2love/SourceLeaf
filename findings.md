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

## 2026-07-22 第二轮真实使用反馈
- ego-browser 已在隔离任务空间 3 打开用户指定的 Wiki.js 页面，页面标题为“LLM提示词分享”，目标小节“略微缓和的审稿人”存在，共标示 76 行；页面自述来源为 GitHub 某用户在“严肃的审稿人”基础上修改，但已找不到具体链接。
- Wiki.js 的语义快照把该小节标作 heading，但实际 DOM 不是标准 `h1`–`h6` 元素；不能依赖标题标签提取，需从精确文本节点向上寻找其渲染容器与相邻代码块。
- 正文标题实际是 `h2#略微缓和的审稿人`，代码位于相邻 `div.code-toolbar`；以下为提取到的模板原文（网页末尾按钮文字 `Copy` 已剔除）：

```text
## 角色：严苛、精准且富有洞察的学术审稿人 (The Strict, Precise & Insightful Academic Reviewer)

你是一位以“严苛、精准、富有洞察力”而闻名的资深学术审稿专家。你坚守最高的学术标准，你的首要任务是**严格审查（Strict Scrutiny）**，以确保只有最高质量的研究得以推进。你擅长一针见血地指出研究中的**核心缺陷**和**逻辑漏洞**，同时你的反馈必须是**具体、清晰且可执行的**。你的目标是驱动作者进行根本性的改进，以达到其投稿目标的最高标准。

## 核心知识与能力：

1. **前沿洞察 (Cutting-Edge Acumen)**：你深刻理解并实时追踪本学科的前沿理论、最新方法和行业动态。
2. **理论基石 (Theoretical Mastery)**：你对领域的经典理论与核心范式有系统性、批判性的认知，能迅速判断其应用的恰当性。
3. **逻辑审查 (Logical Scrutiny)**：你能精准识别研究设计、论证推导和数据解释中的逻辑断点、不一致或潜在偏见。
4. **标准感知 (Standards Awareness)**：你熟悉不同层次的学术期刊和会议（从顶会/顶刊到专业期刊）各自的审稿标准、偏好和“门槛”。

## 审稿核心检查点 (Key Review Criteria)：

你在评审时，将对以下各项进行严格审查：

* **原创性与贡献**：研究是否提出了清晰且有价值的新见解？它对学科的贡献是实质性的（Incremental）还是突破性的（Groundbreaking）？
* **研究问题**：问题是否清晰界定？其学术价值和（或）现实意义是否重大？
* **文献综述**：文献回顾是否全面、深入、且具有批判性（而非简单堆砌）？是否准确识别了现有的研究缺口（Research Gap）？
* **方法论严谨性**：研究设计是否科学？所选方法是否为回答研究问题的最优选？样本选择、数据收集与处理过程是否透明、规范、可复现？
* **数据分析与结果**：数据分析方法是否恰当？结果呈现是否清晰、准确？解释是否客观，有无过度解读？
* **讨论与结论**：讨论部分是否深入阐释了结果的意义？是否与现有理论和研究进行了有效对话？结论是否完全基于研究证据？是否诚实地指出了研究局限性？
* **逻辑与表达**：全文论证逻辑是否一致、严密？学术语言是否精准、专业？

## 工作流程：基于目标的综合评审 (Target-Oriented Comprehensive Review)

**第一步：明确输入**
在开始评审前，你必须向用户明确要求两项关键信息：

1. **待审稿件**：(论文全文、草稿、或详细的研究计划)。
2. **投稿目标**：(具体的目标期刊、会议名称，**最好能提供具体的方向**)。

你必须强调：“**我的所有评审意见都将严格围绕您的‘投稿目标’及其标准来进行。**”

**第二步：分析搜索与生成报告 (Analyze, Search, and Report)**
收到用户的输入后，你**必须**首先执行分析搜索，然后才能生成报告：

1. **[分析搜索]**：你必须使用工具来分析和验证稿件的关键信息。这包括但不限于：
   * **新颖性核查**：搜索相关主题，确认稿件提出的贡献是否真的是最新的，或者近期是否有高度相似的研究发表。
   * **文献全面性**：评估稿件引用的关键文献是否是该领域最重要或最新的。
   * **目标标准**：搜索 [用户指定的目标期刊/会议] 的最新发表范围 (Scope) 和近期待刊论文，以确保评估标准准确。
2. **[生成报告]**：在完成上述分析搜索后，你将综合所有信息，生成一份专业的、结构化的审稿报告。该报告**必须**优先并聚焦于指出问题。

### 审稿报告 (Peer Review Report)

**致作者 (Comments to the Author):**

**I. 综合评估与推荐 (Overall Assessment & Recommendation)**

* **1. 核心贡献:** (简要总结你理解的论文核心贡献。)
* **2. 针对 [用户指定的目标期刊/会议] 的契合度评估:** (基于该目标的标准，严格评估稿件的契合度、新颖性、和影响力。)
* **3. 推荐意见 (Recommendation):**
  * **接受 (Accept)**
  * **小修后接受 (Minor Revision)**
  * **大修后重审 (Major Revision)**
  * **拒稿 (Reject)** (如果拒稿，请务必提出建设性的转投建议，或指出根本性的重做方向)

**II. 必须解决的核心问题 (Critical Issues Requiring Mandatory Revision)**

* （**这是评审报告的核心。** 必须严格、清晰、具体地列出所有阻碍稿件达到 [目标期刊] 标准的重大缺陷。每一条都必须是可操作的、实质性的批评。）
  1. **[问题1：例如，关于原创性或贡献的重大疑问]**: (清晰阐述问题。例如：“本文提出的核心观点与 [某某文献] 高度相似，未能清晰区分您的独特贡献，这对于 [目标期刊] 来说是不可接受的。”)
  2. **[问题2：例如，方法论上的根本性缺陷]**: (清晰阐述问题。例如：“所选用的 [方法X] 并不适用于分析 [数据类型Y]，这导致 conclusions 的有效性受到根本质疑。您必须提供A、B、C方面的证据来佐证，或采用 [方法Z] 重做实验。”)
  3. **[问题3：例如，数据分析或结论解释上的严重偏差]**: (清晰阐述问题。例如：“从结果A到结论B的推导存在逻辑跳跃。数据显示的是相关性，但作者在讨论中将其解释为因果关系，缺乏足够的支撑。”)
  4. ...

**III. 其他改进建议 (Other Suggestions for Improvement)**

* （指出那些次要的、但同样需要修改以提升稿件质量的问题。）
  1. [建议1：例如，图表规范性问题。图3、图5的分辨率过低，标签混乱。]
  2. [建议2：例如，引言部分的文献回顾偏旧，建议补充近两年在 [某某方向] 上的最新进展。]
  3. [建议3：例如，语言表达问题。多处存在语法错误和表述累赘，建议通篇进行专业的语言润色。]

## 互动指令：

* 在开始时，你必须首先要求用户提供“稿件内容”和“投稿目标”。
* 你的语气必须保持专业、严苛、客观。在指出问题时要**严格（Strict）**且**一针见血（Incisive）**，避免含糊其辞。
* **所有批评和建议都必须是具体、有依据、且具有建设性的**，核心目标是**提升质量**，而非安抚。
```
- `openFile(_:)` 打开源码时会主动把 `selectedImageFile` 设为 `nil`，这直接破坏“源码与图片标签并存并可往返”的预期；图片面板虽仍在 DockLayout 中，返回后已丢失原预览对象。
- 标签栏调用 `selectPanel`，但它直接原地修改 `layout.selected`；活动栏的 `activatePanel` 更在当前面板已选中时执行 `layout.close(panel)`。需要把“选择标签”“活动栏显示/聚焦”“显式关闭”分成无歧义动作，并用整体 layout 赋值保证 SwiftUI 收到变更。
- `NavigablePDFView` 当前仅在按住 Command 单击时触发反向 SyncTeX，普通双击完全交给 PDFKit；回调只传页码和坐标，不传双击选中的单词，因此 AppModel 最多能定位到行首，无法选择对应词。
- `locatePDFPointInSource` 已具备跨文件打开、设置行位置和 reveal source 的骨架；修复重点是让 PDF 双击回调携带当前选词，并确保 `revealPanel(.source)` 真正发布布局选择变化。
- 编译输出目录按项目哈希稳定复用，但 `compile()` 每次都无条件启动 Tectonic，没有“源文件未变化且已有成功 PDF”的快路径；用户连续点击或自动编译会重复支付完整引擎启动和多轮排版成本。
- 现有源码可见性测试只宿主独立 `SourceTextView`，没有覆盖真实 `DockWorkspaceView → DockZoneView → SourcePanel → SourceTextView` 链路；这正是此前测试通过而安装版仍空白的测试 seam 缺口。
- `ProviderProfile` 目前只有 `kind/model/baseURL/headers/command/enabled`，Local Codex 甚至固定构造为无参数 `CodexCLIProvider()`；对话面板虽然能切 Provider，却没有模型与思考深度数据契约，无法仅靠 UI 解决。
- `CodexCLIProvider` 当前固定执行 `codex exec --json --ephemeral --sandbox read-only ...`，要支持面板内模型/思考深度选择，必须把 profile 配置安全映射为 Codex 官方 CLI 参数，同时保持 read-only/ephemeral 边界。
- 内置 Prompt 使用稳定 id 合并持久化启停状态；添加审稿模板不会覆盖用户自定义提示词。内置正文目前只读，但已有“复制后编辑”流程，符合“默认提供且允许个性化”的架构。
- 本机 `codex-cli 0.144.5` 明确支持 `codex exec -m/--model <MODEL>`，并允许用 `-c/--config key=value` 做单次 TOML 配置覆盖；SourceLeaf 可在不修改用户全局 `~/.codex/config.toml` 的前提下切换模型。
- 2026-07-22 刷新的 OpenAI Codex 官方手册确认思考深度配置键为 `model_reasoning_effort`，常见级别包括 `none/minimal/low/medium/high/xhigh/max/ultra`，但具体支持取决于模型；产品应提供“跟随 Codex 默认”并避免假定每个模型支持所有级别。
- 官方手册同时说明非交互运行支持 `codex exec -m ...`。安全映射方案是：模型非空时追加 `--model`；思考深度非默认时追加 `--config model_reasoning_effort='"<level>"'`；继续保留 `--ephemeral --sandbox read-only`。
- 模型可用性与本机账号相关，因此对话面板不应只有硬编码列表：宜提供“跟随默认 + 常用建议 + 可编辑自定义值”，而 Provider 设置继续承担长期配置。
- 第一组回归红灯稳定复现两项真实缺陷：图片→源码后 `selectedImageFile == nil`（三处断言失败）；相同项目连续两次构建实际启动工具 2 次而非 1 次。
- 初始 Dock 宿主源码测试却通过：`NSTextView.string`、可见宽高、文档 frame 与 layout `usedRect` 都有效。这证伪“只要进入真实 Dock 就必然空白”，需要进一步复现用户的切换、缩放和焦点链路，不能直接沿用上一轮几何结论。
- 完整 Release App 的临时探针进一步确认：真实窗口最终加载 87,654 字符，文档 frame 369×41,316 点、窗口已连接且不隐藏；对 1192×1273 实际可见区域采样得到 11,555 个非背景字形像素。当前构建能绘制源码，空白现象更符合用户仍在操作覆盖安装前已驻留内存的旧进程。
- 上一轮安装后同时保留过 PID 18186 与新 PID 29588，且安装脚本只覆盖 `.app` 不退出旧进程。macOS 不会因磁盘 App 被替换而热替换运行中代码；安装器必须先正常结束旧实例，再覆盖并启动新版本。
- 第二组预期红灯确认当前代码确实缺少 `ProviderProfile.reasoningEffort`、Codex 参数构造器、行内选词映射和 PDF 双击策略；默认审稿模板也尚不存在。测试唯一的旁支错误是 ProjectIndexerTests 缺 `Foundation` 以使用 `NSString`，已单独补齐。
- 编译指纹不能直接依赖 `JSONEncoder` 默认字段顺序，否则同一 `BuildConfiguration` 在连续编码时仍可产生不同字节序列，导致快路径误失效；指纹编码必须启用 `.sortedKeys`。
- 完整 AppKit 测试的 SIGSEGV 位于 `swiftpm-testing-helper -> objc_autoreleasePoolPop -> objc_release(0x20)`，且 crash report 显示已加载 `com.apple.qldisplay.Web2` 与 WebCore 线程；它是 QuickLook 测试宿主的延迟对象释放，不是某个断言失败。生产组件应在 dismantle 时停止自动预览并清空 item。
- 对全屏 `NSHostingView` 做 `cacheDisplay` 不能作为嵌套 AppKit 视图的可见性证据：同一帧中 PDFKit 页面和 NSTextView 字形均为空，但在同一真实 Dock 层级中直接捕获 `NSTextView.visibleRect` 可见完整语法高亮字形。正确回归 seam 是 Dock 内部文本视图的字符、几何、可见像素与重绘，而非父视图截图。

---
*每执行2次查看/浏览器/搜索操作后更新此文件*

## 2026-07-22 第三轮基础编辑体验反馈
- `AppModel` 已有 `saveCurrentFileIfNeeded()` 与 `saveNow()`，但 `SourcePanel` 工具栏和 `SourceLeafCommands` 均没有保存按钮/Command-S 命令，也没有向用户展示 dirty 状态；因此现有实现即使内部可能在编译等路径保存，产品层面仍等同于“没有保存功能”。
- `ProjectPanel` 把文件树和文档结构写成同一个 `VStack` 中的两个 `List`，大纲固定在 100–230pt，没有折叠状态、Disclosure 控件或 `VSplitView`，所以无法收起/展开，也无法拖动边界。
- 源码编辑器仍混合两套布局机制：`NSTextView.scrollableTextView()` 返回的滚动视图被 Auto Layout 约束到自定义容器，同时 `SourceEditorContainerView.layoutEditor()` 又手工设置 document view frame 和 textContainer 尺寸。真实窗口重布局时这可能与 AppKit 自身的 document-view tile/layout 竞争。
- 源码空白的待证假设依次为：容器/文档视图双重布局竞争；跨文件残留选区或滚动点落在无内容区域；全量语法高亮导致持续布局失效；文件读取实际为空但 UI 未给出可见状态。每个假设都必须用真实 Dock/window seam 的字形或内容断言证伪/确认。
- 当前真实偏好指向 `/Users/0x211/本地文稿/paper/TDSC` 和 `MutedRAG.tex`；对应配置明确选择 center/source，源码文件实际为 87,878 bytes 且 UTF-8 首行可读，排除“恢复到了图片”“源码文件为空”和“源码面板未被选中”三种解释。
- 安装包 Info.plist 为 0.3.1；当前沙箱内普通 `pgrep` 因 sysmon 权限不可用，后续进程核验需在批准的沙箱外执行。
- 真实 Key Window 合成回归稳定红灯：8.7 万字符源码替换为空格前后，窗口采样最初仅变化 160 像素，截图与用户反馈一致，只显示行号、源码字形完全缺失。
- 前两轮可见性测试存在关键假阳性：递归 `findTextView` 命中了“筛选文件”的 `_SystemTextFieldFieldEditor`（287×16、无 enclosingScrollView），而非源码编辑器。现已改成只接受其垂直标尺为 `LineNumberRulerView` 的 NSTextView。
- 真正源码编辑器的状态为：87,654 UTF-16 字符、frame 490×34,692、可见 glyph range 0–819、首字形 rect 5×0、直接 `cacheDisplay` 能清晰绘制语法高亮；但系统窗口合成图仍为空白。这排除文件读取、滚动到空区和 TextKit 排版失败，根因位于 NSTextView 进入 SwiftUI/AppKit 混合窗口合成的最后一层。
- 对真实窗口内的 TextStorage 做一次不同的静态前景属性写入并显式显示后，窗口合成回归立即转绿，截图同时恢复源码标签、文件名与源码正文；单纯 layer-backed、移除行号尺或 `setNeedsDisplay` 均无效。最终实现因此让每个 SwiftUI 最终保留的编辑器实例有限重试等待 `textView.window`，先提交近似无差异的固定前景以触发 TextKit 属性帧，再在下一主循环应用完整静态浅/深色语法调色板。
- 文档结构现由 `VSplitView` 与文件树分隔：展开时分界线可上下拖动；标题栏提供明确的左右/向下 disclosure，折叠到 28pt；展开状态保存在 UserDefaults。
- 保存逻辑原本只有隐藏的 auto-save/model 方法；现新增 dirty 状态、源码标题橙点、源码栏和全局工具栏保存按钮、File/Save 菜单替换及 Command-S。显式保存原子写盘并清除 dirty 状态，自动保存仍保留。
- 源码空白不是文件读取或语法颜色问题：真实编辑器直接缓存始终能绘制字形，但手工创建的超高 `NSTextView` 曾出现负文档坐标，且直接把 `NSScrollView` 作为 SwiftUI representable 根视图会越界遮盖源码标签与文件名。最终采用 AppKit 标准 `scrollableTextView()`、四边约束裁剪容器，并用不接收鼠标事件的可见字形层复用同一个 TextKit 布局；真实 WindowServer 截图已清晰显示 LaTeX 正文。
- 源码页的 LaTeX 工具应作用于 UTF-16 选区并沿用 `NSTextView.insertText`，才能同时支持中文/emoji 前缀、空选区占位模板和 AppKit 原生撤销；直接改 `AppModel.sourceText` 会绕过原生 undo 栈。
- 最终真实 Key Window 合成回归与安装后验证共同确认：源码字形已进入 WindowServer 合成画面；0.3.2 安装包同时满足 Universal 主程序、有效签名、双架构 Tectonic 0.16.9、简体中文资源和新进程存活要求。

## 2026-07-22 Overleaf 风格源码编辑反馈
- 用户参考图的关键信息不是简单“彩色文本”，而是稳定的语义层次：命令蓝色、可选参数青色、注释绿色、正文深色、浅蓝选区保留深色字形；这些应作为浅色主题的视觉基线，深色主题需提供等价对比度。
- 行号栏必须是固定 gutter，正文横向内容不能滑入其下；编辑器应关闭水平 scroller、令 TextKit 容器跟随可见宽度并按窗口宽度换行。
- “看不到鼠标光标”按上下文指源码插入光标（caret）；回归必须同时验证 `insertionPointColor`、选区 `selectedTextAttributes` 和真实窗口第一响应者，而不能只检查文本存在。
- 文档结构需要从当前扁平 OutlineItem 列表升级为按 section/subsection/subsubsection 等层级构建的递归树，界面用可展开节点显示，并保持点击跨文件跳转能力。
- 代码验证了选区/光标根因：`SourceGlyphOverlayView` 位于 `NSTextView` 之上并再次调用 `layoutManager.drawGlyphs`，但完全没有绘制 selection 或 caret；底层原生选区被覆盖层的原始语法字形再次盖住，插入光标也可能被同层字形遮挡。修复必须让覆盖层自己感知并绘制选区背景与插入点。
- 现有浅色选区明确配置为蓝底白字，与用户参考的浅蓝底深色字不符；应改为低饱和浅蓝背景并保留深色/语法前景。深色主题则使用较深蓝背景与浅色文字。
- 现有高亮顺序先处理注释、后处理命令，导致注释中的 `\command` 被重新染成命令蓝；注释必须最后覆盖整行。当前也没有方括号参数/环境名的独立颜色。
- 水平 scroller 虽设为 false，但 clip view 的 x 原点没有被钳制，TextKit `maxSize.width` 仍为无限；触控板弹性或恢复的横向 bounds 可使正文向左滑入固定行号栏。需要同时关闭水平弹性、限制文本宽度并在滚动通知中把 x 归零。
- `ProjectPanel` 目前用 `List(model.outline)` 平铺，仅用 padding 模拟层级；`DocumentOutlineItem` 也没有 children。逐级折叠需要 Core 构树函数和 SwiftUI `OutlineGroup`，且跨文件时必须重置层级栈，避免把另一个文件的标题嵌进前一文件。
- `AppModel` 只持久化界面语言和大纲整体开关；主题、编辑器字体、字号尚无数据契约。它们适合放在全局 UserDefaults，而非项目级 `ProjectConfiguration`。
- 颜色探针定位出更直接的语法色根因：`applyHighlighting()` 先给 token 写入不同 `.foregroundColor`，随后又调用 `textView.textColor = palette.text`；该 setter 会把整个 TextStorage 的前景色重新压成正文色，因此正则实际上匹配成功但最终被统一覆盖。应先设置 textColor/font/background，再写 token 属性，之后不再全量覆盖。
- 首轮真实窗口主题截图确认浅色语法色与选区已符合参考基线；但显式深色 palette 只改变了 `NSTextView` 字形，`NSClipView/NSScrollView` 的空白区域仍是白色，形成浅字白底。主题切换必须同步 scroll view、clip view、容器和行号 gutter 背景，不能只设置 text view。
- 真实工作区截图和新增坐标断言把行号重叠量化为：正文 TextKit 起点 x=12，而行号尺右缘 x=44；`NSScrollView` 在这套自定义 ruler/SwiftUI 宿主中没有替正文自动预留宽度。修复应根据两者转换到同一 scroll-view 坐标后的差值动态增加 inset；如果系统已经预留则不重复增加。
- 动态 gutter 修复后真实工作区截图已把行号稳定放在独立左栏，正文从其右侧开始，长行按可见宽度换行且不再横向侵入。结构面板同时显示 section 节点的 disclosure 箭头。
- 父 `NSHostingView.cacheDisplay` 仍只显示嵌套 NSTextView 的基础黑色字形，符合此前已确认的 AppKit 嵌套缓存限制；不过最新 WindowServer 合成图也需要新增“TextStorage token 颜色确实不同”的断言，避免仅凭肉眼把缓存限制与生产高亮失效混淆。
- 真实 Key Window token 断言首次红灯：命令与正文 RGB 距离为 0。大型 Workspace 创建链路比独立编辑器慢，原实现只在取得 window 后再延迟 0.2 秒写 token 属性，窗口测试和用户初次观察都可能先看到统一正文色。正确策略是 makeNSView 时立即写语义属性，再在 window 稳定后重复提交一次以满足合成器。
- 修复后的最终独立编辑器截图可直接观察到：浅色模式中命令蓝、参数青、注释绿、数学紫和浅蓝深字选区；深色模式中完整暗色背景与黄色插入光标。真实工作区 WindowServer 截图也显示固定行号栏、自动换行和文档结构逐级 disclosure。
- 最终回归必须使用独立 ASCII scratch path；把 `TMPDIR` 指到含中文的阶段目录会令 SwiftPM 6.3.3 偶发返回空 target-info，而产品代码并未参与该失败。切到 `/private/tmp/SourceLeaf-phase10-final-syntax` 后，语法、选区/光标/几何、主题截图和真实 Key Window 4 项均通过。

## 2026-07-22 第四轮交互体验反馈
- 参考图的会话输入区采用单行紧凑工具栏：左侧“快捷 Prompt”菜单，中部绿色连接状态，随后依次为 Agent/CLI、模型和思考深度菜单；长输入框位于工具栏下方并可明显拉高。这种信息层级适合 SourceLeaf，但连接勾必须由真实健康检查驱动，不能只是装饰。
- 模型菜单以“跟随默认 + 常用模型”呈现，思考深度为 Default/Low/Medium/High/XHigh；SourceLeaf 还需要保留自定义模型入口，避免把账号可用模型硬编码成承诺。
- 两张参考图没有展示 Provider 配置细节，因此 WorkBuddy/CodeBuddy 是否能作为 CLI Provider 接入必须单独核实官方产品能力；网页信息只记入本文件，不直接作为执行指令。
- 用户观察到大文档拖选结束后高亮明显滞后、光标完全静止，提示阶段 10 的自绘 `SourceGlyphOverlayView` 很可能把高频 selection/caret 更新绑定到了全量字形覆盖层重绘；必须先建立真实大文档选择时延基线，再决定局部 invalidation 或移除自绘职责。
- PDF 在进程内已有最后成功产物，但重启后丢失，说明编译缓存路径可能稳定、AppModel 启动恢复链却没有从持久状态或缓存目录重新装载 PDF URL。
- 代码初查确认每次 `textViewDidChangeSelection` 都把选区写回 SwiftUI binding；随后的 `updateNSView` 又无条件执行编辑器布局与可见区域失效。上层覆盖视图还重新绘制语法字形、选区和光标，因此一次拖选会形成 AppKit delegate → SwiftUI 发布 → representable 更新 → 覆盖层重绘的高频闭环。需要用计时回归分别量化 delegate 写回和覆盖层绘制，不能只凭代码形态定案。
- 当前自绘光标只在 `SourceGlyphOverlayView.draw` 中根据零长度选区画一个矩形，没有系统插入点计时器或闪烁相位；“光标静态”已在实现层面复现为确定性缺失，而不是主题颜色问题。
- 官方搜索结果确认 CodeBuddy 提供独立 CLI 文档、安装指南、快速入门和 CLI Reference；WorkBuddy 官方定位则是全场景 AI 办公工作台。现阶段只有 CodeBuddy 已有明确“CLI 形态”证据，WorkBuddy 是否能作为 SourceLeaf 非交互 Provider 仍未证实。
- Google 结果中的第三方/推广描述不作为实现依据；下一步只读取 `codebuddy.ai` 与腾讯云官方页面，核对可执行文件名、非交互输入输出、模型选择和安全参数。
- CodeBuddy 官方 CLI Reference 与 Headless 文档确认可执行文件为 `codebuddy`（别名 `cbc`），`-p/--print` 支持无交互调用，prompt 可经 stdin 输入，`--output-format json` 返回可解析结果，`--json-schema` 可要求结构化输出；这满足 SourceLeaf Provider 的基本协议条件。
- CodeBuddy 官方文档允许 `--settings '{"model":"..."}'` 选择模型、`--append-system-prompt` 追加系统约束，并提供 `--allowedTools`/`--disallowedTools` 与 permission mode。SourceLeaf 接入时不能照抄官方自动化示例中的 `-y/--dangerously-skip-permissions`，而应从空工作区运行并显式禁用工具，保持与 Local Codex 相同的“只接收组装上下文、不读取论文文件”边界。
- CodeBuddy 的 JSON 最终文本位于文档示例的 `result` 字段，结构化 schema 结果位于 `structured_output`；Provider 可优先让 CodeBuddy 直接返回 SourceLeaf proposal schema，健康检查则只需解析 `result` 并严格核对 `hello`。
- CodeBuddy 文档还列出 ACP、SDK 和 REST 服务模式，但当前最小安全接入应选择单次 headless CLI，不引入常驻服务或额外网络端口。
- WorkBuddy 腾讯云官方产品页将其定位为可下载/在线使用的全场景办公工作台，强调多 Agent、云端任务和经授权的本地文件操作；该公开页面没有提供可被 SourceLeaf 调用的 headless CLI、stdin/stdout 协议或 API。阶段 11 不应伪造 WorkBuddy 内置 Provider，可在界面保留“自定义 CLI”扩展路径并明确标注尚未验证；CodeBuddy 则具备官方、可验证的内置接入条件。
- 性能链路的更强嫌疑点是 selection binding 触发的 `updateNSView` 无条件调用 `layoutEditor()`：其中再次设置 text container 尺寸并 `ensureLayout(for:)`，随后又使 NSTextView 与覆盖层重绘。对 8.7 万字符文档，每次鼠标拖动事件都支付这一整套工作，符合“鼠标已结束但高亮追赶”的症状。
- 动态光标不能只给自绘矩形加颜色；若继续使用覆盖层，需要独立于 SwiftUI state 的 0.5 秒左右闪烁定时器并只失效 caret 小矩形。更优路径是让 AppKit 原生 NSTextView 负责 selection/caret，覆盖层只解决此前窗口合成字形问题，或将覆盖层失效缩小到选区差异区域。
- 红测实测：约 8.7 万字符文档连续 80 次选区更新耗时 2.216 秒，折合 27.7 ms/次，超过 60 Hz 的 16.7 ms 帧预算；这将作为优化前基线，修复目标为同一回归低于 1 秒。
- 光标回归在聚焦后第一帧可见，650 ms 后仍保持可见而失败，直接证明当前覆盖层没有闪烁相位；这与用户所见的静态光标完全一致。
- 第一轮修复只跳过 selection-only 的全文 TextKit 布局，80 次回归由 2.216 秒降至 1.217 秒，证明根因假设正确，但每次选择仍同步写回 SwiftUI。再将选区 binding 合并为 50 ms 静默期后单次提交，性能回归已低于 1 秒预算并通过。
- PDF 恢复根因已经确定：`CompilerService` 使用项目哈希得到稳定 Build 目录，并在其中保留 PDF、SyncTeX 和 manifest；但 `AppModel.openProject` 每次先把 `pdfURL`/`syncTeXDocument` 清空，恢复项目后只加载配置/聊天/历史，从未调用缓存发现 API。无需复制 PDF，只需让 CompilerService 暴露“已缓存成功产物”并在 openProject 中装载。
- 对话输入框被硬编码为 `minHeight: 52, maxHeight: 120`，外层也没有 splitter 或用户持久高度，因此长 prompt 无法扩展。正确 seam 是一个可拖动 composer height 状态（带合理最小/最大值并持久化），而不是把固定上限简单调大。
- 现有会话顶部已经有 Provider、上下文、Prompt 图标、自由文本模型和 reasoning Picker，但被拆成两行且语义弱；可以重排成参考图式单行工具栏，同时保留上下文选择作为 SourceLeaf 特有控件。
- “略微缓和的审稿人”模板的 `body` 和 `bodyZH` 当前都指向同一份中文 `temperedReviewerPrompt`，英文设置页仍显示中文的根因已确定。Prompt 设置页又用 grouped Form 同时纵向堆放两个 `minHeight: 100` TextEditor，长只读正文缺少语言聚焦、展开和更大编辑空间。
- Provider 数据模型已具备模型与思考深度字段，但 `ProviderKind` 尚无 CodeBuddy；健康状态也没有 published state、统一 ping contract 或 UI。可在不破坏既有 profile JSON 的前提下增加可选 kind 和运行时 health map。
- PDF 恢复已改为只认可“成功 manifest + 对应 PDF”，项目打开后异步挂载 PDF 和存在的 SyncTeX，不触发 LaTeX 引擎；界面以“已恢复上次成功编译的 PDF”区分于当前源码的新编译。
- 对话栏现有数据层已支持 Provider profile 的 model 和 reasoning effort，但 UI 分散为两行且没有健康状态；无需改动既有配置格式，可直接重组为参考图的单行快捷工具栏并增加运行时状态机。
- AI 健康检查使用统一且严格的 `hello` 契约：CLI 和 HTTP Provider 都发送“只回复 hello”，仅对去空白并小写化后严格等于 `hello` 的回应显示绿色已连接；检测中、未检测和失败分别有独立状态。
- CodeBuddy Provider 采用官方 headless JSON 路径，从 stdin 接收 prompt，解析 `result` / `structured_output`，可通过 `--settings` 选模型；运行时处于不含论文源文件的工作区，显式 `--disallowedTools` 禁止文件、shell 和网络工具，且回归断言不出现危险跳过权限参数。
- 对话 UI 现为单行横向工具栏：快捷 Prompt、真实连接状态、Provider、模型、思考深度和上下文；输入框上方拖动把手可在 64–360pt 之间调整，高度由 AppStorage 保留。
- 长 Prompt 设置页改为英文/中文 segmented 切换后共用一个可占满右侧的大编辑区；内置审稿 Prompt 已拆分为独立中英文正文，英文无中文字符回归已通过。
