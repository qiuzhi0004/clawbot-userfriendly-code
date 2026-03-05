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
DRY_RUN_WIZARD_DIR="${DRY_RUN_WIZARD_DIR:-$HOME/.clawbot-userfriendly/dry-run}"

log_info() {
  printf '\033[36m%s\033[0m\n' "$1"
}

log_warn() {
  printf '\033[33m%s\033[0m\n' "$1"
}

log_error() {
  printf '\033[31m%s\033[0m\n' "$1" >&2
}

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

resolve_dry_run_wizard_dir() {
  local candidates=(
    "$DRY_RUN_WIZARD_DIR"
    "${TMPDIR:-/tmp}/clawbot-userfriendly/dry-run"
    "$PWD/.clawbot-userfriendly/dry-run"
  )
  local dir
  for dir in "${candidates[@]}"; do
    [[ -n "$dir" ]] || continue
    if ! mkdir -p "$dir" >/dev/null 2>&1; then
      continue
    fi
    local probe_file="$dir/.wizard-write-test.$$"
    if touch "$probe_file" >/dev/null 2>&1; then
      rm -f "$probe_file" >/dev/null 2>&1 || true
      printf '%s' "$dir"
      return 0
    fi
  done
  return 1
}

write_dry_run_wizard_html() {
  local html_file="$1"
  local default_provider="$2"
  local default_skills_csv="$3"
  local default_hooks_csv="$4"
  local default_feishu_group_policy="$5"
  local default_feishu_group_allow_from="$6"

  cat >"$html_file" <<'HTML_EOF'
<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>OpenClaw 安装向导</title>
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
    .nested-list { margin-top:8px; padding-left:24px; font-size:23px; line-height:1.5; }
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
    .shot { width:100%; height:100%; object-fit:contain; border-radius:8px; background:#f3f4f6; cursor:zoom-in; }
    .shot-note { margin-top:10px; font-size:18px; color:var(--muted); line-height:1.5; }
    .shot-tip { margin-top:8px; font-size:16px; color:#334155; }
    .shot-modal { position:fixed; inset:0; background:rgba(15,23,42,.75); display:none; align-items:center; justify-content:center; padding:18px; z-index:9999; }
    .shot-modal.active { display:flex; }
    .shot-modal-content { width:min(1200px,96vw); height:min(90vh,920px); background:#0f172a; border:3px solid #cbd5e1; border-radius:14px; padding:12px; display:flex; align-items:center; justify-content:center; position:relative; }
    .shot-modal img { max-width:100%; max-height:100%; width:auto; height:auto; object-fit:contain; background:#111827; border-radius:8px; }
    .shot-close { position:absolute; top:10px; right:10px; border:2px solid #e2e8f0; border-radius:10px; background:#111827; color:#f8fafc; font-size:15px; font-weight:700; padding:6px 10px; cursor:pointer; }
    .nav { margin-top:16px; display:flex; justify-content:space-between; align-items:center; gap:10px; }
    .dots { display:flex; gap:8px; }
    .dot { width:14px; height:14px; border-radius:999px; border:2px solid var(--line); background:#fff; }
    .dot.active { background:#f472b6; }
    .btn { border:3px solid var(--line); border-radius:14px; background:#c7d2fe; font-size:24px; font-weight:800; padding:8px 20px; cursor:pointer; }
    .btn[disabled] { opacity:.55; cursor:not-allowed; }
    .btn-next { background:#93c5fd; }
    .submit-wrap { display:none; }
    .submit-wrap.active { display:block; }
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
      <h1>🦞 OpenClaw 安装引导</h1>
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
            <p class="step-subtitle">可多选，部分技能在 Windows 仅做配置</p>
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
                <span><span class="skill-name">网页总结</span><span class="skill-desc">需要额外工具，Windows 将跳过安装。</span></span>
              </label>
              <label class="skill-item">
                <input id="skill-nano-pdf" name="skills" type="checkbox" value="nano-pdf">
                <span><span class="skill-name">PDF 处理</span><span class="skill-desc">需要额外工具，Windows 将跳过安装。</span></span>
              </label>
              <label class="skill-item">
                <input id="skill-openai-whisper" name="skills" type="checkbox" value="openai-whisper">
                <span><span class="skill-name">音频转文字</span><span class="skill-desc">需要额外工具，Windows 将跳过安装。</span></span>
              </label>
              <label class="skill-item">
                <input id="skill-github" name="skills" type="checkbox" value="github">
                <span><span class="skill-name">GitHub 能力</span><span class="skill-desc">需要额外工具，Windows 将跳过安装。</span></span>
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
              <p style="margin:0 0 10px;font-size:18px;color:#475569;">确认前两步配置后，点击“开始安装”。安装会在终端执行。</p>
              <button type="button" class="submit-btn" id="start-install-btn">开始安装</button>
            </div>
          </div>
          <div class="step-page" data-step="6">
            <h2 class="step-title">6. 等待安装</h2>
            <ol class="guide-list">
              <li>安装已在终端启动，请等待完成。</li>
              <li>首次运行会自动检查并安装 NuGet / winget / Node.js LTS。</li>
              <li>执行期间请不要关闭终端窗口。</li>
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
openclaw skills          # 查看已安装技能</pre>
            </div>
            <div class="links" style="margin-top:12px;">
              <a href="https://openclaw.ai" target="_blank">OpenClaw 官网</a><br>
              <a href="https://docs.openclaw.ai" target="_blank">官方文档</a><br>
              <a href="https://discord.com/invite/clawd" target="_blank">Discord 社区</a><br>
              <a href="http://localhost:18789" target="_blank">Dashboard 管理面板</a>
            </div>
            <div class="code-wrap">
              <p style="margin:0;font-size:18px;color:#334155;">完成配对后即可开始使用 OpenClaw。</p>
            </div>
          </div>
        </section>
        <aside class="panel">
          <h3 class="right-title" id="shot-title">步骤截图</h3>
          <div class="shot-frame">
            <img id="shot-image" class="shot" src="https://guide-app-lyart.vercel.app/assets/Pasted%20image%2020260130013219.jpg" alt="步骤截图">
          </div>
          <p class="shot-note" id="shot-note">右侧为操作截图示意，当前先使用统一图片占位。</p>
          <p class="shot-tip">点击截图可放大查看，按 ESC 或点击遮罩关闭。</p>
        </aside>
      </div>
      <div class="nav">
        <button type="button" class="btn" id="prev-btn">← 上一步</button>
        <div class="dots" id="dots"></div>
        <button type="button" class="btn btn-next" id="next-btn">下一步 →</button>
      </div>
    </form>
  </main>
  <div class="shot-modal" id="shot-modal">
    <div class="shot-modal-content">
      <button type="button" class="shot-close" id="shot-close-btn">关闭</button>
      <img id="shot-modal-image" src="" alt="放大截图">
    </div>
  </div>
  <script>
    var defaultProvider = __DEFAULT_PROVIDER_JSON__;
    var defaultSkills = __DEFAULT_SKILLS_JSON__;
    var defaultHooks = __DEFAULT_HOOKS_JSON__;
    var defaultFeishuGroupPolicy = __DEFAULT_FEISHU_GROUP_POLICY_JSON__;
    var defaultFeishuGroupAllowFrom = __DEFAULT_FEISHU_GROUP_ALLOW_FROM_JSON__;
    var labels = { "kimi-code":"Kimi Code API Key", "moonshot":"Moonshot API Key", "minimax":"MiniMax API Key", "zai":"Z.AI API Key", "zai-coding-global":"Z.AI API Key", "zai-coding-cn":"Z.AI API Key" };
    var stepMeta = [
      { title: "步骤 1：配置模型", note: "请先创建并粘贴 API Key。" },
      { title: "步骤 2：配置飞书机器人", note: "填写飞书 App ID 与 App Secret。" },
      { title: "步骤 3：群组访问策略", note: "配置群组策略与可选白名单。" },
      { title: "步骤 4：选择 Skill", note: "根据需要选择技能。" },
      { title: "步骤 5：启用 Hooks", note: "按需启用事件驱动自动化 Hooks。" },
      { title: "步骤 6：等待安装", note: "提交后会自动安装依赖并继续安装 OpenClaw。" },
      { title: "步骤 7：飞书配对", note: "可先填写配对码，也可安装后填写。" },
      { title: "步骤 8：提交配对码", note: "在当前页面提交配对码并执行配对。" },
      { title: "步骤 9：完成与常用命令", note: "复制常用命令并开始使用。" }
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
    var shotImageEl = document.getElementById("shot-image");
    var shotModalEl = document.getElementById("shot-modal");
    var shotModalImageEl = document.getElementById("shot-modal-image");
    var shotCloseBtnEl = document.getElementById("shot-close-btn");
    var startInstallBtn = document.getElementById("start-install-btn");
    var installStatusEl = document.getElementById("install-status");
    var confirmInstallBtn = document.getElementById("confirm-install-btn");
    var pairingCodeEl = document.getElementById("pairingCode");
    var pairingCodeSubmitEl = document.getElementById("pairingCodeSubmit");
    var submitPairingBtn = document.getElementById("submit-pairing-btn");
    var pairingSubmitStatusEl = document.getElementById("pairing-submit-status");
    providerEl.value = defaultProvider;
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
    function updateApiLabel() { labelEl.textContent = labels[providerEl.value] || "API Key"; }
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
      setTimeout(function () {
        installSubmitted = true;
        installStatusEl.textContent = "安装已启动。请等待终端完成安装后点击“我已看到安装完成”。";
        confirmInstallBtn.disabled = false;
        currentStep = 6;
        renderStep();
      }, 200);
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
      setTimeout(function () {
        pairingSubmitStatusEl.textContent = "配对码提交成功，脚本正在执行配对。";
        currentStep = 9;
        renderStep();
      }, 200);
    }
    function openShotModal() {
      shotModalImageEl.src = shotImageEl.src;
      shotModalEl.className = "shot-modal active";
    }
    function closeShotModal() {
      shotModalEl.className = "shot-modal";
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
      if (!ensureValidStep(currentStep)) { return; }
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
    if (shotImageEl && shotModalEl && shotModalImageEl && shotCloseBtnEl) {
      shotImageEl.addEventListener("click", openShotModal);
      shotCloseBtnEl.addEventListener("click", closeShotModal);
      shotModalEl.addEventListener("click", function (event) {
        if (event.target === shotModalEl) {
          closeShotModal();
        }
      });
      document.addEventListener("keydown", function (event) {
        if (event.key === "Escape") {
          closeShotModal();
        }
      });
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
        if (!target) { return; }
        copyText(target.textContent || "");
        button.textContent = "已复制";
          setTimeout(function () { button.textContent = "一键复制命令"; }, 1200);
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

  python3 - "$html_file" "$provider_json" "$skills_json" "$hooks_json" "$feishu_group_policy_json" "$feishu_group_allow_from_json" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
provider_json = sys.argv[2]
skills_json = sys.argv[3]
hooks_json = sys.argv[4]
feishu_group_policy_json = sys.argv[5]
feishu_group_allow_from_json = sys.argv[6]

html = path.read_text(encoding="utf-8")
html = html.replace("__DEFAULT_PROVIDER_JSON__", provider_json)
html = html.replace("__DEFAULT_SKILLS_JSON__", skills_json)
html = html.replace("__DEFAULT_HOOKS_JSON__", hooks_json)
html = html.replace("__DEFAULT_FEISHU_GROUP_POLICY_JSON__", feishu_group_policy_json)
html = html.replace("__DEFAULT_FEISHU_GROUP_ALLOW_FROM_JSON__", feishu_group_allow_from_json)
path.write_text(html, encoding="utf-8")
PY
}

launch_dry_run_wizard() {
  local wizard_dir=""
  wizard_dir="$(resolve_dry_run_wizard_dir || true)"
  if [[ -z "$wizard_dir" ]]; then
    log_warn "Unable to create wizard directory in HOME/TMP/PWD."
    return
  fi
  wizard_dir="${wizard_dir%/}"
  local html_file="$wizard_dir/install-web-v2-mac-dry-run-wizard.html"
  write_dry_run_wizard_html "$html_file" "$provider_value" "$skills_value" "$hooks_value" "$feishu_group_policy_value" "$feishu_group_allow_from_value"
  if ! open_url "$html_file"; then
    log_warn "Browser auto-open failed in current shell; manual open may be required."
  fi
  printf 'Dry-run wizard opened: %s\n' "$html_file"
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
print_cmd "/bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
print_cmd "brew install python"
print_cmd "brew install node"
print_cmd "python3 --version"
print_cmd "node --version"
print_cmd "npm --version"

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
