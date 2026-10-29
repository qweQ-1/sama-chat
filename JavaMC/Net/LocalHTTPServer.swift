import Foundation
import Network

/// 极简本地静态文件服务器。
///
/// 为什么要有它：WKWebView 直接 loadFileURL 时是 file:// 源，
/// Web Worker / IndexedDB / localStorage 都会受限（Eaglercraft 需要 Worker）。
/// 所以我们在 127.0.0.1 上跑一个只读 HTTP 服务，把 App 内资源用 http:// 暴露给 WebView，
/// 这样就是一个正常的、可持久化存档的网页源，而且完全离线、不需要用户开 JIT。
final class LocalHTTPServer {

    /// 依次尝试的端口。固定端口很重要：源（origin）稳定，存档才不会因端口变化而丢失。
    private let candidatePorts: [UInt16] = [47823, 47824, 47825, 47826, 0]

    private let roots: [URL]
    private let queue = DispatchQueue(label: "com.qweq-1.javamc.http")
    private var listener: NWListener?

    private(set) var port: UInt16 = 0
    private(set) var isRunning = false

    var onReady: ((UInt16) -> Void)?
    var onFailure: ((String) -> Void)?

    init(roots: [URL]) {
        self.roots = roots
    }

    func start() {
        tryPort(at: 0)
    }

    func stop() {
        listener?.cancel()
        listener = nil
        isRunning = false
    }

    // MARK: - 监听

    private func tryPort(at index: Int) {
        guard index < candidatePorts.count else {
            onFailure?("没有可用端口")
            return
        }
        let raw = candidatePorts[index]
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        params.acceptLocalOnly = true

        let newListener: NWListener
        do {
            if raw == 0 {
                newListener = try NWListener(using: params)
            } else {
                guard let nwPort = NWEndpoint.Port(rawValue: raw) else {
                    tryPort(at: index + 1)
                    return
                }
                newListener = try NWListener(using: params, on: nwPort)
            }
        } catch {
            tryPort(at: index + 1)
            return
        }

        listener?.cancel()
        listener = newListener

        newListener.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            switch state {
            case .ready:
                self.port = newListener.port?.rawValue ?? raw
                self.isRunning = true
                self.onReady?(self.port)
            case .failed, .cancelled:
                if !self.isRunning {
                    self.tryPort(at: index + 1)
                }
            default:
                break
            }
        }

        newListener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }

        newListener.start(queue: queue)
    }

    // MARK: - 连接处理

    private func accept(_ connection: NWConnection) {
        connection.start(queue: queue)
        readRequest(connection, buffer: Data())
    }

    private func readRequest(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self = self else {
                connection.cancel()
                return
            }
            var accumulated = buffer
            if let chunk = data {
                accumulated.append(chunk)
            }
            if let headerEnd = accumulated.range(of: Data("\r\n\r\n".utf8)) {
                let headerData = accumulated.subdata(in: 0..<headerEnd.lowerBound)
                let header = String(data: headerData, encoding: .utf8) ?? ""
                self.respond(connection, header: header)
            } else if error != nil || isComplete || accumulated.count > 131072 {
                connection.cancel()
            } else {
                self.readRequest(connection, buffer: accumulated)
            }
        }
    }

    private func respond(_ connection: NWConnection, header: String) {
        let lines = header.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else {
            connection.cancel()
            return
        }
        let parts = requestLine.split(separator: " ").map(String.init)
        guard parts.count >= 2 else {
            connection.cancel()
            return
        }
        let method = parts[0].uppercased()
        let headOnly = (method == "HEAD")

        var relative = parts[1]
        if let cut = relative.firstIndex(of: "?") {
            relative = String(relative[relative.startIndex..<cut])
        }
        if let cut = relative.firstIndex(of: "#") {
            relative = String(relative[relative.startIndex..<cut])
        }
        relative = relative.removingPercentEncoding ?? relative
        while relative.hasPrefix("/") {
            relative.removeFirst()
        }
        if relative.isEmpty {
            relative = "index.html"
        }

        let pieces = relative.split(separator: "/").map(String.init)
        if pieces.contains("..") {
            send(connection, status: "400 Bad Request", body: Data(), headOnly: true)
            return
        }

        var hit: URL?
        for root in roots {
            let candidate = root.appendingPathComponent(relative)
            if FileManager.default.fileExists(atPath: candidate.path) {
                hit = candidate
                break
            }
            // 目录（无扩展名）时退回 index.html
            if (relative as NSString).pathExtension.isEmpty {
                let fallback = candidate.appendingPathComponent("index.html")
                if FileManager.default.fileExists(atPath: fallback.path) {
                    hit = fallback
                    break
                }
            }
        }

        guard let fileURL = hit, let body = try? Data(contentsOf: fileURL) else {
            let notFound = Data("<h1>404</h1><p>JavaMC: 未找到 \(relative)</p>".utf8)
            send(connection, status: "404 Not Found", mime: "text/html; charset=utf-8", body: notFound)
            return
        }

        send(connection, status: "200 OK", mime: mimeType(for: fileURL.pathExtension), body: body, headOnly: headOnly)
    }

    private func send(_ connection: NWConnection, status: String, mime: String = "text/plain; charset=utf-8", body: Data, headOnly: Bool = false) {
        var head = "HTTP/1.1 \(status)\r\n"
        head += "Content-Type: \(mime)\r\n"
        head += "Content-Length: \(body.count)\r\n"
        head += "Cache-Control: no-store\r\n"
        head += "Access-Control-Allow-Origin: *\r\n"
        head += "Connection: close\r\n\r\n"

        var payload = Data(head.utf8)
        if !headOnly {
            payload.append(body)
        }
        connection.send(content: payload, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func mimeType(for ext: String) -> String {
        switch ext.lowercased() {
        case "html", "htm": return "text/html; charset=utf-8"
        case "js", "mjs": return "text/javascript; charset=utf-8"
        case "css": return "text/css; charset=utf-8"
        case "json", "map": return "application/json; charset=utf-8"
        case "txt", "log", "lang", "properties", "md": return "text/plain; charset=utf-8"
        case "xml": return "text/xml; charset=utf-8"
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "webp": return "image/webp"
        case "svg": return "image/svg+xml"
        case "ico": return "image/x-icon"
        case "wasm": return "application/wasm"
        case "ogg", "oga": return "audio/ogg"
        case "mp3": return "audio/mpeg"
        case "wav": return "audio/wav"
        case "m4a": return "audio/mp4"
        case "mp4": return "video/mp4"
        case "ttf": return "font/ttf"
        case "otf": return "font/otf"
        case "woff": return "font/woff"
        case "woff2": return "font/woff2"
        case "pdf": return "application/pdf"
        case "zip": return "application/zip"
        default: return "application/octet-stream"
        }
    }
}
