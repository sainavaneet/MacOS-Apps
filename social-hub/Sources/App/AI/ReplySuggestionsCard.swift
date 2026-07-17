import SwiftUI
import AppKit

/// Floating centered suggestion card — sits at the top-center of the chat
/// view, just below the toolbar. Three numbered options stacked vertically,
/// readable size, translucent material so chat content shows through.
struct ReplySuggestionsCard: View {
    let serviceID: String

    @EnvironmentObject private var ai: AIState
    @EnvironmentObject private var store: WebControllerStore

    @State private var suggestions: [String] = []
    @State private var loading = false
    @State private var hidden = false
    @State private var lastError: String?

    static let supported: Set<String> = [
        "whatsapp", "telegram", "messenger", "instagram", "tinder"
    ]
    static func isSupported(_ serviceID: String) -> Bool {
        supported.contains(serviceID)
    }

    var body: some View {
        Group {
            if Self.isSupported(serviceID) {
                if hidden {
                    reopenPill
                        .transition(.opacity.combined(with: .scale(scale: 0.85)))
                } else {
                    card
                        .transition(.opacity.combined(with: .offset(y: -8)))
                }
            }
        }
        .task(id: serviceID) {
            guard Self.isSupported(serviceID) else { return }
            hidden = false
            await fetch()
        }
        .animation(.easeOut(duration: 0.22), value: hidden)
    }

    /// Tiny floating sparkles button shown when the card is dismissed —
    /// click to bring the card back.
    private var reopenPill: some View {
        Button {
            withAnimation { hidden = false }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "sparkles")
                    .font(.system(size: 11, weight: .semibold))
                if !suggestions.isEmpty {
                    Text("\(suggestions.count)")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                Capsule()
                    .fill(Color.purple.opacity(0.55))
            )
            .overlay(
                Capsule()
                    .strokeBorder(Color.white.opacity(0.15), lineWidth: 0.5)
            )
            .shadow(color: Color.purple.opacity(0.45), radius: 10, y: 2)
        }
        .buttonStyle(.plain)
        .help("Show AI replies")
        .padding(.top, 6)
    }

    private var card: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.12)
            content
        }
        .frame(maxWidth: 560)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.black.opacity(0.25))
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(0.35), radius: 24, y: 8)
        .shadow(color: Color.purple.opacity(0.20), radius: 30, y: 0)
        .padding(.top, 4)
    }

    // MARK: - Header (label + action icons)

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.purple)
            Text("AI Replies")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .tracking(0.5)
                .foregroundStyle(Color.white.opacity(0.65))
            Spacer()
            HStack(spacing: 4) {
                miniAction(symbol: "arrow.clockwise", help: "Refresh (read DOM)") {
                    Task { await fetch() }
                }
                miniAction(symbol: "camera.viewfinder", help: "Refresh from screenshot") {
                    Task { await fetchFromScreenshot() }
                }
                miniAction(symbol: "xmark", help: "Hide") {
                    withAnimation { hidden = true }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 9)
        .padding(.bottom, 8)
    }

    private func miniAction(symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.5))
                .frame(width: 22, height: 20)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Color.white.opacity(0.04))
                )
        }
        .buttonStyle(.plain)
        .help(help)
    }

    // MARK: - Content (3 stacked suggestion rows)

    @ViewBuilder
    private var content: some View {
        if loading {
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text("thinking…")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.white.opacity(0.55))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        } else if let err = lastError {
            Text(err)
                .font(.system(size: 12))
                .foregroundStyle(Color.red.opacity(0.85))
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
        } else if suggestions.isEmpty {
            Button {
                Task { await fetch() }
            } label: {
                HStack {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11))
                    Text("no suggestions yet — click to retry")
                        .font(.system(size: 12))
                }
                .foregroundStyle(Color.white.opacity(0.4))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else {
            VStack(spacing: 0) {
                ForEach(Array(suggestions.enumerated()), id: \.offset) { idx, s in
                    if idx > 0 {
                        Rectangle()
                            .fill(Color.white.opacity(0.06))
                            .frame(height: 0.5)
                            .padding(.leading, 44)
                    }
                    SuggestionRow(number: idx + 1, text: s) { use(s) }
                }
            }
        }
    }

    // MARK: - Fetch / use

    private func fetch() async {
        loading = true
        lastError = nil

        var controller = store.existingController(for: serviceID)
        var tries = 0
        while controller == nil && tries < 5 {
            try? await Task.sleep(nanoseconds: 400_000_000)
            controller = store.existingController(for: serviceID)
            tries += 1
        }
        guard let controller = controller else {
            suggestions = []; loading = false; return
        }

        let turns = await controller.readConversationContext()
        guard !turns.isEmpty else {
            suggestions = []; loading = false; return
        }
        do {
            suggestions = try await AIClient.suggestReplies(
                endpoint: ai.endpoint,
                model: ai.model,
                apiKey: ai.apiKey,
                turns: turns
            )
        } catch {
            lastError = error.localizedDescription
            suggestions = []
        }
        loading = false
    }

    private func fetchFromScreenshot() async {
        loading = true
        lastError = nil

        guard let controller = store.existingController(for: serviceID) else {
            loading = false; return
        }
        let cropLeft: CGFloat
        let cropRight: CGFloat
        switch serviceID {
        case "tinder": cropLeft = 0.22; cropRight = 0.22
        default:       cropLeft = 0;    cropRight = 0
        }
        guard let jpeg = await controller.captureScreenshotJPEG(
            cropLeftPercent: cropLeft,
            cropRightPercent: cropRight
        ) else {
            lastError = "Couldn't capture screenshot"
            loading = false
            return
        }
        do {
            suggestions = try await AIClient.suggestRepliesFromImage(
                endpoint: ai.endpoint,
                model: ai.model,
                apiKey: ai.apiKey,
                imageJPEG: jpeg
            )
        } catch {
            lastError = error.localizedDescription
            suggestions = []
        }
        loading = false
    }

    private func use(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        Task {
            if let controller = store.existingController(for: serviceID) {
                _ = await controller.writeActiveInputText(text)
            }
            suggestions.removeAll { $0 == text }
        }
    }
}

// MARK: - Individual numbered row

private struct SuggestionRow: View {
    let number: Int
    let text: String
    let onTap: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 12) {
                // Number badge
                Text("\(number)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(hovering ? .white : Color.purple)
                    .frame(width: 22, height: 22)
                    .background(
                        Circle()
                            .fill(hovering ? Color.purple : Color.purple.opacity(0.16))
                    )

                // The suggestion text — bigger and readable
                Text(text)
                    .font(.system(size: 14, weight: hovering ? .medium : .regular))
                    .foregroundStyle(hovering
                                     ? Color.white
                                     : Color.white.opacity(0.78))
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(
                Color.purple.opacity(hovering ? 0.10 : 0)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }
}
