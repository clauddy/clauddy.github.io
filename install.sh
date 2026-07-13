#!/usr/bin/env bash
# =============================================================================
#  Clauddy 一键接入脚本 / Clauddy one-click setup  (clauddy-setup)
#
#  用法 / Usage:
#    curl -fsSL https://docs.clauddy.com/install.sh | bash
#    bash install.sh [--base-url https://api.clauddy.com] \
#                    [--console-url https://clauddy.com] [--lang zh|en] [--yes]
#
#  URL 说明 / URLs: API 走 --base-url (默认 https://api.clauddy.com);
#  控制台/令牌页走 --console-url (默认 https://clauddy.com)。自定义 --base-url
#  而未给 --console-url 时, 控制台跟随 base-url (单主机部署/测试场景)。
#
#  功能 / What it does:
#    1. 检测系统与已安装的 AI 客户端 (Claude Code / Codex / Gemini CLI /
#       OpenClaw / Hermes agent)
#    2. 按所选客户端指引创建正确分组的令牌 (专用分组更便宜; 也可用 Unified
#       分组一把 key 访问全部模型; 守护进程类必须用不限客户端的分组)
#    3. 自动写入 base_url + api_key 到各客户端配置 (写前备份)
#    4. 连通性自检: 实测 /v1/models, 报告可用模型数与延迟
#    5. 校验失败时可选「AI 诊断」: 用已验证的令牌向网关发一次有界诊断调用,
#       只输出建议, 不自动执行任何操作 (消耗少量额度)
#
#  只与 $BASE_URL 通信, 不上传任何数据到其他地址。写过的文件都有 .bak 备份。
#  Talks only to $BASE_URL; never uploads anything elsewhere. All modified
#  files are backed up first.
# =============================================================================
set -u

VERSION="0.3.1"
BASE_URL="https://api.clauddy.com"
CONSOLE_URL=""        # default: https://clauddy.com; follows --base-url when customized
CONSOLE_KEYS_URL=""   # derived: $CONSOLE_URL/keys
ASSUME_YES=0
UI_LANG="zh"          # 默认中文 / Chinese by default; --lang en to switch
STAMP="$(date +%Y%m%d%H%M%S)"

# ---- 分组约定 / group taxonomy (synced with production UserUsableGroups, 2026-07-12)
#   Claude    1.4x  Claude Max 订阅转发, 仅 Claude Code 客户端 / CC clients only
#   Claude3p  1.8x  Claude Max, 不限制客户端 / any client
#   ClaudeAPI 5.0x  Claude 官方 Key 转发, 不限制客户端 / any client
#   OpenAI    0.5x  Codex Pro 专用 / Codex only
#   Gemini    1.8x  Gemini Ultra 专用 / Gemini only
#   Unified   1.8x  Claude / Codex / Gemini 全可用 / one key for all models
# 倍率以控制台实时显示为准 / ratios: console display is authoritative.

# ----------------------------------------------------------------------------
C_RESET=$'\033[0m'; C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'; C_RED=$'\033[31m'; C_BOLD=$'\033[1m'
ok()   { printf '%s✓%s %s\n' "$C_GREEN" "$C_RESET" "$1"; }
warn() { printf '%s!%s %s\n' "$C_YELLOW" "$C_RESET" "$1"; }
err()  { printf '%s✗ %s%s\n' "$C_RED" "$1" "$C_RESET" >&2; }
say()  { printf '%s\n' "$1"; }
hr()   { printf '%s\n' "----------------------------------------------------------------"; }

while [ $# -gt 0 ]; do
  case "$1" in
    --base-url)      BASE_URL="$2"; shift 2 ;;
    --base-url=*)    BASE_URL="${1#*=}"; shift ;;
    --console-url)   CONSOLE_URL="$2"; shift 2 ;;
    --console-url=*) CONSOLE_URL="${1#*=}"; shift ;;
    --lang)       UI_LANG="$2"; shift 2 ;;
    --lang=*)     UI_LANG="${1#*=}"; shift ;;
    --yes|-y)     ASSUME_YES=1; shift ;;
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

