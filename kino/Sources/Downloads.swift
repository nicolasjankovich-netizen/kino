import Foundation
import SwiftUI

/// Ein wartender/laufender Flug-Download.
struct DLJob: Codable, Identifiable {
    let uid: String
    let title: String
    let quality: String
    var urlString: String
    var cleanupTitle: String?     // nach dem Laden serverseitig löschen (frisch-jedes-Mal-Policy)
    var attempts: Int = 0
    var id: String { uid }
}

/// Lädt komprimierte Filme offline aufs Gerät und verwaltet sie.
/// - **Background-Session**: läuft weiter, wenn die App im Hintergrund/beendet ist (überlebt Abbrüche).
/// - **Queue**: mehrere Filme nacheinander (max. 1 aktiv → volle Bandbreite pro Datei).
/// - **Resume**: bei Netzabbruch wird mit `resumeData` fortgesetzt statt neu geladen.
/// - **Live Activity**: Fortschritt auf Sperrbildschirm / Dynamic Island.
/// - **Cleanup**: nach Fertigstellung löscht der Server die komprimierte Variante wieder.
@MainActor
final class Downloads: NSObject, ObservableObject, URLSessionDownloadDelegate {
    static let shared = Downloads()

    @Published var progress: [String: Double] = [:]   // uid → 0…1 (aktiver Download)
    @Published var speed: [String: Double] = [:]      // uid → Bytes/Sek
    @Published var done: Set<String> = []             // fertig heruntergeladen
    @Published var compressing: Set<String> = []      // wird gerade auf der 3080 komprimiert
    @Published var queue: [DLJob] = []                // wartend + aktiv (persistiert)

    /// Wird von der App gesetzt, wenn iOS die App für Background-URLSession-Events weckt.
    var backgroundCompletion: (() -> Void)?

    func isCompressing(_ uid: String) -> Bool { compressing.contains(uid) }
    func isDownloaded(_ uid: String) -> Bool { done.contains(uid) && localURL(uid) != nil }
    func isDownloading(_ uid: String) -> Bool { progress[uid] != nil }
    func isQueued(_ uid: String) -> Bool { queue.contains { $0.uid == uid } }
    func job(_ uid: String) -> DLJob? { queue.first { $0.uid == uid } }

    private var lastBytes: [String: Int64] = [:]
    private var lastTime: [String: Date] = [:]
    private var activeUID: String?

    // Ein FESTER Identifier → iOS kann die Session nach App-Neustart wiederherstellen.
    private lazy var session: URLSession = {
        let cfg = URLSessionConfiguration.background(withIdentifier: "com.nicolas.Kino.downloads")
        cfg.sessionSendsLaunchEvents = true
        cfg.isDiscretionary = false                    // nicht auf „günstigen Moment" warten → sofort + schnell
        cfg.allowsCellularAccess = true
        cfg.allowsExpensiveNetworkAccess = true
        cfg.allowsConstrainedNetworkAccess = true
        cfg.waitsForConnectivity = true                // wartet auf Netz statt sofort zu scheitern
        cfg.timeoutIntervalForResource = 60 * 60 * 6   // große Datei: bis 6 h Zeit
        return URLSession(configuration: cfg, delegate: self, delegateQueue: nil)
    }()

