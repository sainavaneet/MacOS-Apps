import AppKit
import AVFoundation
import SwiftUI

/// Keeps the app running in the background even when the user closes the
/// window — so notifications keep flowing into the Inbox / Notification Center.
/// While the window is hidden the store is put into idle mode (every webview
/// is unloaded) to save RAM and stop the chat-list polling.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var statusItem: NSStatusItem?
    private weak var mainWindow: NSWindow?

    /// Token returned by `NotificationCenter.addObserver(forName:object:queue:using:)`
    /// — held so we can remove the observer in `deinit` instead of leaking.
    private var didBecomeKeyObserver: NSObjectProtocol?
    private var didBecomeActiveObserver: NSObjectProtocol?

    /// Output audio engine kept alive for the lifetime of the process. Running
    /// a permanently-attached silent node forces the macOS HAL to keep the
    /// output unit in a stable format (48 kHz / 2 ch) instead of renegotiating
    /// every time WebKit starts/stops a media element. That renegotiation is
    /// the textbook source of the "grrr" pop/glitch the user reported.
    private var audioPrewarm: AVAudioEngine?

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBar()
        prewarmAudioOutput()
        // Attach window delegate to every WindowGroup-spawned window so the
        // red close button hides instead of destroying it.
        DispatchQueue.main.async { [weak self] in
            self?.attachWindowDelegate()
        }
        didBecomeKeyObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.handleWindowDidBecomeKey() }
        }
        didBecomeActiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.handleAppDidBecomeActive() }
        }
    }

    deinit {
        if let token = didBecomeKeyObserver {
            NotificationCenter.default.removeObserver(token)
        }
        if let token = didBecomeActiveObserver {
            NotificationCenter.default.removeObserver(token)
        }
        audioPrewarm?.stop()
    }

    /// Never quit just because the window closed.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// Dock click brings the window back up.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows { showMainWindow() }
        return true
    }

    private func handleWindowDidBecomeKey() {
        attachWindowDelegate()
        // Coming back from hidden — wake the previously-foreground service.
        if let store = WebControllerStore.shared, store.isIdle {
            store.exitIdle()
        }
    }

    private func handleAppDidBecomeActive() {
        if let store = WebControllerStore.shared, store.isIdle {
            store.exitIdle()
        }
    }

    private func attachWindowDelegate() {
        for window in NSApp.windows {
            if window.contentViewController != nil || window.contentView != nil {
                if window.delegate !== self {
                    window.delegate = self
                    mainWindow = window
                }
            }
        }
    }

    // MARK: - NSWindowDelegate

    /// Intercept the red close button → hide, not destroy. Keeps state alive
    /// but enters idle mode so the webviews stop burning RAM + CPU.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        NSApp.hide(nil)
        WebControllerStore.shared?.enterIdle()
        return false
    }

    // MARK: - Audio prewarm

    private func prewarmAudioOutput() {
        let engine = AVAudioEngine()
        let format = engine.outputNode.outputFormat(forBus: 0)
        let player = AVAudioPlayerNode()
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        // Feed silence on a loop so the output graph stays active.
        if let buffer = silentBuffer(format: format) {
            player.scheduleBuffer(buffer, at: nil, options: [.loops], completionHandler: nil)
        }
        do {
            try engine.start()
            player.play()
            audioPrewarm = engine
        } catch {
            // Non-fatal: WebKit will still play audio, just without the HAL
            // stabilization. The user will see the same behavior as before.
            print("[Audio] prewarm engine start failed: \(error)")
        }
    }

    private func silentBuffer(format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let frameCount: AVAudioFrameCount = 4096
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            return nil
        }
        buffer.frameLength = frameCount
        // PCM buffers come zeroed already; nothing else to do.
        return buffer
    }

    // MARK: - Menu bar

    private func setupMenuBar() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "tray.full.fill",
                                   accessibilityDescription: "Social Hub")
            button.image?.isTemplate = true
            button.target = self
            button.action = #selector(statusBarClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        statusItem = item
    }

    @objc private func statusBarClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp {
            showMenu()
        } else {
            showMainWindow()
        }
    }

    private func showMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: "Open Social Hub", action: #selector(menuOpen), keyEquivalent: "")
            .target = self
        menu.addItem(.separator())

        let sleeping = WebControllerStore.shared?.isSleeping ?? false
        let sleepTitle = sleeping ? "Wake All Apps" : "Sleep All Apps (save memory)"
        let sleepItem = menu.addItem(withTitle: sleepTitle, action: #selector(toggleSleep), keyEquivalent: "")
        sleepItem.target = self
        sleepItem.state = sleeping ? .on : .off

        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Social Hub", action: #selector(menuQuit), keyEquivalent: "q")
            .target = self
        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        // Reset so subsequent left-clicks don't re-show the menu.
        DispatchQueue.main.async { [weak self] in self?.statusItem?.menu = nil }
    }

    @objc private func menuOpen() { showMainWindow() }
    @objc private func menuQuit() { NSApp.terminate(nil) }

    @objc private func toggleSleep() {
        guard let store = WebControllerStore.shared else { return }
        if store.isSleeping { store.wakeAll() } else { store.sleepAll() }
    }

    private func showMainWindow() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        if let window = mainWindow ?? NSApp.windows.first(where: { $0.canBecomeKey }) {
            window.makeKeyAndOrderFront(nil)
            mainWindow = window
            if window.delegate !== self { window.delegate = self }
        }
    }
}
