import Cocoa

// MARK: - Config
let pythonPath = "/Users/sainavaneet/miniconda3/bin/python"
let repoPath = "/Users/sainavaneet/Tensiq/research-graph"
let logDir = ("~/Library/Logs/TensiqSync" as NSString).expandingTildeInPath

enum SyncKind: String {
    case drive = "Drive"
    case slack = "Slack"

    var script: String {
        switch self {
        case .drive: return "sync_drive.py"
        case .slack: return "sync_slack.py"
        }
    }
}

enum SyncState {
    case idle
    case syncing(SyncKind)
    case success(SyncKind)
    case error(SyncKind)
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var menu: NSMenu!
    var statusMenuItem: NSMenuItem!
    var lastDriveItem: NSMenuItem!
    var lastSlackItem: NSMenuItem!

    var state: SyncState = .idle { didSet { render() } }
    var spinTimer: Timer?
    var spinAngle: CGFloat = 0
    var lastDrive: Date?
    var lastSlack: Date?

    var runningProcess: Process?
    var pendingQueue: [SyncKind] = []

    // Auto-sync
    let driveInterval: TimeInterval = 30 * 60   // 30 min
    let slackInterval: TimeInterval = 10 * 60   // 10 min
    var driveTimer: Timer?
    var slackTimer: Timer?
    var autoSyncEnabled: Bool = true
    var autoSyncMenuItem: NSMenuItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        try? FileManager.default.createDirectory(atPath: logDir, withIntermediateDirectories: true)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        buildMenu()
        statusItem.menu = menu
        render()

