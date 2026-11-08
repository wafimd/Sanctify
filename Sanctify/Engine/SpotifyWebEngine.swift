import WebKit

// Injected at document start — hooks fetch/XHR before Spotify's own JS runs
private let kInterceptJS = """
(function() {
    function emit(token) {
        try { window.webkit.messageHandlers.sanctify.postMessage({ type: 'token', value: token }); } catch(e) {}
    }
    // Intercept fetch
    const _fetch = window.fetch;
    window.fetch = function(input, init) {
        try {
            var h = (init && init.headers) || {};
            if (h instanceof Headers) h = Object.fromEntries(h.entries());
            var auth = h['Authorization'] || h['authorization'] || '';
            if (auth.startsWith('Bearer ')) emit(auth.slice(7));
        } catch(e) {}
        return _fetch.apply(this, arguments);
    };
    // Intercept XHR
    const _open = XMLHttpRequest.prototype.open;
    const _setHeader = XMLHttpRequest.prototype.setRequestHeader;
    XMLHttpRequest.prototype.setRequestHeader = function(name, value) {
        if (name.toLowerCase() === 'authorization' && value.startsWith('Bearer ')) emit(value.slice(7));
        return _setHeader.apply(this, arguments);
    };
    // Poll localStorage for Spotify's stored access token
    function pollStorage() {
        try {
            for (var i = 0; i < localStorage.length; i++) {
                var key = localStorage.key(i);
                var val = localStorage.getItem(key);
                if (!val) continue;
                // Spotify stores token as plain string under various keys
                if (key && (key.includes('accessToken') || key.includes('access_token'))) {
                    if (val.length > 50 && !val.startsWith('{')) { emit(val); return; }
                }
                // Also check JSON blobs
                if (val.startsWith('{') && val.includes('accessToken')) {
                    try {
                        var obj = JSON.parse(val);
                        var t = obj.accessToken || obj.access_token;
                        if (t && t.length > 50) { emit(t); return; }
                    } catch(e) {}
                }
            }
        } catch(e) {}
    }
    // Check every 2s after page load
    window.addEventListener('load', function() {
        var interval = setInterval(function() { pollStorage(); }, 2000);
        setTimeout(function() { clearInterval(interval); }, 60000);
    });
})();
"""

@MainActor
final class SpotifyWebEngine: NSObject, ObservableObject {
    static let shared = SpotifyWebEngine()

    @Published var webPlayerReady = false
    @Published var pageLoaded = false

    private(set) var webView: WKWebView!
    private var lastToken: String?

    private override init() {
        super.init()
        setupWebView()
    }

    private func setupWebView() {
        // Inject at document start so our hooks run before Spotify's JS
        let script = WKUserScript(source: kInterceptJS,
                                  injectionTime: .atDocumentStart,
                                  forMainFrameOnly: false)
        let controller = WKUserContentController()
        controller.addUserScript(script)
        controller.add(self, name: "sanctify")

        let config = WKWebViewConfiguration()
        config.userContentController = controller
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []

        webView = WKWebView(frame: UIScreen.main.bounds, configuration: config)
        webView.navigationDelegate = self
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        // Desktop UA — free accounts get full on-demand playback
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15"

        webView.load(URLRequest(url: URL(string: "https://open.spotify.com")!))
    }

    private func onToken(_ token: String) {
        guard token != lastToken, token.count > 50 else { return }
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

extension SpotifyWebEngine: WKNavigationDelegate {
    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in self.pageLoaded = true }
    }
}
