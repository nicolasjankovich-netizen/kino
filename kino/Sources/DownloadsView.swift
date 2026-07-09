import SwiftUI

/// Download-Übersicht: was die 3080 gerade komprimiert (mit %/GPU), was in der Queue wartet,
/// was gerade aufs Gerät lädt (Live-Speed), und was offline verfügbar ist.
struct DownloadsView: View {
    @EnvironmentObject var c: Cinema
    @EnvironmentObject var dl: Downloads
    @State private var playing: KItem?

    private func item(_ uid: String) -> KItem? { c.item(uid: uid) }

    private var activeUIDs: [String] { dl.progress.keys.sorted() }
    private var waitingJobs: [DLJob] { dl.queue.filter { dl.progress[$0.uid] == nil } }
    private var doneUIDs: [String]    { dl.done.sorted() }
    private var totalBytes: Int64 { doneUIDs.reduce(0) { $0 + dl.fileSize($1) } }

    /// Kompressions-Jobs vom Server (queued/compressing) — die schon aufs Gerät laden, blenden wir aus.
    private var compJobs: [FlightJob] {
        (c.flightQueue?.jobs ?? []).filter { $0.status == "compressing" || $0.status == "queued" }
    }
    private var nothing: Bool { compJobs.isEmpty && activeUIDs.isEmpty && waitingJobs.isEmpty && doneUIDs.isEmpty }

