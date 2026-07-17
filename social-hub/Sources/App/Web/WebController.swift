import AppKit
import WebKit

struct ChatContext {
    let partner: String?
    let turns: [ChatTurn]

    var isEmpty: Bool { turns.isEmpty }
}

@MainActor
final class WebController: NSObject {
    let service: Service
    let webView: WKWebView
    private weak var appState: AppState?
    private weak var feed: NotificationFeed?
    private weak var launchLoader: LaunchLoader?
    weak var toolState: ToolState?
    private var titleObservation: NSKeyValueObservation?
    private var progressObservation: NSKeyValueObservation?
    private var loadingObservation: NSKeyValueObservation?
    private let unreadRegex = try! NSRegularExpression(pattern: #"\((\d+)\)"#)
    private var hasLoaded = false
    private let uiDelegateBridge = WebUIDelegateBridge()
    /// CSS `zoom` factor applied to `document.body`. Persisted per-service.
    private(set) var pageZoom: Double = 1.0

    init(service: Service, appState: AppState, feed: NotificationFeed, launchLoader: LaunchLoader? = nil) {
        self.service = service
        self.appState = appState
        self.feed = feed
        self.launchLoader = launchLoader

        let config = WKWebViewConfiguration()
        // Per-service isolated cookie/localStorage jar (macOS 14+)
        config.websiteDataStore = WKWebsiteDataStore(forIdentifier: service.dataStoreID)
        config.preferences.javaScriptCanOpenWindowsAutomatically = true
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        // Require a user gesture for audio playback. Without this WebKit can
        // start a playback graph the moment the page loads, which triggers
        // first-frame buffer underruns ("grrr" noises) on macOS's audio HAL
        // and also lets ads autoplay sound.
        config.mediaTypesRequiringUserActionForPlayback = .audio

        let userContent = WKUserContentController()
        userContent.addUserScript(WKUserScript(
            source: NotificationBridge.injectedScript,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        ))
        userContent.addUserScript(WKUserScript(
            source: LocationBridge.injectedScript,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        ))
        userContent.addUserScript(WKUserScript(
            source: AudioBridge.injectedScript,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: false
        ))
        config.userContentController = userContent

        self.webView = WKWebView(frame: .zero, configuration: config)
        super.init()

        let proxy = WebScriptMessageProxy(target: self)
        userContent.add(proxy, name: NotificationBridge.channelName)
        userContent.add(proxy, name: LocationBridge.channelName)
        userContent.add(proxy, name: AudioBridge.channelName)
        userContent.add(proxy, name: ToolsBridge.channelName)

        webView.customUserAgent = ServiceCatalog.desktopUserAgent
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsMagnification = true
        // Non-opaque so the aurora gradient stays visible during about:blank
        // (sleep), service-switch transitions, and brief paint gaps — the
        // window flat-blanking bug.
        webView.setValue(false, forKey: "drawsBackground")
        webView.wantsLayer = true
        webView.layer?.backgroundColor = NSColor.clear.cgColor
        webView.uiDelegate = uiDelegateBridge

        // Initialize page zoom from the app-wide UI scale so a freshly-created
        // webview matches the rest of the chrome.
        if let scale = appState.uiScaleValueForController() { self.pageZoom = scale }

        titleObservation = webView.observe(\.title, options: [.new]) { [weak self] _, change in
            guard let self = self, let title = change.newValue ?? nil else { return }
            Task { @MainActor in self.handleTitleChange(title) }
        }

        // Drive the launch overlay progress bars
        progressObservation = webView.observe(\.estimatedProgress, options: [.new]) { [weak self] _, change in
            guard let self = self, let p = change.newValue else { return }
            Task { @MainActor in
                self.launchLoader?.update(self.service.id, progress: p)
            }
        }
        loadingObservation = webView.observe(\.isLoading, options: [.new]) { [weak self] webView, change in
            guard let self = self else { return }
            let stillLoading = change.newValue ?? false
            Task { @MainActor in
                if !stillLoading && webView.estimatedProgress >= 0.95 {
                    self.launchLoader?.markReady(self.service.id)
                    // Re-apply persisted page zoom — every navigation resets
                    // document.body inline styles.
                    self.applyPageZoom()
                }
            }
        }
    }

    deinit {
        titleObservation?.invalidate()
        progressObservation?.invalidate()
        loadingObservation?.invalidate()
    }

    func loadIfNeeded() {
        guard !hasLoaded else { return }
        hasLoaded = true
        launchLoader?.markStarted(service.id)
        webView.load(URLRequest(url: service.url))
    }

    func reload() {
        webView.reload()
    }

    // MARK: - Page zoom

    func setPageZoom(_ zoom: Double) {
        let clamped = max(0.6, min(1.4, (zoom * 100).rounded() / 100))
        pageZoom = clamped
        applyPageZoom()
    }

    func applyPageZoom() {
        // Transform-based zoom on <html> with inverse-scaled width/height.
        // CSS `zoom` shrinks content but the viewport units (vh / vw / 100%)
        // don't change, so the page lays out for the original viewport and
        // renders smaller — leaving empty space below at zoom < 1. Scaling
        // <html> AND expanding its logical size to 1/z lets the page lay out
        // for a wider viewport, then transform-scale brings it back to fit
        // the WKWebView's actual bounds. Chrome's zoom-out works similarly.
        let z = pageZoom
        let inv = 1.0 / z
        let js = """
        (function() {
          var z = \(z), inv = \(inv);
          var h = document.documentElement;
          if (!h) return;
          if (Math.abs(z - 1.0) < 0.001) {
            h.style.transform = '';
            h.style.transformOrigin = '';
            h.style.width = '';
            h.style.height = '';
            h.style.overflow = '';
          } else {
            h.style.transformOrigin = '0 0';
            h.style.transform = 'scale(' + z + ')';
            h.style.width = (inv * 100) + '%';
            h.style.height = (inv * 100) + '%';
            h.style.overflow = 'hidden';
          }
        })();
        """
        webView.evaluateJavaScript(js, completionHandler: nil)
    }

    // MARK: - Sleep / Wake (idle unload)

    /// Unload page state to free RAM. Cookies/auth survive (they live in the
    /// per-service `WKWebsiteDataStore`). On `wake()` the original URL is
    /// reloaded.
    func sleep() {
        guard hasLoaded else { return }
        webView.pauseAllMediaPlayback(completionHandler: nil)
        webView.load(URLRequest(url: URL(string: "about:blank")!))
        hasLoaded = false
        lastUnreadCount = 0
    }

    func wake() {
        loadIfNeeded()
    }

    // MARK: - Tools (Tinder auto-swipe etc.)

    func startAutoSwipe() {
        guard service.id == "tinder" else { return }
        webView.evaluateJavaScript(ToolsBridge.tinderAutoSwipe) { [weak self] _, _ in
            self?.webView.evaluateJavaScript(ToolsBridge.tinderAutoSwipeStart, completionHandler: nil)
        }
    }

    func stopAutoSwipe() {
        guard service.id == "tinder" else { return }
        webView.evaluateJavaScript(ToolsBridge.tinderAutoSwipeStop, completionHandler: nil)
    }

    func setAutoSwipeSpeed(_ speed: Double) {
        guard service.id == "tinder" else { return }
        webView.evaluateJavaScript(ToolsBridge.tinderAutoSwipeSetSpeed(speed), completionHandler: nil)
    }

    // MARK: - AI Compose / Rewrite

    func readActiveInputText() async -> String {
        await withCheckedContinuation { cont in
            webView.evaluateJavaScript(AIInputBridge.readScript) { result, _ in
                cont.resume(returning: (result as? String) ?? "")
            }
        }
    }

    func writeActiveInputText(_ text: String) async -> Bool {
        await withCheckedContinuation { cont in
            webView.evaluateJavaScript(AIInputBridge.writeScript(text)) { result, _ in
                cont.resume(returning: (result as? Bool) ?? false)
            }
        }
    }

    /// Captures the visible web content as a JPEG, optionally cropping a
    /// percentage off the left and right sides (Tinder's UI puts the chat
    /// in the center column with profile previews / nav on the edges, so
    /// dropping 30% per side keeps just the conversation).
    ///
    /// Returns JPEG data in memory — nothing is written to disk.
    func captureScreenshotJPEG(
        cropLeftPercent: CGFloat = 0,
        cropRightPercent: CGFloat = 0,
        maxWidth: CGFloat = 1400,
        quality: CGFloat = 0.78
    ) async -> Data? {
        let config = WKSnapshotConfiguration()
        config.snapshotWidth = NSNumber(value: Double(maxWidth))
        let image: NSImage? = await withCheckedContinuation { cont in
            webView.takeSnapshot(with: config) { img, _ in
                cont.resume(returning: img)
            }
        }
        guard let img = image,
              let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else { return nil }

        // Crop in pixel coordinates (CGImage is top-left origin).
        let w = CGFloat(cg.width)
        let h = CGFloat(cg.height)
        let leftCut = (max(0, min(0.45, cropLeftPercent))) * w
        let rightCut = (max(0, min(0.45, cropRightPercent))) * w
        let cropRect = CGRect(x: leftCut, y: 0, width: max(1, w - leftCut - rightCut), height: h)

        let finalCG: CGImage
        if cropRect.width < w {
            guard let cropped = cg.cropping(to: cropRect) else { return nil }
            finalCG = cropped
        } else {
            finalCG = cg
        }

        let bmp = NSBitmapImageRep(cgImage: finalCG)
        return bmp.representation(using: .jpeg, properties: [.compressionFactor: quality])
    }

    /// Read the last ~15 messages of the open conversation as chat context
    /// (sender = "me" or "them"). Returns empty turns if the page doesn't expose
    /// the messages (e.g. user isn't in a conversation, page still loading).
    func readConversationContext() async -> ChatContext {
        guard let js = ChatContextScraper.script(for: service.id) else {
            return ChatContext(partner: nil, turns: [])
        }
        let raw: String = await withCheckedContinuation { cont in
            webView.evaluateJavaScript(js) { result, _ in
                cont.resume(returning: (result as? String) ?? "")
            }
        }
        guard let data = raw.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data)
        else { return ChatContext(partner: nil, turns: []) }

        let partner: String?
        let turnDicts: [[String: Any]]
        if let dict = object as? [String: Any] {
            let rawPartner = (dict["partner"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            partner = rawPartner.isEmpty ? nil : rawPartner
            turnDicts = dict["turns"] as? [[String: Any]] ?? []
        } else if let arr = object as? [[String: Any]] {
            partner = nil
            turnDicts = arr
        } else {
            return ChatContext(partner: nil, turns: [])
        }

        let turns: [ChatTurn] = turnDicts.compactMap { d -> ChatTurn? in
            guard let from = d["from"] as? String,
                  let text = (d["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !text.isEmpty else { return nil }
            return ChatTurn(from: from, text: text)
        }
        return ChatContext(partner: partner, turns: turns)
    }

    func readPageText() async -> String {
        await withCheckedContinuation { cont in
            webView.evaluateJavaScript(ChatContextScraper.pageTextScript) { result, error in
                guard error == nil else {
                    cont.resume(returning: "")
                    return
                }
                cont.resume(returning: (result as? String) ?? "")
            }
        }
    }

    private func handleToolEvent(_ dict: [String: Any]) {
        guard let tools = toolState else { return }
        let event = dict["event"] as? String ?? ""
        switch event {
        case "started":
            tools.autoSwipeRunning = true
            tools.autoSwipeCount = 0
            tools.autoSwipeStatus = "Looking for cards…"
            tools.appendLog("▶ Started")
        case "swipe":
            tools.autoSwipeRunning = true
            tools.autoSwipeCount = dict["count"] as? Int ?? tools.autoSwipeCount + 1
            let via = (dict["via"] as? String) == "keyboard" ? " (kbd)" : ""
            tools.autoSwipeStatus = "Swiping… \(tools.autoSwipeCount)\(via)"
        case "no-card":
            let n = dict["noCard"] as? Int ?? 1
            tools.autoSwipeStatus = "No card (\(n)/6)…"
            tools.appendLog("· no card \(n)")
        case "limit-hit":
            tools.autoSwipeRunning = false
            let total = dict["swiped"] as? Int ?? tools.autoSwipeCount
            tools.autoSwipeStatus = "Limit hit at \(total)"
            tools.appendLog("■ Limit hit — \(total) swiped")
        case "stopped":
            tools.autoSwipeRunning = false
            let total = dict["swiped"] as? Int ?? tools.autoSwipeCount
            tools.autoSwipeStatus = "Stopped — \(total) swiped"
            tools.appendLog("■ Stopped — \(total) swiped")
        case "log":
            if let msg = dict["message"] as? String {
                tools.appendLog(msg)
                if !tools.autoSwipeRunning { tools.autoSwipeStatus = msg }
            }
        default:
            break
        }
    }

    fileprivate func handleScriptMessage(name: String, body: Any) {
        guard let dict = body as? [String: Any] else { return }
        switch name {
        case NotificationBridge.channelName:
            let title = dict["title"] as? String ?? ""
            let bodyText = dict["body"] as? String ?? ""
            feed?.push(serviceID: service.id,
                       title: title.isEmpty ? service.name : title,
                       body: bodyText)
        case LocationBridge.channelName:
            guard let id = dict["id"] as? Int,
                  let type = dict["type"] as? String else { return }
            LocationBridge.shared.request(from: webView, id: id, type: type)
        case AudioBridge.channelName:
            let playing = (dict["playing"] as? Bool) ?? false
            appState?.setPlayingAudio(playing, for: service.id)
            if playing {
                // Single-active-audio policy: pause every other service when
                // a new one starts. Avoids two audio graphs fighting for the
                // output unit (a textbook cause of "grrr" glitches).
                WebControllerStore.shared?.pauseAllMediaExcept(serviceID: service.id)
            }
        case ToolsBridge.channelName:
            handleToolEvent(dict)
        default:
            break
        }
    }

    private var lastUnreadCount: Int = 0

    private func handleTitleChange(_ title: String) {
        let range = NSRange(title.startIndex..<title.endIndex, in: title)
        let newCount: Int
        if let match = unreadRegex.firstMatch(in: title, range: range),
           match.numberOfRanges >= 2,
           let r = Range(match.range(at: 1), in: title),
           let count = Int(title[r]) {
            newCount = count
        } else {
            newCount = 0
        }
        appState?.setUnread(newCount, for: service.id)

        // Title-only notification: when the unread count rises, push a single
        // count-summary entry. We deliberately don't scrape the DOM here —
        // it's the path that fired Instagram false positives on every reflow.
        // Sender/preview is fetched on demand when the user clicks the toast.
        if newCount > lastUnreadCount {
            let delta = newCount - lastUnreadCount
            pushGenericUnread(count: delta)
        }
        lastUnreadCount = newCount
    }

    private func pushGenericUnread(count: Int) {
        let body = count == 1 ? "1 new message" : "\(count) new messages"
        feed?.push(serviceID: service.id, title: service.name, body: body)
    }

    /// On-demand scraper: returns the currently-visible unread chats for this
    /// service (sender + preview + avatar). Called when the user clicks a
    /// toast that wants more detail, or when the AI composer asks for context.
    /// Never invoked automatically.
    func scrapeUnreadChats() async -> [(sender: String, preview: String, avatar: String?)] {
        guard let script = ChatScraper.pollScript(for: service.id) else { return [] }
        let raw: String = await withCheckedContinuation { cont in
            webView.evaluateJavaScript(script) { result, _ in
                cont.resume(returning: (result as? String) ?? "")
            }
        }
        guard let data = raw.data(using: .utf8),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { return [] }
        return arr.compactMap { d in
            let sender = (d["sender"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !sender.isEmpty else { return nil }
            let preview = (d["preview"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let avatar = (d["avatar"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return (sender, preview, avatar?.isEmpty == false ? avatar : nil)
        }
    }
}

/// Avoids the strong-reference cycle WKUserContentController → handler → WKWebView.
@MainActor
private final class WebScriptMessageProxy: NSObject, WKScriptMessageHandler {
    weak var target: WebController?
    init(target: WebController) {
        self.target = target
        super.init()
    }
    func userContentController(_ userContentController: WKUserContentController,
                                didReceive message: WKScriptMessage) {
        target?.handleScriptMessage(name: message.name, body: message.body)
    }
}
