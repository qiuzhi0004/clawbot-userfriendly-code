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
REPO_RAW_BASE_URL="${REPO_RAW_BASE_URL:-https://raw.githubusercontent.com/qiuzhi0004/clawbot-userfriendly-code/main}"
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
Usage: ./install-web-v2-mac-dry-run.sh [options]

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

One-line start from a brand-new macOS terminal:
  curl -fsSL https://raw.githubusercontent.com/qiuzhi0004/clawbot-userfriendly-code/main/install-web-v2-mac-dry-run.sh | bash
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

open_url() {
  local url="$1"
  if command -v open >/dev/null 2>&1; then
    open "$url" >/dev/null 2>&1 && return 0
  fi
  return 1
}

write_dry_run_wizard_html() {
  local html_file="$1"
  cat >"$html_file" <<'HTML_EOF'
<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>OpenClaw 安装向导（Dry Run）</title>
  <style>
    :root { --bg:#f4edff; --panel:#fff; --line:#0f172a; --text:#111827; --muted:#4b5563; }
    * { box-sizing:border-box; }
    body { margin:0; padding:18px; font-family:"PingFang SC","Noto Sans SC","Microsoft YaHei",sans-serif; background:var(--bg); color:var(--text); }
    .wizard { width:min(1200px,100%); margin:0 auto; border:4px solid var(--line); border-radius:20px; background:var(--panel); padding:16px; }
    .header { display:flex; justify-content:space-between; align-items:center; border:4px solid var(--line); border-radius:14px; padding:12px 16px; }
    .header h1 { margin:0; font-size:30px; }
    .chip { border:3px solid var(--line); border-radius:999px; padding:6px 12px; font-size:20px; font-weight:800; background:#fff; }
    .content { display:grid; grid-template-columns:minmax(420px,1fr) minmax(320px,420px); gap:14px; margin-top:14px; }
    .panel { border:3px solid var(--line); border-radius:14px; padding:14px; background:#fff; }
    .step-page { display:none; }
    .step-page.active { display:block; }
    .step-title { margin:0 0 8px; font-size:30px; }
    .step-sub { margin:0 0 10px; color:var(--muted); font-size:19px; }
    .guide-list { margin:0; padding-left:20px; font-size:20px; line-height:1.5; }
    .field { margin-top:12px; display:grid; gap:6px; }
    .field label { font-weight:800; font-size:18px; }
    .field input, .field select { border:2px solid #64748b; border-radius:10px; padding:10px; font-size:17px; background:#fffbeb; }
    .cta { margin-top:12px; border:3px solid var(--line); border-radius:10px; padding:10px 14px; font-size:18px; font-weight:900; background:#86efac; cursor:pointer; }
    .status { margin-top:10px; color:#334155; font-size:16px; }
    .placeholder { min-height:420px; border:3px solid var(--line); border-radius:12px; padding:16px; background:linear-gradient(135deg,#fcd34d,#fb7185); color:#0f172a; font-size:24px; font-weight:900; display:flex; align-items:center; justify-content:center; text-align:center; }
    .side-note { margin-top:10px; color:var(--muted); font-size:16px; }
    .nav { margin-top:14px; display:flex; justify-content:space-between; gap:10px; }
    .btn { border:3px solid var(--line); border-radius:10px; background:#c7d2fe; font-size:20px; font-weight:800; padding:8px 14px; cursor:pointer; }
    .btn[disabled] { opacity:.45; cursor:not-allowed; }
    @media (max-width:960px) {
      .content { grid-template-columns:1fr; }
      .header h1 { font-size:24px; }
    }
  </style>
</head>
<body>
  <main class="wizard">
    <div class="header">
      <h1>🦞 OpenClaw 安装引导（Dry Run）</h1>
      <div class="chip" id="chip">Step 1 / 9</div>
    </div>
    <div class="content">
      <section class="panel">
        <div class="step-page active" data-step="1">
          <h2 class="step-title">1. 配置大模型 API Key</h2>
          <p class="step-sub">Dry Run 页面：可点击查看完整流程，不会真实安装。</p>
          <div class="field"><label>模型厂商</label><select><option>Kimi Code</option><option>Moonshot</option><option>MiniMax</option><option>Z.AI</option></select></div>
          <div class="field"><label>API Key</label><input placeholder="sk-xxxx"></div>
        </div>
        <div class="step-page" data-step="2">
          <h2 class="step-title">2. 配置飞书机器人</h2>
          <ol class="guide-list"><li>填写 App ID</li><li>填写 App Secret</li><li>确认权限与发布</li></ol>
          <div class="field"><label>飞书 App ID</label><input placeholder="cli_xxx"></div>
          <div class="field"><label>飞书 App Secret</label><input placeholder="secret_xxx"></div>
        </div>
        <div class="step-page" data-step="3">
          <h2 class="step-title">3. 选择群组访问策略</h2>
          <div class="field"><label>群组策略</label><select><option>open</option><option>allowlist</option><option>disabled</option></select></div>
          <div class="field"><label>群组白名单</label><input placeholder="oc_xxx,oc_yyy"></div>
        </div>
        <div class="step-page" data-step="4">
          <h2 class="step-title">4. 选择 Skill</h2>
          <ol class="guide-list"><li>web-search</li><li>autonomy</li><li>summarize</li><li>github</li></ol>
        </div>
        <div class="step-page" data-step="5">
          <h2 class="step-title">5. 启用 Hooks</h2>
          <ol class="guide-list"><li>session-memory</li><li>command-logger</li><li>boot-md</li></ol>
          <button class="cta" id="startBtn" type="button">开始安装（模拟）</button>
          <p class="status" id="installStatus">点击按钮后会跳到“等待安装”步骤。</p>
        </div>
        <div class="step-page" data-step="6">
          <h2 class="step-title">6. 等待安装</h2>
          <ol class="guide-list"><li>这里是 Dry Run，不会执行真实安装。</li><li>仅用于演示完整步骤和页面。</li></ol>
        </div>
        <div class="step-page" data-step="7">
          <h2 class="step-title">7. 飞书配对</h2>
          <div class="field"><label>配对码（可选）</label><input placeholder="PAIRING_CODE"></div>
        </div>
        <div class="step-page" data-step="8">
          <h2 class="step-title">8. 提交配对码</h2>
          <button class="cta" id="pairBtn" type="button">提交配对码并执行（模拟）</button>
          <p class="status" id="pairStatus">点击后会跳到第 9 步。</p>
        </div>
        <div class="step-page" data-step="9">
          <h2 class="step-title">9. 安装完成后常用命令</h2>
          <ol class="guide-list"><li>openclaw gateway start</li><li>openclaw dashboard</li><li>openclaw models list</li></ol>
          <p class="status">Dry Run 完成：页面流程演示结束。</p>
        </div>
      </section>
      <aside class="panel">
        <div class="placeholder" id="placeholder">步骤示意占位区</div>
        <p class="side-note" id="sideNote">这里用于展示每个步骤的说明示意。</p>
      </aside>
    </div>
    <div class="nav">
      <button class="btn" id="prevBtn" type="button">← 上一步</button>
      <button class="btn" id="nextBtn" type="button">下一步 →</button>
    </div>
  </main>
  <script>
    var step=1,total=9;
    var notes=["配置模型","配置飞书","群组策略","选择 Skill","启用 Hooks","等待安装","飞书配对","提交配对码","完成与命令"];
    var colors=[["#fcd34d","#fb7185"],["#a7f3d0","#22d3ee"],["#bfdbfe","#818cf8"],["#fde68a","#fb7185"],["#bbf7d0","#34d399"],["#fecaca","#f97316"],["#ddd6fe","#a78bfa"],["#d9f99d","#84cc16"],["#e2e8f0","#94a3b8"]];
    var pages=document.querySelectorAll(".step-page");
    var chip=document.getElementById("chip");
    var sideNote=document.getElementById("sideNote");
    var placeholder=document.getElementById("placeholder");
    var prevBtn=document.getElementById("prevBtn");
    var nextBtn=document.getElementById("nextBtn");
    function render(){
      for(var i=0;i<pages.length;i++){
        var n=Number(pages[i].getAttribute("data-step"));
        pages[i].classList.toggle("active", n===step);
      }
      chip.textContent="Step "+step+" / "+total;
      sideNote.textContent="当前步骤："+notes[step-1]+"（Dry Run 页面）";
      placeholder.style.background="linear-gradient(135deg,"+colors[step-1][0]+","+colors[step-1][1]+")";
      placeholder.textContent="Step "+step+"\\n"+notes[step-1];
      prevBtn.disabled=step===1;
      nextBtn.disabled=step===total;
    }
    prevBtn.addEventListener("click", function(){ step=Math.max(1, step-1); render(); });
    nextBtn.addEventListener("click", function(){ step=Math.min(total, step+1); render(); });
    document.getElementById("startBtn").addEventListener("click", function(){
      document.getElementById("installStatus").textContent="已模拟开始安装，跳转到第 6 步。";
      step=6; render();
    });
    document.getElementById("pairBtn").addEventListener("click", function(){
      document.getElementById("pairStatus").textContent="已模拟提交配对码，跳转到第 9 步。";
      step=9; render();
    });
    render();
  </script>
</body>
</html>
HTML_EOF
}

launch_dry_run_wizard() {
  TMP_DIR="$(mktemp -d)"
  local html_file="$TMP_DIR/install-web-v2-mac-dry-run-wizard.html"
  write_dry_run_wizard_html "$html_file"
  if ! open_url "$html_file"; then
    log_warn "Browser auto-open failed in current shell; manual open may be required."
  fi
  log_info "Dry-run wizard opened: $html_file"
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

csv_contains_item() {
  local csv="$1"
  local item="$2"
  case ",${csv}," in
    *",${item},"*) return 0 ;;
    *) return 1 ;;
  esac
}

append_csv_unique() {
  local csv="$1"
  local item="$2"
  if [[ -z "$item" ]]; then
    printf '%s' "$csv"
    return
  fi
  if [[ -z "$csv" ]]; then
    printf '%s' "$item"
    return
  fi
  if csv_contains_item "$csv" "$item"; then
    printf '%s' "$csv"
    return
  fi
  printf '%s,%s' "$csv" "$item"
}

tokenize_csv_or_spaces() {
  local raw="$1"
  local normalized
  normalized="${raw//,/ }"
  normalized="$(printf '%s' "$normalized" | tr '\r\n\t' '   ')"
  printf '%s' "$normalized"
}

normalize_csv_by_allowlist() {
  local raw="$1"
  local allowed_csv="$2"
  local tokenized
  tokenized="$(tokenize_csv_or_spaces "$raw")"
  local result=""
  local item
  for item in $tokenized; do
    item="$(lower_trim "$item")"
    [[ -n "$item" ]] || continue
    if csv_contains_item "$allowed_csv" "$item"; then
      result="$(append_csv_unique "$result" "$item")"
    fi
  done
  printf '%s' "$result"
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
  local raw="$1"
  local tokenized
  tokenized="$(tokenize_csv_or_spaces "$raw")"
  local result=""
  local item
  for item in $tokenized; do
    item="$(trim "$item")"
    [[ -n "$item" ]] || continue
    result="$(append_csv_unique "$result" "$item")"
  done
  printf '%s' "$result"
}

json_escape() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  value="${value//$'\n'/\\n}"
  value="${value//$'\r'/\\r}"
  value="${value//$'\t'/\\t}"
  printf '%s' "$value"
}

csv_to_json_array_pretty() {
  local raw="$1"
  local tokenized
  tokenized="$(tokenize_csv_or_spaces "$raw")"
  local out="["
  local first=1
  local item
  for item in $tokenized; do
    item="$(trim "$item")"
    [[ -n "$item" ]] || continue
    local escaped
    escaped="$(json_escape "$item")"
    if [[ "$first" -eq 1 ]]; then
      out="${out}\"${escaped}\""
      first=0
    else
      out="${out}, \"${escaped}\""
    fi
  done
  out="${out}]"
  printf '%s' "$out"
}

print_step() {
  local title="$1"
  printf '\n[%s]\n' "$title"
}

print_cmd() {
  local command_text="$1"
  printf '  -> %s\n' "$command_text"
}

parse_args "$@"

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

provider_value="$(normalize_provider "$provider_value")"
skills_value="$(normalize_skills "$skills_value")"
hooks_value="$(normalize_hooks "$hooks_value")"
feishu_group_policy_value="$(normalize_feishu_group_policy "$feishu_group_policy_value")"
feishu_group_allow_from_value="$(normalize_feishu_group_allow_from "$feishu_group_allow_from_value")"

if [[ -z "$(trim "$api_key_value")" || -z "$(trim "$feishu_app_id_value")" || -z "$(trim "$feishu_app_secret_value")" ]]; then
  if [[ "$NO_WEB" -eq 1 ]]; then
    log_error "Missing required config. Set OPENCLAW_API_KEY, OPENCLAW_FEISHU_APP_ID, OPENCLAW_FEISHU_APP_SECRET or use web setup."
    exit 1
  fi
fi

if [[ -z "$(trim "$provider_value")" ]]; then
  provider_value="kimi-code"
fi

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

log_info "DRY RUN MODE: this script will not install or modify anything."
launch_dry_run_wizard
print_cmd "curl -fsSL ${REPO_RAW_BASE_URL}/install-web-v2-mac-dry-run.sh | bash"

print_step "0) New macOS prerequisites (simulated)"
print_cmd "xcode-select --install"
print_cmd "xcode-select -p"
print_cmd "softwareupdate --list | grep -i \"Command Line Tools\""
print_cmd "sudo softwareupdate --install \"Command Line Tools for Xcode-<version>\""
print_cmd "sudo xcode-select --switch /Library/Developer/CommandLineTools"
print_cmd "python3 --version"
print_cmd "brew install python"
print_cmd "/bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""

print_step "1) Resolve config source"
if [[ -z "$(trim "$api_key_value")" || -z "$(trim "$feishu_app_id_value")" || -z "$(trim "$feishu_app_secret_value")" ]]; then
  print_cmd "Would launch web wizard UI to collect missing required fields"
  print_cmd "Would wait for /submit and optional /pairing-submit"
else
  print_cmd "Using CLI args / environment variables for required fields"
fi

print_step "2) Install OpenClaw CLI (simulated)"
if [[ "$INSTALL_SCRIPT_URL" == https://* ]]; then
  print_cmd "curl -fsSL --proto '=https' --tlsv1.2 ${INSTALL_SCRIPT_URL} | bash -s -- --no-onboard"
else
  print_cmd "curl -fsSL ${INSTALL_SCRIPT_URL} | bash -s -- --no-onboard"
fi
print_cmd "Would refresh PATH and locate openclaw binary"
print_cmd "openclaw doctor --fix"

print_step "3) Onboard non-interactively (simulated)"
print_cmd "openclaw onboard --non-interactive --accept-risk --mode local --auth-choice ${auth_choice} ${key_flag} ***REDACTED*** --skip-channels --skip-daemon --skip-skills --skip-ui --skip-health --gateway-bind loopback --gateway-port 18789"

print_step "4) Configure Feishu channel (simulated)"
print_cmd "openclaw plugins enable feishu || openclaw plugins install @openclaw/feishu"
print_cmd "openclaw config set channels.feishu.enabled true"
print_cmd "openclaw config set channels.feishu.accounts.default.appId ***REDACTED***"
print_cmd "openclaw config set channels.feishu.accounts.default.appSecret ***REDACTED***"
print_cmd "openclaw config set channels.feishu.dmPolicy ${OPENCLAW_FEISHU_DM_POLICY:-pairing}"

if [[ "${OPENCLAW_FEISHU_DM_POLICY:-pairing}" == "open" ]]; then
  print_cmd "openclaw config set channels.feishu.allowFrom '[\"*\"]' --strict-json"
else
  print_cmd "openclaw config unset channels.feishu.allowFrom"
fi

print_cmd "openclaw config set channels.feishu.groupPolicy ${feishu_group_policy_value}"
if [[ "$feishu_group_policy_value" == "allowlist" && -n "$feishu_group_allow_from_value" ]]; then
  print_cmd "openclaw config set channels.feishu.groupAllowFrom $(csv_to_json_array_pretty "$feishu_group_allow_from_value") --strict-json"
else
  print_cmd "openclaw config unset channels.feishu.groupAllowFrom"
fi

print_step "5) Apply selected skills/hooks (simulated)"
if [[ -n "$skills_value" ]]; then
  IFS=',' read -r -a skill_items <<<"$skills_value"
  for skill in "${skill_items[@]}"; do
    skill="$(trim "$skill")"
    [[ -n "$skill" ]] || continue
    case "$skill" in
      web-search)
        print_cmd "openclaw config set tools.web.search.* based on provider/env"
        ;;
      autonomy)
        print_cmd "openclaw config set skills.entries.coding-agent.enabled true"
        print_cmd "openclaw config set skills.entries.tmux.enabled true"
        print_cmd "openclaw config set skills.entries.healthcheck.enabled true"
        print_cmd "openclaw config set skills.entries.session-logs.enabled true"
        ;;
      *)
        print_cmd "Skip skill ${skill} (extra tooling required)"
        ;;
    esac
  done
else
  print_cmd "No skills selected"
fi

if [[ -n "$hooks_value" ]]; then
  print_cmd "openclaw config set hooks.internal.enabled true"
  IFS=',' read -r -a hook_items <<<"$hooks_value"
  for hook in "${hook_items[@]}"; do
    hook="$(trim "$hook")"
    [[ -n "$hook" ]] || continue
    print_cmd "openclaw hooks enable ${hook}"
  done
else
  print_cmd "No hooks selected"
fi

print_step "6) Gateway + dashboard + pairing (simulated)"
print_cmd "openclaw gateway install"
print_cmd "openclaw gateway start"
print_cmd "Resolve Control UI URL and token, then open dashboard"
if [[ -n "$(trim "$pairing_code_value")" ]]; then
  print_cmd "openclaw pairing approve feishu ***REDACTED***"
elif [[ "$NO_WEB" -eq 0 ]]; then
  print_cmd "Would wait up to 30 minutes for pairing code from wizard page"
else
  print_cmd "Pairing skipped (no pairing code provided)"
fi

print_step "Summary"
printf 'Provider: %s\n' "$provider_value"
printf 'Feishu groupPolicy: %s\n' "$feishu_group_policy_value"
if [[ "$feishu_group_policy_value" == "allowlist" && -n "$feishu_group_allow_from_value" ]]; then
  printf 'Feishu groupAllowFrom: %s\n' "$feishu_group_allow_from_value"
fi
if [[ -n "$skills_value" ]]; then
  printf 'Selected Skills: %s\n' "$skills_value"
fi
if [[ -n "$hooks_value" ]]; then
  printf 'Selected Hooks: %s\n' "$hooks_value"
fi

log_warn "Simulation complete. No installation or configuration commands were executed."
