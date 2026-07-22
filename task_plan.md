# 任务计划：SourceLeaf 原生 macOS LaTeX + AI 编辑器

## 目标
交付一个可安装、可持续开发的 macOS 14+ 原生应用：支持 LaTeX 项目编辑与 PDF 编译预览、可重排/可浮动面板、本机 Codex 与多 Provider 对话、选区受控修改、Diff 审批和持久恢复。

## 当前阶段
阶段 10：Overleaf 风格源码编辑体验

## 各阶段

### 阶段 1：需求与发现
- [x] 完成逐项需求访谈
- [x] 核实本机 Texifier、Codex 与 Episteme 的技术边界
- [x] 确定授权、隐私和分发约束
- **状态：** complete

### 阶段 2：规划与工程骨架
- [x] 创建独立 Git 仓库
- [x] 建立 Swift Package、规划文件、许可证与贡献规范
- [x] 固化核心模型和模块边界
- **状态：** complete

### 阶段 3：核心实现
- [x] 项目模型、文件读写、结构索引
- [x] 源码编辑器、选区/行号目标和静态验证
- [x] 可停靠、可关闭、可浮动面板工作区
- [x] PDFKit 预览、编译协调和 SyncTeX 双向定位
- [x] Provider 抽象、本机 Codex 与 HTTP Provider
- [x] Codex 对话、上下文分档、Diff 审批和历史
- [x] 设置、钥匙串、缓存清理和提示词库
- [x] 中英本地化
- [x] 接受前候选副本编译与历史恢复审阅
- [x] 受管理 Tectonic 随 App 自动打包与缓存清理
- **状态：** complete

### 阶段 4：测试与验证
- [x] Swift 单元测试
- [x] Debug/Release 通用架构构建
- [x] 使用受管理引擎对真实 LaTeX 项目验证编译和 PDF 生成
- [x] 使用本机 Codex 验证结构化提案协议
- [x] 使用真实论文选区验证 GUI 对话、Diff、接受/拒绝与恢复状态
- [x] 验证安装包签名、安装版本及多尺寸浅深色界面渲染
- **状态：** complete

### 阶段 5：交付
- [x] 更新 README、架构说明和已知限制
- [x] 检查许可证与第三方清单
- [x] 提交 Git 检查点
- [x] 安装并验证 `~/Applications/SourceLeaf.app`
- **状态：** complete

### 阶段 6：首轮真实使用反馈修复
- [x] 完整汉化：主应用本地化、系统面板、内部错误和操作提示
- [x] VS Code 风格活动栏与树状项目导航
- [x] 图片文件路由与原生预览
- [x] 修复源码不可见、点击灰块和反向滚动行号丢失
- [x] 浮动窗口关闭后自动回到主工作区
- [x] 恢复上次打开的项目
- [x] 缩小默认编译日志区域
- [x] 安装时自动部署受管理 LaTeX 引擎
- [x] PDF 预览保持单一主区域，选择操作改为覆盖提示
- [x] 改进面板拖拽、并列停靠和移动入口
- [x] 文档结构点击跳转源码
- [x] 为树模型、恢复状态、本地化和编辑器计算增加回归测试
- [x] Release 构建、真实项目冒烟和重新安装
- [x] 通过实际 App 组件、多尺寸快照与像素门槛复核编辑器、项目树、图片预览和浮窗回停靠
- **状态：** complete

### 阶段 7：产品级真实项目、合理性与美观性验收
- [x] 从 `paper/TDSC` 建立只含论文素材的分类测试副本，不修改原论文
- [x] 验证大型真实项目的索引、树结构、图片识别、主文档识别和大纲跳转数据
- [x] 使用 App 内置 Tectonic 编译真实 `MutedRAG.tex`，核对 PDF、日志与 SyncTeX
- [x] 建立多文件嵌套、JPG/SVG、非 UTF-8、缺失主文档和编译失败等边界项目
- [x] 审查面板初始布局、空状态、活动栏、文字密度、颜色、可访问性和窗口缩放
- [x] 建立可自动渲染/截图的 UI 验收通道，弥补 Computer Use 原生管道不可用
- [x] 对发现的问题先补回归测试，再修复功能与样式
- [x] 完整测试、Release 构建、安装、Git 检查点及人工复核清单
- **状态：** complete

