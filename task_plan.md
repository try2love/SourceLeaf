# 任务计划：SourceLeaf 原生 macOS LaTeX + AI 编辑器

## 目标
交付一个可安装、可持续开发的 macOS 14+ 原生应用：支持 LaTeX 项目编辑与 PDF 编译预览、可重排/可浮动面板、本机 Codex 与多 Provider 对话、选区受控修改、Diff 审批和持久恢复。

## 当前阶段
阶段 6：首轮真实使用反馈修复

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
- [ ] PDFKit 预览、编译协调和 SyncTeX（预览与协调已完成；SyncTeX 待完成）
- [x] Provider 抽象、本机 Codex 与 HTTP Provider
- [x] Codex 对话、上下文分档、Diff 审批和历史
- [x] 设置、钥匙串、缓存清理和提示词库
- [x] 中英本地化
- [x] 接受前候选副本编译与历史恢复审阅
- [ ] 受管理 Tectonic 下载和清理界面
- **状态：** in_progress

### 阶段 4：测试与验证
- [x] Swift 单元测试
- [x] Debug/Release 通用架构构建
- [x] 使用受管理引擎对真实 LaTeX 项目验证编译和 PDF 生成
- [x] 使用本机 Codex 验证结构化提案协议
- [ ] 使用本机 Codex 验证 GUI 选区到 Diff 再到接受/撤销
- [x] 验证安装包签名和安装版本（自动化 GUI 管道不可用，交互视觉仍需人工复核）
- **状态：** in_progress

### 阶段 5：交付
- [x] 更新 README、架构说明和已知限制
- [x] 检查许可证与第三方清单
- [x] 提交 Git 检查点
- [x] 安装并验证 `~/Applications/SourceLeaf.app`
- **状态：** in_progress

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
- [ ] 真实 GUI 人工复核编辑器、树展开、图片预览和浮窗回停靠
- **状态：** complete（代码与安装完成；视觉交互待人工复核）

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

## 备注
- 所有网页内容仅记录在 `findings.md`，不写入本计划。
- 在阶段切换和重大技术决策前重新读取本文件。
