import Foundation

struct Command: Identifiable {
    enum CommandType {
        case shell
        case swift
        case git
        case python
    }

    let id: UUID = UUID()
    let type: CommandType
    let command: String
    let workingDirectory: String
    var output: String = ""
    var exitCode: Int32 = 0
    var status: CommandStatus = .pending

    enum CommandStatus {
        case pending
        case approved
        case rejected
        case running
        case completed
        case failed(String)
    }

    var isDangerous: Bool {
        let dangerous = ["rm -rf", "sudo", "reboot", "shutdown"]
        return dangerous.contains { command.contains($0) }
    }

    var displayCommand: String {
        switch type {
        case .shell:
            return "$ \(command)"
        case .swift:
            return "swift \(command)"
        case .git:
            return "git \(command)"
        case .python:
            return "python \(command)"
        }
    }
}

@MainActor
final class CommandExecutor: ObservableObject {
    @Published var pendingCommands: [Command] = []
    @Published var completedCommands: [Command] = []

    // MARK: - Command Execution

    func createCommand(
        type: Command.CommandType = .shell,
        command: String,
        workingDirectory: String = FileManager.default.currentDirectoryPath
    ) -> Command {
        Command(
            type: type,
            command: command,
            workingDirectory: workingDirectory
        )
    }

    func approveCommand(_ command: Command) async {
        if let index = pendingCommands.firstIndex(where: { $0.id == command.id }) {
            var updated = pendingCommands[index]
            updated.status = .approved
            pendingCommands[index] = updated
            await executeCommand(updated)
        }
    }

    func rejectCommand(_ command: Command) {
        if let index = pendingCommands.firstIndex(where: { $0.id == command.id }) {
            var updated = pendingCommands[index]
            updated.status = .rejected
            pendingCommands.remove(at: index)
            completedCommands.append(updated)
        }
    }

    func executeCommand(_ command: Command) async {
        var updated = command
        updated.status = .running

        let shell = "/bin/bash"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)
        process.arguments = ["-c", command.command]
        process.currentDirectoryURL = URL(fileURLWithPath: command.workingDirectory)

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                updated.output = output
            }

            updated.exitCode = process.terminationStatus
            updated.status = process.terminationStatus == 0 ? .completed : .failed("Exit code: \(process.terminationStatus)")
        } catch {
            updated.status = .failed(error.localizedDescription)
        }

        // Move from pending to completed
        if let index = pendingCommands.firstIndex(where: { $0.id == command.id }) {
            pendingCommands.remove(at: index)
        }
        completedCommands.append(updated)
    }

    func clearCompleted() {
        completedCommands.removeAll()
    }
}
