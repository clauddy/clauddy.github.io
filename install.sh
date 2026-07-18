#!/usr/bin/env bash
# =============================================================================
#  Clauddy 一键接入脚本 / Clauddy one-click setup  (clauddy-setup)
#
#  用法 / Usage:
#    curl -fsSL https://docs.clauddy.com/install.sh | bash
#    bash install.sh [--base-url https://api.clauddy.com] \
#                    [--console-url https://clauddy.com] [--lang zh|en] [--yes]
#  Windows PowerShell/CMD users: run this Bash script inside WSL, or follow the
#  Windows manual setup guide at https://docs.clauddy.com/cli/claude-code.
#
#  URL 说明 / URLs: API 走 --base-url (默认 https://api.clauddy.com);
#  控制台/密钥页走 --console-url (默认 https://clauddy.com)。自定义 --base-url
#  而未给 --console-url 时, 控制台跟随 base-url (单主机部署/测试场景)。
#
#  功能 / What it does:
#    1. 菜单式选择客户端 (Claude Code / Codex / Gemini CLI / OpenClaw /
#       Hermes agent), 可随时切换中英文界面
#    2. 未安装的客户端可按各官方安装方式现场安装 (安装前须确认);
#       npm 类客户端 (Codex/Gemini) 缺少 Node.js 时, 可自动安装官方 LTS
#       到 ~/.clauddy/node — 仅当前用户、无需 sudo、SHA256 校验;
#       已有的 Node.js 一律不动 (低于 18 只提示手动升级, 绝不自动升级)
#    3. 指引创建 API 密钥并校验 (实测 /v1/models, 报告可用模型数与延迟)
#    4. 自动写入 base_url + api_key 到各客户端配置 (写前备份)
#    5. 每个客户端配置完成后提示启动命令; 校验失败时可选「AI 诊断」:
#       用已验证的密钥向网关发一次有界诊断调用, 只输出建议, 不执行任何操作
#    6. 结束时汇总本次仍未装好的客户端 — 配置已写入, 手动安装后重跑
#       本脚本即可从中断处继续
#
#  除各客户端官方安装源与 nodejs.org (Node.js 官方二进制) 外, 只与
#  $BASE_URL 通信, 不上传任何数据到其他地址。写过的文件都有 .bak 备份。
#  Talks only to $BASE_URL (plus the clients' official install sources and
#  nodejs.org for official Node.js binaries); never uploads anything
#  elsewhere. All modified files are backed up first.
# =============================================================================
set -u

VERSION="0.5.1"
BASE_URL="https://api.clauddy.com"
CONSOLE_URL=""        # default: https://clauddy.com; follows --base-url when customized
CONSOLE_KEYS_URL=""   # derived: $CONSOLE_URL/keys
ASSUME_YES=0
UI_LANG="zh"          # 默认中文 / Chinese by default; --lang en or menu item 6
STAMP="$(date +%Y%m%d%H%M%S)"

# ---- 分组约定 / group taxonomy (synced with production UserUsableGroups, 2026-07-18)
#   Claude    1.0x  Claude Max 订阅转发, 仅 Claude Code 客户端 / CC clients only
#   Claude3p  1.2x  Claude Max, 不限制客户端 / any client
#   ClaudeAPI 5.0x  Claude 官方 Key 转发, 不限制客户端 / any client
#   OpenAI    0.5x  Codex Pro 专用 / Codex only
#   Gemini    1.8x  Gemini Ultra 专用 / Gemini only
#   Unified   1.8x  Claude / Codex / Gemini 全可用 / one key for all models
# 倍率以控制台实时显示为准 / ratios: console display is authoritative.

# ---- 官方安装方式 / official install methods (2026-07)
#   Claude Code:  curl -fsSL https://claude.ai/install.sh | bash
#   Codex CLI:    brew install codex            | npm install -g @openai/codex
#   Gemini CLI:   brew install gemini-cli       | npm install -g @google/gemini-cli
#   OpenClaw:     curl -fsSL https://openclaw.ai/install.sh | bash
#   Hermes agent: curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash
#   Node.js:      https://nodejs.org/dist official LTS tarball -> ~/.clauddy/node
#                 (npm 依赖缺失时的兜底, 用户级安装 / user-local fallback)

# ----------------------------------------------------------------------------
C_RESET=$'\033[0m'; C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'; C_RED=$'\033[31m'; C_BOLD=$'\033[1m'
ok()   { printf '%s✓%s %s\n' "$C_GREEN" "$C_RESET" "$1"; }
warn() { printf '%s!%s %s\n' "$C_YELLOW" "$C_RESET" "$1"; }
err()  { printf '%s✗ %s%s\n' "$C_RED" "$1" "$C_RESET" >&2; }
say()  { printf '%s\n' "$1"; }
hr()   { printf '%s\n' "----------------------------------------------------------------"; }

while [ $# -gt 0 ]; do
  case "$1" in
    --base-url)
      [ "$#" -ge 2 ] && [ -n "$2" ] || { err "--base-url requires a URL"; exit 2; }
      BASE_URL="$2"; shift 2 ;;
    --base-url=)     err "--base-url requires a URL"; exit 2 ;;
    --base-url=*)    BASE_URL="${1#*=}"; shift ;;
    --console-url)
      [ "$#" -ge 2 ] && [ -n "$2" ] || { err "--console-url requires a URL"; exit 2; }
      CONSOLE_URL="$2"; shift 2 ;;
    --console-url=)  err "--console-url requires a URL"; exit 2 ;;
    --console-url=*) CONSOLE_URL="${1#*=}"; shift ;;
    --lang)
      [ "$#" -ge 2 ] && [ -n "$2" ] || { err "--lang requires zh or en"; exit 2; }
      UI_LANG="$2"; shift 2 ;;
    --lang=)      err "--lang requires zh or en"; exit 2 ;;
    --lang=*)     UI_LANG="${1#*=}"; shift ;;
    --yes|-y)     ASSUME_YES=1; shift ;;
    --help|-h)
      say "Usage: bash install.sh [--base-url URL] [--console-url URL] [--lang zh|en] [--yes]"
      say "Windows PowerShell/CMD users: run this script inside WSL."
      exit 0 ;;
    --version)    say "clauddy-setup $VERSION"; exit 0 ;;
    *) err "Unknown argument / 未知参数: $1"; exit 1 ;;
  esac
done
BASE_URL="${BASE_URL%/}"
if [ -z "$CONSOLE_URL" ]; then
  case "$BASE_URL" in
    https://api.clauddy.com) CONSOLE_URL="https://clauddy.com" ;;
    *) CONSOLE_URL="$BASE_URL" ;;
  esac
fi
CONSOLE_URL="${CONSOLE_URL%/}"
CONSOLE_KEYS_URL="$CONSOLE_URL/keys"
case "$UI_LANG" in zh|en) ;; *) err "Unsupported --lang: $UI_LANG (zh|en)"; exit 1 ;; esac

