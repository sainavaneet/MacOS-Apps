import Foundation

@MainActor
final class SessionManager: ObservableObject {
    @Published var sessions: [ChatSessionSummary] = []
    @Published var currentSessionID: UUID?

    private let sessionsDirectory: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init() {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!

        sessionsDirectory = appSupport
            .appendingPathComponent("MeetingAssistant", isDirectory: true)
            .appendingPathComponent("sessions", isDirectory: true)

        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        ensureDirectoryExists()
        refreshSessionList()
    }

    // MARK: - Directory

    private func ensureDirectoryExists() {
        try? FileManager.default.createDirectory(
            at: sessionsDirectory,
            withIntermediateDirectories: true
        )
    }

    // MARK: - List

    func refreshSessionList() {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: sessionsDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            sessions = []
            return
        }

        sessions = files
            .filter { $0.pathExtension == "json" }
            .compactMap { url -> ChatSessionSummary? in
                guard let data = try? Data(contentsOf: url),
                      let session = try? decoder.decode(ChatSession.self, from: data) else {
                    return nil
                }
                return ChatSessionSummary(
                    id: session.id,
                    title: session.title,
                    createdAt: session.createdAt,
                    lastModifiedAt: session.lastModifiedAt,
                    messageCount: session.messages.filter { $0.role != .toolResult }.count
                )
            }
            .sorted { $0.lastModifiedAt > $1.lastModifiedAt }
    }

    // MARK: - Save

    func save(session: ChatSession) {
        var session = session
        session.lastModifiedAt = Date()

        // Normalize in-flight tool calls
        for i in session.messages.indices {
            for j in session.messages[i].toolCalls.indices {
                session.messages[i].toolCalls[j].isLoading = false
            }
        }

        let fileURL = sessionsDirectory
            .appendingPathComponent("\(session.id.uuidString).json")

        do {
            let data = try encoder.encode(session)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("[SessionManager] Save failed: \(error)")
        }

        refreshSessionList()
    }

    // MARK: - Load

    func load(id: UUID) -> ChatSession? {
        let fileURL = sessionsDirectory
            .appendingPathComponent("\(id.uuidString).json")

        guard let data = try? Data(contentsOf: fileURL),
              var session = try? decoder.decode(ChatSession.self, from: data) else {
            return nil
        }

        // Normalize isLoading
        for i in session.messages.indices {
            for j in session.messages[i].toolCalls.indices {
                session.messages[i].toolCalls[j].isLoading = false
            }
        }

        return session
    }

    // MARK: - Delete

    func delete(id: UUID) {
        let fileURL = sessionsDirectory
            .appendingPathComponent("\(id.uuidString).json")
        try? FileManager.default.removeItem(at: fileURL)

        if currentSessionID == id {
            currentSessionID = nil
        }

        refreshSessionList()
    }

    // MARK: - Rename

    func rename(id: UUID, to newTitle: String) {
        guard var session = load(id: id) else { return }
        session.title = newTitle
        save(session: session)
    }
}
