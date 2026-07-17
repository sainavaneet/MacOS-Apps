import SwiftUI
import UserNotifications

@main
struct SocialHubApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appState = AppState()
    @StateObject private var audioState = AudioState()
    @StateObject private var store = WebControllerStore()
    @StateObject private var feed = NotificationFeed()
    @StateObject private var launchLoader = LaunchLoader()
    @StateObject private var tools = ToolState()
    @StateObject private var memoryStat = MemoryStat()
    @StateObject private var ai = AIState()

    var body: some Scene {
        WindowGroup("Social Hub") {
            ZStack {
                RootView()

                if !launchLoader.dismissed {
                    LaunchOverlayView()
                        .zIndex(1)
                }
            }
            .environmentObject(appState)
            .environmentObject(audioState)
            .environmentObject(store)
            .environmentObject(feed)
            .environmentObject(launchLoader)
            .environmentObject(tools)
            .environmentObject(memoryStat)
            .environmentObject(ai)
            .frame(minWidth: 960, minHeight: 600)
            .preferredColorScheme(.dark)
            .background(WindowConfigurator())
            .onAppear {
                NotificationBridge.requestAuthorization()
                appState.attachAudioState(audioState)
                store.launchLoader = launchLoader
                store.toolState = tools
                launchLoader.begin()
            }
        }
        .defaultSize(width: 1280, height: 820)
        .windowResizability(.contentMinSize)
        .commands {
            SidebarCommands()
            CommandGroup(after: .toolbar) {
                Button("Restart Current App") {
                    if case .service(let id) = appState.selection {
                        store.restart(serviceID: id, appState: appState, feed: feed)
                    }
                }
                .keyboardShortcut("r", modifiers: .command)

                Divider()

                Button("Zoom In") {
                    appState.zoomIn()
                    appState.broadcastPageZoom(via: store)
                }
                .keyboardShortcut("=", modifiers: .command)
                .disabled(!appState.canZoomIn)

                Button("Zoom Out") {
                    appState.zoomOut()
                    appState.broadcastPageZoom(via: store)
                }
                .keyboardShortcut("-", modifiers: .command)
                .disabled(!appState.canZoomOut)

                Button("Actual Size") {
                    appState.resetZoom()
                    appState.broadcastPageZoom(via: store)
                }
                .keyboardShortcut("0", modifiers: .command)
            }
        }
    }
}
