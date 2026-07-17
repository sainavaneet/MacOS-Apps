import SwiftUI

@MainActor
final class WebControllerStore: ObservableObject {
    /// Static handle so AppDelegate (Cocoa-land) can reach the store without
    /// going through @EnvironmentObject plumbing.
    nonisolated(unsafe) static weak var shared: WebControllerStore?

    private var controllers: [String: WebController] = [:]
    /// Last time each controller was the foreground service. Used by the idle
    /// sweep to decide who to put to sleep.
    private var lastActive: [String: Date] = [:]
    /// Optional launch loader — when set, each created controller reports
    /// progress so the launch overlay can show per-service bars.
    var launchLoader: LaunchLoader?
    /// Tools state — wired in once at app start, propagated to every controller.
    weak var toolState: ToolState?
    @Published private(set) var isSleeping: Bool = false
    /// True while the main window is hidden. Idle sweep is disabled in this
    /// state (everything is asleep anyway).
    @Published private(set) var isIdle: Bool = false
    /// Service ID that was active just before entering idle, so we wake only
    /// that one when the window returns.
    private var idleResumeServiceID: String?
    /// Most-recently-foreground service. Used by `enterIdle()` to decide
    /// which controller to wake on window return.
    private var currentForeground: String?

    /// How long a service can sit unselected before its webview is unloaded
    /// to about:blank. 5 minutes feels long enough that quick app-hopping
    /// stays fast but a real "I'm done with this" idle gets reclaimed.
    private let idleUnloadInterval: TimeInterval = 5 * 60
    private var sweepTask: Task<Void, Never>?

    init() {
        Self.shared = self
        startSweep()
    }

    /// Lazy create: only invoked when a service is actually selected, or by
    /// `controller(for:)` on first paint. We no longer eagerly preload all
    /// services at launch.
    func controller(for service: Service, appState: AppState, feed: NotificationFeed) -> WebController {
        if let existing = controllers[service.id] { return existing }
        let controller = WebController(service: service, appState: appState, feed: feed, launchLoader: launchLoader)
        controller.toolState = toolState
        controllers[service.id] = controller
        return controller
    }

    func existingController(for serviceID: String) -> WebController? {
        controllers[serviceID]
    }

    func has(_ serviceID: String) -> Bool {
        controllers[serviceID] != nil
    }

    /// Full restart: disposes the existing WKWebView for the service and
    /// creates a brand-new controller, freshly loading the service URL.
    /// Cookies / logins survive because they live in the per-service
    /// `WKWebsiteDataStore(forIdentifier:)`, keyed by the stable UUID in
    /// `ServiceCatalog`. Use this when `reload()` isn't enough — a stuck
    /// page, a broken JS state, the site visualization wedged.
    func restart(serviceID: String, appState: AppState, feed: NotificationFeed) {
        if let old = controllers.removeValue(forKey: serviceID) {
            old.webView.stopLoading()
            old.webView.loadHTMLString("", baseURL: nil)
        }
        guard let svc = ServiceCatalog.service(id: serviceID) else { return }
        let fresh = WebController(service: svc, appState: appState, feed: feed, launchLoader: launchLoader)
        fresh.toolState = toolState
        controllers[serviceID] = fresh
        lastActive[serviceID] = Date()
        fresh.loadIfNeeded()
        objectWillChange.send()
    }

    /// Note which service is on screen right now. Called by the host view
    /// when the user switches selection. Drives the idle-unload sweep.
    func markForeground(_ serviceID: String) {
        lastActive[serviceID] = Date()
        currentForeground = serviceID
    }

    // MARK: - Power management

    /// Cheap: pauses any playing media in every webview. Called when the
    /// window hides so background videos / voice messages don't burn battery.
    func pauseAllMedia() {
        for (_, controller) in controllers {
            controller.webView.pauseAllMediaPlayback(completionHandler: nil)
        }
    }

    /// Pause every controller's media except the one named — used to enforce
    /// the single-active-audio policy from `WebController`'s audio bridge.
    func pauseAllMediaExcept(serviceID: String) {
        for (id, controller) in controllers where id != serviceID {
            controller.webView.pauseAllMediaPlayback(completionHandler: nil)
        }
    }

    /// Hard-unload every webview to about:blank. Frees most of the in-memory
    /// page state. While sleeping, **no notifications arrive** for any service.
    /// Logins persist (cookies live in `WKWebsiteDataStore`).
    func sleepAll() {
        guard !isSleeping else { return }
        isSleeping = true
        for (_, controller) in controllers {
            controller.sleep()
        }
    }

    /// Reload every previously-sleeping webview from its saved URL.
    func wakeAll() {
        guard isSleeping else { return }
        isSleeping = false
        for (_, controller) in controllers {
            controller.wake()
        }
    }

    // MARK: - Idle (window hidden) lifecycle

    /// Called from AppDelegate when the main window closes / hides. Sleeps
    /// every loaded controller, stops the idle sweep. Native notifications
    /// continue working only for service workers that the OS still has
    /// registered — pages themselves are at about:blank.
    func enterIdle() {
        guard !isIdle else { return }
        isIdle = true
        idleResumeServiceID = currentForeground
        sweepTask?.cancel()
        sweepTask = nil
        for (_, controller) in controllers {
            controller.sleep()
        }
    }

    /// Called from AppDelegate when the window becomes key again. Wakes only
    /// the service that was foregrounded before idle, so we don't pay to
    /// reload 7 sites just because the user came back.
    func exitIdle() {
        guard isIdle else { return }
        isIdle = false
        if let id = idleResumeServiceID, let c = controllers[id] {
            c.wake()
            lastActive[id] = Date()
        }
        idleResumeServiceID = nil
        startSweep()
    }

    // MARK: - Idle sweep

    private func startSweep() {
        sweepTask?.cancel()
        sweepTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 60 * 1_000_000_000)
                guard !Task.isCancelled else { return }
                self?.sweepIdle()
            }
        }
    }

    private func sweepIdle() {
        guard !isIdle, !isSleeping else { return }
        let now = Date()
        let cutoff = now.addingTimeInterval(-idleUnloadInterval)
        for (id, controller) in controllers {
            let last = lastActive[id] ?? .distantPast
            if last < cutoff {
                controller.sleep()
            }
        }
    }
}
