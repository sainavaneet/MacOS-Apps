import SwiftUI

/// Round avatar with a small service-logo badge in the corner — mirrors how
/// Chrome shows web push notifications (sender avatar + browser icon).
/// Falls back to a full-size `ServiceIcon` when no avatar URL is available.
struct NotificationAvatar: View {
    let avatarURL: String?
    let service: Service?
    var size: CGFloat = 36

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if let urlString = avatarURL,
               !urlString.isEmpty,
               let url = URL(string: urlString) {
                roundAvatar(url: url)
                if let s = service {
                    ServiceIcon(service: s, size: max(14, size * 0.42))
                        .offset(x: 3, y: 3)
                }
            } else if let s = service {
                ServiceIcon(service: s, size: size)
            } else {
                Circle()
                    .fill(Color.gray.opacity(0.4))
                    .frame(width: size, height: size)
            }
        }
        .frame(width: size + 4, height: size + 4)
    }

    @ViewBuilder
    private func roundAvatar(url: URL) -> some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let img):
                img.resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            case .failure:
                if let s = service {
                    ServiceIcon(service: s, size: size)
                } else {
                    Circle().fill(Color.gray.opacity(0.4)).frame(width: size, height: size)
                }
            case .empty:
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.08))
                        .frame(width: size, height: size)
                    ProgressView()
                        .controlSize(.small)
                }
            @unknown default:
                Color.clear.frame(width: size, height: size)
            }
        }
        .overlay(
            Circle().strokeBorder(Color.white.opacity(0.2), lineWidth: 0.5)
        )
        .frame(width: size, height: size)
    }
}
