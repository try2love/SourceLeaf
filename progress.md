# 进度日志

## 会话：2026-07-22

### 阶段 1：需求与发现
- **状态：** complete
- 执行的操作：
  - 完成平台、编辑权限、项目模型、编译、Provider、提示词、布局、隐私、发布与许可证访谈。
  - 检查 Texifier 扩展接口、Codex 官方接口和 Episteme 工程结构。
- 创建/修改的文件：
  - 无产品文件；形成已确认的设计决策。

### 阶段 2：规划与工程骨架
- **状态：** complete
- 执行的操作：
  - 在 `/Users/0x211/local_folder/SourceLeaf` 初始化独立 Git 仓库。
  - 建立可删除的分类编辑镜像 `临时文件/SourceLeaf开发`。
  - 创建持久化计划文件。
  - 建立 Swift Package、Core/App 分层、正式许可证、DCO、贡献规范和安装脚本。
- 创建/修改的文件：
  - `task_plan.md`
  - `findings.md`
  - `progress.md`

### 阶段 3：核心实现
- **状态：** in_progress
- 执行的操作：
  - 完成项目发现、主文档推断、源码读写、结构大纲和上下文分档。
  - 完成带行号与语法着色的 AppKit 源码编辑器、选区浮动按钮、行号目标解析和过期目标保护。
  - 完成四区停靠、标签切换、拖放换区、关闭和独立窗口。
  - 完成 PDFKit 预览、最后成功 PDF 保留、编译日志和自动编译防抖。
  - 完成本机 Codex、OpenAI、兼容接口、Anthropic、Gemini、Ollama、LM Studio Provider。
  - 完成上下文只读隔离、结构化提案、并排 Diff、静态检查、接受/拒绝/继续调整和持久历史。
  - 完成 Keychain、缓存清理、内置提示词以及英文/简体中文界面。
  - 根据实际冒烟反馈补充应用内“跟随系统/English/简体中文”即时切换，并实现自定义提示词的新增、复制、编辑、启停、删除与全局持久化。
- 尚未完成：
  - SyncTeX 双向定位、接受前候选副本编译、历史一键恢复、受管理 Tectonic 下载界面、自定义 CLI 安全启用。

### 阶段 4：测试与验证
- **状态：** in_progress
- 执行的操作：
  - Debug 构建和 16 个测试通过（其中本机 Codex 联调测试默认按环境变量关闭）。
  - 本机 Codex 真实协议联调通过。
  - Release `.app` 已构建为 `arm64 + x86_64` 通用二进制，并通过 ad-hoc 签名验证。

## 测试结果
| 测试 | 输入 | 预期结果 | 实际结果 | 状态 |
|------|------|---------|---------|------|
| Swift 工具链 | `swift --version` | Swift 可用 | Swift 6.3.3 arm64 | 通过 |
| Xcode 工具链 | `xcode-select -p` | 完整 Xcode | `/Applications/Xcode.app/Contents/Developer` | 通过 |
| Core 单元测试 | `swift test` | 所有测试通过 | 15/15 通过；新增隔离试编译测试单独通过 | 通过 |
| 本机 Codex 联调 | 启用 `SOURCELEAF_RUN_CODEX_TEST=1` | 返回合法结构化提案 | 1/1 通过，8.851 秒 | 通过 |
| Release 通用构建 | `scripts/build-app-bundle.sh` | arm64 + x86_64 `.app` | 两种架构，签名验证通过 | 通过 |

## 错误日志
| 时间戳 | 错误 | 尝试次数 | 解决方案 |
|--------|------|---------|---------|
| 2026-07-22 | 官方手册请求被失效本地代理阻断 | 1 | 授权后直接联网成功 |
| 2026-07-22 | `swift test` 写入 `~/.cache/clang/ModuleCache` 被沙箱拒绝 | 1 | 改用 `/private/tmp/SourceLeaf-*` 任务专用缓存 |
| 2026-07-22 | SwiftPM 内层 `sandbox-exec` 无法在受管沙箱运行 | 1 | 授权后在外层沙箱外运行测试 |
| 2026-07-22 | `URLComponents` 可选链同时读写违反 Swift 6 exclusivity | 1 | 拆分读取与写入 |
| 2026-07-22 | UI 首次编译时测试文件缺少 `Foundation`，编辑器浮点类型推断歧义 | 1 | 补充导入并显式使用 `CGFloat.greatestFiniteMagnitude` |
| 2026-07-22 | Computer Use 原生管道无法启动，未能自动截图检查 UI | 2 | 保留签名、架构、资源和进程存活验证；视觉交互留给人工冒烟测试 |
| 2026-07-22 | 中文资源存在但只能跟随系统语言；提示词页只有启停开关 | 1 | 改为运行时语言 Bundle 选择和动态文案；新增完整提示词 CRUD 与持久化 |

## 五问重启检查
| 问题 | 答案 |
|------|------|
| 我在哪里？ | 阶段 2：规划与工程骨架 |
| 我要去哪里？ | 核心实现、测试验证、安装交付 |
| 目标是什么？ | 交付可安装的 SourceLeaf 原生 macOS 应用 |
| 我学到了什么？ | 见 findings.md |
| 我做了什么？ | 已完成需求收敛、研究和仓库初始化 |
