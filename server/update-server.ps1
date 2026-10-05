# =============================================================
#  sama-chat 服务器一键更新脚本（管理员 PowerShell）
#  用法（复制到服务器上运行）：
#    iex (iwr 'https://gh-proxy.com/https://raw.githubusercontent.com/qweQ-1/sama-chat/main/server/update-server.ps1' -UseBasicParsing).Content
#
#  做三件事：下载最新代码 → 替换 src（保留 node_modules 与数据）→ 重启并自检
# =============================================================

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

Write-Host ">>> [1/3] 下载最新服务端代码…" -ForegroundColor Cyan
Invoke-WebRequest 'https://gh-proxy.com/https://github.com/qweQ-1/sama-chat/archive/refs/heads/main.zip' `
  -OutFile 'C:\sama-chat\src.zip' -UseBasicParsing -TimeoutSec 300
Write-Host "    下载完成 ✓"

Write-Host ">>> [2/3] 替换代码（保留依赖 node_modules 和聊天数据）…" -ForegroundColor Cyan
Expand-Archive 'C:\sama-chat\src.zip' 'C:\sama-chat\tmp' -Force
Remove-Item -Recurse -Force 'C:\sama-chat\server\src.old' -ErrorAction SilentlyContinue
Move-Item 'C:\sama-chat\server\src' 'C:\sama-chat\server\src.old'
Copy-Item 'C:\sama-chat\tmp\sama-chat-main\server\src' 'C:\sama-chat\server\src' -Recurse
Remove-Item -Recurse -Force 'C:\sama-chat\tmp', 'C:\sama-chat\src.zip'
Write-Host "    代码已更新 ✓（旧代码备份在 src.old）"

Write-Host ">>> [3/3] 重启服务…" -ForegroundColor Cyan
Get-CimInstance Win32_Process -Filter "Name='node.exe'" | Where-Object { $_.CommandLine -like '*sama-chat*' -or $_.CommandLine -like '*src\index.js*' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
Start-Sleep 2
Start-Process 'C:\sama-chat\start.bat' -WindowStyle Hidden
Start-Sleep 8
try {
  $r = (Invoke-WebRequest 'http://127.0.0.1:8719/health' -UseBasicParsing -TimeoutSec 10).Content
  Write-Host ">>> 完成！自检通过: $r" -ForegroundColor Green
} catch {
  Write-Host ">>> 自检失败，把窗口内容截图发我" -ForegroundColor Red
}
