import SwiftUI

struct SubApp: Identifiable {
    let id: String
    let windowID: String
    let name: String
    let description: String
    let icon: String
    let color: Color

    static let all: [SubApp] = [
        SubApp(
            id: "meeting-assistant",
            windowID: "meeting-assistant",
            name: "Meeting Assistant",
            description: "Transcribe and chat during meetings",
            icon: "waveform.circle.fill",
            color: .blue
        ),
        // Future sub-apps go here
    ]
}
