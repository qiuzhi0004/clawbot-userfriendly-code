#!/usr/bin/env bash
set -euo pipefail

INSTALL_SCRIPT_URL="https://openclaw.ai/install.sh"
PROVIDER=""
API_KEY=""
FEISHU_APP_ID=""
FEISHU_APP_SECRET=""
FEISHU_GROUP_POLICY=""
FEISHU_GROUP_ALLOW_FROM=""
SKILLS=""
HOOKS=""
PAIRING_CODE=""
NO_WEB=0

WIZARD_SERVER_PID=""
WIZARD_SUBMIT_FILE=""
WIZARD_PAIRING_FILE=""
TMP_DIR=""

log_info() {
  printf '\033[36m%s\033[0m\n' "$1"
}

log_warn() {
  printf '\033[33m%s\033[0m\n' "$1"
}

log_error() {
  printf '\033[31m%s\033[0m\n' "$1" >&2
}

cleanup() {
  if [[ -n "$WIZARD_SERVER_PID" ]]; then
    kill "$WIZARD_SERVER_PID" >/dev/null 2>&1 || true
    wait "$WIZARD_SERVER_PID" >/dev/null 2>&1 || true
    WIZARD_SERVER_PID=""
  fi
  if [[ -n "$TMP_DIR" && -d "$TMP_DIR" ]]; then
    rm -rf "$TMP_DIR"
  fi
}
trap cleanup EXIT

trim() {
  local value="$1"
  # shellcheck disable=SC2001
  value="$(printf '%s' "$value" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
  printf '%s' "$value"
}

lower_trim() {
  local value
  value="$(trim "$1")"
  printf '%s' "$value" | tr '[:upper:]' '[:lower:]'
}

json_string() {
  python3 - "$1" <<'PY'
import json
import sys
print(json.dumps(sys.argv[1], ensure_ascii=False))
PY
}

json_array_from_csv() {
  python3 - "$1" <<'PY'
import json
import sys
raw = sys.argv[1]
items = [p.strip() for p in raw.split(',') if p.strip()]
print(json.dumps(items, ensure_ascii=False))
PY
}

normalize_provider() {
  local normalized
  normalized="$(lower_trim "$1")"
  case "$normalized" in
    ""|"1"|"k"|"kimi"|"kimi-code"|"kimicode")
      printf 'kimi-code'
      ;;
    "2"|"m"|"minimax")
      printf 'minimax'
      ;;
    "3"|"moon"|"moonshot")
      printf 'moonshot'
      ;;
    "4"|"glm"|"z.ai"|"zai"|"zai-api-key")
      printf 'zai'
      ;;
    "zai-global")
      printf 'zai-global'
      ;;
    "zai-cn")
      printf 'zai-cn'
      ;;
    "zai-coding-global")
      printf 'zai-coding-global'
      ;;
    "zai-coding-cn")
      printf 'zai-coding-cn'
      ;;
    *)
      printf '%s' "$normalized"
      ;;
  esac
}

normalize_csv_by_allowlist() {
  local raw="$1"
  local allowed_csv="$2"
  python3 - "$raw" "$allowed_csv" <<'PY'
import re
import sys

raw = sys.argv[1]
allowed = set([x for x in sys.argv[2].split(',') if x])
if not raw.strip():
    print("")
    raise SystemExit(0)
seen = []
for part in re.split(r"[,\s]+", raw.strip()):
    item = part.strip().lower()
    if not item:
        continue
    if item in allowed and item not in seen:
        seen.append(item)
print(",".join(seen))
PY
}

normalize_skills() {
  normalize_csv_by_allowlist "$1" "web-search,autonomy,summarize,github,nano-pdf,openai-whisper"
}

normalize_hooks() {
  normalize_csv_by_allowlist "$1" "session-memory,command-logger,boot-md"
}

normalize_feishu_group_policy() {
  local value
  value="$(lower_trim "$1")"
  case "$value" in
    allowlist|disabled|open)
      printf '%s' "$value"
      ;;
    *)
      printf 'open'
      ;;
  esac
}

normalize_feishu_group_allow_from() {
  python3 - "$1" <<'PY'
import re
import sys

raw = sys.argv[1]
if not raw.strip():
    print("")
    raise SystemExit(0)
seen = []
for part in re.split(r"[,\r\n\t ]+", raw.strip()):
    item = part.strip()
    if not item:
        continue
    if item not in seen:
        seen.append(item)
print(",".join(seen))
PY
}

require_arg_value() {
  local flag="$1"
  local value="${2:-}"
  if [[ -z "$value" ]]; then
    log_error "Missing value for ${flag}"
    exit 1
  fi
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -InstallScriptUrl|--install-script-url)
        require_arg_value "$1" "${2:-}"
        INSTALL_SCRIPT_URL="$2"
        shift 2
        ;;
      -Provider|--provider)
        require_arg_value "$1" "${2:-}"
        PROVIDER="$2"
        shift 2
        ;;
      -ApiKey|--api-key)
        require_arg_value "$1" "${2:-}"
        API_KEY="$2"
        shift 2
        ;;
      -FeishuAppId|--feishu-app-id)
        require_arg_value "$1" "${2:-}"
        FEISHU_APP_ID="$2"
        shift 2
        ;;
      -FeishuAppSecret|--feishu-app-secret)
        require_arg_value "$1" "${2:-}"
        FEISHU_APP_SECRET="$2"
        shift 2
        ;;
      -FeishuGroupPolicy|--feishu-group-policy)
        require_arg_value "$1" "${2:-}"
        FEISHU_GROUP_POLICY="$2"
        shift 2
        ;;
      -FeishuGroupAllowFrom|--feishu-group-allow-from)
        require_arg_value "$1" "${2:-}"
        FEISHU_GROUP_ALLOW_FROM="$2"
        shift 2
        ;;
      -Skills|--skills)
        require_arg_value "$1" "${2:-}"
        SKILLS="$2"
        shift 2
        ;;
      -Hooks|--hooks)
        require_arg_value "$1" "${2:-}"
        HOOKS="$2"
        shift 2
        ;;
      -PairingCode|--pairing-code)
        require_arg_value "$1" "${2:-}"
        PAIRING_CODE="$2"
        shift 2
        ;;
      -NoWeb|--no-web)
        NO_WEB=1
        shift
        ;;
      -h|--help)
        cat <<'HELP_EOF'
Usage: ./install-web-v2-mac.sh [options]

Options:
  -InstallScriptUrl, --install-script-url <url>
  -Provider, --provider <provider>
  -ApiKey, --api-key <key>
  -FeishuAppId, --feishu-app-id <id>
  -FeishuAppSecret, --feishu-app-secret <secret>
  -FeishuGroupPolicy, --feishu-group-policy <open|allowlist|disabled>
  -FeishuGroupAllowFrom, --feishu-group-allow-from <ids>
  -Skills, --skills <comma_or_space_separated>
  -Hooks, --hooks <comma_or_space_separated>
  -PairingCode, --pairing-code <code>
  -NoWeb, --no-web
HELP_EOF
        exit 0
        ;;
      *)
        log_error "Unknown argument: $1"
        exit 1
        ;;
    esac
  done
}

ensure_prerequisites() {
  if ! command -v curl >/dev/null 2>&1; then
    log_error "curl is required. Please install curl and retry."
    exit 1
  fi
  if ! command -v bash >/dev/null 2>&1; then
    log_error "bash is required."
    exit 1
  fi
  if ! command -v python3 >/dev/null 2>&1; then
    log_error "python3 is required for this installer. Please install python3 and retry."
    exit 1
  fi
}

get_free_port() {
  python3 - <<'PY'
import socket
s = socket.socket()
s.bind(("127.0.0.1", 0))
print(s.getsockname()[1])
s.close()
PY
}

