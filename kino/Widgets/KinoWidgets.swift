import WidgetKit
import SwiftUI
import ActivityKit

// Kino Widget-Extension: Live Activity für Flug-Downloads (Sperrbildschirm + Dynamic Island).
// Zeigt Kompression auf der 3080 und danach den Download aufs Gerät mit Prozent/ETA.

private let kAccent = Color(red: 0.20, green: 0.52, blue: 1.00)
private let kCyan   = Color(red: 0.40, green: 0.78, blue: 1.00)
private let kGood   = Color(red: 0.30, green: 0.85, blue: 0.55)

private func phaseIcon(_ phase: String) -> String {
    switch phase {
    case "compressing": return "bolt.badge.clock"
    case "downloading": return "arrow.down.circle"
    case "done":        return "checkmark.circle.fill"
    default:             return "film"
    }
}
private func phaseTint(_ phase: String) -> Color {
    switch phase {
    case "compressing": return kCyan
    case "downloading": return kAccent
    case "done":        return kGood
    default:             return kAccent
    }
}
private func phaseLabel(_ phase: String) -> String {
    switch phase {
    case "compressing": return "3080 komprimiert"
    case "downloading": return "lädt aufs Gerät"
    case "done":        return "fertig"
    default:             return ""
    }
}

struct FlightLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FlightActivityAttributes.self) { context in
            // Sperrbildschirm / Banner
            HStack(spacing: 12) {
                Image(systemName: phaseIcon(context.state.phase))
                    .font(.system(size: 20)).foregroundStyle(phaseTint(context.state.phase))
                VStack(alignment: .leading, spacing: 4) {
                    Text(context.attributes.title).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                    if context.state.progress >= 0 {
                        ProgressView(value: context.state.progress).tint(phaseTint(context.state.phase))
                    } else {
                        ProgressView().tint(phaseTint(context.state.phase))
                    }
                    Text("\(phaseLabel(context.state.phase)) · \(context.state.detail)")
                        .font(.system(size: 11, weight: .light)).foregroundStyle(.white.opacity(0.65)).lineLimit(1)
                }
            }
            .padding()
            .containerBackground(for: .widget) { Color.black }
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: phaseIcon(context.state.phase)).foregroundStyle(phaseTint(context.state.phase))
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.progress >= 0 ? "\(Int(context.state.progress*100))%" : "…")
                        .foregroundStyle(phaseTint(context.state.phase))
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.attributes.title).font(.system(size: 13, weight: .medium)).foregroundStyle(.white).lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if context.state.progress >= 0 {
                        ProgressView(value: context.state.progress).tint(phaseTint(context.state.phase))
                    } else {
                        ProgressView().tint(phaseTint(context.state.phase))
                    }
                }
            } compactLeading: {
                Image(systemName: phaseIcon(context.state.phase)).foregroundStyle(phaseTint(context.state.phase))
            } compactTrailing: {
                Text(context.state.progress >= 0 ? "\(Int(context.state.progress*100))%" : "…")
                    .foregroundStyle(phaseTint(context.state.phase))
            } minimal: {
                Image(systemName: phaseIcon(context.state.phase)).foregroundStyle(phaseTint(context.state.phase))
            }
        }
    }
}

@main
struct KinoWidgetBundle: WidgetBundle {
    var body: some Widget {
        FlightLiveActivity()
    }
}
