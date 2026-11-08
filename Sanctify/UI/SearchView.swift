import SwiftUI

struct SearchView: View {
    @EnvironmentObject var state: AppState
    @State private var query = ""
    @State private var results: [STrack] = []
    @State private var searching = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.white.opacity(0.5))
                TextField("Songs, artists, albums", text: $query)
                    .foregroundColor(.white)
                    .tint(.white)
                    .focused($focused)
                    .submitLabel(.search)
                    .onSubmit { Task { await runSearch() } }
                if !query.isEmpty {
                    Button { query = ""; results = [] } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.white.opacity(0.4))
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(.horizontal, 20)
            .padding(.top, 60)
            .padding(.bottom, 16)

            // Results
            if searching {
                ProgressView().tint(.white).padding(.top, 40)
            } else if results.isEmpty && !query.isEmpty {
                Text("No results").foregroundColor(.white.opacity(0.4)).padding(.top, 40)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(results) { track in
                            TrackRow(track: track)
                                .onTapGesture {
                                    HapticEngine.shared.medium()
                                    Task { await state.play(track: track) }
                                }
                        }
                    }
                    .padding(.bottom, 120)
                }
            }
            Spacer()
        }
        .background(Color.black.ignoresSafeArea())
        .onChange(of: query) { _, _ in
            Task {
                try? await Task.sleep(nanoseconds: 400_000_000)
                guard !query.isEmpty else { results = []; return }
                await runSearch()
            }
        }
    }

    private func runSearch() async {
        guard !query.isEmpty else { return }
        searching = true
        results = await state.search(query)
        searching = false
    }
}

struct TrackRow: View {
    let track: STrack

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color(red: 0.15, green: 0.08, blue: 0.25))
                if let url = track.imageURL.flatMap(URL.init) {
                    AsyncImage(url: url) { phase in
                        if let img = phase.image {
                            img.resizable().scaledToFill()
                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        }
                    }
                }
            }
            .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 3) {
                Text(track.name)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.white)
                    .lineLimit(1)
                Text(track.artistName)
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.5))
                    .lineLimit(1)
            }
            Spacer()
            Text(formatMs(track.durationMs))
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.35))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    private func formatMs(_ ms: Int) -> String {
        let s = ms / 1000
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
