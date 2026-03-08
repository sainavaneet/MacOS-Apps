import SwiftUI

struct MeetingAssistantWindow: View {
    @StateObject private var microphoneManager = MicrophoneManager()
    @StateObject private var speechEngine = SpeechEngine()
    @StateObject private var chatManager = ChatManager()
    @StateObject private var sessionManager = SessionManager()

    var body: some View {
        MeetingAssistantContentView()
            .environmentObject(microphoneManager)
            .environmentObject(speechEngine)
            .environmentObject(chatManager)
            .environmentObject(sessionManager)
            .frame(minWidth: 720, minHeight: 500)
    }
}
