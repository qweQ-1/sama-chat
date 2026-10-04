# =============================================================================
#  萨摩聊天（sama-chat）服务端一键部署脚本 — Windows PowerShell 版
#
#  用法（在服务器上操作）：
#    1. 开始菜单搜索 PowerShell → 右键 → 以管理员身份运行
#    2. 粘贴执行下面这行（复制时注意别断行）：
#       try{$c=(iwr 'https://gh-proxy.com/https://raw.githubusercontent.com/qweQ-1/sama-chat/main/server/deploy-windows.ps1' -UseBasicParsing -TimeoutSec 120).Content}catch{$c=(iwr 'https://raw.githubusercontent.com/qweQ-1/sama-chat/main/server/deploy-windows.ps1' -UseBasicParsing -TimeoutSec 120).Content}; iex $c
#
#  脚本会依次完成：装 Node.js → 下载服务端代码 → 装依赖 → 生成密钥和启动脚本
#                → 放行防火墙 → 启动服务 → 注册开机自启 → 健康检查
# =============================================================================

$ErrorActionPreference = "Continue"
$ProgressPreference = "SilentlyContinue"   # 关掉进度条，PS5.1 下载快 10 倍
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$WorkDir = "C:\sama-chat"
$Port = 8080

# ---- 0. 管理员检查 -----------------------------------------------------------
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
  Write-Host "[X] 请用【管理员身份】运行 PowerShell：开始菜单搜 PowerShell -> 右键 -> 以管理员身份运行" -ForegroundColor Red
  exit 1
}

Write-Host ""
Write-Host "==================== 萨摩聊天 服务端部署 ====================" -ForegroundColor Cyan
Write-Host ""

# ---- 1. 工作目录 -------------------------------------------------------------
Write-Host ">>> [1/7] 准备工作目录 $WorkDir" -ForegroundColor Green
New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null
Set-Location $WorkDir

# ---- 2. Node.js --------------------------------------------------------------
Write-Host ""
Write-Host ">>> [2/7] 检查 Node.js" -ForegroundColor Green
$nodeExe = $null
try { $nodeExe = (Get-Command node -ErrorAction Stop).Source } catch {}
if ($nodeExe) {
  Write-Host "已安装 Node: $(& node -v)  ($nodeExe)"
} else {
  Write-Host "未检测到 Node.js，从国内镜像下载免安装版（约 30MB）..."
  $nodeVer = "v22.23.3"
  $candidates = @(
    "https://npmmirror.com/mirrors/node/$nodeVer/node-$nodeVer-win-x64.zip",
    "https://npmmirror.com/mirrors/node/v22.22.0/node-v22.22.0-win-x64.zip",
    "https://nodejs.org/dist/$nodeVer/node-$nodeVer-win-x64.zip"
  )
  $zip = "$WorkDir\node.zip"
  $ok = $false
  foreach ($u in $candidates) {
    try {
      Write-Host "  下载: $u"
      Invoke-WebRequest -Uri $u -OutFile $zip -UseBasicParsing -TimeoutSec 600
      $ok = $true; break
    } catch { Write-Host "  下载失败，换下一个源..." -ForegroundColor Yellow }
  }
  if (-not $ok) {
    Write-Host "[X] Node.js 下载失败。请手动安装（https://nodejs.org/zh-cn 下载 LTS 版，一路下一步），装完重新运行本脚本" -ForegroundColor Red
    exit 1
  }
  Write-Host "  解压中..."
  Expand-Archive -Path $zip -DestinationPath "$WorkDir\node" -Force
  Remove-Item $zip -ErrorAction SilentlyContinue
  $nodeHome = (Get-ChildItem "$WorkDir\node" -Directory | Select-Object -First 1).FullName
  # 加到当前会话 PATH
  $env:Path = "$nodeHome;$env:Path"
  # 加到用户永久 PATH（去重）
  $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
  if ($userPath -notlike "*$nodeHome*") {
    [Environment]::SetEnvironmentVariable("Path", "$userPath;$nodeHome", "User")
  }
  $nodeExe = Join-Path $nodeHome "node.exe"
  Write-Host "Node 就绪: $(& $nodeExe -v)  ($nodeExe)"
}

# ---- 3. 服务端代码 -----------------------------------------------------------
Write-Host ""
Write-Host ">>> [3/7] 下载服务端代码" -ForegroundColor Green
if (Test-Path "$WorkDir\server\src\index.js") {
  Write-Host "代码已存在，跳过下载"
} else {
  $zip = "$WorkDir\src.zip"
  $urls = @(
    "https://gh-proxy.com/https://github.com/qweQ-1/sama-chat/archive/refs/heads/main.zip",
    "https://github.com/qweQ-1/sama-chat/archive/refs/heads/main.zip"
  )
  $ok = $false
  foreach ($u in $urls) {
    try {
      Write-Host "  下载: $u"
      Invoke-WebRequest -Uri $u -OutFile $zip -UseBasicParsing -TimeoutSec 300
      $ok = $true; break
    } catch { Write-Host "  下载失败，换下一个源..." -ForegroundColor Yellow }
  }
  if (-not $ok) { Write-Host "[X] 代码下载失败，请检查服务器网络" -ForegroundColor Red; exit 1 }
  Write-Host "  解压中..."
  Expand-Archive -Path $zip -DestinationPath "$WorkDir\tmp" -Force
  Move-Item "$WorkDir\tmp\sama-chat-main\server" "$WorkDir\server"
  Remove-Item -Recurse -Force "$WorkDir\tmp", $zip
}
Write-Host "代码就绪: $WorkDir\server"

