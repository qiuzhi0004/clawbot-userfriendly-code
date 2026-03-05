param(
    [string]$InstallScriptUrl = "https://openclaw.ai/install.ps1",
    [string]$Provider,
    [string]$ApiKey,
    [string]$FeishuAppId,
    [string]$FeishuAppSecret,
    [string]$FeishuGroupPolicy,
    [string]$FeishuGroupAllowFrom,
    [string]$Skills,
    [string]$Hooks,
    [string]$PairingCode,
    [switch]$NoWeb
)

$ErrorActionPreference = "Stop"

function Test-IsAdministrator {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Ensure-Administrator {
    if (Test-IsAdministrator) {
        return
    }

    if ([string]::IsNullOrWhiteSpace($PSCommandPath)) {
        throw "This installer must be run from a .ps1 file to auto-elevate. Save and run it with PowerShell as Administrator."
    }

    $argList = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $PSCommandPath)
    if ($PSBoundParameters.ContainsKey("InstallScriptUrl") -and -not [string]::IsNullOrWhiteSpace($InstallScriptUrl)) { $argList += @("-InstallScriptUrl", $InstallScriptUrl) }
    if ($PSBoundParameters.ContainsKey("Provider") -and -not [string]::IsNullOrWhiteSpace($Provider)) { $argList += @("-Provider", $Provider) }
    if ($PSBoundParameters.ContainsKey("ApiKey") -and -not [string]::IsNullOrWhiteSpace($ApiKey)) { $argList += @("-ApiKey", $ApiKey) }
    if ($PSBoundParameters.ContainsKey("FeishuAppId") -and -not [string]::IsNullOrWhiteSpace($FeishuAppId)) { $argList += @("-FeishuAppId", $FeishuAppId) }
    if ($PSBoundParameters.ContainsKey("FeishuAppSecret") -and -not [string]::IsNullOrWhiteSpace($FeishuAppSecret)) { $argList += @("-FeishuAppSecret", $FeishuAppSecret) }
    if ($PSBoundParameters.ContainsKey("FeishuGroupPolicy") -and -not [string]::IsNullOrWhiteSpace($FeishuGroupPolicy)) { $argList += @("-FeishuGroupPolicy", $FeishuGroupPolicy) }
    if ($PSBoundParameters.ContainsKey("FeishuGroupAllowFrom") -and -not [string]::IsNullOrWhiteSpace($FeishuGroupAllowFrom)) { $argList += @("-FeishuGroupAllowFrom", $FeishuGroupAllowFrom) }
    if ($PSBoundParameters.ContainsKey("Skills") -and -not [string]::IsNullOrWhiteSpace($Skills)) { $argList += @("-Skills", $Skills) }
    if ($PSBoundParameters.ContainsKey("Hooks") -and -not [string]::IsNullOrWhiteSpace($Hooks)) { $argList += @("-Hooks", $Hooks) }
    if ($PSBoundParameters.ContainsKey("PairingCode") -and -not [string]::IsNullOrWhiteSpace($PairingCode)) { $argList += @("-PairingCode", $PairingCode) }
    if ($NoWeb.IsPresent) { $argList += "-NoWeb" }

    Write-Host "Requesting Administrator privileges..." -ForegroundColor Yellow
    try {
        Start-Process -FilePath "powershell.exe" -Verb RunAs -ArgumentList $argList | Out-Null
    } catch {
        throw "Administrator privileges are required. Please rerun this script as Administrator."
    }
    exit 0
}

Ensure-Administrator

function Repair-MojibakeText {
    param(
        [string]$Text
    )
    if ([string]::IsNullOrEmpty($Text)) {
        return $Text
    }

    $best = $Text
    $bestScore = ([regex]::Matches($Text, "[\u4e00-\u9fff]").Count)
    $encodings = @(
        [System.Text.Encoding]::GetEncoding(1252),
        [System.Text.Encoding]::GetEncoding(28591),
        [System.Text.Encoding]::GetEncoding(936)
    )

    for ($round = 0; $round -lt 2; $round++) {
        foreach ($encoding in $encodings) {
            $candidate = [System.Text.Encoding]::UTF8.GetString($encoding.GetBytes($best))
            $candidateScore = ([regex]::Matches($candidate, "[\u4e00-\u9fff]").Count)
            if ($candidateScore -gt $bestScore) {
                $best = $candidate
                $bestScore = $candidateScore
            }
        }
    }

    return $best
}

