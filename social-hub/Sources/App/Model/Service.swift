import SwiftUI

struct Service: Identifiable, Hashable {
    let id: String
    let name: String
    let url: URL
    let sfSymbol: String
    let accent: Color
    /// Ordered list of brand-logo URLs to try. First one that returns a valid
    /// image wins and is cached on disk. Subsequent launches use the cached
    /// copy and never re-fetch.
    let logoURLs: [URL]
    /// Stable UUID used for `WKWebsiteDataStore(forIdentifier:)` — must never change
    /// across releases or users will lose their logins.
    let dataStoreID: UUID
}
