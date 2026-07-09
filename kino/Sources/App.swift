import SwiftUI
import UIKit

// Freundin-App „Kino" — eingeschränkte Media-App auf demselben Backend (nur Library/Suche/Anfrage).
// Kontrakt: ~/jellyfin-stack/SHARED_API.md. KEINE Sysadmin-/Power-/Container-Funktionen.
let backendBase = "https://jarvis.tail215d9d.ts.net"
// Kein eingebetteter Admin-Token mehr. Nach dem Login liegt hier ein media-only Session-Token
// (nur /api/media/*, niemals Sysadmin) — aus dem Keychain gesetzt von Accounts.
var kinoToken = ""

// MARK: - Design / Theme
// Zwei Looks im selben App-Binary, umgeschaltet PRO PROFIL (siehe Accounts):
//  • Nico  → das bestehende Apple-TV/JellyTV-Design (tiefes Schwarz, klares Blau, klare Typo).
//  • Ari   → „girlie": warmes Pink/Lavendel, weiche Glows, geschwungene Script-Titel (Snell Roundhand),
//            abgerundete Body-Schrift (SF Rounded). Verspielt, aber Poster bleiben lesbar (dunkler Grund).
// Der Schalter `girlie` wird beim Profilwechsel gesetzt; danach baut SwiftUI den Tab-Baum neu auf,
// sodass alle abgeleiteten Farben/Schriften frisch gelesen werden.
/// Drei Optiken der App. Identität = **Kinekt** (dunkler Liquid-Glass/Glow-Look, Default für Nico/Timu).
/// **brandy** ist Aris privates Easter-Egg (hell, verspielt). **appletv** ist der optionale, cleane
/// Apple-TV-Look (per Einstellungen-Toggle, für alle Profile). Zugriff ist rollenbasiert:
/// Ari bekommt nie Kinekt, Nico/Timu nie Brandy — nur Apple-TV ist für alle zuschaltbar.
enum KTheme: String { case kinekt, brandy, appletv }
@MainActor var appTheme: KTheme = .kinekt
/// Kompat-Shim: `girlie` == Brandy-Melville-Look (Aris Easter-Egg).
@MainActor var girlie: Bool { appTheme == .brandy }

let cBlue = Color(red: 0.30, green: 0.55, blue: 1.00)     // Nico-Profil-Tint (konstant)
let cPink = Color(red: 1.00, green: 0.58, blue: 0.79)     // Ari-Profil-Tint / Akzent (heller, pastellig)
let cLav  = Color(red: 0.83, green: 0.68, blue: 1.00)     // helles Lavendel (girlie „cyan")

// Akzente folgen dem aktiven Theme.
@MainActor var cAccent: Color {
    switch appTheme {
    case .brandy:  return cPink
    case .kinekt:  return Color(red: 0.20, green: 0.52, blue: 1.00)   // Kinekt-Elektroblau
    case .appletv: return Color(red: 0.38, green: 0.62, blue: 1.00)   // cleanes Apple-TV-Blau
    }
}
@MainActor var cCyan: Color {
    switch appTheme {
    case .brandy:  return cLav
    case .kinekt:  return Color(red: 0.40, green: 0.78, blue: 1.00)
    case .appletv: return Color(red: 0.62, green: 0.80, blue: 1.00)
    }
}
let cGood = Color(red: 0.30, green: 0.85, blue: 0.55)     // „verfügbar/offline" (Semantik, alle)
let cWarn = Color(red: 1.00, green: 0.70, blue: 0.30)     // Bewertung/Warnung (alle)

// Text-Tinten: Kinekt/Apple-TV = Weiß (dunkler Grund); Ari/Brandy = Rosé auf Creme.
@MainActor var cInk:  Color { girlie ? Color(red: 0.94, green: 0.60, blue: 0.77) : .white }
@MainActor var cInk2: Color { girlie ? Color(red: 0.74, green: 0.55, blue: 0.64) : .white }

