import SwiftUI

/// Apple-TV-artige Startseite: Hero-Banner + horizontal scrollende Reihen
/// (Weiterschauen aus dem Account-State, Favoriten, Filme, Serien).
struct HomeView: View {
    @EnvironmentObject var c: Cinema
    @EnvironmentObject var acc: Accounts
    @Environment(\.horizontalSizeClass) private var hSize
    @State private var selected: KItem?

    private var compact: Bool { hSize == .compact }         // iPhone Hochkant
    private var heroHeight: CGFloat { compact ? 240 : 360 }
    private var tileW: CGFloat { compact ? 116 : 150 }

    private var pool: [KItem] { c.movies + c.series }
    private var continueRow: [KItem] { acc.continueWatching(pool) }
    private var favRow: [KItem] { acc.favorites(pool) }

    /// Genre-Reihen (Kategorien wie bei Streaming-Apps), nach Häufigkeit sortiert.
    private var genreRows: [(name: String, items: [KItem])] {
        var byGenre: [String: [KItem]] = [:]
        for it in pool { for g in (it.genres ?? []) { byGenre[g, default: []].append(it) } }
        return byGenre.filter { $0.value.count >= 2 }
            .sorted { $0.value.count > $1.value.count }
            .prefix(10)
            .map { (name: $0.key, items: $0.value) }
    }

    @State private var heroIndex = 0

