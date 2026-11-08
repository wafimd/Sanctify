import WebKit

// Injected at document start.
// 1. Intercepts fetch/XHR to capture Bearer tokens.
// 2. Exposes sanctifyPlay/Toggle/Next/Prev that drive the internal player.
private let kInterceptJS = """
(function() {
    // --- Token capture ---
    function emit(token) {
        try { window.webkit.messageHandlers.sanctify.postMessage({ type: 'token', value: token }); } catch(e) {}
    }
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
    const _setHeader = XMLHttpRequest.prototype.setRequestHeader;
    XMLHttpRequest.prototype.setRequestHeader = function(name, value) {
        if (name.toLowerCase() === 'authorization' && value.startsWith('Bearer ')) emit(value.slice(7));
        return _setHeader.apply(this, arguments);
    };

    // --- Playback helpers ---
    // Spotify's web player exposes a global player instance via the Spotify Connect state.
    // We try several known access patterns in order of reliability.
    function getPlayer() {
        // Pattern 1: Spotify SDK window object (web player registers here)
        if (window.Spotify && window.Spotify.Player) {
            var instances = window.Spotify.Player._instances;
            if (instances && instances.length) return instances[0];
        }
        // Pattern 2: SpotifyApi on window
        if (window.SpotifyApi) return window.SpotifyApi;
        return null;
    }

    // Drive playback via keyboard shortcuts as reliable fallback
    function pressKey(code) {
        var e = new KeyboardEvent('keydown', { key: code, code: code, bubbles: true });
        document.dispatchEvent(e);
    }

    window.sanctifyPlay = function(uri) {
        try {
            // Try Spotify Connect REST via page's own fetch (uses its session, works on free)
            fetch('https://api.spotify.com/v1/me/player/play', {
                method: 'PUT',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ uris: [uri] })
            });
        } catch(e) {}
    };

    window.sanctifyToggle = function() {
        pressKey('Space');
    };

    window.sanctifyNext = function() {
        pressKey('ArrowRight');
        // Also try media key
        try { pressKey('MediaTrackNext'); } catch(e) {}
    };

    window.sanctifyPrev = function() {
        pressKey('ArrowLeft');
        try { pressKey('MediaTrackPrevious'); } catch(e) {}
    };

    // Poll localStorage for token fallback
    function pollStorage() {
        try {
            for (var i = 0; i < localStorage.length; i++) {
                var key = localStorage.key(i);
                var val = localStorage.getItem(key);
                if (!val) continue;
                if (key && (key.includes('accessToken') || key.includes('access_token'))) {
                    if (val.length > 50 && !val.startsWith('{')) { emit(val); return; }
                }
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
    window.addEventListener('load', function() {
        var interval = setInterval(function() { pollStorage(); }, 2000);
        setTimeout(function() { clearInterval(interval); }, 120000);

        // Signal native side that the player UI is ready
        setTimeout(function() {
            try { window.webkit.messageHandlers.sanctify.postMessage({ type: 'ready' }); } catch(e) {}
        }, 4000);
    });
})();
"""

@MainActor
final class SpotifyWebEngine: NSObject, ObservableObject {
    static let shared = SpotifyWebEngine()

    @Published var webPlayerReady = false

    private(set) var webView: WKWebView!
    private var lastToken: String?
    private var hasLoaded = false

    private override init() {
        super.init()
        setupWebView()
    }

    private func setupWebView() {
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
        // Desktop UA — free accounts get unlimited skips on the web player
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15"
    }

    func loadWebPlayer() {
        guard !hasLoaded else { return }
        hasLoaded = true
        webView.load(URLRequest(url: URL(string: "https://open.spotify.com")!))
    }

    func reset() {
        webPlayerReady = false
        hasLoaded = false
        lastToken = nil
        webView.load(URLRequest(url: URL(string: "about:blank")!))
    }

    private func onToken(_ token: String) {
        guard token != lastToken, token.count > 50 else { return }
        lastToken = token
        // Token from web player — update API client but don't loop back to loadWebPlayer
        AppState.shared.api.setToken(token)
    }

    private func onPlayerReady() {
        webPlayerReady = true
        AppState.shared.onWebPlayerReady()
    }
}

extension SpotifyWebEngine: WKScriptMessageHandler {
    nonisolated func userContentController(_ userContentController: WKUserContentController,
                                           didReceive message: WKScriptMessage) {
        guard message.name == "sanctify",
              let body = message.body as? [String: Any] else { return }
        let type = body["type"] as? String
        Task { @MainActor in
            switch type {
            case "token":
                if let value = body["value"] as? String { self.onToken(value) }
            case "ready":
                self.onPlayerReady()
            default:
                break
            }
        }
    }
}

extension SpotifyWebEngine: WKNavigationDelegate {
    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {}
}