        // Run both syncs once on launch, then start the timers
        enqueue(.drive)
        enqueue(.slack)
        startAutoSyncTimers()
    }

    func buildMenu() {
        menu = NSMenu()
        statusMenuItem = NSMenuItem(title: "Idle", action: nil, keyEquivalent: "")
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)

        lastDriveItem = NSMenuItem(title: "Drive: never", action: nil, keyEquivalent: "")
        lastDriveItem.isEnabled = false
        menu.addItem(lastDriveItem)

        lastSlackItem = NSMenuItem(title: "Slack: never", action: nil, keyEquivalent: "")
        lastSlackItem.isEnabled = false
        menu.addItem(lastSlackItem)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Sync Drive Now",
                                action: #selector(syncDrive), keyEquivalent: "d"))
        menu.addItem(NSMenuItem(title: "Sync Slack Now",
                                action: #selector(syncSlack), keyEquivalent: "s"))
        menu.addItem(NSMenuItem(title: "Sync Both",
                                action: #selector(syncBoth), keyEquivalent: "b"))
        menu.addItem(.separator())
        autoSyncMenuItem = NSMenuItem(title: "Auto-sync: On (Drive 30m / Slack 10m)",
                                       action: #selector(toggleAutoSync), keyEquivalent: "a")
        menu.addItem(autoSyncMenuItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Open Logs",
                                action: #selector(openLogs), keyEquivalent: "l"))
        menu.addItem(NSMenuItem(title: "Quit",
                                action: #selector(quit), keyEquivalent: "q"))

        for item in menu.items where item.action != nil { item.target = self }
    }

    // MARK: - Rendering

    func render() {
        guard let button = statusItem.button else { return }

        switch state {
        case .idle:
            stopSpin()
            button.image = templateSymbol("arrow.triangle.2.circlepath")
            button.contentTintColor = nil
            button.title = ""
            statusMenuItem.title = "Idle"
        case .syncing(let kind):
            startSpin()
            button.contentTintColor = .systemBlue
            statusMenuItem.title = "Syncing \(kind.rawValue)…"
        case .success(let kind):
            stopSpin()
            button.image = templateSymbol("checkmark.circle.fill")
            button.contentTintColor = .systemGreen
            statusMenuItem.title = "\(kind.rawValue) sync complete"
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
                if case .success = self?.state { self?.state = .idle }
            }
        case .error(let kind):
            stopSpin()
            button.image = templateSymbol("exclamationmark.triangle.fill")
            button.contentTintColor = .systemRed
            statusMenuItem.title = "\(kind.rawValue) sync failed"
            DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) { [weak self] in
                if case .error = self?.state { self?.state = .idle }
            }
        }

        lastDriveItem.title = "Drive: \(format(lastDrive))"
        lastSlackItem.title = "Slack: \(format(lastSlack))"
    }

    func format(_ d: Date?) -> String {
        guard let d = d else { return "never" }
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f.localizedString(for: d, relativeTo: Date())
    }

    func templateSymbol(_ name: String) -> NSImage? {
        let cfg = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        let img = NSImage(systemSymbolName: name, accessibilityDescription: name)?
            .withSymbolConfiguration(cfg)
        img?.isTemplate = true
        return img
    }

    // MARK: - Spinner animation (rotated SF Symbol)

    func startSpin() {
        stopSpin()
        spinAngle = 0
        // initial frame so user sees something immediately
        if let button = statusItem.button {
            button.image = rotatedSyncIcon(angle: 0)
        }
        spinTimer = Timer.scheduledTimer(withTimeInterval: 1.0/30.0, repeats: true) { [weak self] _ in
            guard let self = self, let button = self.statusItem.button else { return }
            self.spinAngle -= 12
            if self.spinAngle <= -360 { self.spinAngle = 0 }
            button.image = self.rotatedSyncIcon(angle: self.spinAngle)
        }
    }

    func stopSpin() {
        spinTimer?.invalidate()
        spinTimer = nil
    }

    func rotatedSyncIcon(angle: CGFloat) -> NSImage? {
        guard let base = templateSymbol("arrow.triangle.2.circlepath") else { return nil }
        let size = NSSize(width: 18, height: 18)
        let img = NSImage(size: size, flipped: false) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            ctx.translateBy(x: rect.width / 2, y: rect.height / 2)
            ctx.rotate(by: angle * .pi / 180)
            let baseSize = base.size
            base.draw(in: NSRect(x: -baseSize.width / 2,
                                  y: -baseSize.height / 2,
                                  width: baseSize.width,
                                  height: baseSize.height),
                       from: .zero,
                       operation: .sourceOver,
                       fraction: 1.0)
            return true
        }
        img.isTemplate = true
        return img
    }

    // MARK: - Actions

    @objc func syncDrive() { enqueue(.drive) }
    @objc func syncSlack() { enqueue(.slack) }

    @objc func syncBoth() {
        enqueue(.drive)
        enqueue(.slack)
    }

    @objc func toggleAutoSync() {
        autoSyncEnabled.toggle()
        if autoSyncEnabled {
            startAutoSyncTimers()
            autoSyncMenuItem.title = "Auto-sync: On (Drive 30m / Slack 10m)"
        } else {
            driveTimer?.invalidate(); driveTimer = nil
            slackTimer?.invalidate(); slackTimer = nil
            autoSyncMenuItem.title = "Auto-sync: Off"
        }
    }

    func startAutoSyncTimers() {
        driveTimer?.invalidate()
        slackTimer?.invalidate()
        driveTimer = Timer.scheduledTimer(withTimeInterval: driveInterval, repeats: true) { [weak self] _ in
            self?.enqueue(.drive)
        }
        slackTimer = Timer.scheduledTimer(withTimeInterval: slackInterval, repeats: true) { [weak self] _ in
            self?.enqueue(.slack)
        }
    }

    func enqueue(_ kind: SyncKind) {
        // de-dup: don't queue the same kind twice
        if pendingQueue.contains(kind) { return }
        pendingQueue.append(kind)
        drainQueue()
    }

    func drainQueue() {
        guard runningProcess?.isRunning != true else { return }
        guard !pendingQueue.isEmpty else { return }
        let next = pendingQueue.removeFirst()
        run(next) { [weak self] _ in self?.drainQueue() }
    }

    @objc func openLogs() {
        NSWorkspace.shared.open(URL(fileURLWithPath: logDir))
    }

    @objc func quit() {
        runningProcess?.terminate()
        NSApp.terminate(nil)
    }

    func run(_ kind: SyncKind, completion: ((Bool) -> Void)? = nil) {
        if runningProcess?.isRunning == true {
            statusMenuItem.title = "Busy — try again when current sync finishes"
            return
        }

        state = .syncing(kind)

        let logURL = URL(fileURLWithPath: logDir)
            .appendingPathComponent("\(kind.rawValue.lowercased()).log")
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        let logHandle = try? FileHandle(forWritingTo: logURL)

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: pythonPath)
        proc.arguments = [kind.script]
        proc.currentDirectoryURL = URL(fileURLWithPath: repoPath)
        proc.standardOutput = logHandle
        proc.standardError = logHandle
        runningProcess = proc

        proc.terminationHandler = { [weak self] p in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.runningProcess = nil
                let ok = (p.terminationStatus == 0)
                if ok {
                    switch kind {
                    case .drive: self.lastDrive = Date()
                    case .slack: self.lastSlack = Date()
                    }
                    self.state = .success(kind)
                } else {
                    self.state = .error(kind)
                }
                completion?(ok)
            }
        }

        do {
            try proc.run()
        } catch {
            state = .error(kind)
            completion?(false)
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