function Normalize-Provider {
    param(
        [string]$Value
    )
    $normalized = ($Value -as [string]).Trim().ToLower()
    switch ($normalized) {
        "" { return "kimi-code" }
        "1" { return "kimi-code" }
        "k" { return "kimi-code" }
        "kimi" { return "kimi-code" }
        "kimi-code" { return "kimi-code" }
        "kimicode" { return "kimi-code" }
        "2" { return "minimax" }
        "m" { return "minimax" }
        "minimax" { return "minimax" }
        "3" { return "moonshot" }
        "moon" { return "moonshot" }
        "moonshot" { return "moonshot" }
        "4" { return "zai" }
        "glm" { return "zai" }
        "z.ai" { return "zai" }
        "zai" { return "zai" }
        "zai-api-key" { return "zai" }
        "zai-global" { return "zai-global" }
        "zai-cn" { return "zai-cn" }
        "zai-coding-global" { return "zai-coding-global" }
        "zai-coding-cn" { return "zai-coding-cn" }
        default { return $normalized }
    }
}

function Normalize-Skills {
    param(
        [string]$Raw
    )
    if ([string]::IsNullOrWhiteSpace($Raw)) {
        return @()
    }
    $allowed = @("web-search","autonomy","summarize","github","nano-pdf","openai-whisper")
    $items = $Raw -split "[, ]+" | ForEach-Object { $_.Trim().ToLower() } | Where-Object { $_ }
    $result = New-Object System.Collections.Generic.List[string]
    foreach ($item in $items) {
        if ($allowed -contains $item -and -not $result.Contains($item)) {
            $result.Add($item)
        }
    }
    return $result.ToArray()
}

function Normalize-Hooks {
    param(
        [string]$Raw
    )
    if ([string]::IsNullOrWhiteSpace($Raw)) {
        return @()
    }
    $allowed = @("session-memory","command-logger","boot-md")
    $items = $Raw -split "[, ]+" | ForEach-Object { $_.Trim().ToLower() } | Where-Object { $_ }
    $result = New-Object System.Collections.Generic.List[string]
    foreach ($item in $items) {
        if ($allowed -contains $item -and -not $result.Contains($item)) {
            $result.Add($item)
        }
    }
    return $result.ToArray()
}

function Normalize-FeishuGroupPolicy {
    param(
        [string]$Raw
    )
    $value = ($Raw -as [string]).Trim().ToLower()
    switch ($value) {
        "allowlist" { return "allowlist" }
        "disabled" { return "disabled" }
        "open" { return "open" }
        default { return "open" }
    }
}

function Get-ControlUiUrl {
    $basePath = "/"
    try {
        $rawBasePath = (& openclaw config get gateway.controlUi.basePath 2>$null | Select-Object -First 1)
        if (-not [string]::IsNullOrWhiteSpace($rawBasePath)) {
            $candidate = $rawBasePath.Trim().Trim("'").Trim('"')
            if (-not [string]::IsNullOrWhiteSpace($candidate) -and $candidate -ne "null") {
                $basePath = $candidate
            }
        }
    } catch {
    }
    if (-not $basePath.StartsWith("/")) {
        $basePath = "/$basePath"
    }
    if (-not $basePath.EndsWith("/")) {
        $basePath = "$basePath/"
    }
    return "http://127.0.0.1:18789$basePath"
}

function Get-GatewayToken {
    if (-not [string]::IsNullOrWhiteSpace($env:OPENCLAW_GATEWAY_TOKEN)) {
        return $env:OPENCLAW_GATEWAY_TOKEN.Trim()
    }
    try {
        $rawToken = (& openclaw config get gateway.auth.token 2>$null | Select-Object -First 1)
        if ([string]::IsNullOrWhiteSpace($rawToken)) {
            return ""
        }
        $token = $rawToken.Trim().Trim("'").Trim('"')
        if ([string]::IsNullOrWhiteSpace($token) -or $token -eq "null") {
            return ""
        }
        return $token
    } catch {
        return ""
    }
}

function Open-Dashboard {
    param(
        [string]$BaseUrl,
        [string]$OpenUrl,
        [string]$Token
    )
    try {
        & openclaw dashboard | Out-Null
        Write-Host "Dashboard opened via openclaw dashboard." -ForegroundColor Green
        return
    } catch {
    }
    if (Open-Url $OpenUrl) {
        Write-Host "Dashboard opened: $BaseUrl" -ForegroundColor Green
        if (-not [string]::IsNullOrWhiteSpace($Token)) {
            Write-Host "Gateway token has been attached automatically." -ForegroundColor Green
        } else {
            Write-Host "Gateway token not found. Paste token in Control UI settings if prompted." -ForegroundColor Yellow
            Write-Host "You can also run: openclaw dashboard" -ForegroundColor Yellow
        }
        return
    }
    Write-Host "Open Dashboard manually: $BaseUrl" -ForegroundColor Yellow
    if (-not [string]::IsNullOrWhiteSpace($Token)) {
        Write-Host "Gateway token: $Token" -ForegroundColor Yellow
    } else {
        Write-Host "Token source: gateway.auth.token or OPENCLAW_GATEWAY_TOKEN" -ForegroundColor Yellow
    }
}

