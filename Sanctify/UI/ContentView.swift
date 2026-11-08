import SwiftUI
import WebKit

struct RootView: View {
    @EnvironmentObject var state: AppState
    @ObservedObject var auth = SpotifyAuth.shared
    @ObservedObject var engine = SpotifyWebEngine.shared

    var body: some View {
        ZStack {
            // Web player always lives here, hidden once ready — audio engine
            SpotifyWebViewWrapper(webView: engine.webView)
                .frame(
                    width:  engine.webPlayerReady ? 1 : 0,
                    height: engine.webPlayerReady ? 1 : 0
                )
                .opacity(0)
                .allowsHitTesting(false)

            if !auth.isAuthenticated {
                LoginView()
                    .transition(.opacity)
            } else if !engine.webPlayerReady {
                // Authenticated but web player still loading
                ZStack {
                    Color.black.ignoresSafeArea()
                    VStack(spacing: 16) {
                        ProgressView()
                            .tint(.white)
                        Text("Loading player…")
                            .font(.system(size: 14))
                            .foregroundColor(.white.opacity(0.5))
                    }
                }
                .transition(.opacity)
            } else {
                MainView()
                    .environmentObject(state)
                    .transition(.opacity)
            }
        }
        .background(Color.black.ignoresSafeArea())
        .animation(.easeInOut(duration: 0.4), value: auth.isAuthenticated)
        .animation(.easeInOut(duration: 0.4), value: engine.webPlayerReady)
    }
}

struct SpotifyWebViewWrapper: UIViewRepresentable {
    let webView: WKWebView
    func makeUIView(context: Context) -> WKWebView { webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

struct LoginView: View {
    @ObservedObject var auth = SpotifyAuth.shared

    var body: some View {
        ZStack {
            LiquidBackground()

            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .fill(LinearGradient(
                                colors: [Color(red: 0.85, green: 0.1, blue: 0.3),
                                         Color(red: 0.6, green: 0.05, blue: 0.5)],
                                startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 90, height: 90)
                        Image(systemName: "music.note")
                            .font(.system(size: 42, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    Text("Sanctify")
                        .font(.system(size: 34, weight: .bold))
                        .foregroundColor(.white)
                    Text("Connect your Spotify account to continue")
                        .font(.system(size: 15))
                        .foregroundColor(.white.opacity(0.55))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }
                .padding(.bottom, 52)

                if let error = auth.authError {
                    Text(error)
                        .font(.system(size: 13))
                        .foregroundColor(Color(red: 1, green: 0.4, blue: 0.4))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                        .padding(.bottom, 20)
                }

                Button {
                    auth.signIn()
                } label: {
                    HStack(spacing: 10) {
                        if auth.isAuthenticating {
                            ProgressView().tint(.white).scaleEffect(0.85)
                        }
                        Text(auth.isAuthenticating ? "Connecting…" : "Sign in with Spotify")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        LinearGradient(
                            colors: [Color(red: 0.85, green: 0.1, blue: 0.3),
                                     Color(red: 0.6, green: 0.05, blue: 0.5)],
                            startPoint: .leading, endPoint: .trailing),
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .disabled(auth.isAuthenticating)
                .padding(.horizontal, 28)
                .padding(.bottom, 16)

                Button {
                    auth.signOut()
                } label: {
                    Text("Use a different account")
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.35))
                }

                Spacer()
                Spacer()
            }
        }
    }
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
