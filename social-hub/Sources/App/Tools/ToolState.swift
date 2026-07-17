import SwiftUI

/// Per-service tool state. Today just Tinder auto-swipe; extensible to other
/// services as new tools are added.
@MainActor
final class ToolState: ObservableObject {
    // Tinder auto-swipe
    @Published var autoSwipeRunning: Bool = false
    @Published var autoSwipeCount: Int = 0
    @Published var autoSwipeStatus: String = ""
    @Published var autoSwipeSpeed: Double = 1.0   // 1.0 / 5.0 / 10.0
    @Published var autoSwipeLog: [String] = []

    func appendLog(_ line: String) {
        autoSwipeLog.append(line)
        if autoSwipeLog.count > 30 { autoSwipeLog.removeFirst(autoSwipeLog.count - 30) }
    }
}
