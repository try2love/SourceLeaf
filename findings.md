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

## 资源
- Codex command reference: https://learn.chatgpt.com/docs/developer-commands.md?surface=cli
- PolyForm Noncommercial 1.0.0: https://polyformproject.org/licenses/noncommercial/1.0.0
- Open Source Definition: https://opensource.org/osd
- Developer Certificate of Origin: https://developercertificate.org/

## 视觉/浏览器发现
- `TeXloom`、`Syntaxis`、`Scholion` 等候选名称已有活跃产品，最终选择 `SourceLeaf`。

---
*每执行2次查看/浏览器/搜索操作后更新此文件*