# ---- 文案目录 / message catalog (reloadable — menu item 6 switches language) ---
load_msgs() {
if [ "$UI_LANG" = "en" ]; then
  MSG_ERR_NOTTY="Cannot open a terminal for interaction (/dev/tty unreadable). Download and run locally: bash install.sh"
  MSG_ERR_OS="Unsupported OS: %s. install.sh requires Bash on macOS/Linux; on Windows run it inside WSL or follow the manual setup guide at https://docs.clauddy.com/cli/claude-code."
  MSG_ERR_NEED_CURL="curl is required, please install it first."
  MSG_HDR="Clauddy Setup Wizard v%s  (%s, gateway: %s)"
  MSG_MENU_TITLE="Which client do you want to install/configure? (numbers, space-separated for several, e.g.: 1 2)"
  MSG_MENU_AGAIN="Install/configure another client? (enter numbers to continue, 0 to finish)"
  MSG_MENU_LANG="中文 (switch language)"
  MSG_MENU_EXIT="Exit"
  MSG_TAG_INSTALLED=" [installed]"
  MSG_TAG_MISSING=" [not installed]"
  MSG_DAEMON_TAG="always-on agent"
  MSG_WARN_BAD_NUM="ignoring invalid input: %s"
  MSG_ERR_NO_CLIENT="Nothing selected — enter a number from the menu."
  MSG_NOT_INSTALLED="%s is not installed yet."
  MSG_INSTALL_ASK="Install it now? Official method: %s  [Y/n] "
  MSG_INSTALLING="Installing %s …"
  MSG_INSTALL_OK="%s installed"
  MSG_INSTALL_FAIL="%s install FAILED (exit %s) — continuing with configuration."
  MSG_INSTALL_SKIP="Skipping install — configuration will still be written (works as soon as you install it)."
  MSG_PATH_HINT="If the command is not found afterwards, open a new terminal and try again."
  MSG_RERUN_HINT="Install it manually, then rerun this script — it picks up where it left off."
  MSG_CFG_ONLY="%s is configured, but the command itself is NOT installed yet — install it manually, then open a new terminal and it will work."
  MSG_NODE_MISSING="%s needs Node.js 18+ (with npm), which was not found on this system."
  MSG_NODE_ASK="Install Node.js LTS (%s) to ~/.clauddy/node now? (official nodejs.org binary, current user only, no sudo)  [Y/n] "
  MSG_NODE_TOO_OLD="Found Node.js %s (older than 18). To avoid breaking your existing environment it will NOT be upgraded automatically — upgrade it yourself, then rerun this script."
  MSG_NODE_INSTALLING="Downloading Node.js %s (%s) from nodejs.org …"
  MSG_NODE_OK="Node.js %s ready at %s (new terminals load its PATH via ~/.clauddy/env)"
  MSG_NODE_FAIL="Node.js auto-install FAILED: %s"
  MSG_NODE_FAIL_HINT="Install Node.js 18+ manually (https://nodejs.org), then rerun this script — it picks up where it left off."
  MSG_NODE_R_ARCH="unsupported CPU architecture: %s"
  MSG_NODE_R_MUSL="musl-based system (e.g. Alpine) — official binaries need glibc"
  MSG_NODE_R_SHA="sha256sum/shasum not found, cannot verify the download"
  MSG_NODE_R_DL="download failed (%s)"
  MSG_NODE_R_SUM="checksum mismatch — the downloaded file was removed"
  MSG_NODE_R_TAR="extract failed (tar required)"
  MSG_NODE_R_RUN="the installed node binary does not run on this system (glibc too old?)"
  MSG_FAILED_SUMMARY="NOT installed in this run: %s — their config is already written. Install them manually, then rerun this script to verify everything works."
  MSG_KEY_FOR="Set up the API key for %s:"
  MSG_KEY_STEP="  Open %s, create an API key (choose group %s), then paste it below."
  MSG_KEY_REUSE="  (a key was already validated in this run — just press Enter to reuse it)"
  MSG_PASTE="Paste your API key and press Enter (for security nothing shows on screen while you paste — that's normal): "
  MSG_ERR_EMPTY="Empty input."
  MSG_WARN_SK="API keys usually start with sk-, trying anyway…"
  MSG_ERR_3FAIL="Three validation failures in a row. Check: group is %s, balance > 0, key pasted completely."
  MSG_MENU_RETRY="Retry(r) / AI diagnosis(d, costs a little quota) / Skip this client(s) / Quit(q)? "
  MSG_MENU_HINT="Please enter r / d / s / q"
  MSG_ERR_NET="Network error, cannot reach %s"
  MSG_ERR_VERIFY="Validation failed (%s)"
  MSG_OK_KEY="key live — %s models available in this group, API latency %ss"
  MSG_SKIP_CLIENT="Skipped %s."
  MSG_DIAG_NEED_KEY="AI diagnosis needs at least one validated API key (none yet in this run). Please check group and key manually."
  MSG_DIAG_NEED_PY="AI diagnosis requires python3."
  MSG_DIAG_NO_MODEL="No usable model under the validated key, cannot diagnose."
  MSG_DIAG_CALLING="Calling %s with your validated key for diagnosis (advice only, executes nothing)…"
  MSG_DIAG_CTX="Client being configured: %s (recommended group: %s)
OS: %s
Gateway: %s
Validation failure: %s"
  MSG_BACKUP="  (original backed up: %s)"
  MSG_OK_CLAUDE="Claude Code: wrote %s (env.ANTHROPIC_BASE_URL / ANTHROPIC_AUTH_TOKEN)"
  MSG_WARN_NO_PY_CLAUDE="python3 not found, cannot merge JSON safely. Manually add to the env block of %s:"
  MSG_TAKEOVER="[clauddy-setup takeover]"
  MSG_OK_CODEX="Codex: wrote %s (provider=clauddy%s)"
  MSG_WARN_CODEX_MODEL="No codex model found in your model list; set model = \"…\" in %s manually"
  MSG_OK_GEMINI="Gemini CLI: wrote %s"
  MSG_OK_ENVFILE="Env file: wrote %s (chmod 600)"
  MSG_OK_RC="Added ~/.clauddy/env loading to %s (takes effect in new terminals)"
  MSG_READY_CLAUDE="Claude Code is ready — type %sclaude%s and press Enter to start."
  MSG_READY_CODEX="Codex is ready — open a NEW terminal, then type %scodex%s and press Enter to start."
  MSG_READY_GEMINI="Gemini CLI is ready — type %sgemini%s and press Enter to start."
  MSG_READY_DAEMON="%s is configured — open a new terminal, then type %s%s%s and press Enter to start."
  MSG_READY_DAEMON2="  Daemon mode: load ~/.clauddy/env (shell: source ~/.clauddy/env; systemd: EnvironmentFile=%h/.clauddy/env)"
  MSG_TIP_DAEMON="  Cost tip: route heartbeats/housekeeping to haiku / flash tier models; use Opus only for real work."
  MSG_CHANGED="Files changed:%s (each backed up as .bak.%s)"
  MSG_FOOTER="Console: %s  ·  API keys: %s"
  MSG_HINT_CCONLY="If you ever hit \"This group only allows Claude Code clients\": create a Unified-group API key for that client instead."
  QL='"'; QR='"'
  MSG_GRP_CLAUDE="${QL}Claude${QR} (1.0x, cheapest) or ${QL}Unified${QR} (1.8x, works everywhere)"
  MSG_GRP_CODEX="${QL}OpenAI${QR} (0.5x, cheapest) or ${QL}Unified${QR} (1.8x, works everywhere)"
  MSG_GRP_GEMINI="${QL}Gemini${QR} or ${QL}Unified${QR} (both 1.8x)"
  MSG_GRP_DAEMON="${QL}Unified${QR} (always-on agents must NOT use the Claude group)"
else
  MSG_ERR_NOTTY="无法打开终端进行交互 (/dev/tty 不可读)。请下载后本地运行: bash install.sh"
  MSG_ERR_OS="暂不支持的系统: %s。install.sh 需要 macOS/Linux 上的 Bash；Windows 请在 WSL 中运行，或参考手动配置教程: https://docs.clauddy.com/cli/claude-code"
  MSG_ERR_NEED_CURL="需要 curl, 请先安装。"
  MSG_HDR="Clauddy 接入向导 v%s  (%s, 网关: %s)"
  MSG_MENU_TITLE="要安装/配置哪个客户端? (输入编号, 多选用空格分隔, 如: 1 2)"
  MSG_MENU_AGAIN="还要安装/配置其他客户端吗? (输入编号继续, 输入 0 结束)"
  MSG_MENU_LANG="English (切换语言)"
  MSG_MENU_EXIT="退出"
  MSG_TAG_INSTALLED=" [已安装]"
  MSG_TAG_MISSING=" [未安装]"
  MSG_DAEMON_TAG="常驻 agent"
  MSG_WARN_BAD_NUM="忽略无效输入: %s"
  MSG_ERR_NO_CLIENT="没有选择任何项 — 请输入菜单中的编号。"
  MSG_NOT_INSTALLED="%s 尚未安装。"
  MSG_INSTALL_ASK="现在安装吗? 官方安装方式: %s  [Y/n] "
  MSG_INSTALLING="正在安装 %s …"
  MSG_INSTALL_OK="%s 安装完成"
  MSG_INSTALL_FAIL="%s 安装失败 (退出码 %s) — 先继续写入配置。"
  MSG_INSTALL_SKIP="跳过安装 — 仍会写入配置 (装好后即可直接使用)。"
  MSG_PATH_HINT="若之后提示 command not found, 请新开一个终端再试。"
  MSG_RERUN_HINT="请手动安装后重新运行本脚本 — 会从中断处继续。"
  MSG_CFG_ONLY="%s 的配置已写好, 但其命令尚未安装成功 — 请手动安装, 之后新开终端即可直接使用。"
  MSG_NODE_MISSING="%s 需要 Node.js 18+ (含 npm), 当前系统未检测到。"
  MSG_NODE_ASK="现在把 Node.js LTS (%s) 安装到 ~/.clauddy/node 吗? (nodejs.org 官方二进制, 仅当前用户, 无需 sudo)  [Y/n] "
  MSG_NODE_TOO_OLD="检测到 Node.js %s (低于 18)。为避免影响现有环境, 不会自动升级 — 请自行升级到 18+ 后重新运行本脚本。"
  MSG_NODE_INSTALLING="正在从 nodejs.org 下载 Node.js %s (%s) …"
  MSG_NODE_OK="Node.js %s 已就绪: %s (新终端会通过 ~/.clauddy/env 自动加载 PATH)"
  MSG_NODE_FAIL="Node.js 自动安装失败: %s"
  MSG_NODE_FAIL_HINT="请手动安装 Node.js 18+ (https://nodejs.org), 然后重新运行本脚本 — 会从中断处继续。"
  MSG_NODE_R_ARCH="暂不支持的 CPU 架构: %s"
  MSG_NODE_R_MUSL="musl 系统 (如 Alpine) — 官方二进制需要 glibc"
  MSG_NODE_R_SHA="未找到 sha256sum/shasum, 无法校验下载文件"
  MSG_NODE_R_DL="下载失败 (%s)"
  MSG_NODE_R_SUM="校验和不匹配 — 已删除下载文件"
  MSG_NODE_R_TAR="解压失败 (需要 tar)"
  MSG_NODE_R_RUN="安装后的 node 无法在本机运行 (glibc 过旧?)"
  MSG_FAILED_SUMMARY="本次未完成安装: %s — 配置均已写好。请手动安装后重新运行本脚本, 验证一切可用。"
  MSG_KEY_FOR="为 %s 配置 API 密钥:"
  MSG_KEY_STEP="  打开 %s, 新建 API 密钥 (分组选 %s), 然后粘贴到下面。"
  MSG_KEY_REUSE="  (本次已验证过一把密钥, 直接按回车即可复用)"
  MSG_PASTE="粘贴 API 密钥后按回车 (安全起见, 粘贴时屏幕上不会显示任何内容, 属正常现象): "
  MSG_ERR_EMPTY="输入为空。"
  MSG_WARN_SK="API 密钥通常以 sk- 开头, 仍尝试校验…"
  MSG_ERR_3FAIL="连续 3 次校验失败。请确认: 分组选的是 %s、账户余额充足、密钥复制完整。"
  MSG_MENU_RETRY="重试(r) / AI 诊断(d, 消耗少量额度) / 跳过此客户端(s) / 退出(q)? "
  MSG_MENU_HINT="请输入 r / d / s / q"
  MSG_ERR_NET="网络错误, 无法访问 %s"
  MSG_ERR_VERIFY="校验失败 (%s)"
  MSG_OK_KEY="密钥可用 — 该分组可用模型 %s 个, 接口延迟 %ss"
  MSG_SKIP_CLIENT="已跳过 %s。"
  MSG_DIAG_NEED_KEY="AI 诊断需要至少一把已通过校验的 API 密钥 (本次还没有)。请先人工核对分组与密钥。"
  MSG_DIAG_NEED_PY="AI 诊断需要 python3。"
  MSG_DIAG_NO_MODEL="已验证密钥下没有可用模型, 无法诊断。"
  MSG_DIAG_CALLING="正在用已验证的密钥调用 %s 诊断 (只输出建议, 不执行操作)…"
  MSG_DIAG_CTX="正在配置的客户端: %s (推荐分组: %s)
系统: %s
网关: %s
校验失败详情: %s"
  MSG_BACKUP="  (原文件已备份: %s)"
  MSG_OK_CLAUDE="Claude Code: 已写入 %s (env.ANTHROPIC_BASE_URL / ANTHROPIC_AUTH_TOKEN)"
  MSG_WARN_NO_PY_CLAUDE="未找到 python3, 无法安全合并 JSON。请手动将以下内容加入 %s 的 env 块:"
  MSG_TAKEOVER="[clauddy-setup 已接管]"
  MSG_OK_CODEX="Codex: 已写入 %s (provider=clauddy%s)"
  MSG_WARN_CODEX_MODEL="未在模型列表中找到 codex 模型, 请在 %s 中手动设置 model = \"…\""
  MSG_OK_GEMINI="Gemini CLI: 已写入 %s"
  MSG_OK_ENVFILE="环境文件: 已写入 %s (chmod 600)"
  MSG_OK_RC="已在 %s 中加载 ~/.clauddy/env (新开终端生效)"
  MSG_READY_CLAUDE="Claude Code 已就绪 — 输入 %sclaude%s 回车即可开始使用。"
  MSG_READY_CODEX="Codex 已就绪 — 新开一个终端, 输入 %scodex%s 回车即可开始使用。"
  MSG_READY_GEMINI="Gemini CLI 已就绪 — 输入 %sgemini%s 回车即可开始使用。"
  MSG_READY_DAEMON="%s 已配置 — 新开一个终端, 输入 %s%s%s 回车即可开始使用。"
  MSG_READY_DAEMON2="  守护进程方式: 需加载 ~/.clauddy/env (shell: source ~/.clauddy/env; systemd: EnvironmentFile=%h/.clauddy/env)"
  MSG_TIP_DAEMON="  省钱提示: 心跳/后台轮询建议配置 haiku / flash 档模型, 真正干活再用 Opus。"
  MSG_CHANGED="改动过的文件:%s (均有 .bak.%s 备份)"
  MSG_FOOTER="控制台: %s  ·  API 密钥管理: %s"
  MSG_HINT_CCONLY="若遇到「该分组仅允许 Claude Code 客户端」报错: 为该客户端另建一个 Unified 分组的 API 密钥即可。"
  QL="「"; QR="」"
  MSG_GRP_CLAUDE="${QL}Claude${QR} (1.0x 最省) 或 ${QL}Unified${QR} (1.8x 通用)"
  MSG_GRP_CODEX="${QL}OpenAI${QR} (0.5x 最省) 或 ${QL}Unified${QR} (1.8x 通用)"
  MSG_GRP_GEMINI="${QL}Gemini${QR} 或 ${QL}Unified${QR} (均 1.8x)"
  MSG_GRP_DAEMON="${QL}Unified${QR} (常驻 agent 请勿用 Claude 组)"
fi
}
load_msgs