/// Sehr elegante, feine Script-Schrift für große Aufmacher (Ari) — „Savoye LET" rendert zart & groß.
@MainActor func kScript(_ size: CGFloat) -> Font {
    switch appTheme {
    case .brandy:  return .custom("SavoyeLetPlain", size: size * 1.9)
    case .kinekt:  return .system(size: size, weight: .thin)     // Kinekt-Wortmarke: ultradünn
    case .appletv: return .system(size: size, weight: .bold)
    }
}
/// Abschnitts-Titel. Ari: Snell-Roundhand-Script. Kinekt: ultradünn (dazu `.kChrome()` für Sperr-/
/// Kleinschreibung — die originale Kinekt-Typo). Apple-TV: kräftig-serifenlos.
@MainActor func kTitle(_ size: CGFloat, _ weight: Font.Weight = .bold) -> Font {
    switch appTheme {
    case .brandy:  return .custom("SnellRoundhand-Bold", size: size * 1.3)
    case .kinekt:  return .system(size: size, weight: .light)
    case .appletv: return .system(size: size, weight: weight)
    }
}
/// Body-/Label-Schrift: bei Ari abgerundet (SF Rounded), sonst Standard.
@MainActor func kBody(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
    .system(size: size, weight: weight, design: girlie ? .rounded : .default)
}

extension View {
    /// Kinekt-Typo für UI-Chrome (Wortmarke/Abschnitts-Titel): weit gesperrt + kleingeschrieben,
    /// wie beim ersten Kino. Nur im Kinekt-Theme; Brandy/Apple-TV bleiben unverändert.
    @MainActor func kChrome(_ tracking: CGFloat = 2) -> some View {
        appTheme == .kinekt ? AnyView(self.tracking(tracking).textCase(.lowercase)) : AnyView(self)
    }
}

/// Hintergrund folgt dem Profil: Nico = ruhiges Schwarz; Ari = Brandy-Melville — helle vertikale
/// Candy-Stripes (Blush-Rosa / Creme) von oben nach unten, luftig-soft.
struct KinoBackground: View {
    /// Vertikale Streifen: gleich breite Rechtecke, abwechselnd Blush & Creme.
    private var stripes: some View {
        GeometryReader { geo in
            let count = 26
            let w = geo.size.width / CGFloat(count)
            HStack(spacing: 0) {
                ForEach(0..<count, id: \.self) { i in
                    Rectangle()
                        .fill(i % 2 == 0 ? Color(red: 0.995, green: 0.955, blue: 0.975)  // sehr helles Rosa
                                         : Color(red: 1.0,   green: 0.99,  blue: 0.985)) // fast Weiß
                        .frame(width: w)
                }
            }
        }
    }
    /// Theme als Property (aus dem globalen appTheme beim Erzeugen) — sonst würde SwiftUI diesen
    /// eigenschaftslosen View bei einem Theme-Wechsel nicht neu rendern (Apple-TV-Toggle bliebe wirkungslos).
    var theme: KTheme = appTheme
    var body: some View {
        switch theme {
        case .brandy:
            ZStack {
                Color(red: 1.0, green: 0.99, blue: 0.985)          // heller Grundton
                stripes
                LinearGradient(colors: [Color.white.opacity(0.10), .clear,
                                        Color(red: 0.99, green: 0.90, blue: 0.94).opacity(0.20)],
                               startPoint: .top, endPoint: .bottom)
            }.ignoresSafeArea()
        case .kinekt:
            // Kinekt-Signatur: tiefes Schwarz mit weichem, mehrfarbigem Siri-Glow (Cyan→Indigo→Magenta).
            ZStack {
                Color.black
                GeometryReader { geo in
                    ZStack {
                        glow(Color(red: 0.20, green: 0.60, blue: 1.00), at: .init(x: 0.18, y: 0.12), r: geo.size.width * 0.9)
                        glow(Color(red: 0.55, green: 0.30, blue: 1.00), at: .init(x: 0.85, y: 0.30), r: geo.size.width * 0.8)
                        glow(Color(red: 0.95, green: 0.35, blue: 0.75), at: .init(x: 0.70, y: 0.92), r: geo.size.width * 0.85)
                        glow(Color(red: 0.20, green: 0.80, blue: 0.95), at: .init(x: 0.10, y: 0.80), r: geo.size.width * 0.7)
                    }
                    .blur(radius: 60)
                }
                LinearGradient(colors: [.black.opacity(0.35), .black.opacity(0.72)], startPoint: .top, endPoint: .bottom)
            }.ignoresSafeArea()
        case .appletv:
            // Apple-TV-Look: cleanes, flaches Fast-Schwarz mit dezentem kühlem Schimmer oben. Kein Farb-Glow.
            ZStack {
                Color(white: 0.04)
                RadialGradient(colors: [Color(red: 0.10, green: 0.12, blue: 0.18).opacity(0.55), .clear],
                               center: .init(x: 0.5, y: -0.1), startRadius: 0, endRadius: 620)
            }.ignoresSafeArea()
        }
    }
    /// Ein weicher runder Farbfleck für den Kinekt-Glow.
    private func glow(_ c: Color, at u: UnitPoint, r: CGFloat) -> some View {
        GeometryReader { geo in
            Circle().fill(RadialGradient(colors: [c.opacity(0.55), .clear], center: .center, startRadius: 0, endRadius: r / 2))
                .frame(width: r, height: r)
                .position(x: geo.size.width * u.x, y: geo.size.height * u.y)
        }
    }
}

