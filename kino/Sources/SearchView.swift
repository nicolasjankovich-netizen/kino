import SwiftUI

/// Suchen + Film/Serie anfragen (fügt via Radarr/Sonarr hinzu — die einzige „Schreib"-Aktion).
struct SearchView: View {
    @EnvironmentObject var c: Cinema
    @State private var query = ""

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Anfragen").font(kTitle(30)).kChrome().foregroundStyle(cInk)
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
                    if !c.myRequests.isEmpty {
                        HStack { Text("Deine Anfragen").font(.system(size: 13, weight: .semibold)).kChrome().foregroundStyle(cInk2.opacity(0.75)); Spacer() }.padding(.top, 2)
                        ForEach(c.myRequests) { rq in requestRow(rq) }
                        if !c.results.isEmpty {
                            HStack { Text("Suche").font(.system(size: 13, weight: .semibold)).kChrome().foregroundStyle(cInk2.opacity(0.75)); Spacer() }.padding(.top, 6)
                        }
                    }
                    ForEach(c.results) { r in row(r) }
                    if c.results.isEmpty && !query.isEmpty && !c.busy {
                        Text("Nichts gefunden").label2().padding(.top, 30)
                    }
                }.padding(.horizontal, 18).padding(.bottom, 12)
            }
            .refreshable { await c.loadMyRequests(); await c.pollNotifications() }
            if !c.toast.isEmpty {
                Text(c.toast).font(.system(size: 12, weight: .light)).foregroundStyle(cCyan)
                    .multilineTextAlignment(.center).padding(.horizontal, 20).padding(.bottom, 6)
            }
        }
        .background(KinoBackground())
        .task {
            await c.loadMyRequests(); await c.pollNotifications()
            while !Task.isCancelled {                        // Status live halten, solange der Tab offen ist
                try? await Task.sleep(nanoseconds: 15_000_000_000)
                await c.loadMyRequests(); await c.pollNotifications()
            }
        }
    }

    /// Kompakte Zeile für eine eigene Anfrage mit Live-Status.
    private func requestRow(_ rq: KRequest) -> some View {
        HStack(spacing: 12) {
            Image(systemName: rq.symbol)
                .font(.system(size: 22))
                .foregroundStyle(rq.status == "available" ? cGood : (rq.status == "retrying" ? cWarn : cAccent))
                .symbolEffect(.pulse, isActive: rq.status == "searching" || rq.status == "downloading")
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(rq.title).font(.system(size: 15)).foregroundStyle(cInk).lineLimit(1)
                Text(rq.label).font(.system(size: 12, weight: .light)).foregroundStyle(cInk2.opacity(0.6))
            }
            Spacer()
            if rq.status == "downloading", let p = rq.progress {
                Text("\(Int(p * 100)) %").font(.system(size: 13, weight: .medium)).foregroundStyle(cAccent)
            }
        }.glass(18)
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