# curl | bash 时 stdin 是脚本本身, 交互必须走 /dev/tty
TTY=/dev/tty
if [ ! -r "$TTY" ]; then
  err "$MSG_ERR_NOTTY"
  exit 1
fi
ask()       { printf '%s' "$1" > "$TTY"; IFS= read -r REPLY < "$TTY"; }
ask_secret(){ printf '%s' "$1" > "$TTY"; IFS= read -rs REPLY < "$TTY"; printf '\n' > "$TTY"; }

# ---- 系统检测 / system detection ----------------------------------------------
OS="$(uname -s 2>/dev/null || echo unknown)"
case "$OS" in
  Darwin) OS_NAME="macOS" ;;
  Linux)  OS_NAME="Linux" ;;
  *) err "$(printf "$MSG_ERR_OS" "$OS")"; exit 1 ;;
esac
command -v curl >/dev/null 2>&1 || { err "$MSG_ERR_NEED_CURL"; exit 1; }
HAS_PY=0; command -v python3 >/dev/null 2>&1 && HAS_PY=1

# ---- 密钥校验 / key validation -------------------------------------------------
TOKEN=""
MODELS_BODY=""
LAST_GOOD_KEY=""
LAST_ERR=""

probe_token() {
  local key="$1" tmp http t
  tmp="$(mktemp)"
  t="$(curl -sS -o "$tmp" -w '%{http_code} %{time_total}' \
        -H "Authorization: Bearer $key" \
        --connect-timeout 10 --max-time 30 \
        "$BASE_URL/v1/models" 2>/dev/null)" || { LAST_ERR="$(printf "$MSG_ERR_NET" "$BASE_URL")"; err "$LAST_ERR"; rm -f "$tmp"; return 1; }
  http="${t%% *}"
  if [ "$http" != "200" ]; then
    LAST_ERR="HTTP $http: $(head -c 300 "$tmp" | LC_ALL=C sed 's/sk-[A-Za-z0-9._-]\{8,\}/sk-***/g')"
    err "$(printf "$MSG_ERR_VERIFY" "$LAST_ERR")"
    rm -f "$tmp"; return 1
  fi
  MODELS_BODY="$(cat "$tmp")"; rm -f "$tmp"
  LAST_GOOD_KEY="$key"
  local count
  count="$(printf '%s' "$MODELS_BODY" | grep -o '"id"' | wc -l | tr -d ' ')"
  ok "$(printf "$MSG_OK_KEY" "$count" "${t#* }")"
  return 0
}

# 从最近一次 probe 的模型列表里找包含关键词的第一个模型 id
pick_model() {
  printf '%s' "$MODELS_BODY" | tr ',{' '\n\n' | grep -o '"id"[[:space:]]*:[[:space:]]*"[^"]*'"$1"'[^"]*"' \
    | head -1 | sed 's/.*:[[:space:]]*"//; s/"$//'
}

# AI 诊断: 用已验证的密钥向网关发一次有界调用, 只打印建议, 绝不执行任何操作。
# AI diagnosis: one bounded call via an already-validated key; advice only.
ai_diagnose() {
  local purpose="$1" group="$2" model diag
  if [ -z "$LAST_GOOD_KEY" ]; then warn "$MSG_DIAG_NEED_KEY"; return 1; fi
  if [ "$HAS_PY" -ne 1 ]; then warn "$MSG_DIAG_NEED_PY"; return 1; fi
  model="$(pick_model haiku)"
  [ -z "$model" ] && model="$(pick_model flash)"
  [ -z "$model" ] && model="$(pick_model mini)"
  [ -z "$model" ] && model="$(pick_model '')"
  if [ -z "$model" ]; then warn "$MSG_DIAG_NO_MODEL"; return 1; fi
  diag="$(printf "$MSG_DIAG_CTX" "$purpose" "$group" "$OS_NAME" "$BASE_URL" "${LAST_ERR:-unknown}")"
  say "$(printf "$MSG_DIAG_CALLING" "$model")"
  python3 - "$BASE_URL" "$LAST_GOOD_KEY" "$model" "$diag" "$UI_LANG" <<'PYEOF'
import json, sys, urllib.request
base, key, model, diag, lang = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5]
reply_lang = "Simplified Chinese" if lang == "zh" else "English"
sysmsg = (
    "You are the onboarding diagnosis assistant for the Clauddy gateway (new-api based). "
    "A user's API key failed validation while configuring an AI client. "
    "Gateway key groups: Claude (Claude Code clients ONLY, 1.0x); Claude3p (any client, 1.2x); "
    "ClaudeAPI (any client, 5x); OpenAI (Codex only, 0.5x); Gemini (1.8x); "
    "Unified (any client, all models, 1.8x — the convenient single-key option). "
    "Common failures: HTTP 401 = invalid or incompletely pasted key; group errors = key group does not "
    "match the client (daemons and non-Claude-Code clients must not use the Claude group); "
    "insufficient balance = needs topup first; network errors = proxy/firewall. "
    "Reply in " + reply_lang + " with the most likely cause and concrete fix steps, under 200 words. "
    "You cannot execute anything; give advice only."
)
req = urllib.request.Request(
    base + "/v1/chat/completions",
    data=json.dumps({
        "model": model,
        "max_tokens": 500,
        "messages": [
            {"role": "system", "content": sysmsg},
            {"role": "user", "content": diag},
        ],
    }).encode(),
    headers={"Authorization": "Bearer " + key, "Content-Type": "application/json"},
)
try:
    with urllib.request.urlopen(req, timeout=60) as r:
        out = json.load(r)
    print(out["choices"][0]["message"]["content"])
except Exception as e:
    print("(AI diagnosis call failed: %s)" % e)
PYEOF
}