/// Filme/Serien-Umschalter: pinke Pillen für Ari (girlie), nativer Segmented-Picker für Nico.
struct KindSwitch: View {
    @Binding var kind: Cinema.Kind
    var onChange: () -> Void
    var body: some View {
        if girlie {
            HStack(spacing: 10) {
                ForEach(Cinema.Kind.allCases, id: \.self) { k in
                    Button { kind = k; onChange() } label: {
                        Text(k.label)
                            .font(.system(size: 14, weight: kind == k ? .semibold : .regular, design: .rounded))
                            .foregroundStyle(kind == k ? AnyShapeStyle(Color.white) : AnyShapeStyle(cInk2.opacity(0.75)))
                            .padding(.horizontal, 18).padding(.vertical, 8)
                            .background(Capsule().fill(kind == k ? AnyShapeStyle(cAccent) : AnyShapeStyle(cInk2.opacity(0.12))))
                    }.buttonStyle(.plain)
                }
                Spacer()
            }
        } else {
            Picker("", selection: $kind) {
                ForEach(Cinema.Kind.allCases, id: \.self) { Text($0.label).tag($0) }
            }.pickerStyle(.segmented)
            .onChange(of: kind) { _, _ in onChange() }
        }
    }
}

extension View {
    func glass(_ r: CGFloat = 20) -> some View { self.padding(14).background(.ultraThinMaterial, in: .rect(cornerRadius: r)) }
    /// Abschnitts-Überschrift im Apple-TV-Stil: kräftig, normale Schreibweise.
    func label2() -> some View { self.font(kBody(14, .semibold)).foregroundStyle(cInk2.opacity(0.65)) }
}

