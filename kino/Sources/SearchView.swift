import SwiftUI

/// Suchen + Film/Serie anfragen (fügt via Radarr/Sonarr hinzu — die einzige „Schreib"-Aktion).
struct SearchView: View {
    @EnvironmentObject var c: Cinema
    @State private var query = ""

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Anfragen").font(kTitle(30)).foregroundStyle(cInk)
                Spacer()
            }.padding(.horizontal, 20).padding(.top, 14)

            KindSwitch(kind: $c.kind) { Task { await c.search(query) } }.padding(.horizontal, 18)

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(cInk2.opacity(0.5))
                TextField("Film oder Serie suchen …", text: $query).foregroundStyle(cInk)
                    .autocorrectionDisabled().textInputAutocapitalization(.words)
                    .onSubmit { Task { await c.search(query) } }
                if c.busy { ProgressView().tint(cInk) }
            }.glass(28).padding(.horizontal, 18)

            ScrollView {
                VStack(spacing: 12) {
                    ForEach(c.results) { r in row(r) }
                    if c.results.isEmpty && !query.isEmpty && !c.busy {
                        Text("Nichts gefunden").label2().padding(.top, 30)
                    }
                }.padding(.horizontal, 18).padding(.bottom, 12)
            }
            if !c.toast.isEmpty {
                Text(c.toast).font(.system(size: 12, weight: .light)).foregroundStyle(cCyan).padding(.bottom, 6)
            }
        }
        .background(KinoBackground())
    }

    private func row(_ r: KResult) -> some View {
        HStack(spacing: 12) {
            CachedImage(url: URL(string: r.poster ?? "")) { img in
                img.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.08))
                    .overlay(Image(systemName: "photo").foregroundStyle(cInk2.opacity(0.25)))
            }
            .frame(width: 52, height: 78).clipShape(RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 3) {
                Text(r.title).font(.system(size: 15)).foregroundStyle(cInk).lineLimit(1)
                if let y = r.year { Text(String(y)).font(.system(size: 12, weight: .light)).foregroundStyle(cInk2.opacity(0.5)) }
                Text(r.overview ?? "").font(.system(size: 11, weight: .light)).foregroundStyle(cInk2.opacity(0.5)).lineLimit(2)
            }
            Spacer()
            if r.added {
                VStack(spacing: 2) {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 24)).foregroundStyle(cGood)
                    Text("Dabei").font(.system(size: 9, weight: .medium)).foregroundStyle(cGood)
                }
            } else {
                Button { c.request(r) } label: {
                    VStack(spacing: 2) {
                        Image(systemName: "plus.circle.fill").font(.system(size: 26)).foregroundStyle(cAccent)
                        Text("Anfragen").font(.system(size: 9, weight: .medium)).foregroundStyle(cAccent)
                    }
                }.buttonStyle(.plain)
            }
        }.glass(18)
    }
}
