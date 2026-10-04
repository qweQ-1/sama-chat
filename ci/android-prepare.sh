#!/usr/bin/env bash
# Runs after `flutter create`: patches the generated Android project.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# Remove the template counter-app test (we ship our own tests).
rm -f "$ROOT/app/test/widget_test.dart"

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
  echo "--- manifest network config ---"
  grep -o 'android.permission.INTERNET\|usesCleartextTraffic="[^"]*"' "$MANIFEST" || true
fi

echo "android-prepare done"