// MARK: - Modelle
struct KItem: Decodable, Identifiable {   // Library-Eintrag
    let id: Int; let title: String; let year: Int?; let poster: String?
    let monitored: Bool?; let hasFile: Bool?; let size_gb: Double?
    let backdrop: String?          // 16:9-Hintergrund (Hero-Banner), sobald das Backend es liefert
    let genres: [String]?          // Kategorien (Action, Comedy, …) für Genre-Reihen
    let tmdb: Int?                 // TMDB-ID → Titel-Logo (clearlogo) fürs Hero-Banner
    var kind: String = "movie"     // wird nach dem Dekodieren gesetzt (nicht im JSON)
    enum CodingKeys: String, CodingKey { case id, title, year, poster, monitored, hasFile, size_gb, backdrop, genres, tmdb }
    /// Stabile, kollisionsfreie Kennung über Film+Serie hinweg (Radarr/Sonarr-IDs starten beide bei 1).
    var uid: String { "\(kind)-\(id)" }
    var hero: String? { backdrop ?? poster }
}
struct KResult: Decodable, Identifiable {  // Suchtreffer
    let title: String; let year: Int?; let key: Int?; let overview: String?; let poster: String?; let added: Bool
    var id: String { key.map(String.init) ?? title }
}
struct KRequest: Decodable, Identifiable {  // eigene Anfrage + Live-Status (Beschaffungs-Agent)
    let rid: String; let title: String; let kind: String; let status: String
    let progress: Double?; let year: Int?
    var id: String { rid }
    /// Menschlicher Status-Text + Symbol/Farbe für die Anfragen-Liste.
    var label: String {
        switch status {
        case "available":   return "verfügbar"
        case "downloading": return "lädt \(Int((progress ?? 0) * 100)) %"
        case "retrying":    return "hing – neuer Versuch"
        default:             return "sucht Release …"
        }
    }
    var symbol: String {
        switch status {
        case "available": return "checkmark.circle.fill"
        case "downloading": return "arrow.down.circle.fill"
        case "retrying": return "arrow.triangle.2.circlepath"
        default: return "magnifyingglass.circle.fill"
        }
    }
}
struct Suggestion: Decodable, Identifiable {  // Jellyseerr-Vorschlag (Discover)
    let title: String; let year: Int?; let poster: String?; let overview: String?; let kind: String; let tmdb: Int?
    var id: String { "\(kind)-\(tmdb ?? title.hashValue)" }
}
struct KCast: Decodable, Identifiable {  // Besetzung (JellyTV-Style)
    let name: String; let role: String?; let photo: String?
    var id: String { name + (role ?? "") }
}
struct KSimilar: Decodable, Identifiable {  // ähnlicher Titel
    let title: String; let poster: String?; let tmdb: Int?; let year: String?
    var id: String { "\(tmdb ?? title.hashValue)" }
}
struct KDetails: Decodable {  // Reiche TMDB/Jellyseerr-Infos
    let overview: String?; let tagline: String?; let rating: Double; let runtime: Int?
    let genres: [String]; let cast: [KCast]; let backdrop: String?; let similar: [KSimilar]?
}

// ── Kompressions-/Flug-Status (3080) ──
struct FlightJob: Decodable, Identifiable {   // ein Job auf dem Server (queued/compressing/ready)
    let title: String?; let quality: String?; let profile: String?
    let status: String; let elapsed_sec: Int?; let pct: Double?; let eta_sec: Int?
    var id: String { (title ?? "?") + status }
}
struct PCStatus: Decodable {                  // Live-GPU-Heartbeat vom PC (falls Reporter läuft)
    let gpu_util: Double?; let gpu_watt: Double?; let gpu_temp: Double?
    let phase: String?; let ffmpeg: Bool?; let online: Bool?; let age_sec: Int?
}
struct FlightQueue: Decodable { let jobs: [FlightJob]; let pc: PCStatus?; let active: Bool }

// MARK: - API (nur Medien)
@MainActor
final class Cinema: ObservableObject {
    enum Kind: String, CaseIterable { case movie, series; var label: String { self == .movie ? "Filme" : "Serien" } }
    @Published var kind: Kind = .movie
    @Published var library: [KItem] = []
    @Published var movies: [KItem] = []      // für die Apple-TV-Home (beide Arten gleichzeitig)
    @Published var series: [KItem] = []
    @Published var results: [KResult] = []
    @Published var suggestions: [Suggestion] = []     // Vorschläge-Tab (Jellyseerr)
    @Published var requested: Set<String> = []        // Titel, die gerade angefragt wurden
    @Published var busy = false
    @Published var homeLoaded = false
    @Published var toast = ""
    @Published var flightQueue: FlightQueue?           // Kompressions-Status (3080)
    @Published var myRequests: [KRequest] = []         // eigene Anfragen + Live-Status (Beschaffungs-Agent)