refresh_process_path() {
  local candidates=()
  local npm_prefix=""
  npm_prefix="$(npm config get prefix 2>/dev/null || true)"
  if [[ -n "$npm_prefix" && "$npm_prefix" != "undefined" ]]; then
    candidates+=("$npm_prefix/bin")
  fi
  candidates+=("$HOME/.npm-global/bin" "$HOME/.local/bin" "/opt/homebrew/bin" "/usr/local/bin")

  local candidate
  for candidate in "${candidates[@]}"; do
    [[ -d "$candidate" ]] || continue
    case ":$PATH:" in
      *":$candidate:"*) ;;
      *) PATH="$candidate:$PATH" ;;
    esac
  done
  export PATH
}

ensure_openclaw_on_path() {
  if command -v openclaw >/dev/null 2>&1; then
    return 0
  fi

  refresh_process_path
  if command -v openclaw >/dev/null 2>&1; then
    return 0
  fi

  local npm_prefix=""
  npm_prefix="$(npm config get prefix 2>/dev/null || true)"
  if [[ -n "$npm_prefix" && -x "$npm_prefix/bin/openclaw" ]]; then
    PATH="$npm_prefix/bin:$PATH"
    export PATH
    return 0
  fi

  return 1
}

open_url() {
  local url="$1"
  if command -v open >/dev/null 2>&1; then
    open "$url" >/dev/null 2>&1 && return 0
  fi
  return 1
}

get_control_ui_url() {
  local base_path="/"
  local raw
  raw="$(openclaw config get gateway.controlUi.basePath 2>/dev/null | head -n1 || true)"
  if [[ -n "$raw" ]]; then
    raw="${raw%\"}"
    raw="${raw#\"}"
    raw="${raw%\'}"
    raw="${raw#\'}"
    if [[ -n "$raw" && "$raw" != "null" ]]; then
      base_path="$raw"
    fi
  fi
  [[ "$base_path" == /* ]] || base_path="/$base_path"
  [[ "$base_path" == */ ]] || base_path="$base_path/"
  printf 'http://127.0.0.1:18789%s' "$base_path"
}

get_gateway_token() {
  if [[ -n "${OPENCLAW_GATEWAY_TOKEN:-}" ]]; then
    printf '%s' "$(trim "$OPENCLAW_GATEWAY_TOKEN")"
    return
  fi

  local raw
  raw="$(openclaw config get gateway.auth.token 2>/dev/null | head -n1 || true)"
  raw="$(trim "$raw")"
  raw="${raw%\"}"
  raw="${raw#\"}"
  raw="${raw%\'}"
  raw="${raw#\'}"
  if [[ -z "$raw" || "$raw" == "null" ]]; then
    printf ''
    return
  fi
  printf '%s' "$raw"
}

url_encode() {
  python3 - "$1" <<'PY'
import sys
import urllib.parse
print(urllib.parse.quote(sys.argv[1], safe=''))
PY
}

build_control_ui_open_url() {
  local base_url="$1"
  local token="$2"
  if [[ -z "$token" ]]; then
    printf '%s' "$base_url"
    return
  fi
  local sep="?"
  [[ "$base_url" == *"?"* ]] && sep="&"
  printf '%s%stoken=%s' "$base_url" "$sep" "$(url_encode "$token")"
}

open_dashboard() {
  local base_url="$1"
  local open_url_value="$2"
  local token="$3"

  if openclaw dashboard >/dev/null 2>&1; then
    log_info "Dashboard opened via openclaw dashboard."
    return
  fi

  if open_url "$open_url_value"; then
    log_info "Dashboard opened: $base_url"
    if [[ -n "$token" ]]; then
      log_info "Gateway token has been attached automatically."
    else
      log_warn "Gateway token not found. Paste token in Control UI settings if prompted."
      log_warn "You can also run: openclaw dashboard"
    fi
    return
  fi

  log_warn "Open Dashboard manually: $base_url"
  if [[ -n "$token" ]]; then
    log_warn "Gateway token: $token"
  else
    log_warn "Token source: gateway.auth.token or OPENCLAW_GATEWAY_TOKEN"
  fi
}

apply_selected_skills() {
  local skills_csv="$1"
  local provider_value="$2"
  local api_key_value="$3"

  [[ -n "$skills_csv" ]] || return

  local skill
  IFS=',' read -r -a skill_items <<<"$skills_csv"
  for skill in "${skill_items[@]}"; do
    skill="$(trim "$skill")"
    [[ -n "$skill" ]] || continue
    case "$skill" in
      web-search)
        local search_provider="${OPENCLAW_SEARCH_PROVIDER:-}"
        local search_api_key="${OPENCLAW_SEARCH_API_KEY:-}"
        search_provider="$(lower_trim "$search_provider")"
        if [[ -n "$search_provider" && -n "$search_api_key" ]]; then
          if [[ "$search_provider" == "brave" ]]; then
            openclaw config set tools.web.search.provider brave >/dev/null
            openclaw config set tools.web.search.apiKey "$search_api_key" >/dev/null
            openclaw config set tools.web.search.enabled true >/dev/null
            continue
          fi
          if [[ "$search_provider" == "kimi" ]]; then
            openclaw config set tools.web.search.provider kimi >/dev/null
            openclaw config set tools.web.search.kimi.apiKey "$search_api_key" >/dev/null
            openclaw config set tools.web.search.enabled true >/dev/null
            continue
          fi
        fi
        if [[ "$provider_value" == "moonshot" ]]; then
          openclaw config set tools.web.search.provider kimi >/dev/null
          openclaw config set tools.web.search.kimi.apiKey "$api_key_value" >/dev/null
          openclaw config set tools.web.search.enabled true >/dev/null
          continue
        fi
        openclaw config set tools.web.search.enabled false >/dev/null
        ;;
      autonomy)
        openclaw config set skills.entries.coding-agent.enabled true >/dev/null
        openclaw config set skills.entries.tmux.enabled true >/dev/null
        openclaw config set skills.entries.healthcheck.enabled true >/dev/null
        openclaw config set skills.entries.session-logs.enabled true >/dev/null
        ;;
      *)
        log_warn "[!] Skipped ${skill}: requires extra tooling not handled in mac installer."
        ;;
    esac
  done
}

apply_selected_hooks() {
  local hooks_csv="$1"
  [[ -n "$hooks_csv" ]] || return

  openclaw config set hooks.internal.enabled true >/dev/null

  local hook
  IFS=',' read -r -a hook_items <<<"$hooks_csv"
  for hook in "${hook_items[@]}"; do
    hook="$(trim "$hook")"
    [[ -n "$hook" ]] || continue
    if ! openclaw hooks enable "$hook" >/dev/null 2>&1; then
      log_warn "[!] Failed to enable hook ${hook}."
    fi
  done
}

