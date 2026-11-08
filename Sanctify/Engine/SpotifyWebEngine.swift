import WebKit

// Injected on every page load — intercepts fetch + XHR to capture Bearer token
private let kTokenInterceptJS = """
(function() {
    function capture(token) {
        try { window.webkit.messageHandlers.sanctify.postMessage({ type: 'token', value: token }); } catch(e) {}
    }
    const _fetch = window.fetch;
    window.fetch = function(input, init) {
        try {
            var h = (init && init.headers) || {};
            if (h instanceof Headers) h = Object.fromEntries(h.entries());
            var auth = h['Authorization'] || h['authorization'] || '';
            if (auth.startsWith('Bearer ')) capture(auth.slice(7));
        } catch(e) {}
        return _fetch.apply(this, arguments);
    };
    const _setHeader = XMLHttpRequest.prototype.setRequestHeader;
    XMLHttpRequest.prototype.setRequestHeader = function(name, value) {
        if (name.toLowerCase() === 'authorization' && value.startsWith('Bearer ')) capture(value.slice(7));
        return _setHeader.apply(this, arguments);
    };
})();
"""

@MainActor
final class SpotifyWebEngine: NSObject, ObservableObject {
    static let shared = SpotifyWebEngine()

    @Published var webPlayerReady = false

    private(set) var webView: WKWebView!
    private var lastToken: String?

    private override init() {
        super.init()
        setupWebView()
    }

    private func setupWebView() {
        let script = WKUserScript(source: kTokenInterceptJS,
                                  injectionTime: .atDocumentEnd,
                                  forMainFrameOnly: false)
        let controller = WKUserContentController()
        controller.addUserScript(script)
        controller.add(self, name: "sanctify")

        let config = WKWebViewConfiguration()
        config.userContentController = controller
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []

        webView = WKWebView(frame: .zero, configuration: config)
        // Desktop UA → free account gets full on-demand playback
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"
        webView.load(URLRequest(url: URL(string: "https://open.spotify.com")!))
    }

    private func onToken(_ token: String) {
        guard token != lastToken else { return }
        lastToken = token
        webPlayerReady = true
        Task { await AppState.shared.onTokenReceived(token) }
    }
}

extension SpotifyWebEngine: WKScriptMessageHandler {
    nonisolated func userContentController(_ userContentController: WKUserContentController,
                                           didReceive message: WKScriptMessage) {
        guard message.name == "sanctify",
              let body = message.body as? [String: Any],
              body["type"] as? String == "token",
              let value = body["value"] as? String else { return }
        Task { @MainActor in self.onToken(value) }
    }
}
