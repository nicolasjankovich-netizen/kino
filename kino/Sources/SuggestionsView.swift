import SwiftUI

/// „Vorschläge" — beliebte & trendende Titel aus Jellyseerr. Antippen → anfragen,
/// landet dann (nach Download) automatisch in der Bibliothek.
struct SuggestionsView: View {
    @EnvironmentObject var c: Cinema
    @State private var kind: Cinema.Kind = .movie
    @State private var detail: Suggestion?

    private let cols = [GridItem(.adaptive(minimum: 110), spacing: 14)]

    var body: some View {
        ZStack(alignment: .bottom) {
            KinoBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    picker
                    if c.suggestions.isEmpty {
                        Text(c.busy ? "Lädt Vorschläge …" : "Keine Vorschläge")
                            .label2().frame(maxWidth: .infinity).padding(.top, 60)
                    } else {
                        LazyVGrid(columns: cols, spacing: 18) {
                            ForEach(c.suggestions) { s in tile(s) }
                        }.padding(.horizontal, 18)
                    }
                }.padding(.top, 12).padding(.bottom, 30)
            }
            if !c.toast.isEmpty {
                Text(c.toast).font(.system(size: 13, weight: .light)).foregroundStyle(.white)
                    .padding(.horizontal, 18).padding(.vertical, 11)
                    .glassEffect(.regular, in: .capsule).padding(.bottom, 20)
            }
        }
        .task { await c.loadSuggestions(kind) }
        .sheet(item: $detail) { s in suggestionSheet(s) }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Vorschläge").font(.system(size: 30, weight: .bold)).foregroundStyle(.white)
            Text("Beliebt & im Trend — antippen zum Anfragen").font(.system(size: 13, weight: .regular)).foregroundStyle(.white.opacity(0.55))
        }.padding(.horizontal, 18)
    }

    private var picker: some View {
        HStack(spacing: 10) {
            ForEach(Cinema.Kind.allCases, id: \.self) { k in
                Button {
                    kind = k
                    Task { await c.loadSuggestions(k) }
                } label: {
                    Text(k.label)
                        .font(.system(size: 14, weight: kind == k ? .semibold : .regular))
                        .foregroundStyle(kind == k ? .black : .white.opacity(0.7))
                        .padding(.horizontal, 18).padding(.vertical, 9)
                        .background(Capsule().fill(kind == k ? Color.white : .white.opacity(0.1)))
                }.buttonStyle(.plain)
            }
            Spacer()
        }.padding(.horizontal, 18)
    }

    private func tile(_ s: Suggestion) -> some View {
        let req = c.requested.contains(s.id)
        return Button { detail = s } label: {
            VStack(alignment: .leading, spacing: 6) {
                ZStack(alignment: .topTrailing) {
                    AsyncImage(url: URL(string: s.poster ?? "")) { img in
                        img.resizable().aspectRatio(2/3, contentMode: .fill)
                    } placeholder: {
                        RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.08))
                            .aspectRatio(2/3, contentMode: .fit)
                            .overlay(Image(systemName: "film").foregroundStyle(.white.opacity(0.25)))
                    }
                    .frame(height: 165).frame(maxWidth: .infinity).clipShape(RoundedRectangle(cornerRadius: 12))
                    if req {
                        Image(systemName: "checkmark.circle.fill").font(.system(size: 18))
                            .foregroundStyle(cGood).padding(6).shadow(radius: 3)
                    }
                }
                Text(s.title).font(.system(size: 12)).foregroundStyle(.white.opacity(0.9)).lineLimit(1)
                if let y = s.year { Text(String(y)).font(.system(size: 10, weight: .light)).foregroundStyle(.white.opacity(0.45)) }
            }
        }.buttonStyle(.plain)
    }

    private func suggestionSheet(_ s: Suggestion) -> some View {
        let req = c.requested.contains(s.id)
        return ZStack {
            KinoBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    AsyncImage(url: URL(string: s.poster ?? "")) { img in
                        img.resizable().aspectRatio(contentMode: .fit)
                    } placeholder: { Rectangle().fill(.white.opacity(0.08)).frame(height: 240) }
                    .frame(maxWidth: .infinity).clipShape(RoundedRectangle(cornerRadius: 16))
                    Text(s.title).font(.system(size: 24, weight: .semibold)).foregroundStyle(.white)
                    HStack(spacing: 10) {
                        if let y = s.year { pill(String(y)) }
                        pill(s.kind == "series" ? "Serie" : "Film")
                    }
                    if let o = s.overview, !o.isEmpty {
                        Text(o).font(.system(size: 14)).foregroundStyle(.white.opacity(0.75))
                    }
                    Button { c.requestSuggestion(s) } label: {
                        Label(req ? "Angefragt" : "Anfragen", systemImage: req ? "checkmark" : "plus")
                            .font(.system(size: 16, weight: .semibold)).foregroundStyle(.black)
                            .frame(maxWidth: .infinity).padding(.vertical, 13)
                            .background(RoundedRectangle(cornerRadius: 12).fill(req ? cGood : Color.white))
                    }.buttonStyle(.plain).disabled(req)
                    Text("Angefragte Titel werden automatisch geladen und erscheinen dann in der Bibliothek.")
                        .font(.system(size: 12)).foregroundStyle(.white.opacity(0.5))
                }.padding(20)
            }
        }
    }

    private func pill(_ t: String) -> some View {
        Text(t).font(.system(size: 12, weight: .light)).foregroundStyle(.white.opacity(0.8))
            .padding(.horizontal, 12).padding(.vertical, 6).background(Capsule().fill(.white.opacity(0.1)))
    }
}
