import SwiftUI

@main
struct AssistantApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // Hub window with sidebar
        WindowGroup("Assistant", id: "hub") {
            HubView()
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 520, height: 400)

        // Meeting Assistant sub-app window
        WindowGroup("Meeting Assistant", id: "meeting-assistant") {
            MeetingAssistantWindow()
        }
        .windowResizability(.contentSize)
    }
}