function Build-ControlUiOpenUrl {
    param(
        [string]$BaseUrl,
        [string]$Token
    )
    if ([string]::IsNullOrWhiteSpace($Token)) {
        return $BaseUrl
    }
    $separator = "?"
    if ($BaseUrl.Contains("?")) {
        $separator = "&"
    }
    $encodedToken = [System.Uri]::EscapeDataString($Token)
    return "$BaseUrl${separator}token=$encodedToken"
}

function Normalize-FeishuGroupAllowFrom {
    param(
        [string]$Raw
    )
    if ([string]::IsNullOrWhiteSpace($Raw)) {
        return @()
    }
    $items = $Raw -split "[,\r\n\t ]+" | ForEach-Object { $_.Trim() } | Where-Object { $_ }
    $result = New-Object System.Collections.Generic.List[string]
    foreach ($item in $items) {
        if (-not $result.Contains($item)) {
            $result.Add($item)
        }
    }
    return $result.ToArray()
}

function Open-Url {
    param(
        [string]$Url
    )
    try {
        Start-Process $Url | Out-Null
        return $true
    } catch {
        return $false
    }
}

function Get-FreePort {
    $listener = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Loopback, 0)
    $listener.Start()
    $port = $listener.LocalEndpoint.Port
    $listener.Stop()
    return $port
}

function Refresh-ProcessPath {
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
}

function Ensure-Prerequisites {
    Set-ExecutionPolicy -Scope Process Bypass -Force | Out-Null
    Refresh-ProcessPath

    $wingetCmd = Get-Command winget -ErrorAction SilentlyContinue
    if (-not $wingetCmd) {
        Install-PackageProvider -Name NuGet -Scope CurrentUser -Force | Out-Null
        Install-Module -Name Microsoft.WinGet.Client -Scope CurrentUser -Force -Repository PSGallery | Out-Null
        try {
            Import-Module Microsoft.WinGet.Client -Force -ErrorAction Stop
            $repairCmd = Get-Command Repair-WinGetPackageManager -ErrorAction SilentlyContinue
            if ($repairCmd) {
                Repair-WinGetPackageManager -Latest -AllUsers | Out-Null
            }
        } catch {
        }
        Refresh-ProcessPath
        $wingetCmd = Get-Command winget -ErrorAction SilentlyContinue
    }
    if (-not $wingetCmd) {
        throw "winget is not available. Please install App Installer from Microsoft Store and retry."
    }

    $nodeCmd = Get-Command node -ErrorAction SilentlyContinue
    if (-not $nodeCmd) {
        winget install OpenJS.NodeJS.LTS --accept-package-agreements --accept-source-agreements --disable-interactivity | Out-Null
        Refresh-ProcessPath
        $nodeCmd = Get-Command node -ErrorAction SilentlyContinue
    }
    if (-not $nodeCmd) {
        throw "Node.js installation failed. Please install Node.js LTS manually and retry."
    }

    $npmCmd = Get-Command npm -ErrorAction SilentlyContinue
    if (-not $npmCmd) {
        throw "npm is not available after Node.js setup. Please reinstall Node.js LTS and retry."
    }
}

