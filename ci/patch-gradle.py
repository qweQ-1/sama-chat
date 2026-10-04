#!/usr/bin/env python3
"""CI 用：为 flutter_local_notifications 开启 core library desugaring。
兼容 Kotlin DSL (build.gradle.kts) 与 Groovy DSL (build.gradle)。"""
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
KTS = os.path.join(ROOT, 'app', 'android', 'app', 'build.gradle.kts')
GROOVY = os.path.join(ROOT, 'app', 'android', 'app', 'build.gradle')

DESUGAR_VERSION = '2.1.4'


def patch_kts(path):
    s = open(path).read()
    changed = False
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
    if changed:
        open(path, 'w').write(s)
    print(('patched: ' if changed else 'already ok: ') + path)


def patch_groovy(path):
    s = open(path).read()
    changed = False
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
    if changed:
        open(path, 'w').write(s)
    print(('patched: ' if changed else 'already ok: ') + path)


if os.path.exists(KTS):
    patch_kts(KTS)
elif os.path.exists(GROOVY):
    patch_groovy(GROOVY)
else:
    print('WARN: no android build.gradle found')