    /// Aktives Profil (nico/ari/timu) fürs Backend — Besteller-Zuordnung im Agenten.
    var profileId: String { UserDefaults.standard.string(forKey: "lastAccount") ?? (girlie ? "ari" : "nico") }

    /// Titel (egal ob Film/Serie) anhand der stabilen uid finden — für Favoriten/Weiterschauen.
    func item(uid: String) -> KItem? { (movies + series).first { $0.uid == uid } }

    /// Eigene Anfragen mit Live-Status laden (Suchen/Lädt/Verfügbar/Neuer Versuch).
    func loadMyRequests() async {
        struct R: Decodable { let requests: [KRequest] }
        guard let (d, _) = try? await URLSession.shared.data(for: req("/api/media/my-requests?profile=\(profileId)")),
              let r = try? JSONDecoder().decode(R.self, from: d) else { return }
        myRequests = r.requests
    }

    /// Neue Status-Benachrichtigungen abholen und als Toast zeigen (Polling).
    func pollNotifications() async {
        struct Notif: Decodable { let title: String; let msg: String; let status: String }
        struct N: Decodable { let notifications: [Notif]; let now: Double }
        let key = "notif_since_\(profileId)"
        let since = UserDefaults.standard.double(forKey: key)
        guard let (d, _) = try? await URLSession.shared.data(for: req("/api/media/notifications?profile=\(profileId)&since=\(since)")),
              let r = try? JSONDecoder().decode(N.self, from: d) else { return }
        UserDefaults.standard.set(r.now, forKey: key)
        guard let last = r.notifications.last else { return }
        toast = last.msg
        try? await Task.sleep(nanoseconds: 5_000_000_000); toast = ""
    }

    private func req(_ path: String, method: String = "GET", body: [String: Any]? = nil) -> URLRequest {
        var r = URLRequest(url: URL(string: backendBase + path)!)
        r.httpMethod = method
        r.setValue("Bearer \(kinoToken)", forHTTPHeaderField: "Authorization")
        if let body { r.setValue("application/json", forHTTPHeaderField: "Content-Type"); r.httpBody = try? JSONSerialization.data(withJSONObject: body) }
        return r
    }
    private func fetchLibrary(_ k: Kind) async -> [KItem] {
        struct R: Decodable { let items: [KItem] }
        guard let (d, _) = try? await URLSession.shared.data(for: req("/api/media/library?kind=\(k.rawValue)")),
              let r = try? JSONDecoder().decode(R.self, from: d) else { return [] }
        return r.items.map { var it = $0; it.kind = k.rawValue; return it }
    }
    func loadLibrary() async {
        busy = true; defer { busy = false }
        library = await fetchLibrary(kind)
    }
    /// Lädt Filme + Serien für die Home. `force` erneuert auch bei bereits geladenen Daten.
    func loadHome(force: Bool = false) async {
        if homeLoaded && !force { return }
        busy = true; defer { busy = false }
        async let m = fetchLibrary(.movie)
        async let s = fetchLibrary(.series)
        movies = await m; series = await s
        homeLoaded = true
    }
    func search(_ term: String) async {
        let t = term.trimmingCharacters(in: .whitespaces); guard !t.isEmpty else { results = []; return }
        let enc = t.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? t
        struct R: Decodable { let results: [KResult] }
        busy = true; defer { busy = false }
        if let (d, _) = try? await URLSession.shared.data(for: req("/api/media/search?kind=\(kind.rawValue)&term=\(enc)")),
           let r = try? JSONDecoder().decode(R.self, from: d) { results = r.results }
    }
    func request(_ item: KResult) {
        Task {
            var body: [String: Any] = ["kind": kind.rawValue, "term": item.title, "profile": profileId]
            if let k = item.key { body["key"] = k }
            struct R: Decodable { let status: String? }
            if let (d, _) = try? await URLSession.shared.data(for: req("/api/media/add", method: "POST", body: body)),
               let r = try? JSONDecoder().decode(R.self, from: d) { toast = "\(item.title) angefragt — \(r.status ?? "ok")" }
            else { toast = "Konnte nicht anfragen" }
            await search(item.title)
            await loadMyRequests()                     // neue Anfrage sofort in der Liste zeigen
            try? await Task.sleep(nanoseconds: 3_000_000_000); toast = ""
        }
    }

