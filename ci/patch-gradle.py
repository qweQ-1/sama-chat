#!/usr/bin/env python3
"""CI 用构建补丁：
1. 为 flutter_local_notifications 开启 core library desugaring
2. 使用固定签名密钥（ci/sama-release.keystore），保证所有版本签名一致、可覆盖升级
兼容 Kotlin DSL (build.gradle.kts) 与 Groovy DSL (build.gradle)。
"""
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
KTS = os.path.join(ROOT, 'app', 'android', 'app', 'build.gradle.kts')
GROOVY = os.path.join(ROOT, 'app', 'android', 'app', 'build.gradle')

DESUGAR_VERSION = '2.1.4'
KEYSTORE = '../../../ci/sama-release.keystore'
KS_PASS = 'samachat123'
KS_ALIAS = 'sama-chat'



def patch_kts(path):
    s = open(path).read()
    changed = False

    # flutter_webrtc 要求 minSdk >= 23
    if 'minSdk = ' in s and 'minSdk = 23' not in s:
        import re
        s2 = re.sub(r'minSdk = flutter\.minSdkVersion', 'minSdk = 23', s)
        s2 = re.sub(r'minSdk = \d+', 'minSdk = 23', s2)
        if s2 != s:
            s = s2
            changed = True

    # --- desugaring ---
    if 'isCoreLibraryDesugaringEnabled' not in s:
        if 'compileOptions {' in s:
            s = s.replace(
                'compileOptions {',
                'compileOptions {\n        isCoreLibraryDesugaringEnabled = true',
                1,
            )
            changed = True
        else:
            print('WARN: compileOptions { not found in', path)
    if 'desugar_jdk_libs' not in s:
        s += (
            '\n\ndependencies {\n'
            f'    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:{DESUGAR_VERSION}")\n'
            '}\n'
        )
        changed = True

    # --- 固定签名 ---
    if 'samarelease' not in s:
        signing_block = (
            'signingConfigs {\n'
            '        create("samarelease") {\n'
            f'            storeFile = file("{KEYSTORE}")\n'
            f'            storePassword = "{KS_PASS}"\n'
            f'            keyAlias = "{KS_ALIAS}"\n'
            f'            keyPassword = "{KS_PASS}"\n'
            '            storeType = "PKCS12"\n'
            '        }\n'
            '    }\n\n'
            '    buildTypes {'
        )
        idx = s.find('buildTypes {')
        if idx != -1:
            s = s[:idx] + signing_block + s[idx + len('buildTypes {'):]
            changed = True
        else:
            print('WARN: buildTypes { not found in', path)
        if 'signingConfig = signingConfigs.getByName("debug")' in s:
            s = s.replace(
                'signingConfig = signingConfigs.getByName("debug")',
                'signingConfig = signingConfigs.getByName("samarelease")',
            )
            changed = True

    if changed:
        open(path, 'w').write(s)
    print(('patched: ' if changed else 'already ok: ') + path)


def patch_groovy(path):
    s = open(path).read()
    changed = False

    # flutter_webrtc 要求 minSdk >= 23
    if 'minSdkVersion' in s and 'minSdkVersion 23' not in s:
        import re
        s2 = re.sub(r'minSdkVersion flutter\.minSdkVersion', 'minSdkVersion 23', s)
        s2 = re.sub(r'minSdkVersion \d+', 'minSdkVersion 23', s2)
        if s2 != s:
            s = s2
            changed = True

    # --- desugaring ---
    if 'coreLibraryDesugaringEnabled' not in s:
        if 'compileOptions {' in s:
            s = s.replace(
                'compileOptions {',
                'compileOptions {\n        coreLibraryDesugaringEnabled true',
                1,
            )
            changed = True
        else:
            print('WARN: compileOptions { not found in', path)
    if 'desugar_jdk_libs' not in s:
        s += (
            '\n\ndependencies {\n'
            f"    coreLibraryDesugaring 'com.android.tools:desugar_jdk_libs:{DESUGAR_VERSION}'\n"
            '}\n'
        )
        changed = True

    # --- 固定签名 ---
    if 'samarelease' not in s:
        signing_block = (
            'signingConfigs {\n'
            '        samarelease {\n'
            f'            storeFile file("{KEYSTORE}")\n'
            f'            storePassword "{KS_PASS}"\n'
            f'            keyAlias "{KS_ALIAS}"\n'
            f'            keyPassword "{KS_PASS}"\n'
            '            storeType "PKCS12"\n'
            '        }\n'
            '    }\n\n'
            '    buildTypes {'
        )
        idx = s.find('buildTypes {')
        if idx != -1:
            s = s[:idx] + signing_block + s[idx + len('buildTypes {'):]
            changed = True
        else:
            print('WARN: buildTypes { not found in', path)
        if 'signingConfig signingConfigs.debug' in s:
            s = s.replace(
                'signingConfig signingConfigs.debug',
                'signingConfig signingConfigs.samarelease',
            )
            changed = True

    if changed:
        open(path, 'w').write(s)
    print(('patched: ' if changed else 'already ok: ') + path)


if os.path.exists(KTS):
    patch_kts(KTS)
elif os.path.exists(GROOVY):
    patch_groovy(GROOVY)
else:
    print('WARN: no android build.gradle found')