# ---- 密钥指引 (精简) / key guide (terse) ----------------------------------------
guide_and_read() { # $1=client name  $2=group hint (display)  $3=primary group (for errors)
  local purpose="$1" group_disp="$2" group="$3" attempt=0
  say ""
  say "${C_BOLD}$(printf "$MSG_KEY_FOR" "$purpose")${C_RESET}"
  say "$(printf "$MSG_KEY_STEP" "${C_BOLD}${CONSOLE_KEYS_URL}${C_RESET}" "$group_disp")"
  [ -n "$LAST_GOOD_KEY" ] && say "$MSG_KEY_REUSE"
  while :; do
    ask_secret "$MSG_PASTE"
    TOKEN="$REPLY"
    if [ -z "$TOKEN" ] && [ -n "$LAST_GOOD_KEY" ]; then TOKEN="$LAST_GOOD_KEY"; fi
    case "$TOKEN" in sk-*) ;; "") err "$MSG_ERR_EMPTY"; continue ;; *) warn "$MSG_WARN_SK" ;; esac
    if probe_token "$TOKEN"; then return 0; fi
    attempt=$((attempt + 1))
    if [ "$attempt" -ge 3 ]; then
      err "$(printf "$MSG_ERR_3FAIL" "${QL}${group}${QR}")"
      while :; do
        ask "$MSG_MENU_RETRY"
        case "$REPLY" in
          r|R) attempt=0; break ;;
          d|D) ai_diagnose "$purpose" "$group" ;;  # back to this menu afterwards
          s|S) TOKEN=""; return 1 ;;
          q|Q) exit 1 ;;
          *) say "$MSG_MENU_HINT" ;;
        esac
      done
    fi
  done
}

