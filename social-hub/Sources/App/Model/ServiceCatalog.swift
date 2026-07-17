import SwiftUI

enum ServiceCatalog {
    static let desktopUserAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_5) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Safari/605.1.15"

    /// Multi-source fallback chain. icon.horse usually wins (256-px, antialiased,
    /// transparent background); DDG and Google are fallbacks.
    private static func logos(_ domain: String) -> [URL] {
        [
            URL(string: "https://icon.horse/icon/\(domain)")!,
            URL(string: "https://icons.duckduckgo.com/ip3/\(domain).ico")!,
            URL(string: "https://www.google.com/s2/favicons?domain=\(domain)&sz=128")!,
        ]
    }

    static let all: [Service] = [
        Service(
            id: "whatsapp",
            name: "WhatsApp",
            url: URL(string: "https://web.whatsapp.com")!,
            sfSymbol: "message.fill",
            accent: .green,
            logoURLs: logos("whatsapp.com"),
            dataStoreID: UUID(uuidString: "1A1A1A1A-0001-4000-A000-000000000001")!
        ),
        Service(
            id: "messenger",
            name: "Messenger",
            url: URL(string: "https://www.messenger.com")!,
            sfSymbol: "bubble.left.fill",
            accent: .blue,
            logoURLs: logos("messenger.com"),
            dataStoreID: UUID(uuidString: "1A1A1A1A-0002-4000-A000-000000000002")!
        ),
        Service(
            id: "telegram",
            name: "Telegram",
            url: URL(string: "https://web.telegram.org/k/")!,
            sfSymbol: "paperplane.fill",
            accent: .blue,
            logoURLs: logos("telegram.org"),
            dataStoreID: UUID(uuidString: "1A1A1A1A-0007-4000-A000-000000000007")!
        ),
        Service(
            id: "instagram",
            name: "Instagram",
            // Default to the DMs page so the chat list is always loaded —
            // that's the DOM we scrape for sender + message previews.
            // User can navigate back to the home feed via the top nav.
            url: URL(string: "https://www.instagram.com/direct/inbox/")!,
            sfSymbol: "camera.fill",
            accent: .pink,
            logoURLs: logos("instagram.com"),
            dataStoreID: UUID(uuidString: "1A1A1A1A-0003-4000-A000-000000000003")!
        ),
        Service(
            id: "tiktok",
            name: "TikTok",
            url: URL(string: "https://www.tiktok.com")!,
            sfSymbol: "music.note",
            accent: .cyan,
            logoURLs: logos("tiktok.com"),
            dataStoreID: UUID(uuidString: "1A1A1A1A-0004-4000-A000-000000000004")!
        ),
        Service(
            id: "snapchat",
            name: "Snapchat",
            url: URL(string: "https://web.snapchat.com")!,
            sfSymbol: "bolt.fill",
            accent: .yellow,
            logoURLs: logos("snapchat.com"),
            dataStoreID: UUID(uuidString: "1A1A1A1A-0005-4000-A000-000000000005")!
        ),
        Service(
            id: "tinder",
            name: "Tinder",
            url: URL(string: "https://tinder.com")!,
            sfSymbol: "flame.fill",
            accent: .red,
            logoURLs: logos("tinder.com"),
            dataStoreID: UUID(uuidString: "1A1A1A1A-0006-4000-A000-000000000006")!
        ),
    ]

    static func service(id: String) -> Service? {
        all.first { $0.id == id }
    }
}
