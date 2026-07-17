import AppKit
import WebKit

/// Per-WebController NSObject that handles file pickers, popups, JS dialogs.
final class WebUIDelegateBridge: NSObject, WKUIDelegate {

    /// Intercept popup links (target="_blank") and load them in the same webview
    /// so OAuth dialogs and "Open in new tab" links don't get eaten.
    func webView(_ webView: WKWebView,
                 createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url {
            webView.load(URLRequest(url: url))
        }
        return nil
    }

    /// Show NSOpenPanel for <input type="file"> — the reason file uploads
    /// silently failed before.
    func webView(_ webView: WKWebView,
                 runOpenPanelWith parameters: WKOpenPanelParameters,
                 initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping ([URL]?) -> Void) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = parameters.allowsMultipleSelection
        panel.canChooseDirectories = parameters.allowsDirectories
        panel.canChooseFiles = true
        panel.canCreateDirectories = false
        panel.title = "Choose files to upload"

        if let window = webView.window {
            panel.beginSheetModal(for: window) { response in
                completionHandler(response == .OK ? panel.urls : nil)
            }
        } else {
            let response = panel.runModal()
            completionHandler(response == .OK ? panel.urls : nil)
        }
    }

    // JS alert / confirm / prompt — surface as native panels so pages don't hang.
    func webView(_ webView: WKWebView,
                 runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping () -> Void) {
        let alert = NSAlert()
        alert.messageText = message
        alert.addButton(withTitle: "OK")
        if let window = webView.window {
            alert.beginSheetModal(for: window) { _ in completionHandler() }
        } else {
            alert.runModal(); completionHandler()
        }
    }

    func webView(_ webView: WKWebView,
                 runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping (Bool) -> Void) {
        let alert = NSAlert()
        alert.messageText = message
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        if let window = webView.window {
            alert.beginSheetModal(for: window) { resp in
                completionHandler(resp == .alertFirstButtonReturn)
            }
        } else {
            completionHandler(alert.runModal() == .alertFirstButtonReturn)
        }
    }

    func webView(_ webView: WKWebView,
                 runJavaScriptTextInputPanelWithPrompt prompt: String,
                 defaultText: String?,
                 initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping (String?) -> Void) {
        let alert = NSAlert()
        alert.messageText = prompt
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        field.stringValue = defaultText ?? ""
        alert.accessoryView = field
        if let window = webView.window {
            alert.beginSheetModal(for: window) { resp in
                completionHandler(resp == .alertFirstButtonReturn ? field.stringValue : nil)
            }
        } else {
            let resp = alert.runModal()
            completionHandler(resp == .alertFirstButtonReturn ? field.stringValue : nil)
        }
    }

    // Camera / mic permission — auto-grant since the user already granted at
    // the app level via Info.plist.
    func webView(_ webView: WKWebView,
                 requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                 initiatedByFrame frame: WKFrameInfo,
                 type: WKMediaCaptureType,
                 decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        decisionHandler(.grant)
    }
}
