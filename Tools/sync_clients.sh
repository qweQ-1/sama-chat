#!/bin/sh
# 把下载好的网页版 Minecraft 客户端同步进仓库的 Clients/ 目录。
#
# 源目录：/var/minis/workspace/eaglercraft/<版本>/（含 index.html）
# 目标：  <仓库>/Clients/<版本>/
#
# 用法： sh Tools/sync_clients.sh [源目录] [目标仓库]
set -eu

SRC="${1:-/var/minis/workspace/eaglercraft}"
DST="${2:-$(cd "$(dirname "$0")/.." && pwd)}"

echo "源：$SRC"
echo "目标：$DST/Clients"

mkdir -p "$DST/Clients"

for dir in "$SRC"/*/; do
  [ -d "$dir" ] || continue
  name=$(basename "$dir")
  case "$name" in
    _*|.*) echo "跳过 $name"; continue ;;
  esac
  if [ ! -f "$dir/index.html" ] && [ ! -f "$dir"/index.htm ]; then
    # 允许只有单个自包含 html 的情况
    single=$(find "$dir" -maxdepth 1 -name '*.html' | head -1)
    if [ -z "$single" ]; then
      echo "跳过 $name（没有 index.html）"
      continue
    fi
  fi
  echo "同步 $name ..."
  rm -rf "$DST/Clients/$name"
  mkdir -p "$DST/Clients/$name"
  cp -R "$dir"/. "$DST/Clients/$name"/
  # 确保入口文件名叫 index.html
  if [ ! -f "$DST/Clients/$name/index.html" ]; then
    single=$(find "$DST/Clients/$name" -maxdepth 1 -name '*.html' | head -1)
    if [ -n "$single" ]; then
      cp "$single" "$DST/Clients/$name/index.html"
    fi
  fi
  du -sh "$DST/Clients/$name"
done

echo "---- 结果"
find "$DST/Clients" -maxdepth 2 -name 'index.html' -o -maxdepth 1 -name '*.json' | sort
du -sh "$DST/Clients"
