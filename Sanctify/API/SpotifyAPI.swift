import Foundation

final class SpotifyAPI {
    private let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 15
        return URLSession(configuration: c)
    }()

    private(set) var token: String?

    func setToken(_ token: String) { self.token = token }

    private func request(_ path: String, method: String = "GET") -> URLRequest? {
        guard let token,
              let url = URL(string: "https://api.spotify.com/v1\(path)") else { return nil }
        var r = URLRequest(url: url)
        r.httpMethod = method
        r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return r
    }

    private func fetch<T: Decodable>(_ path: String) async -> T? {
        guard let req = request(path) else { return nil }
        guard let (data, _) = try? await session.data(for: req) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    func fetchFeatured() async -> [SPlaylist] {
        let r: SFeaturedResponse? = await fetch("/browse/featured-playlists?limit=20")
        return r?.playlists.items ?? []
    }

    func fetchUserPlaylists() async -> [SPlaylist] {
        let r: SPlaylistsResponse? = await fetch("/me/playlists?limit=50")
        return r?.items ?? []
    }

    func fetchPlaylistTracks(_ id: String) async -> [STrack] {
        let r: SPlaylistTracksResponse? = await fetch("/playlists/\(id)/tracks?limit=50")
        return r?.items.compactMap(\.track) ?? []
    }

    func search(_ query: String) async -> [STrack] {
        let q = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        let r: SSearchResponse? = await fetch("/search?q=\(q)&type=track&limit=25")
        return r?.tracks.items ?? []
    }

    func fetchDevices() async -> [SDevice] {
        let r: SDevicesResponse? = await fetch("/me/player/devices")
        return r?.devices ?? []
    }

    func fetchCurrentTrack() async -> SCurrentTrack? {
        await fetch("/me/player/currently-playing")
    }

    func play(uri: String, deviceId: String?) async {
        var path = "/me/player/play"
        if let deviceId { path += "?device_id=\(deviceId)" }
        guard var req = request(path, method: "PUT") else { return }
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["uris": [uri]])
        _ = try? await session.data(for: req)
    }

    func pause(deviceId: String?) async {
        var path = "/me/player/pause"
        if let deviceId { path += "?device_id=\(deviceId)" }
        guard let req = request(path, method: "PUT") else { return }
        _ = try? await session.data(for: req)
    }

    func skipNext(deviceId: String?) async {
        var path = "/me/player/next"
        if let deviceId { path += "?device_id=\(deviceId)" }
        guard let req = request(path, method: "POST") else { return }
        _ = try? await session.data(for: req)
    }

    func skipPrevious(deviceId: String?) async {
        var path = "/me/player/previous"
        if let deviceId { path += "?device_id=\(deviceId)" }
        guard let req = request(path, method: "POST") else { return }
        _ = try? await session.data(for: req)
    }

    func setVolume(_ percent: Int, deviceId: String?) async {
        var path = "/me/player/volume?volume_percent=\(percent)"
        if let deviceId { path += "&device_id=\(deviceId)" }
        guard let req = request(path, method: "PUT") else { return }
        _ = try? await session.data(for: req)
    }
}
