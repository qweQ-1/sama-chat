#!/usr/bin/env bash
# Runs after `flutter create --platforms=windows` (on the Windows runner, via Git Bash).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

rm -f "$ROOT/app/test/widget_test.dart"

# 窗口标题 → 萨摩聊天（用 C++ Unicode 转义，避免源码编码问题）
MAIN="$ROOT/app/windows/runner/main.cpp"
if [ -f "$MAIN" ]; then
  sed -i 's|window.Create(L"samachat"|window.Create(L"\\u8428\\u6469\\u804a\\u5929"|' "$MAIN"
  echo "--- window.Create ---"
  grep -n "window.Create" "$MAIN" || true
fi

echo "windows-prepare done"
