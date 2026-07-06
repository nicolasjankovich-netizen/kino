import SwiftUI

/// Download-Übersicht: was gerade lädt (mit Live-Geschwindigkeit + Fortschritt)
/// und was offline auf dem Gerät liegt (Größe, abspielen, löschen).
struct DownloadsView: View {
    @EnvironmentObject var c: Cinema
    @EnvironmentObject var dl: Downloads
    @State private var playing: KItem?

    /// uid → KItem aus der geladenen Bibliothek.
    private func item(_ uid: String) -> KItem? { c.item(uid: uid) }

    private var loadingUIDs: [String] { dl.progress.keys.sorted() }
    private var doneUIDs: [String]    { dl.done.sorted() }

    private var totalBytes: Int64 { doneUIDs.reduce(0) { $0 + dl.fileSize($1) } }

    var body: some View {
        ZStack {
            KinoBackground()
            if loadingUIDs.isEmpty && doneUIDs.isEmpty {
                empty
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 26) {
                        header
                        if !loadingUIDs.isEmpty {
                            section("Lädt gerade") {
                                ForEach(loadingUIDs, id: \.self) { uid in loadingRow(uid) }
                            }
                        }
                        if !doneUIDs.isEmpty {
                            section("Auf dem Gerät · \(byteStr(totalBytes))") {
                                ForEach(doneUIDs, id: \.self) { uid in doneRow(uid) }
                            }
                        }
                    }
                    .padding(.horizontal, 18).padding(.top, 12).padding(.bottom, 30)
                }
            }
        }
        .task { await c.loadHome() }               // Titel/Poster für die uids sicherstellen
        .fullScreenCover(item: $playing) { PlayerView(item: $0) }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Downloads").font(.system(size: 30, weight: .bold)).foregroundStyle(.white)
            Text("Offline ansehen — ohne Internet").font(.system(size: 13, weight: .regular)).foregroundStyle(.white.opacity(0.55))
        }
    }

    private var empty: some View {
        VStack(spacing: 14) {
            Image(systemName: "arrow.down.circle").font(.system(size: 44, weight: .light)).foregroundStyle(cAccent.opacity(0.9))
            Text("Noch keine Downloads").font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
            Text("Tippe bei einem Film auf das ↓-Symbol,\ndann kannst du ihn hier offline schauen.")
                .font(.system(size: 13)).foregroundStyle(.white.opacity(0.55)).multilineTextAlignment(.center)
        }.padding(40)
    }

    private func section(_ title: String, @ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).label2()
            content()
        }
    }

    // MARK: Zeilen
    private func loadingRow(_ uid: String) -> some View {
        let it = item(uid)
        let p = dl.progress[uid] ?? 0
        let spd = dl.speed[uid] ?? 0
        return HStack(spacing: 14) {
            thumb(it)
            VStack(alignment: .leading, spacing: 7) {
                Text(it?.title ?? uid).font(.system(size: 15, weight: .medium)).foregroundStyle(.white).lineLimit(1)
                ProgressView(value: p).tint(cAccent)
                HStack(spacing: 8) {
                    Text("\(Int(p * 100)) %").font(.system(size: 12, weight: .semibold)).foregroundStyle(cAccent)
                    if spd > 0 {
                        Text("· \(byteStr(Int64(spd)))/s").font(.system(size: 12, weight: .light)).foregroundStyle(.white.opacity(0.6))
                    }
                    Spacer()
                }
            }
            Button { dl.delete(uid) } label: {
                Image(systemName: "stop.circle").font(.system(size: 22)).foregroundStyle(cWarn)
            }.buttonStyle(.plain)
        }
        .padding(12).glassEffect(.regular, in: .rect(cornerRadius: 16))
    }

    private func doneRow(_ uid: String) -> some View {
        let it = item(uid)
        return HStack(spacing: 14) {
            thumb(it)
            VStack(alignment: .leading, spacing: 5) {
                Text(it?.title ?? uid).font(.system(size: 15, weight: .medium)).foregroundStyle(.white).lineLimit(1)
                HStack(spacing: 8) {
                    Label(byteStr(dl.fileSize(uid)), systemImage: "internaldrive")
                        .font(.system(size: 12, weight: .light)).foregroundStyle(.white.opacity(0.6))
                    Label("Offline", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(cGood)
                }
            }
            Spacer()
            if let it {
                Button { playing = it } label: {
                    Image(systemName: "play.circle.fill").font(.system(size: 30)).foregroundStyle(.white)
                }.buttonStyle(.plain)
            }
            Button { dl.delete(uid) } label: {
                Image(systemName: "trash").font(.system(size: 17)).foregroundStyle(.white.opacity(0.5))
            }.buttonStyle(.plain)
        }
        .padding(12).glassEffect(.regular, in: .rect(cornerRadius: 16))
    }

    private func thumb(_ it: KItem?) -> some View {
        AsyncImage(url: URL(string: it?.poster ?? "")) { img in
            img.resizable().aspectRatio(2/3, contentMode: .fill)
        } placeholder: {
            RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.08))
                .overlay(Image(systemName: "film").foregroundStyle(.white.opacity(0.25)))
        }
        .frame(width: 46, height: 69).clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func byteStr(_ b: Int64) -> String {
        let f = ByteCountFormatter(); f.countStyle = .file
        return f.string(fromByteCount: b)
    }
}