# ---- Node.js 兜底安装 / user-local Node.js fallback -----------------------------
# npm 类客户端缺 Node 时: 官方 LTS tarball -> ~/.clauddy/node (无 sudo, SHA256 校验)。
# 已有 Node 一律不动; 低于 18 只提示手动升级, 避免影响用户现有环境。
NODE_DIR="$HOME/.clauddy/node"
NODE_LTS_LINE="v24.x"   # 安装的 LTS 版本线 / LTS line to install
NPM_BIN="npm"           # ensure_node 成功后指向可用的 npm / usable npm after ensure_node

# 命令存在性: PATH 之外还认本脚本装过的位置 (本次运行内 PATH 尚未刷新)
has_cmd() { command -v "$1" >/dev/null 2>&1 || [ -x "$NODE_DIR/bin/$1" ] || [ -x "$HOME/.local/bin/$1" ]; }

ensure_node() { # $1 = client name (仅用于提示); 成功时设置 NPM_BIN
  local name="$1" major plat arch file ver sum got tmpd shas
  if command -v node >/dev/null 2>&1; then
    major="$(node -v 2>/dev/null | sed 's/^v//' | cut -d. -f1)"
    if [ -n "$major" ] && [ "$major" -ge 18 ] 2>/dev/null; then
      if command -v npm >/dev/null 2>&1; then NPM_BIN="npm"; return 0; fi
      # node 够新但缺 npm -> 走本地兜底安装 / node ok but npm missing: local install
    else
      warn "$(printf "$MSG_NODE_TOO_OLD" "$(node -v 2>/dev/null)")"
      return 1
    fi
  fi
  if [ -x "$NODE_DIR/bin/npm" ] && "$NODE_DIR/bin/node" -v >/dev/null 2>&1; then
    NPM_BIN="$NODE_DIR/bin/npm"; ENV_NODE=1; write_env_file
    ok "$(printf "$MSG_NODE_OK" "$("$NODE_DIR/bin/node" -v)" "$NODE_DIR")"
    return 0
  fi
  warn "$(printf "$MSG_NODE_MISSING" "$name")"
  if [ "$ASSUME_YES" -ne 1 ]; then
    ask "$(printf "$MSG_NODE_ASK" "$NODE_LTS_LINE")"
    case "$REPLY" in n|N|no|NO) warn "$MSG_NODE_FAIL_HINT"; return 1 ;; esac
  fi
  case "$(uname -m)" in
    x86_64|amd64)  arch="x64" ;;
    aarch64|arm64) arch="arm64" ;;
    *) warn "$(printf "$MSG_NODE_FAIL" "$(printf "$MSG_NODE_R_ARCH" "$(uname -m)")")"; warn "$MSG_NODE_FAIL_HINT"; return 1 ;;
  esac
  if [ "$OS_NAME" = "macOS" ]; then plat="darwin"; else plat="linux"; fi
  if [ "$plat" = "linux" ] && ldd --version 2>&1 | grep -qi musl; then
    warn "$(printf "$MSG_NODE_FAIL" "$MSG_NODE_R_MUSL")"; warn "$MSG_NODE_FAIL_HINT"; return 1
  fi
  if ! command -v sha256sum >/dev/null 2>&1 && ! command -v shasum >/dev/null 2>&1; then
    warn "$(printf "$MSG_NODE_FAIL" "$MSG_NODE_R_SHA")"; warn "$MSG_NODE_FAIL_HINT"; return 1
  fi
  command -v tar >/dev/null 2>&1 || { warn "$(printf "$MSG_NODE_FAIL" "$MSG_NODE_R_TAR")"; warn "$MSG_NODE_FAIL_HINT"; return 1; }
  shas="$(curl -fsSL --connect-timeout 10 --max-time 60 "https://nodejs.org/dist/latest-$NODE_LTS_LINE/SHASUMS256.txt" 2>/dev/null)"
  file="$(printf '%s\n' "$shas" | grep -o "node-v[0-9.]*-$plat-$arch\.tar\.gz" | head -1)"
  sum="$(printf '%s\n' "$shas" | awk -v f="$file" 'NF==2 && $2==f {print $1; exit}')"
  if [ -z "$file" ] || [ -z "$sum" ]; then
    warn "$(printf "$MSG_NODE_FAIL" "$(printf "$MSG_NODE_R_DL" "SHASUMS256.txt")")"; warn "$MSG_NODE_FAIL_HINT"; return 1
  fi
  ver="${file#node-}"; ver="${ver%%-*}"
  say "$(printf "$MSG_NODE_INSTALLING" "$ver" "$plat-$arch")"
  tmpd="$(mktemp -d)" || { warn "$(printf "$MSG_NODE_FAIL" "mktemp")"; warn "$MSG_NODE_FAIL_HINT"; return 1; }
  if ! curl -fL --progress-bar --connect-timeout 10 --max-time 600 -o "$tmpd/$file" "https://nodejs.org/dist/$ver/$file"; then
    rm -rf "$tmpd"
    warn "$(printf "$MSG_NODE_FAIL" "$(printf "$MSG_NODE_R_DL" "$file")")"; warn "$MSG_NODE_FAIL_HINT"; return 1
  fi
  if command -v sha256sum >/dev/null 2>&1; then got="$(sha256sum "$tmpd/$file" | cut -d' ' -f1)"
  else got="$(shasum -a 256 "$tmpd/$file" | cut -d' ' -f1)"; fi
  if [ "$got" != "$sum" ]; then
    rm -rf "$tmpd"
    warn "$(printf "$MSG_NODE_FAIL" "$MSG_NODE_R_SUM")"; warn "$MSG_NODE_FAIL_HINT"; return 1
  fi
  rm -rf "$NODE_DIR"; mkdir -p "$NODE_DIR"
  if ! tar -xzf "$tmpd/$file" -C "$NODE_DIR" --strip-components=1; then
    rm -rf "$tmpd" "$NODE_DIR"
    warn "$(printf "$MSG_NODE_FAIL" "$MSG_NODE_R_TAR")"; warn "$MSG_NODE_FAIL_HINT"; return 1
  fi
  rm -rf "$tmpd"
  if ! "$NODE_DIR/bin/node" -v >/dev/null 2>&1; then
    rm -rf "$NODE_DIR"
    warn "$(printf "$MSG_NODE_FAIL" "$MSG_NODE_R_RUN")"; warn "$MSG_NODE_FAIL_HINT"; return 1
  fi
  NPM_BIN="$NODE_DIR/bin/npm"
  ENV_NODE=1
  write_env_file
  ok "$(printf "$MSG_NODE_OK" "$("$NODE_DIR/bin/node" -v)" "$NODE_DIR")"
  return 0
}

