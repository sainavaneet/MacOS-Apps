import SwiftUI

/// Inline auto-swipe controls in the WebToolbar when on Tinder.
/// Layout is fixed: [speed picker] [count (when running)] [action button].
/// The action button stays in the same spot whether running or idle so the
/// user never loses track of where Stop is.
struct TinderInlineControls: View {
    @EnvironmentObject private var tools: ToolState
    @EnvironmentObject private var store: WebControllerStore

    private let speedOptions: [Double] = [1.0, 5.0, 10.0]

    var body: some View {
        HStack(spacing: 10) {
            speedPicker

            if tools.autoSwipeRunning {
                HStack(spacing: 5) {
                    EqualizerBars(color: .red, barCount: 3, maxHeight: 11, playing: true)
                    Text("\(tools.autoSwipeCount)")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.red)
                        .contentTransition(.numericText())
                }
            }

            actionButton
        }
        .animation(Theme.springQuick, value: tools.autoSwipeRunning)
    }

    private var speedPicker: some View {
        HStack(spacing: 1) {
            ForEach(speedOptions, id: \.self) { speed in
                let label = speed == 1.0 ? "1x" : "\(Int(speed))x"
                let active = tools.autoSwipeSpeed == speed
                Button {
                    tools.autoSwipeSpeed = speed
                    store.existingController(for: "tinder")?.setAutoSwipeSpeed(speed)
                } label: {
                    Text(label)
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(active ? .white : Theme.textSecondary)
                        .frame(width: 26, height: 20)
                        .background(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(active ? Color.red.opacity(0.9) : Color.clear)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(Theme.strokeSubtle, lineWidth: 0.5)
        )
    }

    private var actionButton: some View {
        Button(action: toggle) {
            HStack(spacing: 4) {
                Image(systemName: tools.autoSwipeRunning ? "stop.fill" : "flame.fill")
                    .font(.system(size: 9, weight: .bold))
                Text(tools.autoSwipeRunning ? "Stop" : "Swipe")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .frame(minWidth: 60)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.red.gradient)
            )
            .accentGlow(.red,
                        radius: tools.autoSwipeRunning ? 8 : 3,
                        intensity: tools.autoSwipeRunning ? 0.6 : 0.3)
        }
        .buttonStyle(.plain)
        .help(tools.autoSwipeRunning ? "Stop auto-swiping" : "Auto-swipe right on every profile")
    }

    private func toggle() {
        guard let controller = store.existingController(for: "tinder") else { return }
        if tools.autoSwipeRunning {
            // Optimistic update so UI reacts even before the JS roundtrip.
            tools.autoSwipeRunning = false
            controller.stopAutoSwipe()
        } else {
            tools.autoSwipeRunning = true
            tools.autoSwipeCount = 0
            tools.autoSwipeStatus = "Starting…"
            controller.setAutoSwipeSpeed(tools.autoSwipeSpeed)
            controller.startAutoSwipe()
        }
    }
}
