import SwiftUI

/// Apple-TV-artige Startseite: Hero-Banner + horizontal scrollende Reihen
/// (Weiterschauen aus dem Account-State, Favoriten, Filme, Serien).
struct HomeView: View {
    @EnvironmentObject var c: Cinema
    @EnvironmentObject var acc: Accounts
    @Environment(\.horizontalSizeClass) private var hSize
    @State private var selected: KItem?

    private var compact: Bool { hSize == .compact }         // iPhone Hochkant
    // ~16:9 zur Gerätebreite, damit der Backdrop NICHT horizontal überzoomt/beschnitten wird ("zu breit").
    private var heroHeight: CGFloat { compact ? 208 : 320 }
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
    @State private var showDebug = false             // versteckter Debug-Screen (nur canDebug)
    @State private var showSettings = false
    @State private var logos: [String: URL?] = [:]   // uid → Titel-Logo (nil = keins, key fehlt = noch nicht geladen)

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
        .task(id: heroPicks.map(\.uid)) {
            for h in heroPicks where logos[h.uid] == nil {   // Titel-Logos für die Hero-Titel laden
                logos[h.uid] = await c.logoURL(for: h)
            }
        }
        .sheet(item: $selected) { DetailView(item: $0) }
        .fullScreenCover(isPresented: $showDebug) { DebugView() }
        .sheet(isPresented: $showSettings) { SettingsView() }
    }

    @ViewBuilder private var header: some View {
        if girlie { girlieHeader } else { nicoHeader }
    }

    /// Aris Aufmacher: nur der Name, linksbündig, in zarter Pastel-Script — kein Bild/Logo.
    private var girlieHeader: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("Hey Ari")
                .font(kScript(34))
                .foregroundStyle(LinearGradient(colors: [cPink, cInk], startPoint: .leading, endPoint: .trailing))
            Text("♡")                                  // gleicher Stil, so groß wie ein „i" mit Punkt
                .font(.system(size: 30, weight: .thin))
                .foregroundStyle(cPink)
            Spacer()
            if c.busy { ProgressView().tint(cPink) }
            Button { showSettings = true } label: {
                Image(systemName: "gearshape.fill").font(.system(size: 20)).foregroundStyle(cPink.opacity(0.7))
            }.buttonStyle(.plain)
            Button { acc.switchProfile() } label: {
                Image(systemName: "heart.circle.fill").font(.system(size: 24)).foregroundStyle(cPink.opacity(0.8))
            }.buttonStyle(.plain)
        }
        .padding(.horizontal, 20).padding(.top, 10)
    }

    private var nicoHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            // Kinekt-Wortmarke: „kino" ultradünn + weit gesperrt (wie beim ersten Kino); Apple-TV: „Kino" fett.
            Group {
                if appTheme == .kinekt {
                    Text("kino").font(.system(size: 26, weight: .thin)).tracking(5)
                } else {
                    Text("Kino").font(.system(size: 26, weight: .bold))
                }
            }
            .foregroundStyle(cInk)
            // Versteckter Zugang zum Debug-Screen (Punkt 5): nur bei canDebug (Timu/Dev),
            // langer Druck auf den Titel. Für normale Nutzer passiert nichts.
            .onLongPressGesture(minimumDuration: 1.1) { if acc.canDebug { showDebug = true } }
            Spacer()
            if c.busy { ProgressView().tint(.white) }
            if let n = acc.current?.name {
                Text(n).font(.system(size: 14, weight: .medium)).foregroundStyle(cInk2.opacity(0.7))
            }
            Button { showSettings = true } label: {
                Image(systemName: "gearshape.fill").font(.system(size: 19)).foregroundStyle(cInk2.opacity(0.7))
            }.buttonStyle(.plain)
            Button { acc.switchProfile() } label: {
                Image(systemName: "person.crop.circle").font(.system(size: 23)).foregroundStyle(cInk2.opacity(0.85))
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
        .overlay(alignment: .bottomTrailing) {
            if heroPicks.count > 1 {
                HStack(spacing: 6) {
                    ForEach(0..<heroPicks.count, id: \.self) { i in
                        Circle().fill(.white.opacity(i == heroIndex % heroPicks.count ? 0.95 : 0.35))
                            .frame(width: 6, height: 6)
                    }
                }.padding(.trailing, 20).padding(.bottom, 18)
            }
        }
        .onReceive(Timer.publish(every: 6, on: .main, in: .common).autoconnect()) { _ in
            guard heroPicks.count > 1 else { return }
            withAnimation(.easeInOut(duration: 0.8)) { heroIndex += 1 }
        }
    }

    /// Hero-Titel als Original-Schriftzug vom Cover (TMDB-Logo, JellyTV-Style) — Fallback: Text.
    @ViewBuilder private func heroTitle(_ h: KItem) -> some View {
        if let entry = logos[h.uid], let url = entry {
            CachedImage(url: url) { img in
                img.resizable().aspectRatio(contentMode: .fit)
            } placeholder: {
                Text(h.title).font(kBody(compact ? 26 : 34, .bold)).foregroundStyle(.white).lineLimit(2)
            }
            .frame(maxWidth: compact ? 196 : 280, maxHeight: compact ? 60 : 82, alignment: .leading)
            .shadow(color: .black.opacity(0.45), radius: 7, y: 2)
        } else {
            Text(h.title).font(kBody(compact ? 26 : 34, .bold)).foregroundStyle(.white)
                .lineLimit(2).shadow(radius: 12)
        }
    }

    private func heroBanner(_ h: KItem) -> some View {
        Button { selected = h } label: {
            ZStack(alignment: .bottomLeading) {
                CachedImage(url: URL(string: h.hero ?? "")) { img in
                    img.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    Rectangle().fill(.white.opacity(0.06))
                }
                .frame(maxWidth: .infinity).frame(height: heroHeight).clipped()
                .overlay(
                    // Text bleibt weiß (über dem Bild); für Ari ein zart-rosa Verlauf statt hartem Schwarz.
                    LinearGradient(colors: girlie
                        ? [.clear, Color(red: 0.30, green: 0.05, blue: 0.16).opacity(0.15), Color(red: 0.30, green: 0.05, blue: 0.16).opacity(0.72)]
                        : [.black.opacity(0.35), .clear, .black.opacity(0.25), .black.opacity(0.92)],
                                   startPoint: .top, endPoint: .bottom)
                )
                VStack(alignment: .leading, spacing: 10) {
                    Text(h.kind == "movie" ? "FILM" : "SERIE")
                        .font(.system(size: 11, weight: .semibold)).tracking(1.5).foregroundStyle(.white.opacity(0.85))
                    heroTitle(h)
                    HStack(spacing: 12) {
                        Label("Abspielen", systemImage: "play.fill")
                            .font(.system(size: 16, weight: .semibold)).foregroundStyle(girlie ? .white : .black)
                            .padding(.horizontal, 26).padding(.vertical, 12)
                            .background(RoundedRectangle(cornerRadius: 14).fill(
                                girlie ? AnyShapeStyle(LinearGradient(colors: [cPink, cLav], startPoint: .leading, endPoint: .trailing))
                                       : AnyShapeStyle(Color.white)))
                        if let y = h.year {
                            Text(String(y)).font(.system(size: 14, weight: .regular)).foregroundStyle(.white.opacity(0.85))
                        }
                        if h.hasFile == true {
                            Image(systemName: "checkmark.circle.fill").font(.system(size: 15)).foregroundStyle(cGood)
                        }
                    }
                }.padding(20).padding(.bottom, 22)
            }
            .clipShape(RoundedRectangle(cornerRadius: girlie ? 22 : 0))
            .padding(.horizontal, girlie ? 14 : 0)
        }.buttonStyle(.plain)
    }

    private func row(_ title: String, _ items: [KItem], showProgress: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(kTitle(20)).kChrome().foregroundStyle(girlie ? AnyShapeStyle(cInk) : AnyShapeStyle(Color.white)).padding(.horizontal, 20)
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
                    CachedImage(url: URL(string: it.poster ?? "")) { img in
                        img.resizable().aspectRatio(2/3, contentMode: .fill)
                    } placeholder: {
                        RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.08))
                            .aspectRatio(2/3, contentMode: .fit)
                            .overlay(Image(systemName: "film").foregroundStyle(cInk2.opacity(0.25)))
                    }
                    .frame(width: tileW, height: tileW * 1.5)
                    .clipShape(RoundedRectangle(cornerRadius: girlie ? 18 : 12))
                    .shadow(color: girlie ? cPink.opacity(0.28) : .clear, radius: 7, y: 4)
                    if acc.isFav(it.uid) {
                        Image(systemName: "heart.fill").font(.system(size: 13))
                            .foregroundStyle(cAccent).padding(6).shadow(radius: 3)
                    }
                }
                if showProgress {
                    ProgressView(value: acc.progress(it.uid)).tint(cAccent)
                        .frame(width: tileW).scaleEffect(x: 1, y: 0.7, anchor: .center)
                }
                Text(it.title).font(kBody(12)).foregroundStyle(cInk2.opacity(0.95))
                    .lineLimit(1).frame(width: tileW, alignment: .leading)
            }
        }.buttonStyle(PosterPress())
    }
}

