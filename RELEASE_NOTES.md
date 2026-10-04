# 萨摩聊天 v1.0.0

首个版本发布 🎉

## 功能

- 💬 **私聊** — 一对一实时消息、输入中提示、已读回执、图片消息
- 👥 **群聊** — 创建群聊、多成员实时收发
- ⚡ **实时传输** — WebSocket 即时推送，消息秒达
- 📷 **面对面加人** — 扫二维码直接加好友
- 🌈 **炫圈** — 发布图文动态（最多 9 图）、点赞、评论，仅好友可见
- 👤 头像 / 昵称修改、好友搜索、深色模式

## 安装

| 平台 | 文件 | 说明 |
|---|---|---|
| Android | `SamaChat-1.0.0.apk` | 下载后直接安装 |
| iOS | `SamaChat-1.0.0-unsigned.ipa` | 未签名版本，需用 AltStore / Sideloadly / 轻松签 等工具自签安装 |

## ⚠️ 注意

- 应用需要连接 **自建服务器** 才能使用。部署后端后（见仓库 `server/README.md`，
  支持 Fly.io / Railway / Docker 一键部署），在登录页或「我 → 服务器设置」填入服务器地址即可。
- iOS 未签名版本 7 天后可能需重新签名（iOS 自签机制限制）。

## 技术栈

- 客户端：Flutter（iOS + Android 一套代码）
- 服务端：Node.js + Fastify + WebSocket
- CI/CD：GitHub Actions（测试 → APK → 未签名 IPA → Release 自动发布）
