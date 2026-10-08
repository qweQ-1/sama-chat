#!/usr/bin/env bash
# ============================================================================
# sama-chat 一键迁移：Windows 电脑 + ngrok隧道  →  Ubuntu 公网服务器直连
# 用法：sudo bash migrate-to-server.sh [选项]
#
# 选项：
#   --data /path           旧服务器 data 目录（db.json + uploads/）
#   --config /path.json    旧服务器 config.json（SMTP 邮箱配置，登录注册必需）
#   --port 8719            Node 内部端口（nginx 反代时用；默认 8719）
#   --nginx                启用 nginx 反代：Node 只听 127.0.0.1，nginx 对外 80
#                          → App 填纯 IPv4 地址：http://你的IP（不带端口）
#   --secret XXXXXX        自定义 JWT 密钥（不给则自动随机生成）
#
# 不带 --nginx：Node 直接对外，App 地址为 http://你的IP:端口
# ============================================================================
set -euo pipefail

PORT=8719
DATA=""
CONFIG=""
SECRET=""
USE_NGINX=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --data) DATA="$2"; shift 2 ;;
    --config) CONFIG="$2"; shift 2 ;;
    --port) PORT="$2"; shift 2 ;;
    --secret) SECRET="$2"; shift 2 ;;
    --nginx) USE_NGINX=1; shift ;;
    -h|--help) sed -n '2,18p' "$0"; exit 0 ;;
    *) echo "未知参数: $1"; exit 1 ;;
  esac
done

[[ $EUID -eq 0 ]] || { echo "请用 sudo 运行"; exit 1; }

APP_DIR=/opt/sama-chat
SVC_USER=sama-chat
[[ -z "$SECRET" ]] && SECRET="sk-$(openssl rand -hex 24)"

echo "──── 1/9 安装 Node 20 ────"
if ! command -v node >/dev/null || [[ $(node -v | cut -d. -f1 | tr -d v) -lt 20 ]]; then
  curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
  apt-get install -y nodejs
fi
node -v && echo "✓ $(node -v)"

echo "──── 2/9 部署代码 ────"
curl -sL --max-time 90 "https://codeload.github.com/qweQ-1/sama-chat/tar.gz/refs/heads/main" -o /tmp/sama.tgz \
  || { echo "❌ 代码下载失败，检查服务器网络"; exit 1; }
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR"
tar xzf /tmp/sama.tgz --strip-components=1 -C "$APP_DIR" \
  || { echo "❌ 解压失败，/tmp/sama.tgz 可能不完整"; exit 1; }
cd "$APP_DIR/server"

echo "──── 3/9 创建独立运行用户（不用 root 跑服务）────"
id -u "$SVC_USER" >/dev/null 2>&1 || useradd -r -d "$APP_DIR" -s /usr/sbin/nologin "$SVC_USER"
chown -R "$SVC_USER:$SVC_USER" "$APP_DIR"
su -s /bin/bash "$SVC_USER" -c "cd $APP_DIR/server && npm ci --omit=dev 2>/dev/null || npm install --omit=dev" \
  || { echo "❌ 依赖安装失败（检查网络/磁盘）"; exit 1; }
echo "✓ 依赖安装完成"

echo "──── 4/9 写配置 ────"
if [[ $USE_NGINX -eq 1 ]]; then
  BIND_HOST=127.0.0.1   # Node 只让本机访问，对外全走 nginx
else
  BIND_HOST=0.0.0.0
fi
cat > "$APP_DIR/server/.env" <<EOF
PORT=$PORT
HOST=$BIND_HOST
JWT_SECRET=$SECRET
UPLOAD_DIR=$APP_DIR/server/uploads
DATA_DIR=$APP_DIR/server/data
EOF
chown "$SVC_USER:$SVC_USER" "$APP_DIR/server/.env"
echo "✓ Node 监听 $BIND_HOST:$PORT"

if [[ -n "$CONFIG" && -f "$CONFIG" ]]; then
  cp "$CONFIG" "$APP_DIR/server/config.json"
  chown "$SVC_USER:$SVC_USER" "$APP_DIR/server/config.json"
  echo "✓ config.json 已带过来（163 邮箱验证码可用）"
else
  echo "⚠️ 没传 config.json —— 邮箱验证码功能不可用（老账号密码登录不受影响）"
fi

echo "──── 5/9 迁移数据 ────"
mkdir -p "$APP_DIR/server/data" "$APP_DIR/server/uploads"
if [[ -n "$DATA" && -d "$DATA" ]]; then
  if [[ -f "$DATA/db.json" ]]; then
    cp "$DATA/db.json" "$APP_DIR/server/data/db.json"
    echo "✓ db.json（账号/消息/好友/投票）"
  else
    echo "⚠️ $DATA 下没找到 db.json"
  fi
  # uploads 可能在 data 里面，也可能是同级目录（看旧服务器当初怎么起的）
  UP_SRC=""
  [[ -d "$DATA/uploads" ]] && UP_SRC="$DATA/uploads"
  [[ -z "$UP_SRC" && -d "$(dirname "$DATA")/uploads" ]] && UP_SRC="$(dirname "$DATA")/uploads"
  if [[ -n "$UP_SRC" ]]; then
    cp -r "$UP_SRC/." "$APP_DIR/server/uploads/"
    N=$(find "$APP_DIR/server/uploads" -type f | wc -l)
    echo "✓ uploads/：$N 个历史文件（图片/视频/语音）← $UP_SRC"
  else
    echo "⚠️ 没找到 uploads/ —— 历史图片会变裂图！检查传输路径"
  fi
