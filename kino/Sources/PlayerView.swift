import SwiftUI
import AVKit

/// Echter Media-Player: streamt HLS von `/api/media/stream` (lokal hohe Bitrate, unterwegs
/// komprimiert), native Controls (Untertitel/Audio-Spuren/Seek/PiP), Resume + Fortschritt speichern.
struct PlayerView: View {
    let item: KItem
    @EnvironmentObject var acc: Accounts
    @EnvironmentObject var c: Cinema
    @EnvironmentObject var dl: Downloads
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?
    @State private var loading = true
    @State private var failed = false
    @State private var errText: String?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let player {
                VideoSurface(player: player,
                             startFraction: acc.progress(item.uid),
                             onProgress: { acc.setProgress(item.uid, $0) })
                    .ignoresSafeArea()
            } else {
                AsyncImage(url: URL(string: item.hero ?? "")) { img in
                    img.resizable().aspectRatio(contentMode: .fit).opacity(0.35)
                } placeholder: { Color.black }.ignoresSafeArea()
                VStack(spacing: 14) {
                    HStack { Button { dismiss() } label: {
                        Image(systemName: "chevron.down").font(.system(size: 18, weight: .semibold)).foregroundStyle(.white).padding(14)
                    }; Spacer() }
                    Spacer()
                    if loading { ProgressView().tint(.white).scaleEffect(1.3); Text(item.title).font(.system(size: 15, weight: .light)).foregroundStyle(.white).padding(.top, 8); Text("Stream wird vorbereitet …").label2() }
                    if failed {
                        Image(systemName: "exclamationmark.triangle").font(.system(size: 30)).foregroundStyle(cWarn)
                        Text("Konnte \(item.title) nicht abspielen").font(.system(size: 14, weight: .light)).foregroundStyle(.white)
                        Text(errText ?? "Ist der Film in Jellyfin? Server erreichbar?")
                            .font(.system(size: 11, weight: .light)).foregroundStyle(.white.opacity(0.6))
                            .multilineTextAlignment(.center).padding(.horizontal, 30)
                        Button { Task { await start() } } label: { Text("erneut").foregroundStyle(.black).padding(.horizontal, 24).padding(.vertical, 10).background(Capsule().fill(cAccent)) }.padding(.top, 6)
                    }
                    Spacer()
                }
            }
        }
        .task { await start() }
        .onDisappear { player?.pause() }
    }

    private func start() async {
        loading = true; failed = false; errText = nil
        // Audio auch im Stumm-Schalter-Modus
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)
        let url: URL
        if let local = dl.localURL(item.uid) {
            url = local                                   // offline abspielen (heruntergeladen)
        } else if let streamed = await c.streamURL(for: item) {
            url = streamed
        } else {
            loading = false; failed = true
            errText = "Kein Stream gefunden — ist \(item.title) in Jellyfin?"
            return
        }
        let p = AVPlayer(url: url)
        p.allowsExternalPlayback = true
        player = p; loading = false
        p.play()
        // Status beobachten → echten Fehler anzeigen (Diagnose)
        for _ in 0..<40 {
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard let it = p.currentItem else { continue }
            if it.status == .readyToPlay { return }
            if it.status == .failed {
                errText = (it.error?.localizedDescription ?? "Wiedergabe fehlgeschlagen") + " · Host: " + (url.host ?? "?")
                failed = true; player = nil; return
            }
        }
        if p.currentItem?.status != .readyToPlay {
            errText = "Stream nicht erreichbar (Host: \(url.host ?? "?")) — Tailscale/WLAN prüfen"
            failed = true; player = nil
        }
    }
}

/// AVPlayerViewController mit Fortschritts-Beobachter + Resume-Seek.
private struct VideoSurface: UIViewControllerRepresentable {
    let player: AVPlayer
    let startFraction: Double
    let onProgress: (Double) -> Void

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let vc = AVPlayerViewController()
        vc.player = player
        vc.allowsPictureInPicturePlayback = true
        vc.videoGravity = .resizeAspect
        context.coordinator.attach(player, startFraction: startFraction, onProgress: onProgress)
        return vc
    }
    func updateUIViewController(_ vc: AVPlayerViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        private var token: Any?
        private var seeked = false
        func attach(_ player: AVPlayer, startFraction: Double, onProgress: @escaping (Double) -> Void) {
            token = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 5, preferredTimescale: 1), queue: .main) { [weak player] t in
                guard let dur = player?.currentItem?.duration.seconds, dur.isFinite, dur > 1 else { return }
                if !self.seeked {
                    self.seeked = true
                    if startFraction > 0.02 && startFraction < 0.97 {
                        player?.seek(to: CMTime(seconds: startFraction * dur, preferredTimescale: 1))
                    }
                }
                onProgress(min(1, max(0, t.seconds / dur)))
            }
        }
        deinit { token = nil }
    }
}
