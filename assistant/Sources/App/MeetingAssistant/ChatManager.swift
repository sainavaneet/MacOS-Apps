import Foundation
import SwiftUI

@MainActor
final class ChatManager: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var mcpConnected = false
    @AppStorage("auto_answer_enabled") var autoAnswer = true
    @AppStorage("auto_connect_mcp") var autoConnectMCP = false

    @AppStorage("anthropic_api_key") var apiKey: String = ""
    @AppStorage("mcp_server_path") var mcpServerPath: String =
        "/Users/sainavaneet/Library/Mobile Documents/com~apple~CloudDocs/WORK/Tensiq/research-graph"
    @AppStorage("mcp_python_path") var mcpPythonPath: String =
        "/Users/sainavaneet/miniconda3/bin/python"

    static let availableModels: [(id: String, name: String)] = [
        ("claude-haiku-4-5-20251001", "Haiku 4.5"),
        ("claude-sonnet-4-6-20250514", "Sonnet 4.6"),
        ("claude-opus-4-6-20250514", "Opus 4.6"),
    ]

    private let mcpClient = MCPClient()
    private(set) var lastProcessedTranscriptLength = 0
    @AppStorage("claude_model") var model: String = "claude-haiku-4-5-20251001"

    // MARK: - Send Message

    /// Send a user message to Claude, with transcript context and MCP tools.
    func send(_ text: String, transcript: String, source: ChatMessage.Source = .typed) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        messages.append(ChatMessage(role: .user, content: trimmed, source: source))
        isLoading = true
        errorMessage = nil

        do {
            try await runConversation(transcript: transcript)
        } catch {
            errorMessage = error.localizedDescription
            print("[ChatManager] Error: \(error)")
        }

        isLoading = false
    }

    /// Main conversation loop — handles tool use cycles.
    private func runConversation(transcript: String) async throws {
        let api = ClaudeAPI(apiKey: apiKey, model: model)
        let systemPrompt = buildSystemPrompt(transcript: transcript)
        let tools = mcpClient.isConnected ? mcpClient.claudeTools() : []

        print("[ChatManager] Sending to Claude (model: \(model), tools: \(tools.count), transcript length: \(transcript.count))")

        var maxIterations = 10 // safety limit for tool loops

        while maxIterations > 0 {
            maxIterations -= 1

            let apiMessages = buildAPIMessages()
            let response = try await api.sendMessage(
                messages: apiMessages,
                system: systemPrompt,
                tools: tools
            )

            // Handle tool_use
            if response.stopReason == "tool_use" {
                let toolBlocks = response.toolUseBlocks

                // Add assistant message with text + tool calls
                var toolCalls = toolBlocks.map { block in
                    ToolCall(
                        id: block.id,
                        name: block.name,
                        input: prettyJSON(block.input)
                    )
                }

                let assistantText = response.textContent
                messages.append(ChatMessage(
                    role: .assistant,
                    content: assistantText,
                    toolCalls: toolCalls
                ))

                // Execute each tool via MCP
                for i in toolCalls.indices {
                    let block = toolBlocks[i]

                    do {
                        let result = try await mcpClient.callTool(
                            name: block.name,
                            arguments: block.input
                        )
                        toolCalls[i].result = result
                        toolCalls[i].isLoading = false
                    } catch {
                        toolCalls[i].result = "Error: \(error.localizedDescription)"
                        toolCalls[i].isLoading = false
                    }
                }

                // Update the message with tool results
                if let lastIndex = messages.indices.last {
                    messages[lastIndex].toolCalls = toolCalls
                }

                // Add tool results as a tool_result message for the API
                messages.append(ChatMessage(
                    role: .toolResult,
                    content: "", // content is in toolCalls
                    toolCalls: toolCalls
                ))

                continue // loop for Claude to process tool results
            }

            // No tool use — just text response
            let text = response.textContent
            if !text.isEmpty {
                messages.append(ChatMessage(role: .assistant, content: text))
            }
            break
        }
    }

    // MARK: - MCP Connection

    func connectMCP() async {
        guard !mcpServerPath.isEmpty, !mcpPythonPath.isEmpty else {
            errorMessage = "MCP server path or Python path not set."
            return
        }

        do {
            try await mcpClient.connect(
                command: mcpPythonPath,
                args: ["-m", "mcp_server.server"],
                cwd: mcpServerPath
            )
            mcpConnected = true
            print("[ChatManager] MCP connected with \(mcpClient.tools.count) tools")
        } catch {
            errorMessage = "MCP connection failed: \(error.localizedDescription)"
            mcpConnected = false
            print("[ChatManager] MCP error: \(error)")
        }
    }

    func disconnectMCP() {
        mcpClient.disconnect()
        mcpConnected = false
    }

    // MARK: - Auto-Answer from Transcript

    /// Send new transcript text to Claude automatically.
    func checkForQuestions(transcript: String) {
        if !autoAnswer { return }
        if isLoading {
            print("[ChatManager] Skipping auto-send: already loading")
            return
        }
        if apiKey.isEmpty {
            print("[ChatManager] Skipping auto-send: no API key set")
            return
        }

        let newText = String(transcript.dropFirst(lastProcessedTranscriptLength))
        lastProcessedTranscriptLength = transcript.count

        guard !newText.isEmpty else { return }

        // Extract the actual text from new lines (strip timestamps)
        let lines = newText.components(separatedBy: "\n")
        var speechTexts: [String] = []

        for line in lines {
            let text: String
            if let bracket = line.range(of: "] "), line.hasPrefix("[") {
                text = String(line[bracket.upperBound...])
            } else {
                text = line
            }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.count > 5 { // skip very short fragments
                speechTexts.append(trimmed)
            }
        }

        guard !speechTexts.isEmpty else { return }

        let combined = speechTexts.joined(separator: " ")
        print("[ChatManager] Auto-sending speech to Claude: \(combined)")

        Task {
            await send(combined, transcript: transcript, source: .speech)
        }
    }

    /// Manually send accumulated unsent transcript text to Claude.
    func sendPendingTranscript(transcript: String) async {
        guard !isLoading, !apiKey.isEmpty else { return }

        let newText = String(transcript.dropFirst(lastProcessedTranscriptLength))
        lastProcessedTranscriptLength = transcript.count

        guard !newText.isEmpty else { return }

        let lines = newText.components(separatedBy: "\n")
        var speechTexts: [String] = []

        for line in lines {
            let text: String
            if let bracket = line.range(of: "] "), line.hasPrefix("[") {
                text = String(line[bracket.upperBound...])
            } else {
                text = line
            }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                speechTexts.append(trimmed)
            }
        }

        guard !speechTexts.isEmpty else { return }

        let combined = speechTexts.joined(separator: " ")
        print("[ChatManager] Manual send transcript: \(combined)")
        await send(combined, transcript: transcript, source: .speech)
    }

    func clearChat() {
        messages.removeAll()
        lastProcessedTranscriptLength = 0
    }

    func loadSession(messages: [ChatMessage], lastProcessedTranscriptLength: Int) {
        self.messages = messages
        self.lastProcessedTranscriptLength = lastProcessedTranscriptLength
    }

    // MARK: - Helpers

    private func buildSystemPrompt(transcript: String) -> String {
        var prompt = """
        You are a helpful meeting assistant. You help answer questions and provide insights \
        during meetings. Be concise and direct in your responses.
        """

        if !transcript.isEmpty {
            prompt += """

            Here is the current meeting transcript for context:

            <transcript>
            \(transcript)
            </transcript>

            Use this transcript to inform your answers when relevant.
            """
        }

        if mcpClient.isConnected {
            prompt += """

            You have access to a research knowledge graph via tools. Use these tools when the user \
            asks about papers, experiments, tasks, people, or research-related topics.
            """
        }

        return prompt
    }

    private func buildAPIMessages() -> [[String: Any]] {
        var apiMessages: [[String: Any]] = []

        for msg in messages {
            switch msg.role {
            case .user:
                apiMessages.append([
                    "role": "user",
                    "content": msg.content
                ])

            case .assistant:
                var content: [[String: Any]] = []

                if !msg.content.isEmpty {
                    content.append(["type": "text", "text": msg.content])
                }

                for tool in msg.toolCalls {
                    var inputJSON: Any = [String: Any]()
                    if let data = tool.input.data(using: .utf8),
                       let parsed = try? JSONSerialization.jsonObject(with: data) {
                        inputJSON = parsed
                    }
                    content.append([
                        "type": "tool_use",
                        "id": tool.id,
                        "name": tool.name,
                        "input": inputJSON
                    ])
                }

                apiMessages.append([
                    "role": "assistant",
                    "content": content
                ])

            case .toolResult:
                var content: [[String: Any]] = []
                for tool in msg.toolCalls {
                    content.append([
                        "type": "tool_result",
                        "tool_use_id": tool.id,
                        "content": tool.result ?? ""
                    ])
                }
                apiMessages.append([
                    "role": "user",
                    "content": content
                ])
            }
        }

        return apiMessages
    }

    private func prettyJSON(_ dict: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: dict, options: .prettyPrinted),
              let str = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return str
    }
}
