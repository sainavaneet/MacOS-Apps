import SwiftUI

enum SidebarSelection: Hashable {
    case home
    case inbox
    case service(String)
}

@MainActor
final class AppState: ObservableObject {
    static let minUIScale: CGFloat = 0.6
    static let maxUIScale: CGFloat = 1.4
    static let uiScaleStep: CGFloat = 0.1

    @Published var selection: SidebarSelection = .home
    @Published var unread: [String: Int] = [:]
    @Published var visited: Set<String> = []
    @Published var uiScale: CGFloat = CGFloat(UserDefaults.standard.double(forKey: "uiScale").nonZeroOrDefault(1.0)) {
        didSet { UserDefaults.standard.set(Double(uiScale), forKey: "uiScale") }
    }

    private weak var audioState: AudioState?

    func zoomIn() {
        uiScale = min(Self.maxUIScale, (uiScale + Self.uiScaleStep).rounded(toPlaces: 2))
    }

    func zoomOut() {
        uiScale = max(Self.minUIScale, (uiScale - Self.uiScaleStep).rounded(toPlaces: 2))
    }

    func resetZoom() {
        uiScale = 1.0
    }

    var canZoomIn: Bool { uiScale < Self.maxUIScale - 0.001 }
    var canZoomOut: Bool { uiScale > Self.minUIScale + 0.001 }

    /// Snapshot of `uiScale` as a Double, for non-SwiftUI callers (WebController init).
    func uiScaleValueForController() -> Double? { Double(uiScale) }

    /// Push the current uiScale onto every loaded controller's page (called
    /// after the user clicks a zoom button so all background services match).
    func broadcastPageZoom(via store: WebControllerStore) {
        let z = Double(uiScale)
        for svc in ServiceCatalog.all {
            store.existingController(for: svc.id)?.setPageZoom(z)
        }
    }

    func attachAudioState(_ audioState: AudioState) {
        self.audioState = audioState
    }

    func setPlayingAudio(_ playing: Bool, for serviceID: String) {
        audioState?.setPlayingAudio(playing, for: serviceID)
    }

    var selectedServiceID: String? {
        if case .service(let id) = selection { return id }
        return nil
    }

    func selectService(_ id: String) {
        selection = .service(id)
        visited.insert(id)
    }

    func setUnread(_ count: Int, for serviceID: String) {
        if (unread[serviceID] ?? 0) != count { unread[serviceID] = count }
    }

    func markVisited(_ serviceID: String) {
        visited.insert(serviceID)
    }

    /// Accent color of the currently-selected service (or violet for non-service screens).
    func currentAccent() -> Color {
        if case .service(let id) = selection, let s = ServiceCatalog.service(id: id) {
            return s.accent
        }
        return Theme.auroraA
    }
}

private extension Double {
    func nonZeroOrDefault(_ fallback: Double) -> Double {
        self == 0 ? fallback : self
    }
}

private extension CGFloat {
    func rounded(toPlaces places: Int) -> CGFloat {
        let m = pow(10.0, Double(places))
        return CGFloat((Double(self) * m).rounded() / m)
    }
}