    /// Rotierende Aufmacher: bevorzugt verfügbare Titel MIT 16:9-Backdrop.
    private var heroPicks: [KItem] {
        let withBg = pool.filter { $0.backdrop != nil }
        let avail = withBg.filter { $0.hasFile == true }
        let base = avail.isEmpty ? (withBg.isEmpty ? pool : withBg) : avail
        return Array(base.prefix(8))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                header
                if !heroPicks.isEmpty { heroCarousel }

                if !continueRow.isEmpty { row("Weiter ansehen", continueRow, showProgress: true) }
                if !favRow.isEmpty { row("Favoriten", favRow) }
                if !c.movies.isEmpty { row("Filme", Array(c.movies.prefix(40))) }
                if !c.series.isEmpty { row("Serien", Array(c.series.prefix(40))) }
                ForEach(genreRows, id: \.name) { g in
                    row(g.name, Array(g.items.prefix(30)))
                }

                if pool.isEmpty {
                    Text(c.busy ? "Lädt …" : "Bibliothek leer").label2()
                        .frame(maxWidth: .infinity).padding(.top, 60)
                }
            }
            .padding(.bottom, 24)
        }
        .background(KinoBackground())
        .refreshable { await c.loadHome(force: true) }
        .task { await c.loadHome() }
        .sheet(item: $selected) { DetailView(item: $0) }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            Text("Kino").font(.system(size: 26, weight: .bold)).foregroundStyle(.white)
            Spacer()
            if c.busy { ProgressView().tint(.white) }
            if let n = acc.current?.name {
                Text(n).font(.system(size: 14, weight: .medium)).foregroundStyle(.white.opacity(0.7))
            }
            Button { acc.switchProfile() } label: {
                Image(systemName: "person.crop.circle").font(.system(size: 23)).foregroundStyle(.white.opacity(0.85))
            }.buttonStyle(.plain)
        }.padding(.horizontal, 20).padding(.top, 8)
    }

    /// Vollbreiter, rotierender Kino-Aufmacher (mehrere Titel, auto-wechselnd).
    private var currentHero: KItem? {
        guard !heroPicks.isEmpty else { return nil }
        return heroPicks[heroIndex % heroPicks.count]
    }
    private var heroCarousel: some View {
        ZStack {
            if let h = currentHero {
                heroBanner(h).id(h.uid).transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity).frame(height: heroHeight).clipped()
        .onReceive(Timer.publish(every: 6, on: .main, in: .common).autoconnect()) { _ in
            guard heroPicks.count > 1 else { return }
            withAnimation(.easeInOut(duration: 0.8)) { heroIndex += 1 }
        }
    }

    private func heroBanner(_ h: KItem) -> some View {
        Button { selected = h } label: {
            ZStack(alignment: .bottomLeading) {
                AsyncImage(url: URL(string: h.hero ?? "")) { img in
                    img.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    Rectangle().fill(.white.opacity(0.06))
                }
                .frame(maxWidth: .infinity).frame(height: heroHeight).clipped()
                .overlay(
                    LinearGradient(colors: [.black.opacity(0.35), .clear, .black.opacity(0.25), .black.opacity(0.92)],
                                   startPoint: .top, endPoint: .bottom)
                )
                VStack(alignment: .leading, spacing: 10) {
                    Text(h.kind == "movie" ? "FILM" : "SERIE")
                        .font(.system(size: 11, weight: .semibold)).tracking(1.5).foregroundStyle(.white.opacity(0.7))
                    Text(h.title).font(.system(size: compact ? 26 : 34, weight: .bold)).foregroundStyle(.white)
                        .lineLimit(2).shadow(radius: 12)
                    HStack(spacing: 12) {
                        Label("Abspielen", systemImage: "play.fill")
                            .font(.system(size: 16, weight: .semibold)).foregroundStyle(.black)
                            .padding(.horizontal, 26).padding(.vertical, 12)
                            .background(RoundedRectangle(cornerRadius: 12).fill(.white))
                        if let y = h.year {
                            Text(String(y)).font(.system(size: 14, weight: .regular)).foregroundStyle(.white.opacity(0.8))
                        }
                        if h.hasFile == true {
                            Image(systemName: "checkmark.circle.fill").font(.system(size: 15)).foregroundStyle(cGood)
                        }
                    }
                }.padding(20).padding(.bottom, 22)
            }
        }.buttonStyle(.plain)
    }

    private func row(_ title: String, _ items: [KItem], showProgress: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.system(size: 20, weight: .bold)).foregroundStyle(.white).padding(.horizontal, 20)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(items) { it in tile(it, showProgress: showProgress) }
                }.padding(.horizontal, 20)
            }
        }
    }

    private func tile(_ it: KItem, showProgress: Bool) -> some View {
        Button { selected = it } label: {
            VStack(alignment: .leading, spacing: 6) {
                ZStack(alignment: .topTrailing) {
                    AsyncImage(url: URL(string: it.poster ?? "")) { img in
                        img.resizable().aspectRatio(2/3, contentMode: .fill)
                    } placeholder: {
                        RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.08))
                            .aspectRatio(2/3, contentMode: .fit)
                            .overlay(Image(systemName: "film").foregroundStyle(.white.opacity(0.25)))
                    }
                    .frame(width: tileW, height: tileW * 1.5).clipShape(RoundedRectangle(cornerRadius: 12))
                    if acc.isFav(it.uid) {
                        Image(systemName: "heart.fill").font(.system(size: 13))
                            .foregroundStyle(cAccent).padding(6).shadow(radius: 3)
                    }
                }
                if showProgress {
                    ProgressView(value: acc.progress(it.uid)).tint(cAccent)
                        .frame(width: tileW).scaleEffect(x: 1, y: 0.7, anchor: .center)
                }
                Text(it.title).font(.system(size: 12)).foregroundStyle(.white.opacity(0.9))
                    .lineLimit(1).frame(width: tileW, alignment: .leading)
            }
        }.buttonStyle(.plain)
    }
}

/// Detail-Ansicht (Sheet): Poster, Metadaten, Favoriten-Toggle und „Ansehen".
struct DetailView: View {
    let item: KItem
    @EnvironmentObject var c: Cinema
    @EnvironmentObject var acc: Accounts
    @EnvironmentObject var dl: Downloads
    @Environment(\.dismiss) private var dismiss
    @State private var showPlayer = false

