# 2026 Claude Code 与 Codex 国内使用指南｜Clauddy 一键配置、模型更新与安全说明

*最后核对：2026 年 7 月 13 日*

<p align="center">
  <img src="https://cdn.prod.website-files.com/67ce28cfec624e2b733f8a52/6826a6227b1fbd47034d1936_claude-code.webp" alt="Claude Code、Codex 与 Clauddy 配置指南" width="600">
</p>

<p align="center">
  <a href="https://clauddy.com">Clauddy 控制台</a> ·
  <a href="https://github.com/clauddy/clauddy.github.io/blob/main/install.sh">在 GitHub 审阅 install.sh 源码</a> ·
  <a href="https://code.claude.com/docs/en/overview">Claude Code 官方文档</a> ·
  <a href="https://developers.openai.com/codex">Codex 官方文档</a>
</p>

> 本页依据 Anthropic 与 OpenAI 官方文档更新。模型、套餐、地区可用性和 Clauddy 分组倍率都可能变化，请以官方文档与 Clauddy 控制台实时显示为准。

## 2026 年 7 月重要更新

| 项目 | 当前信息 |
| --- | --- |
| Claude 模型 | Anthropic 当前列出 Claude Fable 5、Claude Opus 4.8、Claude Sonnet 5 与 Claude Haiku 4.5。复杂的 agentic coding 工作推荐从 Opus 4.8 开始；Fable 5 是能力最高的广泛发布型号。 |
| 上下文窗口 | Fable 5、Opus 4.8、Sonnet 5 为 1M tokens；Haiku 4.5 为 200K tokens。实际可用长度仍取决于模型、客户端和服务商。 |
| Opus 4.1 | 已被 Anthropic 标记为 deprecated，计划于 2026 年 8 月 5 日退役，不应再写成“最新模型”。 |
| Codex / GPT | OpenAI 当前推荐 GPT-5.6 系列；Codex 是可在 CLI、IDE、桌面与云端使用的完整 coding agent，不只是代码补全或单文件生成器。 |
| 安装方式 | Claude Code 与 Codex CLI 都提供官方独立安装器；新用户不必再把 Node.js + npm 当作首选安装路径。 |

## Claude Code 与 Codex 分别是什么？

### Claude Code

Claude Code 是 Anthropic 的 agentic coding 工具。它可以读取项目、修改文件、运行命令、调试、审查代码，并在终端、IDE、桌面应用和 Web 场景中工作。它并不固定“基于某一个模型”；默认模型和可选模型会随账号、套餐、客户端版本及 API 服务商变化。

### Codex

Codex 是 OpenAI 的 coding agent。Codex CLI 在本机项目中运行，也可通过 IDE、桌面应用和 Codex Web 使用。它适合跨文件实现功能、定位问题、执行测试、代码审查和较长时间的工程任务。

### 怎么选择？

| 需求 | 建议 |
| --- | --- |
| 更偏 Claude 模型、长上下文与复杂代码库工作 | 从 Claude Code 开始 |
| 更偏 GPT 模型、OpenAI 工具链与本地/云端协作 | 从 Codex 开始 |
| 想按任务切换模型或客户端 | 使用独立令牌，或选择 Clauddy Unified 分组 |
| 涉及商业机密或敏感代码 | 优先使用组织批准的官方或自托管方案，并先确认数据政策 |

两者都是持续更新的工程代理，适合用实际项目、相同任务和相同验收标准做测试，而不是依赖固定星级或笼统的“谁更强”结论。

## 快速开始

### 1. 安装官方客户端

Claude Code（macOS、Linux、WSL）：

~~~bash
curl -fsSL https://claude.ai/install.sh | bash
claude --version
claude doctor
~~~

Codex CLI（macOS、Linux）：

~~~bash
curl -fsSL https://chatgpt.com/codex/install.sh | sh
codex --version
~~~

然后进入项目目录并启动对应客户端：

~~~bash
cd your-project
claude

# 或
codex
~~~

