import SwiftUI
import Security
import UIKit

// Login neu: KEIN Passwort mehr. Ablauf:
//  1) „Zugang anfragen" → Server erzeugt einen Login-Key, schickt ihn per Telegram aufs iPhone des Besitzers.
//  2) Key eingeben → media-only Session-Token (nur /api/media/*, nie Sysadmin) landet im Keychain.
//  3) Danach beide Profile (Nico/Ari) OHNE Passwort wählbar; App bleibt freigeschaltet (stressfrei).
struct Account: Identifiable, Equatable {
    let id: String        // nico/ari
    let name: String
    let tint: Color
}

enum Keychain {
    static func set(_ value: String, _ key: String) {
        let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrAccount as String: key]
        SecItemDelete(base as CFDictionary)
        var add = base; add[kSecValueData as String] = value.data(using: .utf8)!
        SecItemAdd(add as CFDictionary, nil)
    }
    static func get(_ key: String) -> String? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrAccount as String: key,
                                kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }
    static func delete(_ key: String) {
        SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrAccount as String: key] as CFDictionary)
    }
}

@MainActor
final class Accounts: ObservableObject {
    static let all = [
        Account(id: "nico", name: "Nico", tint: cBlue),
        Account(id: "ari",  name: "Ari",  tint: cAccent),
    ]
    @Published var unlocked = false        // Gerät hat gültiges Session-Token
    @Published var current: Account?       // gewähltes Profil
    @Published var busy = false

    @AppStorage("lastAccount") private var lastAccount = ""

    init() {
        if let tok = Keychain.get("kino_token"), !tok.isEmpty {
            kinoToken = tok; unlocked = true
            current = Accounts.all.first { $0.id == lastAccount }
        }
    }

    /// Zugang anfragen → Server schickt Key per Telegram aufs iPhone des Besitzers.
    /// Rückgabe: (per Telegram zugestellt?, Fallback-Key solange Telegram noch nicht steht).
    func requestAccess() async -> (delivered: Bool, fallbackKey: String?) {
        busy = true; defer { busy = false }
        guard let url = URL(string: backendBase + "/api/kino/request-access") else { return (false, nil) }
        var r = URLRequest(url: url); r.httpMethod = "POST"
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.httpBody = try? JSONSerialization.data(withJSONObject: ["device": UIDevice.current.name])
        struct R: Decodable { let delivered: Bool; let key: String? }
        guard let (d, _) = try? await URLSession.shared.data(for: r),
              let out = try? JSONDecoder().decode(R.self, from: d) else { return (false, nil) }
        return (out.delivered, out.key)
    }

    /// Key einlösen → Session-Token in den Keychain, App freischalten.
    func verifyKey(_ key: String) async -> Bool {
        busy = true; defer { busy = false }
        guard let url = URL(string: backendBase + "/api/kino/verify-key") else { return false }
        var r = URLRequest(url: url); r.httpMethod = "POST"
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.httpBody = try? JSONSerialization.data(withJSONObject: ["key": key.trimmingCharacters(in: .whitespaces)])
        struct R: Decodable { let token: String }
        guard let (d, resp) = try? await URLSession.shared.data(for: r),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let out = try? JSONDecoder().decode(R.self, from: d) else { return false }
        kinoToken = out.token; Keychain.set(out.token, "kino_token"); unlocked = true
        return true
    }

    func selectProfile(_ a: Account) { current = a; lastAccount = a.id }
    func switchProfile() { current = nil }   // zurück zur Profilauswahl (Token bleibt)
    func logout() {
        kinoToken = ""; Keychain.delete("kino_token"); unlocked = false; current = nil; lastAccount = ""
    }

    // ── getrennte Watch-States pro Profil ──
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