# ---- 客户端安装 / client installation ------------------------------------------
ensure_installed() { # $1=name $2=command $3=install command $4=kind(curl|brew|npm)
  local name="$1" cmd="$2" icmd="$3" kind="$4" rcode
  has_cmd "$cmd" && return 0
  warn "$(printf "$MSG_NOT_INSTALLED" "$name")"
  if [ "$kind" = "npm" ]; then
    ensure_node "$name" || return 1   # 失败原因与手动安装提示已在 ensure_node 内输出
    if [ "$NPM_BIN" != "npm" ]; then
      # 本地 Node: npm 及其 shebang 都要能找到 node / local node must be on PATH for npm
      icmd="PATH=\"$NODE_DIR/bin:\$PATH\" $icmd"
    fi
  fi
  if [ "$ASSUME_YES" -ne 1 ]; then
    ask "$(printf "$MSG_INSTALL_ASK" "${C_BOLD}${icmd}${C_RESET}")"
    case "$REPLY" in n|N|no|NO) say "$MSG_INSTALL_SKIP"; return 1 ;; esac
  fi
  say "$(printf "$MSG_INSTALLING" "$name")"
  # 官方安装脚本可能需要交互, stdin 接回终端 / installers may prompt; wire stdin to the tty
  sh -c "$icmd" < "$TTY"
  rcode=$?
  if [ "$rcode" -ne 0 ]; then
    warn "$(printf "$MSG_INSTALL_FAIL" "$name" "$rcode")"
    warn "$MSG_RERUN_HINT"
    return 1
  fi
  ok "$(printf "$MSG_INSTALL_OK" "$name")"
  has_cmd "$cmd" || warn "$MSG_PATH_HINT"
  return 0
}

# ---- 写配置 (写前备份) / write configs (backup first) ----------------------------
# 每个文件每次运行只备份一次, 保留运行前的原始状态 / one backup per file per run
backup() {
  [ -f "$1" ] || return 0
  [ -f "$1.bak.$STAMP" ] && return 0
  cp -p "$1" "$1.bak.$STAMP" && say "$(printf "$MSG_BACKUP" "$1.bak.$STAMP")"
}
strip_managed_block() { # $1=file  删除旧托管块 / remove old managed blocks
  [ -f "$1" ] || return 0
  awk '/# >>> clauddy setup >>>/{skip=1} skip==0{print} /# <<< clauddy setup <<</{skip=0}' "$1" > "$1.tmp.$$" \
    && mv "$1.tmp.$$" "$1"
}
CHANGED=""
ENV_KEY_CODEX=""   # accumulated across the menu loop; env file is rewritten whole
ENV_KEY_DAEMON=""
ENV_NODE=0         # 1 = 使用 ~/.clauddy/node, env 文件需带 PATH / local node in use
CUR_INSTALLED=0    # 当前客户端本次是否确认已装上 / current client install status

# Claude Code: ~/.claude/settings.json env 块 (JSON 合并, 不破坏已有配置)
configure_claude() {
  local key="$1" f="$HOME/.claude/settings.json"
  if [ "$HAS_PY" -eq 1 ]; then
    mkdir -p "$HOME/.claude"; backup "$f"
    python3 - "$f" "$BASE_URL" "$key" <<'PYEOF'
import json, os, sys
path, base, key = sys.argv[1], sys.argv[2], sys.argv[3]
data = {}
if os.path.exists(path):
    with open(path) as fh:
        data = json.load(fh)
env = data.setdefault("env", {})
env["ANTHROPIC_BASE_URL"] = base
env["ANTHROPIC_AUTH_TOKEN"] = key
with open(path, "w") as fh:
    json.dump(data, fh, indent=2, ensure_ascii=False)
    fh.write("\n")
PYEOF
    ok "$(printf "$MSG_OK_CLAUDE" "$f")"
    CHANGED="$CHANGED $f"
  else
    warn "$(printf "$MSG_WARN_NO_PY_CLAUDE" "$f")"
    say "    \"ANTHROPIC_BASE_URL\": \"$BASE_URL\","
    say "    \"ANTHROPIC_AUTH_TOKEN\": \"<your API key>\""
  fi
  if [ "$CUR_INSTALLED" -eq 1 ]; then
    ok "$(printf "$MSG_READY_CLAUDE" "$C_BOLD" "$C_RESET")"
  else
    warn "$(printf "$MSG_CFG_ONLY" "Claude Code")"
  fi
}

