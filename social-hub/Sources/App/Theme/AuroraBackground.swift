import SwiftUI

/// Static background. The previous TimelineView-driven aurora cost ~30 fps
/// of GPU work for a decorative effect the user explicitly said they don't
/// want. Now a single radial+linear composite, computed once.
struct AuroraBackground: View {
    let accent: Color
    var reduceMotion: Bool = false

    var body: some View {
        ZStack {
            Theme.canvas
            LinearGradient(
                colors: [
                    Theme.auroraA.opacity(0.18),
                    Theme.auroraB.opacity(0.12),
                    accent.opacity(0.10)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .ignoresSafeArea()
    }
}
