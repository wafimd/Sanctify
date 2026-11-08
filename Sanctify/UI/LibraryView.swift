import SwiftUI

struct LibraryView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Library")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.top, 60)
                    .padding(.bottom, 20)

                if state.userPlaylists.isEmpty {
                    ForEach(0..<8, id: \.self) { _ in
                        HStack(spacing: 14) {
                            ShimmerRect(width: 56, height: 56, cornerRadius: 8)
                            VStack(alignment: .leading, spacing: 6) {
                                ShimmerRect(width: 140, height: 14, cornerRadius: 4)
                                ShimmerRect(width: 90, height: 11, cornerRadius: 4)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 6)
                    }
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(state.userPlaylists) { playlist in
                            LibraryRow(playlist: playlist)
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 120)
        }
        .background(Color.black.ignoresSafeArea())
    }
}

struct LibraryRow: View {
    @EnvironmentObject var state: AppState
    let playlist: SPlaylist

    var body: some View {
        Button {
            Task {
                let tracks = await state.playlistTracks(playlist.id)
                if let first = tracks.first { await state.play(track: first) }
            }
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(red: 0.15, green: 0.08, blue: 0.25))
                    if let url = playlist.imageURL.flatMap(URL.init) {
                        AsyncImage(url: url) { phase in
                            if let img = phase.image {
                                img.resizable().scaledToFill()
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            }
                        }
                    }
                }
                .frame(width: 56, height: 56)

                VStack(alignment: .leading, spacing: 3) {
                    Text(playlist.name)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    Text("Playlist")
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.45))
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(0.25))
            }
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
    }
}
