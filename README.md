<div align="center">

# 🎬 Kino

**Ein privater, Netflix-artiger Media-Player für iPhone, iPad & Mac.**
Eigene Profile · 4K-HDR · Offline-Downloads für Flüge · Vorschläge.

</div>

---

## 📥 Installieren

### iPhone / iPad (ohne App Store, ohne PC-Kabel-Stress)
1. **SideStore** einmal einrichten (Anleitung: https://sidestore.io).
2. In SideStore **Sources** öffnen → **+** → diese URL einfügen:
   ```
   https://raw.githubusercontent.com/nicolasjankovich-netizen/kino/main/source/apps.json
   ```
3. **Kino** erscheint → **Get** → installiert. Danach **automatische Updates über WLAN**.

*Alternativ:* die fertige [`install/Kino.ipa`](install/Kino.ipa) direkt in SideStore laden.

### Mac
Aus dem Quellcode als Mac-App bauen (Mac Catalyst) — siehe [`kino/`](kino).

---

## 🔐 Login & Sicherheit
Kino hat einen **eigenen Login** (Profil + Passwort). Das ist bewusst so gebaut, dass die App
**ausschließlich Medien** sehen kann:

- **Kein Server-Zugriff:** Das Login-Token ist *media-scoped* — es öffnet nur die Film-/Serien-Funktionen.
  Server, Dateien, System-Einstellungen sind für die App **unerreichbar** (serverseitig geblockt).
- **Kein Geheimnis im Code:** Die App enthält **keinen** Admin-Token. Erst nach dem Login liegt ein
  scoped Token **verschlüsselt im Keychain**.
- **Brute-Force-geschützt:** Login mit Rate-Limit + starkem Passwort.
- **Einmal einloggen:** Danach bleibt man angemeldet — stressfrei, auch offline.

> Der Server ist über eine feste Adresse erreichbar (kein VPN nötig); jeder Zugriff ist login- & scope-geschützt.

---

## ✨ Features
- **Zwei Profile** mit getrennten „Weiterschauen"- & Favoriten-Listen
- **Apple-TV-artige Startseite** mit rotierenden Hero-Bannern & Genre-Reihen
- **Vorschläge-Tab** (beliebt & im Trend) — antippen zum Anfragen
- **Player** mit 4K-HDR (zuhause volle Qualität, unterwegs komprimiert), Untertitel, Resume
- **Offline-Downloads** (komprimiert) mit Download-Seite inkl. Live-Geschwindigkeit — perfekt für Flüge
- **iPhone · iPad · Mac** aus einer Codebasis (SwiftUI / Mac Catalyst)

<div align="center"><sub>🤖 Gebaut mit Claude Code</sub></div>