# ---- 文案目录 / message catalog ----------------------------------------------
if [ "$UI_LANG" = "en" ]; then
  MSG_ERR_NOTTY="Cannot open a terminal for interaction (/dev/tty unreadable). Download and run locally: bash install.sh"
  MSG_ERR_OS="Unsupported OS: %s (on Windows configure manually per docs, or run this script inside WSL)"
  MSG_ERR_NEED_CURL="curl is required, please install it first."
  MSG_HDR="Clauddy Setup Wizard v%s  (%s, gateway: %s)"
  MSG_LANG_HINT=""
  MSG_Q_CLIENTS="Which clients do you want to configure for Clauddy? (numbers separated by spaces, e.g.: 1 2)"
  MSG_DETECTED=" [detected]"
  MSG_DAEMON_TAG="always-on agent"
  MSG_WARN_BAD_NUM="ignoring invalid number: %s"
  MSG_ERR_NO_CLIENT="No client selected."
  MSG_REC_HDR="Recommended token groups (dedicated groups = lower ratio = cheaper):"
  MSG_REC_CLAUDE="  Claude Code      -> group %sClaude%s   (1.4x, CC clients only)"
  MSG_REC_CODEX="  Codex CLI        -> group %sOpenAI%s   (0.5x, Codex only)"
  MSG_REC_GEMINI="  Gemini CLI       -> group %sGemini%s   (1.8x)"
  MSG_REC_DAEMON="  %s  -> group %sUnified%s  (1.8x, any client — daemons must NOT use the Claude group)"
  MSG_TIP_UNIFIED1="Tip: for convenience you can instead create a single %sUnified%s-group token —"
  MSG_TIP_UNIFIED2="one key for ALL models (Claude / Codex / Gemini). Trade-off: 1.8x ratio vs 0.5x (Codex) / 1.4x (Claude)."
  MSG_PLAN_HDR="Token plan:"
  MSG_PLAN_1="  1) One token per client (recommended — groups per table above, cheapest)"
  MSG_PLAN_2="  2) One Unified token for everything — a single key for all models (most convenient, 1.8x)"
  MSG_GUIDE_FOR="Create a token for %s:"
  MSG_GUIDE_1="  1. Open the console: %s"
  MSG_GUIDE_2="  2. Create a new token and select group %s"
  MSG_GUIDE_3="  3. Copy the generated key (starts with sk-)"
  MSG_PASTE="Paste token (input hidden): "
  MSG_ERR_EMPTY="Empty input."
  MSG_WARN_SK="Tokens usually start with sk-, trying anyway…"
  MSG_ERR_3FAIL="Three validation failures in a row. Check: group is %s, balance > 0, key pasted completely."
  MSG_MENU_RETRY="Retry(r) / AI diagnosis(d, costs a little quota) / Skip this client(s) / Quit(q)? "
  MSG_MENU_HINT="Please enter r / d / s / q"
  MSG_ERR_NET="Network error, cannot reach %s"
  MSG_ERR_VERIFY="Validation failed (%s)"
  MSG_OK_KEY="key live — %s models available in this group, API latency %ss"
  MSG_DIAG_NEED_KEY="AI diagnosis needs at least one validated token (none yet in this run). Please check group and key manually."
  MSG_DIAG_NEED_PY="AI diagnosis requires python3."
  MSG_DIAG_NO_MODEL="No usable model under the validated token, cannot diagnose."
  MSG_DIAG_CALLING="Calling %s with your validated token for diagnosis (advice only, executes nothing)…"
  MSG_DIAG_CTX="Client being configured: %s (recommended group: %s)
