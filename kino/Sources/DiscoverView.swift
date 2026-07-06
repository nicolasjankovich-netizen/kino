import SwiftUI

/// Poster-Grid der vorhandenen Bibliothek (nur ansehen).
struct DiscoverView: View {
    @EnvironmentObject var c: Cinema
    private let cols = [GridItem(.adaptive(minimum: 104), spacing: 12)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("kino").font(.system(size: 26, weight: .thin)).tracking(4).foregroundStyle(.white)
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
                    LazyVGrid(columns: cols, spacing: 14) {
                        ForEach(c.library) { it in poster(it) }
                    }
                }
            }
            .padding(18)
        }
        .background(KinoBackground())
        .refreshable { await c.loadLibrary() }
        .task { if c.library.isEmpty { await c.loadLibrary() } }
    }

    private func poster(_ it: KItem) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            ZStack(alignment: .topTrailing) {
                AsyncImage(url: URL(string: it.poster ?? "")) { img in
                    img.resizable().aspectRatio(2/3, contentMode: .fill)
                } placeholder: {
                    RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.08))
                        .aspectRatio(2/3, contentMode: .fit)
                        .overlay(Image(systemName: "film").foregroundStyle(.white.opacity(0.25)))
                }
                .clipShape(RoundedRectangle(cornerRadius: 12))
                if it.hasFile == true {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 15))
                        .foregroundStyle(cGood).padding(6).shadow(radius: 3)
                }
            }
            Text(it.title).font(.system(size: 12, weight: .regular)).foregroundStyle(.white.opacity(0.9)).lineLimit(1)
            if let y = it.year { Text(String(y)).font(.system(size: 10, weight: .light)).foregroundStyle(.white.opacity(0.45)) }
        }
    }
}
