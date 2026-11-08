import SwiftUI

struct SetupView: View {
    @State private var clientId = ""
    @FocusState private var focused: Bool

    var body: some View {
        ZStack {
            LiquidBackground()

            VStack(spacing: 0) {
                Spacer()

                // Logo area
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
                    Text("Enter your Spotify Client ID to continue")
                        .font(.system(size: 15))
                        .foregroundColor(.white.opacity(0.55))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }
                .padding(.bottom, 52)

                // Input
                VStack(spacing: 12) {
                    TextField("Client ID", text: $clientId)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(.horizontal, 18)
                        .padding(.vertical, 14)
                        .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .foregroundColor(.white)
                        .tint(.white)
                        .focused($focused)
                        .padding(.horizontal, 28)

                    Text("Get your Client ID from developer.spotify.com")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.35))
                }
                .padding(.bottom, 28)

                // Continue button
                Button {
                    let trimmed = clientId.trimmingCharacters(in: .whitespaces)
                    guard !trimmed.isEmpty else { return }
                    focused = false
                    SpotifyAuth.shared.defaults.set(trimmed, forKey: "spm_client_id")
                    SpotifyAuth.shared.clientId = trimmed
                } label: {
                    Text("Continue")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            LinearGradient(
                                colors: clientId.trimmingCharacters(in: .whitespaces).isEmpty
                                    ? [Color.white.opacity(0.15), Color.white.opacity(0.15)]
                                    : [Color(red: 0.85, green: 0.1, blue: 0.3), Color(red: 0.6, green: 0.05, blue: 0.5)],
                                startPoint: .leading, endPoint: .trailing),
                            in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .disabled(clientId.trimmingCharacters(in: .whitespaces).isEmpty)
                .padding(.horizontal, 28)

                Spacer()
                Spacer()
            }
        }
        .onTapGesture { focused = false }
    }
}