OS: %s
Gateway: %s
Validation failure: %s"
  MSG_ERR_NO_TOKEN="No usable token, exiting."
  MSG_PURPOSE_ALL="all clients (shared)"
  MSG_PURPOSE_DAEMON="(daemons)"
  MSG_BACKUP="  (original backed up: %s)"
  MSG_OK_CLAUDE="Claude Code: wrote %s (env.ANTHROPIC_BASE_URL / ANTHROPIC_AUTH_TOKEN)"
  MSG_WARN_NO_PY_CLAUDE="python3 not found, cannot merge JSON safely. Manually add to the env block of %s:"
  MSG_TAKEOVER="[clauddy-setup takeover]"
  MSG_OK_CODEX="Codex: wrote %s (provider=clauddy%s)"
  MSG_WARN_CODEX_MODEL="No codex model found in your model list; set model = \"…\" in %s manually"
  MSG_OK_GEMINI="Gemini CLI: wrote %s"
  MSG_OK_ENVFILE="Shared env file: wrote %s (chmod 600)"
  MSG_OK_RC="Added ~/.clauddy/env loading to %s (takes effect in new terminals)"
  MSG_DONE="Done. Next steps:"
  MSG_NEXT_CLAUDE="  • Claude Code: just run %sclaude%s"
  MSG_NEXT_CODEX="  • Codex:       open a new terminal (loads CLAUDDY_API_KEY), then run %scodex%s"
  MSG_NEXT_GEMINI="  • Gemini CLI:  just run %sgemini%s"
  MSG_NEXT_DAEMON="  • %s: load ~/.clauddy/env in the daemon's runtime environment"
  MSG_NEXT_DAEMON2="      shell startup: source ~/.clauddy/env"
  MSG_NEXT_DAEMON3='      systemd unit:  EnvironmentFile=%h/.clauddy/env'
  MSG_TIP_ROUTE1="    Cost tip: point heartbeats/titles and other housekeeping at haiku / flash-lite tier models,"
  MSG_TIP_ROUTE2="    escalate to Opus only for real work — heartbeats on Opus are the most common waste."
  MSG_SKIPPED="Skipped:%s"
  MSG_HANDOFF1="  You can paste the handoff prompt (HANDOFF_PROMPT.en.md, see site docs) into your freshly"
  MSG_HANDOFF2="  configured Claude Code and let it finish the remaining clients for you."
  MSG_CHANGED="Files changed:%s (each backed up as .bak.%s)"
  MSG_FOOTER="Console: %s  ·  Token management: %s"
  MSG_HINT_CCONLY1='Hitting "This group only allows Claude Code clients" = that token is in the Claude group'
  MSG_HINT_CCONLY2="but used by a non-CC client — create a Unified / Claude3p token for that client instead."
  QL='"'; QR='"'
else
  MSG_ERR_NOTTY="无法打开终端进行交互 (/dev/tty 不可读)。请下载后本地运行: bash install.sh"
  MSG_ERR_OS="暂不支持的系统: %s (Windows 请参考文档手动配置, 或在 WSL 中运行本脚本)"
  MSG_ERR_NEED_CURL="需要 curl, 请先安装。"
  MSG_HDR="Clauddy 接入向导 v%s  (%s, 网关: %s)"
  MSG_LANG_HINT="English: rerun with --lang en"
  MSG_Q_CLIENTS="要为哪些客户端配置 Clauddy? (输入编号, 空格分隔, 如: 1 2)"
  MSG_DETECTED=" [已检测到]"
  MSG_DAEMON_TAG="常驻 agent"
  MSG_WARN_BAD_NUM="忽略无效编号: %s"
  MSG_ERR_NO_CLIENT="未选择任何客户端。"
  MSG_REC_HDR="推荐令牌分组 (专用分组倍率更低 = 更便宜):"
  MSG_REC_CLAUDE="  Claude Code      -> 分组 %sClaude%s   (1.4x, 仅 CC 客户端可用)"
  MSG_REC_CODEX="  Codex CLI        -> 分组 %sOpenAI%s   (0.5x, Codex 专用)"
  MSG_REC_GEMINI="  Gemini CLI       -> 分组 %sGemini%s   (1.8x)"
  MSG_REC_DAEMON="  %s  -> 分组 %sUnified%s  (1.8x, 不限客户端 — 守护进程勿用 Claude 组)"
  MSG_TIP_UNIFIED1="提示: 若图省事, 也可以只建一个 %sUnified%s 分组令牌 ——"
  MSG_TIP_UNIFIED2="一把 key 访问全部模型 (Claude / Codex / Gemini 通用)。代价: 倍率 1.8x (对比 Codex 专组 0.5x / Claude 专组 1.4x)。"
  MSG_PLAN_HDR="令牌方案:"
  MSG_PLAN_1="  1) 每个客户端单独令牌 (推荐 — 按上表分组, 最省钱)"
  MSG_PLAN_2="  2) 一个 Unified 令牌全部通用 — 单 key 访问所有模型 (最方便, 但倍率 1.8x)"
  MSG_GUIDE_FOR="为 %s 创建令牌:"
  MSG_GUIDE_1="  1. 打开控制台: %s"
  MSG_GUIDE_2="  2. 新建令牌, 分组选择 %s"
  MSG_GUIDE_3="  3. 复制生成的 sk- 开头的密钥"
  MSG_PASTE="粘贴令牌 (输入不回显): "
  MSG_ERR_EMPTY="输入为空。"
  MSG_WARN_SK="令牌通常以 sk- 开头, 仍尝试校验…"
  MSG_ERR_3FAIL="连续 3 次校验失败。请确认: 分组选的是 %s、余额充足、密钥完整。"
  MSG_MENU_RETRY="重试(r) / AI 诊断(d, 消耗少量额度) / 跳过此客户端(s) / 退出(q)? "
  MSG_MENU_HINT="请输入 r / d / s / q"
  MSG_ERR_NET="网络错误, 无法访问 %s"
  MSG_ERR_VERIFY="校验失败 (%s)"
  MSG_OK_KEY="key 可用 — 该分组可用模型 %s 个, 接口延迟 %ss"
  MSG_DIAG_NEED_KEY="AI 诊断需要至少一把已通过校验的令牌 (本次还没有)。请先人工核对分组与密钥。"
  MSG_DIAG_NEED_PY="AI 诊断需要 python3。"
  MSG_DIAG_NO_MODEL="已验证令牌下没有可用模型, 无法诊断。"
  MSG_DIAG_CALLING="正在用已验证的令牌调用 %s 诊断 (只输出建议, 不执行操作)…"
  MSG_DIAG_CTX="正在配置的客户端: %s (推荐分组: %s)
