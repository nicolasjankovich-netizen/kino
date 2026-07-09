import SwiftUI

/// Schritt 1+2 — Gerät per 2FA-Code freischalten (Code kommt per Telegram aufs iPhone des Besitzers).
struct AccessView: View {
    @EnvironmentObject var acc: Accounts
    @State private var requested = false
    @State private var keyInput = ""
    @State private var info: String?
    @State private var shake = false

    var body: some View {
        ZStack {
            KinoBackground()
            VStack(spacing: 22) {
                Spacer()
                Text("Kino").font(.system(size: 44, weight: .bold)).foregroundStyle(cInk)
                Image(systemName: "lock.shield").font(.system(size: 26)).foregroundStyle(cAccent.opacity(0.9))

                if !requested {
                    Text("Zum Anmelden einen 2FA-Code anfragen").font(.system(size: 14)).foregroundStyle(cInk2.opacity(0.6)).multilineTextAlignment(.center)
                    Button { Task { await request() } } label: {
                        HStack(spacing: 8) {
                            if acc.busy { ProgressView().tint(cInk) }
                            Text("2FA-Code anfragen").font(.system(size: 16, weight: .semibold)).foregroundStyle(cInk)
                        }.frame(width: 250).padding(.vertical, 14).background(RoundedRectangle(cornerRadius: 14).fill(cAccent))
                    }.buttonStyle(.plain).disabled(acc.busy)
                    Button { requested = true } label: {
                        Text("Ich habe schon einen Code").font(.system(size: 13)).foregroundStyle(cInk2.opacity(0.55))
                    }.buttonStyle(.plain)
                } else {
                    if let info { Text(info).font(.system(size: 13, weight: .light)).foregroundStyle(cCyan).multilineTextAlignment(.center).padding(.horizontal, 30) }
                    TextField("2FA-Code", text: $keyInput)
                        .textFieldStyle(.plain).multilineTextAlignment(.center).foregroundStyle(cInk)
                        .font(.system(size: 22, weight: .light)).tracking(4).textInputAutocapitalization(.characters)
                        .autocorrectionDisabled().submitLabel(.go)
                        .frame(width: 250).padding(14).glass(24).offset(x: shake ? -8 : 0)
                        .onSubmit { Task { await verify() } }
                    Button { Task { await verify() } } label: {
                        HStack(spacing: 8) {
                            if acc.busy { ProgressView().tint(cInk) }
                            Text("Freischalten").font(.system(size: 16, weight: .semibold)).foregroundStyle(cInk)
                        }.frame(width: 250).padding(.vertical, 14).background(RoundedRectangle(cornerRadius: 14).fill(cAccent))
                    }.buttonStyle(.plain).disabled(acc.busy || keyInput.count < 4)
                    Button { requested = false; info = nil } label: {
                        Text("Neuen Code anfragen").font(.system(size: 13)).foregroundStyle(cInk2.opacity(0.55))
                    }.buttonStyle(.plain)
                }
                Spacer(); Spacer()
            }.padding(30)
        }
    }

    private func request() async {
        let (delivered, fallback) = await acc.requestAccess()
        requested = true
        if delivered { info = "Ein 2FA-Code wurde ans iPhone des Besitzers geschickt. Code hier eingeben." }
        else if let fallback { info = "Code: \(fallback)"; keyInput = fallback }
        else { info = "Konnte keinen Code anfragen — Verbindung prüfen." }
    }
    private func verify() async {
        if await acc.verifyKey(keyInput) { return }
        withAnimation(.default.repeatCount(3, autoreverses: true).speed(6)) { shake.toggle() }
        info = "Code ungültig oder abgelaufen."; keyInput = ""
    }
}

/// Schritt 3 — persönlichen User-Code eingeben. Der Server gibt genau die Profile frei,
/// die dieser Code sehen darf (rollenbasiert). Keine PIN.
struct UserCodeView: View {
    @EnvironmentObject var acc: Accounts
    @State private var code = ""
    @State private var info: String?
    @State private var shake = false

