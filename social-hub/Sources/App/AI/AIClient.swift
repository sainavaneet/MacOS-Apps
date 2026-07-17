import Foundation

enum AIClient {
    struct Message: Codable {
        let role: String
        let content: String
    }
    private struct Request: Codable {
        let model: String
        let messages: [Message]
        let max_tokens: Int
        let temperature: Double
        let stream: Bool
    }
    private struct Response: Decodable {
        struct Choice: Decodable {
            struct Msg: Decodable { let content: String? }
            let message: Msg
        }
        let choices: [Choice]
    }

    enum AIError: LocalizedError {
        case badURL(String)
        case http(Int, String)
        case decode(Error)
        case network(URLError, URL)

        var errorDescription: String? {
            switch self {
            case .badURL(let s): return "Endpoint URL is not valid: \(s)"
            case .http(let code, let body):
                return "Server returned HTTP \(code). \(body.prefix(200))"
            case .decode(let e): return "Bad response: \(e.localizedDescription)"
            case .network(let e, let url):
                return "Couldn't reach \(url.host ?? url.absoluteString):\(url.port ?? -1) — \(e.localizedDescription) [code \(e.code.rawValue)]"
            }
        }
    }

    /// Default-configuration session — `.ephemeral` can be stricter about
    /// ATS in some macOS versions. We want ATS rules to come straight from
    /// our Info.plist (`NSAllowsArbitraryLoads = true`).
    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = true
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 120
        return URLSession(configuration: config)
    }()

    static func rewrite(
        endpoint: String,
        model: String,
        apiKey: String,
        systemPrompt: String,
        userDraft: String
    ) async throws -> String {
        // Build the URL by appending the well-known OpenAI path. Be lenient
        // about whether the user included /v1 or trailing slashes.
        let trimmed = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\u{200B}", with: "")  // zero-width strip
        var base = trimmed
        while base.hasSuffix("/") { base.removeLast() }
        let full = base + "/chat/completions"
        guard let url = URL(string: full), url.host != nil else {
            throw AIError.badURL(full)
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 60
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !apiKey.isEmpty {
            req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        // Wrap the draft so the model can't mistake it for a message
        // addressed to it. Explicit framing > role: user content alone.
        let framedDraft = """
        DRAFT MESSAGE TO REPHRASE (this is what I want to send, NOT a message to you):

        \(userDraft)

        Now output ONLY the rephrased version of that draft — same meaning, same speaker (me), in the requested style.
        """
        let body = Request(
            model: model,
            messages: [
                Message(role: "system", content: systemPrompt),
                Message(role: "user",   content: framedDraft)
            ],
            max_tokens: 800,
            temperature: 0.6,
            stream: false
        )
        req.httpBody = try JSONEncoder().encode(body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: req)
        } catch let urlError as URLError {
            throw AIError.network(urlError, url)
        } catch {
            throw AIError.network(URLError(.unknown), url)
        }

        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let text = String(data: data, encoding: .utf8) ?? ""
            throw AIError.http(http.statusCode, text)
        }

        do {
            let parsed = try JSONDecoder().decode(Response.self, from: data)
            return parsed.choices.first?.message.content?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        } catch {
            throw AIError.decode(error)
        }
    }

    /// Suggest 3 short message options given a recent conversation. The
    /// model is told to reason about WHOSE TURN IT IS — replying to a
    /// question is different from continuing after your own message went
    /// unanswered or got only a reaction.
    static func suggestReplies(
        endpoint: String,
        model: String,
        apiKey: String,
        turns: [ChatTurn],
        theirName: String? = nil
    ) async throws -> [String] {
        let lastTurns = Array(turns.suffix(20))
        let system = """
        You help the user pick what to send next in a chat. Think carefully before answering.

        STEP 1 — analyze the conversation state (silently, do not write this analysis):
        • Whose turn is it? Look at the LAST 2-3 turns.
        • Case A: LAST turn is from 'them' AND it's a question or invites a reply
                  → suggest 3 ANSWERS / REPLIES that fit naturally.
        • Case B: LAST turn(s) are from 'me' (they haven't replied yet, or only reacted with an emoji,
                  or the latest activity is just a reaction to my message)
                  → DO NOT pretend they said something. Suggest 3 NEW MESSAGES from me to keep the
                    conversation going — follow-up questions, a topic change, a callback to earlier context,
                    or something playful. NEVER suggest acknowledgments like 'okay', 'got it', 'thanks',
                    or replies that imply they just told me something.
        • Case C: conversation feels stalled or one-word-dead
                  → suggest 3 conversation REVIVERS — a new topic, a callback joke, a casual check-in.

        STEP 2 — produce 3 distinct options with DIFFERENT vibes:
        • One CASUAL & short
        • One PLAYFUL / a bit teasing or warm
        • One that MOVES THE CONVERSATION FORWARD (asks a question or proposes something)

        The user (Me) texts in this style — match it exactly. Same casing, same length, same effort:

        <voiceSample>
        \(ConversationFormatter.voiceSample(turns: lastTurns))
        </voiceSample>

        Write replies in that voice.

        VOICE & FORMAT:
        • Each option ~12–25 words — a real sentence or two, not a 2-word reply. Substantial enough to actually push the conversation forward.
        • Never repeat what was just said in the transcript.
        • Each option ON ITS OWN — separated by |||
        • No numbering, no quotes, no commentary, no markdown, no preamble. JUST the 3 options.

        Example output format (literal): option one|||option two|||option three
        """

        let transcript = ConversationFormatter.formatTranscript(turns: lastTurns, theirName: theirName)
        let lastFrom = lastTurns.last?.from ?? "them"
        let stateHint: String
        switch lastFrom {
        case "me":
            stateHint = "MY LAST MESSAGE GOT NO REPLY (or only a reaction). I need NEW messages to continue or restart, not replies."
        default:
            stateHint = "They just messaged me — I might need to reply."
        }

        let user = """
        /no_think

        Conversation (last \(lastTurns.count) turns, oldest first; 'them:' is the other person, 'me:' is what I sent):

        \(transcript)

        STATE: \(stateHint)

        Now output ONLY three message options separated by |||. No reasoning, no analysis, no commentary, no labels. Just the three options.
        """

        // Use a slightly lower temperature for more grounded reasoning.
        let raw = try await rewrite(
            endpoint: endpoint,
            model: model,
            apiKey: apiKey,
            systemPrompt: system,
            userDraft: user
        )

        return parseThreeOptions(raw)
    }

    static func suggestReplies(
        endpoint: String,
        model: String,
        apiKey: String,
        turns context: ChatContext
    ) async throws -> [String] {
        try await suggestReplies(
            endpoint: endpoint,
            model: model,
            apiKey: apiKey,
            turns: context.turns,
            theirName: context.partner
        )
    }

    static func suggestRepliesFromPageText(
        endpoint: String,
        model: String,
        apiKey: String,
        pageText: String,
        theirName: String? = nil
    ) async throws -> [String] {
        let system = """
        You are reading the visible text of a chat web page that was scraped. Identify the conversation turns (right-aligned or blue bubbles tend to be MINE; left or grey are theirs). Infer my texting voice from my recent messages. Output exactly 3 reply options separated by |||. No commentary, no markdown, no preamble.
        """
        let user = """
        Page text:
        \(pageText)

        Suggest 3 replies.
        """
        _ = theirName

        let raw = try await rewrite(
            endpoint: endpoint,
            model: model,
            apiKey: apiKey,
            systemPrompt: system,
            userDraft: user
        )

        return parseThreeOptions(raw)
    }

    /// Same as `suggestReplies` but feeds a screenshot of the chat to a
    /// vision-capable model. Useful for services where DOM scraping is
    /// unreliable (Tinder, Snapchat). Uses the OpenAI multi-modal content
    /// array format: `[{type:text, text:...}, {type:image_url, image_url:{url:...}}]`.
    static func suggestRepliesFromImage(
        endpoint: String,
        model: String,
        apiKey: String,
        imageJPEG: Data
    ) async throws -> [String] {
        let trimmed = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        var base = trimmed; while base.hasSuffix("/") { base.removeLast() }
        let full = base + "/chat/completions"
        guard let url = URL(string: full), url.host != nil else { throw AIError.badURL(full) }

        let b64 = imageJPEG.base64EncodedString()
        let dataURL = "data:image/jpeg;base64,\(b64)"

        let systemPrompt = """
        You are looking at a screenshot of a dating-app conversation. Generate 3 FLIRTY message options for me to send next.

        Visual conventions:
        • Right-aligned bubbles = sent by ME
        • Left-aligned bubbles (often with her avatar) = sent by HER

        Silently identify the last message. If it's from her, suggest flirty replies. If it's from me with no response (or just a like), suggest flirty pivots that re-spark her interest.

        STRICT FORMAT (this is non-negotiable — output will be rejected otherwise):
        • Lowercase only. Even "i" stays lowercase.
        • Each option 15–30 words. Real sentences, not one-liners.
        • ZERO punctuation. No periods commas question marks exclamation marks apostrophes quotes colons semicolons em-dashes ellipses NOTHING. Just letters and spaces.
        • Contractions written without apostrophes: im dont youre wanna gonna isnt cant ill ive ngl idk fr lowkey rn
        • Three different flirty angles: one playful tease, one warm/curious about her, one a bit forward/confident
        • Never repeat what was just said. Never use bare acknowledgments like ok got it thanks haha

        EXAMPLES of correctly formatted flirty options (note: NO punctuation at all, lowercase, 15-30 words):

        okay but you clearly know exactly what youre doing pretending to be casual when youre making it impossible for me to focus on anything else
        ngl im starting to think you might actually be more dangerous than fun and im weirdly into that whole situation rn
        whats the move tonight because im not letting you ghost me after dropping that energy into my inbox so confidently

        OUTPUT: exactly 3 options separated by ||| on a single line. No numbering, no labels, no commentary, no markdown.
        """

        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": [
                    ["type": "text", "text": "/no_think\n\nRead the chat in this screenshot and output ONLY three flirty message options separated by |||. No reasoning, no analysis, no commentary, no labels — just the three options themselves."],
                    ["type": "image_url", "image_url": ["url": dataURL]]
                ] as [Any]] as [String: Any]
            ],
            "max_tokens": 600,
            "temperature": 0.6,
            "stream": false
        ]

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 90
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !apiKey.isEmpty { req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization") }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: req)
        } catch let urlError as URLError {
            throw AIError.network(urlError, url)
        } catch {
            throw AIError.network(URLError(.unknown), url)
        }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw AIError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        let parsed = try JSONDecoder().decode(Response.self, from: data)
        let raw = parsed.choices.first?.message.content?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        // Hard-strip punctuation and force lowercase post-hoc — the model is
        // unreliable about the "no punctuation" rule even with strict prompting.
        return parseThreeOptions(raw).map(stripPunctuationAndLowercase)
    }

    /// Removes every punctuation/symbol char and lowercases the string.
    /// Used to enforce the texting-tone format for screenshot replies.
    private static func stripPunctuationAndLowercase(_ text: String) -> String {
        let punctSet = CharacterSet.punctuationCharacters
            .union(CharacterSet.symbols)
            .union(CharacterSet(charactersIn: "“”‘’—–…•"))
        var out = String(text.unicodeScalars.filter { !punctSet.contains($0) })
        // Collapse any whitespace runs caused by removal
        out = out.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        return out.trimmingCharacters(in: .whitespaces).lowercased()
    }

    /// Generate 3 random pickup lines on demand — no chat context needed.
    /// Uses high temperature + randomized theme rotation so repeat calls
    /// produce genuinely different results.
    static func randomPickupLines(
        endpoint: String,
        model: String,
        apiKey: String
    ) async throws -> [String] {
        // Rotate 3 random themes from a deep pool so every call hits a
        // different set of angles — kills the "same lines every time" effect.
        let themes = [
            "punny / dad-joke energy",
            "smooth and confident — like you actually do this often",
            "absurd, chaotic, slightly unhinged",
            "philosophical and weird in a charming way",
            "self-deprecating and humble",
            "playfully arrogant",
            "movie or song reference, casually dropped",
            "based on a wildly specific hypothetical scenario",
            "starts mid-thought like youve been thinking about her for hours",
            "compliments her in an oblique way (not just 'youre pretty')",
            "challenges her to something playful",
            "low-key chaotic flirt with a callback to something universal",
            "starts with a confession or admission",
            "frames you as the underdog asking for a favor",
            "weather / time-of-day specific"
        ]
        let picked = themes.shuffled().prefix(3)
        let themesText = picked.enumerated()
            .map { "Option \($0.offset + 1) vibe: \($0.element)" }
            .joined(separator: "\n")
        let seed = Int.random(in: 1...99_999)

        let system = """
        Generate 3 random opening pickup lines for me to send on a dating app.

        Rules:
        - Pull from a HUGE pool — never reuse common lines. NO "did it hurt when you fell from heaven", NO "are you a magician", NO "hey beautiful". Skip every tired pickup line on the internet.
        - Three completely different vibes per the assignment below.
        - Each option ~15–25 words — a real sentence, substantive enough to spark a reply.
        - Lowercase. No end-periods. Minimal punctuation overall. Contractions are fine without apostrophes (im, dont, youre, gonna, wanna, idk, ngl).
        - Never start with "hey", "hi", "hello" — go in confident, like the conversation already started.
        - Not corny. Not baby/queen/daddy energy. Not the same lines that get reposted everywhere.

        Theme assignment for this batch (\(seed)):
        \(themesText)

        Output EXACTLY 3 lines separated by ||| on a single line. No numbering, no labels, no markdown, no commentary.
        """

        let user = """
        /no_think

        Give me 3 fresh creative pickup lines following the theme assignment. Random batch \(seed). Output ONLY the three lines separated by |||.
        """

        let trimmed = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        var base = trimmed; while base.hasSuffix("/") { base.removeLast() }
        let full = base + "/chat/completions"
        guard let url = URL(string: full), url.host != nil else { throw AIError.badURL(full) }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 60
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !apiKey.isEmpty { req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization") }
        let body = Request(
            model: model,
            messages: [
                Message(role: "system", content: system),
                Message(role: "user", content: user)
            ],
            max_tokens: 600,
            temperature: 1.05,   // high creativity for variety
            stream: false
        )
        req.httpBody = try JSONEncoder().encode(body)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: req)
        } catch let e as URLError {
            throw AIError.network(e, url)
        } catch {
            throw AIError.network(URLError(.unknown), url)
        }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw AIError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        let parsed = try JSONDecoder().decode(Response.self, from: data)
        let raw = parsed.choices.first?.message.content?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return parseThreeOptions(raw)
    }

    /// Splits the model's output into up to 3 cleaned candidate strings.
    /// Defensively strips Qwen3-style `<think>…</think>` reasoning blocks
    /// and other commentary the model occasionally leaks.
    private static func parseThreeOptions(_ raw: String) -> [String] {
        var stripped = raw
        // Drop any <think>...</think> reasoning blocks (Qwen3, DeepSeek-R1, etc.)
        stripped = stripped.replacingOccurrences(
            of: #"(?is)<think>.*?</think>"#,
            with: "",
            options: .regularExpression
        )
        // Sometimes the close tag is missing — drop everything from <think> to EOF
        stripped = stripped.replacingOccurrences(
            of: #"(?is)<think>.*$"#,
            with: "",
            options: .regularExpression
        )
        // Strip surrounding code fences if the model wrapped its answer
        stripped = stripped.replacingOccurrences(
            of: #"(?s)^```[a-z]*\s*"#, with: "", options: .regularExpression
        )
        stripped = stripped.replacingOccurrences(
            of: #"(?s)```\s*$"#, with: "", options: .regularExpression
        )
        stripped = stripped.trimmingCharacters(in: .whitespacesAndNewlines)

        var parts: [String]
        if stripped.contains("|||") {
            parts = stripped.components(separatedBy: "|||")
        } else {
            parts = stripped.components(separatedBy: .newlines)
        }

        let metaPhrases: [String] = [
            "i need to", "i should", "let me", "first", "step 1", "step 2",
            "analyzing", "thinking", "so i need", "okay so", "let's"
        ]

        let cleaned = parts
            .map { s -> String in
                var t = s.trimmingCharacters(in: .whitespacesAndNewlines)
                t = t.replacingOccurrences(of: #"^\s*[\-\*\•\d\.]+\s*"#,
                                            with: "",
                                            options: .regularExpression)
                if (t.hasPrefix("\"") && t.hasSuffix("\"")) || (t.hasPrefix("'") && t.hasSuffix("'")) {
                    t = String(t.dropFirst().dropLast())
                }
                return t
            }
            .filter { line in
                guard !line.isEmpty else { return false }
                let lower = line.lowercased()
                // Filter out lines that look like reasoning/commentary
                if metaPhrases.contains(where: { lower.hasPrefix($0) }) { return false }
                if line.count > 280 { return false }   // way too long = likely reasoning
                return true
            }
        return Array(cleaned.prefix(3))
    }
}
