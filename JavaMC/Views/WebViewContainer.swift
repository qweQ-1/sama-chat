import SwiftUI
import WebKit

/// WKWebView 包装。
///
/// 关键点：
/// 1) 不做任何自定义 UA —— 保持 iPhone 默认 UA，Eaglercraft 会自动启用触屏操作界面。
/// 2) mediaTypesRequiringUserActionForPlayback = [] —— 允许游戏音效自动播放。
/// 3) 数据存储用默认持久化存储，存档/设置重启后还在。
/// 4) WebAssembly / JavaScript 由 WebKit 自己执行（WebContent 进程自带 JIT 授权），
///    所以 App 本身不需要任何 JIT 相关 entitlement。
struct WebViewContainer: UIViewRepresentable {

    let url: URL
    let reloadToken: Int
    @Binding var isLoading: Bool
    @Binding var errorText: String

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.websiteDataStore = .default()
        configuration.allowsAirPlayForMediaPlayback = true

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = false
        webView.allowsLinkPreview = false
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.scrollView.bouncesZoom = false
        webView.scrollView.maximumZoomScale = 1
        webView.scrollView.minimumZoomScale = 1
        webView.isOpaque = true
        webView.backgroundColor = .black
        webView.scrollView.backgroundColor = .black
        webView.underPageBackgroundColor = .black
        if #available(iOS 16.4, *) {
            webView.isInspectable = false
        }

        context.coordinator.webView = webView
        context.coordinator.load(url)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.parent = self
        if context.coordinator.lastToken != reloadToken {
            context.coordinator.load(url)
        } else if context.coordinator.loadedURL != url.absoluteString {
            context.coordinator.load(url)
        }
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {

        var parent: WebViewContainer
        weak var webView: WKWebView?
        var loadedURL: String = ""
        var lastToken: Int = -1

        init(_ parent: WebViewContainer) {
            self.parent = parent
        }

        func load(_ url: URL) {
            loadedURL = url.absoluteString
            lastToken = parent.reloadToken
            DispatchQueue.main.async {
                self.parent.isLoading = true
                self.parent.errorText = ""
            }
            var request = URLRequest(url: url)
            request.cachePolicy = .reloadRevalidatingCacheData
            request.timeoutInterval = 60
            webView?.load(request)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            let css = "*{-webkit-touch-callout:none !important;-webkit-user-select:none !important;-webkit-tap-highlight-color:transparent !important;} body{margin:0;background:#000;} canvas{display:block;}"
            let script = "var s=document.createElement('style');s.appendChild(document.createTextNode('\(css)'));var h=document.head||document.documentElement;h.appendChild(s);"
            webView.evaluateJavaScript(script, completionHandler: nil)
            DispatchQueue.main.async {
                self.parent.isLoading = false
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            report(error)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            report(error)
        }

        private func report(_ error: Error) {
            let nsError = error as NSError
            if nsError.code == NSURLErrorCancelled { return }
            DispatchQueue.main.async {
                self.parent.isLoading = false
                self.parent.errorText = "加载失败：\(nsError.localizedDescription)（\(nsError.code)）"
            }
        }

        // 允许游戏打开新窗口（Eaglercraft 的链接跳转）时留在同一视图
        func webView(_ webView: WKWebView,
                     createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction,
                     windowFeatures: WKWindowFeatures) -> WKWebView? {
            if let target = navigationAction.request.url {
                webView.load(URLRequest(url: target))
            }
            return nil
        }

        func webView(_ webView: WKWebView,
                     runJavaScriptAlertPanelWithMessage message: String,
                     initiatedByFrame frame: WKFrameInfo,
                     completionHandler: @escaping () -> Void) {
            completionHandler()
        }
    }
}
