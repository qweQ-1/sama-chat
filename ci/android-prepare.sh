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
fi

echo "android-prepare done"
