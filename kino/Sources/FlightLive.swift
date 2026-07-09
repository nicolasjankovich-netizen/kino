import Foundation
#if canImport(ActivityKit)
import ActivityKit
#endif

/// Verwaltet die Live Activities (Sperrbildschirm / Dynamic Island) pro Flug-Download.
/// iOS-only — auf Mac Catalyst no-op (Live Activities gibt es dort nicht).
@MainActor
final class FlightLive {
    static let shared = FlightLive()
    #if canImport(ActivityKit) && !targetEnvironment(macCatalyst)
    private var acts: [String: Any] = [:]   // uid → Activity<FlightActivityAttributes>
    #endif

    func begin(uid: String, title: String, quality: String, phase: String, progress: Double, detail: String) {
        #if canImport(ActivityKit) && !targetEnvironment(macCatalyst)
        guard #available(iOS 16.2, *) else { return }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        if acts[uid] != nil { update(uid: uid, phase: phase, progress: progress, detail: detail); return }
        let attr = FlightActivityAttributes(title: title, quality: quality)
        let state = FlightActivityAttributes.ContentState(phase: phase, progress: progress, detail: detail)
        if let a = try? Activity.request(attributes: attr,
                                         content: ActivityContent(state: state, staleDate: nil),
                                         pushType: nil) {
            acts[uid] = a
        }
        #endif
    }

    func update(uid: String, phase: String, progress: Double, detail: String) {
        #if canImport(ActivityKit) && !targetEnvironment(macCatalyst)
        guard #available(iOS 16.2, *), let a = acts[uid] as? Activity<FlightActivityAttributes> else { return }
        let state = FlightActivityAttributes.ContentState(phase: phase, progress: progress, detail: detail)
        Task { await a.update(ActivityContent(state: state, staleDate: nil)) }
        #endif
    }

    func end(uid: String, detail: String = "fertig") {
        #if canImport(ActivityKit) && !targetEnvironment(macCatalyst)
        guard #available(iOS 16.2, *), let a = acts[uid] as? Activity<FlightActivityAttributes> else { return }
        let state = FlightActivityAttributes.ContentState(phase: "done", progress: 1, detail: detail)
        Task { await a.end(ActivityContent(state: state, staleDate: nil), dismissalPolicy: .after(.now + 4)) }
        acts[uid] = nil
        #endif
    }
}
