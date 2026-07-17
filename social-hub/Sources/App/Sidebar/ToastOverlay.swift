import SwiftUI

struct ToastOverlay: View {
    @EnvironmentObject private var feed: NotificationFeed
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            ForEach(feed.toasts) { n in
                ToastCard(
                    notification: n,
                    onTap: {
                        appState.selectService(n.serviceID)
                        feed.dismissToast(n.id)
                    },
                    onDismiss: { feed.dismissToast(n.id) }
                )
                .transition(.opacity)
            }
        }
        .padding(.top, 20)
        .padding(.trailing, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .allowsHitTesting(!feed.toasts.isEmpty)
    }
}

private struct ToastCard: View {
    let notification: InAppNotification
    let onTap: () -> Void
    let onDismiss: () -> Void

    @State private var hovering = false

    private var service: Service? { ServiceCatalog.service(id: notification.serviceID) }
    private var accent: Color { service?.accent ?? .blue }

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 11) {
                NotificationAvatar(avatarURL: notification.avatarURL, service: service, size: 34)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(notification.title)
                            .font(Theme.headline(13))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                        if let s = service {
                            Text(s.name)
                                .font(Theme.caption(10))
                                .foregroundStyle(accent)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(accent.opacity(0.18)))
                        }
                    }
                    if !notification.body.isEmpty {
                        Text(notification.body)
                            .font(Theme.body(12))
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: 260, alignment: .leading)
                    }
                }
                Spacer(minLength: 0)
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 18, height: 18)
                        .background(Circle().fill(.thinMaterial))
                }
                .buttonStyle(.plain)
                .opacity(hovering ? 1 : 0)
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 10)
            .frame(width: 340, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(accent.opacity(hovering ? 0.45 : 0.22), lineWidth: 0.8)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
