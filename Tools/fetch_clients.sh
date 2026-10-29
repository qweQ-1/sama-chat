#!/bin/sh
# 把「网页版 Minecraft」客户端拉取到 Clients/<版本>/ 。
#
# 仓库里不放这些二进制（体积大 + Minecraft 衍生资源不适合进公开仓库），
# 所以本地想看效果、以及 CI 出 IPA 时，都靠这个脚本现拉。
#
# 用法：  sh Tools/fetch_clients.sh [目标 Clients 目录]
# 环境：  FORCE=1 强制重新下载
set -eu

DST="${1:-$(cd "$(dirname "$0")/.." && pwd)/Clients}"
FORCE="${FORCE:-0}"

B="https://raw.githubusercontent.com/3kh0/eaglercraft-builds/main"
J="https://raw.githubusercontent.com/JessePinkman27/eaglercraft-1.12.2/main"

hash_of() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

fetch() {
  url="$1"; out="$2"; label="$3"
  mkdir -p "$(dirname "$out")"
  if [ -s "$out" ] && [ "$FORCE" != "1" ]; then
    echo "== 已存在，跳过 $label ($(hash_of "$out"))"
    return 0
  fi
  echo "== 下载 $label"
  echo "   $url"
  curl -fL --retry 4 --retry-delay 3 --retry-all-errors --max-time 1800 \
       --connect-timeout 30 -o "$out.part" "$url"
  mv "$out.part" "$out"
  echo "   字节数 $(wc -c < "$out")  sha256 $(hash_of "$out")"
}

fetch "$B/EaglercraftX_1.8_Offline_International.html" "$DST/1.8/index.html"     "EaglercraftX 1.8（EaglercraftX_1.8_Offline_International）"
fetch "$B/Eaglercraft_1.5_Offline_Download.html"      "$DST/1.5.2/index.html"   "Eaglercraft 1.5.2（Eaglercraft_1.5_Offline_Download）"
fetch "$J/offline_download/wasm/Eaglercraft_1.12.2_WASM_Offline_Download.html" "$DST/1.12.2/index.html" "Eaglercraft 1.12.2（社区移植，实验）"

echo "---- Clients 目录"
du -sh "$DST" 2>/dev/null || true
find "$DST" -maxdepth 2 -name 'index.html' -o -maxdepth 2 -name 'version.json' | sort