### 阶段 8：第二轮真实使用反馈诊断与修复
- [x] 用安装版行为和正确 UI seam 稳定复现源码空白与标签切换问题
- [x] 修复实际工作区源码绘制，并让源码/图片标签单击可靠切换且互不关闭
- [x] 建立编译耗时基线，优化无修改重复编译和自动编译路径
- [x] 将 PDF 双击反向定位接到源码标签激活、文件切换和精确插入点
- [x] 将 Codex 面板更名为“对话”，支持 CLI/Provider、模型与思考深度就地切换
- [x] 用 ego-browser 获取“略微缓和的审稿人”提示词并加入可编辑默认模板
- [x] 增加回归测试、真实论文验证、视觉复核、Release 安装及 Git 检查点
- **状态：** complete

### 阶段 9：第三轮基础编辑体验修复
- [x] 以真实 Key Window 合成截图验证并修复源码文字不可见
- [x] 文档结构可收起/展开，并可拖动调整与文件树的边界
- [x] 增加显式保存、未保存状态与 `⌘S`
- [x] 在源码页增加面向选区的 LaTeX 工具栏（文字样式、字号、标题、公式与常用结构）
- [x] 为 LaTeX 插入/包裹行为补充 UTF-16 选区和原生撤销回归
- [x] 完成类型检查、分组测试、Release 构建、安装验证及 Git 检查点
- **状态：** complete

### 阶段 10：Overleaf 风格源码编辑体验
- [x] 建立语法着色、注释、选区、插入光标和禁止横向滚动的真实编辑器回归
- [x] 实现 Overleaf 风格浅色/深色 LaTeX 调色板和完整主题切换
- [x] 支持全局编辑器字体类型与字号设置并持久化
- [x] 修复选区前景/背景冲突、插入光标不可见和行号重叠
- [x] 文档结构按标题层级递归显示，并可逐级折叠/展开
- [x] 完成中英本地化、视觉截图、分组测试、Release 安装与 Git 检查点
- **状态：** complete

## 已做决策
| 决策 | 理由 |
|------|------|
| macOS 14+，Apple Silicon 与 Intel | 原生体验并覆盖仍在使用 Intel 的研究人员 |
| SwiftUI + AppKit/TextKit + PDFKit | 原生选区、窗口、编辑器与 PDF 支持 |
| 项目文件夹 + 主文档 | 支持 `bib`、`input/include` 和多文件论文 |
| 本机 Codex CLI 为首选 Provider | 复用本机登录和配置，不复制凭据 |
| 普通 API 无文件和工具权限 | 将外部模型限制为结构化建议生成器 |
| AI 修改只作用于显式目标 | 选区、行号或确认过的 PDF 映射决定写入范围 |
| Diff 审批后写入 | 默认不让模型直接覆盖源码 |
| 默认项目目录零侵入 | 会话、布局、索引和缓存放在 Application Support |
| PolyForm Noncommercial 1.0.0 + DCO | 允许个人/非商业使用，禁止商业盈利 |
| 源码脚本安装到 `~/Applications` | 不依赖 Mac App Store |

