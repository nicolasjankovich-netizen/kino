import SwiftUI
import AVKit
import Darwin

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
    @AppStorage("playerDebugOverlay") private var debugOverlay = false   // Punkt 6, per Debug-Screen
    @State private var stats: [String: String] = [:]

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let player {
                VideoSurface(player: player,
                             startFraction: acc.progress(item.uid),
                             onProgress: { acc.setProgress(item.uid, $0) })
                    .ignoresSafeArea()
                if debugOverlay {
                    VStack { HStack { debugPanel; Spacer() }; Spacer() }
                        .allowsHitTesting(false).ignoresSafeArea()
                }
            } else {
                CachedImage(url: URL(string: item.hero ?? "")) { img in
                    img.resizable().aspectRatio(contentMode: .fit).opacity(0.35)
                } placeholder: { Color.black }.ignoresSafeArea()
                VStack(spacing: 14) {
                    HStack { Button { dismiss() } label: {
                        Image(systemName: "chevron.down").font(.system(size: 18, weight: .semibold)).foregroundStyle(.white).padding(14)
                    }; Spacer() }
                    Spacer()
                    if loading { ProgressView().tint(.white).scaleEffect(1.3); Text(item.title).font(.system(size: 16, weight: .semibold)).foregroundStyle(.white).padding(.top, 8); Text("Wird geladen …").font(.system(size: 13)).foregroundStyle(.white.opacity(0.55)) }
                    if failed {
                        Image(systemName: "exclamationmark.triangle").font(.system(size: 30)).foregroundStyle(cWarn)
                        Text("Konnte \(item.title) nicht abspielen").font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                        Text(errText ?? "Ist der Film in der Bibliothek? Server erreichbar?")
                            .font(.system(size: 12)).foregroundStyle(.white.opacity(0.6))
                            .multilineTextAlignment(.center).padding(.horizontal, 30)
                        Button { Task { await start() } } label: { Text("Erneut versuchen").font(.system(size: 15, weight: .semibold)).foregroundStyle(.white).padding(.horizontal, 24).padding(.vertical, 10).background(RoundedRectangle(cornerRadius: 12).fill(cAccent)) }.padding(.top, 6)
                    }
                    Spacer()
                }
            }
        }
        .task { await start() }
        .task(id: debugOverlay) {
            guard debugOverlay else { return }
            while !Task.isCancelled && debugOverlay {   // Live-Werte ~1×/s aktualisieren
                updateStats()
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
        .onDisappear { player?.pause() }
    }

    // MARK: – Debug-Overlay (Punkt 6)
    private let statOrder = ["Auflösung", "Bitrate (Stream)", "Bitrate (Netz)", "Video-Codec", "Audio-Codec", "Puffer", "CPU (App)"]

    private var debugPanel: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("DEBUG").font(.system(size: 9, weight: .bold)).tracking(2).foregroundStyle(cCyan)
            ForEach(statOrder, id: \.self) { k in
                if let v = stats[k] {
                    HStack(spacing: 6) {
                        Text(k).foregroundStyle(.white.opacity(0.6))
                        Spacer(minLength: 10)
                        Text(v).foregroundStyle(.white)
                    }
                }
            }
        }
        .font(.system(size: 11, design: .monospaced))
        .padding(10).frame(width: 230, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(.black.opacity(0.55)))
        .padding(.top, 58).padding(.leading, 14)
    }

    private func updateStats() {
        guard let it = player?.currentItem else { return }
        var s: [String: String] = [:]
        let sz = it.presentationSize
        if sz.width > 0 { s["Auflösung"] = "\(Int(sz.width))×\(Int(sz.height))" }
        if let ev = it.accessLog()?.events.last {
            if ev.indicatedBitrate > 0 { s["Bitrate (Stream)"] = fmtBitrate(ev.indicatedBitrate) }
            if ev.observedBitrate > 0 { s["Bitrate (Netz)"] = fmtBitrate(ev.observedBitrate) }
        }
        if let r = it.loadedTimeRanges.first?.timeRangeValue {
            let end = CMTimeGetSeconds(r.start) + CMTimeGetSeconds(r.duration)
            let cur = CMTimeGetSeconds(it.currentTime())
            if end.isFinite && cur.isFinite { s["Puffer"] = String(format: "%.1f s", max(0, end - cur)) }
        }
        let (v, a) = codecs(it)
        if let v { s["Video-Codec"] = v }
        if let a { s["Audio-Codec"] = a }
        s["CPU (App)"] = String(format: "%.0f %%", appCPUUsage())
        stats = s
    }

    private func fmtBitrate(_ b: Double) -> String {
        b >= 1_000_000 ? String(format: "%.1f Mbit/s", b / 1_000_000) : String(format: "%.0f kbit/s", b / 1000)
    }

    private func codecs(_ it: AVPlayerItem) -> (String?, String?) {
        var v: String?; var a: String?
        for t in it.tracks {
            guard let at = t.assetTrack,
                  let fmts = at.formatDescriptions as? [CMFormatDescription], let f = fmts.first else { continue }
            let sub = fourCC(CMFormatDescriptionGetMediaSubType(f))
            switch CMFormatDescriptionGetMediaType(f) {
            case kCMMediaType_Video: v = sub
            case kCMMediaType_Audio: a = sub
            default: break
            }
        }
        return (v, a)
    }
    private func fourCC(_ c: FourCharCode) -> String {
        let bytes = [UInt8((c >> 24) & 0xff), UInt8((c >> 16) & 0xff), UInt8((c >> 8) & 0xff), UInt8(c & 0xff)]
        return (String(bytes: bytes, encoding: .ascii) ?? "?").trimmingCharacters(in: .whitespaces)
    }

    /// CPU-Auslastung dieses App-Prozesses (Summe aller Threads, in %).
    private func appCPUUsage() -> Double {
        var threadList: thread_act_array_t?
        var threadCount: mach_msg_type_number_t = 0
        guard task_threads(mach_task_self_, &threadList, &threadCount) == KERN_SUCCESS, let threads = threadList else { return 0 }
        defer { vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: threads)), vm_size_t(Int(threadCount) * MemoryLayout<thread_t>.stride)) }
        var total = 0.0
        for i in 0..<Int(threadCount) {
            var info = thread_basic_info()
            var count = mach_msg_type_number_t(MemoryLayout<thread_basic_info_data_t>.size / MemoryLayout<integer_t>.size)
            let kr = withUnsafeMutablePointer(to: &info) {
                $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                    thread_info(threads[i], thread_flavor_t(THREAD_BASIC_INFO), $0, &count)
                }
            }
            if kr == KERN_SUCCESS, (info.flags & TH_FLAGS_IDLE) == 0 {
                total += Double(info.cpu_usage) / Double(TH_USAGE_SCALE) * 100.0
            }
        }
        return total
    }

    private func start() async {
        loading = true; failed = false; errText = nil
        // Audio-Session AKTIV schalten: sonst steuern die Lautstärke-Tasten den Klingelton
        // (kein Medien-HUD) und man hört nichts. `.playback` ignoriert auch den Stumm-Schalter.
        let sess = AVAudioSession.sharedInstance()
        do {
            try sess.setCategory(.playback, mode: .moviePlayback, options: [])
            try sess.setActive(true, options: [])
        } catch {
            // Fallback ohne Optionen
            try? sess.setCategory(.playback)
            try? sess.setActive(true)
        }
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
        p.isMuted = false
        p.volume = 1.0
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
