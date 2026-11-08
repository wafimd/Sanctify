import SwiftUI

struct RootView: View {
    @EnvironmentObject var state: AppState
    @ObservedObject var engine = SpotifyWebEngine.shared

    var body: some View {
        if !engine.isLoggedIn && !engine.webPlayerReady {
            LoginView()
        } else {
            MainView()
        }
    }
}

struct MainView: View {
    @EnvironmentObject var state: AppState
    @State private var selectedTab = 0
    @State private var showNowPlaying = false

    var body: some View {
        ZStack(alignment: .bottom) {
            // Tab content
            TabContent(selectedTab: selectedTab)

            // Mini player + tab bar stack
            VStack(spacing: 8) {
                if state.currentTrack != nil {
                    MiniPlayer()
                        .padding(.horizontal, 12)
                        .onTapGesture {
                            HapticEngine.shared.medium()
                            showNowPlaying = true
                        }
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                // Tab bar
                HStack(spacing: 0) {
                    ForEach(tabs.indices, id: \.self) { i in
                        Button {
                            HapticEngine.shared.light()
                            selectedTab = i
                        } label: {
                            VStack(spacing: 4) {
                                Image(systemName: selectedTab == i ? tabs[i].activeIcon : tabs[i].icon)
                                    .font(.system(size: 22))
                                Text(tabs[i].label)
                                    .font(.system(size: 10, weight: .medium))
                            }
                            .foregroundColor(selectedTab == i ? .white : .white.opacity(0.4))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .glassEffect(in: Capsule())
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }
        }
        .background(Color.black.ignoresSafeArea())
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: state.currentTrack?.id)
        .fullScreenCover(isPresented: $showNowPlaying) {
            NowPlayingView(isPresented: $showNowPlaying)
                .environmentObject(state)
        }
    }

    private let tabs: [(label: String, icon: String, activeIcon: String)] = [
        ("Home",    "house",            "house.fill"),
        ("Search",  "magnifyingglass",  "magnifyingglass"),
        ("Library", "music.note.list",  "music.note.list"),
    ]
}

struct TabContent: View {
    @EnvironmentObject var state: AppState
    let selectedTab: Int

    var body: some View {
        switch selectedTab {
        case 0: HomeView()
        case 1: SearchView()
        case 2: LibraryView()
        default: HomeView()
        }
    }
}
