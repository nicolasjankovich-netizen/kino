import SwiftUI

/// Schritt 1 — Zugang per Login-Key (kommt per Telegram aufs iPhone des Besitzers).
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
                Text("Kino").font(.system(size: 44, weight: .bold)).foregroundStyle(.white)

                if !requested {
                    Text("Zum Anmelden einen Zugang anfragen").font(.system(size: 14)).foregroundStyle(.white.opacity(0.6)).multilineTextAlignment(.center)
                    Button { Task { await request() } } label: {
                        HStack(spacing: 8) {
                            if acc.busy { ProgressView().tint(.white) }
                            Text("Zugang anfragen").font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
                        }.frame(width: 250).padding(.vertical, 14).background(RoundedRectangle(cornerRadius: 14).fill(cAccent))
                    }.buttonStyle(.plain).disabled(acc.busy)
                    Button { requested = true } label: {
                        Text("Ich habe schon einen Key").font(.system(size: 13)).foregroundStyle(.white.opacity(0.55))
                    }.buttonStyle(.plain)
                } else {
                    if let info { Text(info).font(.system(size: 13, weight: .light)).foregroundStyle(cCyan).multilineTextAlignment(.center).padding(.horizontal, 30) }
                    TextField("Login-Key", text: $keyInput)
                        .textFieldStyle(.plain).multilineTextAlignment(.center).foregroundStyle(.white)
                        .font(.system(size: 22, weight: .light)).tracking(4).textInputAutocapitalization(.characters)
                        .autocorrectionDisabled().submitLabel(.go)
                        .frame(width: 250).padding(14).glass(24).offset(x: shake ? -8 : 0)
                        .onSubmit { Task { await verify() } }
                    Button { Task { await verify() } } label: {
                        HStack(spacing: 8) {
                            if acc.busy { ProgressView().tint(.white) }
                            Text("Freischalten").font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
                        }.frame(width: 250).padding(.vertical, 14).background(RoundedRectangle(cornerRadius: 14).fill(cAccent))
                    }.buttonStyle(.plain).disabled(acc.busy || keyInput.count < 4)
                    Button { requested = false; info = nil } label: {
                        Text("Neuen Key anfragen").font(.system(size: 13)).foregroundStyle(.white.opacity(0.55))
                    }.buttonStyle(.plain)
                }
                Spacer(); Spacer()
            }.padding(30)
        }
    }

    private func request() async {
        let (delivered, fallback) = await acc.requestAccess()
        requested = true
        if delivered { info = "Ein Login-Key wurde ans iPhone geschickt. Key hier eingeben." }
        else if let fallback { info = "Key: \(fallback)"; keyInput = fallback }
        else { info = "Konnte keinen Key anfragen — Verbindung prüfen." }
    }
    private func verify() async {
        if await acc.verifyKey(keyInput) { return }
        withAnimation(.default.repeatCount(3, autoreverses: true).speed(6)) { shake.toggle() }
        info = "Key ungültig oder abgelaufen."; keyInput = ""
    }
}

/// Schritt 2 — Profil wählen (ohne Passwort), sobald das Gerät freigeschaltet ist.
struct ProfileView: View {
    @EnvironmentObject var acc: Accounts

    var body: some View {
        ZStack {
            KinoBackground()
            VStack(spacing: 30) {
                Spacer()
                Text("Wer schaut?").font(.system(size: 28, weight: .semibold)).foregroundStyle(.white)
                HStack(spacing: 30) {
                    ForEach(Accounts.all) { a in
                        Button { acc.selectProfile(a) } label: {
                            VStack(spacing: 10) {
                                Circle().fill(a.tint.opacity(0.85)).frame(width: 96, height: 96)
                                    .overlay(Text(String(a.name.prefix(1))).font(.system(size: 40, weight: .light)).foregroundStyle(.white))
                                    .shadow(color: a.tint.opacity(0.6), radius: 14)
                                Text(a.name).font(.system(size: 16, weight: .light)).foregroundStyle(.white.opacity(0.9))
                            }
                        }.buttonStyle(.plain)
                    }
                }
                Spacer(); Spacer()
            }.padding(30)
        }
    }
}