else
  echo "⚠️ 未提供数据目录 —— 全新数据库，所有人需要重新注册"
fi
chown -R "$SVC_USER:$SVC_USER" "$APP_DIR/server/data" "$APP_DIR/server/uploads"

echo "──── 6/9 systemd 服务 ────"
cat > /etc/systemd/system/sama-chat.service <<EOF
[Unit]
Description=sama-chat backend
After=network.target

[Service]
Type=simple
User=$SVC_USER
Group=$SVC_USER
WorkingDirectory=$APP_DIR/server
ExecStart=/usr/bin/node src/index.js
EnvironmentFile=$APP_DIR/server/.env
Restart=always
RestartSec=3
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable --now sama-chat >/dev/null 2>&1
sleep 2
systemctl is-active sama-chat | grep -q active && echo "✓ 服务已启动" || { echo "❌ 启动失败，看日志：journalctl -u sama-chat -n 40"; exit 1; }

echo "──── 7/9 防火墙 ────"
if command -v ufw >/dev/null; then
  ufw allow 22/tcp >/dev/null
  if [[ $USE_NGINX -eq 1 ]]; then
    ufw allow 80/tcp >/dev/null
  else
    ufw allow $PORT/tcp >/dev/null
  fi
  ufw --force enable >/dev/null
  echo "✓ 防火墙规则：$(ufw status | grep -c ALLOW || true) 条放行"
else
  echo "⚠️ 无 ufw，请去云控制台放行对应端口"
fi

echo "──── 8/9 自动备份 ────"
cat > "$APP_DIR/backup.sh" <<EOF
#!/usr/bin/env bash
K=$APP_DIR/backups; D=$APP_DIR/server/data
mkdir -p "\$K"; ts=\$(date +%F_%H%M)
cp "\$D/db.json" "\$K/db_\$ts.json"
tar czf "\$K/uploads_\$ts.tgz" -C "$APP_DIR/server" uploads
ls -t "\$K" | tail -n +31 | xargs -r -I{} rm -f "\$K/{}"
EOF
chmod +x "$APP_DIR/backup.sh"
apt-get install -y cron >/dev/null 2>&1 || true
(crontab -l 2>/dev/null; echo "30 3 * * * $APP_DIR/backup.sh") | sort -u | crontab -
echo "✓ 每日 3:30 备份到 $APP_DIR/backups"

echo "──── 9/9 nginx 反代 ────"
if [[ $USE_NGINX -eq 1 ]]; then
  apt-get install -y nginx >/dev/null 2>&1
  cat > /etc/nginx/sites-available/sama-chat <<EOF
server {
    listen 80;
    server_name _;
    client_max_body_size 60m;          # 允许大文件/视频上传

    location / {
        proxy_pass         http://127.0.0.1:$PORT;
        proxy_http_version 1.1;

        # WebSocket 必需（实时消息就靠它）
        proxy_set_header   Upgrade \$http_upgrade;
        proxy_set_header   Connection "upgrade";
        proxy_set_header   Host \$host;
        proxy_set_header   X-Real-IP \$remote_addr;
        proxy_set_header   X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header   X-Forwarded-Proto \$scheme;
        proxy_read_timeout 86400;
        proxy_buffering    off;
    }
}
EOF
  rm -f /etc/nginx/sites-enabled/default
  ln -sf /etc/nginx/sites-available/sama-chat /etc/nginx/sites-enabled/
  if nginx -t 2>/dev/null; then
    systemctl reload nginx && echo "✓ nginx 已反代到 127.0.0.1:$PORT"
  else
    echo "⚠️ nginx 配置测试失败，手动看：nginx -t"
  fi
fi

# ---------------- 自检 + 输出 ----------------
sleep 1
curl -sf "http://127.0.0.1:$PORT/health" >/dev/null || { echo "❌ 本地健康检查失败：journalctl -u sama-chat -n 40"; exit 1; }
PUBIP=$(curl -s --max-time 10 https://api.ipify.org || hostname -I | awk '{print $1}')
echo ""
echo "════════════════════════════════════════"
if [[ $USE_NGINX -eq 1 ]]; then
  APP_URL="http://$PUBIP"
  echo "✅ 迁移完成（纯 IPv4 直连，无端口）"
else
  APP_URL="http://$PUBIP:$PORT"
  echo "✅ 迁移完成（IP + 端口直连）"
fi
cat <<EOF
════════════════════════════════════════

  📱 App 里这样填（我 → 服务器设置）：
       $APP_URL

  🔧 常用命令：
       systemctl restart sama-chat    重启服务
       journalctl -u sama-chat -f     看日志
       $APP_DIR/backup.sh             立即备份

  💾 数据位置：$APP_DIR/server/data/db.json
     自动备份：每日 3:30 → $APP_DIR/backups
EOF
