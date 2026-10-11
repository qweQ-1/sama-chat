#!/usr/bin/env bash
# ============================================================================
# sama-chat 服务端一键更新（Ubuntu / Linux）
# 用法：sudo bash update-linux.sh
#   流程：拉最新代码 → 只替换 server/ 源码（保留 data/uploads/配置/.env）→
#         安装依赖 → 重启服务 → 自检
# ============================================================================
set -euo pipefail

[[ $EUID -eq 0 ]] || { echo "请用 sudo 运行"; exit 1; }
APP_DIR=/opt/sama-chat
SVC_USER=sama-chat
[[ -d "$APP_DIR/server" ]] || { echo "❌ 找不到 $APP_DIR/server"; exit 1; }

echo "──── 1/5 下载最新代码 ────"
curl -sL --max-time 120 "https://codeload.github.com/qweQ-1/sama-chat/tar.gz/refs/heads/main" -o /tmp/sama-upd.tgz \
  || { echo "❌ 下载失败"; exit 1; }
rm -rf /tmp/sama-upd && mkdir -p /tmp/sama-upd
tar xzf /tmp/sama-upd.tgz --strip-components=1 -C /tmp/sama-upd || { echo "❌ 解压失败"; exit 1; }

echo "──── 2/5 备份现有源码 ────"
BAK="$APP_DIR/server/src.bak.$(date +%s)"
cp -r "$APP_DIR/server/src" "$BAK"
echo "✓ 备份 $BAK"

echo "──── 3/5 替换源码（保留 data/uploads/.env/config.json）────"
cp -r /tmp/sama-upd/server/src/. "$APP_DIR/server/src/"
cp /tmp/sama-upd/server/package.json "$APP_DIR/server/package.json"
cp /tmp/sama-upd/server/test-e2e.mjs "$APP_DIR/server/test-e2e.mjs" 2>/dev/null || true
chown -R "$SVC_USER:$SVC_USER" "$APP_DIR/server/src" "$APP_DIR/server/package.json"
echo "✓ 源码已更新"

echo "──── 4/5 安装依赖 ────"
cd "$APP_DIR/server"
su -s /bin/bash "$SVC_USER" -c "cd $APP_DIR/server && npm install --omit=dev --no-audit --no-fund" 2>&1 | tail -2 || true
echo "✓ 依赖就绪"

echo "──── 5/5 重启 + 自检 ────"
systemctl restart sama-chat
sleep 3
PORT=$(grep -oP '^PORT=\K.*' "$APP_DIR/server/.env" 2>/dev/null || echo 8719)
if curl -sf "http://127.0.0.1:$PORT/health" >/dev/null; then
  echo "✓ 服务已重启"
  echo ""
  echo "=== 新接口自检（通话信令）==="
  code=$(curl -s -o /dev/null -w "%{http_code}" "http://127.0.0.1:$PORT/ice")
  [[ "$code" == "401" ]] && echo "✅ /ice 已上线（通话信令就绪）" || echo "⚠️ /ice 返回 $code"
  curl -s "http://127.0.0.1:$PORT/health"; echo
  echo ""
  echo "✅ 更新完成！服务器版本已是最新。"
else
  echo "❌ 服务没起来，看日志：journalctl -u sama-chat -n 40 --no-pager"
  echo "   回滚：rm -rf $APP_DIR/server/src && mv $BAK $APP_DIR/server/src && systemctl restart sama-chat"
  exit 1
fi
