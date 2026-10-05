#!/usr/bin/env bash
# Packages the flutter-built Runner.app into an unsigned .ipa (macOS).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

APP="$ROOT/app/build/ios/iphoneos/Runner.app"
if [ ! -d "$APP" ]; then
  echo "Runner.app not found at $APP"
  exit 1
fi

# 版本号从 pubspec.yaml 读取（自动同步，去掉 +build 部分）
VERSION="$(sed -n 's/^version: \([0-9][0-9.]*\).*/\1/p' "$ROOT/app/pubspec.yaml" | head -1)"
[ -n "$VERSION" ] || VERSION="1.0.0"
echo "IPA version: $VERSION"

WORK=/tmp/ipa-build
rm -rf "$WORK"
mkdir -p "$WORK/Payload"
cp -R "$APP" "$WORK/Payload/"

# Ad-hoc signature so some sideload tools are happier; harmless if it fails.
codesign -s - --force --deep "$WORK/Payload/Runner.app" 2>/dev/null \
  && echo "ad-hoc codesign applied" \
  || echo "(ad-hoc codesign skipped)"

mkdir -p "$ROOT/app/dist"
(cd "$WORK" && zip -qry "$ROOT/app/dist/SamaChat-unsigned-${VERSION}.ipa" Payload)

echo "--- artifact ---"
ls -la "$ROOT/app/dist/"
