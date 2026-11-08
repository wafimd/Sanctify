import SwiftUI
import Combine

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    @Published var isLoggedIn = false
    @Published var webPlayerReady = false

    // Playback
    @Published var currentTrack: STrack?
    @Published var isPlaying = false
    @Published var progressMs: Int = 0

    // Library
    @Published var featured: [SPlaylist] = []
    @Published var userPlaylists: [SPlaylist] = []

    let api = SpotifyAPI()
    private var pollTask: Task<Void, Never>?
    private var loadTask: Task<Void, Never>?

    private init() {}

    // Called by SpotifyWebEngine when a Bearer token is intercepted from the web player
    func onTokenReceived(_ token: String) async {
        api.setToken(token)
        isLoggedIn = true

        if userPlaylists.isEmpty {
            loadTask?.cancel()
            loadTask = Task { await loadLibrary() }
        }
        startPolling()
    }

    func resetState() {
        webPlayerReady = false
        isLoggedIn = false
        currentTrack = nil
        isPlaying = false
        progressMs = 0
        featured = []
        userPlaylists = []
        pollTask?.cancel()
        loadTask?.cancel()
    }

    private func loadLibrary() async {
        async let f = api.fetchFeatured()
        async let p = api.fetchUserPlaylists()
        let (newFeatured, newPlaylists) = await (f, p)
        featured = newFeatured
        userPlaylists = newPlaylists
    }

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task {
            while !Task.isCancelled {
                if let state = await api.fetchCurrentTrack() {
                    currentTrack = state.item
                    isPlaying = state.isPlaying
                    progressMs = state.progressMs ?? 0
                }
                try? await Task.sleep(nanoseconds: 3_000_000_000)
            }
        }
    }

    // MARK: - Playback (via JS injection into the web player)

    func play(track: STrack) async {
        currentTrack = track
        isPlaying = true
        await webJS("window.sanctifyPlay(\(jsonString(track.uri)))")
    }

    func togglePlayPause() async {
        await webJS("window.sanctifyToggle()")
        isPlaying.toggle()
    }

    func skipNext() async {
        await webJS("window.sanctifyNext()")
        try? await Task.sleep(nanoseconds: 800_000_000)
        await refreshTrack()
    }

    func skipPrevious() async {
        await webJS("window.sanctifyPrev()")
        try? await Task.sleep(nanoseconds: 800_000_000)
        await refreshTrack()
    }

    func search(_ query: String) async -> [STrack] {
        await api.search(query)
    }

    func playlistTracks(_ id: String) async -> [STrack] {
        await api.fetchPlaylistTracks(id)
    }

    private func refreshTrack() async {
        if let state = await api.fetchCurrentTrack() {
            currentTrack = state.item
            isPlaying = state.isPlaying
        }
    }

    private func webJS(_ js: String) async {
        await withCheckedContinuation { cont in
            SpotifyWebEngine.shared.webView.evaluateJavaScript(js) { _, _ in
                cont.resume()
            }
        }
    }

    private func jsonString(_ s: String) -> String {
        let escaped = s.replacingOccurrences(of: "\\", with: "\\\\")
                       .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}
