import SwiftUI

@MainActor
final class AIState: ObservableObject {
    @AppStorage("ai.endpoint") var endpoint: String = "http://100.64.0.3:8000/v1"
    @AppStorage("ai.model")    var model:    String = "Qwen/Qwen3.6-35B-A3B-FP8"
    @AppStorage("ai.apiKey")   var apiKey:   String = "not-needed"

    @Published var draft: String = ""
    @Published var result: String = ""
    @Published var lastStyle: RewriteStyle?
    @Published var isWorking = false
    @Published var lastError: String?
}

enum RewriteStyle: String, CaseIterable, Identifiable {
    case improve, funny, formal, shorter, flirty, casual

    var id: String { rawValue }

    var label: String {
        switch self {
        case .improve: return "Improve"
        case .funny:   return "Funnier"
        case .formal:  return "Formal"
        case .shorter: return "Shorter"
        case .flirty:  return "Flirty"
        case .casual:  return "Casual"
        }
    }

    var icon: String {
        switch self {
        case .improve: return "wand.and.stars"
        case .funny:   return "face.smiling"
        case .formal:  return "person.crop.circle.badge.checkmark"
        case .shorter: return "scissors"
        case .flirty:  return "flame"
        case .casual:  return "bubble.left.and.bubble.right"
        }
    }

    var systemPrompt: String {
        // Universal texting voice — applies to every style except .formal.
        let baseVoice = """
        ROLE: You are rephrasing a draft message that the user is about to SEND to someone else.

        CRITICAL — what your job is and isn't:
        - The user is the SENDER. The input is THEIR own draft — the text THEY want to send.
        - Your output REPLACES their draft. You are rewording the SAME message.
        - DO NOT reply to the draft. DO NOT respond to it. The input is NOT a message sent to you.
        - DO NOT change the speaker, the meaning, or who's talking to whom.

        Examples (input → correct output):
        - "damn you look cute as fuck" → "damn u look cute af" (rephrased, still complimenting them)
        - "wanna grab dinner tomorrow?" → "dinner tmrw?" (same invitation, shorter)
        - "I'll be there in 5 minutes" → "be there in 5" (same statement, casual)

        WRONG examples (these are REPLIES, never do this):
        - "damn you look cute" → "thanks!" ❌
        - "damn you look cute" → "stop it ur making me blush" ❌
        - "wanna grab dinner?" → "sure!" ❌

        Voice & format rules (apply unless the style explicitly overrides them):
        - Write like a real person texting a friend — natural, conversational, low-effort
        - Lowercase everything (except proper nouns and "i" stays lowercase too)
        - DO NOT end sentences with a period
        - Use minimal punctuation overall — drop commas where possible
        - Use contractions (im, dont, youre, gonna, wanna, idk, ngl, etc.) where they sound natural
        - Short. Sound like a text message, not a paragraph
        - No quotes around the output. No prefix, no preamble, no commentary, no markdown
        - One message. Don't add greetings if the draft didn't have one
        - Keep the original meaning and intent. You are REPHRASING, not REPLYING.
        """

        let styleNote: String
        switch self {
        case .improve:
            styleNote = "Style: Improve the draft — fix typos and awkward phrasing, but keep the same energy and length. Don't make it longer or fancier."
        case .funny:
            styleNote = "Style: Add a light, dry, playful spin. Not corny, not jokey, just a bit of personality. Keep it short."
        case .formal:
            // The one style that overrides the lowercase / no-punctuation rule
            styleNote = """
            STYLE OVERRIDE: Be polite, professional and clear. Use proper capitalization and punctuation. Drop slang and abbreviations. Output ONLY the message — no quotes or commentary.
            """
        case .shorter:
            styleNote = "Style: Cut to the essential point. Aim ~50% shorter. Still casual texting tone, lowercase, no periods."
        case .flirty:
            styleNote = "Style: Warm, flirty, confident, low-effort vibe — like someone who's interested but chill. Not cringe, not over the top. Keep it short and a little playful."
        case .casual:
            styleNote = "Style: Just make it sound more like normal texting — chill, lowercase, contractions, no formality."
        }

        if case .formal = self { return styleNote }
        return baseVoice + "\n\n" + styleNote
    }
}
