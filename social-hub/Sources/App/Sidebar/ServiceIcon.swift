import SwiftUI
import AppKit

/// Two-tier (memory + disk) cache for brand logos. Disk path lives in
/// Application Support so logos persist across launches.
@MainActor
final class IconCache {
    static let shared = IconCache()
    private let memory = NSCache<NSString, NSImage>()
    private let dir: URL

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory,
                                                   in: .userDomainMask).first!
        // Bump the version segment ("v2") to invalidate stale caches after
        // changing icon source providers.
        dir = appSupport.appendingPathComponent("SocialHub/icons/v2", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    private func diskURL(for url: URL) -> URL {
        let hash = url.absoluteString
            .data(using: .utf8)?
            .base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "=", with: "")
            ?? UUID().uuidString
        return dir.appendingPathComponent(hash + ".png")
    }

    func image(for url: URL) -> NSImage? {
        let key = url.absoluteString as NSString
        if let cached = memory.object(forKey: key) { return cached }
        let path = diskURL(for: url)
        if let data = try? Data(contentsOf: path), let img = NSImage(data: data) {
            memory.setObject(img, forKey: key)
            return img
        }
        return nil
    }

    func store(_ img: NSImage, for url: URL) {
        memory.setObject(img, forKey: url.absoluteString as NSString)
        if let tiff = img.tiffRepresentation,
           let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: diskURL(for: url), options: .atomic)
        }
    }
}

/// Displays a service's real brand logo. Falls back to the SF Symbol on a
/// colored gradient if every URL in the fallback chain fails.
struct ServiceIcon: View {
    let service: Service
    var size: CGFloat = 28

    @State private var image: NSImage?

    var body: some View {
        ZStack {
            if let img = image {
                RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                    .fill(Color.white)
                Image(nsImage: img)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .padding(size * 0.12)
            } else {
                RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                    .fill(service.accent.gradient)
                Image(systemName: service.sfSymbol)
                    .font(.system(size: size * 0.48, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
        .shadow(color: service.accent.opacity(0.28), radius: size * 0.12, y: 1)
        .task(id: service.id) { await load() }
    }

    private func load() async {
        // Memory/disk-cache hit on any URL in the chain wins immediately.
        for url in service.logoURLs {
            if let cached = IconCache.shared.image(for: url) {
                image = cached
                return
            }
        }
        // Otherwise walk the chain until one succeeds.
        for url in service.logoURLs {
            var req = URLRequest(url: url)
            req.timeoutInterval = 8
            req.setValue(ServiceCatalog.desktopUserAgent, forHTTPHeaderField: "User-Agent")
            do {
                let (data, response) = try await URLSession.shared.data(for: req)
                if let http = response as? HTTPURLResponse, http.statusCode != 200 { continue }
                guard let img = NSImage(data: data) else { continue }
                // Skip degenerate placeholder images (e.g. 1x1 trackers).
                let rep = NSBitmapImageRep(data: data)
                let w = rep?.pixelsWide ?? Int(img.size.width)
                let h = rep?.pixelsHigh ?? Int(img.size.height)
                if w < 8 || h < 8 { continue }
                IconCache.shared.store(img, for: url)
                image = img
                return
            } catch {
                continue
            }
        }
    }
}
