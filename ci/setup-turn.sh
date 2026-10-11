#!/usr/bin/env bash
# ============================================================================
# sama-chat TURN 服务器一键安装（语音通话跨网络中转）
# 前提：Lightsail 防火墙需要放行 UDP/TCP 3478 + UDP 49152-65535
# 用法：sudo bash setup-turn.sh [服务器公网IP]
# 效果：/ice 接口自动返回 TURN 配置，App 无需更新
# ============================================================================
set -euo pipefail

[[ $EUID -eq 0 ]] || { echo "请用 sudo 运行"; exit 1; }

PUBIP="${1:-$(curl -s --max-time 10 https://api.ipify.org || hostname -I | awk '{print $1}')}"
[[ -n "$PUBIP" ]] || { echo "无法确定公网 IP，请手动传入：sudo bash setup-turn.sh 1.2.3.4"; exit 1; }

TURN_USER="sama"
TURN_PASS="$(openssl rand -hex 16)"
ENV_FILE=/opt/sama-chat/server/.env
[[ -f "$ENV_FILE" ]] || { echo "❌ 找不到 $ENV_FILE，先确认 sama-chat 部署在 /opt/sama-chat"; exit 1; }

echo "──── 1/4 安装 coturn ────"
apt-get update -qq >/dev/null 2>&1 || true
apt-get install -y coturn >/dev/null

echo "──── 2/4 配置 ────"
# 打开 TURN 服务开关
sed -i 's/^#*TURNSERVER_ENABLED=.*/TURNSERVER_ENABLED=1/' /etc/default/coturn 2>/dev/null || \
  echo 'TURNSERVER_ENABLED=1' >> /etc/default/coturn

cat > /etc/turnserver.conf <<EOF
# sama-chat TURN —— 语音通话 NAT 穿透兜底
listening-port=3478
fingerprint
lt-cred-mech
user=$TURN_USER:$TURN_PASS
realm=samachat
external-ip=$PUBIP
min-port=49152
max-port=65535
no-multicast-peers
# 不做中继给非认证用户
no-cli
EOF

echo "──── 3/4 启动服务 ────"
systemctl enable coturn >/dev/null 2>&1 || true
systemctl restart coturn
sleep 2
systemctl is-active coturn | grep -q active && echo "✓ coturn 运行中" || {
  echo "❌ coturn 启动失败：journalctl -u coturn -n 30"; exit 1;
}

echo "──── 4/4 写入 sama-chat 环境 + 防火墙 ────"
# 幂等：先删旧的 TURN 行再加
sed -i '/^TURN_URL=/d;/^TURN_USER=/d;/^TURN_PASS=/d' "$ENV_FILE"
cat >> "$ENV_FILE" <<EOF
TURN_URL=turn:$PUBIP:3478?transport=udp,turn:$PUBIP:3478?transport=tcp
TURN_USER=$TURN_USER
TURN_PASS=$TURN_PASS
EOF

if command -v ufw >/dev/null; then
  ufw allow 3478/tcp >/dev/null 2>&1 || true
  ufw allow 3478/udp >/dev/null 2>&1 || true
  ufw allow 49152:65535/udp >/dev/null 2>&1 || true
  echo "✓ ufw 已放行 3478 + 中继端口段"
fi

systemctl restart sama-chat
sleep 2
curl -sf http://127.0.0.1:8719/health >/dev/null && echo "✓ sama-chat 已重启并接线 TURN"

cat <<EOF

════════════════════════════════════════
✅ TURN 中转已就绪！
════════════════════════════════════════

⚠️ 最后一步（手动）：AWS Lightsail 控制台 → 你的实例 → Networking → Firewall 添加：
   ① UDP 3478
   ② TCP 3478
   ③ UDP 49152-65535

（Lightsail 控制台那层脚本改不了，必须在网页上加）

之后双方都是对称 NAT/严格网络时也能通话了。App 端无需任何更新。
EOF
