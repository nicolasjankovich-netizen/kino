import SwiftUI

/// Versteckter Debug-/Diagnose-Screen (Punkt 5). Erreichbar NUR über den langen Druck auf den
/// „Kino"-Titel und nur, wenn der User-Code canDebug hat (Timu/Dev). Kein Eintrag im normalen UI.
/// Enthält den Schalter fürs Player-Debug-Overlay (Punkt 6).
struct DebugView: View {
    @EnvironmentObject var acc: Accounts
    @EnvironmentObject var c: Cinema
    @Environment(\.dismiss) private var dismiss
    @AppStorage("kinoQuality") private var quality = "hoch"
    @AppStorage("playerDebugOverlay") private var overlay = false

    @State private var health = "…"
    @State private var local: Bool?

    private var build: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(v) (\(b))"
    }

    var body: some View {
        ZStack {
            KinoBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Label("Debug", systemImage: "ladybug").font(.system(size: 24, weight: .bold)).foregroundStyle(cInk)
                        Spacer()
                        Button { dismiss() } label: { Image(systemName: "xmark.circle.fill").font(.system(size: 26)).foregroundStyle(cInk2.opacity(0.6)) }.buttonStyle(.plain)
                    }.padding(.top, 8)

                    card("Session") {
                        rowKV("Profil", acc.current?.name ?? "—")
                        rowKV("Admin", acc.isAdmin ? "ja" : "nein")
                        rowKV("Debug", acc.canDebug ? "ja" : "nein")
                        rowKV("Profile erlaubt", (acc.allowedProfiles ?? []).map(\.name).joined(separator: ", "))
                        rowKV("Token", kinoToken.isEmpty ? "—" : "•••\(kinoToken.suffix(4))")
                    }

                    card("Wiedergabe") {
                        rowKV("Qualität", quality == "hoch" ? "Gute Qualität" : "Datensparend")
                        Toggle(isOn: $overlay) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Player-Debug-Overlay").font(.system(size: 15)).foregroundStyle(cInk)
                                Text("Live Bitrate · Auflösung · Codec · Buffer · CPU im Player").font(.system(size: 11)).foregroundStyle(cInk2.opacity(0.55))
                            }
                        }.tint(cCyan)
                    }

                    card("Netzwerk") {
                        rowKV("Backend", backendBase.replacingOccurrences(of: "https://", with: ""))
                        rowKV("Heimnetz (LAN)", local == nil ? "prüfe …" : (local! ? "ja — direkt" : "nein — Funnel"))
                        rowKV("Backend /healthz", health)
                    }

                    card("App") {
                        rowKV("Version", build)
                        rowKV("Gerät", UIDevice.current.systemName + " " + UIDevice.current.systemVersion)
                    }

                    Button { acc.logout(); dismiss() } label: {
                        Text("Abmelden & Token löschen").font(.system(size: 14, weight: .medium)).foregroundStyle(cWarn)
                            .frame(maxWidth: .infinity).padding(.vertical, 12)
                            .background(RoundedRectangle(cornerRadius: 12).fill(cWarn.opacity(0.12)))
                    }.buttonStyle(.plain)
                }
                .padding(.horizontal, 18).padding(.bottom, 30)
            }
        }
        .task {
            guard acc.canDebug else { dismiss(); return }   // Defense-in-depth
            local = await c.isLocal()
            health = await fetchHealth()
        }
    }

    private func fetchHealth() async -> String {
        guard let url = URL(string: backendBase + "/healthz") else { return "keine URL" }
        guard let (d, resp) = try? await URLSession.shared.data(from: url) else { return "nicht erreichbar" }
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any] {
            let ok = obj["ok"] as? Bool ?? false
            let tools = obj["tools"] as? Int ?? 0
            return "\(code) · ok=\(ok) · \(tools) tools"
        }
        return "\(code)"
    }

    private func card<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased()).font(.system(size: 11, weight: .semibold)).tracking(1.2).foregroundStyle(cInk2.opacity(0.5))
            content()
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16).fill(.white.opacity(0.06)))
    }
    private func rowKV(_ k: String, _ v: String) -> some View {
        HStack(alignment: .top) {
            Text(k).font(.system(size: 14)).foregroundStyle(cInk2.opacity(0.7))
            Spacer(minLength: 12)
            Text(v).font(.system(size: 14, weight: .medium)).foregroundStyle(cInk).multilineTextAlignment(.trailing)
        }
    }
}
