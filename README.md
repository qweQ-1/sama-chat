# JavaMC —— iOS 上的 Java 版 Minecraft（不需要开启 JIT）

一个自带网页版 Minecraft 客户端的 iOS App：全屏、横屏、离屏可玩、支持切换版本。
附带一条 GitHub Actions 流水线，直接产出**未签名 IPA**，用 AltStore / SideStore / Sideloadly /
轻松签 / TrollStore 自签安装即可。

---

## 一、先说清楚技术边界（这部分不能含糊）

**「在 iOS 上直接跑原生 Java 虚拟机」这条路，不开 JIT 是走不通的。** 这不是实现难度问题，是系统限制：

| 事实 | 说明 |
|---|---|
| iOS 强制 W^X | 一块内存不能同时可写和可执行。任何 JVM 都要把字节码变成机器码写进内存再执行 —— 这正是 JIT。 |
| JIT 需要授权 | 非越狱设备上只有两种可能：① App 带 `com.apple.security.get-task-allow`（开发签名）并用调试器附加进程；② TrollStore / 越狱授予扩展 entitlement。 |
| 免费 Apple ID 自签 | 拿不到上面任何一种，所以自签的 PojavLauncher / Amethyst 必须靠 StikDebug 之类工具“开 JIT”才能玩。 |
| 纯解释器 JVM | OpenJDK Zero / JamVM 不写机器码，能在 iOS 上跑，但速度是 JIT 的百分之一量级 —— 能启动，不能玩。 |
| AOT 编译 MC 客户端 | GraalVM native-image 没有 `arm64-apple-ios` 目标，也不支持 LWJGL/OpenGL 栈，没有公开先例。 |

**本项目的做法：换一条绕开 W^X 的路。**