    override init() {
        super.init()
        done = Set(UserDefaults.standard.stringArray(forKey: "dl_done") ?? [])
        done = done.filter { Downloads.dest($0).map { FileManager.default.fileExists(atPath: $0.path) } ?? false }
        if let data = UserDefaults.standard.data(forKey: "dl_queue"),
           let q = try? JSONDecoder().decode([DLJob].self, from: data) {
            queue = q.filter { !done.contains($0.uid) }
        }
        // App aktualisiert/neu installiert? → NICHT fertig geladene Filme verwerfen (Queue + Teil-
        // dateien + Resume-Daten), damit nach dem Update kein kaputter Halb-Download hängen bleibt.
        // Fertige (offline verfügbare) Filme bleiben erhalten.
        let ver = (Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?")
            + "-" + (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?")
        if UserDefaults.standard.string(forKey: "dl_appver") != ver {
            purgeIncomplete()
            UserDefaults.standard.set(ver, forKey: "dl_appver")
        } else {
            // normaler Start → laufende Background-Tasks wieder anhängen.
            // WICHTIG: echten Stand aus dem Task lesen (countOfBytesReceived), NICHT auf 0 setzen —
            // sonst „springt" ein laufender Download beim App-Öffnen sichtbar auf 0 zurück.
            session.getAllTasks { tasks in
                let running = Set(tasks.compactMap { $0.taskDescription })
                let restored: [(String, Double)] = tasks.compactMap { t in
                    guard let uid = t.taskDescription else { return nil }
                    let exp = t.countOfBytesExpectedToReceive
                    return (uid, exp > 0 ? Double(t.countOfBytesReceived) / Double(exp) : 0.001)
                }
                Task { @MainActor in
                    for (uid, p) in restored { self.progress[uid] = max(self.progress[uid] ?? 0, p) }
                    self.activeUID = running.first
                    self.pump()
                }
            }
        }
    }

    /// Alle NICHT fertigen Downloads verwerfen (bei App-Update). Fertige (`done`) bleiben.
    private func purgeIncomplete() {
        session.getAllTasks { tasks in for t in tasks { t.cancel() } }
        for j in queue where !done.contains(j.uid) {
            if let r = Downloads.resumeFile(j.uid) { try? FileManager.default.removeItem(at: r) }
            if let d = Downloads.dest(j.uid) { try? FileManager.default.removeItem(at: d) }
        }
        queue.removeAll()
        progress.removeAll()
        speed.removeAll()
        activeUID = nil
        persistQueue()
    }

    // MARK: Pfade
    nonisolated static func dest(_ uid: String) -> URL? {
        guard let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return nil }
        let dir = base.appendingPathComponent("downloads", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("\(uid).mp4")
    }
    private static func resumeFile(_ uid: String) -> URL? {
        Downloads.dest(uid)?.deletingLastPathComponent().appendingPathComponent("\(uid).resume")
    }
    func localURL(_ uid: String) -> URL? {
        guard let u = Downloads.dest(uid), FileManager.default.fileExists(atPath: u.path) else { return nil }
        return u
    }
    func fileSize(_ uid: String) -> Int64 {
        guard let u = localURL(uid),
              let a = try? FileManager.default.attributesOfItem(atPath: u.path) else { return 0 }
        return (a[.size] as? Int64) ?? 0
    }

    // MARK: Öffentliche API
    /// Fügt einen Flug-Download in die Queue (mit optionalem Cleanup-Titel + Live Activity).
    func enqueue(uid: String, title: String, quality: String, url: URL, cleanupTitle: String?) {
        guard !isDownloaded(uid), !isQueued(uid) else { return }
        compressing.remove(uid)
        queue.append(DLJob(uid: uid, title: title, quality: quality,
                           urlString: url.absoluteString, cleanupTitle: cleanupTitle))
        persistQueue()
        FlightLive.shared.begin(uid: uid, title: title, quality: quality,
                                phase: "downloading", progress: 0, detail: "startet …")
        pump()
    }

    /// Kompatibilität: einfacher Start ohne Cleanup/Live-Activity-Metadaten.
    func start(uid: String, url: URL) {
        enqueue(uid: uid, title: uid, quality: "", url: url, cleanupTitle: nil)
    }

    func delete(_ uid: String) {
        if let u = Downloads.dest(uid) { try? FileManager.default.removeItem(at: u) }
        if let r = Downloads.resumeFile(uid) { try? FileManager.default.removeItem(at: r) }
        done.remove(uid); progress[uid] = nil; speed[uid] = nil
        queue.removeAll { $0.uid == uid }
        if activeUID == uid { activeUID = nil }
        session.getAllTasks { tasks in for t in tasks where t.taskDescription == uid { t.cancel() } }
        FlightLive.shared.end(uid: uid, detail: "entfernt")
        save(); persistQueue(); pump()
    }

    // MARK: Queue-Motor (seriell: max. 1 aktiver Download)
    private func pump() {
        guard activeUID == nil, let next = queue.first(where: { progress[$0.uid] != nil ? false : true }) ?? queue.first else { return }
        // Wenn schon ein Task für die aktive uid läuft, nicht doppelt starten.
        if let a = activeUID, progress[a] != nil { return }
        guard let url = URL(string: next.urlString) else { queue.removeAll { $0.uid == next.uid }; persistQueue(); return }
        activeUID = next.uid
        progress[next.uid] = progress[next.uid] ?? 0.001
        let task: URLSessionDownloadTask
        if let rf = Downloads.resumeFile(next.uid), let rd = try? Data(contentsOf: rf) {
            task = session.downloadTask(withResumeData: rd)
            try? FileManager.default.removeItem(at: rf)
        } else {
            task = session.downloadTask(with: url)
        }
        task.taskDescription = next.uid
        task.resume()
    }

    private func advance() {
        activeUID = nil
        pump()
    }

    private func save() { UserDefaults.standard.set(Array(done), forKey: "dl_done") }
    private func persistQueue() {
        if let d = try? JSONEncoder().encode(queue) { UserDefaults.standard.set(d, forKey: "dl_queue") }
    }

    // MARK: URLSessionDownloadDelegate (Hintergrund-Queue)
    nonisolated func urlSession(_ s: URLSession, downloadTask t: URLSessionDownloadTask,
                                didWriteData _: Int64, totalBytesWritten w: Int64, totalBytesExpectedToWrite exp: Int64) {
        guard exp > 0, let uid = t.taskDescription else { return }
        let p = Double(w) / Double(exp)
        Task { @MainActor in
            self.progress[uid] = p
            let now = Date()
            var spdStr = ""
            if let lt = self.lastTime[uid], let lb = self.lastBytes[uid] {
                let dt = now.timeIntervalSince(lt)
                if dt > 0.7 {
                    let sp = Double(w - lb) / dt
                    self.speed[uid] = sp
                    self.lastTime[uid] = now; self.lastBytes[uid] = w
                    spdStr = " · \(Self.byteStr(Int64(sp)))/s"
                }
            } else { self.lastTime[uid] = now; self.lastBytes[uid] = w }
            if let j = self.job(uid) {
                FlightLive.shared.update(uid: uid, phase: "downloading", progress: p,
                                         detail: "\(Int(p*100)) %\(spdStr)")
            }
        }
    }

    nonisolated func urlSession(_ s: URLSession, downloadTask t: URLSessionDownloadTask, didFinishDownloadingTo loc: URL) {
        guard let uid = t.taskDescription, let dest = Downloads.dest(uid) else { return }
        try? FileManager.default.removeItem(at: dest)
        try? FileManager.default.moveItem(at: loc, to: dest)   // synchron, bevor temp gelöscht wird
        Task { @MainActor in self.finish(uid) }
    }

    nonisolated func urlSession(_ s: URLSession, task t: URLSessionTask, didCompleteWithError err: Error?) {
        guard let uid = t.taskDescription else { return }
        let resume = (err as NSError?)?.userInfo[NSURLSessionDownloadTaskResumeData] as? Data
        Task { @MainActor in
            guard let err = err else { return }              // Erfolg wird in didFinishDownloadingTo behandelt
            _ = err
            self.speed[uid] = nil; self.lastTime[uid] = nil; self.lastBytes[uid] = nil
            // Resume-Daten sichern und (begrenzt) automatisch neu versuchen.
            let jobIdx = self.queue.firstIndex { $0.uid == uid }
            let hasResume = resume != nil
            if let rd = resume, let rf = Downloads.resumeFile(uid) { try? rd.write(to: rf) }
            // Weiterversuchen — MIT Resume-Daten (setzt am letzten Byte fort, Fortschritt bleibt),
            // sonst als Neustart (Fortschritt beginnt sichtbar wieder, läuft aber sauber durch statt
            // zu verschwinden). Mehr Versuche als früher, da Mobilfunk/WLAN-Wechsel häufig sind.
            if let idx = jobIdx, self.queue[idx].attempts < 6 {
                self.queue[idx].attempts += 1
                if self.activeUID == uid { self.activeUID = nil }
                if !hasResume { self.progress[uid] = 0.001 }   // echter Neustart
                self.persistQueue()
                FlightLive.shared.update(uid: uid, phase: "downloading",
                                         progress: self.progress[uid] ?? 0,
                                         detail: hasResume ? "verbindung unterbrochen — setze fort …"
                                                           : "verbindung unterbrochen — lädt neu …")
                // Backoff (länger bei Neustart, um Netz-Flapping abzuwarten)
                try? await Task.sleep(nanoseconds: hasResume ? 3_000_000_000 : 6_000_000_000)
                self.pump()
            } else {
                // endgültig aufgegeben (nach 6 Versuchen)
                self.progress[uid] = nil
                self.queue.removeAll { $0.uid == uid }
                if self.activeUID == uid { self.activeUID = nil }
                self.persistQueue()
                FlightLive.shared.end(uid: uid, detail: "fehlgeschlagen")
                self.advance()
            }
        }
    }

    /// iOS hat alle Background-Events zugestellt → gespeicherten Completion-Handler aufrufen.
    nonisolated func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        Task { @MainActor in
            self.backgroundCompletion?()
            self.backgroundCompletion = nil
        }
    }

    private func finish(_ uid: String) {
        progress[uid] = nil; speed[uid] = nil
        lastTime[uid] = nil; lastBytes[uid] = nil
        done.insert(uid)
        let j = job(uid)
        queue.removeAll { $0.uid == uid }
        if activeUID == uid { activeUID = nil }
        if let rf = Downloads.resumeFile(uid) { try? FileManager.default.removeItem(at: rf) }
        save(); persistQueue()
        FlightLive.shared.update(uid: uid, phase: "downloading", progress: 1, detail: "fertig — auf dem Gerät")
        FlightLive.shared.end(uid: uid, detail: "offline verfügbar")
        // Bulletproof: die komprimierte Variante bleibt auf dem Server (Speicher egal) → ein
        // erneuter Download (nach App-Neuinstallation o.ä.) ist SOFORT da, nichts geht verloren.
        _ = j   // cleanupTitle bewusst NICHT mehr aufgerufen
        pump()
    }

    static func byteStr(_ b: Int64) -> String {
        let f = ByteCountFormatter(); f.countStyle = .file
        return f.string(fromByteCount: b)
    }
}