    var body: some View {
        ZStack {
            KinoBackground()
            VStack(spacing: 22) {
                Spacer()
                Text("Wer bist du?").font(.system(size: 28, weight: .semibold)).foregroundStyle(cInk)
                Text("Gib deinen persönlichen Code ein.").font(.system(size: 14)).foregroundStyle(cInk2.opacity(0.6)).multilineTextAlignment(.center)
                if let info { Text(info).font(.system(size: 13, weight: .light)).foregroundStyle(cWarn).multilineTextAlignment(.center).padding(.horizontal, 30) }
                TextField("User-Code", text: $code)
                    .textFieldStyle(.plain).multilineTextAlignment(.center).foregroundStyle(cInk)
                    .font(.system(size: 22, weight: .light)).tracking(4).textInputAutocapitalization(.characters)
                    .autocorrectionDisabled().submitLabel(.go)
                    .frame(width: 250).padding(14).glass(24).offset(x: shake ? -8 : 0)
                    .onSubmit { Task { await submit() } }
                Button { Task { await submit() } } label: {
                    HStack(spacing: 8) {
                        if acc.busy { ProgressView().tint(cInk) }
                        Text("Weiter").font(.system(size: 16, weight: .semibold)).foregroundStyle(cInk)
                    }.frame(width: 250).padding(.vertical, 14).background(RoundedRectangle(cornerRadius: 14).fill(cAccent))
                }.buttonStyle(.plain).disabled(acc.busy || code.count < 2)
                Button { acc.logout() } label: {
                    Text("Abmelden").font(.system(size: 13)).foregroundStyle(cInk2.opacity(0.5))
                }.buttonStyle(.plain)
                Spacer(); Spacer()
            }.padding(30)
        }
    }

    private func submit() async {
        if await acc.submitUserCode(code) { return }
        withAnimation(.default.repeatCount(3, autoreverses: true).speed(6)) { shake.toggle() }
        info = "Unbekannter Code."; code = ""
    }
}

/// Profil-Avatar. Normale Profile = farbiger Kreis mit Initiale. Timu (tint „kinekt") ist in die
/// Kinekt-Bildsprache eingebettet: Liquid-Glass-Glow (Cyan→Violett→Magenta) statt flacher Farbe —
/// gleiche Kachel-Struktur wie die anderen, nur mit dem Marken-Look.
struct ProfileAvatar: View {
    let account: Account
    var size: CGFloat = 96

    var body: some View {
        if account.tintName == "kinekt" {
            ZStack {
                Circle()   // weicher Glow-Halo
                    .fill(AngularGradient(colors: [cCyan, cBlue, cLav, cPink, cCyan],
                                          center: .center))
                    .frame(width: size, height: size).blur(radius: 16).opacity(0.75)
                Circle()   // Glaskörper
                    .fill(AngularGradient(colors: [cCyan, cBlue, cLav, cPink, cCyan],
                                          center: .center))
                    .frame(width: size, height: size)
                    .overlay(Circle().strokeBorder(.white.opacity(0.35), lineWidth: 1))
                    .overlay(
                        Circle().fill(RadialGradient(colors: [.white.opacity(0.35), .clear],
                                                     center: .init(x: 0.32, y: 0.28),
                                                     startRadius: 1, endRadius: size * 0.6))
                    )
                Image(systemName: "sparkles").font(.system(size: size * 0.34, weight: .light))
                    .foregroundStyle(.white)
            }
            .shadow(color: cCyan.opacity(0.55), radius: 16)
        } else {
            Circle().fill(account.tint.opacity(0.85)).frame(width: size, height: size)
                .overlay(Text(String(account.name.prefix(1))).font(.system(size: size * 0.42, weight: .light)).foregroundStyle(cInk))
                .shadow(color: account.tint.opacity(0.6), radius: 14)
        }
    }
}

/// Profilwahl — zeigt nur die vom User-Code freigeschalteten Profile. Kein Passwort, keine PIN.
struct ProfileView: View {
    @EnvironmentObject var acc: Accounts

    var body: some View {
        ZStack {
            KinoBackground()
            VStack(spacing: 30) {
                Spacer()
                Text("Wer schaut?").font(.system(size: 28, weight: .semibold)).foregroundStyle(cInk)
                HStack(spacing: 30) {
                    ForEach(acc.allowedProfiles ?? []) { a in
                        Button { acc.selectProfile(a) } label: {
                            VStack(spacing: 10) {
                                ProfileAvatar(account: a, size: 96)
                                Text(a.name).font(.system(size: 16, weight: .light)).foregroundStyle(cInk2.opacity(0.9))
                            }
                        }.buttonStyle(.plain)
                    }
                }
                Button { acc.resetUserCode() } label: {
                    Text("Anderer Code").font(.system(size: 13)).foregroundStyle(cInk2.opacity(0.5))
                }.buttonStyle(.plain).padding(.top, 10)
                Spacer(); Spacer()
            }.padding(30)
        }
    }
}
