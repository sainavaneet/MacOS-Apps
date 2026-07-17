import SwiftUI
import AppKit

/// Toolbar button + dropdown popover for AI reply suggestions.
///
/// Renders as a single small "✨ Replies ▾" pill in the WebToolbar. Click
/// opens a native SwiftUI `.popover` anchored below the button containing
/// three vertically-stacked numbered options at readable size. Click a row
/// to insert it into the chat input.
struct ReplyMenuButton: View {
    let serviceID: String

    @EnvironmentObject private var ai: AIState
    @EnvironmentObject private var store: WebControllerStore

    @State private var open = false
    @State private var suggestions: [String] = []
    @State private var loading = false
    @State private var lastError: String?
    @State private var hasFetchedThisOpen = false

    static let supported: Set<String> = [
        "whatsapp", "telegram", "messenger", "instagram", "tinder"
    ]
    static func isSupported(_ serviceID: String) -> Bool { supported.contains(serviceID) }

    var body: some View {
        if Self.isSupported(serviceID) {
            Button {
                open.toggle()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.purple)
                    Text("Replies")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.75))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Color.white.opacity(0.45))
                        .rotationEffect(.degrees(open ? 180 : 0))
                        .animation(.easeOut(duration: 0.15), value: open)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(
                    Capsule().fill(Color.white.opacity(open ? 0.10 : 0.05))
                )
                .overlay(
                    Capsule().strokeBorder(
                        open ? Color.purple.opacity(0.5) : Color.white.opacity(0.08),
                        lineWidth: 0.5
                    )
                )
            }
            .buttonStyle(.plain)
            .help("AI reply suggestions")
            .popover(isPresented: $open, arrowEdge: .bottom) {
                ReplyMenuPopover(
                    suggestions: $suggestions,
                    loading: $loading,
                    lastError: $lastError,
                    serviceID: serviceID,
                    onUse: { text in
                        Task { await applyAndClose(text: text) }
                    },
                    onRefresh: { Task { await fetch() } },
                    onScreenshot: { Task { await fetchFromScreenshot() } },
                    onPickupLines: { Task { await fetchPickupLines() } },
                    onClose: { open = false }
                )
                .task {
                    if !hasFetchedThisOpen {
                        hasFetchedThisOpen = true
                        if suggestions.isEmpty { await fetch() }
                    }
                }
                .onDisappear { hasFetchedThisOpen = false }
            }
        }
    }

    // MARK: - Logic

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
        let context = await controller.readConversationContext()
        do {
            let replies: [String]
            if context.turns.isEmpty {
                let pageText = await controller.readPageText()
                if pageText.isEmpty {
                    replies = []
                } else {
                    replies = try await AIClient.suggestRepliesFromPageText(
                        endpoint: ai.endpoint,
                        model: ai.model,
                        apiKey: ai.apiKey,
                        pageText: pageText,
                        theirName: context.partner
                    )
                }
            } else {
                replies = try await AIClient.suggestReplies(
                    endpoint: ai.endpoint,
                    model: ai.model,
                    apiKey: ai.apiKey,
                    turns: context.turns,
                    theirName: context.partner
                )
            }
            suggestions = replies
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
        let cropL: CGFloat = serviceID == "tinder" ? 0.22 : 0
        let cropR: CGFloat = serviceID == "tinder" ? 0.22 : 0
        guard let jpeg = await controller.captureScreenshotJPEG(
            cropLeftPercent: cropL, cropRightPercent: cropR
        ) else { lastError = "Couldn't capture screenshot"; loading = false; return }
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

    private func fetchPickupLines() async {
        loading = true
        lastError = nil
        do {
            suggestions = try await AIClient.randomPickupLines(
                endpoint: ai.endpoint, model: ai.model, apiKey: ai.apiKey
            )
        } catch {
            lastError = error.localizedDescription
            suggestions = []
        }
        loading = false
    }

    private func applyAndClose(text: String) async {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        open = false
        try? await Task.sleep(nanoseconds: 220_000_000)
        if let controller = store.existingController(for: serviceID) {
            _ = await controller.writeActiveInputText(text)
        }
        suggestions.removeAll { $0 == text }
    }
}

// MARK: - Popover content

private struct ReplyMenuPopover: View {
    @Binding var suggestions: [String]
    @Binding var loading: Bool
    @Binding var lastError: String?
    let serviceID: String
    let onUse: (String) -> Void
    let onRefresh: () -> Void
    let onScreenshot: () -> Void
    let onPickupLines: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.15)
            content
            Divider().opacity(0.15)
            footer
        }
        .frame(width: 460)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.purple)
            Text("AI Replies")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private var content: some View {
        if loading {
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text("thinking…").font(.system(size: 13)).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 16)
        } else if let err = lastError {
            Text(err)
                .font(.system(size: 12))
                .foregroundStyle(.red)
                .lineLimit(4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
        } else if suggestions.isEmpty {
            Button(action: onRefresh) {
                Text("no suggestions yet — click refresh below")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
        } else {
            VStack(spacing: 0) {
                ForEach(Array(suggestions.enumerated()), id: \.offset) { idx, s in
                    if idx > 0 {
                        Rectangle().fill(Color.white.opacity(0.05)).frame(height: 0.5)
                            .padding(.leading, 42)
                    }
                    SuggestionRow(number: idx + 1, text: s) { onUse(s) }
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 6) {
            footerButton(symbol: "arrow.clockwise", label: "Refresh", action: onRefresh)
            footerButton(symbol: "camera.viewfinder", label: "Screenshot", action: onScreenshot)
            footerButton(symbol: "flame.fill", label: "Pickup Lines", action: onPickupLines)
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    private func footerButton(symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: 10, weight: .semibold))
                Text(label).font(.system(size: 11))
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.white.opacity(0.04))
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Row

private struct SuggestionRow: View {
    let number: Int
    let text: String
    let onTap: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 12) {
                Text("\(number)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(hovering ? .white : Color.purple)
                    .frame(width: 20, height: 20)
                    .background(
                        Circle().fill(hovering ? Color.purple : Color.purple.opacity(0.18))
                    )

                Text(text)
                    .font(.system(size: 13))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                Color.purple.opacity(hovering ? 0.10 : 0)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.1), value: hovering)
    }
}