    var body: some View {
        ZStack {
            KinoBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    AsyncImage(url: URL(string: item.hero ?? "")) { img in
                        img.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Rectangle().fill(.white.opacity(0.08))
                    }
                    .frame(height: 210).frame(maxWidth: .infinity).clipped()
                    .overlay(LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: .top, endPoint: .bottom))

                    VStack(alignment: .leading, spacing: 12) {
                        Text(item.title).font(.system(size: 24, weight: .semibold)).foregroundStyle(.white)
                        HStack(spacing: 12) {
                            if let y = item.year { pill(String(y)) }
                            pill(item.kind == "movie" ? "Film" : "Serie")
                            if let g = item.size_gb, g > 0 { pill(String(format: "%.1f GB", g)) }
                            if item.hasFile == true { Label("Verfügbar", systemImage: "checkmark.circle.fill").font(.system(size: 12)).foregroundStyle(cGood) }
                        }

                        HStack(spacing: 12) {
                            Button { start() } label: {
                                Label(acc.progress(item.uid) > 0.02 ? "Weiterschauen" : "Abspielen", systemImage: "play.fill")
                                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(.black)
                                    .frame(maxWidth: .infinity).padding(.vertical, 12)
                                    .background(Capsule().fill(item.hasFile == true ? Color.white : .white.opacity(0.35)))
                            }.buttonStyle(.plain).disabled(item.hasFile != true)

                            Button { acc.toggleFav(item.uid) } label: {
                                Image(systemName: acc.isFav(item.uid) ? "heart.fill" : "heart")
                                    .font(.system(size: 18)).foregroundStyle(cAccent)
                                    .padding(13).glassEffect(.regular, in: .circle)
                            }.buttonStyle(.plain)

                            Button { downloadTapped() } label: {
                                ZStack {
                                    if dl.isDownloading(item.uid) {
                                        Circle().trim(from: 0, to: dl.progress[item.uid] ?? 0)
                                            .stroke(cGood, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                                            .rotationEffect(.degrees(-90)).frame(width: 26, height: 26)
                                        Image(systemName: "stop.fill").font(.system(size: 11)).foregroundStyle(.white)
                                    } else {
                                        Image(systemName: dl.isDownloaded(item.uid) ? "checkmark.circle.fill" : "arrow.down.circle")
                                            .font(.system(size: 18)).foregroundStyle(dl.isDownloaded(item.uid) ? cGood : .white)
                                    }
                                }.frame(width: 44, height: 44).glassEffect(.regular, in: .circle)
                            }.buttonStyle(.plain).disabled(item.hasFile != true)
                        }

                        if item.hasFile == true {
                            Button { c.prepareFlightDownload(item, profile: acc.current?.id ?? "nico") } label: {
                                Label("Für den Flug vorbereiten", systemImage: "airplane")
                                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                                    .frame(maxWidth: .infinity).padding(.vertical, 12)
                                    .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.1)))
                            }.buttonStyle(.plain)
                            if !c.toast.isEmpty {
                                Text(c.toast).font(.system(size: 12)).foregroundStyle(cCyan)
                                    .multilineTextAlignment(.center).frame(maxWidth: .infinity)
                            }
                        }

                        if item.hasFile != true {
                            Text("Noch nicht in der Bibliothek — über den Anfragen-Tab hinzufügen.").font(.system(size: 13)).foregroundStyle(.white.opacity(0.55))
                        }
                    }.padding(.horizontal, 18)
                    Spacer(minLength: 20)
                }
            }
            .ignoresSafeArea(edges: .top)
        }
        .fullScreenCover(isPresented: $showPlayer) { PlayerView(item: item) }
    }

    private func pill(_ s: String) -> some View {
        Text(s).font(.system(size: 12, weight: .light)).foregroundStyle(.white.opacity(0.8))
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Capsule().fill(.white.opacity(0.1)))
    }

    private func start() { showPlayer = true }

    private func downloadTapped() {
        if dl.isDownloaded(item.uid) {
            dl.delete(item.uid)
        } else if !dl.isDownloading(item.uid) {
            Task { if let url = await c.downloadURL(for: item) { dl.start(uid: item.uid, url: url) } }
        }
    }
}
