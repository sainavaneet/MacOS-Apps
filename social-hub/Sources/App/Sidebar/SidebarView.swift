import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var audioState: AudioState
    @EnvironmentObject private var store: WebControllerStore
    @EnvironmentObject private var feed: NotificationFeed
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var selectionNS

    var body: some View {
        ZStack {
            VibrancyBackground(material: .sidebar).ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    sectionHeader("Overview")
                    SidebarRow(
                        kind: .system(icon: "house.fill", color: Color.purple),
                        title: "Home",
                        badge: 0,
                        selected: appState.selection == .home,
                        namespace: selectionNS,
                        accent: .purple,
                        action: { withSelectionAnim { appState.selection = .home } }
                    )
                    SidebarRow(
                        kind: .system(icon: "tray.full.fill", color: Color.gray),
                        title: "Inbox",
                        badge: feed.unseenInInbox.count,
                        selected: appState.selection == .inbox,
                        namespace: selectionNS,
                        accent: .gray,
                        action: { withSelectionAnim { appState.selection = .inbox } }
                    )

                    sectionHeader("Apps").padding(.top, Theme.s12)

                    ForEach(ServiceCatalog.all) { service in
                        SidebarRow(
                            kind: .service(service),
                            title: service.name,
                            badge: appState.unread[service.id] ?? 0,
                            selected: appState.selection == .service(service.id),
                            namespace: selectionNS,
                            accent: service.accent,
                            playingAudio: audioState.playingAudio.contains(service.id),
                            action: { withSelectionAnim { appState.selectService(service.id) } }
                        )
                        .contextMenu {
                            Button("Reload") {
                                store.existingController(for: service.id)?.reload()
                            }
                        }
                    }
                    Spacer(minLength: Theme.s12)
                }
                .padding(.horizontal, 10)
                .padding(.top, 10)
            }
            .scrollContentBackground(.hidden)
        }
        .frame(minWidth: 218, idealWidth: 240)
    }

    private func withSelectionAnim(_ action: @escaping () -> Void) {
        action()
    }

    @ViewBuilder
    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .foregroundStyle(Theme.textTertiary)
            .tracking(0.8)
            .padding(.horizontal, 12)
            .padding(.top, 4)
            .padding(.bottom, 6)
    }
}

// MARK: - Row

private struct SidebarRow: View {
    enum Kind {
        case system(icon: String, color: Color)
        case service(Service)
    }

    let kind: Kind
    let title: String
    let badge: Int
    let selected: Bool
    let namespace: Namespace.ID
    let accent: Color
    var playingAudio: Bool = false
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                iconView
                Text(title)
                    .font(Theme.body(13))
                    .foregroundStyle(selected ? Theme.textPrimary : Theme.textSecondary)
                if playingAudio {
                    EqualizerBars(color: accent, playing: true)
                }
                Spacer()
                if badge > 0 {
                    UnreadBadgeView(count: badge, accent: accent)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                ZStack {
                    if selected {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(accent.opacity(0.16))
                            .overlay(
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .strokeBorder(accent.opacity(0.35), lineWidth: 0.8)
                            )
                            .matchedGeometryEffect(id: "sidebar-pill", in: namespace)
                    } else if hovering {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(Color.white.opacity(0.05))
                    }
                }
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }

    @ViewBuilder
    private var iconView: some View {
        switch kind {
        case .system(let icon, let color):
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(color.gradient)
                )
                .accentGlow(color, radius: 4, intensity: 0.35)
        case .service(let s):
            ServiceIcon(service: s, size: 24)
        }
    }
}
