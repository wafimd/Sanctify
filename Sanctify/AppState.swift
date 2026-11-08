import SwiftUI
import Combine

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    // Auth / engine
    @Published var isLoggedIn = false
    @Published var webPlayerReady = false

    // Playback
    @Published var currentTrack: STrack?
    @Published var isPlaying = false
    @Published var progressMs: Int = 0
    @Published var webPlayerDeviceId: String?

    // Library
    @Published var featured: [SPlaylist] = []
    @Published var userPlaylists: [SPlaylist] = []

    // UI state
    @Published var showNowPlaying = false

    let api = SpotifyAPI()
    private var pollTask: Task<Void, Never>?
    private var loadTask: Task<Void, Never>?

    private init() {}

    func onTokenReceived(_ token: String) async {
        api.setToken(token)
        webPlayerReady = true
        isLoggedIn = true

        // Find the web player device (registered by our hidden WKWebView)
        await resolveWebPlayerDevice()

        // Load library data once
        if userPlaylists.isEmpty {
            loadTask?.cancel()
            loadTask = Task { await loadLibrary() }
        }

        // Start polling current track
        startPolling()
    }

    private func resolveWebPlayerDevice() async {
        // Retry a few times — web player may take a moment to register
        for _ in 0..<5 {
            let devices = await api.fetchDevices()
            if let device = devices.first(where: { $0.type == "Computer" || $0.name.contains("Web Player") }) {
                webPlayerDeviceId = device.id
                return
            }
            try? await Task.sleep(nanoseconds: 1_500_000_000)
        }
    }

    private func loadLibrary() async {
        async let f: () = { self.featured = await self.api.fetchFeatured() }()
        async let p: () = { self.userPlaylists = await self.api.fetchUserPlaylists() }()
        _ = await (f, p)
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

    // MARK: - Playback actions

    func play(track: STrack) async {
        currentTrack = track
        isPlaying = true
        await api.play(uri: track.uri, deviceId: webPlayerDeviceId)
    }

    func togglePlayPause() async {
        if isPlaying {
            await api.pause(deviceId: webPlayerDeviceId)
            isPlaying = false
        } else {
            if let track = currentTrack {
                await api.play(uri: track.uri, deviceId: webPlayerDeviceId)
                isPlaying = true
            }
        }
    }

    func skipNext() async {
        await api.skipNext(deviceId: webPlayerDeviceId)
        try? await Task.sleep(nanoseconds: 500_000_000)
        if let state = await api.fetchCurrentTrack() {
            currentTrack = state.item
            isPlaying = state.isPlaying
        }
    }

    func skipPrevious() async {
        await api.skipPrevious(deviceId: webPlayerDeviceId)
        try? await Task.sleep(nanoseconds: 500_000_000)
        if let state = await api.fetchCurrentTrack() {
            currentTrack = state.item
            isPlaying = state.isPlaying
        }
    }

    func search(_ query: String) async -> [STrack] {
        await api.search(query)
    }

    func playlistTracks(_ id: String) async -> [STrack] {
        await api.fetchPlaylistTracks(id)
    }
}
