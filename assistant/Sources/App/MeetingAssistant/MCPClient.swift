import Foundation

/// MCP client that communicates with an MCP server over stdio (newline-delimited JSON-RPC 2.0).
final class MCPClient: @unchecked Sendable {
    private var process: Process?
    private var stdinHandle: FileHandle?
    private var readBuffer = Data()
    private var nextID = 1
    private var pendingRequests: [Int: CheckedContinuation<[String: Any], Error>] = [:]
    private let lock = NSLock()

    private(set) var tools: [[String: Any]] = []
    private(set) var isConnected = false

    struct MCPError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// Start the MCP server process and initialize the connection.
    func connect(command: String, args: [String], cwd: String) async throws {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: command)
        proc.arguments = args
        proc.currentDirectoryURL = URL(fileURLWithPath: cwd)

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        proc.standardInput = stdinPipe
        proc.standardOutput = stdoutPipe
        proc.standardError = stderrPipe

        try proc.run()

        self.process = proc
        self.stdinHandle = stdinPipe.fileHandleForWriting

        // Start background reader for stdout
        let handle = stdoutPipe.fileHandleForReading
        Task.detached { [weak self] in
            self?.readLoop(handle: handle)
        }

        // Discard stderr
        stderrPipe.fileHandleForReading.readabilityHandler = { _ in }

        // Initialize MCP handshake
        let initResult = try await sendRequest(method: "initialize", params: [
            "protocolVersion": "2024-11-05",
            "capabilities": [String: Any](),
            "clientInfo": [
                "name": "MeetingAssistant",
                "version": "1.0"
            ]
        ])
        print("[MCP] Initialized: \(initResult["serverInfo"] ?? "unknown")")

        // Send initialized notification (no response expected)
        sendNotification(method: "notifications/initialized", params: nil)

        // Fetch tools
        let toolsResult = try await sendRequest(method: "tools/list", params: [String: Any]())
        if let toolsList = toolsResult["tools"] as? [[String: Any]] {
            self.tools = toolsList
            print("[MCP] Loaded \(toolsList.count) tools")
        }

        isConnected = true
    }

    /// Call an MCP tool by name with arguments.
    func callTool(name: String, arguments: [String: Any]) async throws -> String {
        let result = try await sendRequest(method: "tools/call", params: [
            "name": name,
            "arguments": arguments
        ])

        // Extract text content from MCP response
        if let content = result["content"] as? [[String: Any]] {
            let texts = content.compactMap { block -> String? in
                guard block["type"] as? String == "text" else { return nil }
                return block["text"] as? String
            }
            return texts.joined(separator: "\n")
        }

        // Fallback: return raw JSON
        if let data = try? JSONSerialization.data(withJSONObject: result, options: .prettyPrinted),
           let str = String(data: data, encoding: .utf8) {
            return str
        }
        return "{}"
    }

    /// Convert MCP tools to Claude API tool format.
    func claudeTools() -> [[String: Any]] {
        return tools.map { tool in
            var claudeTool: [String: Any] = [
                "name": tool["name"] ?? "",
                "description": tool["description"] ?? ""
            ]
            if let schema = tool["inputSchema"] {
                claudeTool["input_schema"] = schema
            }
            return claudeTool
        }
    }

    func disconnect() {
        isConnected = false
        stdinHandle?.closeFile()
        process?.terminate()
        process = nil
        stdinHandle = nil
        tools = []

        lock.lock()
        let pending = pendingRequests
        pendingRequests.removeAll()
        lock.unlock()

        for (_, continuation) in pending {
            continuation.resume(throwing: MCPError(message: "Disconnected"))
        }
    }

    // MARK: - JSON-RPC

    private func sendRequest(method: String, params: [String: Any]?) async throws -> [String: Any] {
        let id: Int = {
            lock.withLock {
                let current = nextID
                nextID += 1
                return current
            }
        }()

        var message: [String: Any] = [
            "jsonrpc": "2.0",
            "id": id,
            "method": method
        ]
        if let params = params {
            message["params"] = params
        }

        return try await withCheckedThrowingContinuation { continuation in
            lock.withLock {
                pendingRequests[id] = continuation
            }

            do {
                try writeMessage(message)
            } catch {
                _ = lock.withLock {
                    pendingRequests.removeValue(forKey: id)
                }
                continuation.resume(throwing: error)
            }
        }
    }

    private func sendNotification(method: String, params: [String: Any]?) {
        var message: [String: Any] = [
            "jsonrpc": "2.0",
            "method": method
        ]
        if let params = params {
            message["params"] = params
        }
        try? writeMessage(message)
    }

    private func writeMessage(_ message: [String: Any]) throws {
        guard let handle = stdinHandle else {
            throw MCPError(message: "Not connected")
        }
        let data = try JSONSerialization.data(withJSONObject: message, options: [])
        var line = data
        line.append(contentsOf: [UInt8(ascii: "\n")])
        handle.write(line)
    }

    private func readLoop(handle: FileHandle) {
        while true {
            let chunk = handle.availableData
            if chunk.isEmpty { break } // EOF

            readBuffer.append(chunk)

            // Process complete lines
            while let newlineIndex = readBuffer.firstIndex(of: UInt8(ascii: "\n")) {
                let lineData = readBuffer[readBuffer.startIndex..<newlineIndex]
                readBuffer = Data(readBuffer[readBuffer.index(after: newlineIndex)...])

                guard !lineData.isEmpty,
                      let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else {
                    continue
                }

                handleIncoming(json)
            }
        }

        // Process terminated — fail all pending requests
        lock.lock()
        let pending = pendingRequests
        pendingRequests.removeAll()
        lock.unlock()

        for (_, continuation) in pending {
            continuation.resume(throwing: MCPError(message: "MCP server process ended"))
        }
    }

    private func handleIncoming(_ message: [String: Any]) {
        // Response (has id)
        if let id = message["id"] as? Int {
            lock.lock()
            let continuation = pendingRequests.removeValue(forKey: id)
            lock.unlock()

            if let error = message["error"] as? [String: Any] {
                let msg = error["message"] as? String ?? "Unknown MCP error"
                continuation?.resume(throwing: MCPError(message: msg))
            } else if let result = message["result"] as? [String: Any] {
                continuation?.resume(returning: result)
            } else {
                continuation?.resume(returning: [:])
            }
        }
        // Notifications (no id) — ignore for now
    }
}
