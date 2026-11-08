import SwiftUI

struct MiniPlayer: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        HStack(spacing: 12) {
            // Artwork
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(red: 0.2, green: 0.1, blue: 0.3))
                if let url = state.currentTrack?.imageURL.flatMap(URL.init) {
                    AsyncImage(url: url) { phase in
                        if let img = phase.image {
                            img.resizable().scaledToFill()
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                    }
                }
            }
            .frame(width: 44, height: 44)

            // Track info
            VStack(alignment: .leading, spacing: 2) {
                Text(state.currentTrack?.name ?? "Not Playing")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                Text(state.currentTrack?.artistName ?? "")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.55))
                    .lineLimit(1)
            }

            Spacer()

            // Controls
            HStack(spacing: 20) {
                BreathingButton(action: { HapticEngine.shared.light(); Task { await state.skipPrevious() } }) {
                    Image(systemName: "backward.fill")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.white)
                }
                BreathingButton(action: { HapticEngine.shared.snap(); Task { await state.togglePlayPause() } }) {
                    Image(systemName: state.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundColor(.white)
                }
                BreathingButton(action: { HapticEngine.shared.light(); Task { await state.skipNext() } }) {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.white)
                }
            }
            .padding(.trailing, 4)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(.white.opacity(0.08), lineWidth: 0.5)
        )
    }
}