系统: %s
网关: %s
校验失败详情: %s"
  MSG_ERR_NO_TOKEN="没有可用令牌, 退出。"
  MSG_PURPOSE_ALL="全部客户端 (通用)"
  MSG_PURPOSE_DAEMON="(守护进程)"
  MSG_BACKUP="  (原文件已备份: %s)"
  MSG_OK_CLAUDE="Claude Code: 已写入 %s (env.ANTHROPIC_BASE_URL / ANTHROPIC_AUTH_TOKEN)"
  MSG_WARN_NO_PY_CLAUDE="未找到 python3, 无法安全合并 JSON。请手动将以下内容加入 %s 的 env 块:"
  MSG_TAKEOVER="[clauddy-setup 已接管]"
  MSG_OK_CODEX="Codex: 已写入 %s (provider=clauddy%s)"
  MSG_WARN_CODEX_MODEL="未在模型列表中找到 codex 模型, 请在 %s 中手动设置 model = \"…\""
  MSG_OK_GEMINI="Gemini CLI: 已写入 %s"
  MSG_OK_ENVFILE="通用环境文件: 已写入 %s (chmod 600)"
  MSG_OK_RC="已在 %s 中加载 ~/.clauddy/env (新开终端生效)"
  MSG_DONE="完成。下一步:"
  MSG_NEXT_CLAUDE="  • Claude Code: 直接运行 %sclaude%s"
  MSG_NEXT_CODEX="  • Codex:       新开终端 (加载 CLAUDDY_API_KEY) 后运行 %scodex%s"
  MSG_NEXT_GEMINI="  • Gemini CLI:  直接运行 %sgemini%s"
  MSG_NEXT_DAEMON="  • %s: 在守护进程运行环境中加载 ~/.clauddy/env"
  MSG_NEXT_DAEMON2="      shell 启动:   source ~/.clauddy/env"
  MSG_NEXT_DAEMON3='      systemd 单元: EnvironmentFile=%h/.clauddy/env'
  MSG_TIP_ROUTE1="    省钱提示: 心跳/标题等日常轮询建议配置到 haiku / flash-lite 档模型,"
  MSG_TIP_ROUTE2="    真正干活的轮次再用 Opus —— 常驻 agent 的心跳跑 Opus 是最常见的浪费。"
  MSG_SKIPPED="跳过了:%s"
  MSG_HANDOFF1="  可以把「接力提示词」(HANDOFF_PROMPT.zh.md, 见网站文档) 粘贴给刚配置好的"
  MSG_HANDOFF2="  Claude Code, 由它替你完成剩余客户端的接入。"
  MSG_CHANGED="改动过的文件:%s (均有 .bak.%s 备份)"
  MSG_FOOTER="控制台: %s  ·  令牌管理: %s"
  MSG_HINT_CCONLY1="遇到「该分组仅允许 Claude Code 客户端」错误 = 该令牌是 Claude 分组却被非 CC 客户端使用,"
  MSG_HINT_CCONLY2="请为该客户端另建 Unified / Claude3p 分组令牌。"
  QL="「"; QR="」"
fi

# curl | bash 时 stdin 是脚本本身, 交互必须走 /dev/tty
TTY=/dev/tty
if [ ! -r "$TTY" ]; then
  err "$MSG_ERR_NOTTY"
  exit 1
