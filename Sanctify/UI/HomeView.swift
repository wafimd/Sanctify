import SwiftUI

struct HomeView: View {
    @EnvironmentObject var state: AppState

    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                // Header
                Text("Good \(timeOfDay)")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.top, 60)

                if state.featured.isEmpty && state.userPlaylists.isEmpty {
                    skeletonGrid
                } else {
                    if !state.featured.isEmpty {
                        section(title: "Featured", playlists: state.featured)
                    }
                    if !state.userPlaylists.isEmpty {
                        section(title: "Your Playlists", playlists: state.userPlaylists)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 120)
        }
        .background(Color.black.ignoresSafeArea())
    }

    private func section(title: String, playlists: [SPlaylist]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.white)
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(playlists) { playlist in
                    PlaylistCard(playlist: playlist)
                }
            }
        }
    }

    private var skeletonGrid: some View {
        VStack(alignment: .leading, spacing: 14) {
            ShimmerRect(width: 120, height: 20, cornerRadius: 6)
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(0..<6, id: \.self) { _ in
                    ShimmerRect(width: .infinity, height: 100, cornerRadius: 12)
                        .frame(maxWidth: .infinity)
                        .aspectRatio(1, contentMode: .fit)
                }
            }
        }
    }

    private var timeOfDay: String {
        let h = Calendar.current.component(.hour, from: Date())
        switch h {
        case 5..<12: return "Morning"
        case 12..<17: return "Afternoon"
        default: return "Evening"
        }
    }
}

struct PlaylistCard: View {
    @EnvironmentObject var state: AppState
    let playlist: SPlaylist
    @State private var tracks: [STrack] = []
    @State private var loading = false

    var body: some View {
        Button {
            Task {
                guard !loading else { return }
                loading = true
                tracks = await state.playlistTracks(playlist.id)
                if let first = tracks.first {
                    await state.play(track: first)
                }
                loading = false
            }
        } label: {
            ZStack(alignment: .bottomLeading) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(red: 0.15, green: 0.08, blue: 0.25))
                    if let url = playlist.imageURL.flatMap(URL.init) {
                        AsyncImage(url: url) { phase in
                            if let img = phase.image {
                                img.resizable().scaledToFill()
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                        }
                    }
                }
                .aspectRatio(1, contentMode: .fit)

                Text(playlist.name)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(2)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        LinearGradient(colors: [.clear, .black.opacity(0.7)],
                                       startPoint: .top, endPoint: .bottom)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    )
            }
        }
        .buttonStyle(.plain)
    }
}

struct ShimmerRect: View {
    let width: CGFloat
    let height: CGFloat
    let cornerRadius: CGFloat
    @State private var phase: CGFloat = -1

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(shimmerGradient)
            .frame(width: width == .infinity ? nil : width, height: height)
            .onAppear {
                withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) { phase = 1 }
            }
    }

    private var shimmerGradient: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: Color.white.opacity(0.06), location: 0),
                .init(color: Color.white.opacity(0.12), location: 0.4 + phase * 0.5),
                .init(color: Color.white.opacity(0.06), location: 1),
            ],
            startPoint: .leading, endPoint: .trailing)
    }
}
