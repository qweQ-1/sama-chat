#!/usr/bin/env bash
# Packages the flutter-built Runner.app into an unsigned .ipa (macOS).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

APP="$ROOT/app/build/ios/iphoneos/Runner.app"
if [ ! -d "$APP" ]; then
  echo "Runner.app not found at $APP"
  exit 1
fi

WORK=/tmp/ipa-build
rm -rf "$WORK"
mkdir -p "$WORK/Payload"
cp -R "$APP" "$WORK/Payload/"

# Ad-hoc signature so some sideload tools are happier; harmless if it fails.
codesign -s - --force --deep "$WORK/Payload/Runner.app" 2>/dev/null \
  && echo "ad-hoc codesign applied" \
  || echo "(ad-hoc codesign skipped)"

mkdir -p "$ROOT/app/dist"
(cd "$WORK" && zip -qry "$ROOT/app/dist/SamaChat-unsigned-1.0.0.ipa" Payload)

echo "--- artifact ---"
ls -la "$ROOT/app/dist/"
