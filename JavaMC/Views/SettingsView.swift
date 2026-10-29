import SwiftUI
import WebKit
import UIKit

struct SettingsView: View {

    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var newURL: String = ""
    @State private var cleared = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(model.diagnostics())
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                    Button {
                        model.rescan()
                    } label: {
                        Label("重新扫描客户端目录", systemImage: "arrow.clockwise")
                    }
                } header: {
                    Text("本地服务诊断")
                } footer: {
                    Text("App 在 127.0.0.1 上跑一个只读静态服务，把内置/导入的网页客户端用 http:// 交给 WebView（网页源要比 file:// 稳定，Worker 和存档才能正常工作）。")
                }

                Section {
                    ForEach(Array(model.customURLs.enumerated()), id: \.offset) { pair in
                        Text(pair.element)
                            .font(.caption)
                            .lineLimit(2)
                    }
                    .onDelete { indexSet in
                        for index in indexSet.sorted(by: >) {
                            model.removeCustomURL(at: index)
                        }
                    }
                    HStack {
                        TextField("https://.../index.html", text: $newURL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                        Button("添加") {
                            model.addCustomURL(newURL)
                            newURL = ""
                        }
                        .disabled(newURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                } header: {
                    Text("自定义客户端链接")
                } footer: {
                    Text("左滑删除。任意网页版 Minecraft 客户端地址都可以，App 只负责用一个全屏 WebView 打开它（记得给 App 联网权限；离线内置客户端则完全不需要联网）。")
                }

                Section {
                    TextField("wss://你的服务器地址", text: $model.directServer)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                } header: {
                    Text("启动时直连多人服务器")
                } footer: {
                    Text("填写后会以 ?server= 参数传给内置客户端，进入游戏直接连这个服务器。Eaglercraft 的服务器地址必须以 wss:// 开头。")
                }

                Section {
                    TextField("例如 renderDistance=4&fps=60", text: $model.extraQuery)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("额外启动参数")
                } footer: {
                    Text("不想加就留空。不同客户端支持的参数不一样，写错了客户端通常会忽略。")
                }

                Section {
                    TextField("http://192.168.1.10:6080/vnc.html", text: $model.streamURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    TextField("用户名（可选）", text: $model.streamUser)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("密码（可选）", text: $model.streamPassword)
                } header: {
                    Text("远程串流地址（真 Java 版）")
                } footer: {
                    Text("把真正的 Java 版 Minecraft 跑在服务器上（Xvfb + 软件渲染或独显），再用 noVNC / WebRTC 网页串到手机。填了地址后，版本列表里会多出「远程串流」一项，可玩任意原版版本。\n如果页面开了 HTTP 基本认证，把用户名密码填在这里——WKWebView 自己不会弹认证框。")
                }

                Section {
                    Button(role: .destructive) {
                        clearWebsiteData()
                    } label: {
                        Label(cleared ? "已清除网页数据" : "清除网页存档与缓存", systemImage: "trash")
                    }
                } footer: {
                    Text("会清掉所有内置客户端在 WebView 里的存档、设置与缓存（相当于恢复出厂）。")
                }
            }
            .navigationTitle("设置")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    private func clearWebsiteData() {
        let store = WKWebsiteDataStore.default()
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        store.removeData(ofTypes: types, modifiedSince: Date(timeIntervalSince1970: 0)) {
            DispatchQueue.main.async {
                cleared = true
            }
        }
    }
}
