import SwiftUI

/// Einstellungen. Kern: Apple-TV-Optik an/aus (pro Profil gespeichert). Ari startet im Brandy-Look,
/// Nico/Timu im Kinekt-Look — der Toggle schaltet jeweils auf die cleane Apple-TV-Optik um.
struct SettingsView: View {
    @EnvironmentObject var acc: Accounts
    @Environment(\.dismiss) private var dismiss
    @State private var appleTV = false

    private var nativeName: String {
        Accounts.nativeTheme(acc.current?.id ?? "nico") == .brandy ? "Brandy" : "Kinekt"
    }

    var body: some View {
        ZStack {
            KinoBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text("Einstellungen").font(kTitle(26)).foregroundStyle(girlie ? cPink : cInk)
                        Spacer()
                        Button { dismiss() } label: { Image(systemName: "xmark.circle.fill").font(.system(size: 26)).foregroundStyle(cInk2.opacity(0.6)) }.buttonStyle(.plain)
                    }.padding(.top, 8)

                    section("Optik") {
                        Toggle(isOn: $appleTV) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Apple-TV-Optik").font(.system(size: 16)).foregroundStyle(cInk)
                                Text(appleTV ? "cleaner, dunkler Apple-TV-Look"
                                              : "Standard: \(nativeName)-Look")
                                    .font(.system(size: 12)).foregroundStyle(cInk2.opacity(0.55))
                            }
                        }
                        .tint(cAccent)
                        .onChange(of: appleTV) { _, on in acc.setAppleTV(on) }
                    }

                    section("Konto") {
                        rowButton("Profil wechseln", "person.2.arrow.trianglehead.counterclockwise") { acc.switchProfile(); dismiss() }
                        rowButton("Anderer User-Code", "key") { acc.resetUserCode(); dismiss() }
                        rowButton("Abmelden", "rectangle.portrait.and.arrow.right", tint: cWarn) { acc.logout(); dismiss() }
                    }
                }
                .padding(.horizontal, 18).padding(.bottom, 30)
            }
        }
        .onAppear { appleTV = acc.appleTVOn() }
    }

    private func section<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title.uppercased()).font(.system(size: 11, weight: .semibold)).tracking(1.2).foregroundStyle(cInk2.opacity(0.5))
            content()
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16).fill(girlie ? Color.white.opacity(0.5) : Color.white.opacity(0.06)))
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
