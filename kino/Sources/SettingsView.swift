import SwiftUI

/// Einstellungen: Optik (Apple-TV-Look an/aus, pro Profil gespeichert), Standard-Streamqualität,
/// Netz-Status, Konto und App-Info.
struct SettingsView: View {
    @EnvironmentObject var acc: Accounts
    @EnvironmentObject var c: Cinema
    @Environment(\.dismiss) private var dismiss
    @AppStorage("kinoQuality") private var quality = "hoch"
    @State private var appleTV = false
    @State private var local: Bool?
    @State private var cacheCleared = false

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
                        Text("Einstellungen").font(kTitle(26)).kChrome().foregroundStyle(girlie ? cPink : cInk)
                        Spacer()
                        Button { dismiss() } label: { Image(systemName: "xmark.circle.fill").font(.system(size: 26)).foregroundStyle(cInk2.opacity(0.6)) }.buttonStyle(.plain)
                    }.padding(.top, 8)

                    section("Optik") {
                        Toggle(isOn: $appleTV) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Apple-TV-Optik").font(.system(size: 16)).foregroundStyle(cInk)
                                Text(appleTV ? "cleaner, dunkler Apple-TV-Look" : "Standard-Look der App")
                                    .font(.system(size: 12)).foregroundStyle(cInk2.opacity(0.55))
                            }
                        }
                        .tint(cAccent)
                        .onChange(of: appleTV) { _, on in acc.setAppleTV(on) }
                    }

                    section("Wiedergabe") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Standard-Qualität").font(.system(size: 15)).foregroundStyle(cInk)
                            Picker("", selection: $quality) {
                                Text("Gute Qualität").tag("hoch")
                                Text("Datensparend").tag("sparsam")
                            }.pickerStyle(.segmented)
                            Text(quality == "hoch" ? "Streamt das Original in voller Qualität."
                                                    : "Komprimiert – spart Daten unterwegs.")
                                .font(.system(size: 12)).foregroundStyle(cInk2.opacity(0.55))
                        }
                    }

                    section("Netz & Speicher") {
                        rowKV("Verbindung", local == nil ? "prüfe …" : (local! ? "Heimnetz (direkt)" : "unterwegs (Funnel)"))
                        rowButton(cacheCleared ? "Bild-Cache geleert ✓" : "Bild-Cache leeren", "photo.stack") {
                            ImageCache.shared.clear(); cacheCleared = true
                        }
                    }

                    section("Konto") {
                        rowKV("Profil", acc.current?.name ?? "—")
                        rowButton("Profil wechseln", "person.2.arrow.trianglehead.counterclockwise") { acc.switchProfile(); dismiss() }
                        rowButton("Anderer User-Code", "key") { acc.resetUserCode(); dismiss() }
                        rowButton("Abmelden", "rectangle.portrait.and.arrow.right", tint: cWarn) { acc.logout(); dismiss() }
                    }

                    section("App") {
                        rowKV("Version", build)
                        Text("Kino läuft über deinen eigenen Server.").font(.system(size: 12)).foregroundStyle(cInk2.opacity(0.45))
                    }
                }
                .padding(.horizontal, 18).padding(.bottom, 30)
            }
        }
        .task { appleTV = acc.appleTVOn(); local = await c.isLocal() }
    }

    private func section<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title.uppercased()).font(.system(size: 11, weight: .semibold)).tracking(1.2).foregroundStyle(cInk2.opacity(0.5))
            content()
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16).fill(girlie ? Color.white.opacity(0.5) : Color.white.opacity(0.06)))
    }
    private func rowKV(_ k: String, _ v: String) -> some View {
        HStack { Text(k).font(.system(size: 15)).foregroundStyle(cInk2.opacity(0.75)); Spacer(); Text(v).font(.system(size: 15, weight: .medium)).foregroundStyle(cInk) }
    }
    private func rowButton(_ t: String, _ icon: String, tint: Color? = nil, _ act: @escaping () -> Void) -> some View {
        Button { act() } label: {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.system(size: 16)).foregroundStyle(tint ?? cAccent).frame(width: 24)
                Text(t).font(.system(size: 15)).foregroundStyle(tint ?? cInk)
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 12)).foregroundStyle(cInk2.opacity(0.3))
            }.contentShape(Rectangle()).padding(.vertical, 4)
        }.buttonStyle(.plain)
    }
}
