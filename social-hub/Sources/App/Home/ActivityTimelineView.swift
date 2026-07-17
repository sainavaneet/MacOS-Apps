import SwiftUI

struct ActivityTimelineView: View {
    let notifications: [InAppNotification]
    let onSelect: (InAppNotification) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.s8) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                Text("Recent activity")
                    .font(Theme.headline(13))
                    .foregroundStyle(Theme.textSecondary)
            }
            if notifications.isEmpty {
                HStack {
                    Image(systemName: "moon.zzz")
                        .foregroundStyle(Theme.textTertiary)
                    Text("Nothing yet today")
                        .font(Theme.caption(12))
                        .foregroundStyle(Theme.textTertiary)
                }
                .padding(.vertical, Theme.s8)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Theme.s8) {
                        ForEach(notifications.prefix(12)) { n in
                            ActivityPill(notification: n, onTap: { onSelect(n) })
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }
}

private struct ActivityPill: View {
    let notification: InAppNotification
    let onTap: () -> Void

    @State private var hovering = false
    private var service: Service? { ServiceCatalog.service(id: notification.serviceID) }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                NotificationAvatar(avatarURL: notification.avatarURL, service: service, size: 22)
                VStack(alignment: .leading, spacing: 1) {
                    Text(notification.title)
                        .font(Theme.body(12))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    Text(relative(notification.receivedAt))
                        .font(Theme.caption(10))
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: 190, alignment: .leading)
            .glassCard(accent: service?.accent ?? .white,
                       cornerRadius: 999,
                       accentOpacity: hovering ? 0.18 : 0.08)
            .scaleEffect(hovering ? 1.04 : 1.0)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Theme.springQuick, value: hovering)
    }

    private func relative(_ date: Date) -> String {
        let d = Date().timeIntervalSince(date)
        if d < 60 { return "now" }
        if d < 3600 { return "\(Int(d / 60))m ago" }
        if d < 86400 { return "\(Int(d / 3600))h ago" }
        return "\(Int(d / 86400))d ago"
    }
}