# Codex CLI: ~/.codex/config.toml 托管块 + key 走环境变量 CLAUDDY_API_KEY
configure_codex() {
  local key="$1" f="$HOME/.codex/config.toml" model
  model="$(pick_model codex)"
  [ -z "$model" ] && model="$(pick_model gpt)"   # 分组内无 codex 命名时退而选 gpt 系
  mkdir -p "$HOME/.codex"; backup "$f"; touch "$f"; strip_managed_block "$f"
  # TOML 语义: 顶层键必须出现在任何 [table] 之前 -> 顶层键写头部托管块,
  # provider table 写尾部托管块; 原有顶层 model/model_provider 注释接管, 避免重复键。
  awk -v tag="$MSG_TAKEOVER" 'BEGIN{intable=0}
       /^\[/{intable=1}
       intable==0 && /^[[:space:]]*(model_provider|model)[[:space:]]*=/{print "# " tag " " $0; next}
       {print}' "$f" > "$f.tmp.$$"
  {
    printf '%s\n' '# >>> clauddy setup >>>'
    printf '%s\n' 'model_provider = "clauddy"'
    [ -n "$model" ] && printf 'model = "%s"\n' "$model"
    printf '%s\n' '# <<< clauddy setup <<<'
    cat "$f.tmp.$$"
    printf '%s\n' '# >>> clauddy setup >>>'
    printf '%s\n' '[model_providers.clauddy]'
    printf '%s\n' 'name = "Clauddy"'
    printf 'base_url = "%s/v1"\n' "$BASE_URL"
    printf '%s\n' 'wire_api = "responses"'
    printf '%s\n' 'env_key = "CLAUDDY_API_KEY"'
    printf '%s\n' '# <<< clauddy setup <<<'
  } > "$f"
  rm -f "$f.tmp.$$"
  ok "$(printf "$MSG_OK_CODEX" "$f" "${model:+, model=$model}")"
  [ -z "$model" ] && warn "$(printf "$MSG_WARN_CODEX_MODEL" "$f")"
  CHANGED="$CHANGED $f"
  ENV_KEY_CODEX="$key"
  write_env_file
  if [ "$CUR_INSTALLED" -eq 1 ]; then
    ok "$(printf "$MSG_READY_CODEX" "$C_BOLD" "$C_RESET")"
  else
    warn "$(printf "$MSG_CFG_ONLY" "Codex CLI")"
  fi
}

# Gemini CLI: ~/.gemini/.env (gemini-cli 启动时自动加载)
configure_gemini() {
  local key="$1" f="$HOME/.gemini/.env"
  mkdir -p "$HOME/.gemini"; backup "$f"; touch "$f"; strip_managed_block "$f"
  {
    printf '%s\n' '# >>> clauddy setup >>>'
    printf 'GOOGLE_GEMINI_BASE_URL="%s"\n' "$BASE_URL"
    printf 'GEMINI_API_KEY="%s"\n' "$key"
    printf '%s\n' '# <<< clauddy setup <<<'
  } >> "$f"
  chmod 600 "$f"
  ok "$(printf "$MSG_OK_GEMINI" "$f")"
  CHANGED="$CHANGED $f"
  if [ "$CUR_INSTALLED" -eq 1 ]; then
    ok "$(printf "$MSG_READY_GEMINI" "$C_BOLD" "$C_RESET")"
  else
    warn "$(printf "$MSG_CFG_ONLY" "Gemini CLI")"
  fi
}

# 常驻 agent (OpenClaw / Hermes): 全套变量写 ~/.clauddy/env
configure_daemon() {
  local key="$1" name="$2" cmd="$3"
  ENV_KEY_DAEMON="$key"
  write_env_file
  if [ "$CUR_INSTALLED" -eq 1 ]; then
    ok "$(printf "$MSG_READY_DAEMON" "$name" "$C_BOLD" "$cmd" "$C_RESET")"
  else
    warn "$(printf "$MSG_CFG_ONLY" "$name")"
  fi
  say "$MSG_READY_DAEMON2"
  say "${C_YELLOW}${MSG_TIP_DAEMON}${C_RESET}"
}

# 通用环境文件 ~/.clauddy/env — 守护进程 + Codex 的 env_key + 本地 Node 的 PATH。
# 每次整块重写; 重写前先回收上次运行写入的值, 保证多轮/多次运行不互相覆盖。
write_env_file() {
  local f="$HOME/.clauddy/env" rc
  mkdir -p "$HOME/.clauddy"
  if [ -f "$f" ]; then
    [ -z "$ENV_KEY_CODEX" ] && ENV_KEY_CODEX="$(sed -n 's/^export CLAUDDY_API_KEY="\(.*\)"$/\1/p' "$f" | head -1)"
    [ -z "$ENV_KEY_DAEMON" ] && ENV_KEY_DAEMON="$(sed -n 's/^export ANTHROPIC_AUTH_TOKEN="\(.*\)"$/\1/p' "$f" | head -1)"
    [ "$ENV_NODE" -eq 0 ] && grep -q 'clauddy/node/bin' "$f" && ENV_NODE=1
  fi
  backup "$f"; touch "$f"; strip_managed_block "$f"
  {
    printf '%s\n' '# >>> clauddy setup >>>'
    if [ "$ENV_NODE" -eq 1 ]; then
      printf '%s\n' 'case ":$PATH:" in *":$HOME/.clauddy/node/bin:"*) ;; *) export PATH="$PATH:$HOME/.clauddy/node/bin" ;; esac'
    fi
    if [ -n "$ENV_KEY_CODEX" ]; then
      printf 'export CLAUDDY_API_KEY="%s"\n' "$ENV_KEY_CODEX"
    fi
    if [ -n "$ENV_KEY_DAEMON" ]; then
      printf 'export ANTHROPIC_BASE_URL="%s"\n' "$BASE_URL"
      printf 'export ANTHROPIC_AUTH_TOKEN="%s"\n' "$ENV_KEY_DAEMON"
      printf 'export ANTHROPIC_API_KEY="%s"\n' "$ENV_KEY_DAEMON"
      printf 'export OPENAI_BASE_URL="%s/v1"\n' "$BASE_URL"
      printf 'export OPENAI_API_KEY="%s"\n' "$ENV_KEY_DAEMON"
      printf 'export GOOGLE_GEMINI_BASE_URL="%s"\n' "$BASE_URL"
      printf 'export GEMINI_API_KEY="%s"\n' "$ENV_KEY_DAEMON"
    fi
    printf '%s\n' '# <<< clauddy setup <<<'
  } >> "$f"
  chmod 600 "$f"
  ok "$(printf "$MSG_OK_ENVFILE" "$f")"
  CHANGED="$CHANGED $f"

  # shell rc 中加载 (幂等) / idempotent rc hook
  case "${SHELL:-}" in
    */zsh)  rc="$HOME/.zshrc" ;;
    */bash) rc="$HOME/.bashrc" ;;
    *)      rc="$HOME/.profile" ;;
  esac
  if ! grep -q 'clauddy/env' "$rc" 2>/dev/null; then
    backup "$rc"
    printf '\n# >>> clauddy setup >>>\n[ -f "$HOME/.clauddy/env" ] && . "$HOME/.clauddy/env"\n# <<< clauddy setup <<<\n' >> "$rc"
    ok "$(printf "$MSG_OK_RC" "$rc")"
    CHANGED="$CHANGED $rc"
  fi
}

