import SwiftUI

struct InAppNotification: Identifiable, Equatable {
    let id: UUID = UUID()
    let serviceID: String
    let title: String
    let body: String
    let avatarURL: String?
    let receivedAt: Date
}

@MainActor
final class NotificationFeed: ObservableObject {
    @Published private(set) var all: [InAppNotification] = []
    /// Notifications currently showing as toast.
    @Published private(set) var toasts: [InAppNotification] = []
    /// Per-service IDs of notifications the user hasn't seen in the Inbox.
    @Published private(set) var unseenInInbox: Set<UUID> = []

    private let maxStored = 200
    private let maxToasts = 4
    private let toastLifetime: TimeInterval = 6
    /// Drop pushes that exactly match an existing notification within this window.
    /// Multiple capture paths (page Notification, page showNotification wrapper,
    /// DOM observer, title-change poll) often see the same event.
    private let dedupWindow: TimeInterval = 10

    func push(serviceID: String, title: String, body: String, avatarURL: String? = nil, deliverNative: Bool = true) {
        let now = Date()
        if all.contains(where: { existing in
            existing.serviceID == serviceID
                && existing.title == title
                && existing.body == body
                && now.timeIntervalSince(existing.receivedAt) < dedupWindow
        }) {
            return
        }
        let n = InAppNotification(serviceID: serviceID, title: title, body: body, avatarURL: avatarURL, receivedAt: now)
        all.insert(n, at: 0)
        if deliverNative, let service = ServiceCatalog.service(id: serviceID) {
            NotificationBridge.deliver(title: title, body: body, serviceName: service.name)
        }
        if all.count > maxStored { all.removeLast(all.count - maxStored) }
        unseenInInbox.insert(n.id)

        toasts.append(n)
        if toasts.count > maxToasts { toasts.removeFirst(toasts.count - maxToasts) }

        let toastID = n.id
        let lifetime = toastLifetime
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(lifetime * 1_000_000_000))
            self?.dismissToast(toastID)
        }
    }

    func dismissToast(_ id: UUID) {
        toasts.removeAll { $0.id == id }
    }

    func markInboxSeen() {
        unseenInInbox.removeAll()
    }

    func remove(_ id: UUID) {
        all.removeAll { $0.id == id }
        toasts.removeAll { $0.id == id }
        unseenInInbox.remove(id)
    }

    func clearAll() {
        all.removeAll()
        toasts.removeAll()
        unseenInInbox.removeAll()
    }
}