官方 Claude Code 当前要求 Pro、Max、Team、Enterprise 或 Console 账号，且受支持地区限制；Codex 可以使用符合条件的 ChatGPT 账号，也可以配置 API Key。具体资格以各自官方页面为准。

### 2. 使用 Clauddy 一键配置

仓库根目录的 <code>install.sh</code> 是双语、菜单式交互配置向导，当前版本为 <code>0.4.0</code>。默认 API base URL 为 <code>https://api.clauddy.com</code>；控制台与 API 密钥管理仍使用 <code>https://clauddy.com</code>。运行前可以先在 [GitHub 查看并审阅完整脚本源码](https://github.com/clauddy/clauddy.github.io/blob/main/install.sh)，再下载执行：

~~~bash
curl -fsSL https://docs.clauddy.com/install.sh \
  -o /tmp/clauddy-install.sh

less /tmp/clauddy-install.sh
bash /tmp/clauddy-install.sh
~~~

可信环境下也可以直接运行：

~~~bash
curl -fsSL https://docs.clauddy.com/install.sh | bash
~~~

> **Windows PowerShell / CMD:** `install.sh` 是 Bash 脚本，不能直接在 PowerShell 或 CMD 中运行。如果已安装 WSL，请打开 Ubuntu/WSL 终端后再执行上面的命令（脚本只配置 WSL 环境）；也可以在 PowerShell 中调用 `wsl.exe bash -lc "curl -fsSL https://docs.clauddy.com/install.sh | bash"`。如果要在 Windows 原生终端运行客户端，或没有 WSL，请按各客户端的 Windows 手动配置教程操作。

英文界面：

~~~bash
bash /tmp/clauddy-install.sh --lang en
~~~

该脚本会：

- 检测 Claude Code、Codex CLI、Gemini CLI、OpenClaw 和 Hermes agent；缺少客户端时可在确认后调用官方安装方式。
- 通过菜单选择一个或多个客户端，并可在运行中切换中文或英文界面。
- 根据客户端推荐专用 API 密钥分组，也可使用一个 Unified 密钥，并可复用本次已验证的密钥。
- 修改配置前创建带时间戳的备份。
- 写入对应的 base URL 与 API 密钥配置，并在每个客户端完成后提示启动命令。
- 调用 <code>/v1/models</code> 验证密钥、可用模型数量和接口延迟。
- 连续验证失败时，可选择执行一次有界的 AI 诊断；这会消耗少量额度，只返回建议，不自动执行修复。

如需连接自托管或测试网关，可使用 <code>--base-url</code> 覆盖 API 地址；如 API 与控制台不在同一主机，可另外使用 <code>--console-url</code> 指定控制台地址。

## Clauddy 当前分组说明

以下倍率来自安装脚本中 2026 年 7 月 12 日同步的生产分组信息。控制台实时显示始终具有更高优先级。

| 分组 | 适用客户端 | 脚本记录倍率 |
| --- | --- | ---: |
| Claude | Claude Code 专用 | 1.4x |
| OpenAI | Codex 专用 | 0.5x |
| Gemini | Gemini CLI 专用 | 1.8x |
| Claude3p | 不限制 Claude 客户端类型 | 1.8x |
| ClaudeAPI | Claude 官方 Key 转发 | 5.0x |
| Unified | Claude、Codex、Gemini 及常驻 agent | 1.8x |

如果只配置一个客户端，专用分组通常更省；如果需要多个客户端共用一把 key，Unified 更方便。OpenClaw、Hermes 等常驻 agent 不应使用仅接受 Claude Code 客户端的 Claude 分组。

## 脚本会修改哪些文件？

按你的选择，脚本可能修改：

| 客户端 | 配置位置 |
| --- | --- |
| Claude Code | <code>~/.claude/settings.json</code> |
| Codex | <code>~/.codex/config.toml</code> 与 <code>~/.clauddy/env</code> |
| Gemini CLI | <code>~/.gemini/.env</code> |
| Shell 环境 | <code>~/.zshrc</code>、<code>~/.bashrc</code> 或 <code>~/.profile</code> |

