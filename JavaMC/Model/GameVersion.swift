import Foundation

/// 一个可启动的“游戏版本”。
///
/// - bundled：随 App 打包的客户端（bundle 内 Clients/<目录>/index.html）
/// - custom ：用户自己填的任意网页客户端地址
/// - stream ：远程串流（把真正的 Java 版跑在服务器上，用 noVNC / WebRTC 网页串到 iOS）
struct GameVersion: Identifiable, Hashable {

    enum Kind: String, Codable {
        case bundled
        case custom
        case stream
    }

    var id: String
    var kind: Kind
    var title: String
    var detail: String
    /// bundled 专用：bundle 内 Clients/ 下的相对目录名
    var path: String = ""
    /// custom / stream 专用：完整 URL
    var url: String = ""
    /// 排序权重，越小越靠前
    var order: Int = 100
    /// 该客户端对应的 Minecraft 版本号（可选，来自 version.json）
    var minecraft: String = ""
    /// 渲染引擎说明（可选，来自 version.json）
    var engine: String = ""
    /// 图标 emoji
    var badge: String = "🟩"

    var isPlayable: Bool {
        switch kind {
        case .bundled: return !path.isEmpty
        case .custom, .stream: return !url.isEmpty
        }
    }
}
