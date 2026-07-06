import Foundation
import SwiftUI

/// Lädt komprimierte Filme (Progressive-MP4 vom Backend) offline auf's Gerät und verwaltet sie.
@MainActor
final class Downloads: NSObject, ObservableObject, URLSessionDownloadDelegate {
    static let shared = Downloads()

    @Published var progress: [String: Double] = [:]   // uid → 0…1 während des Ladens
    @Published var speed: [String: Double] = [:]      // uid → Bytes/Sek
    @Published var done: Set<String> = []             // fertig heruntergeladen

    private var lastBytes: [String: Int64] = [:]
    private var lastTime: [String: Date] = [:]
    private lazy var session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)

    /// Größe einer heruntergeladenen Datei in Bytes.
    func fileSize(_ uid: String) -> Int64 {
        guard let u = localURL(uid),
              let a = try? FileManager.default.attributesOfItem(atPath: u.path) else { return 0 }
        return (a[.size] as? Int64) ?? 0
    }

    override init() {
        super.init()
        done = Set(UserDefaults.standard.stringArray(forKey: "dl_done") ?? [])
        // verwaiste Einträge (Datei fehlt) bereinigen
        done = done.filter { Downloads.dest($0).map { FileManager.default.fileExists(atPath: $0.path) } ?? false }
    }

    nonisolated static func dest(_ uid: String) -> URL? {
        guard let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return nil }
        let dir = base.appendingPathComponent("downloads", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("\(uid).mp4")
    }

    func localURL(_ uid: String) -> URL? {
        guard let u = Downloads.dest(uid), FileManager.default.fileExists(atPath: u.path) else { return nil }
        return u
    }
    func isDownloaded(_ uid: String) -> Bool { done.contains(uid) && localURL(uid) != nil }
    func isDownloading(_ uid: String) -> Bool { progress[uid] != nil }

    func start(uid: String, url: URL) {
        guard progress[uid] == nil, !isDownloaded(uid) else { return }
        progress[uid] = 0.001
        let t = session.downloadTask(with: url)
        t.taskDescription = uid
        t.resume()
    }

    func delete(_ uid: String) {
        if let u = Downloads.dest(uid) { try? FileManager.default.removeItem(at: u) }
        done.remove(uid); progress[uid] = nil; save()
    }

    private func save() { UserDefaults.standard.set(Array(done), forKey: "dl_done") }

    // MARK: URLSessionDownloadDelegate (läuft auf Hintergrund-Queue)
    nonisolated func urlSession(_ s: URLSession, downloadTask t: URLSessionDownloadTask,
                                didWriteData _: Int64, totalBytesWritten w: Int64, totalBytesExpectedToWrite exp: Int64) {
        guard exp > 0, let uid = t.taskDescription else { return }
        let p = Double(w) / Double(exp)
        Task { @MainActor in
            self.progress[uid] = p
            let now = Date()
            if let lt = self.lastTime[uid], let lb = self.lastBytes[uid] {
                let dt = now.timeIntervalSince(lt)
                if dt > 0.7 {                               // alle ~0,7s die Geschwindigkeit auffrischen
                    self.speed[uid] = Double(w - lb) / dt
                    self.lastTime[uid] = now; self.lastBytes[uid] = w
                }
            } else {
                self.lastTime[uid] = now; self.lastBytes[uid] = w
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
        if err != nil { Task { @MainActor in self.progress[uid] = nil; self.speed[uid] = nil; self.lastTime[uid] = nil; self.lastBytes[uid] = nil } }
    }

    private func finish(_ uid: String) {
        progress[uid] = nil; speed[uid] = nil
        lastTime[uid] = nil; lastBytes[uid] = nil
        done.insert(uid); save()
    }
}
