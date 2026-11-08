import Foundation
import CryptoKit
import AuthenticationServices

@MainActor
final class SpotifyAuth: NSObject, ObservableObject {
    static let shared = SpotifyAuth()

    static let redirectURI = "sanctify://callback"
    static let scopes = "streaming user-read-playback-state user-modify-playback-state user-read-currently-playing playlist-read-private playlist-read-collaborative user-library-read"

    @Published var accessToken: String?
    @Published var isAuthenticated = false
    @Published var isAuthenticating = false
    @Published var authError: String?

    private let clientId = "02484c72dadf4013823c94e68d238bf3"

    private var codeVerifier: String?
    private var refreshToken: String?
    private var tokenExpiry: Date?
    private var authSession: ASWebAuthenticationSession?

    private let defaults = UserDefaults.standard

    private override init() {
        super.init()
        accessToken   = defaults.string(forKey: "spm_access_token")
        refreshToken  = defaults.string(forKey: "spm_refresh_token")
        tokenExpiry   = defaults.object(forKey: "spm_token_expiry") as? Date
        isAuthenticated = accessToken != nil

        if isAuthenticated { scheduleRefresh() }
    }

    // MARK: - Sign In via ASWebAuthenticationSession

    func signIn() {
        guard !clientId.isEmpty, let authURL = makeAuthURL() else { return }

        isAuthenticating = true
        authError = nil

        let session = ASWebAuthenticationSession(
            url: authURL,
            callbackURLScheme: "sanctify"
        ) { [weak self] callbackURL, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isAuthenticating = false

                if let error {
                    if (error as? ASWebAuthenticationSessionError)?.code != .canceledLogin {
                        self.authError = error.localizedDescription
                    }
                    return
                }

                guard let url = callbackURL else { return }

                guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                      let code = components.queryItems?.first(where: { $0.name == "code" })?.value,
                      let verifier = self.codeVerifier else { return }

                let ok = await self.exchangeCode(code, verifier: verifier)
                if !ok { self.authError = "Token exchange failed — check your Client ID." }
            }
        }

        session.presentationContextProvider = self
        session.prefersEphemeralWebBrowserSession = false
        authSession = session
        session.start()
    }

    // MARK: - PKCE Auth URL

    private func makeAuthURL() -> URL? {
        var bytes = [UInt8](repeating: 0, count: 64)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let verifier = Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        codeVerifier = verifier

        let challenge = Data(SHA256.hash(data: Data(verifier.utf8)))
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")

        var c = URLComponents(string: "https://accounts.spotify.com/authorize")!
        c.queryItems = [
            .init(name: "client_id",             value: clientId),
            .init(name: "response_type",          value: "code"),
            .init(name: "redirect_uri",           value: Self.redirectURI),
            .init(name: "scope",                  value: Self.scopes),
            .init(name: "code_challenge_method",  value: "S256"),
            .init(name: "code_challenge",         value: challenge),
            .init(name: "show_dialog",            value: "false"),
        ]
        return c.url
    }

    // MARK: - Token exchange

    private func exchangeCode(_ code: String, verifier: String) async -> Bool {
        var req = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body = [
            "grant_type=authorization_code",
            "code=\(code)",
            "redirect_uri=\(Self.redirectURI)",
            "client_id=\(clientId)",
            "code_verifier=\(verifier)"
        ].joined(separator: "&")
        req.httpBody = body.data(using: .utf8)

        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let r = try? JSONDecoder().decode(TokenResponse.self, from: data),
              !r.access_token.isEmpty else { return false }

        store(accessToken: r.access_token, refreshToken: r.refresh_token, expiresIn: r.expires_in)
        return true
    }

    // MARK: - Refresh

    func refresh() async {
        guard let rt = refreshToken else { return }
        var req = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = "grant_type=refresh_token&refresh_token=\(rt)&client_id=\(clientId)".data(using: .utf8)

        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let r = try? JSONDecoder().decode(TokenResponse.self, from: data),
              !r.access_token.isEmpty else { return }

        store(accessToken: r.access_token, refreshToken: r.refresh_token ?? rt, expiresIn: r.expires_in)
    }

    // MARK: - Storage

    private func store(accessToken: String, refreshToken: String?, expiresIn: Int) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken ?? self.refreshToken
        self.tokenExpiry = Date().addingTimeInterval(TimeInterval(expiresIn - 60))
        isAuthenticated = true

        defaults.set(accessToken, forKey: "spm_access_token")
        if let rt = refreshToken { defaults.set(rt, forKey: "spm_refresh_token") }
        defaults.set(tokenExpiry, forKey: "spm_token_expiry")

        Task { await AppState.shared.onTokenReceived(accessToken) }
        scheduleRefresh()
    }

    private func scheduleRefresh() {
        guard let expiry = tokenExpiry else { return }
        let delay = max(expiry.timeIntervalSinceNow, 60)
        Task {
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            await self.refresh()
        }
    }

    // MARK: - Sign Out

    func signOut() {
        accessToken = nil; refreshToken = nil; tokenExpiry = nil; isAuthenticated = false
        defaults.removeObject(forKey: "spm_access_token")
        defaults.removeObject(forKey: "spm_refresh_token")
        defaults.removeObject(forKey: "spm_token_expiry")
        AppState.shared.resetState()
    }

    // MARK: - Token Response

    private struct TokenResponse: Decodable {
        let access_token: String
        let refresh_token: String?
        let expires_in: Int
    }
}

// MARK: - Presentation context

extension SpotifyAuth: ASWebAuthenticationPresentationContextProviding {
    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow } ?? ASPresentationAnchor()
    }
}
