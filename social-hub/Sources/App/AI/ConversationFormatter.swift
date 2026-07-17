import Foundation

enum ConversationFormatter {
    /// Bracket-prefixed conversation log:
    /// ```
    /// [Aya 21]   yeah just woke up lol
    /// [Me]       same haha what time did you sleep
    /// ```
    static func formatTranscript(turns: [ChatTurn], theirName: String? = nil) -> String {
        let cleaned = theirName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let otherName = cleaned.isEmpty ? "Them" : cleaned

        let bracketed: [String] = turns.map { turn in
            let label = turn.from.lowercased() == "me" ? "Me" : otherName
            return "[\(label)]"
        }
        let width = bracketed.map { $0.count }.max() ?? 0

        let lines: [String] = zip(bracketed, turns).map { pair in
            let padded = pair.0.padding(toLength: width, withPad: " ", startingAt: 0)
            let body = pair.1.text.trimmingCharacters(in: .whitespacesAndNewlines)
            return "\(padded)   \(body)"
        }

        return lines.joined(separator: "\n")
            .replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
    }

    /// Numbered list of the user's last `count` me-messages, used as a
    /// few-shot style sample so the model mirrors the user's voice.
    static func voiceSample(turns: [ChatTurn], count: Int = 6) -> String {
        let mine = turns
            .filter { $0.from.lowercased() == "me" }
            .suffix(max(0, count))

        guard !mine.isEmpty else { return "" }

        return mine.enumerated().map { pair in
            "\(pair.offset + 1). \(pair.element.text.trimmingCharacters(in: .whitespacesAndNewlines))"
        }
        .joined(separator: "\n")
    }
}
