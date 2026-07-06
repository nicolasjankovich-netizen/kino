import SwiftUI

/// Bibliothek: Poster-Grid im Apple-TV-Stil — antippen öffnet die Detail-Ansicht (Abspielen/Download).
struct DiscoverView: View {
    @EnvironmentObject var c: Cinema
    @State private var selected: KItem?
    private let cols = [GridItem(.adaptive(minimum: 108), spacing: 14)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Bibliothek").font(.system(size: 30, weight: .bold)).foregroundStyle(.white)
                    Spacer()
                    if c.busy { ProgressView().tint(.white) }
                }
                Picker("", selection: $c.kind) {
                    ForEach(Cinema.Kind.allCases, id: \.self) { Text($0.label).tag($0) }
                }.pickerStyle(.segmented)
                .onChange(of: c.kind) { _, _ in Task { await c.loadLibrary() } }

                if c.library.isEmpty && !c.busy {
                    Text("Bibliothek lädt …").label2().frame(maxWidth: .infinity).padding(.top, 40)
                } else {
                    LazyVGrid(columns: cols, spacing: 18) {
                        ForEach(c.library) { it in poster(it) }
                    }
                }
            }
            .padding(20)
        }
        .background(KinoBackground())
        .refreshable { await c.loadLibrary() }
        .task { if c.library.isEmpty { await c.loadLibrary() } }
        .sheet(item: $selected) { DetailView(item: $0) }
    }

    private func poster(_ it: KItem) -> some View {
        Button {
            var item = it; item.kind = c.kind.rawValue
            selected = item
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                ZStack(alignment: .topTrailing) {
                    AsyncImage(url: URL(string: it.poster ?? "")) { img in
                        img.resizable().aspectRatio(2/3, contentMode: .fill)
                    } placeholder: {
                        RoundedRectangle(cornerRadius: 10).fill(.white.opacity(0.08))
                            .aspectRatio(2/3, contentMode: .fit)
                            .overlay(Image(systemName: "film").foregroundStyle(.white.opacity(0.25)))
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    if it.hasFile == true {
                        Image(systemName: "checkmark.circle.fill").font(.system(size: 15))
                            .foregroundStyle(cGood).padding(6).shadow(radius: 3)
                    }
                }
                Text(it.title).font(.system(size: 13, weight: .medium)).foregroundStyle(.white).lineLimit(1)
                if let y = it.year { Text(String(y)).font(.system(size: 11)).foregroundStyle(.white.opacity(0.5)) }
            }
        }.buttonStyle(.plain)
    }
}
