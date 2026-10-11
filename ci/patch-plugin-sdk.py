#!/usr/bin/env python3
"""CI 用补丁：把 flutter_webrtc 插件自身的 compileSdk 从 31 提到 36。

背景：flutter_webrtc 0.12.x 的 android/build.gradle 写死 compileSdkVersion 31，
但它拉入的 androidx 库（core 1.13+、lifecycle 2.7+ 等）要求调用方 compileSdk ≥ 34，
导致 `:flutter_webrtc:compileReleaseJavaWithJavac` 之类的任务直接失败。
主 App 提高 compileSdk 无法影响插件自己的编译配置，只能改插件源码。

放在 `flutter pub get` 之后、`flutter build apk` 之前执行。
"""
import glob
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PKG_CACHE = os.path.expanduser('~/.pub-cache/hosted')
if not os.path.exists(PKG_CACHE):
    # Flutter pub 缓存也可能在 PUB_CACHE 指定位置
    alt = os.environ.get('PUB_CACHE')
    if alt and os.path.exists(alt):
        PKG_CACHE = os.path.join(alt, 'hosted')

TARGET_SDK = '36'
patched = []

# 需要修正 compileSdk 的插件（写死低版本的）
PLUGINS = ['flutter_webrtc']

for host in glob.glob(os.path.join(PKG_CACHE, '*')):
    for name in PLUGINS:
        for pkg in glob.glob(os.path.join(host, name + '-' + '*')):
            gradle = os.path.join(pkg, 'android', 'build.gradle')
            if not os.path.isfile(gradle):
                continue
            s = open(gradle).read()
            orig = s
            s = re.sub(r'compileSdkVersion\s+\d+', f'compileSdkVersion {TARGET_SDK}', s)
            s = re.sub(r'compileSdk\s+\d+', f'compileSdk {TARGET_SDK}', s)
            # Kotlin DSL
            s = re.sub(r'compileSdk\s*=\s*\d+', f'compileSdk = {TARGET_SDK}', s)
            if s != orig:
                open(gradle, 'w').write(s)
                patched.append(gradle)

if patched:
    for p in patched:
        print('patched plugin compileSdk ->', p)
else:
    print('WARN: no plugin gradle patched (cache path: %s)' % PKG_CACHE)
    # 列出缓存里现有的 flutter_webrtc，便于排查
    for host in glob.glob(os.path.join(PKG_CACHE, '*')):
        hits = glob.glob(os.path.join(host, 'flutter_webrtc-*'))
        if hits:
            print('  found but not patched:', hits[:3])
