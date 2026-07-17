import SwiftUI
import AppKit

/// Compact AI reply suggestions that live INLINE in the main toolbar row.
/// Three small numbered chips with truncated text + tooltip-on-hover for the
/// full sentence. No extra bar, no separate panel.
///
/// Layout when expanded:
///   ┌──────────────────────────────────────────────────────────┐
///   │ ① option one…   ② option two…   ③ option three…  ⟳ 📷 × │
///   └──────────────────────────────────────────────────────────┘
/// When dismissed → collapses to a single ✨ pill in the same spot.
struct ReplyChipsInline: View {
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
                } else {
                    expandedBar
                }
            }
        }
        .task(id: serviceID) {
            guard Self.isSupported(serviceID) else { return }
            hidden = false
            await fetch()
        }
        .animation(.easeOut(duration: 0.2), value: hidden)
    }

    private var expandedBar: some View {
        HStack(alignment: .center, spacing: 6) {
            content
                .frame(maxWidth: .infinity, alignment: .leading)
            actions
        }
    }

    @ViewBuilder
    private var content: some View {
        if loading {
            HStack(spacing: 6) {
                ProgressView().controlSize(.mini).scaleEffect(0.65)
                Text("thinking")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.white.opacity(0.45))
            }
        } else if let err = lastError {
            Text(err)
                .font(.system(size: 11))
                .foregroundStyle(Color.red.opacity(0.75))
                .lineLimit(2)
                .truncationMode(.tail)
        } else if suggestions.isEmpty {
            Button {
                Task { await fetch() }
            } label: {
                Text("no suggestions — retry")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.white.opacity(0.32))
            }
            .buttonStyle(.plain)
        } else {
            // Vertical stack of suggestion chips — toolbar grows in height
            // to fit. Each chip is full-width within the available middle
            // column space.
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(suggestions.enumerated()), id: \.offset) { idx, s in
                    NumberedChip(index: idx + 1, text: s) { use(s) }
                }
            }
        }
    }

    /// Actions stack vertically alongside the chip column to keep the row
    /// narrow horizontally.
    private var actions: some View {
        VStack(spacing: 3) {
            tiny(symbol: "arrow.clockwise", help: "Refresh") { Task { await fetch() } }
            tiny(symbol: "camera.viewfinder", help: "Refresh from screenshot") { Task { await fetchFromScreenshot() } }
            tiny(symbol: "xmark", help: "Hide") {
                withAnimation { hidden = true }
            }
        }
    }

    private func tiny(symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.4))
                .frame(width: 18, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private var reopenPill: some View {
        Button {
            withAnimation { hidden = false }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "sparkles")
                    .font(.system(size: 10, weight: .semibold))
                if !suggestions.isEmpty {
                    Text("\(suggestions.count)")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(Color.purple.opacity(0.55))
            )
            .overlay(
                Capsule().strokeBorder(Color.white.opacity(0.15), lineWidth: 0.5)
            )
            .accentGlow(.purple, radius: 6, intensity: 0.4)
        }
        .buttonStyle(.plain)
        .help("Show AI replies")
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
        guard let controller = controller else { suggestions = []; loading = false; return }

        let turns = await controller.readConversationContext()
        guard !turns.isEmpty else { suggestions = []; loading = false; return }
        do {
            suggestions = try await AIClient.suggestReplies(
                endpoint: ai.endpoint, model: ai.model, apiKey: ai.apiKey, turns: turns
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
        guard let controller = store.existingController(for: serviceID) else { loading = false; return }
        let cropLeft: CGFloat
        let cropRight: CGFloat
        switch serviceID {
        case "tinder": cropLeft = 0.22; cropRight = 0.22
        default:       cropLeft = 0;    cropRight = 0
        }
        guard let jpeg = await controller.captureScreenshotJPEG(
            cropLeftPercent: cropLeft, cropRightPercent: cropRight
        ) else {
            lastError = "Couldn't capture screenshot"; loading = false; return
        }
        do {
            suggestions = try await AIClient.suggestRepliesFromImage(
                endpoint: ai.endpoint, model: ai.model, apiKey: ai.apiKey, imageJPEG: jpeg
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

// MARK: - Numbered chip with truncation + tooltip

private struct NumberedChip: View {
    let index: Int
    let text: String
    let onTap: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 5) {
                Text("\(index)")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(hovering ? .white : Color.purple)
                    .frame(width: 14, height: 14)
                    .background(
                        Circle().fill(hovering ? Color.purple : Color.purple.opacity(0.20))
                    )
                Text(text)
                    .font(.system(size: 11, weight: hovering ? .medium : .regular))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(hovering ? .white : Color.white.opacity(0.72))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule().fill(hovering ? Color.purple.opacity(0.32) : Color.white.opacity(0.05))
            )
            .overlay(
                Capsule().strokeBorder(
                    hovering ? Color.purple.opacity(0.5) : Color.white.opacity(0.08),
                    lineWidth: 0.5
                )
            )
            .frame(maxWidth: 380)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .help(text)
    }
}
