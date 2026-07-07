import ActivityKit

/// Geteilt zwischen App (startet/aktualisiert) und Widget-Extension (rendert die Live Activity).
/// Zeigt den Flug-Download eines Films: erst Kompression auf der 3080, dann Download aufs Gerät.
struct FlightActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var phase: String       // "compressing" | "downloading" | "done"
        var progress: Double    // 0…1  (bei unbestimmter Kompression < 0 → indeterminate)
        var detail: String      // z. B. "42 % · noch 3 min" oder "lädt … 12,4 MB/s"
    }
    var title: String
    var quality: String         // "1080p" / "klein (720p)"
}
