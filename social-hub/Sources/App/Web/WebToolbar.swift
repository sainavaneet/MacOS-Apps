import SwiftUI

struct WebToolbar: View {
    let service: Service
    let controller: WebController?

    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var store: WebControllerStore
    @EnvironmentObject private var feed: NotificationFeed

    @State private var canGoBack = false
    @State private var canGoForward = false
    @State private var pageTitle: String = ""
    @State private var reloadTick = 0
    @State private var backTick = 0
    @State private var forwardTick = 0

    var body: some View {
        mainRow
        .background(
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                Rectangle().fill(Color.black.opacity(0.10))
            }
            .ignoresSafeArea(edges: .top)
        )
        .overlay(alignment: .bottom) {
            LinearGradient(
                colors: [Theme.strokeSubtle.opacity(0), Theme.strokeBright, Theme.strokeSubtle.opacity(0)],
                startPoint: .leading, endPoint: .trailing
            )
            .frame(height: 1)
        }
        .task(id: controller?.webView) {
            guard let webView = controller?.webView else { return }
            while !Task.isCancelled {
                canGoBack = webView.canGoBack
                canGoForward = webView.canGoForward
                pageTitle = webView.title ?? ""
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    private var mainRow: some View {
        HStack(spacing: 8) {
            navButton(systemName: "chevron.left", disabled: !canGoBack, tick: backTick) {
                controller?.webView.goBack()
                backTick &+= 1
            }
            navButton(systemName: "chevron.right", disabled: !canGoForward, tick: forwardTick) {
                controller?.webView.goForward()
                forwardTick &+= 1
            }
            navButton(systemName: "arrow.triangle.2.circlepath", disabled: false, tick: reloadTick) {
                store.restart(serviceID: service.id, appState: appState, feed: feed)
                reloadTick &+= 1
            }

            Divider().frame(height: 14).padding(.horizontal, 4).opacity(0.4)

            ServiceIcon(service: service, size: 18)
            Text(pageTitle.isEmpty ? service.name : pageTitle)
                .font(Theme.body(12))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)

            Spacer()

            // Single dropdown button — opens a centered popover with the
            // vertical reply suggestions menu.
            ReplyMenuButton(serviceID: service.id)

            AIComposerButton(service: service)

            if service.id == "tinder" {
                TinderInlineControls()
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    @ViewBuilder
    private func navButton(systemName: String, disabled: Bool, tick: Int, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(disabled ? Theme.textTertiary : Theme.textPrimary)
                .frame(width: 26, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.white.opacity(disabled ? 0 : 0.06))
                )
                .symbolEffect(.bounce, value: tick)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }
}
