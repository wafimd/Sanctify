import WebKit
import Combine

// JS injected on every page load — intercepts fetch + XHR to capture Bearer token
private let kTokenInterceptJS = """
(function() {
    function capture(token) {
        try { window.webkit.messageHandlers.sanctify.postMessage({ type: 'token', value: token }); } catch(e) {}
    }
    // Intercept fetch
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
    // Intercept XHR
    const _setHeader = XMLHttpRequest.prototype.setRequestHeader;
    XMLHttpRequest.prototype.setRequestHeader = function(name, value) {
        if (name.toLowerCase() === 'authorization' && value.startsWith('Bearer ')) capture(value.slice(7));
        return _setHeader.apply(this, arguments);
    };
    // Report login state
    function checkLogin() {
        const loggedIn = !!document.cookie.includes('sp_dc') || !!localStorage.getItem('logout');
        window.webkit.messageHandlers.sanctify.postMessage({ type: 'loginState', loggedIn: !document.querySelector('[data-testid="login-button"]') });
    }
    setTimeout(checkLogin, 2000);
})();
"""

@MainActor
final class SpotifyWebEngine: NSObject, ObservableObject {
    static let shared = SpotifyWebEngine()

    @Published var token: String?
    @Published var isLoggedIn = false
    @Published var webPlayerReady = false

    private(set) var webView: WKWebView!
    private var lastToken: String?

    private override init() {
        super.init()
        setupWebView()
    }

    private func setupWebView() {
        let userScript = WKUserScript(source: kTokenInterceptJS,
                                      injectionTime: .atDocumentEnd,
                                      forMainFrameOnly: false)
        let controller = WKUserContentController()
        controller.addUserScript(userScript)
        controller.add(self, name: "sanctify")

        let config = WKWebViewConfiguration()
        config.userContentController = controller
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []

        webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = self
        // Desktop UA → unlocks full on-demand playback for free accounts
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"

        load()
    }

    func load() {
        let req = URLRequest(url: URL(string: "https://open.spotify.com")!)
        webView.load(req)
    }

    // Called by bridge after token arrives — signals web player is ready
    private func onToken(_ token: String) {
        guard token != lastToken else { return }
        lastToken = token
        self.token = token
        webPlayerReady = true
        Task { await AppState.shared.onTokenReceived(token) }
    }
}

extension SpotifyWebEngine: WKScriptMessageHandler {
    nonisolated func userContentController(_ userContentController: WKUserContentController,
                                           didReceive message: WKScriptMessage) {
        guard message.name == "sanctify",
              let body = message.body as? [String: Any] else { return }

        Task { @MainActor in
            switch body["type"] as? String {
            case "token":
                if let value = body["value"] as? String { self.onToken(value) }
            case "loginState":
                self.isLoggedIn = body["loggedIn"] as? Bool ?? false
            default: break
            }
        }
    }
}

extension SpotifyWebEngine: WKNavigationDelegate {
    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            self.isLoggedIn = !(webView.url?.absoluteString.contains("login") ?? false)
        }
    }
}
