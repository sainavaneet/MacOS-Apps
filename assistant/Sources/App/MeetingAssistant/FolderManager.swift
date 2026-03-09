import Foundation

@MainActor
final class FolderManager: ObservableObject {
    @Published var folders: [ChatFolder] = []
    private let folderKey = "chat_folders"

    init() {
        load()
    }

    func load() {
        if let data = UserDefaults.standard.data(forKey: folderKey),
           let decoded = try? JSONDecoder().decode([ChatFolder].self, from: data) {
            folders = decoded
        } else {
            folders = []
        }
    }

    func save() {
        if let encoded = try? JSONEncoder().encode(folders) {
            UserDefaults.standard.set(encoded, forKey: folderKey)
        }
    }

    func createFolder(name: String) {
        let folder = ChatFolder(name: name)
        folders.append(folder)
        save()
    }

    func renameFolder(id: UUID, newName: String) {
        if let index = folders.firstIndex(where: { $0.id == id }) {
            folders[index].name = newName
            save()
        }
    }

    func deleteFolder(id: UUID) {
        folders.removeAll { $0.id == id }
        save()
    }

    func addSessionToFolder(sessionId: UUID, folderId: UUID) {
        if let folderIndex = folders.firstIndex(where: { $0.id == folderId }) {
            if !folders[folderIndex].sessionIds.contains(sessionId) {
                folders[folderIndex].sessionIds.append(sessionId)
                save()
            }
        }
    }

    func removeSessionFromFolder(sessionId: UUID, folderId: UUID) {
        if let folderIndex = folders.firstIndex(where: { $0.id == folderId }) {
            folders[folderIndex].sessionIds.removeAll { $0 == sessionId }
            save()
        }
    }

    func removeSessionFromAllFolders(sessionId: UUID) {
        for i in 0..<folders.count {
            folders[i].sessionIds.removeAll { $0 == sessionId }
        }
        save()
    }

    func getFolder(for sessionId: UUID) -> ChatFolder? {
        folders.first { $0.sessionIds.contains(sessionId) }
    }
}

struct ChatFolder: Identifiable, Codable {
    var id: UUID = UUID()
    var name: String
    var sessionIds: [UUID] = []
    var createdAt: Date = Date()

    init(name: String) {
        self.name = name
    }
}
