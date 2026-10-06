; SamaChat（萨摩聊天）Windows 安装脚本 —— 用 Inno Setup 6 编译
; CI 用法：iscc /DMyAppVersion=2.2.0 ci\windows-installer.iss
;
; 特点：
; - 固定安装到「%LOCALAPPDATA%\Programs\SamaChat」（无需管理员权限、不弹 UAC）
; - 安装时可选「创建桌面快捷方式」（默认勾选，升级时记住选择）
; - 同 AppId 直接覆盖升级，安装文件夹保持不变 → 自动更新只需跑新版安装包

#ifndef MyAppVersion
  #define MyAppVersion "0.0.0"
#endif

#define MyAppName "萨摩聊天"
#define MyAppExeName "samachat.exe"

[Setup]
AppId={{9E7B3A42-6F1D-4C58-B2A9-3D8E5F0C1A67}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName} {#MyAppVersion}
AppPublisher=SamaChat
DefaultDirName={autopf}\SamaChat
DisableDirPage=yes
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
SourceDir=..
OutputDir=dist
OutputBaseFilename=SamaChat-{#MyAppVersion}-setup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
CloseApplications=yes
RestartApplications=yes
UninstallDisplayName={#MyAppName}
UninstallDisplayIcon={app}\{#MyAppExeName}

[Tasks]
Name: "desktopicon"; Description: "创建桌面快捷方式"; GroupDescription: "附加任务："; Flags: checkedonce

[Files]
Source: "app\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "运行 {#MyAppName}"; Flags: nowait postinstall skipifsilent
