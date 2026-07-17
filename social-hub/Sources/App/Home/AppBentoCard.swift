import SwiftUI

struct AppBentoCard: View {
    let service: Service
    let unread: Int
    let latest: InAppNotification?
    let onOpen: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: Theme.s12) {
                HStack(alignment: .top) {
                    ServiceIcon(service: service, size: 44)
                    Spacer()
                    if unread > 0 {
                        Text(unread > 99 ? "99+" : "\(unread)")
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundStyle(service.accent)
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(service.name)
                        .font(Theme.headline(17))
                        .foregroundStyle(Theme.textPrimary)
                    if let n = latest {
                        Text(n.title)
                            .font(Theme.body(12))
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                        Text(n.body.isEmpty ? "Open to read" : n.body)
                            .font(Theme.caption(11))
                            .foregroundStyle(Theme.textTertiary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    } else {
                        Text("All caught up")
                            .font(Theme.body(12))
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
                Spacer(minLength: 0)
                HStack(spacing: 6) {
                    Circle().fill(service.accent).frame(width: 5, height: 5)
                    Text("Open \(service.name)")
                        .font(Theme.caption(10))
                        .foregroundStyle(service.accent.opacity(0.9))
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Theme.textTertiary)
                        .opacity(hovering ? 1 : 0.5)
                }
            }
            .padding(Theme.s16)
            .frame(maxWidth: .infinity, minHeight: 168, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: Theme.r14, style: .continuous)
                    .fill(Color.white.opacity(hovering ? 0.06 : 0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.r14, style: .continuous)
                    .strokeBorder(service.accent.opacity(hovering ? 0.35 : 0.12), lineWidth: 0.8)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
