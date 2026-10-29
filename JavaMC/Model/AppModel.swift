import Foundation
import Combine
import SwiftUI

/// 全局状态：本地服务器、可玩版本列表、用户设置。
final class AppModel: ObservableObject {

    static let shared = AppModel()

    @Published private(set) var versions: [GameVersion] = []
    @Published private(set) var port: UInt16 = 0
    @Published private(set) var serverStatus: String = "未启动"
    @Published private(set) var customURLs: [String] = []
    @Published private(set) var bundledCount: Int = 0
    @Published private(set) var userCount: Int = 0

    /// 直连服务器（wss:// 地址），非空时会作为 URL 参数传给客户端
    @Published var directServer: String = "" {
        didSet { defaults.set(directServer, forKey: Keys.directServer) }
    }
    /// 追加到 URL 的自定义参数，例如 renderDistance=4&fps=60
    @Published var extraQuery: String = "" {
        didSet { defaults.set(extraQuery, forKey: Keys.extraQuery) }
    }
    /// 远程串流地址（noVNC / WebRTC 网页），用于跑“真正的” Java 版
    @Published var streamURL: String = "" {
        didSet { defaults.set(streamURL, forKey: Keys.streamURL) }
    }

    private enum Keys {
        static let directServer = "directServer"
        static let extraQuery = "extraQuery"
        static let streamURL = "streamURL"
        static let customURLs = "customURLs"
    }

    private let defaults = UserDefaults.standard
    private var server: LocalHTTPServer?
    private var rootDirs: [URL] = []
    private var booted = false

    private init() {
        directServer = defaults.string(forKey: Keys.directServer) ?? ""
        extraQuery = defaults.string(forKey: Keys.extraQuery) ?? ""
        streamURL = defaults.string(forKey: Keys.streamURL) ?? ""
        if let raw = defaults.array(forKey: Keys.customURLs) as? [String] {
            customURLs = raw
        }
    }

    // MARK: - 目录

    /// 用户可写的客户端目录：通过「文件」App → 我的 iPhone → JavaMC → Clients 放进去
    var documentsClientsDir: URL {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Clients", isDirectory: true)
    }

    /// App 内置客户端目录
    var bundledClientsDir: URL? {
        guard let res = Bundle.main.resourceURL else { return nil }
        let url = res.appendingPathComponent("Clients", isDirectory: true)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    // MARK: - 启动

    func boot() {
        guard !booted else { return }
        booted = true

        try? FileManager.default.createDirectory(at: documentsClientsDir, withIntermediateDirectories: true)

        var roots: [URL] = [documentsClientsDir]
        if let bundled = bundledClientsDir {
            roots.append(bundled)
        }
        rootDirs = roots

        // 首次启动时放一份说明文件，方便用户知道怎么加版本
        writeReadmeIfNeeded()

        let localServer = LocalHTTPServer(roots: roots)
        localServer.onReady = { [weak self] readyPort in
            DispatchQueue.main.async {
                self?.port = readyPort
                self?.serverStatus = "运行中 · 127.0.0.1:\(readyPort)"
            }
        }
        localServer.onFailure = { [weak self] message in
            DispatchQueue.main.async {
                self?.serverStatus = "启动失败：\(message)"
            }
        }
        server = localServer
        localServer.start()

        scanVersions()
    }

    func rescan() {
        scanVersions()
    }

    // MARK: - 扫描版本

    private func scanVersions() {
        var collected: [GameVersion] = []
        var seen = Set<String>()
        var userAdded = 0
        var bundledAdded = 0

        let ordered: [(URL, Bool)] = {
            var list: [(URL, Bool)] = []
            if let bundled = bundledClientsDir { list.append((bundled, false)) }
            list.append((documentsClientsDir, true))
            return list
        }()

        for (root, isUser) in ordered {
            guard let items = try? FileManager.default.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            for item in items.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                let name = item.lastPathComponent
                if name.hasPrefix(".") || name == "README.txt" { continue }

                var isDir: ObjCBool = false
                guard FileManager.default.fileExists(atPath: item.path, isDirectory: &isDir) else { continue }

                var entryPath = ""
                var titled = name
                var engine = "Eaglercraft"
                var minecraft = ""
                var order = 100
                var badge = "🟩"

                if isDir.boolValue {
                    let index = item.appendingPathComponent("index.html")
                    guard FileManager.default.fileExists(atPath: index.path) else { continue }
                    entryPath = name + "/index.html"
                } else if name.lowercased().hasSuffix(".html") {
                    entryPath = name
                } else {
                    continue
                }

                let metaURL = isDir.boolValue
                    ? item.appendingPathComponent("version.json")
                    : item.deletingPathExtension().appendingPathExtension("json")

                if let data = try? Data(contentsOf: metaURL),
                   let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    titled = (object["title"] as? String) ?? titled
                    engine = (object["engine"] as? String) ?? engine
                    minecraft = (object["minecraft"] as? String) ?? ""
                    if let value = object["order"] as? Int { order = value }
                    if let value = object["badge"] as? String { badge = value }
                }

                if minecraft.isEmpty {
                    // 目录名形如 1.8 / 1.5.2 时直接当作版本号显示
                    if name.range(of: "^[0-9]+\\.[0-9]+", options: .regularExpression) != nil {
                        minecraft = name
                    }
                }

                let key = name.lowercased()
                if seen.contains(key) { continue }
                seen.insert(key)

                var detail = "内置客户端 · \(engine)"
                if isUser { detail = "用户导入 · \(engine)" }
                if !minecraft.isEmpty { detail = "Minecraft \(minecraft) · " + detail }

                collected.append(GameVersion(
                    id: (isUser ? "user:" : "bundle:") + name,
                    kind: .bundled,
                    title: titled,
                    detail: detail,
                    path: entryPath,
                    url: "",
                    order: order,
                    minecraft: minecraft,
                    engine: engine,
                    badge: badge
                ))

                if isUser { userAdded += 1 } else { bundledAdded += 1 }
            }
        }