# ---- 单个客户端: 安装 -> 密钥 -> 配置 -> 启动提示 --------------------------------
setup_client() { # $1 = menu id 1..5
  local id="$1" name cmd icmd ikind group_disp group
  case "$id" in
    1) name="Claude Code"; cmd="claude"
       icmd="curl -fsSL https://claude.ai/install.sh | bash"; ikind="curl"
       group_disp="$MSG_GRP_CLAUDE"; group="Claude" ;;
    2) name="Codex CLI"; cmd="codex"
       if [ "$OS_NAME" = "macOS" ] && command -v brew >/dev/null 2>&1; then
         icmd="brew install codex"; ikind="brew"
       else
         icmd="npm install -g @openai/codex"; ikind="npm"
       fi
       group_disp="$MSG_GRP_CODEX"; group="OpenAI" ;;
    3) name="Gemini CLI"; cmd="gemini"
       if [ "$OS_NAME" = "macOS" ] && command -v brew >/dev/null 2>&1; then
         icmd="brew install gemini-cli"; ikind="brew"
       else
         icmd="npm install -g @google/gemini-cli"; ikind="npm"
       fi
       group_disp="$MSG_GRP_GEMINI"; group="Gemini" ;;
    4) name="OpenClaw"; cmd="openclaw"
       icmd="curl -fsSL https://openclaw.ai/install.sh | bash"; ikind="curl"
       group_disp="$MSG_GRP_DAEMON"; group="Unified" ;;
    5) name="Hermes agent"; cmd="hermes"
       icmd="curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash"; ikind="curl"
       group_disp="$MSG_GRP_DAEMON"; group="Unified" ;;
    *) return 0 ;;
  esac
  say ""
  hr
  # 安装失败/跳过仍继续写配置 / config is still written when install fails or is skipped
  CUR_INSTALLED=0
  if ensure_installed "$name" "$cmd" "$icmd" "$ikind"; then CUR_INSTALLED=1; fi
  if ! guide_and_read "$name" "$group_disp" "$group"; then
    warn "$(printf "$MSG_SKIP_CLIENT" "$name")"
    return 0
  fi
  case "$id" in
    1) configure_claude "$TOKEN" ;;
    2) configure_codex  "$TOKEN" ;;
    3) configure_gemini "$TOKEN" ;;
    4|5) configure_daemon "$TOKEN" "$name" "$cmd" ;;
  esac
}

# ---- 主菜单循环 / main menu loop ------------------------------------------------
inst_tag() { has_cmd "$1" && printf '%s' "$MSG_TAG_INSTALLED" || printf '%s' "$MSG_TAG_MISSING"; }
ATTEMPTED=""   # 本次运行处理过的客户端编号 / client ids handled in this run

say ""
say "${C_BOLD}$(printf "$MSG_HDR" "$VERSION" "$OS_NAME" "$BASE_URL")${C_RESET}"

FIRST_ROUND=1
while :; do
  say ""
  hr
  if [ "$FIRST_ROUND" -eq 1 ]; then say "$MSG_MENU_TITLE"; else say "$MSG_MENU_AGAIN"; fi
  say "  1) Claude Code$(inst_tag claude)"
  say "  2) Codex CLI$(inst_tag codex)"
  say "  3) Gemini CLI$(inst_tag gemini)"
  say "  4) OpenClaw ($MSG_DAEMON_TAG)$(inst_tag openclaw)"
  say "  5) Hermes agent ($MSG_DAEMON_TAG)$(inst_tag hermes)"
  say "  6) $MSG_MENU_LANG"
  say "  0) $MSG_MENU_EXIT"
  ask "> "

  EXIT_REQ=0; TOGGLE_LANG=0; SEL_CLIENTS=""
  for n in $REPLY; do
    case "$n" in
      0|q|Q|exit) EXIT_REQ=1 ;;
      6) TOGGLE_LANG=1 ;;
      1|2|3|4|5) SEL_CLIENTS="$SEL_CLIENTS $n" ;;
      *) warn "$(printf "$MSG_WARN_BAD_NUM" "$n")" ;;
    esac
  done

  if [ "$TOGGLE_LANG" -eq 1 ]; then
    if [ "$UI_LANG" = "zh" ]; then UI_LANG="en"; else UI_LANG="zh"; fi
    load_msgs
  fi
  for id in $SEL_CLIENTS; do
    setup_client "$id"
    ATTEMPTED="$ATTEMPTED $id"
    FIRST_ROUND=0
  done
  [ "$EXIT_REQ" -eq 1 ] && break
  if [ -z "$SEL_CLIENTS" ] && [ "$TOGGLE_LANG" -eq 0 ] && [ -z "$REPLY" ]; then
    warn "$MSG_ERR_NO_CLIENT"
  fi
done

# ---- 退出总结 / exit summary ----------------------------------------------------
say ""
hr
# 逐个复核本次处理过的客户端, 未装上的明确列出 / recheck every client handled this run
MISSING=""
for id in $(printf '%s\n' $ATTEMPTED | awk '!seen[$0]++'); do
  case "$id" in
    1) SUM_NAME="Claude Code";  SUM_CMD="claude" ;;
    2) SUM_NAME="Codex CLI";    SUM_CMD="codex" ;;
    3) SUM_NAME="Gemini CLI";   SUM_CMD="gemini" ;;
    4) SUM_NAME="OpenClaw";     SUM_CMD="openclaw" ;;
    5) SUM_NAME="Hermes agent"; SUM_CMD="hermes" ;;
    *) continue ;;
  esac
  has_cmd "$SUM_CMD" || MISSING="${MISSING:+$MISSING, }$SUM_NAME"
done
if [ -n "$MISSING" ]; then
  warn "$(printf "$MSG_FAILED_SUMMARY" "${C_BOLD}${MISSING}${C_RESET}")"
fi
if [ -n "$CHANGED" ]; then
  CHANGED_UNIQ=" $(printf '%s\n' $CHANGED | awk '!seen[$0]++' | tr '\n' ' ')"
  say "$(printf "$MSG_CHANGED" "${CHANGED_UNIQ% }" "$STAMP")"
fi
say "$(printf "$MSG_FOOTER" "$CONSOLE_URL" "$CONSOLE_KEYS_URL")"
say "$MSG_HINT_CCONLY"
