import SwiftUI
import AppKit

/// Translucent NSVisualEffectView background for the sidebar — gives the
/// classic macOS "frosted" look that ignoresSafeArea + Material can't quite
/// match.
struct VibrancyBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .sidebar
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material
        v.blendingMode = blendingMode
        v.state = .active
        v.isEmphasized = true
        return v
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

/// Configures the host NSWindow once: transparent titlebar, no background
/// pseudo-color, unified toolbar appearance. Attaches via NSViewRepresentable
/// because SwiftUI's WindowGroup doesn't expose this.
struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async {
            guard let window = v.window else { return }
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.styleMask.insert(.fullSizeContentView)
            window.isMovableByWindowBackground = true
            // Keep the toolbar slot itself visible so SwiftUI .toolbar items
            // dock into the titlebar area correctly (matched with the traffic
            // lights instead of floating into content).
            window.toolbarStyle = .unified
        }
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
