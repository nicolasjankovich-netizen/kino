import SwiftUI
import UIKit

/// Bild-Cache: In-Memory (NSCache) + Disk (URLCache) → Poster laden schnell & flackern nicht mehr.
@MainActor
final class ImageCache {
    static let shared = ImageCache()
    private let mem = NSCache<NSURL, UIImage>()
    private let session: URLSession
    private init() {
        mem.countLimit = 400
        let cfg = URLSessionConfiguration.default
        cfg.urlCache = URLCache(memoryCapacity: 40_000_000, diskCapacity: 400_000_000)
        cfg.requestCachePolicy = .returnCacheDataElseLoad
        cfg.timeoutIntervalForRequest = 20
        session = URLSession(configuration: cfg)
    }
    func image(_ url: URL) async -> UIImage? {
        if let c = mem.object(forKey: url as NSURL) { return c }
        guard let (d, _) = try? await session.data(from: url), let img = UIImage(data: d) else { return nil }
        mem.setObject(img, forKey: url as NSURL)
        return img
    }
    /// Speicher- und Disk-Cache leeren (Einstellungen → Bild-Cache leeren).
    func clear() {
        mem.removeAllObjects()
        session.configuration.urlCache?.removeAllCachedResponses()
    }
}

/// Drop-in-Ersatz für AsyncImage(url:content:placeholder:) — nur eben gecached.
struct CachedImage<Content: View, Placeholder: View>: View {
    let url: URL?
    @ViewBuilder let content: (Image) -> Content
    @ViewBuilder let placeholder: () -> Placeholder
    @State private var img: UIImage?

    var body: some View {
        Group {
            if let img { content(Image(uiImage: img)) }
            else { placeholder() }
        }
        .task(id: url) {
            guard let url, url.absoluteString.count > 5, img == nil else { return }
            img = await ImageCache.shared.image(url)
        }
    }
}
