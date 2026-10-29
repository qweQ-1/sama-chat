import SwiftUI

struct RootView: View {

    @EnvironmentObject private var model: AppModel
    @State private var playing: GameVersion?
    @State private var showSettings = false
    @State private var showInspector = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if model.versions.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("还没有可玩的版本", systemImage: "exclamationmark.triangle")
                                .foregroundColor(.orange)
                            Text("内置客户端缺失时，可以在「设置 → 自定义客户端链接」里粘贴一个网页版客户端的地址，或者把客户端文件通过「文件」App 放进 JavaMC/Clients 目录。")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                    ForEach(model.versions) { version in
                        Button {
                            start(version)
                        } label: {
                            row(version)
                        }
                        .buttonStyle(.plain)
                        .disabled(!version.isPlayable)
                    }
                } header: {
                    Text("可玩版本 · \(model.versions.count)")
                } footer: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(model.serverStatus)
                            .font(.caption)
                            .foregroundColor(model.port > 0 ? .green : .secondary)
                        Text("内置 \(model.bundledCount) 个 · 用户导入 \(model.userCount) 个")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 6)
                }

                Section("说明") {
                    Text("这些客户端是「Java 版 Minecraft 的网页移植实现」，用 WebAssembly/JavaScript 运行，完全离线，不需要开启 JIT，也不依赖任何越狱环境。")
                        .font(.footnote)
                    Button {
                        model.rescan()
                    } label: {
                        Label("重新扫描客户端目录", systemImage: "arrow.clockwise")
                    }
                    Button {
                        showInspector = true
                    } label: {
                        Label("技术说明（为什么不能跑原生 JVM）", systemImage: "info.circle")
                    }
                }
            }
            .navigationTitle("JavaMC")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
        }
        .fullScreenCover(item: $playing) { version in
            GameView(version: version)
                .environmentObject(model)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environmentObject(model)
        }
        .sheet(isPresented: $showInspector) {
            InspectorView()
        }
    }

    private func start(_ version: GameVersion) {
        guard version.isPlayable else { return }
        if version.kind == .bundled && model.port == 0 {
            // 本地服务器还没就绪，等一会儿再进
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                playing = version
            }
            return
        }
        playing = version
    }

    private func row(_ version: GameVersion) -> some View {
        HStack(spacing: 12) {
            Text(version.badge)
                .font(.system(size: 26))
                .frame(width: 34)
            VStack(alignment: .leading, spacing: 3) {
                Text(version.title)
                    .font(.body)
                    .foregroundColor(.primary)
                Text(version.detail)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            Image(systemName: version.isPlayable ? "play.circle.fill" : "slash.circle")
                .font(.title2)
                .foregroundColor(version.isPlayable ? .accentColor : .secondary)
        }
        .padding(.vertical, 2)
    }
}
