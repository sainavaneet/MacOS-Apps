import SwiftUI

/// Compact zoom controls for the main window toolbar (next to RAM and Inbox).
/// Single pair of −/+ buttons that scales both the app chrome (`appState.uiScale`
/// driving a `scaleEffect`) and the active webpage (CSS `document.body.zoom`).
struct ZoomControlsToolbarView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var store: WebControllerStore

    var body: some View {
        HStack(spacing: 4) {
            zoomButton(systemName: "minus", disabled: !appState.canZoomOut) {
                appState.zoomOut()
                appState.broadcastPageZoom(via: store)
            }
            .help("Zoom Out")

            Text("\(Int((appState.uiScale * 100).rounded()))%")
                .font(Theme.body(11))
                .foregroundStyle(Theme.textSecondary)
                .monospacedDigit()
                .frame(minWidth: 32)

            zoomButton(systemName: "plus", disabled: !appState.canZoomIn) {
                appState.zoomIn()
                appState.broadcastPageZoom(via: store)
            }
            .help("Zoom In")
        }
    }

    @ViewBuilder
    private func zoomButton(systemName: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(disabled ? Theme.textTertiary : Theme.textSecondary)
                .frame(width: 22, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Color.white.opacity(disabled ? 0 : 0.06))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }
}
