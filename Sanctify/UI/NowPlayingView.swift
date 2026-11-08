import SwiftUI

struct NowPlayingView: View {
    @EnvironmentObject var state: AppState
    @Binding var isPresented: Bool
    @State private var dragOffset: CGFloat = 0
    @State private var showContent = false

    var body: some View {
        ZStack {
            LiquidBackground()

            VStack(spacing: 0) {
                // Drag pill
                Capsule()
                    .fill(.white.opacity(0.3))
                    .frame(width: 36, height: 4)
                    .padding(.top, 60)
                    .padding(.bottom, 28)

                // Artwork
                artworkView
                    .padding(.bottom, 36)

                // Track info + controls
                VStack(spacing: 0) {
                    trackInfo
                    progressBar
                    transport
                    volumeBar
                }
                .opacity(showContent ? 1 : 0)
                .offset(y: showContent ? 0 : 24)
                .animation(.spring(response: 0.5, dampingFraction: 0.82).delay(0.18), value: showContent)

                Spacer()
            }
        }
        .offset(y: dragOffset)
        .gesture(dragGesture)
        .onAppear {
            dragOffset = 0
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { showContent = true }
        }
        .onDisappear { showContent = false }
    }

    // MARK: - Subviews

    private var artworkView: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(LinearGradient(
                    colors: [Color(red: 0.28, green: 0.12, blue: 0.42),
                             Color(red: 0.18, green: 0.08, blue: 0.28)],
                    startPoint: .topLeading, endPoint: .bottomTrailing))
            if let url = state.currentTrack?.imageURL.flatMap(URL.init) {
                AsyncImage(url: url) { phase in
                    if let img = phase.image {
                        img.resizable().scaledToFill()
                            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    }
                }
            }
        }
        .frame(width: 280, height: 280)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: Color(red: 0.4, green: 0.0, blue: 0.6).opacity(0.5), radius: 40, y: 20)
    }

    private var trackInfo: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(state.currentTrack?.name ?? "Not Playing")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                Text(state.currentTrack?.artistName ?? "")
                    .font(.system(size: 15))
                    .foregroundColor(.white.opacity(0.55))
                    .lineLimit(1)
            }
            Spacer()
            BreathingButton(action: { HapticEngine.shared.light() }) {
                Image(systemName: "heart")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundColor(.white.opacity(0.65))
            }
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 28)
    }

    private var progressBar: some View {
        VStack(spacing: 6) {
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.15)).frame(height: 4)
                let progress = progressFraction
                GeometryReader { geo in
                    Capsule().fill(.white).frame(width: geo.size.width * progress, height: 4)
                }.frame(height: 4)
            }
            HStack {
                Text(formatMs(state.progressMs))
                    .font(.system(size: 11)).foregroundColor(.white.opacity(0.45))
                Spacer()
                Text("-\(formatMs((state.currentTrack?.durationMs ?? 0) - state.progressMs))")
                    .font(.system(size: 11)).foregroundColor(.white.opacity(0.45))
            }
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 32)
    }

    private var transport: some View {
        HStack(spacing: 44) {
            BreathingButton(action: { HapticEngine.shared.light(); Task { await state.skipPrevious() } }) {
                Image(systemName: "backward.fill")
                    .font(.system(size: 26, weight: .medium)).foregroundColor(.white)
            }
            BreathingButton(action: { HapticEngine.shared.snap(); Task { await state.togglePlayPause() } }) {
                Image(systemName: state.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 46, weight: .medium)).foregroundColor(.white)
                    .frame(width: 60, height: 60)
            }
            BreathingButton(action: { HapticEngine.shared.light(); Task { await state.skipNext() } }) {
                Image(systemName: "forward.fill")
                    .font(.system(size: 26, weight: .medium)).foregroundColor(.white)
            }
        }
        .padding(.bottom, 40)
    }

    private var volumeBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "speaker.fill")
                .font(.system(size: 13)).foregroundColor(.white.opacity(0.4))
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.2)).frame(height: 4)
                Capsule().fill(.white).frame(width: 160, height: 4)
            }
            Image(systemName: "speaker.wave.3.fill")
                .font(.system(size: 13)).foregroundColor(.white.opacity(0.4))
        }
        .padding(.horizontal, 28)
    }

    // MARK: - Gesture

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { v in
                let t = v.translation.height
                dragOffset = t > 0 ? t * 0.6 : t * 0.08
            }
            .onEnded { v in
                if v.predictedEndTranslation.height > 300 || v.translation.height > 100 {
                    HapticEngine.shared.light()
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        dragOffset = 1000
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { isPresented = false }
                } else {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) { dragOffset = 0 }
                }
            }
    }

    // MARK: - Helpers

    private var progressFraction: CGFloat {
        let dur = state.currentTrack?.durationMs ?? 0
        guard dur > 0 else { return 0 }
        return min(CGFloat(state.progressMs) / CGFloat(dur), 1)
    }

    private func formatMs(_ ms: Int) -> String {
        let s = ms / 1000
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

struct LiquidBackground: View {
    @State private var phase: Double = 0

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.38, green: 0.08, blue: 0.52),
                         Color(red: 0.55, green: 0.08, blue: 0.38),
                         Color(red: 0.14, green: 0.06, blue: 0.26),
                         Color.black],
                startPoint: UnitPoint(x: 0.1 + 0.3 * phase, y: 0),
                endPoint:   UnitPoint(x: 0.9 - 0.2 * phase, y: 1))
            RadialGradient(
                colors: [Color(red: 0.65, green: 0.1, blue: 0.55).opacity(0.35), .clear],
                center: UnitPoint(x: 0.4 + 0.25 * phase, y: 0.22 + 0.1 * phase),
                startRadius: 0, endRadius: 320)
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.easeInOut(duration: 5.5).repeatForever(autoreverses: true)) { phase = 1.0 }
        }
    }
}