write_wizard_template() {
  local template_file="$1"
  cat >"$template_file" <<'HTML_EOF'
<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>OpenClaw 安装向导（macOS）</title>
  <style>
    :root { color-scheme: light; --bg:#f4edff; --panel:#ffffff; --line:#0f172a; --text:#111827; --muted:#4b5563; --accent:#3b82f6; --accent-soft:#dbeafe; --ok:#16a34a; --warn:#f97316; }
    * { box-sizing:border-box; }
    body { margin:0; font-family:"PingFang SC","Noto Sans SC","Microsoft YaHei",sans-serif; background:var(--bg); color:var(--text); padding:18px; }
    .wizard { width:min(1280px,100%); margin:0 auto; border:4px solid var(--line); border-radius:22px; background:var(--panel); padding:18px; }
    .header { display:flex; justify-content:space-between; gap:12px; align-items:center; border:4px solid var(--line); border-radius:18px; padding:14px 18px; }
    .header h1 { margin:0; font-size:34px; line-height:1.1; }
    .step-chip { border:4px solid var(--line); border-radius:999px; padding:8px 16px; font-size:24px; font-weight:800; background:#fff; }
    .content { margin-top:16px; display:grid; grid-template-columns:minmax(460px,1fr) minmax(420px,1fr); gap:16px; }
    .panel { border:4px solid var(--line); border-radius:18px; padding:18px; background:#fff; min-height:620px; }
    .step-page { display:none; height:100%; }
    .step-page.active { display:block; }
    .step-title { display:inline-block; margin:0 0 12px; background:#dcfce7; border:2px solid var(--line); border-radius:8px; font-size:34px; line-height:1.15; padding:4px 10px; }
    .step-subtitle { margin:0 0 12px; font-size:22px; color:var(--muted); }
    .guide-list { margin:0; padding-left:24px; font-size:25px; line-height:1.55; }
    .guide-list li { margin:5px 0; }
    .field { display:grid; gap:8px; margin-top:14px; }
    .field-title { font-size:21px; font-weight:800; }
    input[type="text"], select { width:100%; border:2px solid #64748b; border-radius:12px; padding:14px; font-size:20px; background:#fffbeb; }
    .skills-block { margin-top:10px; display:grid; gap:10px; }
    .skill-item { display:grid; grid-template-columns:34px 1fr; gap:10px; border:2px solid #cbd5e1; border-radius:12px; padding:10px; background:#f8fafc; }
    .skill-item input { width:24px; height:24px; margin-top:4px; accent-color:#4f46e5; }
    .skill-name { display:block; font-weight:800; font-size:22px; }
    .skill-desc { display:block; color:var(--muted); font-size:19px; line-height:1.45; }
    .code-wrap { margin-top:14px; border:2px solid #cbd5e1; border-radius:12px; padding:12px; background:#f8fafc; }
    .copy-row { display:flex; justify-content:flex-end; margin-bottom:8px; }
    .copy-btn { border:2px solid var(--line); border-radius:10px; background:#fff; font-size:17px; font-weight:700; padding:6px 10px; cursor:pointer; }
    pre { margin:0; white-space:pre-wrap; font-size:17px; line-height:1.55; overflow:auto; }
    .links a { color:var(--warn); font-size:20px; font-weight:700; text-decoration:none; line-height:1.8; }
    .links a:hover { text-decoration:underline; }
    .right-title { margin:0 0 10px; font-size:24px; font-weight:800; }
    .shot-frame { width:100%; height:520px; border:3px solid var(--line); border-radius:12px; background:#f8fafc; display:flex; align-items:center; justify-content:center; padding:8px; overflow:hidden; }
    .shot-placeholder { width:100%; height:100%; border-radius:8px; display:flex; align-items:center; justify-content:center; text-align:center; padding:18px; color:#0f172a; font-size:24px; font-weight:900; line-height:1.35; border:2px dashed rgba(15,23,42,.35); background:linear-gradient(135deg,#fcd34d,#fb7185); }
    .shot-note { margin-top:10px; font-size:18px; color:var(--muted); line-height:1.5; }
    .shot-tip { margin-top:8px; font-size:16px; color:#334155; }
    .nav { margin-top:16px; display:flex; justify-content:space-between; align-items:center; gap:10px; }
    .dots { display:flex; gap:8px; }
    .dot { width:14px; height:14px; border-radius:999px; border:2px solid var(--line); background:#fff; }
    .dot.active { background:#f472b6; }
    .btn { border:3px solid var(--line); border-radius:14px; background:#c7d2fe; font-size:24px; font-weight:800; padding:8px 20px; cursor:pointer; }
    .btn[disabled] { opacity:.55; cursor:not-allowed; }
    .btn-next { background:#93c5fd; }
    .submit-btn { border:3px solid var(--line); border-radius:14px; background:#86efac; font-size:24px; font-weight:900; padding:10px 20px; cursor:pointer; }
    @media (max-width:1080px) {
      .header h1 { font-size:28px; }
      .step-chip { font-size:20px; }
      .content { grid-template-columns:1fr; }
      .panel { min-height:auto; }
      .shot-frame { height:360px; }
    }
  </style>
</head>
<body>
  <main class="wizard">
    <div class="header">
      <h1>🦞 OpenClaw 安装引导（macOS）</h1>
      <div class="step-chip" id="step-chip">Step 1 / 9</div>
    </div>
    <form method="post" action="/submit" id="wizard-form">
      <div class="content">
        <section class="panel">
          <div class="step-page active" data-step="1">
            <h2 class="step-title">1. 配置大模型 API Key</h2>
            <p class="step-subtitle">选择模型供应商并填写 API Key</p>
            <ol class="guide-list">
              <li>打开模型供应商官网注册账号并创建 API Key。</li>
              <li>将 API Key 粘贴到当前输入框。</li>
              <li>推荐先使用 Kimi Code 或 GLM（Z.AI 自动）。</li>
            </ol>
            <div class="field">
              <span class="field-title">模型厂商</span>
              <select id="provider" name="provider">
                <option value="kimi-code">Kimi Code（推荐）</option>
                <option value="moonshot">Moonshot（月之暗面）</option>
                <option value="minimax">MiniMax</option>
                <option value="zai">GLM（Z.AI 自动）</option>
                <option value="zai-coding-global">GLM Coding（Global）</option>
                <option value="zai-coding-cn">GLM Coding（CN）</option>
              </select>
            </div>
            <div class="field">
              <span class="field-title" id="api-key-label">API Key</span>
              <input id="apiKey" name="apiKey" type="text" autocomplete="off" required>
            </div>
            <div class="links">
              <a href="https://platform.moonshot.cn" target="_blank">Moonshot 官网</a><br>
              <a href="https://platform.minimaxi.com" target="_blank">MiniMax 官网</a><br>
              <a href="https://bigmodel.cn/console/overview" target="_blank">Z.AI 官网</a><br>
              <a href="https://platform.moonshot.cn/console/api-keys" target="_blank">Kimi/Moonshot API Key 页面</a>
            </div>
          </div>
          <div class="step-page" data-step="2">
            <h2 class="step-title">2. 配置飞书机器人</h2>
            <ol class="guide-list">
              <li>创建应用</li>
              <li>获取凭证</li>
              <li>添加机器人能力</li>
              <li>开通权限</li>
              <li>启用长连接</li>
              <li>发布应用</li>
            </ol>
            <div class="field">
              <span class="field-title">飞书 App ID</span>
              <input id="feishuAppId" name="feishuAppId" type="text" autocomplete="off" placeholder="cli_xxx" required>
            </div>
            <div class="field">
              <span class="field-title">飞书 App Secret</span>
              <input id="feishuAppSecret" name="feishuAppSecret" type="text" autocomplete="off" required>
            </div>
          </div>
          <div class="step-page" data-step="3">
            <h2 class="step-title">3. 选择群组访问策略</h2>
            <p class="step-subtitle">按需限制机器人可响应的群组范围</p>
            <div class="field">
              <span class="field-title">群组策略（channels.feishu.groupPolicy）</span>
              <select id="feishuGroupPolicy" name="feishuGroupPolicy">
                <option value="open">open（允许所有群组，默认）</option>
                <option value="allowlist">allowlist（仅允许白名单群组）</option>
                <option value="disabled">disabled（禁用群组消息）</option>
              </select>
            </div>
            <div class="field">
              <span class="field-title">群组白名单（仅 allowlist 生效）</span>
              <input id="feishuGroupAllowFrom" name="feishuGroupAllowFrom" type="text" autocomplete="off" placeholder="oc_xxx,oc_yyy">
            </div>
          </div>
          <div class="step-page" data-step="4">
            <h2 class="step-title">4. 选择 Skill</h2>
            <p class="step-subtitle">可多选，部分技能在 macOS 仅做配置</p>
            <section class="skills-block">
              <label class="skill-item">
                <input id="skill-web-search" name="skills" type="checkbox" value="web-search">
                <span><span class="skill-name">网页搜索</span><span class="skill-desc">启用内置网页搜索。</span></span>
              </label>
              <label class="skill-item">
                <input id="skill-autonomy" name="skills" type="checkbox" value="autonomy">
                <span><span class="skill-name">自主执行</span><span class="skill-desc">启用内置自动化能力。</span></span>
              </label>
              <label class="skill-item">
                <input id="skill-summarize" name="skills" type="checkbox" value="summarize">
                <span><span class="skill-name">网页总结</span><span class="skill-desc">需要额外工具，默认仅写入配置。</span></span>
              </label>
              <label class="skill-item">
                <input id="skill-nano-pdf" name="skills" type="checkbox" value="nano-pdf">
                <span><span class="skill-name">PDF 处理</span><span class="skill-desc">需要额外工具，默认仅写入配置。</span></span>
              </label>
              <label class="skill-item">
                <input id="skill-openai-whisper" name="skills" type="checkbox" value="openai-whisper">
                <span><span class="skill-name">音频转文字</span><span class="skill-desc">需要额外工具，默认仅写入配置。</span></span>
              </label>
              <label class="skill-item">
                <input id="skill-github" name="skills" type="checkbox" value="github">
                <span><span class="skill-name">GitHub 能力</span><span class="skill-desc">需要额外工具，默认仅写入配置。</span></span>
              </label>
            </section>
          </div>
          <div class="step-page" data-step="5">
            <h2 class="step-title">5. 启用 Hooks</h2>
            <p class="step-subtitle">可多选，推荐启用会话记忆与命令日志</p>
            <section class="skills-block">
              <label class="skill-item">
                <input id="hook-session-memory" name="hooks" type="checkbox" value="session-memory">
                <span><span class="skill-name">session-memory</span><span class="skill-desc">在 /new 时保存会话记忆。</span></span>
              </label>
              <label class="skill-item">
                <input id="hook-command-logger" name="hooks" type="checkbox" value="command-logger">
                <span><span class="skill-name">command-logger</span><span class="skill-desc">记录命令事件到日志。</span></span>
              </label>
              <label class="skill-item">
                <input id="hook-boot-md" name="hooks" type="checkbox" value="boot-md">
                <span><span class="skill-name">boot-md</span><span class="skill-desc">Gateway 启动时执行工作区 BOOT.md。</span></span>
              </label>
            </section>
            <div class="code-wrap">
              <p style="margin:0 0 10px;font-size:18px;color:#475569;">确认前几步配置后，点击“开始安装”。安装会在终端执行。</p>
              <button type="button" class="submit-btn" id="start-install-btn">开始安装</button>
            </div>
          </div>
          <div class="step-page" data-step="6">
            <h2 class="step-title">6. 等待安装</h2>
            <ol class="guide-list">
              <li>安装已在终端启动，请等待完成。</li>
              <li>脚本会执行官方 install.sh（带 --no-onboard）并自动完成后续配置。</li>
              <li>首次运行可能安装/检查 Node.js 与 npm，请按终端提示操作。</li>
              <li>终端出现 Installed and configured successfully 后再继续。</li>
            </ol>
            <div class="code-wrap">
              <p id="install-status" style="margin:0 0 12px;font-size:18px;color:#334155;">尚未开始安装，请先返回上一步点击“开始安装”。</p>
              <button type="button" class="copy-btn" id="confirm-install-btn" disabled>我已看到安装完成，继续配对</button>
            </div>
          </div>
          <div class="step-page" data-step="7">
            <h2 class="step-title">7. 飞书配对</h2>
            <ol class="guide-list">
              <li>打开飞书找到机器人。</li>
              <li>发送一条消息。</li>
              <li>获取配对码。</li>
              <li>粘贴到输入框。</li>
            </ol>
            <div class="field">
              <span class="field-title">配对码（可选）</span>
              <input id="pairingCode" name="pairingCode" type="text" autocomplete="off" placeholder="PAIRING_CODE">
            </div>
          </div>
          <div class="step-page" data-step="8">
            <h2 class="step-title">8. 提交配对码</h2>
            <ol class="guide-list">
              <li>安装完成后粘贴配对码并点击“提交配对码并执行”。</li>
              <li>提交成功后脚本会直接执行配对，无需再打开新页面。</li>
            </ol>
            <div class="field">
              <span class="field-title">配对码</span>
              <input id="pairingCodeSubmit" type="text" autocomplete="off" placeholder="PAIRING_CODE">
            </div>
            <div class="code-wrap">
              <button type="button" class="submit-btn" id="submit-pairing-btn">提交配对码并执行</button>
              <p id="pairing-submit-status" style="margin:10px 0 0;font-size:17px;color:#334155;">等待提交配对码。</p>
            </div>
          </div>
          <div class="step-page" data-step="9">
            <h2 class="step-title">9. 安装完成后常用命令</h2>
            <div class="code-wrap">
              <div class="copy-row"><button type="button" class="copy-btn" data-copy-target="cmd-block">一键复制命令</button></div>
              <pre id="cmd-block">openclaw gateway start   # 启动网关
openclaw gateway stop    # 停止网关
openclaw gateway restart # 重启网关
openclaw dashboard       # 打开管理面板
openclaw models list     # 查看可用模型
openclaw skills          # 查看已安装技能
openclaw doctor --fix    # 修复常见环境问题</pre>
            </div>
            <div class="links" style="margin-top:12px;">
              <a href="https://openclaw.ai" target="_blank">OpenClaw 官网</a><br>
              <a href="https://docs.openclaw.ai" target="_blank">官方文档</a><br>
              <a href="https://github.com/openclaw/openclaw" target="_blank">GitHub 仓库</a><br>
              <a href="http://localhost:18789" target="_blank">Dashboard 管理面板</a>
            </div>
            <div class="code-wrap">
              <p style="margin:0;font-size:18px;color:#334155;">完成配对后即可开始使用 OpenClaw。</p>
            </div>
          </div>
        </section>
        <aside class="panel">
          <h3 class="right-title" id="shot-title">步骤示意</h3>
          <div class="shot-frame">
            <div id="shot-placeholder" class="shot-placeholder">步骤示意占位区</div>
          </div>
          <p class="shot-note" id="shot-note">这里预留为图示说明区域，当前使用色块占位。</p>
          <p class="shot-tip">后续可替换为真实截图，不影响安装流程。</p>
        </aside>
      </div>
      <div class="nav">
        <button type="button" class="btn" id="prev-btn">← 上一步</button>
        <div class="dots" id="dots"></div>
        <button type="button" class="btn btn-next" id="next-btn">下一步 →</button>
      </div>
    </form>
  </main>
  <script>
    var defaultProvider = __DEFAULT_PROVIDER_JSON__;
    var defaultSkills = __DEFAULT_SKILLS_JSON__;
    var defaultHooks = __DEFAULT_HOOKS_JSON__;
    var defaultFeishuGroupPolicy = __DEFAULT_FEISHU_GROUP_POLICY_JSON__;
    var defaultFeishuGroupAllowFrom = __DEFAULT_FEISHU_GROUP_ALLOW_FROM_JSON__;

    var labels = {
      "kimi-code":"Kimi Code API Key",
      "moonshot":"Moonshot API Key",
      "minimax":"MiniMax API Key",
      "zai":"Z.AI API Key",
      "zai-coding-global":"Z.AI API Key",
      "zai-coding-cn":"Z.AI API Key"
    };

    var stepMeta = [
      { title: "步骤 1：配置模型", note: "请先创建并粘贴 API Key。", swatch:["#fcd34d", "#fb7185"] },
      { title: "步骤 2：配置飞书机器人", note: "填写飞书 App ID 与 App Secret。", swatch:["#a7f3d0", "#22d3ee"] },
      { title: "步骤 3：群组访问策略", note: "配置群组策略与可选白名单。", swatch:["#bfdbfe", "#818cf8"] },
      { title: "步骤 4：选择 Skill", note: "根据需要选择技能。", swatch:["#fde68a", "#fb7185"] },
      { title: "步骤 5：启用 Hooks", note: "按需启用事件驱动自动化 Hooks。", swatch:["#bbf7d0", "#34d399"] },
      { title: "步骤 6：等待安装", note: "终端将执行 macOS 安装与配置流程。", swatch:["#fecaca", "#f97316"] },
      { title: "步骤 7：飞书配对", note: "可先填写配对码，也可安装后填写。", swatch:["#ddd6fe", "#a78bfa"] },
      { title: "步骤 8：提交配对码", note: "在当前页面提交配对码并执行配对。", swatch:["#d9f99d", "#84cc16"] },
      { title: "步骤 9：完成与常用命令", note: "复制常用命令并开始使用。", swatch:["#e2e8f0", "#94a3b8"] }
    ];

    var totalSteps = stepMeta.length;
    var currentStep = 1;
    var installSubmitted = false;
    var installConfirmed = false;

    var providerEl = document.getElementById("provider");
    var labelEl = document.getElementById("api-key-label");
    var feishuGroupPolicyEl = document.getElementById("feishuGroupPolicy");
    var feishuGroupAllowFromEl = document.getElementById("feishuGroupAllowFrom");

    var webSearchEl = document.getElementById("skill-web-search");
    var autonomyEl = document.getElementById("skill-autonomy");
    var summarizeEl = document.getElementById("skill-summarize");
    var nanoPdfEl = document.getElementById("skill-nano-pdf");
    var whisperEl = document.getElementById("skill-openai-whisper");
    var githubEl = document.getElementById("skill-github");

    var hookSessionMemoryEl = document.getElementById("hook-session-memory");
    var hookCommandLoggerEl = document.getElementById("hook-command-logger");
    var hookBootMdEl = document.getElementById("hook-boot-md");

    var pages = document.querySelectorAll(".step-page");
    var prevBtn = document.getElementById("prev-btn");
    var nextBtn = document.getElementById("next-btn");
    var dotsEl = document.getElementById("dots");
    var stepChipEl = document.getElementById("step-chip");
    var shotTitleEl = document.getElementById("shot-title");
    var shotNoteEl = document.getElementById("shot-note");
    var shotPlaceholderEl = document.getElementById("shot-placeholder");

    var startInstallBtn = document.getElementById("start-install-btn");
    var installStatusEl = document.getElementById("install-status");
    var confirmInstallBtn = document.getElementById("confirm-install-btn");
    var pairingCodeEl = document.getElementById("pairingCode");
    var pairingCodeSubmitEl = document.getElementById("pairingCodeSubmit");
    var submitPairingBtn = document.getElementById("submit-pairing-btn");
    var pairingSubmitStatusEl = document.getElementById("pairing-submit-status");

    providerEl.value = defaultProvider || "kimi-code";
    webSearchEl.checked = defaultSkills.includes("web-search");
    autonomyEl.checked = defaultSkills.includes("autonomy");
    summarizeEl.checked = defaultSkills.includes("summarize");
    nanoPdfEl.checked = defaultSkills.includes("nano-pdf");
    whisperEl.checked = defaultSkills.includes("openai-whisper");
    githubEl.checked = defaultSkills.includes("github");

    hookSessionMemoryEl.checked = defaultHooks.includes("session-memory");
    hookCommandLoggerEl.checked = defaultHooks.includes("command-logger");
    hookBootMdEl.checked = defaultHooks.includes("boot-md");

    feishuGroupPolicyEl.value = defaultFeishuGroupPolicy || "open";
    feishuGroupAllowFromEl.value = defaultFeishuGroupAllowFrom || "";

    function updateApiLabel() {
      labelEl.textContent = labels[providerEl.value] || "API Key";
    }

    function ensureValidStep(current) {
      if (current === 1) {
        if (!providerEl.value || !document.getElementById("apiKey").value.trim()) {
          alert("请先填写模型厂商和 API Key。");
          return false;
        }
      }
      if (current === 2) {
        if (!document.getElementById("feishuAppId").value.trim() || !document.getElementById("feishuAppSecret").value.trim()) {
          alert("请先填写飞书 App ID 和 App Secret。");
          return false;
        }
      }
      if (current === 3) {
        var policy = feishuGroupPolicyEl.value || "open";
        var allowFrom = feishuGroupAllowFromEl.value ? feishuGroupAllowFromEl.value.trim() : "";
        if (policy === "allowlist" && !allowFrom) {
          alert("allowlist 策略需要至少填写一个群组 ID。");
          return false;
        }
      }
      return true;
    }

    function encodeFormValue(value) {
      return encodeURIComponent(value).replace(/%20/g, "+");
    }

    function buildSubmitBody() {
      var parts = [];
      parts.push("provider=" + encodeFormValue(providerEl.value || ""));
      parts.push("apiKey=" + encodeFormValue(document.getElementById("apiKey").value || ""));
      parts.push("feishuAppId=" + encodeFormValue(document.getElementById("feishuAppId").value || ""));
      parts.push("feishuAppSecret=" + encodeFormValue(document.getElementById("feishuAppSecret").value || ""));
      parts.push("feishuGroupPolicy=" + encodeFormValue(feishuGroupPolicyEl.value || "open"));
      parts.push("feishuGroupAllowFrom=" + encodeFormValue(feishuGroupAllowFromEl.value || ""));
      parts.push("pairingCode=");

      var skillEls = document.querySelectorAll("input[name='skills']:checked");
      for (var s = 0; s < skillEls.length; s++) {
        parts.push("skills=" + encodeFormValue(skillEls[s].value || ""));
      }

      var hookEls = document.querySelectorAll("input[name='hooks']:checked");
      for (var h = 0; h < hookEls.length; h++) {
        parts.push("hooks=" + encodeFormValue(hookEls[h].value || ""));
      }
      return parts.join("&");
    }

    function startInstall() {
      if (!ensureValidStep(1) || !ensureValidStep(2) || !ensureValidStep(3)) {
        return;
      }
      startInstallBtn.disabled = true;
      startInstallBtn.textContent = "安装启动中...";
      installStatusEl.textContent = "正在提交配置并启动安装...";

      var xhr = new XMLHttpRequest();
      xhr.open("POST", "/submit", true);
      xhr.setRequestHeader("Content-Type", "application/x-www-form-urlencoded; charset=UTF-8");
      xhr.onreadystatechange = function () {
        if (xhr.readyState !== 4) {
          return;
        }
        if (xhr.status >= 200 && xhr.status < 300) {
          installSubmitted = true;
          installStatusEl.textContent = "安装已启动。请等待终端完成安装后点击“我已看到安装完成”。";
          confirmInstallBtn.disabled = false;
          currentStep = 6;
          renderStep();
          return;
        }
        startInstallBtn.disabled = false;
        startInstallBtn.textContent = "开始安装";
        installStatusEl.textContent = "启动安装失败，请检查必填项后重试。";
        alert("启动安装失败，请检查输入后重试。");
      };
      xhr.send(buildSubmitBody());
    }

    function submitPairingCode() {
      var code = pairingCodeSubmitEl.value ? pairingCodeSubmitEl.value.trim() : "";
      if (!code) {
        pairingSubmitStatusEl.textContent = "请先填写配对码。";
        return;
      }
      submitPairingBtn.disabled = true;
      submitPairingBtn.textContent = "提交中...";
      pairingSubmitStatusEl.textContent = "正在提交配对码...";

      var xhr = new XMLHttpRequest();
      xhr.open("POST", "/pairing-submit", true);
      xhr.setRequestHeader("Content-Type", "application/x-www-form-urlencoded; charset=UTF-8");
      xhr.onreadystatechange = function () {
        if (xhr.readyState !== 4) {
          return;
        }
        if (xhr.status >= 200 && xhr.status < 300) {
          pairingSubmitStatusEl.textContent = "配对码提交成功，脚本正在执行配对。";
          currentStep = 9;
          renderStep();
          return;
        }
        submitPairingBtn.disabled = false;
        submitPairingBtn.textContent = "提交配对码并执行";
        pairingSubmitStatusEl.textContent = "提交失败，请确认安装已完成后重试。";
      };
      xhr.send("pairingCode=" + encodeFormValue(code));
    }

    function renderStep() {
      for (var p = 0; p < pages.length; p++) {
        var page = pages[p];
        var pageStep = Number(page.getAttribute("data-step"));
        page.classList.toggle("active", pageStep === currentStep);
      }

      stepChipEl.textContent = "Step " + currentStep + " / " + totalSteps;
      shotTitleEl.textContent = stepMeta[currentStep - 1].title;
      shotNoteEl.textContent = stepMeta[currentStep - 1].note;

      var swatch = stepMeta[currentStep - 1].swatch;
      shotPlaceholderEl.style.background = "linear-gradient(135deg," + swatch[0] + "," + swatch[1] + ")";
      shotPlaceholderEl.textContent = stepMeta[currentStep - 1].title + "\n图示占位";

      prevBtn.disabled = currentStep === 1;
      nextBtn.style.display = (currentStep === totalSteps || currentStep === 5) ? "none" : "inline-block";
      if (currentStep === 6) {
        nextBtn.disabled = !installConfirmed;
      } else {
        nextBtn.disabled = false;
      }

      dotsEl.innerHTML = "";
      for (var i = 1; i <= totalSteps; i++) {
        var dot = document.createElement("span");
        dot.className = "dot" + (i === currentStep ? " active" : "");
        dotsEl.appendChild(dot);
      }
    }

    function copyText(content) {
      if (navigator.clipboard && navigator.clipboard.writeText) {
        navigator.clipboard.writeText(content);
        return;
      }
      var area = document.createElement("textarea");
      area.value = content;
      document.body.appendChild(area);
      area.select();
      document.execCommand("copy");
      document.body.removeChild(area);
    }

    providerEl.addEventListener("change", updateApiLabel);
    prevBtn.addEventListener("click", function () {
      currentStep = Math.max(1, currentStep - 1);
      renderStep();
    });

    nextBtn.addEventListener("click", function () {
      if (!ensureValidStep(currentStep)) {
        return;
      }
      if (currentStep === 6 && !installConfirmed) {
        return;
      }
      currentStep = Math.min(totalSteps, currentStep + 1);
      renderStep();
    });

    if (startInstallBtn) {
      startInstallBtn.addEventListener("click", startInstall);
    }

    if (confirmInstallBtn) {
      confirmInstallBtn.addEventListener("click", function () {
        if (!installSubmitted) {
          installStatusEl.textContent = "请先返回上一步点击“开始安装”。";
          return;
        }
        installConfirmed = true;
        installStatusEl.textContent = "已确认安装完成，请点击右下角“下一步”继续配对。";
        renderStep();
      });
    }

    if (pairingCodeEl) {
      pairingCodeEl.addEventListener("input", function () {
        if (!pairingCodeSubmitEl.value || !pairingCodeSubmitEl.value.trim()) {
          pairingCodeSubmitEl.value = pairingCodeEl.value || "";
        }
      });
    }

    if (submitPairingBtn) {
      submitPairingBtn.addEventListener("click", submitPairingCode);
    }

    document.getElementById("wizard-form").addEventListener("submit", function (event) {
      event.preventDefault();
    });

    var copyButtons = document.querySelectorAll("[data-copy-target]");
    for (var b = 0; b < copyButtons.length; b++) {
      (function (button) {
        button.addEventListener("click", function () {
          var targetId = button.getAttribute("data-copy-target");
          var target = document.getElementById(targetId);
          if (!target) {
            return;
          }
          copyText(target.textContent || "");
          button.textContent = "已复制";
          setTimeout(function () {
            button.textContent = "一键复制命令";
          }, 1200);
        });
      })(copyButtons[b]);
    }

    updateApiLabel();
    if (pairingCodeEl && pairingCodeSubmitEl) {
      pairingCodeSubmitEl.value = pairingCodeEl.value || "";
    }
    renderStep();
  </script>
</body>
</html>
HTML_EOF
}

render_wizard_html() {
  local template_file="$1"
  local output_file="$2"
  local default_provider="$3"
  local default_skills_csv="$4"
  local default_hooks_csv="$5"
  local default_feishu_group_policy="$6"
  local default_feishu_group_allow_from="$7"

  local provider_json
  local skills_json
  local hooks_json
  local feishu_group_policy_json
  local feishu_group_allow_from_json

  provider_json="$(json_string "$default_provider")"
  skills_json="$(json_array_from_csv "$default_skills_csv")"
  hooks_json="$(json_array_from_csv "$default_hooks_csv")"
  feishu_group_policy_json="$(json_string "$default_feishu_group_policy")"
  feishu_group_allow_from_json="$(json_string "$default_feishu_group_allow_from")"

  python3 - "$template_file" "$output_file" "$provider_json" "$skills_json" "$hooks_json" "$feishu_group_policy_json" "$feishu_group_allow_from_json" <<'PY'
from pathlib import Path
import sys

template_path = Path(sys.argv[1])
output_path = Path(sys.argv[2])
provider_json = sys.argv[3]
skills_json = sys.argv[4]
hooks_json = sys.argv[5]
feishu_group_policy_json = sys.argv[6]
feishu_group_allow_from_json = sys.argv[7]

html = template_path.read_text(encoding="utf-8")
html = html.replace("__DEFAULT_PROVIDER_JSON__", provider_json)
html = html.replace("__DEFAULT_SKILLS_JSON__", skills_json)
html = html.replace("__DEFAULT_HOOKS_JSON__", hooks_json)
html = html.replace("__DEFAULT_FEISHU_GROUP_POLICY_JSON__", feishu_group_policy_json)
html = html.replace("__DEFAULT_FEISHU_GROUP_ALLOW_FROM_JSON__", feishu_group_allow_from_json)
output_path.write_text(html, encoding="utf-8")
PY
}

start_wizard_server() {
  local port="$1"
  local html_file="$2"
  local submit_file="$3"
  local pairing_file="$4"
  local ready_file="$5"

  python3 - "$port" "$html_file" "$submit_file" "$pairing_file" "$ready_file" <<'PY' &
import http.server
import json
import urllib.parse
import sys
from pathlib import Path

port = int(sys.argv[1])
html = Path(sys.argv[2]).read_text(encoding="utf-8")
submit_file = Path(sys.argv[3])
pairing_file = Path(sys.argv[4])
ready_file = Path(sys.argv[5])

success_html = """<!doctype html>
<html lang=\"zh-CN\">
<head>
  <meta charset=\"utf-8\">
  <meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">
  <title>OpenClaw 安装中</title>
  <style>
    body { margin:0; min-height:100vh; display:grid; place-items:center; background:linear-gradient(135deg,#f7f3ea,#f2e7d2); color:#2d2418; font-family:\"PingFang SC\",\"Noto Sans SC\",\"Microsoft YaHei\",sans-serif; padding:24px; }
    .panel { width:min(560px,100%); background:rgba(255,252,246,.96); border:1px solid rgba(216,199,171,.9); border-radius:20px; padding:28px; box-shadow:0 24px 60px rgba(45,36,24,.10); }
    h1 { margin:0 0 10px; font-size:30px; }
    p { margin:0; line-height:1.7; color:#695744; }
  </style>
</head>
<body>
  <main class=\"panel\">
    <h1>已开始安装</h1>
    <p>配置已经收到，终端正在继续执行安装。这个页面可以直接关掉。</p>
  </main>
</body>
</html>"""


def normalize_items(values):
    result = []
    for item in values:
        item = (item or "").strip().lower()
        if item and item not in result:
            result.append(item)
    return result


class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        return

    def _respond(self, status, body, content_type="text/html; charset=utf-8"):
        payload = body.encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def do_GET(self):
        if self.path == "/":
            self._respond(200, html)
            return
        self._respond(404, "not found", "text/plain; charset=utf-8")

    def do_POST(self):
        length = int(self.headers.get("Content-Length", "0"))
        body = self.rfile.read(length).decode("utf-8", "replace")
        parsed = urllib.parse.parse_qs(body, keep_blank_values=True)

        if self.path == "/submit":
            provider = (parsed.get("provider", [""])[0] or "").strip().lower()
            api_key = (parsed.get("apiKey", [""])[0] or "").strip()
            app_id = (parsed.get("feishuAppId", [""])[0] or "").strip()
            app_secret = (parsed.get("feishuAppSecret", [""])[0] or "").strip()
            group_policy = (parsed.get("feishuGroupPolicy", ["open"])[0] or "open").strip().lower() or "open"
            group_allow_from = (parsed.get("feishuGroupAllowFrom", [""])[0] or "").strip()
            pairing_code = (parsed.get("pairingCode", [""])[0] or "").strip()

            if provider and api_key and app_id and app_secret:
                payload = {
                    "provider": provider,
                    "apiKey": api_key,
                    "feishuAppId": app_id,
                    "feishuAppSecret": app_secret,
                    "feishuGroupPolicy": group_policy,
                    "feishuGroupAllowFrom": group_allow_from,
                    "skillsCsv": ",".join(normalize_items(parsed.get("skills", []))),
                    "hooksCsv": ",".join(normalize_items(parsed.get("hooks", []))),
                    "pairingCode": pairing_code,
                }
                submit_file.write_text(json.dumps(payload, ensure_ascii=False), encoding="utf-8")
                self._respond(200, success_html)
                return

            self._respond(400, "missing required fields", "text/plain; charset=utf-8")
            return

        if self.path == "/pairing-submit":
            pairing_code = (parsed.get("pairingCode", [""])[0] or "").strip()
            if pairing_code:
                payload = {"pairingCode": pairing_code}
                pairing_file.write_text(json.dumps(payload, ensure_ascii=False), encoding="utf-8")
                self._respond(200, "{\"ok\":true}", "application/json; charset=utf-8")
                return
            self._respond(400, "{\"ok\":false,\"message\":\"missing pairing code\"}", "application/json; charset=utf-8")
            return

        self._respond(404, "not found", "text/plain; charset=utf-8")


server = http.server.ThreadingHTTPServer(("127.0.0.1", port), Handler)
ready_file.write_text("ready", encoding="utf-8")
try:
    server.serve_forever()
finally:
    server.server_close()
PY
  WIZARD_SERVER_PID="$!"
}

wait_for_file() {
  local file_path="$1"
  local timeout_seconds="$2"
  local start_ts
  start_ts="$(date +%s)"

  while true; do
    if [[ -s "$file_path" ]]; then
      return 0
    fi
    local now_ts
    now_ts="$(date +%s)"
    if (( now_ts - start_ts >= timeout_seconds )); then
      return 1
    fi
    sleep 1
  done
}

load_submit_payload() {
  local submit_file="$1"
  # shellcheck disable=SC2046
  eval "$(python3 - "$submit_file" <<'PY'
import json
import shlex
import sys

path = sys.argv[1]
with open(path, encoding="utf-8") as f:
    data = json.load(f)

pairs = {
    "WEB_PROVIDER": data.get("provider", ""),
    "WEB_API_KEY": data.get("apiKey", ""),
    "WEB_FEISHU_APP_ID": data.get("feishuAppId", ""),
    "WEB_FEISHU_APP_SECRET": data.get("feishuAppSecret", ""),
    "WEB_FEISHU_GROUP_POLICY": data.get("feishuGroupPolicy", ""),
    "WEB_FEISHU_GROUP_ALLOW_FROM": data.get("feishuGroupAllowFrom", ""),
    "WEB_SKILLS": data.get("skillsCsv", ""),
    "WEB_HOOKS": data.get("hooksCsv", ""),
    "WEB_PAIRING_CODE": data.get("pairingCode", ""),
}
for key, value in pairs.items():
    print(f"{key}={shlex.quote(str(value))}")
PY
)"
}

read_pairing_payload() {
  local pairing_file="$1"
  python3 - "$pairing_file" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as f:
    data = json.load(f)
print((data.get("pairingCode") or "").strip())
PY
}

wait_for_pairing_code_from_wizard() {
  local pairing_file="$1"
  local timeout_seconds="$2"
  local start_ts
  start_ts="$(date +%s)"

  while true; do
    if [[ -s "$pairing_file" ]]; then
      local code
      code="$(read_pairing_payload "$pairing_file" || true)"
      code="$(trim "$code")"
      if [[ -n "$code" ]]; then
        printf '%s' "$code"
        return 0
      fi
    fi

    local now_ts
    now_ts="$(date +%s)"
    if (( now_ts - start_ts >= timeout_seconds )); then
      return 1
    fi
    sleep 1
  done
}

get_web_config() {
  local default_provider="$1"
  local default_skills_csv="$2"
  local default_hooks_csv="$3"
  local default_feishu_group_policy="$4"
  local default_feishu_group_allow_from="$5"

  TMP_DIR="$(mktemp -d)"

  local template_file="$TMP_DIR/wizard.template.html"
  local html_file="$TMP_DIR/wizard.html"
  local ready_file="$TMP_DIR/wizard.ready"
  WIZARD_SUBMIT_FILE="$TMP_DIR/wizard.submit.json"
  WIZARD_PAIRING_FILE="$TMP_DIR/wizard.pairing.json"

  write_wizard_template "$template_file"
  render_wizard_html "$template_file" "$html_file" "$default_provider" "$default_skills_csv" "$default_hooks_csv" "$default_feishu_group_policy" "$default_feishu_group_allow_from"

  local port
  port="$(get_free_port)"

  start_wizard_server "$port" "$html_file" "$WIZARD_SUBMIT_FILE" "$WIZARD_PAIRING_FILE" "$ready_file"

  if ! wait_for_file "$ready_file" 15; then
    log_error "Failed to start web setup server."
    return 1
  fi

  local url="http://127.0.0.1:${port}/"
  if ! open_url "$url"; then
    log_info "Open this URL in your browser: $url"
  fi

  if ! wait_for_file "$WIZARD_SUBMIT_FILE" 900; then
    log_warn "Web setup timed out after 15 minutes."
    return 1
  fi

  load_submit_payload "$WIZARD_SUBMIT_FILE"
  return 0
}

parse_args "$@"
ensure_prerequisites

provider_value="$PROVIDER"
api_key_value="$API_KEY"
feishu_app_id_value="$FEISHU_APP_ID"
feishu_app_secret_value="$FEISHU_APP_SECRET"
feishu_group_policy_value="$FEISHU_GROUP_POLICY"
feishu_group_allow_from_value="$FEISHU_GROUP_ALLOW_FROM"
skills_value="$SKILLS"
hooks_value="$HOOKS"
pairing_code_value="$PAIRING_CODE"

[[ -n "$provider_value" ]] || provider_value="${OPENCLAW_PROVIDER:-}"
[[ -n "$api_key_value" ]] || api_key_value="${OPENCLAW_API_KEY:-}"
[[ -n "$feishu_app_id_value" ]] || feishu_app_id_value="${OPENCLAW_FEISHU_APP_ID:-}"
[[ -n "$feishu_app_secret_value" ]] || feishu_app_secret_value="${OPENCLAW_FEISHU_APP_SECRET:-}"
[[ -n "$feishu_group_policy_value" ]] || feishu_group_policy_value="${OPENCLAW_FEISHU_GROUP_POLICY:-}"
[[ -n "$feishu_group_allow_from_value" ]] || feishu_group_allow_from_value="${OPENCLAW_FEISHU_GROUP_ALLOW_FROM:-}"
[[ -n "$skills_value" ]] || skills_value="${OPENCLAW_SKILLS:-}"
[[ -n "$hooks_value" ]] || hooks_value="${OPENCLAW_HOOKS:-}"
[[ -n "$pairing_code_value" ]] || pairing_code_value="${OPENCLAW_PAIRING_CODE:-}"

if [[ -z "$(trim "$api_key_value")" || -z "$(trim "$feishu_app_id_value")" || -z "$(trim "$feishu_app_secret_value")" ]]; then
  if [[ "$NO_WEB" -eq 0 ]]; then
    defaults_provider="$(normalize_provider "$provider_value")"
    defaults_skills="$(normalize_skills "$skills_value")"
    defaults_hooks="$(normalize_hooks "$hooks_value")"
    defaults_feishu_group_policy="$(normalize_feishu_group_policy "$feishu_group_policy_value")"
    defaults_feishu_group_allow_from="$(normalize_feishu_group_allow_from "$feishu_group_allow_from_value")"

    if get_web_config "$defaults_provider" "$defaults_skills" "$defaults_hooks" "$defaults_feishu_group_policy" "$defaults_feishu_group_allow_from"; then
      provider_value="$WEB_PROVIDER"
      api_key_value="$WEB_API_KEY"
      feishu_app_id_value="$WEB_FEISHU_APP_ID"
      feishu_app_secret_value="$WEB_FEISHU_APP_SECRET"
      feishu_group_policy_value="$WEB_FEISHU_GROUP_POLICY"
      feishu_group_allow_from_value="$WEB_FEISHU_GROUP_ALLOW_FROM"
      skills_value="$WEB_SKILLS"
      hooks_value="$WEB_HOOKS"
      if [[ -z "$(trim "$pairing_code_value")" ]]; then
        pairing_code_value="$WEB_PAIRING_CODE"
      fi
    fi
  fi
fi

if [[ -z "$(trim "$api_key_value")" || -z "$(trim "$feishu_app_id_value")" || -z "$(trim "$feishu_app_secret_value")" ]]; then
  log_error "Missing required config. Set OPENCLAW_API_KEY, OPENCLAW_FEISHU_APP_ID, OPENCLAW_FEISHU_APP_SECRET or use web setup."
  exit 1
fi

provider_value="$(normalize_provider "$provider_value")"
skills_value="$(normalize_skills "$skills_value")"
hooks_value="$(normalize_hooks "$hooks_value")"
feishu_group_policy_value="$(normalize_feishu_group_policy "$feishu_group_policy_value")"
feishu_group_allow_from_value="$(normalize_feishu_group_allow_from "$feishu_group_allow_from_value")"

log_info "Installing OpenClaw CLI on macOS (official install.sh --no-onboard)..."
if [[ "$INSTALL_SCRIPT_URL" == https://* ]]; then
  curl -fsSL --proto '=https' --tlsv1.2 "$INSTALL_SCRIPT_URL" | bash -s -- --no-onboard
else
  curl -fsSL "$INSTALL_SCRIPT_URL" | bash -s -- --no-onboard
fi

refresh_process_path
if ! ensure_openclaw_on_path; then
  log_error "OpenClaw not found on PATH. Restart terminal or add npm global bin to PATH."
  exit 1
fi

openclaw doctor --fix >/dev/null 2>&1 || true

auth_choice="kimi-code-api-key"
key_flag="--kimi-code-api-key"

if [[ "$provider_value" == "moonshot" ]]; then
  auth_choice="moonshot-api-key"
  key_flag="--moonshot-api-key"
elif [[ "$provider_value" == "minimax" ]]; then
  auth_choice="minimax-api"
  key_flag="--minimax-api-key"
elif [[ "$provider_value" == "zai" ]]; then
  auth_choice="zai-api-key"
  key_flag="--zai-api-key"
elif [[ "$provider_value" == "zai-global" ]]; then
  auth_choice="zai-global"
  key_flag="--zai-api-key"
elif [[ "$provider_value" == "zai-cn" ]]; then
  auth_choice="zai-cn"
  key_flag="--zai-api-key"
elif [[ "$provider_value" == "zai-coding-global" ]]; then
  auth_choice="zai-coding-global"
  key_flag="--zai-api-key"
elif [[ "$provider_value" == "zai-coding-cn" ]]; then
  auth_choice="zai-coding-cn"
  key_flag="--zai-api-key"
fi

openclaw onboard --non-interactive --accept-risk --mode local --auth-choice "$auth_choice" "$key_flag" "$api_key_value" --skip-channels --skip-daemon --skip-skills --skip-ui --skip-health --gateway-bind loopback --gateway-port 18789

if ! openclaw plugins enable feishu >/dev/null 2>&1; then
  openclaw plugins install @openclaw/feishu >/dev/null
  openclaw plugins enable feishu >/dev/null
fi

openclaw config set channels.feishu.enabled true >/dev/null
openclaw config set channels.feishu.accounts.default.appId "$feishu_app_id_value" >/dev/null
openclaw config set channels.feishu.accounts.default.appSecret "$feishu_app_secret_value" >/dev/null

dm_policy="${OPENCLAW_FEISHU_DM_POLICY:-}"
if [[ -z "$(trim "$dm_policy")" ]]; then
  dm_policy="pairing"
fi
openclaw config set channels.feishu.dmPolicy "$dm_policy" >/dev/null
if [[ "$dm_policy" == "open" ]]; then
  openclaw config set channels.feishu.allowFrom '["*"]' --strict-json >/dev/null
else
  openclaw config unset channels.feishu.allowFrom >/dev/null
fi

openclaw config set channels.feishu.groupPolicy "$feishu_group_policy_value" >/dev/null
if [[ "$feishu_group_policy_value" == "allowlist" && -n "$feishu_group_allow_from_value" ]]; then
  feishu_group_allow_from_json="$(json_array_from_csv "$feishu_group_allow_from_value")"
  openclaw config set channels.feishu.groupAllowFrom "$feishu_group_allow_from_json" --strict-json >/dev/null
else
  openclaw config unset channels.feishu.groupAllowFrom >/dev/null
fi

apply_selected_skills "$skills_value" "$provider_value" "$api_key_value"
apply_selected_hooks "$hooks_value"

openclaw gateway install >/dev/null 2>&1 || true
openclaw gateway start >/dev/null 2>&1 || true

dashboard_opened=0
dashboard_url="$(get_control_ui_url)"
dashboard_token="$(get_gateway_token)"
dashboard_open_url="$(build_control_ui_open_url "$dashboard_url" "$dashboard_token")"

if [[ -z "$(trim "$pairing_code_value")" && "$NO_WEB" -eq 0 && -n "$WIZARD_SERVER_PID" ]]; then
  log_info "Waiting for pairing code submission in the same setup page..."
  open_dashboard "$dashboard_url" "$dashboard_open_url" "$dashboard_token"
  dashboard_opened=1
  pairing_code_value="$(wait_for_pairing_code_from_wizard "$WIZARD_PAIRING_FILE" 1800 || true)"
fi

if [[ -n "$pairing_code_value" ]]; then
  openclaw pairing approve feishu "$pairing_code_value" >/dev/null
  log_info "Feishu pairing completed."
else
  log_warn "Feishu pairing skipped. You can run: openclaw pairing approve feishu <Pairing code>"
fi

if [[ "$dashboard_opened" -eq 0 ]]; then
  open_dashboard "$dashboard_url" "$dashboard_open_url" "$dashboard_token"
fi

log_info "Installed and configured successfully."
log_info "Provider: $provider_value"
log_info "Feishu groupPolicy: $feishu_group_policy_value"
if [[ "$feishu_group_policy_value" == "allowlist" && -n "$feishu_group_allow_from_value" ]]; then
  log_info "Feishu groupAllowFrom: $feishu_group_allow_from_value"
fi
if [[ -n "$skills_value" ]]; then
  log_info "Selected Skills: $skills_value"
fi
if [[ -n "$hooks_value" ]]; then
  log_info "Selected Hooks: $hooks_value"
fi
