# sama-chat 服务端部署

单进程 Node.js 服务：REST API + WebSocket 同端口（默认 8080）。
数据存 JSON 文件（`DATA_DIR`），图片存 `UPLOAD_DIR` —— 部署时挂一个持久卷即可。

## 方式 A：Fly.io（推荐，免费额度够用）

1. 安装 flyctl：https://fly.io/docs/flyctl/install/
2. 登录并创建应用：

```bash
cd server
fly launch --copy-config --name sama-chat-你的名字   # 使用仓库里的 fly.toml
fly volumes create sama_data --size 1               # 1GB 持久卷
fly deploy
```

3. 地址形如 `https://sama-chat-你的名字.fly.dev` —— 填进 App 的「服务器设置」。

## 方式 B：Railway

1. 打开 https://railway.app → New Project → Deploy from GitHub repo → 选 `sama-chat`
2. 设置 Root Directory 为 `server`（它会自动识别 Dockerfile）
3. 添加 Volume 挂载到 `/app/data`
4. Settings → Networking → Generate Domain

## 方式 C：自己有服务器（Docker）

```bash
cd server
docker build -t sama-chat-server .
docker run -d \
  -p 8080:8080 \
  -v /srv/sama-chat-data:/app/data \
  -e JWT_SECRET=$(openssl rand -hex 32) \
  --restart unless-stopped \
  sama-chat-server
```

建议前面挂 Nginx/Caddy 做 HTTPS（WebSocket 需要 `proxy_set_header Upgrade/Connection`）。

## 环境变量

| 变量 | 默认 | 说明 |
|---|---|---|
| `PORT` | 8080 | 监听端口 |
| `DATA_DIR` | `./data` | JSON 数据库目录 |
| `UPLOAD_DIR` | `./data/uploads` | 图片目录 |
| `JWT_SECRET` | 开发默认值 | **生产必须设置** |
| `LOG_LEVEL` | info | 日志等级 |

## 健康检查

`GET /health` → `{"status":"ok", ...}`

## 验证

```bash
node test-e2e.mjs   # 需要服务已在 127.0.0.1:8080 运行
```
