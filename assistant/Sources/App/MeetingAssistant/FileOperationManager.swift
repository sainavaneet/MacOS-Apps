import Foundation

struct FileOperation: Identifiable {
    enum OperationType {
        case read
        case write
        case create
        case delete
    }

    let id: UUID = UUID()
    let type: OperationType
    let filePath: String
    let content: String?
    let originalContent: String?
    var status: OperationStatus = .pending

    enum OperationStatus {
        case pending
        case approved
        case rejected
        case completed
        case failed(String)
    }

    var isDangerous: Bool {
        switch type {
        case .delete:
            return true
        case .write:
            // Dangerous if modifying system files or sensitive directories
            return filePath.contains("/System") || filePath.contains("/Library/System")
        default:
            return false
        }
    }
}

@MainActor
final class FileOperationManager: ObservableObject {
    @Published var pendingOperations: [FileOperation] = []
    @Published var completedOperations: [FileOperation] = []

    private let fileManager = FileManager.default

    // MARK: - File Operations

    func readFile(path: String) -> Result<String, Error> {
        do {
            let content = try String(contentsOfFile: path, encoding: .utf8)
            return .success(content)
        } catch {
            return .failure(error)
        }
    }

    func writeFile(path: String, content: String) async -> Result<Void, Error> {
        do {
            // Create directory if it doesn't exist
            let directory = (path as NSString).deletingLastPathComponent
            if !fileManager.fileExists(atPath: directory) {
                try fileManager.createDirectory(atPath: directory, withIntermediateDirectories: true)
            }

            try content.write(toFile: path, atomically: true, encoding: .utf8)
            return .success(())
        } catch {
            return .failure(error)
        }
    }

    func deleteFile(path: String) -> Result<Void, Error> {
        do {
            try fileManager.removeItem(atPath: path)
            return .success(())
        } catch {
            return .failure(error)
        }
    }

    func fileExists(path: String) -> Bool {
        fileManager.fileExists(atPath: path)
    }

    // MARK: - Operation Management

    func createOperation(
        type: FileOperation.OperationType,
        filePath: String,
        content: String? = nil
    ) async -> FileOperation {
        var originalContent: String?
        if type == .write {
            if case .success(let existing) = readFile(path: filePath) {
                originalContent = existing
            }
        }

        let operation = FileOperation(
            type: type,
            filePath: filePath,
            content: content,
            originalContent: originalContent
        )

        DispatchQueue.main.async {
            self.pendingOperations.append(operation)
        }

        return operation
    }

    func approveOperation(_ operation: FileOperation) async {
        if let index = pendingOperations.firstIndex(where: { $0.id == operation.id }) {
            var updated = pendingOperations[index]
            updated.status = .approved
            pendingOperations[index] = updated
            await executeOperation(updated)
        }
    }

    func rejectOperation(_ operation: FileOperation) {
        if let index = pendingOperations.firstIndex(where: { $0.id == operation.id }) {
            var updated = pendingOperations[index]
            updated.status = .rejected
            pendingOperations.remove(at: index)
            completedOperations.append(updated)
        }
    }

    func executeOperation(_ operation: FileOperation) async {
        var updated = operation

        let result: Result<Void, Error>

        switch operation.type {
        case .read:
            result = .success(())

        case .write:
            guard let content = operation.content else {
                result = .failure(NSError(domain: "FileOperation", code: -1, userInfo: [NSLocalizedDescriptionKey: "No content provided"]))
                break
            }
            result = await writeFile(path: operation.filePath, content: content)

        case .create:
            guard let content = operation.content else {
                result = .failure(NSError(domain: "FileOperation", code: -1, userInfo: [NSLocalizedDescriptionKey: "No content provided"]))
                break
            }
            result = await writeFile(path: operation.filePath, content: content)

        case .delete:
            result = deleteFile(path: operation.filePath)
        }

        switch result {
        case .success:
            updated.status = .completed
        case .failure(let error):
            updated.status = .failed(error.localizedDescription)
        }

        // Move from pending to completed
        if let index = pendingOperations.firstIndex(where: { $0.id == operation.id }) {
            pendingOperations.remove(at: index)
        }
        completedOperations.append(updated)
    }

    func clearCompleted() {
        completedOperations.removeAll()
    }
}
