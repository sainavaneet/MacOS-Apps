import Foundation

/// HTTP client for the Anthropic Messages API.
struct ClaudeAPI {
    let apiKey: String
    let model: String

    struct APIError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    struct Response {
        let contentBlocks: [ContentBlock]
        let stopReason: String

        enum ContentBlock {
            case text(String)
            case toolUse(id: String, name: String, input: [String: Any])
        }

        var textContent: String {
            contentBlocks.compactMap { block in
                if case .text(let text) = block { return text }
                return nil
            }.joined(separator: "\n")
        }

        var toolUseBlocks: [(id: String, name: String, input: [String: Any])] {
            contentBlocks.compactMap { block in
                if case .toolUse(let id, let name, let input) = block {
                    return (id, name, input)
                }
                return nil
            }
        }
    }

    func sendMessage(
        messages: [[String: Any]],
        system: String,
        tools: [[String: Any]] = []
    ) async throws -> Response {
        guard !apiKey.isEmpty else {
            throw APIError(message: "API key not set. Enter your Anthropic API key in Settings.")
        }

        guard let url = URL(string: "https://api.anthropic.com/v1/messages") else {
            throw APIError(message: "Invalid API URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.timeoutInterval = 60

        var body: [String: Any] = [
            "model": model,
            "max_tokens": 2048,
            "system": system,
            "messages": messages
        ]

        if !tools.isEmpty {
            body["tools"] = tools
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, httpResponse) = try await URLSession.shared.data(for: request)

        if let httpResp = httpResponse as? HTTPURLResponse, httpResp.statusCode != 200 {
            if let errorJSON = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = errorJSON["error"] as? [String: Any],
               let msg = error["message"] as? String {
                throw APIError(message: "API error (\(httpResp.statusCode)): \(msg)")
            }
            throw APIError(message: "API error: HTTP \(httpResp.statusCode)")
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw APIError(message: "Invalid API response")
        }

        return parseResponse(json)
    }

    private func parseResponse(_ json: [String: Any]) -> Response {
        let stopReason = json["stop_reason"] as? String ?? "end_turn"
        var blocks: [Response.ContentBlock] = []

        if let content = json["content"] as? [[String: Any]] {
            for block in content {
                let type = block["type"] as? String ?? ""

                switch type {
                case "text":
                    if let text = block["text"] as? String {
                        blocks.append(.text(text))
                    }

                case "tool_use":
                    if let id = block["id"] as? String,
                       let name = block["name"] as? String,
                       let input = block["input"] as? [String: Any] {
                        blocks.append(.toolUse(id: id, name: name, input: input))
                    }

                default:
                    break
                }
            }
        }

        return Response(contentBlocks: blocks, stopReason: stopReason)
    }
}
