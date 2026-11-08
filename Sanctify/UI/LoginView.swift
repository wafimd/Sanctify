import SwiftUI
import WebKit

struct LoginView: View {
    @EnvironmentObject var state: AppState
    @ObservedObject var engine = SpotifyWebEngine.shared

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 24) {
                Spacer()
                Image(systemName: "music.note")
                    .font(.system(size: 56, weight: .light))
                    .foregroundColor(.white)
                Text("Sanctify")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundColor(.white)
                Text("Sign in to Spotify to continue")
                    .font(.system(size: 16))
                    .foregroundColor(.white.opacity(0.55))
                Spacer()
                // Embedded WKWebView for login
                SpotifyWebView(webView: engine.webView)
                    .frame(height: 480)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .padding(.horizontal, 16)
                    .padding(.bottom, 32)
            }
        }
    }
}

struct SpotifyWebView: UIViewRepresentable {
    let webView: WKWebView
    func makeUIView(context: Context) -> WKWebView { webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
