import AppKit
import WebKit

@MainActor
final class DaytonaOutcomePreviewController: NSObject, NSWindowDelegate, WKNavigationDelegate {
    private let window: NSWindow
    private let webView: WKWebView
    private let onClose: () -> Void

    init(artifactHTML: String, title: String, onClose: @escaping () -> Void) {
        self.onClose = onClose

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        webView = WKWebView(frame: .zero, configuration: configuration)

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1_080, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        super.init()

        window.title = "Daytona outcome · \(String(title.prefix(80)))"
        window.minSize = NSSize(width: 680, height: 480)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = webView
        webView.navigationDelegate = self
        webView.loadHTMLString(Self.securedHTML(artifactHTML), baseURL: nil)
    }

    func present() {
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    func close() {
        window.close()
    }

    func windowWillClose(_ notification: Notification) {
        onClose()
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void
    ) {
        let scheme = navigationAction.request.url?.scheme?.lowercased()
        let isInitialDocument = navigationAction.navigationType == .other && scheme == "about"
        decisionHandler(isInitialDocument ? .allow : .cancel)
    }

    private static func securedHTML(_ html: String) -> String {
        let policy = "default-src 'none'; style-src 'unsafe-inline'; img-src data:; script-src 'none'; connect-src 'none'; font-src 'none'; media-src 'none'; object-src 'none'; frame-src 'none'; form-action 'none'; base-uri 'none'"
        let meta = #"<meta http-equiv="Content-Security-Policy" content="\#(policy)">"#
        if let head = html.range(of: #"<head(?:\s[^>]*)?>"#, options: [.regularExpression, .caseInsensitive]) {
            var secured = html
            secured.insert(contentsOf: meta, at: head.upperBound)
            return secured
        }
        if let root = html.range(of: #"<html(?:\s[^>]*)?>"#, options: [.regularExpression, .caseInsensitive]) {
            var secured = html
            secured.insert(contentsOf: "<head>\(meta)</head>", at: root.upperBound)
            return secured
        }
        return "<!doctype html><html><head>\(meta)</head><body></body></html>"
    }
}
