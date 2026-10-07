#!/usr/bin/env bash
# Runs after `flutter create`: patches the generated Android project.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# Remove the template counter-app test (we ship our own tests).
rm -f "$ROOT/app/test/widget_test.dart"

# flutter_local_notifications 需要 core library desugaring
python3 "$ROOT/ci/patch-gradle.py"

# App display name.
MANIFEST="$ROOT/app/android/app/src/main/AndroidManifest.xml"
if [ -f "$MANIFEST" ]; then
  sed -i 's/android:label="[^"]*"/android:label="萨摩聊天"/' "$MANIFEST"
  echo "--- manifest label ---"
  grep -o 'android:label="[^"]*"' "$MANIFEST" | head -2 || true

  # Release builds need INTERNET permission explicitly.
  if ! grep -q 'android.permission.INTERNET' "$MANIFEST"; then
    sed -i 's|<manifest\([^>]*\)>|<manifest\1>\n    <uses-permission android:name="android.permission.INTERNET"/>|' "$MANIFEST"
  fi

  # Allow plain-HTTP connections (self-hosted servers may not have HTTPS yet).
  if ! grep -q 'usesCleartextTraffic' "$MANIFEST"; then
    sed -i 's|<application |<application android:usesCleartextTraffic="true" |' "$MANIFEST"
  fi

  # 通知权限 + 前台保活服务（flutter_foreground_task）
  if ! grep -q 'POST_NOTIFICATIONS' "$MANIFEST"; then
    sed -i 's|<manifest\([^>]*\)>|<manifest\1>\n    <uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>\n    <uses-permission android:name="android.permission.FOREGROUND_SERVICE"/>\n    <uses-permission android:name="android.permission.FOREGROUND_SERVICE_DATA_SYNC"/>\n    <uses-permission android:name="android.permission.WAKE_LOCK"/>|' "$MANIFEST"
  fi
  if ! grep -q 'ForegroundService' "$MANIFEST"; then
    sed -i 's|<manifest |<manifest xmlns:tools="http://schemas.android.com/tools" |' "$MANIFEST"
    sed -i 's|</application>|        <service android:name="com.pravera.flutter_foreground_task.service.ForegroundService" android:foregroundServiceType="dataSync" android:exported="false" tools:replace="android:foregroundServiceType" />\n    </application>|' "$MANIFEST"
  fi

  # 应用内更新：允许拉起 APK 安装器
  if ! grep -q 'REQUEST_INSTALL_PACKAGES' "$MANIFEST"; then
    sed -i 's|<manifest\([^>]*\)>|<manifest\1>\n    <uses-permission android:name="android.permission.REQUEST_INSTALL_PACKAGES"/>|' "$MANIFEST"
  fi

  # 语音消息：录音权限
  if ! grep -q 'RECORD_AUDIO' "$MANIFEST"; then
    sed -i 's|<manifest\([^>]*\)>|<manifest\1>\n    <uses-permission android:name="android.permission.RECORD_AUDIO"/>|' "$MANIFEST"
  fi

  echo "--- manifest network config ---"
  grep -o 'android.permission.INTERNET\|POST_NOTIFICATIONS\|ForegroundService' "$MANIFEST" || true
fi

echo "android-prepare done"