    /// Reiche Infos (Bewertung/Handlung/Besetzung/ähnliche) aus Jellyseerr/TMDB — JellyTV-Style.
    func details(for item: KItem) async -> KDetails? {
        let enc = item.title.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? item.title
        var q = "title=\(enc)&kind=\(item.kind)"
        if let y = item.year { q += "&year=\(y)" }
        guard let (d, _) = try? await URLSession.shared.data(for: req("/api/media/details?\(q)")),
              let r = try? JSONDecoder().decode(KDetails.self, from: d) else { return nil }
        return r
    }

    /// Einen „ähnlichen Titel" (aus dem Detail, JellyTV „More Like This") direkt anfragen.
    func requestSimilar(_ s: KSimilar, kind: String) {
        requested.insert(s.id)
        Task {
            let body: [String: Any] = ["kind": kind, "term": s.title, "profile": profileId]
            _ = try? await URLSession.shared.data(for: req("/api/media/add", method: "POST", body: body))
            toast = "\(s.title) angefragt ✓"
            try? await Task.sleep(nanoseconds: 3_000_000_000); toast = ""
        }
    }

    /// Vorschläge (Jellyseerr trending/popular) für den Vorschläge-Tab laden.
    func loadSuggestions(_ kind: Kind) async {
        struct R: Decodable { let results: [Suggestion] }
        busy = true; defer { busy = false }
        if let (d, _) = try? await URLSession.shared.data(for: req("/api/media/discover?kind=\(kind.rawValue)")),
           let r = try? JSONDecoder().decode(R.self, from: d) { suggestions = r.results }
    }
    /// Einen Vorschlag anfragen (Radarr/Sonarr-Lookup per Titel → hinzufügen).
    func requestSuggestion(_ s: Suggestion) {
        requested.insert(s.id)
        Task {
            let body: [String: Any] = ["kind": s.kind == "series" ? "series" : "movie", "term": s.title, "profile": profileId]
            _ = try? await URLSession.shared.data(for: req("/api/media/add", method: "POST", body: body))
            toast = "\(s.title) angefragt ✓"
            try? await Task.sleep(nanoseconds: 3_000_000_000); toast = ""
        }
    }

    /// EIN-Klick-Download: lädt die auf dem Server BEREITS FERTIGE Datei direkt aufs Gerät
    /// (kein On-Demand-Komprimieren mehr). Qualität wählt 720p (datensparend) oder 1080p (gute Quali).
    /// Ist die 1080p-Fassung noch nicht produziert, sagt der Server ready:false → kurzer Hinweis.
    func startFlightDownload(_ item: KItem, profile: String, quality: KinoQuality = .current) {
        let dl = Downloads.shared
        guard !dl.isDownloaded(item.uid), !dl.isDownloading(item.uid) else { return }
        let q = quality == .sparsam ? "720" : "1080"
        let label = quality == .sparsam ? "720p" : "1080p"
        Task {
            let local = await isLocal()
            let enc = item.title.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? item.title
            var path = "/api/media/download?title=\(enc)&quality=\(q)&remote=\(local ? 0 : 1)"
            if let y = item.year { path += "&year=\(y)" }
            struct R: Decodable { let ready: Bool; let url: String?; let have_other: Bool? }
            guard let (d, _) = try? await URLSession.shared.data(for: req(path)),
                  let r = try? JSONDecoder().decode(R.self, from: d) else {
                toast = "Download gerade nicht erreichbar — Verbindung prüfen."
                try? await Task.sleep(nanoseconds: 3_000_000_000); toast = ""; return
            }
            if r.ready, let u = r.url, let url = await bestDownloadURL(u) {
                dl.enqueue(uid: item.uid, title: item.title, quality: label, url: url, cleanupTitle: nil)
            } else {
                toast = "\(label) wird noch auf dem Server vorbereitet — versuch's gleich nochmal."
                try? await Task.sleep(nanoseconds: 4_000_000_000); toast = ""
            }
        }
    }