Minecraft Java 版的字节码**提前**（AOT）编译成 JavaScript / WebAssembly —— 这就是
[Eaglercraft](https://github.com/lax1dude/eaglercraft-1.5.2)（TeaVM 路线）在做的事。
运行时不再需要生成机器码，于是：

- App 本身**不需要任何 JIT 相关 entitlement**，你**不需要开 JIT**，不需要越狱，不需要 TrollStore；
- WebKit 的 JS/WASM 引擎跑在系统独立的 WebContent 进程里，那个进程自带系统级 JIT 授权 ——
  这一层是 iOS 平台自己给的，与我们是否“开启 JIT”无关；
- 代价是版本受限：能用的是社区已经移植好的版本（1.5.2 / 1.8.9 / 1.12.2 实验版）。

想玩**任意原版版本**，看第五节（远程串流）。

---

## 二、App 里有什么

- **版本列表**：内置 1.8.9 / 1.5.2 / 1.12.2 三个客户端，可再叠加自定义客户端链接和远程串流。
- **本地 HTTP 服务**：App 在 `127.0.0.1:47823`（端口固定，保证网页源稳定、存档不丢）跑一个只读静态服务，
  把 bundle 内的客户端用 `http://` 交给 WKWebView。
  为什么要这么做：直接 `loadFileURL` 是 `file://` 源，Web Worker、IndexedDB、fetch 都会受限，
  而 Eaglercraft 需要这些。
- **离线可玩**：客户端是自包含单文件（20~35MB），单人模式完全不需要网络。
- **存档持久化**：使用 WKWebView 默认数据存储，重启 App 后地图和设置还在。
- **全屏横屏**：隐藏状态栏、屏幕常亮、禁用手势缩放与长按菜单，触屏操作由客户端自己提供。
- **自定义客户端目录**：`文件` App → 我的 iPhone → JavaMC → Clients，
  放一个含 `index.html` 的子目录（或单个自包含 `.html`），App 自动扫描进版本列表。
  可选放 `version.json` 自定义标题与排序。
- **设置项**：直连服务器（`?server=wss://...`）、额外启动参数、远程串流地址、清除网页存档。

## 三、拿 IPA

流水线：`.github/workflows/unsigned-ipa.yml`

```
推送 main / 手动 workflow_dispatch
   → macos-26 runner + Xcode 26.6
   → xcodegen generate
   → xcodebuild archive（CODE_SIGNING_ALLOWED=NO）
   → 打包 Payload → uploads/JavaMC-unsigned.ipa
   → Actions Artifact 下载
```

安装（任选）：

1. **Sideloadly / AltStore / SideStore**：用你的免费 Apple ID 重签 → 装到设备（7 天有效，需重签）。
2. **轻松签 / i4Tools 等自签工具**：直接拖入 IPA。
3. **TrollStore**（仅支持存在 CoreTrust 漏洞的系统版本）：永久签名。

> 免费账号自签的 App **不需要**开 JIT —— 因为这个 App 压根没有需要 JIT 的东西。

## 四、本地开发

```sh
# 拉取客户端（仓库里不放二进制）
sh Tools/fetch_clients.sh

# 生成 Xcode 工程（需要 XcodeGen）
xcodegen generate

# 用 Xcode 打开、连真机跑
open JavaMC.xcodeproj
```

没有 XcodeGen 也行：直接把 `JavaMC/` 当源码目录，把 `Clients/` 作为 folder reference 加进工程即可。

## 五、想要“真正的”原版 Java 版（任意版本）

方案：**服务器跑客户端，网页串流到 iOS**。iOS 侧只是浏览器，跟 JIT 无关。

```sh
# 服务器（推荐带 GPU；纯 CPU 用软件渲染只能算能跑）
Xvfb :1 -screen 0 1280x720x24 &
DISPLAY=:1 LIBGL_ALWAYS_SOFTWARE=1 java -jar .../minecraft.jar
# 再挂 noVNC / Selkies / Sunshine 之类的网页串流
```

配好以后，在 App 的「设置 → 远程串流地址」里填网页地址，
版本列表里就会出现「远程串流（真 Java 版）」一项，点开即可玩。

权衡：版本完全自由，帧率取决于服务器（软件渲染大约 10~20 fps 量级，独显+硬件编码能到 60）。

## 五点半、如果你就是想要“真正的” Java 版（那必须开 JIT）

本 App 的定位是**不开 JIT 也能玩 Java 版**，代价是版本受限于社区移植。
如果你更想要原版任意版本，那绕不开 JIT，现成的路是：

- **Angel Aura Amethyst**（`AngelAuraMC/Amethyst-iOS`）—— PojavLauncher iOS 已停维（仓库 archived，2025-09），
  Amethyst 是官方指定的继承者，仍在维护。它内置 Azul Zulu JDK + GL4ES/MetalANGLE/MoltenVK，**必须 JIT**。
- JIT 怎么开（非越狱）：自签时带 `com.apple.security.get-task-allow`（开发签名本来就有），
  再用 **StikDebug**（`StikDebug/StikDebug`）附加调试器放开进程 —— 每次冷启动重开一次。
  官方矩阵里只有 TrollStore / 越狱是“完全不用外部设备”的。
- 免费 Apple ID 自签 7 天到期需重签；TrollStore / 越狱是永久签名。

本 App 不需要上面任何一步。

## 六、目录结构

```
JavaMC/
  App/JavaMCApp.swift          入口
  Model/AppModel.swift         状态、版本扫描、URL 组装
  Model/GameVersion.swift      版本模型
  Net/LocalHTTPServer.swift    127.0.0.1 只读静态服务（NWListener，手写）
  Views/RootView.swift         版本列表
  Views/GameView.swift         全屏游戏容器
  Views/WebViewContainer.swift WKWebView 包装
  Views/SettingsView.swift     设置
  Views/InspectorView.swift    技术说明（为什么不能跑原生 JVM）
  Assets.xcassets              App 图标（脚本生成）
Clients/                       随包客户端（index.html + version.json）
Tools/fetch_clients.sh         拉客户端
Tools/make_icon.py             生成 1024 图标（纯标准库 PNG 编码）
Tools/sync_clients.sh          把本地已下载的客户端同步进仓库目录
```

## 七、已知限制

- 版本受限于社区已有的 AOT 移植（1.5.2 / 1.8.9 / 1.12.2），不是任意版本。
- 联网多人游戏要连 `wss://` 的 Eaglercraft 服务器，原版 Java 服务器**不能**直连
  （协议是 TCP，浏览器只有 WebSocket）—— 需要服务器侧加 WebSocket 网桥。
- 手机端 WASM 内存与 WebKit 单页内存有上限，视野拉太大会崩，建议 4~8 chunk。
- 内置客户端是 Minecraft 衍生资源，仅限自用；公开发布请自行评估法律风险。

## 八、客户端来源

| 版本 | 来源 |
|---|---|
| EaglercraftX 1.8.9 | `3kh0/eaglercraft-builds` → `EaglercraftX_1.8_Offline_International.html` |
| Eaglercraft 1.5.2 | `3kh0/eaglercraft-builds` → `Eaglercraft_1.5_Offline_Download.html` |
| Eaglercraft 1.12.2 | `JessePinkman27/eaglercraft-1.12.2` → `offline_download/wasm/...`（社区移植，实验） |

Eaglercraft 本体来自 `lax1dude`（1.5.2 / 1.8 作者）。以上镜像均为第三方托管，
构建日志里会打印每个文件的 sha256，可自行核对。