function Get-WebConfigHtml {
    param(
        [string]$DefaultProvider,
        [string[]]$DefaultSkills,
        [string[]]$DefaultHooks,
        [string]$DefaultFeishuGroupPolicy,
        [string[]]$DefaultFeishuGroupAllowFrom
    )
    $defaultSkillsJson = ($DefaultSkills | ConvertTo-Json -Compress)
    if ([string]::IsNullOrWhiteSpace($defaultSkillsJson)) {
        $defaultSkillsJson = "[]"
    }
    $defaultHooksJson = ($DefaultHooks | ConvertTo-Json -Compress)
    if ([string]::IsNullOrWhiteSpace($defaultHooksJson)) {
        $defaultHooksJson = "[]"
    }
    $defaultFeishuGroupPolicyValue = Normalize-FeishuGroupPolicy $DefaultFeishuGroupPolicy
    $defaultFeishuGroupAllowFromText = ""
    if ($DefaultFeishuGroupAllowFrom -and $DefaultFeishuGroupAllowFrom.Count -gt 0) {
        $defaultFeishuGroupAllowFromText = ($DefaultFeishuGroupAllowFrom -join ",")
    }
    $defaultFeishuGroupAllowFromJs = $defaultFeishuGroupAllowFromText.Replace("\", "\\").Replace("""", "\""")
    $html = Repair-MojibakeText @'
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
    var defaultProvider = "__DEFAULT_PROVIDER__";
    var defaultSkills = __DEFAULT_SKILLS__;
    var defaultHooks = __DEFAULT_HOOKS__;
    var defaultFeishuGroupPolicy = "__DEFAULT_FEISHU_GROUP_POLICY__";
    var defaultFeishuGroupAllowFrom = "__DEFAULT_FEISHU_GROUP_ALLOW_FROM__";
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
'@
    $html = $html.Replace("__DEFAULT_PROVIDER__", $DefaultProvider)
    $html = $html.Replace("__DEFAULT_SKILLS__", $defaultSkillsJson)
    $html = $html.Replace("__DEFAULT_HOOKS__", $defaultHooksJson)
    $html = $html.Replace("__DEFAULT_FEISHU_GROUP_POLICY__", $defaultFeishuGroupPolicyValue)
    $html = $html.Replace("__DEFAULT_FEISHU_GROUP_ALLOW_FROM__", $defaultFeishuGroupAllowFromJs)
    return $html
}

function Get-WebConfig {
    param(
        [string]$DefaultProvider,
        [string[]]$DefaultSkills,
        [string[]]$DefaultHooks,
        [string]$DefaultFeishuGroupPolicy,
        [string[]]$DefaultFeishuGroupAllowFrom
    )
    Add-Type -AssemblyName System.Web
    $port = Get-FreePort
    $listener = New-Object System.Net.HttpListener
    $prefix = "http://127.0.0.1:$port/"
    $listener.Prefixes.Add($prefix)
    $listener.Start()

    $html = Get-WebConfigHtml -DefaultProvider $DefaultProvider -DefaultSkills $DefaultSkills -DefaultHooks $DefaultHooks -DefaultFeishuGroupPolicy $DefaultFeishuGroupPolicy -DefaultFeishuGroupAllowFrom $DefaultFeishuGroupAllowFrom
    $successHtml = Repair-MojibakeText @'
<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>OpenClaw 安装中</title>
  <style>
    body { margin:0; min-height:100vh; display:grid; place-items:center; background:linear-gradient(135deg,#f7f3ea,#f2e7d2); color:#2d2418; font-family:"PingFang SC","Noto Sans SC","Microsoft YaHei",sans-serif; padding:24px; }
    .panel { width:min(560px,100%); background:rgba(255,252,246,.96); border:1px solid rgba(216,199,171,.9); border-radius:20px; padding:28px; box-shadow:0 24px 60px rgba(45,36,24,.10); }
    h1 { margin:0 0 10px; font-size:30px; }
    p { margin:0; line-height:1.7; color:#695744; }
  </style>
</head>
<body>
  <main class="panel">
    <h1>已开始安装</h1>
    <p>配置已经收到，终端正在继续执行安装。这个页面可以直接关掉。</p>
  </main>
</body>
</html>
'@

    $url = "http://127.0.0.1:$port/"
    if (-not (Open-Url $url)) {
        Write-Host "Open this URL in your browser: $url" -ForegroundColor Cyan
    }

    $deadline = [DateTime]::UtcNow.AddMinutes(15)
    $result = $null
    $keepListener = $false

    try {
        while ([DateTime]::UtcNow -lt $deadline) {
            $context = $listener.GetContext()
            $request = $context.Request
            if ($request.HttpMethod -eq "GET" -and $request.Url.AbsolutePath -eq "/") {
                $bytes = [System.Text.Encoding]::UTF8.GetBytes($html)
                $context.Response.StatusCode = 200
                $context.Response.ContentType = "text/html; charset=utf-8"
                $context.Response.ContentEncoding = [System.Text.Encoding]::UTF8
                $context.Response.ContentLength64 = $bytes.Length
                $context.Response.OutputStream.Write($bytes, 0, $bytes.Length)
                $context.Response.OutputStream.Close()
                continue
            }

            if ($request.HttpMethod -eq "POST" -and $request.Url.AbsolutePath -eq "/submit") {
                $reader = New-Object System.IO.StreamReader($request.InputStream, [System.Text.Encoding]::UTF8)
                $body = $reader.ReadToEnd()
                $reader.Close()
                $parsed = [System.Web.HttpUtility]::ParseQueryString($body)
                $provider = Normalize-Provider $parsed["provider"]
                $apiKey = ($parsed["apiKey"] -as [string]).Trim()
                $feishuAppId = ($parsed["feishuAppId"] -as [string]).Trim()
                $feishuAppSecret = ($parsed["feishuAppSecret"] -as [string]).Trim()
                $feishuGroupPolicy = Normalize-FeishuGroupPolicy $parsed["feishuGroupPolicy"]
                $feishuGroupAllowFrom = ($parsed["feishuGroupAllowFrom"] -as [string]).Trim()
                $pairingCode = ($parsed["pairingCode"] -as [string]).Trim()
                $skillsValues = $parsed.GetValues("skills")
                $skillsCsv = ""
                if ($skillsValues) {
                    $skillsCsv = ($skillsValues | ForEach-Object { $_.Trim().ToLower() }) -join ","
                }
                $hooksValues = $parsed.GetValues("hooks")
                $hooksCsv = ""
                if ($hooksValues) {
                    $hooksCsv = ($hooksValues | ForEach-Object { $_.Trim().ToLower() }) -join ","
                }

                if (-not [string]::IsNullOrWhiteSpace($provider) -and -not [string]::IsNullOrWhiteSpace($apiKey) -and -not [string]::IsNullOrWhiteSpace($feishuAppId) -and -not [string]::IsNullOrWhiteSpace($feishuAppSecret)) {
                    $result = [pscustomobject]@{
                        provider = $provider
                        apiKey = $apiKey
                        feishuAppId = $feishuAppId
                        feishuAppSecret = $feishuAppSecret
                        feishuGroupPolicy = $feishuGroupPolicy
                        feishuGroupAllowFrom = $feishuGroupAllowFrom
                        skillsCsv = $skillsCsv
                        hooksCsv = $hooksCsv
                        pairingCode = $pairingCode
                        listener = $listener
                    }
                    $keepListener = $true
                    $bytes = [System.Text.Encoding]::UTF8.GetBytes($successHtml)
                    $context.Response.StatusCode = 200
                    $context.Response.ContentType = "text/html; charset=utf-8"
                    $context.Response.ContentEncoding = [System.Text.Encoding]::UTF8
                    $context.Response.ContentLength64 = $bytes.Length
                    $context.Response.OutputStream.Write($bytes, 0, $bytes.Length)
                    $context.Response.OutputStream.Close()
                    break
                }

                $bytes = [System.Text.Encoding]::UTF8.GetBytes($html.Replace("</form>", "<div class=`"error`">请填写所有必填项。</div></form>"))
                $context.Response.StatusCode = 400
                $context.Response.ContentType = "text/html; charset=utf-8"
                $context.Response.ContentEncoding = [System.Text.Encoding]::UTF8
                $context.Response.ContentLength64 = $bytes.Length
                $context.Response.OutputStream.Write($bytes, 0, $bytes.Length)
                $context.Response.OutputStream.Close()
                continue
            }

            $context.Response.StatusCode = 404
            $context.Response.ContentEncoding = [System.Text.Encoding]::UTF8
            $context.Response.OutputStream.Close()
        }
    } finally {
        if (-not $keepListener -and $listener) {
            $listener.Stop()
        }
    }

    return $result
}

function Get-PairingCodeFromWizardWeb {
    param(
        [Parameter(Mandatory = $true)]
        [System.Net.HttpListener]$Listener
    )
    Add-Type -AssemblyName System.Web
    $deadline = [DateTime]::UtcNow.AddMinutes(30)
    $pairingCode = $null
    try {
        while ($Listener.IsListening -and [DateTime]::UtcNow -lt $deadline) {
            $context = $Listener.GetContext()
            $request = $context.Request
            if ($request.HttpMethod -eq "POST" -and $request.Url.AbsolutePath -eq "/pairing-submit") {
                $reader = New-Object System.IO.StreamReader($request.InputStream, [System.Text.Encoding]::UTF8)
                $body = $reader.ReadToEnd()
                $reader.Close()
                $parsed = [System.Web.HttpUtility]::ParseQueryString($body)
                $value = ($parsed["pairingCode"] -as [string]).Trim()
                if (-not [string]::IsNullOrWhiteSpace($value)) {
                    $pairingCode = $value
                    $bytes = [System.Text.Encoding]::UTF8.GetBytes('{"ok":true}')
                    $context.Response.StatusCode = 200
                    $context.Response.ContentType = "application/json; charset=utf-8"
                    $context.Response.ContentEncoding = [System.Text.Encoding]::UTF8
                    $context.Response.ContentLength64 = $bytes.Length
                    $context.Response.OutputStream.Write($bytes, 0, $bytes.Length)
                    $context.Response.OutputStream.Close()
                    break
                }
                $bytes = [System.Text.Encoding]::UTF8.GetBytes('{"ok":false,"message":"missing pairing code"}')
                $context.Response.StatusCode = 400
                $context.Response.ContentType = "application/json; charset=utf-8"
                $context.Response.ContentEncoding = [System.Text.Encoding]::UTF8
                $context.Response.ContentLength64 = $bytes.Length
                $context.Response.OutputStream.Write($bytes, 0, $bytes.Length)
                $context.Response.OutputStream.Close()
                continue
            }
            $context.Response.StatusCode = 404
            $context.Response.ContentEncoding = [System.Text.Encoding]::UTF8
            $context.Response.OutputStream.Close()
        }
    } finally {
        if ($Listener.IsListening) {
            $Listener.Stop()
        }
    }
    return $pairingCode
}

function Ensure-OpenClawOnPath {
    $openclawCmd = Get-Command openclaw.cmd -ErrorAction SilentlyContinue
    if ($openclawCmd -and $openclawCmd.Source) {
        return $true
    }
    $openclaw = Get-Command openclaw -ErrorAction SilentlyContinue
    if ($openclaw -and $openclaw.Source) {
        return $true
    }

    $npmPrefix = $null
    try {
        $npmPrefix = (npm config get prefix 2>$null).Trim()
    } catch {
        $npmPrefix = $null
    }

    $candidates = @()
    if (-not [string]::IsNullOrWhiteSpace($npmPrefix)) {
        $candidates += $npmPrefix
        $candidates += (Join-Path $npmPrefix "bin")
    }
    if (-not [string]::IsNullOrWhiteSpace($env:APPDATA)) {
        $candidates += (Join-Path $env:APPDATA "npm")
    }
    $candidates = $candidates | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique
    foreach ($candidate in $candidates) {
        if (-not (Test-Path (Join-Path $candidate "openclaw.cmd"))) {
            continue
        }
        $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
        if (-not ($userPath -split ";" | Where-Object { $_ -ieq $candidate })) {
            [Environment]::SetEnvironmentVariable("Path", "$userPath;$candidate", "User")
        }
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
        return $true
    }
    return $false
}

function Apply-SelectedSkills {
    param(
        [string[]]$Skills,
        [string]$Provider,
        [string]$ApiKey
    )
    if (-not $Skills -or $Skills.Count -eq 0) {
        return
    }
    foreach ($skill in $Skills) {
        switch ($skill) {
            "web-search" {
                $searchProvider = $env:OPENCLAW_SEARCH_PROVIDER
                $searchApiKey = $env:OPENCLAW_SEARCH_API_KEY
                if (-not [string]::IsNullOrWhiteSpace($searchProvider) -and -not [string]::IsNullOrWhiteSpace($searchApiKey)) {
                    if ($searchProvider -eq "brave") {
                        openclaw config set tools.web.search.provider brave | Out-Null
                        openclaw config set tools.web.search.apiKey $searchApiKey | Out-Null
                        openclaw config set tools.web.search.enabled true | Out-Null
                        continue
                    }
                    if ($searchProvider -eq "kimi") {
                        openclaw config set tools.web.search.provider kimi | Out-Null
                        openclaw config set tools.web.search.kimi.apiKey $searchApiKey | Out-Null
                        openclaw config set tools.web.search.enabled true | Out-Null
                        continue
                    }
                }
                if ($Provider -eq "moonshot") {
                    openclaw config set tools.web.search.provider kimi | Out-Null
                    openclaw config set tools.web.search.kimi.apiKey $ApiKey | Out-Null
                    openclaw config set tools.web.search.enabled true | Out-Null
                    continue
                }
                openclaw config set tools.web.search.enabled false | Out-Null
                continue
            }
            "autonomy" {
                openclaw config set skills.entries.coding-agent.enabled true | Out-Null
                openclaw config set skills.entries.tmux.enabled true | Out-Null
                openclaw config set skills.entries.healthcheck.enabled true | Out-Null
                openclaw config set skills.entries.session-logs.enabled true | Out-Null
                continue
            }
            default {
                Write-Host "[!] Skipped ${skill}: requires extra tooling not handled in Windows installer." -ForegroundColor Yellow
                continue
            }
        }
    }
}

function Apply-SelectedHooks {
    param(
        [string[]]$Hooks
    )
    if (-not $Hooks -or $Hooks.Count -eq 0) {
        return
    }
    openclaw config set hooks.internal.enabled true | Out-Null
    foreach ($hook in $Hooks) {
        try {
            & openclaw hooks enable $hook | Out-Null
        } catch {
            Write-Host "[!] Failed to enable hook ${hook}: $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }
}

$providerValue = $Provider
if ([string]::IsNullOrWhiteSpace($providerValue)) {
    $providerValue = $env:OPENCLAW_PROVIDER
}
$apiKeyValue = $ApiKey
if ([string]::IsNullOrWhiteSpace($apiKeyValue)) {
    $apiKeyValue = $env:OPENCLAW_API_KEY
}
$feishuAppIdValue = $FeishuAppId
if ([string]::IsNullOrWhiteSpace($feishuAppIdValue)) {
    $feishuAppIdValue = $env:OPENCLAW_FEISHU_APP_ID
}
$feishuAppSecretValue = $FeishuAppSecret
if ([string]::IsNullOrWhiteSpace($feishuAppSecretValue)) {
    $feishuAppSecretValue = $env:OPENCLAW_FEISHU_APP_SECRET
}
$feishuGroupPolicyValue = $FeishuGroupPolicy
if ([string]::IsNullOrWhiteSpace($feishuGroupPolicyValue)) {
    $feishuGroupPolicyValue = $env:OPENCLAW_FEISHU_GROUP_POLICY
}
$feishuGroupAllowFromValue = $FeishuGroupAllowFrom
if ([string]::IsNullOrWhiteSpace($feishuGroupAllowFromValue)) {
    $feishuGroupAllowFromValue = $env:OPENCLAW_FEISHU_GROUP_ALLOW_FROM
}
$skillsValue = $Skills
if ([string]::IsNullOrWhiteSpace($skillsValue)) {
    $skillsValue = $env:OPENCLAW_SKILLS
}
$hooksValue = $Hooks
if ([string]::IsNullOrWhiteSpace($hooksValue)) {
    $hooksValue = $env:OPENCLAW_HOOKS
}
$pairingCodeValue = $PairingCode
if ([string]::IsNullOrWhiteSpace($pairingCodeValue)) {
    $pairingCodeValue = $env:OPENCLAW_PAIRING_CODE
}
$wizardListener = $null

if ([string]::IsNullOrWhiteSpace($apiKeyValue) -or [string]::IsNullOrWhiteSpace($feishuAppIdValue) -or [string]::IsNullOrWhiteSpace($feishuAppSecretValue)) {
    if (-not $NoWeb) {
        $defaultsProvider = Normalize-Provider $providerValue
        $defaultsSkills = Normalize-Skills $skillsValue
        $defaultsHooks = Normalize-Hooks $hooksValue
        $defaultsFeishuGroupPolicy = Normalize-FeishuGroupPolicy $feishuGroupPolicyValue
        $defaultsFeishuGroupAllowFrom = Normalize-FeishuGroupAllowFrom $feishuGroupAllowFromValue
        $webConfig = Get-WebConfig -DefaultProvider $defaultsProvider -DefaultSkills $defaultsSkills -DefaultHooks $defaultsHooks -DefaultFeishuGroupPolicy $defaultsFeishuGroupPolicy -DefaultFeishuGroupAllowFrom $defaultsFeishuGroupAllowFrom
        if ($webConfig) {
            $providerValue = $webConfig.provider
            $apiKeyValue = $webConfig.apiKey
            $feishuAppIdValue = $webConfig.feishuAppId
            $feishuAppSecretValue = $webConfig.feishuAppSecret
            $feishuGroupPolicyValue = $webConfig.feishuGroupPolicy
            $feishuGroupAllowFromValue = $webConfig.feishuGroupAllowFrom
            $skillsValue = $webConfig.skillsCsv
            $hooksValue = $webConfig.hooksCsv
            $wizardListener = $webConfig.listener
            if ([string]::IsNullOrWhiteSpace($pairingCodeValue)) {
                $pairingCodeValue = $webConfig.pairingCode
            }
        }
    }
}

if ([string]::IsNullOrWhiteSpace($apiKeyValue) -or [string]::IsNullOrWhiteSpace($feishuAppIdValue) -or [string]::IsNullOrWhiteSpace($feishuAppSecretValue)) {
    Write-Host "Missing required config. Set OPENCLAW_API_KEY, OPENCLAW_FEISHU_APP_ID, OPENCLAW_FEISHU_APP_SECRET or use web setup." -ForegroundColor Red
    exit 1
}

$providerValue = Normalize-Provider $providerValue

Write-Host "Checking prerequisite environment (NuGet/winget/Node.js)..." -ForegroundColor Cyan
Ensure-Prerequisites

$env:OPENCLAW_NO_ONBOARD = "1"
iwr -useb $InstallScriptUrl | iex
Refresh-ProcessPath

if (-not (Ensure-OpenClawOnPath)) {
    Write-Host "OpenClaw not found on PATH. Restart terminal or add npm global bin to PATH." -ForegroundColor Yellow
    exit 1
}

openclaw doctor --fix | Out-Null

$authChoice = "kimi-code-api-key"
$keyFlag = "--kimi-code-api-key"
if ($providerValue -eq "moonshot") {
    $authChoice = "moonshot-api-key"
    $keyFlag = "--moonshot-api-key"
} elseif ($providerValue -eq "minimax") {
    $authChoice = "minimax-api"
    $keyFlag = "--minimax-api-key"
} elseif ($providerValue -eq "zai") {
    $authChoice = "zai-api-key"
    $keyFlag = "--zai-api-key"
} elseif ($providerValue -eq "zai-global") {
    $authChoice = "zai-global"
    $keyFlag = "--zai-api-key"
} elseif ($providerValue -eq "zai-cn") {
    $authChoice = "zai-cn"
    $keyFlag = "--zai-api-key"
} elseif ($providerValue -eq "zai-coding-global") {
    $authChoice = "zai-coding-global"
    $keyFlag = "--zai-api-key"
} elseif ($providerValue -eq "zai-coding-cn") {
    $authChoice = "zai-coding-cn"
    $keyFlag = "--zai-api-key"
}

& openclaw onboard --non-interactive --accept-risk --mode local --auth-choice $authChoice $keyFlag $apiKeyValue --skip-channels --skip-daemon --skip-skills --skip-ui --skip-health --gateway-bind loopback --gateway-port 18789

try {
    openclaw plugins enable feishu | Out-Null
} catch {
    openclaw plugins install @openclaw/feishu | Out-Null
    openclaw plugins enable feishu | Out-Null
}

openclaw config set channels.feishu.enabled true | Out-Null
openclaw config set channels.feishu.accounts.default.appId $feishuAppIdValue | Out-Null
openclaw config set channels.feishu.accounts.default.appSecret $feishuAppSecretValue | Out-Null
$dmPolicy = $env:OPENCLAW_FEISHU_DM_POLICY
if ([string]::IsNullOrWhiteSpace($dmPolicy)) {
    $dmPolicy = "pairing"
}
openclaw config set channels.feishu.dmPolicy $dmPolicy | Out-Null
if ($dmPolicy -eq "open") {
    openclaw config set channels.feishu.allowFrom '["*"]' --strict-json | Out-Null
} else {
    openclaw config unset channels.feishu.allowFrom | Out-Null
}
$feishuGroupPolicyNormalized = Normalize-FeishuGroupPolicy $feishuGroupPolicyValue
$feishuGroupAllowFromList = Normalize-FeishuGroupAllowFrom $feishuGroupAllowFromValue
openclaw config set channels.feishu.groupPolicy $feishuGroupPolicyNormalized | Out-Null
if ($feishuGroupPolicyNormalized -eq "allowlist" -and $feishuGroupAllowFromList -and $feishuGroupAllowFromList.Count -gt 0) {
    $feishuGroupAllowFromJson = $feishuGroupAllowFromList | ConvertTo-Json -Compress
    openclaw config set channels.feishu.groupAllowFrom $feishuGroupAllowFromJson --strict-json | Out-Null
} else {
    openclaw config unset channels.feishu.groupAllowFrom | Out-Null
}

$skillsList = Normalize-Skills $skillsValue
Apply-SelectedSkills -Skills $skillsList -Provider $providerValue -ApiKey $apiKeyValue
$hooksList = Normalize-Hooks $hooksValue
Apply-SelectedHooks -Hooks $hooksList

try {
    openclaw gateway install | Out-Null
    openclaw gateway start | Out-Null
} catch {
}

$dashboardOpened = $false
$dashboardUrl = Get-ControlUiUrl
$dashboardToken = Get-GatewayToken
$dashboardOpenUrl = Build-ControlUiOpenUrl -BaseUrl $dashboardUrl -Token $dashboardToken
if ([string]::IsNullOrWhiteSpace($pairingCodeValue) -and -not $NoWeb -and $wizardListener) {
    Write-Host "Waiting for pairing code submission in the same setup page..." -ForegroundColor Cyan
    Open-Dashboard -BaseUrl $dashboardUrl -OpenUrl $dashboardOpenUrl -Token $dashboardToken
    $dashboardOpened = $true
    $pairingCodeValue = Get-PairingCodeFromWizardWeb -Listener $wizardListener
} elseif ($wizardListener -and $wizardListener.IsListening) {
    $wizardListener.Stop()
}
if (-not [string]::IsNullOrWhiteSpace($pairingCodeValue)) {
    & openclaw pairing approve feishu $pairingCodeValue | Out-Null
    Write-Host "Feishu pairing completed." -ForegroundColor Green
} else {
    Write-Host "Feishu pairing skipped. You can run: openclaw pairing approve feishu <Pairing code>" -ForegroundColor Yellow
}

if (-not $dashboardOpened) {
    Open-Dashboard -BaseUrl $dashboardUrl -OpenUrl $dashboardOpenUrl -Token $dashboardToken
}

Write-Host "Installed and configured successfully." -ForegroundColor Green
Write-Host "Provider: $providerValue" -ForegroundColor Cyan
Write-Host "Feishu groupPolicy: $feishuGroupPolicyNormalized" -ForegroundColor Cyan
if ($feishuGroupPolicyNormalized -eq "allowlist" -and $feishuGroupAllowFromList -and $feishuGroupAllowFromList.Count -gt 0) {
    Write-Host "Feishu groupAllowFrom: $($feishuGroupAllowFromList -join ",")" -ForegroundColor Cyan
}
if ($skillsList -and $skillsList.Count -gt 0) {
    Write-Host "Selected Skills: $($skillsList -join ",")" -ForegroundColor Cyan
}
if ($hooksList -and $hooksList.Count -gt 0) {
    Write-Host "Selected Hooks: $($hooksList -join ",")" -ForegroundColor Cyan
}
