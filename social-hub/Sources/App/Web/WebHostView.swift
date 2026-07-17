import SwiftUI

/// Host that mounts the **currently selected** service's webview only. Other
/// services live in `WebControllerStore` until they're either selected again
/// (warm reload) or idle-unloaded by the store's sweep. Mounting only the
/// foreground view dropped baseline RAM from ~1 GB (7 hot webviews) to roughly
/// the cost of one site.
struct WebHostView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var store: WebControllerStore
    @EnvironmentObject private var feed: NotificationFeed

    private var foreground: Service? {
        if case .service(let id) = appState.selection {
            return ServiceCatalog.service(id: id)
        }
        return nil
    }

    var body: some View {
        VStack(spacing: 0) {
            if let svc = foreground {
                WebToolbar(service: svc, controller: store.existingController(for: svc.id))
            }
            ZStack(alignment: .top) {
                // Local aurora backstop — guarantees the gradient stays visible
                // behind the WKWebView during about:blank, sleep, and switch
                // transitions even if the root-level gradient gets clipped.
                AuroraBackground(accent: appState.currentAccent())
                if let svc = foreground {
                    let controller = store.controller(for: svc, appState: appState, feed: feed)
                    ServiceWebView(controller: controller)
                        .id(ObjectIdentifier(controller))
                        .transition(.opacity)
                }
                ToastOverlay()
            }
            .animation(.easeInOut(duration: 0.15), value: foreground?.id)
        }
        .onChange(of: foreground?.id) { _, newID in
            if let id = newID {
                appState.markVisited(id)
                store.markForeground(id)
            }
        }
        .onAppear {
            if let id = foreground?.id { store.markForeground(id) }
        }
    }
}
