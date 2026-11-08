import SwiftUI
import WebKit

struct RootView: View {
    @EnvironmentObject var state: AppState
    @ObservedObject var engine = SpotifyWebEngine.shared

    var body: some View {
        ZStack {
            // WebView always lives here — visible for login, 1pt hidden after
            SpotifyWebViewWrapper(webView: engine.webView)
                .frame(
                    width:  engine.webPlayerReady ? 1 : nil,
                    height: engine.webPlayerReady ? 1 : nil
                )
                .opacity(engine.webPlayerReady ? 0 : 1)
                .allowsHitTesting(!engine.webPlayerReady)
                .ignoresSafeArea()

            if !engine.webPlayerReady {
                // Login prompt overlay
                VStack(spacing: 16) {
                    Spacer()
                    Text("Sanctify")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundColor(.white)
                    Text("Sign in to Spotify above to continue")
                        .font(.system(size: 15))
                        .foregroundColor(.white.opacity(0.5))
                    Spacer().frame(height: 40)
                }
                .background(Color.black.opacity(0.0))
            } else {
                MainView()
                    .environmentObject(state)
                    .transition(.opacity)
            }
        }
        .background(Color.black.ignoresSafeArea())
        .animation(.easeInOut(duration: 0.4), value: engine.webPlayerReady)
    }
}

struct SpotifyWebViewWrapper: UIViewRepresentable {
    let webView: WKWebView
    func makeUIView(context: Context) -> WKWebView { webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

struct MainView: View {
    @EnvironmentObject var state: AppState
    @State private var selectedTab = 0
    @State private var showNowPlaying = false

    var body: some View {
        ZStack(alignment: .bottom) {
            TabContent(selectedTab: selectedTab)

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
        ("Home",    "house",           "house.fill"),
        ("Search",  "magnifyingglass", "magnifyingglass"),
        ("Library", "music.note.list", "music.note.list"),
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
