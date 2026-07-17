import SwiftUI

/// Tracks the initial app warmup — per-service web load progress, overall
/// readiness, and a hard timeout so we never block the UI longer than
/// `timeout` seconds even if a single site is slow.
@MainActor
final class LaunchLoader: ObservableObject {
    @Published var progress: [String: Double] = [:]
    @Published var ready: Set<String> = []
    @Published var started: Set<String> = []
    @Published var dismissed = false

    /// Services now load lazily on first selection, so the launch overlay
    /// has nothing to wait on — dismiss it almost immediately.
    let timeout: TimeInterval = 0.6
    private let lingerOnComplete: TimeInterval = 0.0

    private var timeoutTask: Task<Void, Never>?

    var totalCount: Int { ServiceCatalog.all.count }
    var readyCount: Int { ready.count }

    var overallProgress: Double {
        guard totalCount > 0 else { return 1 }
        let sum = ServiceCatalog.all.reduce(0.0) { $0 + (progress[$1.id] ?? 0) }
        return sum / Double(totalCount)
    }

    func begin() {
        guard timeoutTask == nil else { return }
        timeoutTask = Task { [weak self] in
            let seconds = self?.timeout ?? 14
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            await MainActor.run { self?.dismiss(animated: true) }
        }
    }

    func markStarted(_ serviceID: String) {
        started.insert(serviceID)
        if progress[serviceID] == nil { progress[serviceID] = 0.02 }
    }

    func update(_ serviceID: String, progress: Double) {
        let clamped = max(0, min(1, progress))
        // Don't let progress go backwards (some sites restart estimatedProgress
        // mid-load).
        if (self.progress[serviceID] ?? 0) > clamped { return }
        self.progress[serviceID] = clamped
        if clamped >= 0.99 {
            markReady(serviceID)
        }
    }

    func markReady(_ serviceID: String) {
        ready.insert(serviceID)
        progress[serviceID] = 1.0
        if ready.count >= totalCount {
            Task { [weak self] in
                let linger = self?.lingerOnComplete ?? 0.6
                try? await Task.sleep(nanoseconds: UInt64(linger * 1_000_000_000))
                await MainActor.run { self?.dismiss(animated: true) }
            }
        }
    }

    func dismiss(animated: Bool) {
        guard !dismissed else { return }
        dismissed = true
        timeoutTask?.cancel()
    }
}
