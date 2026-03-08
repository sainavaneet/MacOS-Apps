import Foundation

struct ChatMessage: Identifiable, Codable {
    let id: UUID
    let role: Role
    var content: String
    let timestamp: Date
    var toolCalls: [ToolCall]
    var source: Source

    enum Role: String, Codable {
        case user
        case assistant
        case toolResult
    }

    enum Source: String, Codable {
        case typed
        case speech
    }

    init(role: Role, content: String, toolCalls: [ToolCall] = [], source: Source = .typed) {
        self.id = UUID()
        self.role = role
        self.content = content
        self.timestamp = Date()
        self.toolCalls = toolCalls
        self.source = source
    }
}

struct ToolCall: Identifiable, Codable {
    let id: String
    let name: String
    let input: String
    var result: String?
    var isLoading: Bool

    init(id: String, name: String, input: String) {
        self.id = id
        self.name = name
        self.input = input
        self.result = nil
        self.isLoading = true
    }
}
