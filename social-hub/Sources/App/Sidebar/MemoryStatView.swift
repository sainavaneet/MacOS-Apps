import SwiftUI

/// Tiny RAM-usage pill for the window toolbar: colored dot + monospaced
/// number. Updates every couple of seconds via `MemoryStat`.
struct MemoryStatView: View {
    @EnvironmentObject private var stat: MemoryStat

    private var tier: Color {
        let mb = stat.megabytes
        if mb < 500  { return .green }
        if mb < 1000 { return .yellow }
        return .red
    }

    private var label: String {
        let mb = stat.megabytes
        if mb >= 1024 { return String(format: "%.1f GB", mb / 1024) }
        return String(format: "%.0f MB", mb)
    }

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(tier)
                .frame(width: 6, height: 6)
                .accentGlow(tier, radius: 3, intensity: 0.55)
            Text(label)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(Theme.textSecondary)
                .frame(minWidth: 46, alignment: .leading)
                .contentTransition(.numericText())
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Capsule().fill(.ultraThinMaterial))
        .overlay(Capsule().strokeBorder(Theme.strokeSubtle, lineWidth: 0.5))
        .help("App memory usage — \(label)")
    }
}
