#!/usr/bin/env bash
# ============================================================================
# sama-chat 启用 AI 生图（mama秀 专属形象）
# 用法：sudo bash setup-ai.sh
#   会交互式询问 API Key（不回显、不落日志），写入服务器 .env 后重启服务
# ============================================================================
set -euo pipefail

[[ $EUID -eq 0 ]] || { echo "请用 sudo 运行"; exit 1; }
ENV_FILE=/opt/sama-chat/server/.env
[[ -f "$ENV_FILE" ]] || { echo "❌ 找不到 $ENV_FILE（先确认已部署）"; exit 1; }

echo "════════════════════════════════════════"
echo "  启用 mama秀 AI 生图"
echo "════════════════════════════════════════"
echo ""
echo "请粘贴你的 AI 平台 API Key（输入时不显示、不会存到日志）："
read -r -s AIKEY
echo ""
[[ -n "$AIKEY" ]] || { echo "❌ Key 不能为空"; exit 1; }

echo ""
echo "API 地址（直接回车 = https://api1.weilai.chat）："
read -r AIBASE
AIBASE="${AIBASE:-https://api1.weilai.chat}"

echo "模型（直接回车 = gpt-image-2.5）："
read -r AIMODEL
AIMODEL="${AIMODEL:-gpt-image-2.5}"

echo "每人每天生成上限（直接回车 = 5 次）："
read -r AILIMIT
AILIMIT="${AILIMIT:-5}"

# 幂等：先删旧配置行
sed -i '/^AI_IMAGE_KEY=/d;/^AI_IMAGE_BASE_URL=/d;/^AI_IMAGE_MODEL=/d;/^AI_IMAGE_DAILY_LIMIT=/d' "$ENV_FILE"
cat >> "$ENV_FILE" <<EOF
AI_IMAGE_KEY=$AIKEY
AI_IMAGE_BASE_URL=$AIBASE
AI_IMAGE_MODEL=$AIMODEL
AI_IMAGE_DAILY_LIMIT=$AILIMIT
EOF
chmod 600 "$ENV_FILE"
unset AIKEY

echo ""
echo "重启服务…"
systemctl restart sama-chat
sleep 3

if systemctl is-active sama-chat | grep -q active; then
  echo "✓ 服务已重启"
else
  echo "❌ 服务没起来：journalctl -u sama-chat -n 30 --no-pager"
  exit 1
fi

echo ""
echo "自检（未登录时应返回 401，说明接口已就绪）："
PORT=$(grep -oP '^PORT=\K.*' "$ENV_FILE" 2>/dev/null || echo 8719)
CODE=$(curl -s -o /dev/null -w "%{http_code}" -X POST "http://127.0.0.1:$PORT/mamashow/ai-generate")
if [[ "$CODE" == "401" ]]; then
  echo "✅ AI 生图接口已上线（/mamashow/ai-generate 返回 $CODE）"
else
  echo "⚠️ 接口返回 $CODE（预期 401），请检查服务日志"
fi

cat <<'EOF'

════════════════════════════════════════
配置完成！
════════════════════════════════════════
App 里「我 → mama秀 → AI 生成形象」就能用了。
默认每人每天 5 次；想调整次数就重跑本脚本。

EOF