        collected.sort { lhs, rhs in
            if lhs.order != rhs.order { return lhs.order < rhs.order }
            return lhs.id < rhs.id
        }

        // 用户自定义链接
        for (index, raw) in customURLs.enumerated() {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            collected.append(GameVersion(
                id: "custom:\(index):\(trimmed)",
                kind: .custom,
                title: "自定义客户端 \(index + 1)",
                detail: trimmed,
                url: trimmed,
                order: 500 + index,
                badge: "🔗"
            ))
        }

        // 远程串流
        if !streamURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            collected.append(GameVersion(
                id: "stream:remote",
                kind: .stream,
                title: "远程串流（真 Java 版）",
                detail: streamURL,
                url: streamURL.trimmingCharacters(in: .whitespacesAndNewlines),
                order: 1000,
                badge: "🖥️"
            ))
        }

        bundledCount = bundledAdded
        userCount = userAdded
        versions = collected
    }

    // MARK: - 自定义链接管理

    func addCustomURL(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        customURLs.append(trimmed)
        defaults.set(customURLs, forKey: Keys.customURLs)
        scanVersions()
    }

    func removeCustomURL(at index: Int) {
        guard customURLs.indices.contains(index) else { return }
        customURLs.remove(at: index)
        defaults.set(customURLs, forKey: Keys.customURLs)
        scanVersions()
    }

    // MARK: - 组装 URL

    func playURL(for version: GameVersion) -> URL? {
        switch version.kind {
        case .bundled:
            guard port > 0 else { return nil }
            var components = URLComponents()
            components.scheme = "http"
            components.host = "127.0.0.1"
            components.port = Int(port)
            components.path = "/" + version.path

            var queryItems: [String] = []
            let direct = directServer.trimmingCharacters(in: .whitespacesAndNewlines)
            if !direct.isEmpty {
                queryItems.append("server=" + (direct.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""))
            }
            let extra = extraQuery.trimmingCharacters(in: .whitespacesAndNewlines)
            if !extra.isEmpty {
                queryItems.append(extra)
            }
            if !queryItems.isEmpty {
                components.query = queryItems.joined(separator: "&")
            }
            return components.url
        case .custom, .stream:
            var raw = version.url.trimmingCharacters(in: .whitespacesAndNewlines)
            if !raw.contains("://") {
                raw = "https://" + raw
            }
            return URL(string: raw)
        }
    }

    func diagnostics() -> String {
        var lines: [String] = []
        lines.append("本地服务器：\(serverStatus)")
        lines.append("内置客户端目录：\(bundledClientsDir?.path ?? "无")")
        lines.append("用户客户端目录：\(documentsClientsDir.path)")
        lines.append("内置客户端数：\(bundledCount)")
        lines.append("用户导入数：\(userCount)")
        lines.append("可玩条目总数：\(versions.count)")
        let roots = rootDirs.map { $0.lastPathComponent }.joined(separator: ", ")
        lines.append("服务器根目录：\(roots)")
        return lines.joined(separator: "\n")
    }

    private func writeReadmeIfNeeded() {
        let readme = documentsClientsDir.appendingPathComponent("README.txt")
        if FileManager.default.fileExists(atPath: readme.path) { return }
        let text = """
        JavaMC 用户客户端目录

        把任意「浏览器版 Minecraft」客户端放进这个目录，App 会自动出现在版本列表里。

        两种放法都可以：
        1) 建一个子目录，里面放 index.html（例如 Clients/1.20/index.html）
           可选再放 version.json 自定义显示信息：
           {"title":"我的 1.20","minecraft":"1.20","engine":"Eaglercraft","order":10,"badge":"🟩"}
        2) 直接放一个独立的 .html 文件（例如 Clients/myclient.html）

        怎么放进手机：
        文件 App → 我的 iPhone → JavaMC → Clients
        或者用 iTunes/Finder 文件共享、AirDrop 到 JavaMC。

        注意：客户端必须是纯网页实现（JS/WASM）。原生 Java 虚拟机在 iOS 上无法运行，
        原因见项目 README（iOS 禁止可写可执行内存，JIT 需要特殊授权）。
        """
        try? text.write(to: readme, atomically: true, encoding: .utf8)
    }
}