/// Apple-TV-artiges Antippen: Kachel skaliert beim Drücken leicht herunter.
struct PosterPress: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.easeOut(duration: 0.18), value: configuration.isPressed)
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
    @State private var details: KDetails?
    @State private var seasons: [KSeason] = []        // Serien: Staffeln + verfügbare Folgen
    @State private var selSeason: Int = 0             // gewählte Staffel-Nummer
    @State private var playingEpisode: KEpisode?      // gewählte Folge → Player
    @AppStorage("kinoQuality") private var quality = "hoch"   // gilt für Abspielen UND Download

    var body: some View {
        ZStack {
            KinoBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    CachedImage(url: URL(string: item.hero ?? "")) { img in
                        img.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Rectangle().fill(.white.opacity(0.08))
                    }
                    .frame(maxWidth: .infinity).frame(height: 240).clipped()
                    .overlay(LinearGradient(colors: [.clear, .clear, .black.opacity(0.55), .black],
                                            startPoint: .top, endPoint: .bottom))

                    VStack(alignment: .leading, spacing: 12) {
                        Text(item.title).font(kTitle(24)).foregroundStyle(girlie ? cPink : .white)
                            .fixedSize(horizontal: false, vertical: true)
                        if let tl = details?.tagline, !tl.isEmpty {
                            Text(tl).font(.system(size: 14, weight: .light)).italic()
                                .foregroundStyle(cInk2.opacity(0.6))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                if let y = item.year { pill(String(y)) }
                                pill(item.kind == "movie" ? "Film" : "Serie")
                                if let g = item.size_gb, g > 0 { pill(String(format: "%.1f GB", g)) }
                                if item.hasFile == true { Label("Verfügbar", systemImage: "checkmark.circle.fill").font(.system(size: 12)).foregroundStyle(cGood) }
                            }
                        }

                        HStack(spacing: 12) {
                            Button { start() } label: {
                                Label(playLabel, systemImage: "play.fill")
                                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(girlie ? .white : .black)
                                    .frame(maxWidth: .infinity).padding(.vertical, 12)
                                    .background(Capsule().fill(
                                        canPlay
                                        ? (girlie ? AnyShapeStyle(LinearGradient(colors: [cPink, cLav], startPoint: .leading, endPoint: .trailing)) : AnyShapeStyle(Color.white))
                                        : AnyShapeStyle(cInk2.opacity(0.3))))
                            }.buttonStyle(.plain).disabled(!canPlay)

                            Button { acc.toggleFav(item.uid) } label: {
                                Image(systemName: acc.isFav(item.uid) ? "heart.fill" : "heart")
                                    .font(.system(size: 18)).foregroundStyle(cAccent)
                                    .padding(13).glassEffect(.regular, in: .circle)
                            }.buttonStyle(.plain)

                            if item.kind != "series" {   // Downloads gibt es (vorerst) nur für Filme
                                Button { downloadTapped() } label: {
                                    ZStack {
                                        if dl.isDownloading(item.uid) {
                                            Circle().trim(from: 0, to: dl.progress[item.uid] ?? 0)
                                                .stroke(cGood, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                                                .rotationEffect(.degrees(-90)).frame(width: 26, height: 26)
                                            Image(systemName: "stop.fill").font(.system(size: 11)).foregroundStyle(cInk)
                                        } else {
                                            Image(systemName: dl.isDownloaded(item.uid) ? "checkmark.circle.fill" : "arrow.down.circle")
                                                .font(.system(size: 18)).foregroundStyle(dl.isDownloaded(item.uid) ? cGood : .white)
                                        }
                                    }.frame(width: 44, height: 44).glassEffect(.regular, in: .circle)
                                }.buttonStyle(.plain).disabled(item.hasFile != true)
                            }
                        }

                        if item.hasFile == true {
                            VStack(alignment: .leading, spacing: 6) {
                                Picker("Qualität", selection: $quality) {
                                    Label("Gute Qualität", systemImage: "sparkles").tag("hoch")
                                    Label("Datensparend", systemImage: "arrow.down.circle").tag("sparsam")
                                }
                                .pickerStyle(.segmented)
                                Text(quality == "hoch"
                                     ? "Original in voller Qualität — mehr Daten."
                                     : "Komprimiert, spart Daten — fürs Handynetz.")
                                    .font(.system(size: 11)).foregroundStyle(cInk2.opacity(0.55))
                            }
                        }

                        if dl.isDownloading(item.uid) {
                            let spd = dl.speed[item.uid] ?? 0
                            Text("lädt aufs Gerät … \(Int((dl.progress[item.uid] ?? 0) * 100)) %"
                                 + (spd > 0 ? " · \(Downloads.byteStr(Int64(spd)))/s" : ""))
                                .font(.system(size: 12)).foregroundStyle(cGood)
                        } else if dl.isDownloaded(item.uid) {
                            Label("offline auf dem Gerät", systemImage: "checkmark.circle.fill")
                                .font(.system(size: 12)).foregroundStyle(cGood)
                        }

                        if item.kind == "series" { seasonsSection }

                        if let d = details {
                            HStack(spacing: 14) {
                                if d.rating > 0 {
                                    Label(String(format: "%.1f", d.rating), systemImage: "star.fill")
                                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(cWarn)
                                }
                                if let rt = d.runtime, rt > 0 {
                                    Text("\(rt) Min").font(.system(size: 13)).foregroundStyle(cInk2.opacity(0.7))
                                }
                                if !d.genres.isEmpty {
                                    Text(d.genres.prefix(3).joined(separator: " · "))
                                        .font(.system(size: 13)).foregroundStyle(cInk2.opacity(0.6)).lineLimit(1)
                                }
                            }
                            if let o = d.overview, !o.isEmpty {
                                Text(o).font(.system(size: 14)).foregroundStyle(cInk2.opacity(0.82))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            if !d.cast.isEmpty {
                                Text("Besetzung").font(.system(size: 17, weight: .bold)).foregroundStyle(cInk).padding(.top, 4)
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 12) {
                                        ForEach(d.cast) { m in
                                            VStack(spacing: 5) {
                                                CachedImage(url: URL(string: m.photo ?? "")) { img in
                                                    img.resizable().aspectRatio(contentMode: .fill)
                                                } placeholder: {
                                                    Circle().fill(.white.opacity(0.1))
                                                        .overlay(Image(systemName: "person.fill").foregroundStyle(cInk2.opacity(0.3)))
                                                }
                                                .frame(width: 62, height: 62).clipShape(Circle())
                                                Text(m.name).font(.system(size: 11)).foregroundStyle(cInk2.opacity(0.85)).lineLimit(1).frame(width: 68)
                                                if let r = m.role, !r.isEmpty {
                                                    Text(r).font(.system(size: 9)).foregroundStyle(cInk2.opacity(0.45)).lineLimit(1).frame(width: 68)
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                            if let sims = d.similar, !sims.isEmpty {
                                Text("Ähnliche Titel").font(.system(size: 17, weight: .bold)).foregroundStyle(cInk).padding(.top, 4)
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 12) {
                                        ForEach(sims) { s in
                                            Button { c.requestSimilar(s, kind: item.kind) } label: {
                                                VStack(alignment: .leading, spacing: 5) {
                                                    CachedImage(url: URL(string: s.poster ?? "")) { img in
                                                        img.resizable().aspectRatio(2/3, contentMode: .fill)
                                                    } placeholder: {
                                                        RoundedRectangle(cornerRadius: 10).fill(.white.opacity(0.08))
                                                            .overlay(Image(systemName: "film").foregroundStyle(cInk2.opacity(0.25)))
                                                    }
                                                    .frame(width: 100, height: 150).clipShape(RoundedRectangle(cornerRadius: 10))
                                                    Text(s.title).font(.system(size: 11)).foregroundStyle(cInk2.opacity(0.85))
                                                        .lineLimit(1).frame(width: 100, alignment: .leading)
                                                }
                                            }.buttonStyle(.plain)
                                        }
                                    }
                                }
                            }
                        }

                        if item.hasFile != true {
                            Text("Noch nicht in der Bibliothek — über den Anfragen-Tab hinzufügen.").font(.system(size: 13)).foregroundStyle(cInk2.opacity(0.55))
                        }
                    }.padding(.horizontal, 18)
                    Spacer(minLength: 20)
                }
            }
            .ignoresSafeArea(edges: .top)
        }
        .task {
            if details == nil { details = await c.details(for: item) }
            if item.kind == "series", seasons.isEmpty {
                seasons = await c.seasons(for: item)
                selSeason = seasons.first?.season ?? 0
            }
        }
        .fullScreenCover(isPresented: $showPlayer) { PlayerView(item: item) }
        .fullScreenCover(item: $playingEpisode) { ep in
            PlayerView(item: item, episodeId: ep.id, episodeName: episodeLabel(ep))
        }
    }

    // MARK: – Serien: Staffel-/Folgen-Auswahl
    private var currentEpisodes: [KEpisode] { seasons.first { $0.season == selSeason }?.episodes ?? [] }
    /// Zuletzt geschaute, noch nicht beendete Folge (übers Profil-Progress-Log).
    private var resumeEpisode: KEpisode? {
        for uid in acc.history() {
            for se in seasons {
                if let ep = se.episodes.first(where: { $0.id == uid }) {
                    let p = acc.progress(uid)
                    if p > 0.02 && p < 0.95 { return ep }
                }
            }
        }
        return nil
    }
    private var canPlay: Bool { item.kind == "series" ? !seasons.isEmpty : item.hasFile == true }
    private var playLabel: String {
        if item.kind == "series" { return resumeEpisode != nil ? "Weiterschauen" : "Abspielen" }
        return acc.progress(item.uid) > 0.02 ? "Weiterschauen" : "Abspielen"
    }
    private func episodeLabel(_ ep: KEpisode) -> String {
        var s = "S\(selSeason)"
        if let e = ep.episode { s += "E\(e)" }
        if let n = ep.name, !n.isEmpty { s += " · \(n)" }
        return s
    }

    private var seasonsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Staffeln & Folgen").font(kTitle(18)).kChrome().foregroundStyle(cInk)
            if seasons.isEmpty {
                Label("Noch keine Folgen auf dem Server — Staffeln über den Anfragen-Tab laden.",
                      systemImage: "tray")
                    .font(.system(size: 12)).foregroundStyle(cInk2.opacity(0.55))
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(seasons) { se in
                            Button { selSeason = se.season } label: {
                                Text("Staffel \(se.season)")
                                    .font(.system(size: 13, weight: selSeason == se.season ? .semibold : .regular))
                                    .foregroundStyle(selSeason == se.season ? (girlie ? .white : .black) : cInk2.opacity(0.75))
                                    .padding(.horizontal, 14).padding(.vertical, 7)
                                    .background(Capsule().fill(selSeason == se.season
                                        ? AnyShapeStyle(girlie ? AnyShapeStyle(cPink) : AnyShapeStyle(Color.white))
                                        : AnyShapeStyle(Color.white.opacity(0.1))))
                            }.buttonStyle(.plain)
                        }
                    }
                }
                VStack(spacing: 8) {
                    ForEach(currentEpisodes) { ep in
                        Button { playingEpisode = ep } label: {
                            HStack(spacing: 12) {
                                Text(ep.episode.map { String(format: "%02d", $0) } ?? "–")
                                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(cAccent).frame(width: 28)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(ep.name ?? "Folge \(ep.episode ?? 0)")
                                        .font(.system(size: 14)).foregroundStyle(cInk).lineLimit(1)
                                    HStack(spacing: 6) {
                                        if let rt = ep.runtime, rt > 0 {
                                            Text("\(rt) Min").font(.system(size: 11)).foregroundStyle(cInk2.opacity(0.5))
                                        }
                                        let p = acc.progress(ep.id)
                                        if p > 0.94 {
                                            Label("gesehen", systemImage: "checkmark").font(.system(size: 11)).foregroundStyle(cGood)
                                        } else if p > 0.02 {
                                            Text("\(Int(p * 100)) %").font(.system(size: 11)).foregroundStyle(cAccent)
                                        }
                                    }
                                }
                                Spacer()
                                Image(systemName: "play.circle.fill").font(.system(size: 24)).foregroundStyle(cInk.opacity(0.9))
                            }
                            .padding(10)
                            .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.06)))
                            .overlay(alignment: .bottomLeading) {
                                let p = acc.progress(ep.id)
                                if p > 0.02 && p < 0.95 {   // dünner Fortschrittsbalken unten
                                    GeometryReader { geo in
                                        Capsule().fill(cAccent.opacity(0.9))
                                            .frame(width: geo.size.width * p, height: 2)
                                    }.frame(height: 2).padding(.horizontal, 10)
                                }
                            }
                        }.buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.top, 4)
    }

    private func pill(_ s: String) -> some View {
        Text(s).font(.system(size: 12, weight: .light)).foregroundStyle(cInk2.opacity(0.8))
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Capsule().fill(.white.opacity(0.1)))
    }

    private func start() {
        if item.kind == "series" {
            // Serie: zuletzt geschaute Folge fortsetzen, sonst erste verfügbare Folge.
            if let ep = resumeEpisode ?? seasons.first?.episodes.first {
                if let se = seasons.first(where: { $0.episodes.contains(where: { $0.id == ep.id }) }) {
                    selSeason = se.season
                }
                playingEpisode = ep
            }
        } else {
            showPlayer = true
        }
    }

    private func downloadTapped() {
        if dl.isDownloaded(item.uid) || dl.isDownloading(item.uid) {
            dl.delete(item.uid)                                 // erneut tippen = löschen/abbrechen
        } else {
            c.startFlightDownload(item, profile: acc.current?.id ?? "nico")   // 1 Klick: fertige Datei direkt laden
        }
    }
}
