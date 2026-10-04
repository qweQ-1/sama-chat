#!/usr/bin/env bash
# Runs after `flutter create` (macOS): patches the generated iOS project.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

rm -f "$ROOT/app/test/widget_test.dart"

PLIST="$ROOT/app/ios/Runner/Info.plist"

plist_set() {
  /usr/libexec/PlistBuddy -c "Add :$1 string $2" "$PLIST" 2>/dev/null \
    || /usr/libexec/PlistBuddy -c "Set :$1 $2" "$PLIST"
}

plist_set CFBundleDisplayName "萨摩聊天"
plist_set NSCameraUsageDescription "用于扫描二维码，面对面添加好友"
plist_set NSPhotoLibraryUsageDescription "用于发送图片、发布炫圈和更换头像"

echo "--- plist keys ---"
/usr/libexec/PlistBuddy -c "Print :CFBundleDisplayName" "$PLIST" || true
/usr/libexec/PlistBuddy -c "Print :NSCameraUsageDescription" "$PLIST" || true

# iOS deployment target: raise to satisfy modern plugins (mobile_scanner etc.)
PODFILE="$ROOT/app/ios/Podfile"
if [ -f "$PODFILE" ]; then
  if grep -q "platform :ios" "$PODFILE"; then
    sed -i '' -E "s/# *platform :ios, '[0-9.]+'/platform :ios, '15.5'/; s/^platform :ios, '[0-9.]+'/platform :ios, '15.5'/" "$PODFILE"
  else
    sed -i '' "1a\\
platform :ios, '15.5'
" "$PODFILE"
  fi
  echo "--- podfile platform ---"
  grep -n "platform :ios" "$PODFILE" | head -3 || true
fi

PBX="$ROOT/app/ios/Runner.xcodeproj/project.pbxproj"
if [ -f "$PBX" ]; then
  sed -i '' -E "s/IPHONEOS_DEPLOYMENT_TARGET = [0-9.]+;/IPHONEOS_DEPLOYMENT_TARGET = 15.5;/g" "$PBX"
fi

echo "ios-prepare done"
