import Foundation

struct STrack: Decodable, Identifiable, Equatable {
    let id: String
    let name: String
    let durationMs: Int
    let explicit: Bool
    let album: SAlbum
    let artists: [SArtist]

    var artistName: String { artists.map(\.name).joined(separator: ", ") }
    var imageURL: String? { album.images.first?.url }
    var uri: String { "spotify:track:\(id)" }

    enum CodingKeys: String, CodingKey {
        case id, name, explicit, album, artists
        case durationMs = "duration_ms"
    }
}

struct SAlbum: Decodable, Identifiable, Equatable {
    let id: String
    let name: String
    let images: [SImage]
}

struct SArtist: Decodable, Identifiable, Equatable {
    let id: String
    let name: String
}

struct SImage: Decodable, Equatable {
    let url: String
    let width: Int?
    let height: Int?
}

struct SPlaylist: Decodable, Identifiable, Equatable {
    let id: String
    let name: String
    let images: [SImage]
    var imageURL: String? { images.first?.url }
}

struct SDevice: Decodable, Identifiable {
    let id: String?
    let name: String
    let type: String
    let isActive: Bool

    enum CodingKeys: String, CodingKey {
        case id, name, type
        case isActive = "is_active"
    }
}

struct SCurrentTrack: Decodable {
    let isPlaying: Bool
    let item: STrack?
    let progressMs: Int?

    enum CodingKeys: String, CodingKey {
        case item
        case isPlaying = "is_playing"
        case progressMs = "progress_ms"
    }
}

// Response wrappers
struct SPlaylistsResponse: Decodable { let items: [SPlaylist] }
struct SDevicesResponse: Decodable { let devices: [SDevice] }
struct SSearchResponse: Decodable {
    struct Tracks: Decodable { let items: [STrack] }
    let tracks: Tracks
}
struct SFeaturedResponse: Decodable {
    struct Playlists: Decodable { let items: [SPlaylist] }
    let playlists: Playlists
}
struct SPlaylistTracksResponse: Decodable {
    struct Item: Decodable { let track: STrack? }
    let items: [Item]
}