fi
ask()       { printf '%s' "$1" > "$TTY"; IFS= read -r REPLY < "$TTY"; }
ask_secret(){ printf '%s' "$1" > "$TTY"; IFS= read -rs REPLY < "$TTY"; printf '\n' > "$TTY"; }

# ---- 1. 系统检测 / system detection ------------------------------------------
OS="$(uname -s 2>/dev/null || echo unknown)"
case "$OS" in
  Darwin) OS_NAME="macOS" ;;
  Linux)  OS_NAME="Linux" ;;
  *) err "$(printf "$MSG_ERR_OS" "$OS")"; exit 1 ;;
esac
command -v curl >/dev/null 2>&1 || { err "$MSG_ERR_NEED_CURL"; exit 1; }
HAS_PY=0; command -v python3 >/dev/null 2>&1 && HAS_PY=1

say ""
say "${C_BOLD}$(printf "$MSG_HDR" "$VERSION" "$OS_NAME" "$BASE_URL")${C_RESET}"
[ -n "$MSG_LANG_HINT" ] && say "$MSG_LANG_HINT"
hr

detected() { command -v "$1" >/dev/null 2>&1 && printf '%s' "$MSG_DETECTED" || printf ''; }

# ---- 2. 客户端选择 / client selection -----------------------------------------
say "$MSG_Q_CLIENTS"
say "  1) Claude Code$(detected claude)"
say "  2) Codex CLI$(detected codex)"
say "  3) Gemini CLI$(detected gemini)"
say "  4) OpenClaw ($MSG_DAEMON_TAG)$(detected openclaw)"
say "  5) Hermes agent ($MSG_DAEMON_TAG)$(detected hermes)"
ask "> "
SEL="$REPLY"

WANT_CLAUDE=0; WANT_CODEX=0; WANT_GEMINI=0; WANT_DAEMON=0; DAEMON_NAMES=""
for n in $SEL; do
  case "$n" in
    1) WANT_CLAUDE=1 ;;
    2) WANT_CODEX=1 ;;
    3) WANT_GEMINI=1 ;;
    4) WANT_DAEMON=1; DAEMON_NAMES="$DAEMON_NAMES OpenClaw" ;;
    5) WANT_DAEMON=1; DAEMON_NAMES="$DAEMON_NAMES Hermes" ;;
    *) warn "$(printf "$MSG_WARN_BAD_NUM" "$n")" ;;
  esac
done
N_TARGETS=$((WANT_CLAUDE + WANT_CODEX + WANT_GEMINI + WANT_DAEMON))
[ "$N_TARGETS" -eq 0 ] && { err "$MSG_ERR_NO_CLIENT"; exit 1; }