# ---- 4. 依赖 -----------------------------------------------------------------
Write-Host ""
Write-Host ">>> [4/7] 安装依赖（用国内 npm 镜像加速）" -ForegroundColor Green
Set-Location "$WorkDir\server"
& npm install --omit=dev --no-audit --no-fund --registry=https://registry.npmmirror.com
if ($LASTEXITCODE -ne 0) {
  Write-Host "  国内源失败，改用官方源重试..." -ForegroundColor Yellow
  & npm install --omit=dev --no-audit --no-fund
}
if (-not (Test-Path "$WorkDir\server\node_modules\fastify")) {
  Write-Host "[X] 依赖安装失败，请把上面的报错发给我们" -ForegroundColor Red
  exit 1
}
Write-Host "依赖安装完成"

# ---- 5. 配置与启动脚本 --------------------------------------------------------
Write-Host ""
Write-Host ">>> [5/7] 生成密钥与启动脚本" -ForegroundColor Green
if (-not (Test-Path "$WorkDir\jwt.secret")) {
  $bytes = New-Object byte[] 32
  [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
  (($bytes | ForEach-Object { $_.ToString("x2") }) -join "") | Out-File "$WorkDir\jwt.secret" -NoNewline -Encoding ascii
}
$secret = Get-Content "$WorkDir\jwt.secret"
New-Item -ItemType Directory -Force -Path "$WorkDir\data\uploads" | Out-Null

$bat = @"
@echo off
title sama-chat server
cd /d $WorkDir\server
set PORT=$Port
set DATA_DIR=$WorkDir\data
set UPLOAD_DIR=$WorkDir\data\uploads
set JWT_SECRET=$secret
:main
"$nodeExe" src\index.js
echo [sama-chat] exited, restart in 5s...
timeout /t 5 /nobreak >nul
goto main
"@
Set-Content -Path "$WorkDir\start.bat" -Value $bat -Encoding ascii
Write-Host "启动脚本: $WorkDir\start.bat"

# ---- 6. 防火墙 + 启动 ---------------------------------------------------------
Write-Host ""
Write-Host ">>> [6/7] 放行防火墙并启动服务" -ForegroundColor Green
$listening = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue
if ($listening) {
  Write-Host "端口 $Port 已有服务在监听，跳过启动"
} else {
  Start-Process -FilePath "cmd.exe" -ArgumentList "/c `"$WorkDir\start.bat`"" -WindowStyle Hidden
  Write-Host "已后台启动，等待就绪..."
}
if (-not (Get-NetFirewallRule -DisplayName "sama-chat $Port" -ErrorAction SilentlyContinue)) {
  New-NetFirewallRule -DisplayName "sama-chat $Port" -Direction Inbound -Action Allow -Protocol TCP -LocalPort $Port | Out-Null
  Write-Host "已放行 Windows 防火墙 TCP $Port"
} else {
  Write-Host "防火墙规则已存在"
}

# 注册开机自启（任务计划）
try {
  Invoke-Expression "schtasks /Create /TN `"sama-chat`" /TR `"$WorkDir\start.bat`" /SC ONSTART /RU SYSTEM /F" | Out-Null
  Write-Host "已注册开机自启（任务计划: sama-chat）"
} catch {
  Write-Host "开机自启注册失败（不影响使用）。想手动加：任务计划程序 -> 新建任务 -> 操作选 $WorkDir\start.bat，触发器选『计算机启动时』" -ForegroundColor Yellow
}

# ---- 7. 健康检查 --------------------------------------------------------------
Write-Host ""
Write-Host ">>> [7/7] 健康检查" -ForegroundColor Green
$healthy = $false
foreach ($i in 1..6) {
  Start-Sleep -Seconds 3
  try {
    $r = Invoke-WebRequest "http://127.0.0.1:$Port/health" -UseBasicParsing -TimeoutSec 10
    Write-Host "服务正常: $($r.Content)"
    $healthy = $true
    break
  } catch {
    Write-Host "  等待服务启动... ($i/6)"
  }
}

Write-Host ""
Write-Host "==================== 部署完成 ====================" -ForegroundColor Cyan
if (-not $healthy) {
  Write-Host "[!] 健康检查暂未通过。看看 $WorkDir\start.bat 双击运行有没有报错，或把屏幕内容发给我们" -ForegroundColor Yellow
}
$publicIp = $null
foreach ($api in @("https://api.ipify.org", "https://ifconfig.me/ip", "https://ip.sb")) {
  try { $publicIp = (Invoke-WebRequest $api -UseBasicParsing -TimeoutSec 10).Content.Trim(); break } catch {}
}
if ($publicIp) {
  Write-Host ("外网地址: http://{0}:{1}" -f $publicIp, $Port) -ForegroundColor Yellow
} else {
  Write-Host "外网地址: http://<你的服务器公网IP>:$Port" -ForegroundColor Yellow
}
Write-Host ""
Write-Host "下一步：" -ForegroundColor Cyan
Write-Host "  1) 去云控制台【安全组】放行 TCP $Port（入方向，源 0.0.0.0/0）"
Write-Host "  2) 浏览器打开 http://<公网IP>:$Port/health 应看到 {`"status`":`"ok`"...}"
Write-Host "  3) 把 http://<公网IP>:$Port 填到 App 的「服务器设置」里"
Write-Host ""
Write-Host "常用操作："
Write-Host "  停止服务: taskkill /IM node.exe /F"
Write-Host "  启动服务: 双击 $WorkDir\start.bat（或重启服务器自动拉起）"
Write-Host "  数据目录: $WorkDir\data"