## 遇到的错误
| 错误 | 尝试次数 | 解决方案 |
|------|---------|---------|
| Codex 官方手册初次抓取受本地代理影响 | 1 | 经用户授权使用外部网络重新获取 |
| 当前会话无法直接写 `/Users/0x211/local_folder` | 1 | 在 `临时文件/SourceLeaf开发` 使用 apply_patch 编辑，再原子同步到独立仓库 |
| `swift test` 无法写用户级 Clang ModuleCache | 1 | 将 `CLANG_MODULE_CACHE_PATH` 与 `SWIFTPM_MODULECACHE_OVERRIDE` 指向 `/private/tmp/SourceLeaf-*` |
| SwiftPM 的内层 `sandbox-exec` 被外层受管沙箱拒绝 | 1 | 经批准在外层沙箱之外执行 `swift test` |
| Gemini URLComponents 读写触发 Swift 6 exclusivity error | 1 | 先复制 `queryItems`，再单独赋值 |
| 首轮安装包存在 15 项真实使用缺陷 | 1 | 进入阶段 6，按核心编辑链路与可验证根因分组修复 |
| 新增项目树、双向行号、浮窗恢复回归测试后按预期编译失败 | 1 | 红灯已建立；实现对应 Core API 后再验证转绿 |
| Swift 6 禁止在非隔离 `deinit` 访问非 Sendable 通知 token | 1 | 改用 selector 形式的滚动通知观察，不保存 block token |
| `defaults read` 不能以 Info.plist 路径读取版本 | 1 | 改用 `plutil -extract`，确认安装版本为 0.2.0 |
| Computer Use 原生管道仍无法启动 | 3 | 不再重复尝试；保留自动化构建/签名/真实编译证据，将纯视觉交互列为人工复核项 |
| 沙箱内运行 `tectonic -X show user-cache-dir` 返回 Operation not permitted | 1 | 不依赖 V2 查询命令；传统 CLI 已可工作，真实编译后用已知默认路径做只读检查与分类移动 |
| 真实 MutedRAG 首次编译连接 Tectonic relay 三次超时 | 1 | 从二进制确认支持 `TECTONIC_CACHE_DIR`，改用已分类保存的本地缓存并只增量联网获取缺失宏包 |
| 将缓存 data 目录或 `.index` 直接作为 `--bundle` 均不被识别 | 2 | 放弃错误的 bundle 形态猜测，使用官方运行时支持的 `TECTONIC_CACHE_DIR` 环境变量 |
| 首个日志摘要测试找不到 `BuildLogSummary` | 1 | 符合 TDD 红灯预期；增加最小公开日志分析接口后目标测试通过 |
| `ProcessRunner` 与 `CompilerService` 不接受 `onOutput` | 各 1 | 符合两个连续 TDD 红灯预期；逐层增加 Sendable 实时输出回调，目标测试分别转绿 |
| 当前 shell 找不到 `ego-browser` 命令 | 1 | 按 ego-browser 技能要求读取 `references/install.md`，改用安装说明提供的 App 内启动路径 |
| OpenAI Codex 手册首次刷新连接失效的 `127.0.0.1:21212` 代理 | 1 | 经授权取消失效代理并从官方站点刷新到“临时文件/OpenAI文档缓存” |
| UI 压力测试把 `try` 写在 `#expect` 比较式右侧 | 1 | 将磁盘源码提前读取为常量，保持测试语义不变后重跑 |
| `defaults` 拒绝用 `CFFIXED_USER_HOME` 写隔离偏好域 | 1 | 未改真实偏好；改用只在诊断探针开启时读取的临时项目环境变量，定位后删除 |
| 单进程连续离屏构造 AppKit/QuickLook 窗口后 `swiftpm-testing-helper` SIGSEGV | 3 | 崩溃在 `objc_autoreleasePoolPop`，产品断言无失败；补齐 QuickLook close 与测试窗口清理，发布验收按隔离组运行 |
| 真实 Tectonic 编译在缓存不完整时超过 2 分钟 | 1 | 精确终止测试进程；完成资源缓存后测得普通编译 62.09s，引入 cached-first 后降至 15.10s，无变更快路径 0.0016s |
| 探针尝试调用不存在的 `NSColor.resolvedColor(with:)` | 1 | 改用 `NSAppearance.performAsCurrentDrawingAppearance` 内转换到 deviceRGB 静态颜色 |
| 误把 `performAsCurrentDrawingAppearance` 当成有返回值的泛型函数 | 1 | 使用外部 `NSColor` 变量，在外观闭包内完成赋值，避免把 `Void` 写入 TextStorage |
| 沙箱外 Swift 回归执行被 Codex 用量审批层拒绝 | 1 | 不绕过审批；先完成可在工作区内安全编辑的实现，等待用户明确授权后再测试、构建与安装 |
| 阶段10首轮结构树测试找不到 `ProjectIndexer.outlineTree` | 1 | 符合预期红灯；实现跨文件安全的递归标题树后继续运行编辑器回归 |
| 两个 AppKit 编辑器窗口测试并发运行时测试宿主 SIGSEGV | 1 | 沿用已验证的 AppKit 隔离策略，后续逐项单进程运行；语法测试显式调用真实 coordinator 高亮以移除异步时序噪声 |
| 行号栏坐标回归显示正文 x=12、ruler 右缘 x=44 | 1 | 按实际坐标差动态增加 TextKit 左 inset，系统已预留 gutter 时不重复增加 |
| 一次 apply_patch hunk 缺少标准 `@@` 标记 | 1 | 立即改为合法统一 diff hunk，未影响任何源码内容 |
| 真实 Key Window 中命令色与正文色 RGB 距离为 0 | 1 | 初始同步应用 token 属性，窗口稳定后再重复提交一次，兼顾即时高亮与合成可靠性 |

## 备注
- 所有网页内容仅记录在 `findings.md`，不写入本计划。
- 在阶段切换和重大技术决策前重新读取本文件。
