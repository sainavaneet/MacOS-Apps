import Foundation

struct ChatSession: Identifiable, Codable {
    let id: UUID
    var title: String
    let createdAt: Date
    var lastModifiedAt: Date
    var messages: [ChatMessage]
    var transcript: String
    var lastProcessedTranscriptLength: Int

    init(
        title: String,
        messages: [ChatMessage] = [],
        transcript: String = "",
        lastProcessedTranscriptLength: Int = 0
    ) {
        self.id = UUID()
        self.title = title
        self.createdAt = Date()
        self.lastModifiedAt = Date()
        self.messages = messages
        self.transcript = transcript
        self.lastProcessedTranscriptLength = lastProcessedTranscriptLength
    }
}

struct ChatSessionSummary: Identifiable {
    let id: UUID
    let title: String
    let createdAt: Date
    let lastModifiedAt: Date
    let messageCount: Int
}
