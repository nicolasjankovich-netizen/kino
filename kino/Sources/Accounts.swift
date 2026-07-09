import SwiftUI
import Security
import UIKit

// Login-Flow (Punkt 3):
//  1) 2FA-Code anfragen → Server schickt einen Code per Telegram an den Besitzer.
//  2) Code eingeben → media-only Session-Token (nur /api/media/*, nie Sysadmin) in den Keychain.
//  3) User-Code eingeben → Server liefert die für diesen Code freigeschalteten Profile (rollenbasiert,
//     NICHT in der App hardcodiert). Es erscheinen nur erlaubte Profile → keine PIN nötig.
struct Account: Identifiable, Equatable, Codable {
    let id: String          // nico/ari/timu
    let name: String
    let tintName: String    // "blue"|"pink"|"kinekt" — kommt vom Server
    @MainActor var tint: Color { Account.color(tintName) }
    @MainActor static func color(_ s: String) -> Color {
        switch s {
        case "pink":   return cPink
        case "kinekt": return cCyan
        default:       return cBlue
        }
    }
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
    // Nur Fallback/Simulator-Katalog; die tatsächlich sichtbaren Profile liefert der Server.
    static let catalog = [
        Account(id: "nico", name: "Nico", tintName: "blue"),
        Account(id: "ari",  name: "Ari",  tintName: "pink"),
        Account(id: "timu", name: "Timu", tintName: "kinekt"),
    ]
    @Published var unlocked = false            // Gerät hat gültiges 2FA-Session-Token
    @Published var allowedProfiles: [Account]? // vom User-Code freigeschaltet (nil = noch kein Code)
    @Published var current: Account?           // gewähltes Profil
    @Published var isAdmin = false             // sieht alle Profile / Admin-Funktionen
    @Published var canDebug = false            // darf den versteckten Debug-Screen (Punkt 5)
    @Published var busy = false
    @Published var themeTick = 0               // hochzählen erzwingt UI-Neuaufbau bei Theme-Wechsel

    /// Default-Theme eines Profils (rollenbasiert): Ari = Brandy-Easter-Egg, sonst Kinekt.
    static func nativeTheme(_ id: String) -> KTheme { id == "ari" ? .brandy : .kinekt }
    /// Aktives Theme aus Profil + Apple-TV-Toggle ableiten und global setzen.
    func applyTheme() {
        guard let id = current?.id else { appTheme = .kinekt; return }   // Login/Profilwahl = Kinekt-Identität
        appTheme = UserDefaults.standard.bool(forKey: "appletv_\(id)") ? .appletv : Accounts.nativeTheme(id)
    }
    func appleTVOn() -> Bool {
        guard let id = current?.id else { return false }
        return UserDefaults.standard.bool(forKey: "appletv_\(id)")
    }
    /// Apple-TV-Optik für das aktuelle Profil an/aus (persistiert pro Profil) + UI neu aufbauen.
    func setAppleTV(_ on: Bool) {
        guard let id = current?.id else { return }
        UserDefaults.standard.set(on, forKey: "appletv_\(id)")
        applyTheme(); themeTick += 1
    }

    @AppStorage("lastAccount") private var lastAccount = ""

    init() {
        if let tok = Keychain.get("kino_token"), !tok.isEmpty {
            kinoToken = tok; unlocked = true
            restoreProfiles()
            current = allowedProfiles?.first { $0.id == lastAccount }
            applyTheme()
        }
        #if targetEnvironment(simulator)
        // DEMO nur im Simulator: direkt als Nico rein (Kinekt-Look = App-Identität). Token aus der
        // Launch-Umgebung, nicht im Quellcode. KINO_DEMO_PROFILE kann das Profil überschreiben.
        if !unlocked, let demo = ProcessInfo.processInfo.environment["KINO_DEMO_TOKEN"], !demo.isEmpty {
            kinoToken = demo; unlocked = true
            allowedProfiles = Accounts.catalog; isAdmin = true; canDebug = true
            let pid = ProcessInfo.processInfo.environment["KINO_DEMO_PROFILE"] ?? "nico"
            current = Accounts.catalog.first { $0.id == pid } ?? Accounts.catalog.first
            applyTheme()
        }
        #endif
    }

    // ── Schritt 1+2: 2FA ──────────────────────────────────────────────────
    /// 2FA-Code anfragen → Server schickt ihn per Telegram an den Besitzer.
    /// Rückgabe: (zugestellt?, Fallback-Code solange Telegram nicht steht).
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

    /// 2FA-Code einlösen → Session-Token in den Keychain, Gerät freischalten.
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

    // ── Schritt 3: User-Code → erlaubte Profile (rollenbasiert, Server entscheidet) ──
    func submitUserCode(_ code: String) async -> Bool {
        busy = true; defer { busy = false }
        guard let url = URL(string: backendBase + "/api/kino/profiles") else { return false }
        var r = URLRequest(url: url); r.httpMethod = "POST"
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.setValue("Bearer \(kinoToken)", forHTTPHeaderField: "Authorization")
        r.httpBody = try? JSONSerialization.data(withJSONObject: ["code": code.trimmingCharacters(in: .whitespaces)])
        struct P: Decodable { let id: String; let name: String; let tint: String }
        struct R: Decodable { let profiles: [P]; let admin: Bool; let debug: Bool }
        guard let (d, resp) = try? await URLSession.shared.data(for: r),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let out = try? JSONDecoder().decode(R.self, from: d), !out.profiles.isEmpty else { return false }
        let profs = out.profiles.map { Account(id: $0.id, name: $0.name, tintName: $0.tint) }
        allowedProfiles = profs; isAdmin = out.admin; canDebug = out.debug
        saveProfiles()
        if profs.count == 1 { selectProfile(profs[0]) }   // genau ein Profil → direkt rein
        return true
    }

    private func saveProfiles() {
        let d = UserDefaults.standard
        if let data = try? JSONEncoder().encode(allowedProfiles) { d.set(data, forKey: "allowedProfiles") }
        d.set(isAdmin, forKey: "cap_admin"); d.set(canDebug, forKey: "cap_debug")
    }
    private func restoreProfiles() {
        let d = UserDefaults.standard
        if let data = d.data(forKey: "allowedProfiles"),
           let profs = try? JSONDecoder().decode([Account].self, from: data), !profs.isEmpty {
            allowedProfiles = profs
        }
        isAdmin = d.bool(forKey: "cap_admin"); canDebug = d.bool(forKey: "cap_debug")
    }

    func selectProfile(_ a: Account) { current = a; lastAccount = a.id; applyTheme() }
    func switchProfile() { current = nil; applyTheme() }          // zurück zur Profilauswahl (Code bleibt)
    /// User-Code zurücksetzen (anderer Nutzer am selben Gerät) — 2FA-Token bleibt.
    func resetUserCode() {
        allowedProfiles = nil; current = nil; isAdmin = false; canDebug = false; applyTheme()
        UserDefaults.standard.removeObject(forKey: "allowedProfiles")
    }
    func logout() {
        kinoToken = ""; Keychain.delete("kino_token"); unlocked = false; current = nil; lastAccount = ""
        allowedProfiles = nil; isAdmin = false; canDebug = false; applyTheme()
        UserDefaults.standard.removeObject(forKey: "allowedProfiles")
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
