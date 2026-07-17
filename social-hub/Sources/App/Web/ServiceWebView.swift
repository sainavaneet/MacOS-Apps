import SwiftUI
import WebKit

struct ServiceWebView: NSViewRepresentable {
    let controller: WebController

    func makeNSView(context: Context) -> WKWebView {
        controller.loadIfNeeded()
        controller.webView.isHidden = false
        return controller.webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        if nsView.isHidden { nsView.isHidden = false }
    }
}