    /// Beste Download-URL: im Heimnetz die Funnel-URL (:8443, Relay ~3 MB/s) auf die direkte
    /// LAN-URL (192.168.178.88:8096, Gigabit) umschreiben → viel schneller. Unterwegs unverändert.
    private func bestDownloadURL(_ u: String) async -> URL? {
        var s = u
        if await isLocal() {
            s = s.replacingOccurrences(of: "https://jarvis.tail215d9d.ts.net:8443",
                                       with: "http://192.168.178.88:8096")
        }
        return URL(string: s)
    }

    /// JellyTV-Style Titel-Logo (clearlogo, TMDB) für ein Hero-Item — nil wenn keins existiert.
    func logoURL(for item: KItem) async -> URL? {
        guard let t = item.tmdb else { return nil }
        struct R: Decodable { let logo: String? }
        guard let (d, _) = try? await URLSession.shared.data(for: req("/api/media/logo?kind=\(item.kind)&tmdb=\(t)")),
              let r = try? JSONDecoder().decode(R.self, from: d), let s = r.logo else { return nil }
        return URL(string: s)
    }

    /// Kompressions-Status (3080) für den Downloads-Tab laden.
    func loadFlightQueue() async {
        guard let (d, _) = try? await URLSession.shared.data(for: req("/api/media/flight-queue")),
              let r = try? JSONDecoder().decode(FlightQueue.self, from: d) else { return }
        flightQueue = r
    }

    /// Nach dem Download aufs Gerät: komprimierte Variante serverseitig löschen (frisch-jedes-Mal).
    nonisolated static func cleanupFlight(title: String) {
        Task {
            guard let url = URL(string: backendBase + "/api/media/flight-cleanup") else { return }
            var r = URLRequest(url: url); r.httpMethod = "POST"
            r.setValue("Bearer \(kinoToken)", forHTTPHeaderField: "Authorization")
            r.setValue("application/json", forHTTPHeaderField: "Content-Type")
            r.httpBody = try? JSONSerialization.data(withJSONObject: ["title": title])
            _ = try? await URLSession.shared.data(for: r)
        }
    }

    // Heimnetz-Cache (30 s), damit nicht jeder Stream/Download neu pingt.
    private var _localCache: (val: Bool, at: Date)?
    /// Sind wir im Heimnetz? Kurzer Direkt-Ping an den NAS. Erreichbar → LAN-direkt (Gigabit,
    /// ~10–30× schneller als der Tailnet-Funnel-Relay). Unterwegs → false → Funnel (überall erreichbar).
    /// Backend liefert für `remote=0` inzwischen die erreichbare LAN-URL `192.168.178.88:8096`.
    func isLocal() async -> Bool {
        if let c = _localCache, Date().timeIntervalSince(c.at) < 30 { return c.val }
        var ok = false
        if let url = URL(string: "http://192.168.178.88:8096/System/Info/Public") {
            var r = URLRequest(url: url); r.timeoutInterval = 1.5
            let cfg = URLSessionConfiguration.ephemeral
            cfg.timeoutIntervalForRequest = 1.5; cfg.timeoutIntervalForResource = 2; cfg.waitsForConnectivity = false
            if let (_, resp) = try? await URLSession(configuration: cfg).data(for: r) {
                ok = (resp as? HTTPURLResponse)?.statusCode == 200
            }
        }
        _localCache = (ok, Date())
        return ok
    }

    /// Spielbare HLS-URL holen. Qualität wählt der Nutzer selbst (gute Qualität = Original kopieren,
    /// datensparend = komprimiert). `remote` bestimmt nur den Host (LAN direkt vs. Funnel unterwegs).
    func streamURL(for item: KItem) async -> URL? {
        let local = await isLocal()
        let bitrate = KinoQuality.current.streamBitrate   // gute Qualität → kopieren, datensparend → transcode
        let enc = item.title.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? item.title
        var q = "title=\(enc)&kind=\(item.kind)&maxbitrate=\(bitrate)&remote=\(local ? 0 : 1)"
        if let y = item.year { q += "&year=\(y)" }
        struct R: Decodable { let url: String }
        guard let (d, _) = try? await URLSession.shared.data(for: req("/api/media/stream?\(q)")),
              let r = try? JSONDecoder().decode(R.self, from: d) else { return nil }
        return URL(string: r.url)
    }