# ---- 3. 令牌方案 / token plan --------------------------------------------------
say ""
say "$MSG_REC_HDR"
[ "$WANT_CLAUDE" -eq 1 ] && say "$(printf "$MSG_REC_CLAUDE" "$C_BOLD" "$C_RESET")"
[ "$WANT_CODEX"  -eq 1 ] && say "$(printf "$MSG_REC_CODEX" "$C_BOLD" "$C_RESET")"
[ "$WANT_GEMINI" -eq 1 ] && say "$(printf "$MSG_REC_GEMINI" "$C_BOLD" "$C_RESET")"
[ "$WANT_DAEMON" -eq 1 ] && say "$(printf "$MSG_REC_DAEMON" "${DAEMON_NAMES# }" "$C_BOLD" "$C_RESET")"
say ""
say "$(printf "$MSG_TIP_UNIFIED1" "$C_BOLD" "$C_RESET")"
say "$MSG_TIP_UNIFIED2"

TOKEN_MODE="per-client"
say ""
say "$MSG_PLAN_HDR"
say "$MSG_PLAN_1"
say "$MSG_PLAN_2"
ask "> "
[ "$REPLY" = "2" ] && TOKEN_MODE="unified"

# ---- 4. 令牌创建指引 + 校验 / token guide + validation --------------------------
TOKEN=""
MODELS_BODY=""
LAST_GOOD_KEY=""
LAST_ERR=""
guide_and_read() {
  local purpose="$1" group="$2" attempt=0
  say ""
  hr
  say "$(printf "$MSG_GUIDE_FOR" "${C_BOLD}${purpose}${C_RESET}")"
  say "$(printf "$MSG_GUIDE_1" "${C_BOLD}${CONSOLE_KEYS_URL}${C_RESET}")"
  say "$(printf "$MSG_GUIDE_2" "${C_BOLD}${QL}${group}${QR}${C_RESET}")"
  say "$MSG_GUIDE_3"
  while :; do
    ask_secret "$MSG_PASTE"
    TOKEN="$REPLY"
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

# AI 诊断: 用已验证的令牌向网关发一次有界调用, 只打印建议, 绝不执行任何操作。
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
    "A user's token failed validation while configuring an AI client. "
    "Gateway token groups: Claude (Claude Code clients ONLY, 1.4x); Claude3p (any client, 1.8x); "
    "ClaudeAPI (any client, 5x); OpenAI (Codex only, 0.5x); Gemini (1.8x); "
    "Unified (any client, all models, 1.8x — the convenient single-key option). "
    "Common failures: HTTP 401 = invalid or incompletely pasted token; group errors = token group does not "
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

KEY_CLAUDE=""; KEY_CODEX=""; KEY_GEMINI=""; KEY_DAEMON=""
CODEX_MODEL=""; SKIPPED=""
if [ "$TOKEN_MODE" = "unified" ]; then
  guide_and_read "$MSG_PURPOSE_ALL" "Unified" || { err "$MSG_ERR_NO_TOKEN"; exit 1; }
  [ "$WANT_CLAUDE" -eq 1 ] && KEY_CLAUDE="$TOKEN"
  [ "$WANT_CODEX"  -eq 1 ] && { KEY_CODEX="$TOKEN"; CODEX_MODEL="$(pick_model codex)"; }
  [ "$WANT_GEMINI" -eq 1 ] && KEY_GEMINI="$TOKEN"
  [ "$WANT_DAEMON" -eq 1 ] && KEY_DAEMON="$TOKEN"
else
  if [ "$WANT_CLAUDE" -eq 1 ]; then
    if guide_and_read "Claude Code" "Claude"; then KEY_CLAUDE="$TOKEN"; else SKIPPED="$SKIPPED Claude-Code"; fi
  fi
  if [ "$WANT_CODEX" -eq 1 ]; then
    if guide_and_read "Codex CLI" "OpenAI"; then KEY_CODEX="$TOKEN"; CODEX_MODEL="$(pick_model codex)"; else SKIPPED="$SKIPPED Codex"; fi
  fi
  if [ "$WANT_GEMINI" -eq 1 ]; then
    if guide_and_read "Gemini CLI" "Gemini"; then KEY_GEMINI="$TOKEN"; else SKIPPED="$SKIPPED Gemini-CLI"; fi
  fi
  if [ "$WANT_DAEMON" -eq 1 ]; then
    if guide_and_read "${DAEMON_NAMES# } $MSG_PURPOSE_DAEMON" "Unified"; then KEY_DAEMON="$TOKEN"; else SKIPPED="$SKIPPED ${DAEMON_NAMES# }"; fi
  fi
fi

# ---- 5. 写配置 (写前备份) / write configs (backup first) ------------------------
backup() { [ -f "$1" ] && cp -p "$1" "$1.bak.$STAMP" && say "$(printf "$MSG_BACKUP" "$1.bak.$STAMP")"; }
CHANGED=""

# 5.1 Claude Code: ~/.claude/settings.json env 块 (JSON 合并, 不破坏已有配置)
if [ -n "$KEY_CLAUDE" ]; then
  f="$HOME/.claude/settings.json"
  if [ "$HAS_PY" -eq 1 ]; then
    mkdir -p "$HOME/.claude"; backup "$f"
    python3 - "$f" "$BASE_URL" "$KEY_CLAUDE" <<'PYEOF'
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
    say "    \"ANTHROPIC_AUTH_TOKEN\": \"<your token>\""
  fi
fi

# 5.2 Codex CLI: ~/.codex/config.toml 托管块 + key 走环境变量 CLAUDDY_API_KEY
strip_managed_block() { # $1=file  删除旧托管块 / remove old managed blocks
  [ -f "$1" ] || return 0
  awk '/# >>> clauddy setup >>>/{skip=1} skip==0{print} /# <<< clauddy setup <<</{skip=0}' "$1" > "$1.tmp.$$" \
    && mv "$1.tmp.$$" "$1"
}
if [ -n "$KEY_CODEX" ]; then
  f="$HOME/.codex/config.toml"
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
    [ -n "$CODEX_MODEL" ] && printf 'model = "%s"\n' "$CODEX_MODEL"
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
  ok "$(printf "$MSG_OK_CODEX" "$f" "${CODEX_MODEL:+, model=$CODEX_MODEL}")"
  [ -z "$CODEX_MODEL" ] && warn "$(printf "$MSG_WARN_CODEX_MODEL" "$f")"
  CHANGED="$CHANGED $f"
  NEED_ENV_CODEX=1
else
  NEED_ENV_CODEX=0
fi

# 5.3 Gemini CLI: ~/.gemini/.env (gemini-cli 启动时自动加载)
if [ -n "$KEY_GEMINI" ]; then
  f="$HOME/.gemini/.env"
  mkdir -p "$HOME/.gemini"; backup "$f"; touch "$f"; strip_managed_block "$f"
  {
    printf '%s\n' '# >>> clauddy setup >>>'
    printf 'GOOGLE_GEMINI_BASE_URL="%s"\n' "$BASE_URL"
    printf 'GEMINI_API_KEY="%s"\n' "$KEY_GEMINI"
    printf '%s\n' '# <<< clauddy setup <<<'
  } >> "$f"
  chmod 600 "$f"
  ok "$(printf "$MSG_OK_GEMINI" "$f")"
  CHANGED="$CHANGED $f"
fi

# 5.4 通用环境文件 ~/.clauddy/env — 守护进程 + Codex 的 env_key 从这里加载
if [ -n "$KEY_DAEMON" ] || [ "$NEED_ENV_CODEX" -eq 1 ]; then
  f="$HOME/.clauddy/env"
  mkdir -p "$HOME/.clauddy"; backup "$f"; touch "$f"; strip_managed_block "$f"
  {
    printf '%s\n' '# >>> clauddy setup >>>'
    if [ "$NEED_ENV_CODEX" -eq 1 ]; then
      printf 'export CLAUDDY_API_KEY="%s"\n' "$KEY_CODEX"
    fi
    if [ -n "$KEY_DAEMON" ]; then
      printf 'export ANTHROPIC_BASE_URL="%s"\n' "$BASE_URL"
      printf 'export ANTHROPIC_AUTH_TOKEN="%s"\n' "$KEY_DAEMON"
      printf 'export ANTHROPIC_API_KEY="%s"\n' "$KEY_DAEMON"
      printf 'export OPENAI_BASE_URL="%s/v1"\n' "$BASE_URL"
      printf 'export OPENAI_API_KEY="%s"\n' "$KEY_DAEMON"
      printf 'export GOOGLE_GEMINI_BASE_URL="%s"\n' "$BASE_URL"
      printf 'export GEMINI_API_KEY="%s"\n' "$KEY_DAEMON"
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
fi

# ---- 6. 总结 / summary ---------------------------------------------------------
say ""
hr
say "${C_BOLD}${MSG_DONE}${C_RESET}"
[ -n "$KEY_CLAUDE" ] && say "$(printf "$MSG_NEXT_CLAUDE" "$C_BOLD" "$C_RESET")"
[ -n "$KEY_CODEX" ]  && say "$(printf "$MSG_NEXT_CODEX" "$C_BOLD" "$C_RESET")"
[ -n "$KEY_GEMINI" ] && say "$(printf "$MSG_NEXT_GEMINI" "$C_BOLD" "$C_RESET")"
if [ -n "$KEY_DAEMON" ]; then
  say "$(printf "$MSG_NEXT_DAEMON" "${DAEMON_NAMES# }")"
  say "$MSG_NEXT_DAEMON2"
  say "$MSG_NEXT_DAEMON3"
  say "${C_YELLOW}${MSG_TIP_ROUTE1}${C_RESET}"
  say "$MSG_TIP_ROUTE2"
fi
if [ -n "$SKIPPED" ] && [ -n "$KEY_CLAUDE" ]; then
  say ""
  say "${C_YELLOW}$(printf "$MSG_SKIPPED" "$SKIPPED")${C_RESET}"
  say "$MSG_HANDOFF1"
  say "$MSG_HANDOFF2"
fi
[ -n "$CHANGED" ] && say "$(printf "$MSG_CHANGED" "$CHANGED" "$STAMP")"
say "$(printf "$MSG_FOOTER" "$CONSOLE_URL" "$CONSOLE_KEYS_URL")"
say "$MSG_HINT_CCONLY1"
say "$MSG_HINT_CCONLY2"