已有文件会先备份为 <code>.bak.&lt;时间戳&gt;</code>。令牌属于敏感凭据，不要提交到 Git、粘贴到 Issue、截图或发送给无关人员。

## 手动配置 Claude Code

如果不使用向导，可以在当前终端临时设置：

~~~bash
export ANTHROPIC_BASE_URL="https://api.clauddy.com"
export ANTHROPIC_AUTH_TOKEN="你的 Clauddy 令牌"

claude
~~~

临时环境变量只对当前 shell 生效。需要持久化时，优先使用客户端支持的配置文件，并确保文件权限和备份符合你的安全要求。

## 如何判断网关是否适合自己？

Claude Code、Codex 等是官方客户端；Clauddy 是独立的第三方统一 AI API 网关，两者不是同一层产品。选择任何中转或网关服务前，建议检查：

1. 模型列表是否返回明确的模型 ID，是否与控制台说明一致。
2. 计费单位、分组倍率、余额和用量记录是否可核对。
3. 隐私政策、日志保留、数据处理区域和客服渠道是否满足要求。
4. 是否支持令牌撤销、额度限制和独立客户端令牌。
5. 是否允许先用非敏感代码和小额度进行稳定性测试。

使用第三方网关意味着请求会经过该服务。不要把“使用官方客户端”误解为“流量只经过模型厂商”。

## 常见问题

### Claude Code 还需要 Node.js 18+ 吗？

官方当前推荐原生安装器，macOS、Linux 和 WSL 的首选路径不再要求先安装 Node.js。Homebrew、WinGet 和 Linux 软件包管理器也是官方文档列出的选项。

### Claude Code 固定使用 Opus 吗？

不固定。当前模型别名、默认值和可用模型会变化，也受账号与 API 服务商影响。运行客户端时应查看实际模型选择，而不是依赖旧教程。

### 上下文窗口到底是 200K 还是 1M？

取决于模型。当前 Fable 5、Opus 4.8 与 Sonnet 5 的官方模型表列出 1M；Haiku 4.5 列出 200K。网关或客户端还可能设置自己的限制。

### 如何检查安装是否正常？

Claude Code 可运行 <code>claude --version</code> 和 <code>claude doctor</code>；Codex 可运行 <code>codex --version</code>。Clauddy 配置向导还会实际请求 <code>/v1/models</code> 检查连通性。

### 一个令牌能否同时用于 Claude Code 和 Codex？

可以选择 Unified 分组共用一把 key；也可以分别创建 Claude 与 OpenAI 专用令牌以降低倍率并方便单独撤销。以控制台当前可选分组为准。

### “Claude 镜像”或“Claude 中转”一定安全吗？

不能只凭名称判断。应重点核对运营主体、数据政策、模型透明度、计费记录、令牌管理和故障处理。敏感项目应遵循所在组织的安全与合规要求。

## 官方资料

- [Anthropic：Claude models overview](https://platform.claude.com/docs/en/about-claude/models/overview)
- [Anthropic：Claude Code setup](https://code.claude.com/docs/en/setup)
- [Anthropic：Claude Code model configuration](https://code.claude.com/docs/en/model-config)
- [OpenAI：Using GPT-5.6](https://developers.openai.com/api/docs/guides/latest-model)
- [OpenAI：Codex documentation](https://developers.openai.com/codex)
- [OpenAI：Codex CLI repository](https://github.com/openai/codex)

---

<p align="center">
  <strong><a href="https://clauddy.com">打开 Clauddy 控制台</a></strong><br>
  <sub>Claude Code · Codex · Gemini CLI · Unified AI API gateway</sub>
</p>

<p align="center">
  <sub>Clauddy 是独立第三方服务；本页不代表 Anthropic 或 OpenAI 官方立场。产品名称与商标归各自权利人所有。</sub>
</p>
