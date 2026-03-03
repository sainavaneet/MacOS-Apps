import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem.button {
            let chromeIcon = NSWorkspace.shared.icon(forFile: "/Applications/Google Chrome.app")
            chromeIcon.size = NSSize(width: 18, height: 18)
            button.image = chromeIcon
            button.action = #selector(openChrome)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.target = self
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Open Chrome", action: #selector(openChrome), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q"))
        statusItem.menu = nil
        self.menu = menu
    }

    var menu: NSMenu!

    @objc func openChrome() {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp {
            statusItem.menu = menu
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
            return
        }
        let chromeURL = URL(fileURLWithPath: "/Applications/Google Chrome.app")
        NSWorkspace.shared.openApplication(at: chromeURL,
                                           configuration: NSWorkspace.OpenConfiguration(),
                                           completionHandler: nil)
    }

    @objc func quitApp() {
        NSApp.terminate(nil)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
