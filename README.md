# sama-chat 萨摩聊天

轻量实时聊天应用：**私聊 · 群聊 · 炫圈（朋友圈）· 面对面扫码加好友**。

| 部分 | 技术 | 说明 |
|---|---|---|
| 服务端 `server/` | Node.js + Fastify + WebSocket | 账号、好友、私聊/群聊、炫圈、图片上传 |
| 客户端 `app/` | Flutter（一套代码双端） | iOS（→ IPA）+ Android（→ APK） |
| 构建 `.github/workflows/ci.yml` | GitHub Actions | 自动跑测试并产出 APK / 未签名 IPA |

## 功能

- **私聊**：一对一消息、输入中提示、已读回执、图片消息
- **群聊**：建群、多成员实时收发（含发送者昵称/头像）
- **实时传输**：WebSocket 推送，消息即刻送达所有在线成员
- **面对面加人**：生成个人二维码 / 扫一扫 → 直接加好友
- **炫圈**：发布图文动态（最多 9 图）、点赞、评论，仅好友可见

## 快速开始

### 1. 跑服务端

```bash
cd server
npm install
npm start          # 默认 http://127.0.0.1:8080
```

生产部署见 [server/README.md](server/README.md)（Docker / Fly.io / Railway）。

### 2. 跑客户端

```bash
cd app
flutter create --platforms=android,ios --org com.qweq1 --project-name samachat .   # 生成平台目录
flutter pub get
flutter run --dart-define=SAMA_SERVER=http://你的服务器:8080
```

App 内「我 → 服务器设置」也可以改服务器地址。

### 3. 构建产物（CI）

推送后 GitHub Actions 自动构建，在 Actions 页面下载：

- `sama-chat-apk` → Android 安装包（直接装）
- `sama-chat-ipa` → iOS 未签名 IPA（用 AltStore / Sideloadly / 轻松签等自签安装）

## 测试

```bash
# 服务端（需要先启动服务）
cd server && node test-e2e.mjs      # 45+ 端到端断言

# 客户端
cd app && flutter test
```

## 结构

```
sama-chat/
├── server/               # Node.js 后端
│   ├── src/index.js      #   入口 / CORS / 鉴权
│   ├── src/auth.js       #   注册 / 登录 / JWT
│   ├── src/routes.js     #   好友·会话·消息·炫圈·上传
│   ├── src/realtime.js   #   WebSocket 实时层
│   ├── src/store.js      #   JSON 数据库
│   └── test-e2e.mjs      #   端到端测试
├── app/                  # Flutter 客户端
│   ├── lib/api.dart      #   REST 客户端
│   ├── lib/realtime.dart #   WebSocket 客户端
│   ├── lib/store.dart    #   全局状态
│   ├── lib/screens/      #   登录/消息/聊天/通讯录/二维码/炫圈/我的
│   └── test/             #   单元 + 组件测试
├── ci/                   # 构建脚本（CI 使用）
└── .github/workflows/    # GitHub Actions
```
