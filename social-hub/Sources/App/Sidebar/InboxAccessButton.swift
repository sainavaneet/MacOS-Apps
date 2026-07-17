import SwiftUI

/// Toolbar button that jumps to the Inbox from any view. Shows a small red
/// dot when there are unseen notifications.
struct InboxAccessButton: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var feed: NotificationFeed

    private var unseen: Int { feed.unseenInInbox.count }
    private var active: Bool { appState.selection == .inbox }

    var body: some View {
        Button {
            withAnimation(Theme.springLively) { appState.selection = .inbox }
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "envelope.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(active ? Color.purple : Theme.textSecondary)
                    .frame(width: 28, height: 22)

                if unseen > 0 {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 8, height: 8)
                        .overlay(Circle().strokeBorder(Color.white.opacity(0.4), lineWidth: 0.6))
                        .accentGlow(.red, radius: 4, intensity: 0.6)
                        .offset(x: 2, y: -1)
                }
            }
        }
        .buttonStyle(.plain)
        .help(unseen > 0 ? "Inbox (\(unseen) new)" : "Open Inbox")
    }
}