    var body: some View {
        ZStack {
            KinoBackground()
            if nothing {
                empty
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 26) {
                        header
                        if !compJobs.isEmpty {
                            section(pcHeader) { ForEach(compJobs) { compRow($0) } }
                        }
                        if !activeUIDs.isEmpty {
                            section("Lädt aufs Gerät") { ForEach(activeUIDs, id: \.self) { loadingRow($0) } }
                        }
                        if !waitingJobs.isEmpty {
                            section("In Warteschlange") { ForEach(waitingJobs) { waitingRow($0) } }
                        }
                        if !doneUIDs.isEmpty {
                            section("Auf dem Gerät · \(byteStr(totalBytes))") { ForEach(doneUIDs, id: \.self) { doneRow($0) } }
                        }
                    }
                    .padding(.horizontal, 18).padding(.top, 12).padding(.bottom, 30)
                }
            }
        }
        .task {
            await c.loadHome()
            while !Task.isCancelled {
                await c.loadFlightQueue()
                try? await Task.sleep(nanoseconds: 5_000_000_000)
            }
        }
        .fullScreenCover(item: $playing) { PlayerView(item: $0) }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Downloads").font(kTitle(30)).kChrome().foregroundStyle(cInk)
            Text("Offline ansehen — ohne Internet").font(.system(size: 13, weight: .regular)).foregroundStyle(cInk2.opacity(0.55))
        }
    }

    /// Überschrift der Kompressions-Sektion inkl. Live-GPU, falls der PC-Reporter läuft.
    private var pcHeader: String {
        if let pc = c.flightQueue?.pc, pc.online == true {
            var s = "3080 komprimiert"
            if let w = pc.gpu_watt { s += " · \(Int(w)) W" }
            if let t = pc.gpu_temp { s += " · \(Int(t))°" }
            return s
        }
        return "Kompression (3080)"
    }

    private var empty: some View {
        VStack(spacing: 14) {
            Image(systemName: "arrow.down.circle").font(.system(size: 44, weight: .light)).foregroundStyle(cAccent.opacity(0.9))
            Text("Noch keine Downloads").font(.system(size: 17, weight: .semibold)).foregroundStyle(cInk)
            Text("Tippe bei einem Film auf das ↓-Symbol,\ndann komprimiert die 3080 ihn und lädt ihn hierher.")
                .font(.system(size: 13)).foregroundStyle(cInk2.opacity(0.55)).multilineTextAlignment(.center)
        }.padding(40)
    }

    private func section(_ title: String, @ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).label2()
            content()
        }
    }

    // MARK: Kompressions-Zeile (Server-Status)
    private func compRow(_ j: FlightJob) -> some View {
        let it = j.title.flatMap { t in (c.movies + c.series).first { $0.title == t } }
        let compressing = j.status == "compressing"
        return HStack(spacing: 14) {
            thumb(it)
            VStack(alignment: .leading, spacing: 7) {
                Text(j.title ?? "—").font(.system(size: 15, weight: .medium)).foregroundStyle(cInk).lineLimit(1)
                if let pct = j.pct {
                    ProgressView(value: min(1, max(0, pct/100))).tint(cCyan)
                } else if compressing {
                    ProgressView().tint(cCyan).frame(maxWidth: .infinity, alignment: .leading)
                }
                HStack(spacing: 8) {
                    Image(systemName: compressing ? "bolt.badge.clock" : "hourglass")
                        .font(.system(size: 11)).foregroundStyle(compressing ? cCyan : cInk2.opacity(0.5))
                    Text(compRowLabel(j)).font(.system(size: 12, weight: .light)).foregroundStyle(cInk2.opacity(0.65))
                    Spacer()
                    if let q = j.quality { Text(q).font(.system(size: 11, weight: .light)).foregroundStyle(cInk2.opacity(0.4)) }
                }
            }
        }
        .padding(12).glassEffect(.regular, in: .rect(cornerRadius: 16))
    }
    private func compRowLabel(_ j: FlightJob) -> String {
        if j.status == "queued" { return "in der Warteschlange" }
        if let pct = j.pct {
            var s = "\(Int(pct)) %"
            if let e = j.eta_sec, e > 0 { s += " · noch \(mmss(e))" }
            return s
        }
        if let el = j.elapsed_sec { return "wird komprimiert · \(mmss(el)) läuft" }
        return "wird komprimiert …"
    }

    // MARK: Aktiver Download aufs Gerät
    private func loadingRow(_ uid: String) -> some View {
        let it = item(uid)
        let p = dl.progress[uid] ?? 0
        let spd = dl.speed[uid] ?? 0
        return HStack(spacing: 14) {
            thumb(it)
            VStack(alignment: .leading, spacing: 7) {
                Text(it?.title ?? dl.job(uid)?.title ?? uid).font(.system(size: 15, weight: .medium)).foregroundStyle(cInk).lineLimit(1)
                ProgressView(value: p).tint(cAccent)
                HStack(spacing: 8) {
                    Text("\(Int(p * 100)) %").font(.system(size: 12, weight: .semibold)).foregroundStyle(cAccent)
                    if spd > 0 { Text("· \(byteStr(Int64(spd)))/s").font(.system(size: 12, weight: .light)).foregroundStyle(cInk2.opacity(0.6)) }
                    Spacer()
                }
            }
            Button { dl.delete(uid) } label: {
                Image(systemName: "stop.circle").font(.system(size: 22)).foregroundStyle(cWarn)
            }.buttonStyle(.plain)
        }
        .padding(12).glassEffect(.regular, in: .rect(cornerRadius: 16))
    }

    // MARK: Wartender Download
    private func waitingRow(_ j: DLJob) -> some View {
        HStack(spacing: 14) {
            thumb(item(j.uid))
            VStack(alignment: .leading, spacing: 4) {
                Text(j.title).font(.system(size: 15, weight: .medium)).foregroundStyle(cInk).lineLimit(1)
                Label("wartet auf Download", systemImage: "hourglass").font(.system(size: 12, weight: .light)).foregroundStyle(cInk2.opacity(0.6))
            }
            Spacer()
            Button { dl.delete(j.uid) } label: {
                Image(systemName: "xmark.circle").font(.system(size: 19)).foregroundStyle(cInk2.opacity(0.5))
            }.buttonStyle(.plain)
        }
        .padding(12).glassEffect(.regular, in: .rect(cornerRadius: 16))
    }

    // MARK: Fertig
    private func doneRow(_ uid: String) -> some View {
        let it = item(uid)
        return HStack(spacing: 14) {
            thumb(it)
            VStack(alignment: .leading, spacing: 5) {
                Text(it?.title ?? uid).font(.system(size: 15, weight: .medium)).foregroundStyle(cInk).lineLimit(1)
                HStack(spacing: 8) {
                    Label(byteStr(dl.fileSize(uid)), systemImage: "internaldrive")
                        .font(.system(size: 12, weight: .light)).foregroundStyle(cInk2.opacity(0.6))
                    Label("Offline", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(cGood)
                }
            }
            Spacer()
            if let it {
                Button { playing = it } label: {
                    Image(systemName: "play.circle.fill").font(.system(size: 30)).foregroundStyle(cInk)
                }.buttonStyle(.plain)
            }
            Button { dl.delete(uid) } label: {
                Image(systemName: "trash").font(.system(size: 17)).foregroundStyle(cInk2.opacity(0.5))
            }.buttonStyle(.plain)
        }
        .padding(12).glassEffect(.regular, in: .rect(cornerRadius: 16))
    }

    private func thumb(_ it: KItem?) -> some View {
        CachedImage(url: URL(string: it?.poster ?? "")) { img in
            img.resizable().aspectRatio(2/3, contentMode: .fill)
        } placeholder: {
            RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.08))
                .overlay(Image(systemName: "film").foregroundStyle(cInk2.opacity(0.25)))
        }
        .frame(width: 46, height: 69).clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func byteStr(_ b: Int64) -> String {
        let f = ByteCountFormatter(); f.countStyle = .file
        return f.string(fromByteCount: b)
    }
    private func mmss(_ s: Int) -> String {
        let m = s / 60, sec = s % 60
        return m > 0 ? "\(m) min \(sec) s" : "\(sec) s"
    }
}
