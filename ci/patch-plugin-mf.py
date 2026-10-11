#!/usr/bin/env python3
"""CI 用补丁：给 video_player_win 插件加 Media Foundation 延迟加载。

背景：video_player_win 静态导入 mfplat.dll（#pragma comment(lib, "Mfplat")）。
在缺少 Media Foundation 的 Windows（Server 精简版 / N 版）上，插件 DLL
会加载失败，导致整个 App 启动即崩（"找不到 MF.dll"）。

把 mfplat.dll 改为延迟加载（DELAYLOAD）后：
- 系统缺 MF 时 App 仍能正常启动、聊天一切正常
- 只有真正播放视频时才会报错（Dart 层已提前检测并给出友好提示）

放在 `flutter pub get` 之后、`flutter build windows` 之前执行。
"""
import glob
import os

PKG_CACHE = os.path.expanduser('~/.pub-cache/hosted')
if not os.path.exists(PKG_CACHE):
    alt = os.environ.get('PUB_CACHE')
    if alt and os.path.exists(alt):
        PKG_CACHE = os.path.join(alt, 'hosted')

MARK = 'sama-chat delayload patch'
PATCH = f'''
# ===== {MARK} =====
# Media Foundation 延迟加载：缺 MF 的系统（Server 精简版/N版）也能启动 App
if (WIN32)
  target_link_options(${{PLUGIN_NAME}} PRIVATE "/DELAYLOAD:mfplat.dll")
  target_link_libraries(${{PLUGIN_NAME}} PRIVATE delayimp)
endif()
# ===== end {MARK} =====
'''

patched = []
for host in glob.glob(os.path.join(PKG_CACHE, '*')):
    for pkg in glob.glob(os.path.join(host, 'video_player_win-*')):
        cmake = os.path.join(pkg, 'windows', 'CMakeLists.txt')
        if not os.path.isfile(cmake):
            continue
        s = open(cmake, 'r', encoding='utf-8').read()
        if MARK in s:
            continue
        with open(cmake, 'a', encoding='utf-8') as f:
            f.write(PATCH)
        patched.append(cmake)

if patched:
    for p in patched:
        print('patched mf delayload ->', p)
else:
    print('WARN: video_player_win not found in', PKG_CACHE)
