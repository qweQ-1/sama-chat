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
set /p SSHUSER=SSH 用户名 (直接回车 = root): 
if "%SSHUSER%"=="" set SSHUSER=root

echo.
echo 登录方式：
echo    [1] SSH 密钥 (默认，推荐)
echo    [2] 密码
set /p LOGINMODE=请选择 (直接回车 = 密钥): 

if "%LOGINMODE%"=="2" (
    set SSHOPT=
    echo [使用密码登录]
) else (
    echo.
    echo 密钥文件一般在：C:\Users\你的用户名\.ssh\id_rsa
    echo 云厂商给的通常是下载的 .pem 文件，比如 C:\Users\你\Downloads\key.pem
    set /p KEYPATH=请输入密钥文件完整路径: 
    if "%KEYPATH%"=="" (
        echo [错误] 密钥路径不能为空
        pause
        exit /b 1
    )
    if not exist "%KEYPATH%" (
        echo [错误] 找不到密钥文件: %KEYPATH%
        echo.
        echo 如果你的密钥是 .ppk 结尾（PuTTY 格式），OpenSSH 用不了
        echo 解决：用 PuTTYgen 打开它 -^> Conversions -^> Export OpenSSH key 保存后再试
        pause
        exit /b 1
    )
    rem 修复密钥权限（Windows OpenSSH 要求私钥只能本人读，否则直接拒绝）
    icacls "%KEYPATH%" /inheritance:r /grant:r "%USERNAME%:R" >nul 2>&1
    set SSHOPT=-i "%KEYPATH%"
    echo [使用密钥] %KEYPATH%
    echo (如果密钥有密码短语，接下来会提示输入，输完回车)
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
echo [2/3] 正在上传到 %SSHUSER%@%SERVERIP% ...
scp %SSHOPT% sama-data.tgz %SSHUSER%@%SERVERIP%:/tmp/
if errorlevel 1 (
    echo.
    echo [错误] 上传失败，请检查：
    echo   1. IP / 用户名是否正确
    echo   2. 密钥文件是否选对（.ppk 不行，要 OpenSSH 格式）
    echo   3. 云厂商安全组是否放行 22 端口
    echo   4. 密钥密码短语是否输错
    pause
    exit /b 1
)

echo.
echo [3/3] 正在服务器上解压 ...
ssh %SSHOPT% %SSHUSER%@%SERVERIP% "rm -rf /tmp/sama-srv && mkdir -p /tmp/sama-srv && tar -xzf /tmp/sama-data.tgz -C /tmp/sama-srv && echo '--- 解压内容 ---' && ls /tmp/sama-srv && wget -q -O /tmp/migrate.sh https://gh-proxy.com/https://raw.githubusercontent.com/qweQ-1/sama-chat/main/ci/migrate-to-server.sh && echo '迁移脚本已就绪'"
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
