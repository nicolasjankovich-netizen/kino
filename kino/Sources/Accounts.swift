import SwiftUI
import Security

// Zwei Profile mit getrennten Watch-States. Auth läuft jetzt SERVERSEITIG (media-only Token):
// die App bettet KEINEN Admin-Token mehr ein — nach dem Login liegt nur ein scoped Token
// (nur /api/media/*, niemals Sysadmin) sicher im Keychain. Bleibt eingeloggt = stressfrei.
struct Account: Identifiable, Equatable {
    let id: String        // stabiler Key (nico/ari)
    let name: String
    let tint: Color
}

/// Minimaler Keychain-Wrapper (Token verschlüsselt & app-privat gespeichert).
enum Keychain {
    static func set(_ value: String, _ key: String) {
        let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrAccount as String: key]
        SecItemDelete(base as CFDictionary)
        var add = base; add[kSecValueData as String] = value.data(using: .utf8)!
        SecItemAdd(add as CFDictionary, nil)
    }
    static func get(_ key: String) -> String? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                kSecAttrAccount as String: key,
                                kSecReturnData as String: true,
                                kSecMatchLimit as String: kSecMatchLimitOne]
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess,
              let d = out as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }
    static func delete(_ key: String) {
        SecItemDelete([kSecClass as String: kSecClassGenericPassword,
                       kSecAttrAccount as String: key] as CFDictionary)
    }
}

@MainActor
final class Accounts: ObservableObject {
    static let all = [
        Account(id: "nico", name: "Nico", tint: cBlue),
        Account(id: "ari",  name: "Ari",  tint: cAccent),
    ]
    @Published var current: Account?
    @Published var loggingIn = false

    init() {
        // Beim Start: gespeichertes Token → eingeloggt bleiben (kein erneutes Passwort).
        if let uid = Keychain.get("kino_user"), let tok = Keychain.get("kino_token"),
           let a = Accounts.all.first(where: { $0.id == uid }) {
            kinoToken = tok
            current = a
        }
    }

    /// Serverseitiger Login → scoped Token in den Keychain, eingeloggt bleiben.
    func login(_ a: Account, _ pass: String) async -> Bool {
        loggingIn = true; defer { loggingIn = false }
        guard let url = URL(string: backendBase + "/api/kino/login") else { return false }
        var r = URLRequest(url: url); r.httpMethod = "POST"
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.httpBody = try? JSONSerialization.data(withJSONObject: ["user": a.id, "pass": pass])
        struct R: Decodable { let token: String }
        guard let (d, resp) = try? await URLSession.shared.data(for: r),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let out = try? JSONDecoder().decode(R.self, from: d) else { return false }
        kinoToken = out.token
        Keychain.set(out.token, "kino_token")
        Keychain.set(a.id, "kino_user")
        current = a
        return true
    }

    func logout() {
        kinoToken = ""
        Keychain.delete("kino_token"); Keychain.delete("kino_user")
        current = nil
    }

    // ── getrennte Watch-States pro Account (Favoriten / Continue Watching) ──
    private func key(_ suffix: String) -> String { "\(current?.id ?? "none")_\(suffix)" }

    func isFav(_ uid: String) -> Bool { favs().contains(uid) }
    func toggleFav(_ uid: String) {
        var f = favs(); if f.contains(uid) { f.remove(uid) } else { f.insert(uid) }
        UserDefaults.standard.set(Array(f), forKey: key("favs")); objectWillChange.send()
    }
    func favs() -> Set<String> { Set((UserDefaults.standard.array(forKey: key("favs")) as? [String]) ?? []) }

    func progress(_ uid: String) -> Double { UserDefaults.standard.double(forKey: key("prog_\(uid)")) }
    func setProgress(_ uid: String, _ p: Double) {
        UserDefaults.standard.set(p, forKey: key("prog_\(uid)"))
        var h = history(); h.removeAll { $0 == uid }; h.insert(uid, at: 0)
        UserDefaults.standard.set(Array(h.prefix(30)), forKey: key("history")); objectWillChange.send()
    }
    func history() -> [String] { (UserDefaults.standard.array(forKey: key("history")) as? [String]) ?? [] }

    func continueWatching(_ pool: [KItem]) -> [KItem] {
        history().compactMap { uid in pool.first { $0.uid == uid } }
            .filter { let p = progress($0.uid); return p > 0.02 && p < 0.95 }
    }
    func favorites(_ pool: [KItem]) -> [KItem] { pool.filter { favs().contains($0.uid) } }
}

struct LoginView: View {
    @EnvironmentObject var acc: Accounts
    @State private var pass = ""
    @State private var pick = Accounts.all.first!
    @State private var shake = false
    @State private var failed = false

    var body: some View {
        ZStack {
            KinoBackground()
            VStack(spacing: 26) {
                Spacer()
                Text("kino").font(.system(size: 40, weight: .thin)).tracking(8).foregroundStyle(.white)
                Text("wer schaut?").label2()

                HStack(spacing: 20) {
                    ForEach(Accounts.all) { a in
                        Button { pick = a; pass = ""; failed = false } label: {
                            VStack(spacing: 8) {
                                Circle().fill(a.tint.opacity(pick == a ? 0.9 : 0.25))
                                    .frame(width: 76, height: 76)
                                    .overlay(Text(String(a.name.prefix(1))).font(.system(size: 30, weight: .light)).foregroundStyle(.white))
                                    .shadow(color: a.tint.opacity(pick == a ? 0.7 : 0), radius: 12)
                                Text(a.name).font(.system(size: 14, weight: pick == a ? .regular : .light))
                                    .foregroundStyle(.white.opacity(pick == a ? 1 : 0.5))
                            }
                        }.buttonStyle(.plain)
                    }
                }.padding(.vertical, 8)

                SecureField("Passwort", text: $pass)
                    .textFieldStyle(.plain).multilineTextAlignment(.center).foregroundStyle(.white)
                    .textContentType(.password).submitLabel(.go)
                    .frame(width: 220).padding(12).glass(24)
                    .offset(x: shake ? -8 : 0)
                    .onSubmit(tryLogin)

                Button(action: tryLogin) {
                    ZStack {
                        if acc.loggingIn { ProgressView().tint(.black) }
                        else { Text("los").font(.system(size: 16, weight: .light)).tracking(2).foregroundStyle(.black) }
                    }
                    .frame(width: 220).padding(.vertical, 13)
                    .background(Capsule().fill(pick.tint))
                }.buttonStyle(.plain).disabled(acc.loggingIn)

                if failed { Text("falsches passwort").font(.system(size: 12, weight: .light)).foregroundStyle(cWarn) }
                Spacer(); Spacer()
            }.padding(30)
        }
    }

    private func tryLogin() {
        let p = pass
        Task {
            if await acc.login(pick, p) { return }
            failed = true; pass = ""
            withAnimation(.default.repeatCount(3, autoreverses: true).speed(6)) { shake.toggle() }
        }
    }
}