    /// Komprimierte Download-URL (progressive MP4) für Offline.
    func downloadURL(for item: KItem, bitrate: Int = 2_000_000) async -> URL? {
        let local = await isLocal()
        let enc = item.title.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? item.title
        var q = "title=\(enc)&kind=\(item.kind)&bitrate=\(bitrate)&remote=\(local ? 0 : 1)"
        if let y = item.year { q += "&year=\(y)" }
        struct R: Decodable { let url: String }
        guard let (d, _) = try? await URLSession.shared.data(for: req("/api/media/download?\(q)")),
              let r = try? JSONDecoder().decode(R.self, from: d) else { return nil }
        return URL(string: r.url)
    }
}

/// Vom Nutzer wählbare Wiedergabe-/Download-Qualität (persistiert unter „kinoQuality").
/// Default = gute Qualität. `hoch` ≥15 Mbit → Backend kopiert den Original-Stream (verlustfrei, HDR bleibt),
/// `sparsam` → h264-Transcode mit gedeckelter Bitrate (kleiner, unterwegs-freundlich).
enum KinoQuality: String, CaseIterable {
    case hoch, sparsam
    static var current: KinoQuality { KinoQuality(rawValue: UserDefaults.standard.string(forKey: "kinoQuality") ?? "hoch") ?? .hoch }
    var streamBitrate: Int { self == .hoch ? 40_000_000 : 6_000_000 }
    var label: String { self == .hoch ? "Gute Qualität" : "Datensparend" }
    var icon: String { self == .hoch ? "sparkles" : "arrow.down.circle" }
}

/// Fängt die Background-URLSession-Events ab, wenn iOS die App zum Abschließen von Downloads weckt.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     handleEventsForBackgroundURLSession identifier: String,
                     completionHandler: @escaping () -> Void) {
        Downloads.shared.backgroundCompletion = completionHandler
    }
}

@main
struct KinoApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var c = Cinema()
    @StateObject private var acc = Accounts()
    var body: some Scene {
        WindowGroup {
            RootView().environmentObject(c).environmentObject(acc)
                .environmentObject(Downloads.shared)
                .preferredColorScheme(girlie ? .light : .dark)   // nur Brandy ist hell, sonst dunkel
        }
    }
}

struct RootView: View {
    @EnvironmentObject var acc: Accounts
    @State private var tab = RootView.initialTab()
    static func initialTab() -> Int {
        #if targetEnvironment(simulator)
        if let s = ProcessInfo.processInfo.environment["KINO_DEMO_TAB"], let i = Int(s) { return i }
        #endif
        return 0
    }
    var body: some View {
        if !acc.unlocked {
            AccessView()                 // Schritt 1+2: 2FA-Code
        } else if acc.allowedProfiles == nil {
            UserCodeView()               // Schritt 3: User-Code → erlaubte Profile
        } else if acc.current == nil {
            ProfileView()                // Profil wählen (nur erlaubte; kein PIN)
        } else {
            TabView(selection: $tab) {
                HomeView().tabItem { Label("Start", systemImage: "play.tv") }.tag(0)
                SuggestionsView().tabItem { Label("Vorschläge", systemImage: "sparkles") }.tag(1)
                DiscoverView().tabItem { Label("Bibliothek", systemImage: "film.stack") }.tag(2)
                DownloadsView().tabItem { Label("Downloads", systemImage: "arrow.down.circle") }.tag(3)
                SearchView().tabItem { Label("Anfragen", systemImage: "sparkle.magnifyingglass") }.tag(4)
            }.tint(cAccent)
        }
    }
}
