#!/usr/bin/env bash
# ============================================================================
# sama-chat 域名 + HTTPS 一键配置
# 前提：① 域名 A 记录已指向本服务器公网 IP ② Lightsail 防火墙已放行 443
# 用法：sudo bash setup-domain.sh chat.example.com
# 效果：https://域名 正式可用（证书自动续期），旧的 http://IP 过渡期继续能用
# ============================================================================
set -euo pipefail

[[ $EUID -eq 0 ]] || { echo "请用 sudo 运行"; exit 1; }
DOMAIN="${1:?用法: sudo bash setup-domain.sh 你的域名}"
PORT="${SAMA_PORT:-8719}"
[[ -f /etc/nginx/sites-available/sama-chat ]] || { echo "❌ 没找到 nginx 配置，先跑 migrate-to-server.sh"; exit 1; }

echo "──── 0/4 检查域名解析 ────"
MYIP=$(curl -s --max-time 10 https://api.ipify.org || hostname -I | awk '{print $1}')
RESOLVED=$(getent hosts "$DOMAIN" | awk '{print $1}' | head -1)
if [[ -z "$RESOLVED" ]]; then
  echo "❌ $DOMAIN 还没有解析记录（或未生效）"
  echo "   去域名注册商后台添加：类型 A / 主机记录 @ / 记录值 $MYIP"
  echo "   加完等 5~10 分钟再跑本脚本"
  exit 1
fi
if [[ "$RESOLVED" != "$MYIP" ]]; then
  echo "⚠️ $DOMAIN 解析到 $RESOLVED，不是本机 $MYIP —— 刚改的？等几分钟再跑"
  echo "   （继续跑也行，但申请证书大概率失败）"
  read -p "仍要继续吗？(y/N) " ans
  [[ "$ans" == "y" || "$ans" == "Y" ]] || exit 1
fi
echo "✓ $DOMAIN → $MYIP"

echo "──── 1/4 备份当前 nginx 配置 ────"
BAK="/etc/nginx/sites-available/sama-chat.bak.$(date +%s)"
cp /etc/nginx/sites-available/sama-chat "$BAK"
echo "✓ 备份到 $BAK"

echo "──── 2/4 写入「域名 + IP」双入口配置 ────"
# 域名 block：certbot 稍后自动升级成 HTTPS + 跳转
# IP block：保持原样可用，过渡期老地址不断
cat > /etc/nginx/sites-available/sama-chat <<EOF
# ---- 域名入口（certbot 会自动加 443 和 HTTP→HTTPS 跳转）----
server {
    listen 80;
    server_name $DOMAIN;
    client_max_body_size 60m;

    location / {
        proxy_pass http://127.0.0.1:$PORT;
        proxy_http_version 1.1;

        # WebSocket 必需（实时消息）
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_read_timeout 86400;
        proxy_buffering off;
    }
}

# ---- IP 直连入口（过渡期保险；所有人改用域名后可删）----
server {
    listen 80 default_server;
    server_name _;
    client_max_body_size 60m;

    location / {
        proxy_pass http://127.0.0.1:$PORT;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_read_timeout 86400;
        proxy_buffering off;
    }
}
EOF
nginx -t && systemctl reload nginx
echo "✓ 双入口生效：域名(待HTTPS) + IP(原样)"

echo "──── 3/4 申请 Let's Encrypt 证书（免费，90天自动续期）────"
apt-get update -qq >/dev/null 2>&1 || true
apt-get install -y certbot python3-certbot-nginx >/dev/null
certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos --register-unsafely-without-email

echo "──── 4/4 验证 ────"
sleep 2
if curl -sf --max-time 15 "https://$DOMAIN/health" >/dev/null; then
  curl -s "https://$DOMAIN/health"; echo
  echo ""
  echo "✅ HTTPS 已生效！"
  echo ""
  echo "════════════════════════════════════════"
  echo "  📱 App 填：https://$DOMAIN"
  echo "════════════════════════════════════════"
  echo "  · 旧地址 http://$MYIP 过渡期继续可用"
  echo "  · 证书 90 天有效，已装自动续期，无需管理"
  echo "  · 通知朋友们逐个改成新地址即可，不着急"
else
  echo "⚠️ HTTPS 还没通，按顺序查："
  echo "   ① Lightsail 控制台 → Networking → 防火墙放行 TCP 443"
  echo "   ② 上方证书申请是否报错（最常见是 443 不通）"
  echo "   ③ 手动看证书状态：certbot certificates"
fi
