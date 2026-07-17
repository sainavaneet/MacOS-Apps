import SwiftUI

/// Static playing indicator. Replaces the four animated bars; a small filled
/// circle is enough to communicate "audio is playing here" without spending
/// frames on it.
struct EqualizerBars: View {
    var color: Color
    var barCount: Int = 4
    var width: CGFloat = 3
    var maxHeight: CGFloat = 13
    var playing: Bool = true

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 6, height: 6)
            .opacity(playing ? 1 : 0)
    }
}
