import SwiftUI

/// 技术说明页：把“为什么 iOS 上不能直接跑原生 Java 版”讲清楚，
/// 也顺手把几条可行路线写明白，避免以后自己再踩一遍。
struct InspectorView: View {

    @Environment(\.dismiss) private var dismiss

    private let sections: [(String, String)] = [
        ("iOS 禁止“可写 + 可执行”内存",
         "任何原生 Java 虚拟机（HotSpot / ART / Zero）都要把字节码编译成机器码再执行。iOS 对非越狱设备强制 W^X：一块内存不能同时可写和可执行，除非 App 拿到 JIT 授权（com.apple.security.cs.allow-jit / dynamic-codesigning，或调试器附加时的 get-task-allow）。免费 Apple ID 自签的 App 拿不到这些授权，所以“无需开启 JIT 的原生 JVM”这条路在 iOS 上不存在。"),

        ("解释器 JVM 能跑，但跑不动 Minecraft",
         "OpenJDK Zero、JamVM 这类纯解释器不写机器码，技术上能在 iOS 上运行，但速度通常是 JIT 的百分之一量级。Minecraft 1.13+ 还要 Java 17 运行时。结论：能启动，不能玩。"),

        ("所以走“把 Java 提前编译成 JS/WASM”这条路",
         "Eaglercraft 用 TeaVM 把 Minecraft Java 版的字节码提前编译成 JavaScript/WebAssembly，AOT 完成，运行时不需要生成机器码 —— 正好绕开 W^X 限制。WebKit 的 JS/WASM 引擎跑在独立的 WebContent 进程里，那个进程自带系统级 JIT 授权，所以本 App 不需要任何 JIT entitlement，你也不需要做任何额外操作。"),

        ("存档与联网",
         "内置客户端完全是本地网页，单人模式离线可玩。存档写进 App 的 WebView 数据区（localStorage / IndexedDB）。多人游戏需要客户端连接 wss:// 开头的服务器；本 App 只在“自定义客户端链接”和“远程串流”模式下才需要联网权限。"),

        ("想要“真正的”原版 Java 版怎么办",
         "两条路：① 服务器上跑原版服务端（任意版本都能跑），客户端用 Eaglercraft 连（协议限制在 1.5.2 / 1.8 附近）；② 服务器上跑原版客户端 + Xvfb 软件渲染（Mesa llvmpipe），用 noVNC / Selkies 这类网页串流到 iOS —— 版本完全自由，代价是分辨率与帧率取决于服务器。设置里填好串流地址即可。"),

        ("想加自己的客户端",
         "「文件」App → 我的 iPhone → JavaMC → Clients：放一个含 index.html 的子目录，或直接放一个自包含的 .html。可选放 version.json 自定义标题与排序：\n{\"title\":\"我的 1.20\",\"minecraft\":\"1.20\",\"order\":10,\"badge\":\"🟩\"}")
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(Array(sections.enumerated()), id: \.offset) { pair in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(pair.element.0)
                                .font(.headline)
                            Text(pair.element.1)
                                .font(.footnote)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("技术说明")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}
