import SwiftUI

// Freundin-App „Kino" — eingeschränkte Media-App auf demselben Backend (nur Library/Suche/Anfrage).
// Kontrakt: ~/jellyfin-stack/SHARED_API.md. KEINE Sysadmin-/Power-/Container-Funktionen.
let backendBase = "https://jarvis.tail215d9d.ts.net"
// Kein eingebetteter Admin-Token mehr. Nach dem Login liegt hier ein media-only Session-Token
// (nur /api/media/*, niemals Sysadmin) — aus dem Keychain gesetzt von Accounts.
var kinoToken = ""

// MARK: - Design (Apple-TV / JellyTV: tiefes Schwarz, Artwork trägt die Farbe, klare Typo)
let cAccent = Color(red: 0.20, green: 0.52, blue: 1.00)   // klares Blau (Auswahl/Highlights)
let cBlue   = Color(red: 0.30, green: 0.55, blue: 1.00)
let cCyan   = Color(red: 0.40, green: 0.78, blue: 1.00)
let cGood   = Color(red: 0.30, green: 0.85, blue: 0.55)
let cWarn   = Color(red: 1.00, green: 0.70, blue: 0.30)

/// Ruhiger, dunkler Hintergrund (kein animiertes Aurora mehr) — das Artwork liefert die Farbe.
struct KinoBackground: View {
    var body: some View {
        LinearGradient(colors: [Color(white: 0.055), .black],
                       startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
    }
}

extension View {
    func glass(_ r: CGFloat = 20) -> some View { self.padding(14).background(.ultraThinMaterial, in: .rect(cornerRadius: r)) }
    /// Abschnitts-Überschrift im Apple-TV-Stil: kräftig, normale Schreibweise.
    func label2() -> some View { self.font(.system(size: 14, weight: .semibold)).foregroundStyle(.white.opacity(0.65)) }
}

// MARK: - Modelle
struct KItem: Decodable, Identifiable {   // Library-Eintrag
    let id: Int; let title: String; let year: Int?; let poster: String?
    let monitored: Bool?; let hasFile: Bool?; let size_gb: Double?
    let backdrop: String?          // 16:9-Hintergrund (Hero-Banner), sobald das Backend es liefert
    let genres: [String]?          // Kategorien (Action, Comedy, …) für Genre-Reihen
    var kind: String = "movie"     // wird nach dem Dekodieren gesetzt (nicht im JSON)
    enum CodingKeys: String, CodingKey { case id, title, year, poster, monitored, hasFile, size_gb, backdrop, genres }
    /// Stabile, kollisionsfreie Kennung über Film+Serie hinweg (Radarr/Sonarr-IDs starten beide bei 1).
    var uid: String { "\(kind)-\(id)" }
    var hero: String? { backdrop ?? poster }
}
struct KResult: Decodable, Identifiable {  // Suchtreffer
    let title: String; let year: Int?; let key: Int?; let overview: String?; let poster: String?; let added: Bool
    var id: String { key.map(String.init) ?? title }
}
struct Suggestion: Decodable, Identifiable {  // Jellyseerr-Vorschlag (Discover)
    let title: String; let year: Int?; let poster: String?; let overview: String?; let kind: String; let tmdb: Int?
    var id: String { "\(kind)-\(tmdb ?? title.hashValue)" }
}

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

    /// Titel (egal ob Film/Serie) anhand der stabilen uid finden — für Favoriten/Weiterschauen.
    func item(uid: String) -> KItem? { (movies + series).first { $0.uid == uid } }

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
            var body: [String: Any] = ["kind": kind.rawValue, "term": item.title]
            if let k = item.key { body["key"] = k }
            struct R: Decodable { let status: String? }
            if let (d, _) = try? await URLSession.shared.data(for: req("/api/media/add", method: "POST", body: body)),
               let r = try? JSONDecoder().decode(R.self, from: d) { toast = "\(item.title) angefragt — \(r.status ?? "ok")" }
            else { toast = "Konnte nicht anfragen" }
            await search(item.title)
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
            let body: [String: Any] = ["kind": s.kind == "series" ? "series" : "movie", "term": s.title]
            _ = try? await URLSession.shared.data(for: req("/api/media/add", method: "POST", body: body))
            toast = "\(s.title) angefragt ✓"
            try? await Task.sleep(nanoseconds: 3_000_000_000); toast = ""
        }
    }

    /// Flug-Download über den PC anfragen (komprimiert per NVENC). Profil bestimmt die Größe.
    func prepareFlightDownload(_ item: KItem, profile: String) {
        Task {
            var body: [String: Any] = ["title": item.title, "kind": item.kind, "profile": profile]
            if let y = item.year { body["year"] = y }
            struct R: Decodable { let quality: String? }
            if let (d, _) = try? await URLSession.shared.data(for: req("/api/media/prepare-download", method: "POST", body: body)),
               let r = try? JSONDecoder().decode(R.self, from: d) {
                toast = "Flug-Download wird vorbereitet (\(r.quality ?? "")) — Info kommt per Telegram ✈️"
            } else { toast = "Konnte Flug-Download nicht anfragen" }
            try? await Task.sleep(nanoseconds: 4_000_000_000); toast = ""
        }
    }

    /// Sind wir im Heimnetz? (Jellyfin direkt per LAN-IP erreichbar → uncompressed/hohe Bitrate)
    func isLocal() async -> Bool {
        var r = URLRequest(url: URL(string: "http://192.168.178.82:8096/System/Info/Public")!)
        r.timeoutInterval = 1.5
        if let (_, resp) = try? await URLSession.shared.data(for: r),
           let h = resp as? HTTPURLResponse, h.statusCode == 200 { return true }
        return false
    }

    /// Spielbare HLS-URL holen. Lokal: hohe Bitrate (near-lossless). Unterwegs: komprimiert.
    func streamURL(for item: KItem) async -> URL? {
        let local = await isLocal()
        let bitrate = local ? 40_000_000 : 6_000_000
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

@main
struct KinoApp: App {
    @StateObject private var c = Cinema()
    @StateObject private var acc = Accounts()
    var body: some Scene {
        WindowGroup {
            RootView().environmentObject(c).environmentObject(acc)
                .environmentObject(Downloads.shared).preferredColorScheme(.dark)
        }
    }
}

struct RootView: View {
    @EnvironmentObject var acc: Accounts
    var body: some View {
        if !acc.unlocked {
            AccessView()
        } else if acc.current == nil {
            ProfileView()
        } else {
            TabView {
                HomeView().tabItem { Label("Start", systemImage: "play.tv") }
                SuggestionsView().tabItem { Label("Vorschläge", systemImage: "sparkles") }
                DiscoverView().tabItem { Label("Bibliothek", systemImage: "film.stack") }
                DownloadsView().tabItem { Label("Downloads", systemImage: "arrow.down.circle") }
                SearchView().tabItem { Label("Anfragen", systemImage: "sparkle.magnifyingglass") }
            }.tint(cAccent)
        }
    }
}
