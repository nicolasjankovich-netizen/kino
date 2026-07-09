import SwiftUI

/// Suchen + Film/Serie anfragen (fügt via Radarr/Sonarr hinzu — die einzige „Schreib"-Aktion).
struct SearchView: View {
    @EnvironmentObject var c: Cinema
    @State private var query = ""
    @State private var seasonSheet: KResult?                     // Serie → Staffel-Auswahl vor dem Anfragen
    @AppStorage("reqQuality") private var reqQuality = "1080p"   // Qualität für neue Anfragen

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Anfragen").font(kTitle(30)).kChrome().foregroundStyle(cInk)
                Spacer()
            }.padding(.horizontal, 20).padding(.top, 14)

            KindSwitch(kind: $c.kind) { Task { await c.search(query) } }.padding(.horizontal, 18)

            HStack(spacing: 8) {
                Image(systemName: "4k.tv").foregroundStyle(cInk2.opacity(0.5))
                Text("Anfrage-Qualität").font(.system(size: 13)).foregroundStyle(cInk2.opacity(0.7))
                Spacer()
                Picker("Qualität", selection: $reqQuality) {
                    Text("1080p").tag("1080p")
                    Text("4K").tag("4k")
                }.pickerStyle(.segmented).frame(width: 150)
            }.padding(.horizontal, 18)

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
        .sheet(item: $seasonSheet) { r in
            SeasonRequestSheet(result: r).environmentObject(c)
                .presentationDetents([.medium, .large])
        }
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
                Button {
                    if c.kind == .series { seasonSheet = r }   // Serie: erst Staffeln wählen
                    else { c.request(r) }
                } label: {
                    VStack(spacing: 2) {
                        Image(systemName: "plus.circle.fill").font(.system(size: 26)).foregroundStyle(cAccent)
                        Text("Anfragen").font(.system(size: 9, weight: .medium)).foregroundStyle(cAccent)
                    }
                }.buttonStyle(.plain)
            }
        }.glass(18)
    }
}

/// Staffel-Auswahl vor dem Anfragen einer Serie: lädt die Staffel-Liste aus Sonarr
/// (funktioniert auch, wenn die Serie noch gar nicht auf dem Server ist) und fragt
/// dann gezielt nur die gewählten Staffeln an.
struct SeasonRequestSheet: View {
    let result: KResult
    @EnvironmentObject var c: Cinema
    @Environment(\.dismiss) private var dismiss
    @State private var options: [SeasonOption] = []
    @State private var selected: Set<Int> = []
    @State private var loading = true
    @State private var inLibrary = false

    var body: some View {
        ZStack {
            KinoBackground()
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(result.title).font(kTitle(22)).foregroundStyle(cInk).lineLimit(1)
                        Text(inLibrary ? "Staffeln nachladen" : "Welche Staffeln willst du?")
                            .font(.system(size: 13)).foregroundStyle(cInk2.opacity(0.6))
                    }
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 24)).foregroundStyle(cInk2.opacity(0.5))
                    }.buttonStyle(.plain)
                }.padding(.top, 18)

                if loading {
                    HStack { Spacer(); ProgressView().tint(cInk); Spacer() }.padding(.top, 30)
                } else if options.isEmpty {
                    Text("Keine Staffel-Infos gefunden — es wird die ganze Serie angefragt.")
                        .font(.system(size: 13)).foregroundStyle(cInk2.opacity(0.6))
                } else {
                    HStack {
                        Button(selected.count == options.count ? "Keine" : "Alle") {
                            selected = selected.count == options.count ? [] : Set(options.map(\.season))
                        }
                        .font(.system(size: 13, weight: .medium)).foregroundStyle(cAccent).buttonStyle(.plain)
                        Spacer()
                        Text("\(selected.count) gewählt").font(.system(size: 12)).foregroundStyle(cInk2.opacity(0.5))
                    }
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 8)], spacing: 8) {
                            ForEach(options) { o in
                                let on = selected.contains(o.season)
                                Button {
                                    if on { selected.remove(o.season) } else { selected.insert(o.season) }
                                } label: {
                                    VStack(spacing: 3) {
                                        Text("Staffel \(o.season)")
                                            .font(.system(size: 14, weight: on ? .semibold : .regular))
                                            .foregroundStyle(on ? (girlie ? .white : .black) : cInk)
                                        HStack(spacing: 4) {
                                            if let e = o.episodes { Text("\(e) Folgen").font(.system(size: 10)) }
                                            if let h = o.have, h > 0 {
                                                Image(systemName: "checkmark.circle.fill").font(.system(size: 9))
                                            }
                                        }
                                        .foregroundStyle(on ? (girlie ? Color.white.opacity(0.8) : .black.opacity(0.6)) : cInk2.opacity(0.5))
                                    }
                                    .frame(maxWidth: .infinity).padding(.vertical, 10)
                                    .background(RoundedRectangle(cornerRadius: 12).fill(on
                                        ? AnyShapeStyle(girlie ? AnyShapeStyle(cPink) : AnyShapeStyle(Color.white))
                                        : AnyShapeStyle(Color.white.opacity(0.08))))
                                }.buttonStyle(.plain)
                            }
                        }
                    }
                }

                Button {
                    c.request(result, seasons: options.isEmpty ? nil : Array(selected).sorted())
                    dismiss()
                } label: {
                    Text(requestLabel)
                        .font(.system(size: 16, weight: .semibold)).foregroundStyle(girlie ? .white : .black)
                        .frame(maxWidth: .infinity).padding(.vertical, 13)
                        .background(Capsule().fill(canSend
                            ? (girlie ? AnyShapeStyle(LinearGradient(colors: [cPink, cLav], startPoint: .leading, endPoint: .trailing)) : AnyShapeStyle(Color.white))
                            : AnyShapeStyle(cInk2.opacity(0.3))))
                }.buttonStyle(.plain).disabled(!canSend).padding(.bottom, 16)
            }
            .padding(.horizontal, 18)
        }
        .task {
            if let r = await c.seasonOptions(term: result.title, key: result.key) {
                inLibrary = r.inLibrary
                options = r.seasons
                // sinnvolle Vorauswahl: neueste Staffel (bzw. alles, wenn nur wenige)
                if options.count <= 2 { selected = Set(options.map(\.season)) }
                else if let last = options.last { selected = [last.season] }
            }
            loading = false
        }
    }

    private var canSend: Bool { !loading && (options.isEmpty || !selected.isEmpty) }
    private var requestLabel: String {
        if options.isEmpty { return "Ganze Serie anfragen" }
        if selected.count == options.count { return "Alle Staffeln anfragen" }
        return selected.count == 1 ? "Staffel \(selected.first!) anfragen" : "\(selected.count) Staffeln anfragen"
    }
}
