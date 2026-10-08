@echo off
chcp 65001 >nul
setlocal enabledelayedexpansion

cd /d C:\sama-chat\server 2>nul
if errorlevel 1 (
    echo [错误] 找不到 C:\sama-chat\server 目录
    echo 请把这个 bat 文件放进 C:\sama-chat\server\ 里再双击运行
    pause
    exit /b 1
)

echo ==========================================================
echo    sama-chat 数据打包 -^> 上传到新服务器
echo ==========================================================
echo.

set /p SERVERIP=请输入 Ubuntu 服务器 IP: 
if "%SERVERIP%"=="" (
    echo IP 不能为空
    pause
    exit /b 1
)

echo.
echo [1/3] 正在打包 data + uploads + config.json ...
if exist sama-data.tgz del /f sama-data.tgz
if exist config.json (
    tar -czf sama-data.tgz data uploads config.json
) else (
    tar -czf sama-data.tgz data uploads
    echo [注意] 没找到 config.json（邮箱验证码配置），稍后需手动补
)
if errorlevel 1 (
    echo [错误] 打包失败
    pause
    exit /b 1
)
for %%I in (sama-data.tgz) do echo    打包完成: %%~zI 字节

echo.
echo [2/3] 正在上传到 %SERVERIP% ...
echo       ^(接下来会问密码，输入时屏幕不显示是正常的^)
scp sama-data.tgz root@%SERVERIP%:/tmp/
if errorlevel 1 (
    echo.
    echo [错误] 上传失败，请检查：
    echo   1. IP 是否正确
    echo   2. 密码是否正确
    echo   3. 云厂商安全组是否放行 22 端口
    pause
    exit /b 1
)

echo.
echo [3/3] 正在服务器上解压 ...
ssh root@%SERVERIP% "rm -rf /tmp/sama-srv && mkdir -p /tmp/sama-srv && tar -xzf /tmp/sama-data.tgz -C /tmp/sama-srv && echo '--- 解压内容 ---' && ls /tmp/sama-srv && wget -q -O /tmp/migrate.sh https://gh-proxy.com/https://raw.githubusercontent.com/qweQ-1/sama-chat/main/ci/migrate-to-server.sh && echo '迁移脚本已就绪'"
if errorlevel 1 (
    echo [警告] 解压步骤出错，但文件已上传成功，可手动解压
)

echo.
echo ==========================================================
echo   全部完成！
echo.
echo   现在去 Ubuntu 服务器上运行：
echo     sudo bash /tmp/migrate.sh --nginx --data /tmp/sama-srv/data --config /tmp/sama-srv/config.json
echo ==========================================================
pause
